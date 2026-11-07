## Event handling
##
## This module provides comprehensive event handling for keyboard input,
## including escape sequences and arrow keys for POSIX systems.

import std/[os, posix, options, strutils, strformat, atomics, monotimes]
from std/times import initDuration, inMilliseconds, inMicroseconds

import geometry, mouse_logic, utf8_utils, key_logic, escape_sequence_logic
from terminal_common import
  ReadOutcome, classifyReadResult, canQueryCursor, CursorPositionQuerySeq
from output_stream import flushStdio, writeStream

# Re-export types to maintain API compatibility
export mouse_logic.MouseButton, mouse_logic.MouseEventKind, mouse_logic.KeyModifier
export key_logic.KeyCode, key_logic.KeyEvent
export utf8_utils except wellFormedSeqLen, toRunesSanitized

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
    InputClosed
      ## Stdin has ended (end of file, or a read error on a fd that is not a
      ## live terminal), so no more input will arrive. The event loop delivers
      ## it once, to the global handler only, and keeps running at its normal
      ## pace.
      ##
      ## The first read path to see the end owns that one event; a bulk
      ## `readStdinAsync` consumes it silently, leaving `isClosed` as the
      ## durable signal there. `waitForKey` / `waitForKeyAsync` report it on
      ## every call while the input stays closed, so a caller loop ends instead
      ## of waiting for a key that cannot arrive.
      ##
      ## Only Linux reads a hung-up terminal as ended; XNU keeps answering
      ## `isatty` on the zombie pty, so it stays a live input there.
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
    of Resize, FocusIn, FocusOut, Quit, InputClosed, Unknown:
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
  of InputClosed:
    "Event(InputClosed)"
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

# Typeahead a cursor position query read past its reply. Every stdin byte read
# takes it before the fd; `pendingByte` comes first, as it is always older.
var queuedInput {.threadvar.}: string

proc clearPendingByte*() =
  ## Drop any byte waiting to be re-injected as the next event's first byte,
  ## and any queued typeahead. Call this from raw-mode toggles to prevent stale
  ## bytes from leaking across mode transitions.
  pendingByte = none(byte)
  queuedInput = ""

proc unreadInput(bytes: string) =
  ## Put bytes read ahead within an event back in front of the queue.
  queuedInput = bytes & queuedInput

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

# Set once a read finds stdin gone (`roClosed`); stdin is not read again until
# `clearInputClosed`. Process-wide like fd 0, so a clear from any thread counts.
var inputClosed: Atomic[bool]
var inputCloseReported: Atomic[bool]

proc clearInputClosed*() =
  ## Forget an earlier end of input. `Terminal.enableRawMode` calls this once it
  ## succeeds, and a caller that replaces stdin's fd must do the same.
  inputClosed.store(false)
  inputCloseReported.store(false)

proc takeCloseNotice(): bool =
  ## True exactly once after stdin closes; the caller then emits the one
  ## `InputClosed` event.
  inputClosed.load and not inputCloseReported.exchange(true)

proc readRawByte(
    fd: cint
): tuple[success: bool, ch: char, wouldBlock: bool, interrupted: bool] =
  ## One `read(2)` of a byte from `fd`, latching `inputClosed` when it finds the
  ## end. Reads the fd directly, not Nim's `stdin` File, so bytes left in the C
  ## stdio buffer are not seen. Queued typeahead goes before stdin's fd.
  if fd == STDIN_FILENO and queuedInput.len > 0:
    let ch = queuedInput[0]
    queuedInput = queuedInput[1 ..^ 1]
    return (true, ch, false, false)
  if inputClosed.load:
    return (false, '\0', false, false)
  var ch: char
  let bytesRead = read(fd, addr ch, 1)
  let wouldBlock = bytesRead == -1 and (errno == EAGAIN or errno == EWOULDBLOCK)
  let interrupted = bytesRead == -1 and errno == EINTR
  case classifyReadResult(bytesRead, fd)
  of roData:
    (true, ch, false, false)
  of roNoData:
    (false, '\0', wouldBlock, interrupted)
  of roClosed:
    inputClosed.store(true)
    (false, '\0', false, false)

