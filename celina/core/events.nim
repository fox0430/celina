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

# Define SIGWINCH if not available
when not declared(SIGWINCH):
  const SIGWINCH = 28

# Global counter for resize detection
# Note: We use a counter instead of a bool to support multiple App instances.
# Each App tracks the last counter value it saw, allowing all Apps to receive
# resize events independently without race conditions.
var resizeCounter {.global.}: int = 0

# Signal handler for SIGWINCH
proc sigwinchHandler(sig: cint) {.noconv.} =
  # Increment counter on each resize signal
  # This is safe in signal handlers as it's a simple increment
  resizeCounter.inc()

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

# Escape sequence parsing for blocking mode (ordered by dependencies)

proc parseEscapeSequenceVT100Blocking(): Event =
  ## Parse VT100-style function keys: ESC O P/Q/R/S (blocking mode)
  let funcResult = readByteBlocking()
  let parseResult = processVT100FunctionKey(funcResult.ch, funcResult.success)
  return Event(kind: Key, key: parseResult.keyEvent)

type PasteEndState = enum
  ## State machine for detecting paste end sequence ESC[201~
  PesNone # Not in sequence
  PesEsc # Saw ESC
  PesBracket # Saw ESC [
  Pes2 # Saw ESC [ 2
  Pes20 # Saw ESC [ 2 0
  Pes201 # Saw ESC [ 2 0 1

proc readPasteContentBlocking(): string =
  ## Read all content until paste end sequence ESC[201~
  ## Returns the pasted text (without the end sequence)
  result = ""
  var state = PesNone
  var pendingBytes: string = ""

  while true:
    let readResult = readByteBlocking()
    if not readResult.success:
      # On read failure, return what we have
      result.add(pendingBytes)
      return

    let ch = readResult.ch

    case state
    of PesNone:
      if ch == '\x1b':
        state = PesEsc
        pendingBytes = $ch
      else:
        result.add(ch)
    of PesEsc:
      if ch == '[':
        state = PesBracket
        pendingBytes.add(ch)
      elif ch == '\x1b':
        # New potential sequence, flush previous ESC
        result.add(pendingBytes)
        pendingBytes = $ch
        # state stays PesEsc
      else:
        # Not a sequence, flush pending and continue
        result.add(pendingBytes)
        result.add(ch)
        pendingBytes = ""
        state = PesNone
    of PesBracket:
      if ch == '2':
        state = Pes2
        pendingBytes.add(ch)
      elif ch == '\x1b':
        # New potential sequence, flush and restart
        result.add(pendingBytes)
        pendingBytes = $ch
        state = PesEsc
      else:
        # Not paste end, flush pending
        result.add(pendingBytes)
        result.add(ch)
        pendingBytes = ""
        state = PesNone
    of Pes2:
      if ch == '0':
        state = Pes20
        pendingBytes.add(ch)
      elif ch == '\x1b':
        result.add(pendingBytes)
        pendingBytes = $ch
        state = PesEsc
      else:
        result.add(pendingBytes)
        result.add(ch)
        pendingBytes = ""
        state = PesNone
    of Pes20:
      if ch == '1':
        state = Pes201
        pendingBytes.add(ch)
      elif ch == '\x1b':
        result.add(pendingBytes)
        pendingBytes = $ch
        state = PesEsc
      else:
        result.add(pendingBytes)
        result.add(ch)
        pendingBytes = ""
        state = PesNone
    of Pes201:
      if ch == '~':
        # Found paste end sequence ESC[201~
        # Don't add pendingBytes or this char to result
        return
      elif ch == '\x1b':
        result.add(pendingBytes)
        pendingBytes = $ch
        state = PesEsc
      else:
        result.add(pendingBytes)
        result.add(ch)
        pendingBytes = ""
        state = PesNone

proc parseMultiDigitFunctionKeyBlocking(firstDigit, secondDigit: char): Event =
  ## Parse multi-digit function keys like ESC[15~, ESC[200~, ESC[201~ (blocking mode)
  let thirdResult = readByteBlocking()

  # Check for 3-digit sequences (paste markers: 200~, 201~)
  if thirdResult.success and thirdResult.ch in {'0' .. '9'}:
    # This is a 3-digit sequence, read one more byte for the tilde
    let tildeResult = readByteBlocking()
    if tildeResult.success and tildeResult.ch == '~':
      # Check for paste start: ESC[200~
      if isPasteStartSequence(firstDigit, secondDigit, thirdResult.ch, '~'):
        let pastedText = readPasteContentBlocking()
        return Event(kind: Paste, pastedText: pastedText)
      # Check for paste end (orphaned - shouldn't happen in normal flow)
      if isPasteEndSequence(firstDigit, secondDigit, thirdResult.ch, '~'):
        return Event(kind: Unknown)
    # Unknown 3-digit sequence, return escape key
    return Event(kind: Key, key: escapeKey())

  # Standard 2-digit function key: ESC[15~
  let parseResult = processMultiDigitFunctionKey(
    firstDigit, secondDigit, thirdResult.ch, thirdResult.success
  )
  return Event(kind: Key, key: parseResult.keyEvent)

