## Async event handling
##
## This module provides asynchronous event handling for keyboard input,
## mouse events, and other terminal events using either Chronos or std/asyncdispatch.

import std/[posix, options, strutils]

import async_backend, async_io
import ../core/[events, mouse_logic, utf8_utils, key_logic]

type
  AsyncEventError* = object of CatchableError

  AsyncEventStream* = ref object
    running*: bool
    eventCallback*: proc(event: Event): Future[bool] {.async.}

# Define SIGWINCH if not available
when not declared(SIGWINCH):
  const SIGWINCH = 28

# Global state for async event handling
var resizeDetected* = false

# Signal handler for SIGWINCH
proc sigwinchHandler(sig: cint) {.noconv.} =
  resizeDetected = true

# Initialize async event system
proc initAsyncEventSystem*() =
  ## Initialize async event handling system
  try:
    initAsyncIO()
    signal(SIGWINCH, sigwinchHandler)
  except CatchableError as e:
    raise
      newException(AsyncEventError, "Failed to initialize async event system: " & e.msg)

proc cleanupAsyncEventSystem*() =
  ## Cleanup async event system
  try:
    cleanupAsyncIO()
  except CatchableError:
    discard # Ignore cleanup errors

# Async mouse event parsing (using shared logic from mouse_logic module)

proc toEvent(data: mouse_logic.MouseEventData): Event =
  ## Convert MouseEventData to Event
  Event(
    kind: EventKind.Mouse,
    mouse: MouseEvent(
      kind: data.kind,
      button: data.button,
      x: data.x,
      y: data.y,
      modifiers: data.modifiers,
    ),
  )

proc parseMouseEventX10(): Future[Event] {.async.} =
  ## Parse X10 mouse format: ESC[Mbxy
  ## where b is button byte, x,y are coordinate bytes
  ##
  ## This async function handles I/O and delegates parsing to shared mouse_logic module
  var data: array[3, char]

  # Read 3 bytes for X10 format (async I/O)
  for i in 0 .. 2:
    let ch = await readCharAsync()
    if ch == '\0':
      return Event(kind: Unknown)
    data[i] = ch

  # Use shared parsing logic - no duplication with sync version!
  return parseMouseDataX10(data).toEvent()

proc parseMouseEventSGR(): Future[Event] {.async.} =
  ## Parse SGR mouse format: ESC[<button;x;y;M/m
  ## M for press, m for release
  ##
  ## This async function handles I/O and delegates parsing to shared mouse_logic module
  var buffer: string
  var ch: char
  var readCount = 0
  const maxReadCount = 20 # Prevent infinite loops

  # Read until we get M or m, with safety limits (async I/O)
  while readCount < maxReadCount:
    ch = await readCharAsync()
    readCount.inc()
    if ch == '\0':
      return Event(kind: Unknown)
    if ch == 'M' or ch == 'm':
      break
    buffer.add(ch)

  # If we didn't find a terminator, return unknown event
  if readCount >= maxReadCount or (ch != 'M' and ch != 'm'):
    return Event(kind: Unknown)

  # Parse the SGR format: button;x;y
  let parts = buffer.split(';')
  if parts.len >= 3:
    try:
      let buttonCode = parseInt(parts[0])
      let x = parseInt(parts[1]) - 1 # SGR uses 1-based coordinates
      let y = parseInt(parts[2]) - 1
      let isRelease = (ch == 'm')

      # Use shared parsing logic - no duplication with sync version!
      return parseMouseDataSGR(buttonCode, x, y, isRelease).toEvent()
    except ValueError:
      return Event(kind: Unknown)

  return Event(kind: Unknown)

# UTF-8 helper functions (using shared logic from utf8_utils module)
proc readUtf8CharAsync(firstByte: byte): Future[string] {.async.} =
  ## Read a complete UTF-8 character asynchronously
  ## Uses shared UTF-8 validation logic from utf8_utils
  let byteLen = utf8ByteLength(firstByte)
  if byteLen == 0:
    return ""

  if byteLen == 1:
    return $char(firstByte)

  # Read continuation bytes asynchronously
  var continuationBytes: seq[byte] = @[]
  for i in 1 ..< byteLen:
    let nextByte = await readCharAsync()

    if nextByte == '\0':
      # Failed to read, return what we have
      if continuationBytes.len > 0:
        return buildUtf8String(firstByte, continuationBytes)
      else:
        return $char(firstByte)

    # Validate using shared logic
    if not isUtf8ContinuationByte(nextByte.byte):
      # Invalid, return what we have
      if continuationBytes.len > 0:
        return buildUtf8String(firstByte, continuationBytes)
      else:
        return $char(firstByte)

    continuationBytes.add(nextByte.byte)

  return buildUtf8String(firstByte, continuationBytes)