proc waitForStdin(timeoutUs: int): bool =
  ## Wait up to `timeoutUs` for stdin to become readable. A signal does not end
  ## the wait, so a resize cannot split a sequence.
  let deadline = getMonoTime() + initDuration(microseconds = timeoutUs)
  while true:
    var readSet: TFdSet
    FD_ZERO(readSet)
    FD_SET(STDIN_FILENO, readSet)
    let left = max((deadline - getMonoTime()).inMicroseconds, 0)
    # select(2) rejects tv_usec >= 1_000_000 with EINVAL, so carry whole seconds.
    var timeout =
      Timeval(tv_sec: Time(left div 1_000_000), tv_usec: Suseconds(left mod 1_000_000))
    let r = select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout)
    if r > 0:
      return true
    if r == 0 or errno != EINTR:
      return false

# Blocking I/O helper functions
proc readNextByteBlocking(
    waitUs: int = SequenceByteWaitMs * 1000
): tuple[success: bool, ch: char] =
  ## Read the next byte of a sequence, retrying after a signal so a resize
  ## cannot split it. On raw mode's non-blocking stdin it waits like
  ## `readByteWithTimeoutNonBlocking`, so a byte split off by the link is still
  ## read. `pendingByte` is not consulted: it belongs to event start bytes.
  while true:
    let r = readRawByte(STDIN_FILENO)
    if r.wouldBlock:
      if not waitForStdin(waitUs):
        return (false, '\0')
    elif not r.interrupted:
      return (r.success, r.ch)

proc readDrainByteBlocking(): tuple[success: bool, ch: char] =
  ## Read a tail byte only if one is available; an ill-formed key must not
  ## wait for bytes that may never arrive.
  if queuedInput.len == 0:
    var readSet: TFdSet
    FD_ZERO(readSet)
    FD_SET(STDIN_FILENO, readSet)
    var timeout = Timeval(tv_sec: Time(0), tv_usec: Suseconds(0))
    if select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout) <= 0:
      return (false, '\0')
  readNextByteBlocking()

proc readByteBlocking(): tuple[success: bool, ch: char] =
  ## Read the first byte of an event, taking a stashed UTF-8 resync byte before
  ## stdin. A signal ends the read with no byte, so the caller can react to it.
  if pendingByte.isSome:
    let b = pendingByte.get
    pendingByte = none(byte)
    return (true, char(b))
  let r = readRawByte(STDIN_FILENO)
  (r.success, r.ch)

proc parseMouseEventX10(): Event =
  ## Parse X10 mouse format: ESC[Mbxy (blocking mode)
  ## where b is button byte, x,y are coordinate bytes
  ##
  ## This function handles I/O and delegates parsing to shared mouse_logic module
  var data: array[3, char]
  # A byte missing mid-sequence (end of input, or a transient failure) reports
  # no event.
  for i in 0 .. 2:
    let r = readNextByteBlocking()
    if not r.success:
      return Event(kind: Unknown)
    data[i] = r.ch

  # Use shared parsing logic - no duplication with async version!
  return parseMouseDataX10(data).toEvent()

proc parseMouseEventSGR(): Event =
  ## Parse SGR mouse format: ESC[<button;x;y;M/m (blocking mode)
  ## M for press, m for release
  ##
  ## This function handles I/O and delegates parsing to shared mouse_logic module
  var buffer: string
  var ch: char
  var readCount = 0

  # Read until we get M or m, with safety limits
  while readCount < MaxSGRMouseReadBytes:
    let r = readNextByteBlocking()
    if not r.success:
      break
    ch = r.ch
    readCount.inc()
    if ch == 'M' or ch == 'm':
      break
    buffer.add(ch)

  if ch != 'M' and ch != 'm':
    # If we didn't find a terminator, return unknown event. A terminator found on
    # the MaxSGRMouseReadBytes-th byte is still valid, so guard on the terminator
    # alone: if the loop instead exited at the byte limit, `ch` holds a
    # non-terminator byte and this check rejects it anyway.
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

# Bracketed paste content reader (blocking mode)
# Uses the shared paste-end state machine from escape_sequence_logic.

proc readPasteContentBlocking(): string =
  ## Read all content until paste end sequence ESC[201~ (blocking mode).
  ## Returns the pasted text without the end sequence.
  result = ""
  var state = PesNone
  var pending = ""
  while true:
    let r = readNextByteBlocking(PasteByteWaitMs * 1000)
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
# Each parameter is an *expression* re-evaluated at every textual occurrence in
# the template body. Synchronous callers pass direct proc calls
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
#   unread        -> a sync proc taking a string, passed without arguments; puts
#                    those bytes back in front of the input, so `readByte`
#                    returns them next
#   drainByte     -> same shape as `readByte`; skips the tail of an ill-formed
#                    character and returns `success = false` instead of waiting

