## Escape sequence parsing logic (I/O independent)
##
## This module contains shared escape sequence parsing logic used by
## blocking, non-blocking, and async parsers. It eliminates code duplication
## by separating parsing logic from I/O operations.

import std/[strutils, unicode]

import key_logic
export key_logic.KeyEvent, key_logic.KeyCode
export key_logic.mapVT100FunctionKey, key_logic.mapLinuxFunctionKey
export key_logic.mapFunctionKey
export key_logic.mapNumericKeyCode, key_logic.parseModifierCode
export key_logic.applyModifiers, key_logic.mapArrowKey, key_logic.mapNavigationKey

type
  EscapeResult* = object ## Result of escape sequence processing
    isValid*: bool
    keyEvent*: KeyEvent

  CursorReply* = object ## A cursor position report taken out of input bytes
    found*: bool
    row*, col*: int ## 0-based
    typeahead*: string ## the other bytes, in order

  CursorReplyMatch = enum
    ## How the bytes after `ESC [` compare with a cursor position report
    crmPartial ## a prefix of `row ; col R`
    crmComplete
    crmNone

  CsiScanState* = enum
    ## Where the bytes after `ESC [` have got to
    cssReading
    cssDone ## ended by a final byte
    cssTruncated ## no more bytes arrived, or `MaxCsiScanBytes` did
    cssStray ## a byte that cannot be in a CSI sequence ended it

  CsiScan* = object ## A CSI sequence read up to its final byte
    state*: CsiScanState
    params: string
    length: int
    intermediates: bool
    overflow: bool
    final: char
    stray*: char ## the byte that ended a `cssStray` scan, not part of the sequence

  CsiActionKind* = enum
    ## What a CSI sequence means to the event readers
    cakIgnore ## not an input event
    cakKey
    cakPaste ## bracketed paste content follows
    cakQuit ## Ctrl+C

  CsiAction* = object ## The meaning of a CSI sequence
    kind*: CsiActionKind
    key*: KeyEvent

  PasteEndState* = enum
    ## State machine for detecting paste end sequence ESC[201~
    PesNone ## Not in sequence
    PesEsc ## Saw ESC
    PesBracket ## Saw ESC [
    Pes2 ## Saw ESC [ 2
    Pes20 ## Saw ESC [ 2 0
    Pes201 ## Saw ESC [ 2 0 1

proc escapeKey*(): KeyEvent {.inline.} =
  ## Create an Escape key event
  KeyEvent(code: KeyCode.Escape, char: "\x1b")

proc escapeResult*(): EscapeResult {.inline.} =
  ## Create an EscapeResult with Escape key (fallback for invalid sequences)
  EscapeResult(isValid: true, keyEvent: escapeKey())

type BracketSequenceKind* = enum
  ## Classification of bracket escape sequences after ESC[
  BskArrowKey # ESC[A, ESC[B, ESC[C, ESC[D
  BskNavigationKey # ESC[H, ESC[F, ESC[Z
  BskMouseX10 # ESC[M
  BskMouseSGR # ESC[<
  BskFocusIn # ESC[I
  BskFocusOut # ESC[O
  BskLinuxFunctionKey # ESC [ [ A..E, F1-F5 on the Linux console
  BskGeneric # anything else, read to its final byte with `CsiScan`

proc classifyBracketSequence*(final: char): BracketSequenceKind =
  ## Classify bracket sequence type by character after ESC[
  case final
  of 'I':
    return BskFocusIn
  of 'O':
    return BskFocusOut
  of 'M':
    return BskMouseX10
  of '<':
    return BskMouseSGR
  of '[':
    return BskLinuxFunctionKey
  else:
    discard

  let arrowKey = mapArrowKey(final)
  if arrowKey.code != KeyCode.Escape:
    return BskArrowKey

  let navKey = mapNavigationKey(final)
  if navKey.code != KeyCode.Escape:
    return BskNavigationKey

  return BskGeneric

