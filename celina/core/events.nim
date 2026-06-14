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
  EventResult* = enum
    ## Outcome of event handling.
    ##
    ## Returned by event handlers to control propagation through the
    ## window-first fallthrough chain (`Window` handler -> global
    ## `App.onEvent` handler):
    ## - `erContinue`: handler did not consume the event; allow the next
    ##   layer to process it.
    ## - `erConsume`: handler consumed the event; stop propagation.
    ##   (Only window/widget handlers cause stop; from a global handler
    ##   this is equivalent to `erContinue` because there is no next layer.)
    ## - `erQuit`: signal the application to exit. Meaningful only from a
    ##   global handler. If a window handler returns `erQuit` it is
    ##   normalized to `erConsume` by `handleWindowEvent` — only the
    ##   global handler can quit.
    erContinue
    erConsume
    erQuit

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

# Pushback buffer for one byte that was read but rejected as a UTF-8
# continuation. It must be presented as the *first* byte of the next event so
# we don't lose its information (Unicode §3.9 resync byte). Set by readKey /
# readKeyInput after a `readUtf8Char*` returns `leftover.isSome`, and consumed
# by readByteBlocking / readByteNonBlocking on the next call.
#
# pendingByte is only set immediately before an event is returned, so by the
# time any byte reader is called again, the byte is naturally for a fresh
# event — there is no chance of mixing it with ESC sequence or paste content
# bytes that follow within the same event.
var pendingByte* {.threadvar.}: Option[byte]

proc clearPendingByte*() =
  ## Drop any byte waiting to be re-injected as the next event's first byte.
  ## Call this from raw-mode toggles to prevent stale bytes from leaking
  ## across mode transitions.
  pendingByte = none(byte)

# Tracks whether Terminal.enableRawMode has pinned stdin to O_NONBLOCK for the
# lifetime of the current raw-mode session. When true, pollKey/readKeyInput
# skip the per-tick fcntl(F_GETFL)+F_SETFL dance entirely — without this flag
# they would still pay an F_GETFL on every tick just to learn the pin state.
#
# The flag is thread-local but the underlying stdin O_NONBLOCK state is
# process-global; in multi-threaded readers the flag only short-circuits the
# thread that owns raw mode. Other threads correctly fall back to per-tick
# fcntl toggling.
var stdinNonBlockingPinned {.threadvar.}: bool

proc setStdinNonBlockingPinned*(pinned: bool) =
  ## Mark stdin as pinned to non-blocking mode by the raw-mode owner.
  ## Called by Terminal.enableRawMode/disableRawMode; event readers consult
  ## this flag to short-circuit the per-tick fcntl toggle.
  stdinNonBlockingPinned = pinned

proc isStdinNonBlockingPinned*(): bool {.inline.} =
  ## Read-only accessor for the pin flag, intended for tests and diagnostics.
  stdinNonBlockingPinned

# Blocking I/O helper functions
proc readByteBlocking(): tuple[success: bool, ch: char] =
  ## Read a single byte in blocking mode
  ## Returns (success, char) where success is true if read succeeded
  if pendingByte.isSome:
    let b = pendingByte.get
    pendingByte = none(byte)
    return (true, char(b))
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
        # Alt+key: terminals encode Alt by prefixing the key's usual bytes
        # with ESC (e.g. ESC 'a' = Alt+a). ASCII bytes map directly; a
        # high-bit byte starts a UTF-8 character that is assembled inline
        # because the closure-based `assembleUtf8Char` cannot be used here —
        # async callers must `await` each byte read.
        if first.ch.byte < 0x80:
          Event(kind: Key, key: mapAltKey(first.ch))
        else:
          let expectedLen = utf8ByteLength(first.ch.byte)
          var contBytes: seq[byte] = @[]
          var wellFormed = expectedLen > 0
          while wellFormed and contBytes.len < expectedLen - 1:
            let cont = readByte
            if cont.success and isUtf8ContinuationByte(cont.ch.byte):
              contBytes.add(cont.ch.byte)
            else:
              # Truncated or ill-formed sequence. Unlike the plain-key UTF-8
              # path there is no pushback channel shared by sync and async
              # callers, so an invalid continuation byte is dropped rather
              # than re-injected as the next event's first byte.
              wellFormed = false
          let text =
            if wellFormed:
              buildUtf8String(first.ch.byte, contBytes)
            else:
              Utf8ReplacementChar
          Event(kind: Key, key: KeyEvent(code: Char, char: text, modifiers: {Alt}))

