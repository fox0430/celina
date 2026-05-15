## Event handling
##
## This module provides comprehensive event handling for keyboard input,
## including escape sequences and arrow keys for POSIX systems.

import std/[os, posix, options, strutils, strformat]

import errors, mouse_logic, utf8_utils, key_logic, escape_sequence_logic

# Re-export types to maintain API compatibility
export mouse_logic.MouseButton, mouse_logic.MouseEventKind, mouse_logic.KeyModifier
export key_logic.KeyCode, key_logic.KeyEvent
export utf8_utils

type
  EventKind* = enum
    Key
    Mouse
    Resize
    Paste
    FocusIn
    FocusOut
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
    of Paste:
      pastedText*: string
    of Resize, FocusIn, FocusOut, Quit, Unknown:
      discard

proc modifiersToString(modifiers: set[KeyModifier]): string =
  ## Convert modifier set to string like "Ctrl+Alt+Shift"
  var mods: seq[string] = @[]
  if Ctrl in modifiers:
    mods.add("Ctrl")
  if Alt in modifiers:
    mods.add("Alt")
  if Shift in modifiers:
    mods.add("Shift")
  mods.join("+")

proc `$`*(key: KeyEvent): string =
  ## String representation of a KeyEvent for debugging
  var parts: seq[string] = @[]
  if key.modifiers.len > 0:
    parts.add(modifiersToString(key.modifiers))
  parts.add($key.code)
  if key.code == Char and key.char.len > 0:
    parts.add("'" & key.char & "'")
  "KeyEvent(" & parts.join(", ") & ")"

proc `$`*(mouse: MouseEvent): string =
  ## String representation of a MouseEvent for debugging
  var parts = @[$mouse.kind, $mouse.button, &"({mouse.x}, {mouse.y})"]
  if mouse.modifiers.len > 0:
    parts.add(modifiersToString(mouse.modifiers))
  "MouseEvent(" & parts.join(", ") & ")"

proc `$`*(event: Event): string =
  ## String representation of an Event for debugging
  case event.kind
  of Key:
    &"Event(Key, {event.key})"
  of Mouse:
    &"Event(Mouse, {event.mouse})"
  of Paste:
    let preview =
      if event.pastedText.len <= 20:
        event.pastedText
      else:
        event.pastedText[0 ..< 20] & "..."
    &"Event(Paste, \"{preview}\")"
  of Resize:
    "Event(Resize)"
  of FocusIn:
    "Event(FocusIn)"
  of FocusOut:
    "Event(FocusOut)"
  of Quit:
    "Event(Quit)"
  of Unknown:
    "Event(Unknown)"

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
  ## Parse X10 mouse format: ESC[Mbxy (blocking mode)
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
  ## Parse SGR mouse format: ESC[<button;x;y;M/m (blocking mode)
  ## M for press, m for release
  ##
  ## This function handles I/O and delegates parsing to shared mouse_logic module
  var buffer: string
  var ch: char
  var readCount = 0

  # Read until we get M or m, with safety limits
  while readCount < MaxSGRMouseReadBytes and stdin.readBuffer(addr ch, 1) == 1:
    readCount.inc()
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

      # Use shared parsing logic - no duplication with async version!
      return parseMouseDataSGR(buttonCode, x, y, isRelease).toEvent()
    except ValueError:
      return Event(kind: Unknown)

  return Event(kind: Unknown)

# Blocking I/O helper functions
proc readByteBlocking(): tuple[success: bool, ch: char] =
  ## Read a single byte in blocking mode
  ## Returns (success, char) where success is true if read succeeded
  var ch: char
  let bytesRead = tryRecover(
    proc(): int =
      stdin.readBuffer(addr ch, 1),
    fallback = 0,
  )
  if bytesRead == 1:
    return (true, ch)
  else:
    return (false, '\0')

# Bracketed paste content reader (blocking mode)
# Uses the shared paste-end state machine from escape_sequence_logic.

