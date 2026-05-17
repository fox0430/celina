## Async event handling
##
## This module provides asynchronous event handling for keyboard input,
## mouse events, and other terminal events using either Chronos or std/asyncdispatch.

import std/[options, strutils]

import async_backend, async_io
import
  ../core/[
    events, mouse_logic, utf8_utils, key_logic, escape_sequence_logic, terminal,
    geometry,
  ]

type
  AsyncEventError* = object of CatchableError

  AsyncEventStream* = ref object
    running*: bool
    eventCallback*: proc(event: Event): Future[bool] {.async.}
    lastWidth: int ## Track last seen terminal width
    lastHeight: int ## Track last seen terminal height

# Initialize async event system
proc initAsyncEventSystem*() =
  ## Initialize async event handling system
  try:
    initAsyncIO()
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

  # Read until we get M or m, with safety limits (async I/O)
  while readCount < MaxSGRMouseReadBytes:
    ch = await readCharAsync()
    readCount.inc()
    if ch == '\0':
      return Event(kind: Unknown)
    if ch == 'M' or ch == 'm':
      break
    buffer.add(ch)

  # If we didn't find a terminator, return unknown event
  if readCount >= MaxSGRMouseReadBytes or (ch != 'M' and ch != 'm'):
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
#
# This async version mirrors `assembleUtf8Char`'s logic but cannot reuse the
# pure helper directly because each continuation-byte read must `await`. The
# semantics — including the Unicode §3.9 leftover byte for invalid
# continuations — are kept identical; see `assembleUtf8Char` for the contract.
proc readUtf8CharAsync(firstByte: byte): Future[Utf8AssemblyResult] {.async.} =
  let byteLen = utf8ByteLength(firstByte)
  if byteLen == 0:
    return Utf8AssemblyResult(text: "", leftover: none(byte))

  if byteLen == 1:
    return Utf8AssemblyResult(text: $char(firstByte), leftover: none(byte))

  var continuationBytes: seq[byte] = @[]
  for i in 1 ..< byteLen:
    let nextByte = await readCharAsync()

    if nextByte == '\0':
      # Truncated: nothing to push back.
      return Utf8AssemblyResult(text: Utf8ReplacementChar, leftover: none(byte))

    if not isUtf8ContinuationByte(nextByte.byte):
      # Invalid continuation: surface the byte so readKeyAsync can re-inject
      # it as the first byte of the next event.
      return
        Utf8AssemblyResult(text: Utf8ReplacementChar, leftover: some(nextByte.byte))

    continuationBytes.add(nextByte.byte)

  return Utf8AssemblyResult(
    text: buildUtf8String(firstByte, continuationBytes), leftover: none(byte)
  )

# Async escape sequence parsing
# Uses the shared `parseEscapeSequenceUnified` template from core/events.
# Each reader expression is `await`-wrapped so the template's repeated use
# of the parameter becomes a fresh async byte read at each occurrence.

proc readByteTupleAsync(): Future[tuple[success: bool, ch: char]] {.async.} =
  ## Async adapter that exposes readCharAsync() with the same shape the
  ## unified routing template expects (sentinel '\0' becomes success=false).
  let ch = await readCharAsync()
  return (success: ch != '\0', ch: ch)

proc readPasteContentAsync(): Future[string] {.async.} =
  ## Read all content until paste end sequence ESC[201~ (async mode).
  ## Uses the shared paste-end state machine from escape_sequence_logic;
  ## differs from the sync versions only in how each byte is awaited.
  var resultStr = ""
  var state = PesNone
  var pending = ""

  while true:
    # Check for data with reasonable timeout
    let hasData = await hasInputAsync(1000) # 1 second timeout
    if not hasData:
      resultStr.add(pending)
      return resultStr

    let ch = await readCharAsync()
    if ch == '\0':
      resultStr.add(pending)
      return resultStr

    if stepPasteEnd(state, pending, ch, resultStr):
      return resultStr

# Async key reading with escape sequence support
proc readKeyAsync*(): Future[Event] {.async.} =
  ## Read a key event asynchronously using non-blocking I/O
  try:
    let ch = await readCharAsync()

    if ch == '\0':
      return Event(kind: Unknown)

    # Handle Ctrl+C (quit signal)
    if ch == '\x03':
      return Event(kind: Quit)

    # Handle Ctrl-letter combinations
    let ctrlLetterResult = mapCtrlLetterKey(ch)
    if ctrlLetterResult.isCtrlKey:
      return Event(kind: Key, key: ctrlLetterResult.keyEvent)

    # Handle Ctrl-number combinations
    let ctrlNumberResult = mapCtrlNumberKey(ch)
    if ctrlNumberResult.isCtrlKey:
      return Event(kind: Key, key: ctrlNumberResult.keyEvent)

    # Handle basic keys (Enter, Tab, Space, Backspace)
    let basicKey = mapBasicKey(ch)
    if basicKey.code in {Enter, Tab, Space, Backspace}:
      return Event(kind: Key, key: basicKey)

    # Handle escape sequences via the unified routing template.
    # The 20ms post-ESC timeout check distinguishes standalone ESC from a
    # sequence start; if no follow-up byte arrives, return a bare ESC.
    if ch == '\x1b':
      let hasMoreData = await hasInputAsync(20)
      if not hasMoreData:
        return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))
      return parseEscapeSequenceUnified(
        await readByteTupleAsync(),
        await readPasteContentAsync(),
        await parseMouseEventX10(),
        await parseMouseEventSGR(),
      )

    # Handle regular UTF-8 characters
    let assembly = await readUtf8CharAsync(ch.byte)
    if assembly.leftover.isSome:
      # Resync byte: stash for the next readCharAsync to pick up as the
      # first byte of the next event (Unicode §3.9 best practice).
      setPendingByteAsync(assembly.leftover.get)
    if assembly.text.len > 0:
      return Event(kind: Key, key: KeyEvent(code: Char, char: assembly.text))
    else:
      # Invalid UTF-8 start byte — emit U+FFFD (KeyEvent.char invariant).
      return Event(kind: Key, key: KeyEvent(code: Char, char: Utf8ReplacementChar))
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

# Async event stream
proc newAsyncEventStream*(
    callback: proc(event: Event): Future[bool] {.async.}
): AsyncEventStream =
  ## Create a new async event stream with callback
  let termSize = getTerminalSizeOrDefault()
  return AsyncEventStream(
    running: false,
    eventCallback: callback,
    lastWidth: termSize.width,
    lastHeight: termSize.height,
  )

proc startAsync*(stream: AsyncEventStream) {.async.} =
  ## Start the async event stream
  stream.running = true

  while stream.running:
    try:
      # Check for events from multiple sources
      var event: Option[Event]

      # Check resize first (highest priority) by polling terminal size
      let currentSize = getTerminalSizeOrDefault()
      if currentSize.width != stream.lastWidth or currentSize.height != stream.lastHeight:
        stream.lastWidth = currentSize.width
        stream.lastHeight = currentSize.height
        event = some(Event(kind: Resize))
      else:
        # Check for keyboard events
        let keyEventOpt = await pollKeyAsync()
        if keyEventOpt.isSome():
          event = keyEventOpt
        else:
          # Small sleep to prevent busy waiting
          await sleepMs(16) # ~60 FPS
          continue

      if event.isSome() and stream.eventCallback != nil:
        let shouldContinue = await stream.eventCallback(event.get())
        if not shouldContinue:
          stream.running = false
    except CatchableError:
      # Any errors should stop the stream for now
      stream.running = false

proc stopAsync*(stream: AsyncEventStream) {.async.} =
  ## Stop the async event stream
  stream.running = false