proc parseModifiedKeySequenceBlocking(digit: char): Event =
  ## Parse modified key sequences like ESC[1;2A (blocking mode)
  let modResult = readByteBlocking()
  let keyResult = readByteBlocking()
  let parseResult = processModifiedKeySequence(
    digit, modResult.ch, modResult.success, keyResult.ch, keyResult.success
  )
  return Event(kind: Key, key: parseResult.keyEvent)

proc parseNumericKeySequenceBlocking(digit: char): Event =
  ## Parse numeric key sequences like ESC[1~, ESC[15~, ESC[1;2A, etc. (blocking mode)
  let nextResult = readByteBlocking()
  let seqKind = classifyNumericSequence(nextResult.ch, nextResult.success)

  case seqKind
  of NskSingleDigitWithTilde:
    let parseResult = processSingleDigitNumeric(digit)
    return Event(kind: Key, key: parseResult.keyEvent)
  of NskMultiDigit:
    return parseMultiDigitFunctionKeyBlocking(digit, nextResult.ch)
  of NskModifiedKey:
    return parseModifiedKeySequenceBlocking(digit)
  of NskInvalid:
    return Event(kind: Key, key: escapeKey())

proc parseEscapeSequenceBracketBlocking(): Event =
  ## Parse ESC [ sequences (CSI sequences) (blocking mode)
  let finalResult = readByteBlocking()
  let seqKind = classifyBracketSequence(finalResult.ch)

  case seqKind
  of BskArrowKey, BskNavigationKey:
    let parseResult = processSimpleBracketSequence(finalResult.ch, finalResult.success)
    return Event(kind: Key, key: parseResult.keyEvent)
  of BskMouseX10:
    return parseMouseEventX10()
  of BskMouseSGR:
    return parseMouseEventSGR()
  of BskNumeric:
    return parseNumericKeySequenceBlocking(finalResult.ch)
  of BskFocusIn:
    return Event(kind: FocusIn)
  of BskFocusOut:
    return Event(kind: FocusOut)
  of BskInvalid:
    return Event(kind: Key, key: escapeKey())

proc parseEscapeSequenceBlocking(): Event =
  ## Parse escape sequences in blocking mode
  ## Assumes ESC has already been read
  let nextResult = readByteBlocking()
  if not nextResult.success:
    return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))

  let next = nextResult.ch

  if next == '[':
    return parseEscapeSequenceBracketBlocking()
  elif next == 'O':
    return parseEscapeSequenceVT100Blocking()
  else:
    # Not an escape sequence we recognize
    return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))

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

    # Handle escape sequences
    if ch == '\x1b':
      return parseEscapeSequenceBlocking()

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

proc parseMouseEventX10NonBlocking(): Option[Event] =
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
      return some(Event(kind: Unknown))

    let readResult = readByteNonBlocking(STDIN_FILENO)
    if not readResult.success:
      return some(Event(kind: Unknown))

    data[i] = readResult.ch

  # Use shared parsing logic - no duplication with async version!
  return some(parseMouseDataX10(data).toEvent())

proc parseMouseEventSGRNonBlocking(): Option[Event] =
  ## Parse SGR mouse format: ESC[<button;x;y;M/m (non-blocking mode)
  ## M for press, m for release
  ##
  ## Uses non-blocking I/O with select() to wait for complete sequence
  var buffer: string
  var ch: char
  var readCount = 0
  const maxReadCount = 20 # Prevent infinite loops

  # Read until we get M or m, with safety limits
  while readCount < maxReadCount:
    # Use select with timeout to wait for data
    var readSet: TFdSet
    FD_ZERO(readSet)
    FD_SET(STDIN_FILENO, readSet)
    var timeout = Timeval(tv_sec: Time(0), tv_usec: Suseconds(50000)) # 50ms per byte

    let selectResult = select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout)
    if selectResult <= 0:
      # Timeout or error - incomplete sequence
      return some(Event(kind: Unknown))

    let readResult = readByteNonBlocking(STDIN_FILENO)
    if not readResult.success:
      return some(Event(kind: Unknown))

    ch = readResult.ch
    readCount.inc()

    if ch == 'M' or ch == 'm':
      break
    buffer.add(ch)

  # If we didn't find a terminator, return unknown event
  if readCount >= maxReadCount or (ch != 'M' and ch != 'm'):
    return some(Event(kind: Unknown))

  # Parse the SGR format: button;x;y
  let parts = buffer.split(';')
  if parts.len >= 3:
    try:
      let buttonCode = parseInt(parts[0])
      let x = parseInt(parts[1]) - 1 # SGR uses 1-based coordinates
      let y = parseInt(parts[2]) - 1
      let isRelease = (ch == 'm')

      # Use shared parsing logic - no duplication with async version!
      return some(parseMouseDataSGR(buttonCode, x, y, isRelease).toEvent())
    except ValueError:
      return some(Event(kind: Unknown))

  return some(Event(kind: Unknown))