proc readPasteContentBlocking(): string =
  ## Read all content until paste end sequence ESC[201~ (blocking mode).
  ## Returns the pasted text without the end sequence.
  result = ""
  var state = PesNone
  var pending = ""
  while true:
    let r = readByteBlocking()
    if not r.success:
      # On read failure, flush any buffered partial-match bytes and return.
      result.add(pending)
      return
    if stepPasteEnd(state, pending, r.ch, result):
      return

# Unified escape sequence parsing routing (shared with async via template).
#
# The template body lives here (rather than escape_sequence_logic.nim) because
# it constructs `Event` values, and `Event` is defined in this module. Async
# callers reach it through `import ../core/events`.
#
# Each of the four parameters is an *expression* re-evaluated at every textual
# occurrence in the template body. Synchronous callers pass direct proc calls
# (`readByteBlocking()`); async callers pass `await ...` expressions. Because
# the template body itself contains no `await`, it is type-checked under the
# enclosing proc's sync/async context, so each context sees only its own form.
#
# Required shapes:
#   readByte      -> tuple with `.success: bool` and `.ch: char` fields
#                    (extra fields are ignored; e.g. non-blocking adds `.isTimeout`)
#   readPaste     -> string                          (paste content w/o terminator)
#   parseMouseX10 -> Event
#   parseMouseSGR -> Event

template parseEscapeSequenceUnified*(
    readByte, readPaste, parseMouseX10, parseMouseSGR: untyped
): Event =
  ## Parse an ESC sequence (ESC has already been consumed by the caller).
  ## For non-blocking callers, the post-ESC timeout check (standalone ESC vs
  ## start of a sequence) must be performed by the caller before invocation.
  block:
    let first = readByte
    if not first.success:
      Event(kind: Key, key: KeyEvent(code: KeyCode.Escape, char: "\x1b"))
    else:
      case first.ch
      of '[':
        let bracket = readByte
        case classifyBracketSequence(bracket.ch)
        of BskArrowKey, BskNavigationKey:
          let p = processSimpleBracketSequence(bracket.ch, bracket.success)
          Event(kind: Key, key: p.keyEvent)
        of BskMouseX10:
          parseMouseX10
        of BskMouseSGR:
          parseMouseSGR
        of BskNumeric:
          let digit = bracket.ch
          let numeric = readByte
          case classifyNumericSequence(numeric.ch, numeric.success)
          of NskSingleDigitWithTilde:
            let p = processSingleDigitNumeric(digit)
            Event(kind: Key, key: p.keyEvent)
          of NskMultiDigit:
            let second = numeric.ch
            let third = readByte
            if third.success and third.ch in {'0' .. '9'}:
              let tilde = readByte
              let tildeMatched = tilde.success and tilde.ch == '~'
              if tildeMatched and isPasteStartSequence(digit, second, third.ch, '~'):
                Event(kind: Paste, pastedText: readPaste)
              elif tildeMatched and isPasteEndSequence(digit, second, third.ch, '~'):
                # Orphaned paste end - shouldn't happen in normal flow
                Event(kind: Unknown)
              else:
                # Unknown 3-digit sequence (tilde missing or unrecognized)
                Event(kind: Key, key: escapeKey())
            else:
              let p =
                processMultiDigitFunctionKey(digit, second, third.ch, third.success)
              Event(kind: Key, key: p.keyEvent)
          of NskModifiedKey:
            let modifier = readByte
            let key = readByte
            let p = processModifiedKeySequence(
              digit, modifier.ch, modifier.success, key.ch, key.success
            )
            Event(kind: Key, key: p.keyEvent)
          of NskInvalid:
            Event(kind: Key, key: escapeKey())
        of BskFocusIn:
          Event(kind: FocusIn)
        of BskFocusOut:
          Event(kind: FocusOut)
        of BskInvalid:
          Event(kind: Key, key: escapeKey())
      of 'O':
        let vt = readByte
        let p = processVT100FunctionKey(vt.ch, vt.success)
        Event(kind: Key, key: p.keyEvent)
      else:
        Event(kind: Key, key: KeyEvent(code: KeyCode.Escape, char: "\x1b"))

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
    let readResult = readByteBlocking()

    if not readResult.success:
      return Event(kind: Unknown)

    let ch = readResult.ch

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

    # Handle escape sequences via the unified routing template (blocking I/O)
    if ch == '\x1b':
      return parseEscapeSequenceUnified(
        readByteBlocking(),
        readPasteContentBlocking(),
        parseMouseEventX10(),
        parseMouseEventSGR(),
      )

    # Handle regular UTF-8 characters
    let utf8Char = readUtf8Char(ch.byte)
    if utf8Char.len > 0:
      return Event(kind: Key, key: KeyEvent(code: Char, char: utf8Char))
    else:
      # Invalid UTF-8, treat as single byte
      return Event(kind: Key, key: KeyEvent(code: Char, char: $ch))
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