template parseEscapeSequenceUnified*(
    readByte, readPaste, parseMouseX10, parseMouseSGR, unread, drainByte: untyped
): Event =
  ## Parse an ESC sequence (ESC has already been consumed by the caller).
  ## For non-blocking callers, the post-ESC timeout check (standalone ESC vs
  ## start of a sequence) must be performed by the caller before invocation.
  ##
  ## A CSI sequence is read to its final byte, so one that no key maps to gives
  ## `Unknown` rather than turning its tail into keys. After `first`, every
  ## reader waits for each `readByte`: up to `SequenceByteWaitMs`, or without
  ## limit on a blocking stdin.
  ## Reading to the final byte covers a cursor position report
  ## (`CSI row ; col R`) that came after `queryCursorPosition` stopped waiting.
  ## A byte that cannot be in a sequence ends it and goes back.
  ##
  ## `ESC [` with no sequence byte after it is Alt+[, and `ESC O` with no final
  ## byte after it is Alt+Shift+O.
  block:
    let first = readByte
    if not first.success:
      Event(kind: Key, key: KeyEvent(code: KeyCode.Escape, char: "\x1b"))
    else:
      case first.ch
      of '[':
        let bracket = readByte
        if not bracket.success:
          Event(kind: Key, key: mapAltKey('['))
        else:
          case classifyBracketSequence(bracket.ch)
          of BskArrowKey, BskNavigationKey:
            let p = processSimpleBracketSequence(bracket.ch, bracket.success)
            Event(kind: Key, key: p.keyEvent)
          of BskMouseX10:
            parseMouseX10
          of BskMouseSGR:
            parseMouseSGR
          of BskFocusIn:
            Event(kind: FocusIn)
          of BskFocusOut:
            Event(kind: FocusOut)
          of BskLinuxFunctionKey:
            let final = readByte
            let key =
              if final.success:
                mapLinuxFunctionKey(final.ch)
              else:
                escapeKey()
            if key.code != Escape:
              Event(kind: Key, key: key)
            else:
              if final.success:
                unread($final.ch)
              Event(kind: Unknown)
          of BskGeneric:
            var scan = CsiScan()
            scan.feed(bracket.ch)
            while scan.state == cssReading:
              let next = readByte
              if next.success:
                scan.feed(next.ch)
              else:
                scan.state = cssTruncated
            if scan.state == cssStray:
              unread($scan.stray)
            if scan.state == cssStray and scan.length == 1:
              Event(kind: Key, key: mapAltKey('['))
            else:
              let action = scan.action()
              case action.kind
              of cakKey:
                Event(kind: Key, key: action.key)
              of cakPaste:
                Event(kind: Paste, pastedText: readPaste)
              of cakQuit:
                Event(kind: Quit)
              of cakIgnore:
                Event(kind: Unknown)
      of 'O':
        let vt = readByte
        if vt.success and vt.ch in Ss3FinalBytes:
          let action = ss3Action(vt.ch)
          if action.kind == cakKey:
            Event(kind: Key, key: action.key)
          else:
            Event(kind: Unknown)
        else:
          if vt.success:
            unread($vt.ch)
          Event(kind: Key, key: mapAltKey('O'))
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
          # Structural length also covers leads `utf8ByteLength` rejects but
          # `std/unicode` still decodes; their tail must be drained too.
          let sequenceLen =
            if expectedLen > 0:
              expectedLen
            else:
              structuralUtf8Length(first.ch.byte)
          let (secondLo, secondHi) = utf8SecondByteRange(first.ch.byte)
          var contBytes: seq[byte] = @[]
          var wellFormed = expectedLen > 0
          var rejected = false
            ## A continuation byte was rejected; its tail is still in the stream.
          while wellFormed and contBytes.len < expectedLen - 1:
            let cont = readByte
            # Reject overlong, surrogate and out-of-range second bytes, as
            # `assembleUtf8Char` does.
            if cont.success and isUtf8ContinuationByte(cont.ch.byte) and (
              contBytes.len > 0 or
              (cont.ch.byte >= secondLo and cont.ch.byte <= secondHi)
            ):
              contBytes.add(cont.ch.byte)
            else:
              # Truncated or ill-formed. Drop an out-of-range continuation
              # byte; unread any other byte, which starts the next sequence.
              wellFormed = false
              if cont.success:
                if isUtf8ContinuationByte(cont.ch.byte):
                  rejected = true
                else:
                  unread($cont.ch)
          # Skip the rest of the malformed character so it stays one event;
          # a non-continuation byte starts the next sequence.
          let consumed = 1 + contBytes.len + (if rejected: 1 else: 0)
          if rejected or (expectedLen == 0 and sequenceLen > 1):
            for _ in 0 ..< sequenceLen - consumed:
              let rest = drainByte
              if not rest.success:
                break
              if isUtf8ContinuationByte(rest.ch.byte):
                continue
              unread($rest.ch)
              break
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
      let r = readNextByteBlocking()
      if r.success:
        (true, r.ch.byte)
      else:
        (false, 0.byte),
  )