# Escape sequence parsing helpers (ordered by dependencies)

proc parseEscapeSequenceVT100(): Option[Event] =
  ## Parse VT100-style function keys: ESC O P/Q/R/S
  let funcResult = readByteNonBlocking(STDIN_FILENO)
  let parseResult = processVT100FunctionKey(funcResult.ch, funcResult.success)
  return some(Event(kind: Key, key: parseResult.keyEvent))

proc readPasteContentNonBlocking(): Option[string] =
  ## Read paste content in non-blocking mode until ESC[201~
  ## Uses select() with timeout to wait for data
  var resultStr = ""
  var state = PesNone
  var pendingBytes: string = ""

  while true:
    # Wait for data with reasonable timeout
    var readSet: TFdSet
    FD_ZERO(readSet)
    FD_SET(STDIN_FILENO, readSet)
    var timeout = Timeval(tv_sec: Time(1), tv_usec: Suseconds(0)) # 1 second max

    let selectResult = select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout)
    if selectResult <= 0:
      # Timeout or error - return what we have
      resultStr.add(pendingBytes)
      return some(resultStr)

    let readResult = readByteNonBlocking(STDIN_FILENO)
    if not readResult.success:
      resultStr.add(pendingBytes)
      return some(resultStr)

    let ch = readResult.ch

    case state
    of PesNone:
      if ch == '\x1b':
        state = PesEsc
        pendingBytes = $ch
      else:
        resultStr.add(ch)
    of PesEsc:
      if ch == '[':
        state = PesBracket
        pendingBytes.add(ch)
      elif ch == '\x1b':
        # New potential sequence, flush previous ESC
        resultStr.add(pendingBytes)
        pendingBytes = $ch
        # state stays PesEsc
      else:
        resultStr.add(pendingBytes)
        resultStr.add(ch)
        pendingBytes = ""
        state = PesNone
    of PesBracket:
      if ch == '2':
        state = Pes2
        pendingBytes.add(ch)
      elif ch == '\x1b':
        resultStr.add(pendingBytes)
        pendingBytes = $ch
        state = PesEsc
      else:
        resultStr.add(pendingBytes)
        resultStr.add(ch)
        pendingBytes = ""
        state = PesNone
    of Pes2:
      if ch == '0':
        state = Pes20
        pendingBytes.add(ch)
      elif ch == '\x1b':
        resultStr.add(pendingBytes)
        pendingBytes = $ch
        state = PesEsc
      else:
        resultStr.add(pendingBytes)
        resultStr.add(ch)
        pendingBytes = ""
        state = PesNone
    of Pes20:
      if ch == '1':
        state = Pes201
        pendingBytes.add(ch)
      elif ch == '\x1b':
        resultStr.add(pendingBytes)
        pendingBytes = $ch
        state = PesEsc
      else:
        resultStr.add(pendingBytes)
        resultStr.add(ch)
        pendingBytes = ""
        state = PesNone
    of Pes201:
      if ch == '~':
        # Found paste end sequence ESC[201~
        return some(resultStr)
      elif ch == '\x1b':
        resultStr.add(pendingBytes)
        pendingBytes = $ch
        state = PesEsc
      else:
        resultStr.add(pendingBytes)
        resultStr.add(ch)
        pendingBytes = ""
        state = PesNone