# File descriptor management helpers
type FdFlags = object ## RAII-style file descriptor flags manager
  fd: cint
  originalFlags: cint
  restored: bool

proc getFdFlags(fd: cint): Option[FdFlags] =
  ## Get current file descriptor flags
  let flags = fcntl(fd, F_GETFL, 0)
  if flags == -1:
    return none(FdFlags)
  return some(FdFlags(fd: fd, originalFlags: flags, restored: false))

proc setNonBlocking(flags: var FdFlags): bool =
  ## Set file descriptor to non-blocking mode
  ## Returns false on error
  if fcntl(flags.fd, F_SETFL, flags.originalFlags or O_NONBLOCK) == -1:
    return false
  return true

proc restore(flags: var FdFlags) =
  ## Restore original file descriptor flags
  if not flags.restored:
    discard fcntl(flags.fd, F_SETFL, flags.originalFlags)
    flags.restored = true

# Non-blocking byte reading helper
proc readByteNonBlocking(fd: cint): tuple[success: bool, ch: char, isTimeout: bool] =
  ## Read a single byte in non-blocking mode
  ## Returns (success, char, isTimeout) where:
  ## - success: true if read succeeded
  ## - ch: the character read (only valid if success is true)
  ## - isTimeout: true if EAGAIN/EWOULDBLOCK (no data available)
  var ch: char
  let bytesRead = read(fd, addr ch, 1)

  if bytesRead == -1:
    let err = errno
    if err == EAGAIN or err == EWOULDBLOCK:
      return (false, '\0', true)
    return (false, '\0', false)
  elif bytesRead == 1:
    return (true, ch, false)
  else:
    return (false, '\0', false)

# Non-blocking mouse event parsing

proc parseMouseEventX10NonBlocking(): Event =
  ## Parse X10 mouse format: ESC[Mbxy (non-blocking mode)
  ## where b is button byte, x,y are coordinate bytes
  ##
  ## Uses non-blocking I/O with select() to wait for complete sequence
  var data: array[3, char]

  for i in 0 .. 2:
    # Use select with timeout to wait for data
    var readSet: TFdSet
    FD_ZERO(readSet)
    FD_SET(STDIN_FILENO, readSet)
    var timeout = Timeval(tv_sec: Time(0), tv_usec: Suseconds(50000)) # 50ms per byte

    let selectResult = select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout)
    if selectResult <= 0:
      # Timeout or error - incomplete sequence
      return Event(kind: Unknown)

    let readResult = readByteNonBlocking(STDIN_FILENO)
    if not readResult.success:
      return Event(kind: Unknown)

    data[i] = readResult.ch

  # Use shared parsing logic - no duplication with async version!
  return parseMouseDataX10(data).toEvent()

proc parseMouseEventSGRNonBlocking(): Event =
  ## Parse SGR mouse format: ESC[<button;x;y;M/m (non-blocking mode)
  ## M for press, m for release
  ##
  ## Uses non-blocking I/O with select() to wait for complete sequence
  var buffer: string
  var ch: char
  var readCount = 0

  # Read until we get M or m, with safety limits
  while readCount < MaxSGRMouseReadBytes:
    # Use select with timeout to wait for data
    var readSet: TFdSet
    FD_ZERO(readSet)
    FD_SET(STDIN_FILENO, readSet)
    var timeout = Timeval(tv_sec: Time(0), tv_usec: Suseconds(50000)) # 50ms per byte

    let selectResult = select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout)
    if selectResult <= 0:
      # Timeout or error - incomplete sequence
      return Event(kind: Unknown)

    let readResult = readByteNonBlocking(STDIN_FILENO)
    if not readResult.success:
      return Event(kind: Unknown)

    ch = readResult.ch
    readCount.inc()

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

      # Use shared parsing logic - no duplication with async version!
      return parseMouseDataSGR(buttonCode, x, y, isRelease).toEvent()
    except ValueError:
      return Event(kind: Unknown)

  return Event(kind: Unknown)