# Advanced key reading with escape sequence support
proc readKey*(): Event =
  ## Read a key event (blocking mode).
  ##
  ## Returns `Event(kind: InputClosed)` once when stdin has ended, then
  ## `Unknown`. A caller loop must leave on `InputClosed` or use `waitForKey`:
  ## a closed stdin then answers `Unknown` without a syscall, so the loop would
  ## spin. Reads never raise; a failed read on a live terminal (such as a
  ## cooked-mode Ctrl-D) also returns `Unknown` and does not end the input.
  ##
  ## Reads fd 0 directly: bytes Nim's `stdin` File has already buffered are not
  ## seen, so do not mix the two.
  let readResult = readByteBlocking()
  if not readResult.success:
    if takeCloseNotice():
      return Event(kind: InputClosed)
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
      readNextByteBlocking(),
      readPasteContentBlocking(),
      parseMouseEventX10(),
      parseMouseEventSGR(),
      unreadInput,
      readDrainByteBlocking(),
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
  let r = readRawByte(fd)
  (r.success, r.ch, r.wouldBlock)

proc readByteWithTimeoutNonBlocking(
    timeoutUs: int = SequenceByteWaitMs * 1000
): tuple[success: bool, ch: char, isTimeout: bool] =
  ## Wait up to `timeoutUs` for stdin to become readable, then read one byte.
  ## All non-blocking sub-parsers (escape, mouse, paste, UTF-8) read continuation
  ## bytes through this, so a byte split across packets (slow SSH/tmux) is still picked
  ## up rather than misread as a timeout. A buffered `pendingByte` or queued
  ## typeahead skips the wait.
  if pendingByte.isSome or queuedInput.len > 0:
    return readByteNonBlocking(STDIN_FILENO)

  if waitForStdin(timeoutUs):
    return readByteNonBlocking(STDIN_FILENO)
  (false, '\0', true)

proc readUtf8CharNonBlocking(firstByte: byte): Utf8AssemblyResult =
  ## Read a complete UTF-8 character in non-blocking mode. Thin stdin-backed
  ## adapter over `assembleUtf8Char`. A timeout, other read errors, and short
  ## reads all collapse to "truncated sequence" and yield U+FFFD with no
  ## leftover. An end of input latches the close like any other read.
  assembleUtf8Char(
    firstByte,
    proc(): tuple[ok: bool, b: byte] =
      let r = readByteWithTimeoutNonBlocking()
      if r.success:
        (true, r.ch.byte)
      else:
        (false, 0.byte),
  )

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

  if ch != 'M' and ch != 'm':
    # If we didn't find a terminator, return unknown event. A terminator found on
    # the MaxSGRMouseReadBytes-th byte is still valid, so guard on the terminator
    # alone: if the loop instead exited at the byte limit, `ch` holds a
    # non-terminator byte and this check rejects it anyway.
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
    let r = readByteWithTimeoutNonBlocking(PasteByteWaitMs * 1000)
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
  # Ensure stdin is O_NONBLOCK before the first readByteNonBlocking, which is not
  # guarded by select() like readByteWithTimeoutNonBlocking.
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

  # No data available, or stdin has ended
  if not readResult.success:
    if needRestore:
      flags.restore()
    if takeCloseNotice():
      return some(Event(kind: InputClosed))
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
        unreadInput,
        readByteWithTimeoutNonBlocking(0),
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
  # available so the byte isn't stranded until fresh fd input arrives. Queued
  # typeahead has already left the fd too.
  if pendingByte.isSome or queuedInput.len > 0:
    return true
  if inputClosed.load:
    return not inputCloseReported.load

  # Use select to check if input is available
  var readSet: TFdSet
  FD_ZERO(readSet)
  FD_SET(STDIN_FILENO, readSet)

  var timeout = Timeval(tv_sec: Time(0), tv_usec: 0)
  select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout) > 0

