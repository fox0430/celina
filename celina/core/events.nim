## Event handling
##
## This module provides comprehensive event handling for keyboard input,
## including escape sequences and arrow keys for POSIX systems.

import std/[os, posix, options, strutils]

import errors
import mouse_logic
import utf8_utils
import key_logic

# Re-export types to maintain API compatibility
export mouse_logic.MouseButton, mouse_logic.MouseEventKind, mouse_logic.KeyModifier
export key_logic.KeyCode, key_logic.KeyEvent
export utf8_utils

# Define SIGWINCH if not available
when not declared(SIGWINCH):
  const SIGWINCH = 28

# Global flag for resize detection
var resizeDetected* = false

# Signal handler for SIGWINCH
proc sigwinchHandler(sig: cint) {.noconv.} =
  resizeDetected = true

type
  EventKind* = enum
    Key
    Mouse
    Resize
    Quit
    Unknown

  MouseEvent* = object
    kind*: MouseEventKind
    button*: MouseButton
    x*: int
    y*: int
    modifiers*: set[KeyModifier]

  Event* = object
    case kind*: EventKind
    of Key:
      key*: KeyEvent
    of Mouse:
      mouse*: MouseEvent
    of Resize, Quit, Unknown:
      discard

# Mouse event parsing functions (using shared logic from mouse_logic module)

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

proc parseMouseEventX10(): Event =
  ## Parse X10 mouse format: ESC[Mbxy
  ## where b is button byte, x,y are coordinate bytes
  ##
  ## This function handles I/O and delegates parsing to shared mouse_logic module
  var data: array[3, char]
  # Use a timeout to prevent hanging on incomplete sequences
  if stdin.readBuffer(addr data[0], 3) == 3:
    # Use shared parsing logic - no duplication with async version!
    return parseMouseDataX10(data).toEvent()

  return Event(kind: Unknown)

proc parseMouseEventSGR(): Event =
  ## Parse SGR mouse format: ESC[<button;x;y;M/m
  ## M for press, m for release
  ##
  ## This function handles I/O and delegates parsing to shared mouse_logic module
  var buffer: string
  var ch: char
  var readCount = 0
  const maxReadCount = 20 # Prevent infinite loops

  # Read until we get M or m, with safety limits
  while readCount < maxReadCount and stdin.readBuffer(addr ch, 1) == 1:
    readCount.inc()
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

      # Use shared parsing logic - no duplication with async version!
      return parseMouseDataSGR(buttonCode, x, y, isRelease).toEvent()
    except ValueError:
      return Event(kind: Unknown)

  return Event(kind: Unknown)

# UTF-8 helper functions (using shared logic from utf8_utils module)
proc readUtf8Char(firstByte: byte): string =
  ## Read a complete UTF-8 character given its first byte (blocking mode)
  ## Uses shared UTF-8 validation logic from utf8_utils
  let byteLen = utf8ByteLength(firstByte)
  if byteLen == 0:
    return ""

  if byteLen == 1:
    return $char(firstByte)

  # Read continuation bytes
  var continuationBytes: seq[byte] = @[]
  for i in 1 ..< byteLen:
    var nextByte: char
    let bytesRead = tryRecover(
      proc(): int =
        stdin.readBuffer(addr nextByte, 1),
      fallback = 0,
    )
    if bytesRead != 1:
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

proc readUtf8CharNonBlocking(firstByte: byte): string =
  ## Read a complete UTF-8 character in non-blocking mode
  ## Uses shared UTF-8 validation logic from utf8_utils
  let byteLen = utf8ByteLength(firstByte)
  if byteLen == 0:
    return ""

  if byteLen == 1:
    return $char(firstByte)

  # Read continuation bytes in non-blocking mode
  var continuationBytes: seq[byte] = @[]
  for i in 1 ..< byteLen:
    var nextByte: char
    let bytesRead = read(STDIN_FILENO, addr nextByte, 1)
    if bytesRead == -1:
      let err = errno
      if err == EAGAIN or err == EWOULDBLOCK:
        # No more data, return what we have
        if continuationBytes.len > 0:
          return buildUtf8String(firstByte, continuationBytes)
        else:
          return $char(firstByte)
      else:
        # Other error, return what we have
        if continuationBytes.len > 0:
          return buildUtf8String(firstByte, continuationBytes)
        else:
          return $char(firstByte)
    elif bytesRead != 1:
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