# Bracketed paste content reader (non-blocking mode)
# Uses the shared paste-end state machine; differs from the blocking version
# only in how each byte is acquired (select() + non-blocking read with 1s
# timeout per byte vs unconditional blocking read).

proc readPasteContentNonBlocking(): string =
  ## Read paste content in non-blocking mode until ESC[201~.
  ## Uses select() with a 1-second timeout per byte; returns whatever has been
  ## buffered if the timeout fires.
  result = ""
  var state = PesNone
  var pending = ""

  while true:
    var readSet: TFdSet
    FD_ZERO(readSet)
    FD_SET(STDIN_FILENO, readSet)
    var timeout = Timeval(tv_sec: Time(1), tv_usec: Suseconds(0))

    let selectResult = select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout)
    if selectResult <= 0:
      result.add(pending)
      return

    let r = readByteNonBlocking(STDIN_FILENO)
    if not r.success:
      result.add(pending)
      return

    if stepPasteEnd(state, pending, r.ch, result):
      return

# Non-blocking event reading
proc readKeyInput*(): Option[Event] =
  ## Read a single key input event (non-blocking)
  ## Returns none(Event) if no input is available or on error
  var fdFlags = getFdFlags(STDIN_FILENO)
  if fdFlags.isNone:
    return none(Event)

  var flags = fdFlags.get()
  if not flags.setNonBlocking():
    return none(Event)

  let readResult = readByteNonBlocking(STDIN_FILENO)

  # No data available or error
  if not readResult.success:
    flags.restore()
    return none(Event)

  let ch = readResult.ch

  # Restore flags before returning
  defer:
    flags.restore()

  # Handle escape sequences via the unified routing template (non-blocking I/O).
  # The 20ms post-ESC select() distinguishes a standalone ESC keypress from the
  # start of a real sequence; this check is unique to non-blocking mode.
  if ch == '\x1b':
    var readSet: TFdSet
    FD_ZERO(readSet)
    FD_SET(STDIN_FILENO, readSet)
    var timeout = Timeval(tv_sec: Time(0), tv_usec: Suseconds(20000))
    if select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout) == 0:
      return some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))

    return some(
      parseEscapeSequenceUnified(
        readByteNonBlocking(STDIN_FILENO),
        readPasteContentNonBlocking(),
        parseMouseEventX10NonBlocking(),
        parseMouseEventSGRNonBlocking(),
      )
    )

  # Handle Ctrl+C (quit signal)
  if ch == '\x03':
    return some(Event(kind: Quit))

  # Handle Ctrl-letter combinations
  let ctrlLetterResult = mapCtrlLetterKey(ch)
  if ctrlLetterResult.isCtrlKey:
    return some(Event(kind: Key, key: ctrlLetterResult.keyEvent))

  # Handle Ctrl-number combinations
  let ctrlNumberResult = mapCtrlNumberKey(ch)
  if ctrlNumberResult.isCtrlKey:
    return some(Event(kind: Key, key: ctrlNumberResult.keyEvent))

  # Handle basic keys (Enter, Tab, Space, Backspace)
  let basicKey = mapBasicKey(ch)
  if basicKey.code in {Enter, Tab, Space, Backspace}:
    return some(Event(kind: Key, key: basicKey))

  # Handle regular UTF-8 characters
  let utf8Char = readUtf8CharNonBlocking(ch.byte)
  if utf8Char.len > 0:
    return some(Event(kind: Key, key: KeyEvent(code: Char, char: utf8Char)))
  else:
    # Invalid UTF-8, treat as single byte
    return some(Event(kind: Key, key: KeyEvent(code: Char, char: $ch)))

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