proc parseMultiDigitFunctionKey(firstDigit, secondDigit: char): Option[Event] =
  ## Parse multi-digit function keys like ESC[15~, ESC[200~, ESC[201~
  let thirdResult = readByteNonBlocking(STDIN_FILENO)

  # Check for 3-digit sequences (paste markers: 200~, 201~)
  if thirdResult.success and thirdResult.ch in {'0' .. '9'}:
    # This is a 3-digit sequence, read one more byte for the tilde
    let tildeResult = readByteNonBlocking(STDIN_FILENO)
    if tildeResult.success and tildeResult.ch == '~':
      # Check for paste start: ESC[200~
      if isPasteStartSequence(firstDigit, secondDigit, thirdResult.ch, '~'):
        let pastedText = readPasteContentNonBlocking()
        if pastedText.isSome:
          return some(Event(kind: Paste, pastedText: pastedText.get))
        return some(Event(kind: Unknown))
      # Check for paste end (orphaned)
      if isPasteEndSequence(firstDigit, secondDigit, thirdResult.ch, '~'):
        return some(Event(kind: Unknown))
    # Unknown 3-digit sequence
    return some(Event(kind: Key, key: escapeKey()))

  # Standard 2-digit function key: ESC[15~
  let parseResult = processMultiDigitFunctionKey(
    firstDigit, secondDigit, thirdResult.ch, thirdResult.success
  )
  return some(Event(kind: Key, key: parseResult.keyEvent))

proc parseModifiedKeySequence(digit: char): Option[Event] =
  ## Parse modified key sequences like ESC[1;2A
  let modResult = readByteNonBlocking(STDIN_FILENO)
  let keyResult = readByteNonBlocking(STDIN_FILENO)
  let parseResult = processModifiedKeySequence(
    digit, modResult.ch, modResult.success, keyResult.ch, keyResult.success
  )
  return some(Event(kind: Key, key: parseResult.keyEvent))

proc parseNumericKeySequence(digit: char): Option[Event] =
  ## Parse numeric key sequences like ESC[1~, ESC[15~, ESC[1;2A, etc.
  let nextResult = readByteNonBlocking(STDIN_FILENO)
  let seqKind = classifyNumericSequence(nextResult.ch, nextResult.success)

  case seqKind
  of NskSingleDigitWithTilde:
    let parseResult = processSingleDigitNumeric(digit)
    return some(Event(kind: Key, key: parseResult.keyEvent))
  of NskMultiDigit:
    return parseMultiDigitFunctionKey(digit, nextResult.ch)
  of NskModifiedKey:
    return parseModifiedKeySequence(digit)
  of NskInvalid:
    return some(Event(kind: Key, key: escapeKey()))

proc parseEscapeSequenceBracket(): Option[Event] =
  ## Parse ESC [ sequences (CSI sequences) (non-blocking mode)
  let finalResult = readByteNonBlocking(STDIN_FILENO)
  let seqKind = classifyBracketSequence(finalResult.ch)

  case seqKind
  of BskArrowKey, BskNavigationKey:
    let parseResult = processSimpleBracketSequence(finalResult.ch, finalResult.success)
    return some(Event(kind: Key, key: parseResult.keyEvent))
  of BskMouseX10:
    return parseMouseEventX10NonBlocking()
  of BskMouseSGR:
    return parseMouseEventSGRNonBlocking()
  of BskNumeric:
    return parseNumericKeySequence(finalResult.ch)
  of BskFocusIn:
    return some(Event(kind: FocusIn))
  of BskFocusOut:
    return some(Event(kind: FocusOut))
  of BskInvalid:
    return some(Event(kind: Key, key: escapeKey()))

proc parseEscapeSequenceNonBlocking(): Option[Event] =
  ## Parse escape sequences in non-blocking mode
  ## Returns Some(Event) if a valid sequence is parsed, None if incomplete/invalid
  ## Assumes ESC has already been read

  # Use select with timeout to detect escape sequences
  var readSet: TFdSet
  FD_ZERO(readSet)
  FD_SET(STDIN_FILENO, readSet)
  var timeout = Timeval(tv_sec: Time(0), tv_usec: Suseconds(20000)) # 20ms

  # If no more data available in 20ms, it's a standalone ESC
  if select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout) == 0:
    return some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))

  let nextResult = readByteNonBlocking(STDIN_FILENO)
  if not nextResult.success:
    return some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))

  let next = nextResult.ch

  if next == '[':
    return parseEscapeSequenceBracket()
  elif next == 'O':
    return parseEscapeSequenceVT100()
  else:
    # Not an escape sequence we recognize
    return some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))

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

  # Handle escape sequences
  if ch == '\x1b':
    return parseEscapeSequenceNonBlocking()

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

# Initialize signal handling
proc initSignalHandling*() =
  ## Initialize signal handling for terminal resize
  signal(SIGWINCH, sigwinchHandler)

# Get current resize counter value
proc getResizeCounter*(): int =
  ## Get the current resize counter value
  ##
  ## Apps should track the last value they saw and compare with this
  ## to detect resize events without race conditions.
  return resizeCounter

# Test helper: Increment resize counter (for testing only)
proc incrementResizeCounter*() =
  ## Increment the resize counter (for testing purposes)
  ## This simulates a SIGWINCH signal being received
  resizeCounter.inc()

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
