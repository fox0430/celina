## Async event handling
##
## This module provides asynchronous event handling for keyboard input,
## mouse events, and other terminal events using either Chronos or std/asyncdispatch.

import std/[posix, options]

import async_backend, async_io
import ../core/events

# Define SIGWINCH if not available
when not declared(SIGWINCH):
  const SIGWINCH = 28

# Global state for async event handling
var resizeDetected* = false
var asyncStdinFd*: AsyncFD

# Signal handler for SIGWINCH
proc sigwinchHandler(sig: cint) {.noconv.} =
  resizeDetected = true

type AsyncEventError* = object of CatchableError

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

# Async key reading with escape sequence support
proc readKeyAsync*(): Future[Event] {.async.} =
  ## Read a key event asynchronously using non-blocking I/O
  try:
    # Use non-blocking AsyncFD read instead of blocking POSIX read
    let ch = await readCharAsync()

    if ch == '\0':
      return Event(kind: Unknown)

    case ch
    of '\r', '\n':
      return Event(kind: Key, key: KeyEvent(code: Enter, char: ch))
    of '\t':
      return Event(kind: Key, key: KeyEvent(code: Tab, char: ch))
    of ' ':
      return Event(kind: Key, key: KeyEvent(code: Space, char: ch))
    of '\x08', '\x7f': # Backspace or DEL
      return Event(kind: Key, key: KeyEvent(code: Backspace, char: ch))
    of '\x1b': # Escape or start of escape sequence
      # Check if more data is available with 20ms timeout
      let hasMoreData = await hasInputAsync(20)

      if not hasMoreData:
        # No more data after timeout - standalone ESC key
        return Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))

      # Try to read escape sequence
      let next = await readCharAsync()

      if next == '[':
        let final = await readCharAsync()

        if final != '\0':
          case final
          of 'A': # Arrow Up
            return Event(kind: Key, key: KeyEvent(code: ArrowUp, char: '\0'))
          of 'B': # Arrow Down
            return Event(kind: Key, key: KeyEvent(code: ArrowDown, char: '\0'))
          of 'C': # Arrow Right
            return Event(kind: Key, key: KeyEvent(code: ArrowRight, char: '\0'))
          of 'D': # Arrow Left
            return Event(kind: Key, key: KeyEvent(code: ArrowLeft, char: '\0'))
          of 'H': # Home
            return Event(kind: Key, key: KeyEvent(code: Home, char: '\0'))
          of 'F': # End
            return Event(kind: Key, key: KeyEvent(code: End, char: '\0'))
          of 'Z': # Shift+Tab (BackTab)
            return Event(kind: Key, key: KeyEvent(code: BackTab, char: '\0'))
          of 'M': # Mouse event (X10 format) - not implemented yet
            return Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
          of '<': # SGR mouse format - not implemented yet
            return Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
          of '1' .. '6':
            # Could be function key or special key with modifiers
            let nextChar = await readCharAsync()

            if nextChar != '\0':
              if nextChar == '~':
                # Special keys with numeric codes
                case final
                of '1': # Home (alternative)
                  return Event(kind: Key, key: KeyEvent(code: Home, char: '\0'))
                of '2': # Insert
                  return Event(kind: Key, key: KeyEvent(code: Insert, char: '\0'))
                of '3': # Delete
                  return Event(kind: Key, key: KeyEvent(code: Delete, char: '\0'))
                of '4': # End (alternative)
                  return Event(kind: Key, key: KeyEvent(code: End, char: '\0'))
                of '5': # PageUp
                  return Event(kind: Key, key: KeyEvent(code: PageUp, char: '\0'))
                of '6': # PageDown
                  return Event(kind: Key, key: KeyEvent(code: PageDown, char: '\0'))
                else:
                  return Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
              else:
                # Complex escape sequence - return escape for now
                return Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
            else:
              return Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
          else:
            return Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
        else:
          return Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
      else:
        return Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
    of '\x03': # Ctrl+C
      return Event(kind: Quit)
    else:
      return Event(kind: Key, key: KeyEvent(code: Char, char: ch))
  except Exception as e:
    raise newException(AsyncEventError, "Async key reading failed: " & e.msg)
  except CatchableError:
    return Event(kind: Unknown)

# Async mouse event parsing (simplified - to be implemented later)
proc parseMouseEventX10Async*(): Future[Event] {.async.} =
  ## Parse X10 mouse format - simplified implementation
  return Event(kind: Unknown)

proc parseMouseEventSGRAsync*(): Future[Event] {.async.} =
  ## Parse SGR mouse format - simplified implementation
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
type AsyncEventStream* = ref object
  running*: bool
  eventCallback*: proc(event: Event): Future[bool] {.async.}

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