proc processSimpleBracketSequence*(final: char, isValid: bool): EscapeResult =
  ## Process simple bracket sequences: ESC[A/H (arrow/navigation keys)
  if not isValid:
    return escapeResult()

  # Try arrow keys first
  let arrowKey = mapArrowKey(final)
  if arrowKey.code != KeyCode.Escape:
    return EscapeResult(isValid: true, keyEvent: arrowKey)

  # Try navigation keys
  let navKey = mapNavigationKey(final)
  if navKey.code != KeyCode.Escape:
    return EscapeResult(isValid: true, keyEvent: navKey)

  return escapeResult()

# CSI sequences (I/O independent)

const
  Ss3FinalBytes* = {'@' .. '~'}
  SequenceByteWaitMs* = 50
    ## how long a reader waits for the next byte of a sequence or character
  PasteByteWaitMs* = 1000 ## the same for the next byte of paste content
  MaxCsiBytes = 32 ## longer parameters are read, but ignored
  MaxCsiScanBytes* = 64
    ## A scan gives up here. At `SequenceByteWaitMs` a byte, this bounds how long
    ## a stream of parameter bytes holds a reader to 3.2 s (a blocking stdin has
    ## no per-byte limit).
  MaxCsiNumber = 0x110000 ## past every codepoint; bigger numbers stop here

proc feed*(scan: var CsiScan, ch: char) =
  ## Advance `scan` by one byte after `ESC [`.
  case ch
  of '\x30' .. '\x3f':
    if scan.params.len < MaxCsiBytes:
      scan.params.add(ch)
    else:
      scan.overflow = true
  of '\x20' .. '\x2f':
    # rxvt ends Shift+Home and the like with `$`: `CSI 7 $`.
    if ch == '$' and not scan.intermediates and scan.params.len > 0 and
        scan.params.allCharsInSet(Digits):
      scan.state = cssDone
      scan.final = ch
    else:
      scan.intermediates = true
  of '\x40' .. '\x7e':
    scan.state = cssDone
    scan.final = ch
  else:
    scan.state = cssStray
    scan.stray = ch

  inc scan.length
  if scan.state == cssReading and scan.length >= MaxCsiScanBytes:
    scan.state = cssTruncated

proc csiFields(params: string): seq[seq[int]] =
  ## Split digits into `;` fields of `:` sub-fields. An empty one reads as 0.
  for field in params.split(';'):
    var values: seq[int]
    for value in field.split(':'):
      var number = 0
      for digit in value:
        number = min(number * 10 + digit.ord - '0'.ord, MaxCsiNumber)
      values.add(number)
    result.add(values)

proc at(fields: seq[seq[int]], field: int, sub = 0): int =
  if field < fields.len and sub < fields[field].len:
    fields[field][sub]
  else:
    0

proc keyAction(key: KeyEvent): CsiAction =
  CsiAction(kind: cakKey, key: key)

proc namedKeyAction(key: KeyEvent, modifiers: set[KeyModifier]): CsiAction =
  ## The `map*Key` procs answer Escape for a code they do not know.
  if key.code == Escape:
    CsiAction(kind: cakIgnore)
  elif key.code == BackTab:
    keyAction(applyModifiers(key, modifiers - {Shift}))
  else:
    keyAction(applyModifiers(key, modifiers))

proc shiftedCode(code, alternate: int): int =
  ## The character Shift produces: the alternate key the terminal sends, else
  ## the uppercase of an ASCII letter.
  if alternate >= 0x21 and alternate <= 0x7e or alternate >= 0xa0 and alternate <= 0xd7ff or
      alternate >= 0xf900 and alternate <= 0x10ffff:
    return alternate
  if code >= ord('a') and code <= ord('z'):
    return code - ord('a') + ord('A')
  code

proc ctrlAction(code: int): CsiAction =
  ## The event of the control byte Ctrl+`code` is everywhere else, so that
  ## Ghostty and others sending it as CSI u mean the same thing.
  let ch = char(code and 0x1f)
  case ch
  of '\x03':
    CsiAction(kind: cakQuit)
  of '\x1b':
    keyAction(escapeKey())
  else:
    let letter = mapCtrlLetterKey(ch)
    let number = mapCtrlNumberKey(ch)
    if letter.isCtrlKey:
      keyAction(letter.keyEvent)
    elif number.isCtrlKey:
      keyAction(number.keyEvent)
    else:
      keyAction(mapBasicKey(ch))