# Async key reading with escape sequence support
proc readKeyAsync*(): Future[Event] {.async.} =
  ## Read a key event asynchronously using non-blocking I/O
  try:
    # Use non-blocking AsyncFD read instead of blocking POSIX read
    let ch = await readCharAsync()

    if ch == '\0':
      return Event(kind: Unknown)

    # Handle Ctrl+C quit first
    if ch == '\x03':
      return Event(kind: Quit)

    # Handle Ctrl-letter combinations using shared logic
    let ctrlLetterResult = mapCtrlLetterKey(ch)
    if ctrlLetterResult.isCtrlKey:
      return Event(kind: Key, key: ctrlLetterResult.keyEvent)

    # Handle Ctrl-number and special control characters using shared logic
    let ctrlNumberResult = mapCtrlNumberKey(ch)
    if ctrlNumberResult.isCtrlKey:
      return Event(kind: Key, key: ctrlNumberResult.keyEvent)

    # Use shared basic key mapping for common keys
    let basicKey = mapBasicKey(ch)
    if basicKey.code in {Enter, Tab, Space, Backspace}:
      return Event(kind: Key, key: basicKey)

    # Handle escape sequences
    if ch == '\x1b':
      # Check if more data is available with 20ms timeout
      let hasMoreData = await hasInputAsync(20)

      if not hasMoreData:
        # No more data after timeout - standalone ESC key
        return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))

      # Try to read escape sequence
      let next = await readCharAsync()

      if next == '[':
        let final = await readCharAsync()

        if final != '\0':
          # Try arrow keys first
          let arrowKey = mapArrowKey(final)
          if arrowKey.code != Escape:
            return Event(kind: Key, key: arrowKey)

          # Try navigation keys
          let navKey = mapNavigationKey(final)
          if navKey.code != Escape:
            return Event(kind: Key, key: navKey)

          # Handle mouse events and numeric sequences
          case final
          of 'M': # Mouse event (X10 format)
            return await parseMouseEventX10()
          of '<': # SGR mouse format
            return await parseMouseEventSGR()
          of '1' .. '6':
            # Could be function key or special key with modifiers
            let nextChar = await readCharAsync()

            if nextChar != '\0':
              if nextChar == '~':
                # Special keys with numeric codes - use shared logic
                let numKey = mapNumericKeyCode(final)
                return Event(kind: Key, key: numKey)
              else:
                # Complex escape sequence - return escape for now
                return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))
            else:
              return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))
          else:
            return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))
        else:
          return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))
      else:
        return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))

    # For regular characters, read complete UTF-8 character asynchronously
    let utf8Char = await readUtf8CharAsync(ch.byte)
    if utf8Char.len > 0:
      return Event(kind: Key, key: KeyEvent(code: Char, char: utf8Char))
    else:
      # Invalid UTF-8, treat as single byte
      return Event(kind: Key, key: KeyEvent(code: Char, char: $ch))
  except Exception as e:
    raise newException(AsyncEventError, "Async key reading failed: " & e.msg)
  except CatchableError:
    return Event(kind: Unknown)

# Non-blocking async event reading
proc pollKeyAsync*(): Future[Option[Event]] {.async.} =
  ## Poll for a key event asynchronously (non-blocking)
  try:
    # Check if input is available first
    let hasInput = await hasInputAsync(1)
    if not hasInput:
      return none(Event)

    # Input is available, read the event
    let event = await readKeyAsync()
    if event.kind != Unknown:
      return some(event)
    else:
      return none(Event)
  except Exception as e:
    raise newException(AsyncEventError, "Async key polling failed: " & e.msg)
  except CatchableError:
    return none(Event)

# Check for resize event
proc checkResizeAsync*(): Future[Option[Event]] {.async.} =
  ## Check if a resize event occurred asynchronously
  if resizeDetected:
    resizeDetected = false
    return some(Event(kind: Resize))
  return none(Event)

# Event polling with timeout
proc pollEventsAsync*(timeoutMs: int): Future[bool] {.async.} =
  ## Poll for available events asynchronously with a timeout
  ## Returns true if events are available, false if timeout occurred
  try:
    return await hasInputAsync(timeoutMs)
  except Exception as e:
    raise newException(AsyncEventError, "Async event polling failed: " & e.msg)
  except CatchableError:
    return false

# Advanced async event waiting
proc waitForKeyAsync*(): Future[Event] {.async.} =
  ## Wait for a key press asynchronously (blocking until event)
  while true:
    try:
      let event = await readKeyAsync()
      if event.kind != Unknown:
        return event
    except Exception as e:
      raise newException(AsyncEventError, "Async key waiting failed: " & e.msg)
    except CatchableError:
      discard

    # Small async sleep to prevent busy waiting
    await sleepMs(10)

proc waitForAnyKeyAsync*(): Future[bool] {.async.} =
  ## Wait for any key press asynchronously, return true if not quit
  let event = await waitForKeyAsync()
  return event.kind != Quit

# Multiple event source handling
proc waitForMultipleEventsAsync*(): Future[Event] {.async.} =
  ## Wait for events from multiple sources (keyboard, resize, etc.)
  while true:
    # Check resize first (highest priority)
    let resizeEventOpt = await checkResizeAsync()
    if resizeEventOpt.isSome():
      return resizeEventOpt.get()

    # Then check for keyboard events
    let keyEventOpt = await pollKeyAsync()
    if keyEventOpt.isSome():
      return keyEventOpt.get()

    # Small sleep to prevent busy waiting
    await sleepMs(16) # ~60 FPS

# Async event stream
proc newAsyncEventStream*(
    callback: proc(event: Event): Future[bool] {.async.}
): AsyncEventStream =
  ## Create a new async event stream with callback
  result = AsyncEventStream(running: false, eventCallback: callback)

proc startAsync*(stream: AsyncEventStream) {.async.} =
  ## Start the async event stream
  stream.running = true

  while stream.running:
    try:
      let event = await waitForMultipleEventsAsync()

      if stream.eventCallback != nil:
        let shouldContinue = await stream.eventCallback(event)
        if not shouldContinue:
          stream.running = false
    except CatchableError:
      # Any errors should stop the stream for now
      stream.running = false

proc stopAsync*(stream: AsyncEventStream) {.async.} =
  ## Stop the async event stream
  stream.running = false