# UTF-8 helper functions (using shared logic from utf8_utils module)
proc readUtf8Char(firstByte: byte): Utf8AssemblyResult =
  ## Read a complete UTF-8 character given its first byte (blocking mode).
  ## Thin stdin-backed adapter over `assembleUtf8Char`; see that proc for
  ## the full return-value contract (text + optional leftover byte). The
  ## continuation-byte reader does NOT consult `pendingByte` — that buffer
  ## is reserved for fresh event start bytes.
  assembleUtf8Char(
    firstByte,
    proc(): tuple[ok: bool, b: byte] =
      var nextByte: char
      let bytesRead = tryRecover(
        proc(): int =
          stdin.readBuffer(addr nextByte, 1),
        fallback = 0,
      )
      if bytesRead == 1:
        (true, nextByte.byte)
      else:
        (false, 0.byte),
  )

proc readUtf8CharNonBlocking(firstByte: byte): Utf8AssemblyResult =
  ## Read a complete UTF-8 character in non-blocking mode. Thin stdin-backed
  ## adapter over `assembleUtf8Char`. EAGAIN/EWOULDBLOCK, other read errors,
  ## and short reads all collapse to "truncated sequence" and yield U+FFFD
  ## with no leftover.
  assembleUtf8Char(
    firstByte,
    proc(): tuple[ok: bool, b: byte] =
      var nextByte: char
      let bytesRead = read(STDIN_FILENO, addr nextByte, 1)
      if bytesRead == 1:
        (true, nextByte.byte)
      else:
        (false, 0.byte),
  )

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
    let assembly = readUtf8Char(ch.byte)
    if assembly.leftover.isSome:
      # Resync byte: an invalid continuation that should be processed as the
      # first byte of the next event (Unicode §3.9 best practice). Stash it
      # for the next readByteBlocking call to consume.
      pendingByte = some(assembly.leftover.get)
    if assembly.text.len > 0:
      return Event(kind: Key, key: KeyEvent(code: Char, char: assembly.text))
    else:
      # Invalid UTF-8 start byte — emit U+FFFD so Char events always carry
      # a valid UTF-8 codepoint (see KeyEvent invariant).
      return Event(kind: Key, key: KeyEvent(code: Char, char: Utf8ReplacementChar))
  except IOError:
    return Event(kind: Unknown)

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
  if pendingByte.isSome:
    let b = pendingByte.get
    pendingByte = none(byte)
    return (true, char(b), false)
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

proc readByteWithTimeoutNonBlocking(
    timeoutUs: int = 50000
): tuple[success: bool, ch: char, isTimeout: bool] =
  ## Wait up to `timeoutUs` for stdin to become readable, then read one byte.
  ## All non-blocking sub-parsers (escape, mouse, paste) read continuation bytes
  ## through this, so a byte split across packets (slow SSH/tmux) is still picked
  ## up rather than misread as a timeout. A buffered `pendingByte` skips the wait.
  if pendingByte.isSome:
    return readByteNonBlocking(STDIN_FILENO)

  var readSet: TFdSet
  FD_ZERO(readSet)
  FD_SET(STDIN_FILENO, readSet)
  # select(2) rejects tv_usec >= 1_000_000 with EINVAL, so carry whole seconds.
  var timeout = Timeval(
    tv_sec: Time(timeoutUs div 1_000_000), tv_usec: Suseconds(timeoutUs mod 1_000_000)
  )
  if select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout) <= 0:
    # Timeout or error - no further byte of the sequence has arrived.
    return (false, '\0', true)

  readByteNonBlocking(STDIN_FILENO)

# Non-blocking mouse event parsing

proc parseMouseEventX10NonBlocking(): Event =
  ## Parse X10 mouse format: ESC[Mbxy (non-blocking mode)
  ## where b is button byte, x,y are coordinate bytes.
  ## Each byte is awaited per-byte so a split sequence is still assembled.
  var data: array[3, char]

  for i in 0 .. 2:
    let readResult = readByteWithTimeoutNonBlocking()
    if not readResult.success:
      # Timeout or error - incomplete sequence
      return Event(kind: Unknown)

    data[i] = readResult.ch

  # Use shared parsing logic - no duplication with async version!
  return parseMouseDataX10(data).toEvent()

proc parseMouseEventSGRNonBlocking(): Event =
  ## Parse SGR mouse format: ESC[<button;x;y;M/m (non-blocking mode)
  ## M for press, m for release.
  ## Each byte is awaited per-byte so a split sequence is still assembled.
  var buffer: string
  var ch: char
  var readCount = 0

  # Read until we get M or m, with safety limits
  while readCount < MaxSGRMouseReadBytes:
    let readResult = readByteWithTimeoutNonBlocking()
    if not readResult.success:
      # Timeout or error - incomplete sequence
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
# Shares the paste-end state machine with the blocking version; differs only in
# the byte source (readByteWithTimeoutNonBlocking, 1s per byte).

proc readPasteContentNonBlocking(): string =
  ## Read paste content until ESC[201~, awaiting each byte with a 1s timeout.
  ## Returns whatever has been buffered if the timeout fires.
  result = ""
  var state = PesNone
  var pending = ""

  while true:
    let r = readByteWithTimeoutNonBlocking(1_000_000) # 1s per byte
    if not r.success:
      result.add(pending) # timeout/error: flush what we have
      return

    if stepPasteEnd(state, pending, r.ch, result):
      return