proc codepointAction(code, alternate: int, modifiers: set[KeyModifier]): CsiAction =
  ## The key of `CSI code : alternate ; modifiers u` and
  ## `CSI 27 ; modifiers ; code ~`.
  if modifiers == {Ctrl} and (code in 0x40 .. 0x5f or code in 0x61 .. 0x7a):
    return ctrlAction(code)

  case code
  of 9:
    if Shift in modifiers:
      keyAction(applyModifiers(KeyEvent(code: BackTab), modifiers - {Shift}))
    else:
      keyAction(applyModifiers(mapBasicKey('\t'), modifiers))
  of 8, 13, 32, 127:
    keyAction(applyModifiers(mapBasicKey(char(code)), modifiers))
  of 27:
    keyAction(applyModifiers(escapeKey(), modifiers))
  of 0x21 .. 0x7e, 0xa0 .. 0xd7ff, 0xf900 .. 0x10ffff:
    # Ctrl+letter is a chord, not text, and the legacy bytes carry no Shift.
    let charCode =
      if Shift in modifiers and Ctrl notin modifiers:
        shiftedCode(code, alternate)
      else:
        code
    keyAction(KeyEvent(code: Char, char: Rune(charCode).toUTF8, modifiers: modifiers))
  else:
    # The kitty protocol's functional keys are in the private use area.
    CsiAction(kind: cakIgnore)

proc cursorKeyAction(final: char, modifiers: set[KeyModifier]): CsiAction =
  let arrow = mapArrowKey(final)
  if arrow.code != Escape:
    namedKeyAction(arrow, modifiers)
  else:
    namedKeyAction(mapNavigationKey(final), modifiers)

proc ss3Action*(final: char): CsiAction =
  ## The meaning of `ESC O final`: F1-F4, or an arrow, Home or End from a
  ## terminal in application cursor mode (DECCKM).
  let function = mapVT100FunctionKey(final)
  if function.code != Escape:
    keyAction(function)
  else:
    cursorKeyAction(final, {})

proc action*(scan: CsiScan): CsiAction =
  ## The meaning of a finished scan. A sequence that was cut off, or that no key
  ## maps to, is ignored: its bytes are not input.
  const KeyParams = {'0' .. '9', ':', ';'}
  if scan.state != cssDone or scan.intermediates or scan.overflow or
      not scan.params.allCharsInSet(KeyParams):
    return CsiAction(kind: cakIgnore)

  let fields = csiFields(scan.params)
  const ReleaseEvent = 3 # kitty's `modifiers : event-type`
  if fields.at(1, 1) == ReleaseEvent:
    return CsiAction(kind: cakIgnore)

  # Super, Hyper and Meta have no `KeyModifier`. Without them a shortcut would
  # read as the plain key.
  const UnmappedModifiers = 8 or 16 or 32
  if (max(fields.at(1) - 1, 0) and UnmappedModifiers) != 0:
    return CsiAction(kind: cakIgnore)

  let modifiers = parseModifierCode(fields.at(1))
  case scan.final
  of 'u':
    codepointAction(fields.at(0), fields.at(0, 1), modifiers)
  of '~':
    let first = fields.at(0)
    case first
    of 27:
      codepointAction(fields.at(2), fields.at(2, 1), modifiers)
    of 200:
      if fields.len == 1 and fields[0].len == 1:
        CsiAction(kind: cakPaste)
      else:
        CsiAction(kind: cakIgnore)
    of 1 .. 9:
      # rxvt sends Home as 7~ and End as 8~.
      let key =
        case first
        of 7:
          KeyEvent(code: Home)
        of 8:
          KeyEvent(code: End)
        else:
          mapNumericKeyCode(char('0'.ord + first))
      namedKeyAction(key, modifiers)
    else:
      namedKeyAction(mapFunctionKey($first), modifiers)
  else:
    # `CSI 1 ; modifiers P/Q/S` are F1/F2/F4. R has the shape of a cursor
    # position report, so the modified F3 stays unreadable.
    if scan.final in {'P', 'Q', 'S'} and fields.len > 1 and fields.at(0) == 1:
      namedKeyAction(mapVT100FunctionKey(scan.final), modifiers)
    else:
      cursorKeyAction(scan.final, modifiers)