# Event loop utilities
proc waitForKey*(): Event =
  ## Wait for a key press (blocking).
  ##
  ## Returns `Event(kind: InputClosed)` while stdin is closed, rather than
  ## waiting for a key that cannot arrive.
  while true:
    let event = readKey()
    if event.kind != Unknown:
      return event
    if inputClosed.load:
      discard takeCloseNotice()
      return Event(kind: InputClosed)
    sleep(10) # Small delay to prevent busy waiting

proc waitForAnyKey*(): bool =
  ## Wait for any key press. False on a quit request or once stdin has ended;
  ## use `waitForKey` to tell the two apart.
  let event = waitForKey()
  return event.kind notin {Quit, InputClosed}

# Event polling with timeout
proc pollEvents*(timeoutMs: int): bool =
  ## Poll for available events with a timeout
  ## Returns true if events are available, false if timeout occurred
  ## Similar to crossterm::event::poll()
  # A stashed UTF-8 resync byte already constitutes an available event; return
  # immediately rather than sleeping out the timeout while it sits invisible to
  # select(). So does queued typeahead.
  if pendingByte.isSome or queuedInput.len > 0:
    return true
  if inputClosed.load:
    if not inputCloseReported.load:
      return true # The close itself is pending; `readKeyInput` emits it.
    # Sleep out the timeout rather than return at once, or a poll loop such as
    # `App.tick` would spin.
    if timeoutMs > 0:
      sleep(timeoutMs)
    return false

  var readSet: TFdSet
  FD_ZERO(readSet)
  FD_SET(STDIN_FILENO, readSet)

  var timeout = Timeval(
    tv_sec: Time(timeoutMs div 1000), tv_usec: Suseconds((timeoutMs mod 1000) * 1000)
  )

  # Use select to check if input is available with timeout
  let r = select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout)
  return r > 0

# Cursor position query

proc readCursorReply(timeoutMs: int): Option[Position] =
  ## Read stdin until a cursor position report arrives or `timeoutMs` passes.
  ## Other bytes read on the way are queued for the event readers. Typeahead
  ## queued before the call is not searched.
  # Capped so the deadline cannot overflow and the time left fits a cint.
  let deadline = getMonoTime() + initDuration(milliseconds = min(timeoutMs, int32.high))
  var bytes = ""
  try:
    var chunk = newString(64)
    while not inputClosed.load:
      var pfd = TPollfd(fd: STDIN_FILENO, events: POLLIN)
      let left = max((deadline - getMonoTime()).inMilliseconds, 0)
      let r = poll(addr pfd, 1, left.cint)
      if r < 0 and errno == EINTR:
        continue
      if r <= 0:
        break
      let n = read(STDIN_FILENO, addr chunk[0], chunk.len)
      case classifyReadResult(n, STDIN_FILENO)
      of roData:
        bytes.add(chunk[0 ..< n])
      of roNoData:
        if n == 0:
          break # a terminal that reads empty sends no reply either
      of roClosed:
        inputClosed.store(true)
      let reply = extractCursorReply(bytes)
      if reply.found:
        bytes = reply.typeahead
        return some(pos(reply.col, reply.row))
  finally:
    queuedInput.add(bytes)

proc queryCursorPosition*(timeoutMs: int): Option[Position] =
  ## Ask the terminal where the cursor is (DSR 6) and wait up to `timeoutMs`
  ## for the reply. Returns the 0-based position, or `none` if no reply came in
  ## time. Returns `none` at once unless stdin and stdout are terminals and
  ## stdin is in raw mode: otherwise the reply is echoed or held until Enter.
  ##
  ## Keys typed while waiting stay queued for the event readers. A reply that
  ## comes after the deadline is taken by the next query if that comes first;
  ## otherwise the event readers turn it into one `Unknown` event, as they do
  ## the modified F3 keys of the same shape (`CSI 1;n R`). Reads stdin, so
  ## nothing else may read it meanwhile; `App` reads input only inside its tick.
  if inputClosed.load or not canQueryCursor():
    return none(Position)
  if not flushStdio():
    return none(Position)
  if writeStream(CursorPositionQuerySeq, {}) != CursorPositionQuerySeq.len:
    return none(Position)
  readCursorReply(timeoutMs)