# Advanced key reading with escape sequence support
proc readKey*(): Event =
  ## Read a key event (blocking mode)
  ## Raises IOError if unable to read from stdin
  try:
    var ch: char
    let bytesRead = tryRecover(
      proc(): int =
        stdin.readBuffer(addr ch, 1),
      fallback = 0,
    )

    if bytesRead == 1:
      # Handle Ctrl+letter combinations using shared logic
      let ctrlLetterResult = mapCtrlLetterKey(ch)
      if ctrlLetterResult.isCtrlKey:
        return Event(kind: Key, key: ctrlLetterResult.keyEvent)

      # Handle Ctrl+number using shared logic
      let ctrlNumberResult = mapCtrlNumberKey(ch)
      if ctrlNumberResult.isCtrlKey:
        return Event(kind: Key, key: ctrlNumberResult.keyEvent)

      # Handle basic keys using shared logic
      case ch
      of '\r', '\n', '\t', ' ', '\x08', '\x7f':
        return Event(kind: Key, key: mapBasicKey(ch))
      of '\x1b': # Escape or start of escape sequence
        # Try to read escape sequence in blocking mode
        var next: char
        if stdin.readBuffer(addr next, 1) == 1:
          if next == '[':
            var final: char
            if stdin.readBuffer(addr final, 1) == 1:
              # Handle arrow keys using shared logic
              if final in {'A', 'B', 'C', 'D'}:
                return Event(kind: Key, key: mapArrowKey(final))

              # Handle navigation keys using shared logic
              if final in {'H', 'F', 'Z'}:
                return Event(kind: Key, key: mapNavigationKey(final))

              # Mouse events (not shared logic)
              if final == 'M':
                return parseMouseEventX10()
              if final == '<':
                return parseMouseEventSGR()

              # Numeric key codes (single digit and multi-digit)
              if final in {'1' .. '6'}:
                var nextChar: char
                if stdin.readBuffer(addr nextChar, 1) == 1:
                  if nextChar == '~':
                    # Use shared logic for numeric key codes
                    return Event(kind: Key, key: mapNumericKeyCode(final))
                  elif nextChar in {'0' .. '9'}:
                    # Multi-digit sequence for function keys (e.g., 11~, 15~, etc.)
                    let twoDigitSeq = $final & $nextChar
                    var tilde: char
                    if stdin.readBuffer(addr tilde, 1) == 1 and tilde == '~':
                      return Event(kind: Key, key: mapFunctionKey(twoDigitSeq))
                    else:
                      # Invalid sequence
                      return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))
                  elif nextChar == ';':
                    # Modified key sequence ESC[1;modifierX where X is the key
                    var modChar: char
                    if stdin.readBuffer(addr modChar, 1) == 1:
                      # Parse modifier using shared logic
                      let modifiers = parseModifierCode(modChar)

                      var keyChar: char
                      if stdin.readBuffer(addr keyChar, 1) == 1:
                        # Map the key using shared logic and apply modifiers
                        let baseKey =
                          if keyChar in {'A', 'B', 'C', 'D'}:
                            mapArrowKey(keyChar)
                          elif keyChar in {'H', 'F'}:
                            mapNavigationKey(keyChar)
                          elif keyChar == '~':
                            mapNumericKeyCode(final)
                          else:
                            KeyEvent(code: Escape, char: "\x1b")

                        return Event(kind: Key, key: applyModifiers(baseKey, modifiers))
                  else:
                    # Unknown sequence
                    return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))
              else:
                # Unknown escape sequence
                return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))
            else:
              # No final character
              return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))
          elif next == 'O':
            # VT100-style function keys: ESC O P/Q/R/S
            var funcKey: char
            if stdin.readBuffer(addr funcKey, 1) == 1:
              return Event(kind: Key, key: mapVT100FunctionKey(funcKey))
            else:
              return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))
          else:
            # No '[' or 'O' after ESC
            return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))
        else:
          # No character after ESC
          return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))
      of '\x03': # Ctrl-C
        return Event(kind: Quit)
      else:
        # Read complete UTF-8 character
        let utf8Char = readUtf8Char(ch.byte)
        if utf8Char.len > 0:
          return Event(kind: Key, key: KeyEvent(code: Char, char: utf8Char))
        else:
          # Invalid UTF-8, treat as single byte
          return Event(kind: Key, key: KeyEvent(code: Char, char: $ch))
    else:
      return Event(kind: Unknown)
  except IOError:
    return Event(kind: Unknown)

# Polling key reading
proc pollKey*(): Event =
  ## Poll for a key event (non-blocking)
  # Set stdin to non-blocking mode temporarily
  let flags = fcntl(STDIN_FILENO, F_GETFL)
  discard fcntl(STDIN_FILENO, F_SETFL, flags or O_NONBLOCK)

  let event = readKey()

  # Restore blocking mode
  discard fcntl(STDIN_FILENO, F_SETFL, flags)

  return event