# Bracketed paste content reading (I/O independent state machine)

proc stepPasteEnd*(
    state: var PasteEndState, pending: var string, ch: char, output: var string
): bool =
  ## Advance the paste-end state machine by one byte.
  ##
  ## Bytes are buffered in `pending` while a candidate ESC[201~ sequence is
  ## being matched, and flushed into `output` if the match fails. Returns true
  ## when the paste end terminator (ESC[201~) is consumed; the caller should
  ## then stop reading. The terminator bytes themselves are not appended to
  ## `output`.
  ##
  ## Shared by blocking, non-blocking, and async paste readers - only the
  ## byte-source differs between them.
  case state
  of PesNone:
    if ch == '\x1b':
      state = PesEsc
      pending = $ch
    else:
      output.add(ch)
  of PesEsc:
    if ch == '[':
      state = PesBracket
      pending.add(ch)
    elif ch == '\x1b':
      # New potential sequence, flush previous ESC
      output.add(pending)
      pending = $ch
      # state stays PesEsc
    else:
      # Not a sequence, flush pending and continue
      output.add(pending)
      output.add(ch)
      pending = ""
      state = PesNone
  of PesBracket:
    if ch == '2':
      state = Pes2
      pending.add(ch)
    elif ch == '\x1b':
      output.add(pending)
      pending = $ch
      state = PesEsc
    else:
      output.add(pending)
      output.add(ch)
      pending = ""
      state = PesNone
  of Pes2:
    if ch == '0':
      state = Pes20
      pending.add(ch)
    elif ch == '\x1b':
      output.add(pending)
      pending = $ch
      state = PesEsc
    else:
      output.add(pending)
      output.add(ch)
      pending = ""
      state = PesNone
  of Pes20:
    if ch == '1':
      state = Pes201
      pending.add(ch)
    elif ch == '\x1b':
      output.add(pending)
      pending = $ch
      state = PesEsc
    else:
      output.add(pending)
      output.add(ch)
      pending = ""
      state = PesNone
  of Pes201:
    if ch == '~':
      # Found paste end sequence ESC[201~
      return true
    elif ch == '\x1b':
      output.add(pending)
      pending = $ch
      state = PesEsc
    else:
      output.add(pending)
      output.add(ch)
      pending = ""
      state = PesNone
  return false

# Cursor position report (I/O independent)

const MaxCursorReplyDigits = 5

proc readReplyNumber(bytes: string, i: var int, value: var int): bool =
  ## Read 1 to `MaxCursorReplyDigits` digits at `i` into `value`.
  let start = i
  value = 0
  while i < bytes.len and bytes[i] in {'0' .. '9'}:
    if i - start == MaxCursorReplyDigits:
      return false
    value = value * 10 + (ord(bytes[i]) - ord('0'))
    inc i
  i > start

proc scanCursorReply(bytes: string, i: var int, row, col: var int): CursorReplyMatch =
  ## Read the `row ; col R` of a cursor position report at `i`, leaving `i`
  ## after it.
  template expect(value: var int, final: char) =
    if not readReplyNumber(bytes, i, value) or i == bytes.len:
      return (if i == bytes.len: crmPartial else: crmNone)
    if bytes[i] != final:
      return crmNone
    inc i

  expect(row, ';')
  expect(col, 'R')
  crmComplete

proc extractCursorReply*(bytes: string): CursorReply =
  ## Take the first cursor position report (`ESC [ row ; col R`, 1-based) out
  ## of `bytes`. A report cut off at the end stays in `typeahead`.
  ##
  ## Shared by the sync and async cursor position queries.
  for start in 0 ..< bytes.len:
    if bytes[start] != '\x1b' or start + 1 >= bytes.len or bytes[start + 1] != '[':
      continue
    var i = start + 2
    var row, col: int
    if scanCursorReply(bytes, i, row, col) != crmComplete:
      continue
    return CursorReply(
      found: true,
      row: max(row - 1, 0),
      col: max(col - 1, 0),
      typeahead: bytes[0 ..< start] & bytes[i .. ^1],
    )
  CursorReply(typeahead: bytes)