# Non-blocking event reading
proc readKeyInput*(): Option[Event] =
  ## Read a single key input event (non-blocking)
  ## Returns none(Event) if no input is available or on error
  ##
  ## Inside an active raw-mode session `stdinNonBlockingPinned` is true and
  ## the entire fcntl(2) toggle is skipped. Standalone callers still get the
  ## legacy auto-toggle behavior.
  let pinned = stdinNonBlockingPinned
  var flags: FdFlags
  var needRestore = false
  # Ensure stdin is O_NONBLOCK before any raw fd read below. This path issues
  # unguarded reads that assume non-blocking mode: the first readByteNonBlocking,
  # and — for a multibyte lead byte — readUtf8CharNonBlocking's continuation
  # read(2) (only the ESC/mouse/paste sub-parsers go through the select()-gated
  # readByteWithTimeoutNonBlocking). A stashed pendingByte can itself be a UTF-8
  # lead byte (e.g. the 0xC3 leftover of a 0xC3 0xC3 pair), so the toggle is
  # still required when one is pending; skipping it would let that continuation
  # read block indefinitely on a blocking fd.
  if not pinned:
    let fdFlags = getFdFlags(STDIN_FILENO)
    if fdFlags.isNone:
      return none(Event)
    flags = fdFlags.get()
    if (flags.originalFlags and O_NONBLOCK) == 0:
      if not flags.setNonBlocking():
        return none(Event)
      needRestore = true

  let readResult = readByteNonBlocking(STDIN_FILENO)

  # No data available or error
  if not readResult.success:
    if needRestore:
      flags.restore()
    return none(Event)

  let ch = readResult.ch

  # Restore flags before returning (no-op when stdin was pinned by raw mode
  # or was already non-blocking when we entered)
  defer:
    if needRestore:
      flags.restore()

  # Escape sequences via the unified routing template (non-blocking I/O).
  # The first post-ESC byte uses a short 20ms wait to tell a standalone ESC from
  # the start of a sequence; continuation bytes use the standard 50ms per-byte
  # wait, so a CSI split across packets (slow SSH/tmux) is assembled instead of
  # decaying into a phantom Escape + stray Char.
  if ch == '\x1b':
    let firstByte = readByteWithTimeoutNonBlocking(20000)
    if not firstByte.success:
      return some(Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b")))

    # First byte is already in hand; yield it once, then fall through to the
    # per-byte reader — avoids a redundant second select() for it.
    var firstPending = some(firstByte)
    proc nextEscByte(): tuple[success: bool, ch: char, isTimeout: bool] =
      if firstPending.isSome:
        result = firstPending.get
        firstPending = none(typeof(firstByte))
      else:
        result = readByteWithTimeoutNonBlocking()

    return some(
      parseEscapeSequenceUnified(
        nextEscByte(),
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
  let assembly = readUtf8CharNonBlocking(ch.byte)
  if assembly.leftover.isSome:
    # Resync byte: re-inject as the first byte of the next event (§3.9).
    pendingByte = some(assembly.leftover.get)
  if assembly.text.len > 0:
    return some(Event(kind: Key, key: KeyEvent(code: Char, char: assembly.text)))
  else:
    # Invalid UTF-8 start byte — emit U+FFFD (KeyEvent.char invariant).
    return some(Event(kind: Key, key: KeyEvent(code: Char, char: Utf8ReplacementChar)))

proc pollKey*(): Event =
  ## Poll for a key event (non-blocking).
  ##
  ## Thin wrapper over `readKeyInput` that collapses `none(Event)` to
  ## `Event(kind: Unknown)`. All fcntl management (raw-mode pin fast-path,
  ## standalone auto-toggle, F_GETFL failure handling) lives in `readKeyInput`
  ## so the two entry points cannot drift apart in behavior or syscall cost.
  let opt = readKeyInput()
  if opt.isSome:
    opt.get
  else:
    Event(kind: Unknown)

# Check if input is available
proc hasInput*(): bool =
  ## Check if input is available without blocking
  # A stashed UTF-8 resync byte is a real keystroke that the next readKey will
  # emit; select() can't see it because it never reached the fd. Report it as
  # available so the byte isn't stranded until fresh fd input arrives.
  if pendingByte.isSome:
    return true

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
  # A stashed UTF-8 resync byte already constitutes an available event; return
  # immediately rather than sleeping out the timeout while it sits invisible to
  # select().
  if pendingByte.isSome:
    return true

  var readSet: TFdSet
  FD_ZERO(readSet)
  FD_SET(STDIN_FILENO, readSet)

  var timeout = Timeval(
    tv_sec: Time(timeoutMs div 1000), tv_usec: Suseconds((timeoutMs mod 1000) * 1000)
  )

  # Use select to check if input is available with timeout
  let r = select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout)
  return r > 0