# Non-blocking event reading
proc readKeyInput*(): Option[Event] =
  ## Read a single key input event (non-blocking)
  ## Returns none(Event) if no input is available or on error
  let flags = fcntl(STDIN_FILENO, F_GETFL, 0)
  if flags == -1:
    return none(Event)

  if fcntl(STDIN_FILENO, F_SETFL, flags or O_NONBLOCK) == -1:
    return none(Event)

  var ch: char
  let bytesRead = read(STDIN_FILENO, addr ch, 1)

  # Handle EAGAIN/EWOULDBLOCK (no data available in non-blocking mode)
  if bytesRead == -1:
    let err = errno
    if err == EAGAIN or err == EWOULDBLOCK:
      discard fcntl(STDIN_FILENO, F_SETFL, flags)
      return none(Event)
    else:
      # Other error occurred
      discard fcntl(STDIN_FILENO, F_SETFL, flags)
      return none(Event)

  if bytesRead > 0:
    if ch == '\x1b':
      # Use select with timeout to detect escape sequences
      var readSet: TFdSet
      FD_ZERO(readSet)
      FD_SET(STDIN_FILENO, readSet)
      var timeout = Timeval(tv_sec: Time(0), tv_usec: Suseconds(20000)) # 20ms

      # If no more data available in 20ms, it's a standalone ESC
      if select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout) == 0:
        return some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))

      var next: char
      let nextRead = read(STDIN_FILENO, addr next, 1)
      if nextRead == -1 and (errno == EAGAIN or errno == EWOULDBLOCK):
        discard fcntl(STDIN_FILENO, F_SETFL, flags)
        return some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))

      if nextRead == 1 and next == '[':
        var final: char
        let finalRead = read(STDIN_FILENO, addr final, 1)
        if finalRead == -1 and (errno == EAGAIN or errno == EWOULDBLOCK):
          discard fcntl(STDIN_FILENO, F_SETFL, flags)
          return some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))

        if finalRead == 1:
          # Restore non-blocking mode
          discard fcntl(STDIN_FILENO, F_SETFL, flags or O_NONBLOCK)

          # Try arrow keys first
          let arrowKey = mapArrowKey(final)
          if arrowKey.code != Escape:
            return some(Event(kind: Key, key: arrowKey))

          # Try navigation keys
          let navKey = mapNavigationKey(final)
          if navKey.code != Escape:
            return some(Event(kind: Key, key: navKey))

          # Handle mouse events and numeric sequences
          case final
          of 'M': # Mouse event (X10 format)
            let mouseEvent = parseMouseEventX10()
            return some(mouseEvent)
          of '<': # SGR mouse format
            let mouseEvent = parseMouseEventSGR()
            return some(mouseEvent)
          of '1' .. '6':
            # Could be function key or special key with modifiers
            var nextChar: char
            let nextCharRead = read(STDIN_FILENO, addr nextChar, 1)
            if nextCharRead == -1 and (errno == EAGAIN or errno == EWOULDBLOCK):
              discard fcntl(STDIN_FILENO, F_SETFL, flags)
              return some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))

            if nextCharRead == 1:
              if nextChar == '~':
                # Special keys with numeric codes - use shared logic
                let numKey = mapNumericKeyCode(final)
                return some(Event(kind: Key, key: numKey))
              elif nextChar in {'0' .. '9'}:
                # Multi-digit sequence for function keys
                let twoDigitSeq = $final & $nextChar
                var tilde: char
                let tildeRead = read(STDIN_FILENO, addr tilde, 1)
                if tildeRead == -1 and (errno == EAGAIN or errno == EWOULDBLOCK):
                  discard fcntl(STDIN_FILENO, F_SETFL, flags)
                  return
                    some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))
                if tildeRead == 1 and tilde == '~':
                  return some(Event(kind: Key, key: mapFunctionKey(twoDigitSeq)))
                else:
                  return
                    some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))
              elif nextChar == ';':
                # Modified key sequence
                var modChar: char
                let modCharRead = read(STDIN_FILENO, addr modChar, 1)
                if modCharRead == -1 and (errno == EAGAIN or errno == EWOULDBLOCK):
                  discard fcntl(STDIN_FILENO, F_SETFL, flags)
                  return
                    some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))

                if modCharRead == 1:
                  # Parse modifier using shared logic
                  let modifiers = parseModifierCode(modChar)

                  var keyChar: char
                  let keyCharRead = read(STDIN_FILENO, addr keyChar, 1)
                  if keyCharRead == -1 and (errno == EAGAIN or errno == EWOULDBLOCK):
                    discard fcntl(STDIN_FILENO, F_SETFL, flags)
                    return
                      some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))

                  if keyCharRead == 1:
                    # Try arrow keys with modifiers
                    let arrowKey = mapArrowKey(keyChar)
                    if arrowKey.code != Escape:
                      return
                        some(Event(kind: Key, key: applyModifiers(arrowKey, modifiers)))

                    # Try navigation keys with modifiers
                    let navKey = mapNavigationKey(keyChar)
                    if navKey.code != Escape:
                      return
                        some(Event(kind: Key, key: applyModifiers(navKey, modifiers)))

                    # Handle modified special keys (numeric codes with ~)
                    if keyChar == '~':
                      let numKey = mapNumericKeyCode(final)
                      if numKey.code != Escape:
                        return
                          some(Event(kind: Key, key: applyModifiers(numKey, modifiers)))
                    else:
                      return some(
                        Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))
                      )
                  else:
                    return
                      some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))
                else:
                  return
                    some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))
              else:
                # Might be function key, but we'll skip for now
                return some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))
            else:
              return some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))
          else:
            return some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))
        else:
          # Not an escape sequence we recognize
          return some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))
      elif nextRead == 1 and next == 'O':
        # VT100-style function keys: ESC O P/Q/R/S
        var funcKey: char
        let funcKeyRead = read(STDIN_FILENO, addr funcKey, 1)
        if funcKeyRead == -1 and (errno == EAGAIN or errno == EWOULDBLOCK):
          discard fcntl(STDIN_FILENO, F_SETFL, flags)
          return some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))
        if funcKeyRead == 1:
          return some(Event(kind: Key, key: mapVT100FunctionKey(funcKey)))
        else:
          return some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))
      else:
        # Not an escape sequence (no '[' or 'O' after ESC)
        return some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))
    else:
      # Restore non-blocking mode
      discard fcntl(STDIN_FILENO, F_SETFL, flags)

      # Handle Ctrl-letter combinations using shared logic
      let ctrlLetterResult = mapCtrlLetterKey(ch)
      if ctrlLetterResult.isCtrlKey:
        return some(Event(kind: Key, key: ctrlLetterResult.keyEvent))

      # Handle Ctrl-number and special control characters using shared logic
      let ctrlNumberResult = mapCtrlNumberKey(ch)
      if ctrlNumberResult.isCtrlKey:
        return some(Event(kind: Key, key: ctrlNumberResult.keyEvent))

      # Handle special quit signal
      if ch == '\x03':
        return some(Event(kind: Quit))

      # Use shared basic key mapping for common keys
      let basicKey = mapBasicKey(ch)
      if basicKey.code in {Enter, Tab, Space, Backspace}:
        return some(Event(kind: Key, key: basicKey))

      # For regular characters, read complete UTF-8 character in non-blocking mode
      let utf8Char = readUtf8CharNonBlocking(ch.byte)
      if utf8Char.len > 0:
        return some(
          Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Char, char: utf8Char))
        )
      else:
        # Invalid UTF-8, treat as single byte
        return
          some(Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Char, char: $ch)))
  else:
    # Restore non-blocking mode
    discard fcntl(STDIN_FILENO, F_SETFL, flags)
    return none(Event)

# Check if input is available
proc hasInput*(): bool =
  ## Check if input is available without blocking
  # Use select to check if input is available
  var readSet: TFdSet
  FD_ZERO(readSet)
  FD_SET(STDIN_FILENO, readSet)

  var timeout = Timeval(tv_sec: Time(0), tv_usec: 0)
  select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout) > 0

# Event loop utilities
proc waitForKey*(): Event =
  ## Wait for a key press (blocking)
  while true:
    let event = readKey()
    if event.kind != Unknown:
      return event
    sleep(10) # Small delay to prevent busy waiting

proc waitForAnyKey*(): bool =
  ## Wait for any key press, return true if not quit
  let event = waitForKey()
  return event.kind != Quit

# Initialize signal handling
proc initSignalHandling*() =
  ## Initialize signal handling for terminal resize
  signal(SIGWINCH, sigwinchHandler)

# Check for resize event
proc checkResize*(): Option[Event] =
  ## Check if a resize event occurred
  if resizeDetected:
    resizeDetected = false
    return some(Event(kind: Resize))
  return none(Event)

# Event polling with timeout
proc pollEvents*(timeoutMs: int): bool =
  ## Poll for available events with a timeout
  ## Returns true if events are available, false if timeout occurred
  ## Similar to crossterm::event::poll()
  var readSet: TFdSet
  FD_ZERO(readSet)
  FD_SET(STDIN_FILENO, readSet)

  var timeout = Timeval(
    tv_sec: Time(timeoutMs div 1000), tv_usec: Suseconds((timeoutMs mod 1000) * 1000)
  )

  # Use select to check if input is available with timeout
  let r = select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout)
  return r > 0
