## Escape sequence parsing logic (I/O independent)
##
## This module contains shared escape sequence parsing logic used by
## blocking, non-blocking, and async parsers. It eliminates code duplication
## by separating parsing logic from I/O operations.

import key_logic
export key_logic.KeyEvent, key_logic.KeyCode
export key_logic.mapVT100FunctionKey, key_logic.mapFunctionKey
export key_logic.mapNumericKeyCode, key_logic.parseModifierCode
export key_logic.applyModifiers, key_logic.mapArrowKey, key_logic.mapNavigationKey

type EscapeResult* = object ## Result of escape sequence processing
  isValid*: bool
  keyEvent*: KeyEvent

proc escapeKey*(): KeyEvent {.inline.} =
  ## Create an Escape key event
  KeyEvent(code: KeyCode.Escape, char: "\x1b")

proc escapeResult*(): EscapeResult {.inline.} =
  ## Create an EscapeResult with Escape key (fallback for invalid sequences)
  EscapeResult(isValid: true, keyEvent: escapeKey())

proc processVT100FunctionKey*(ch: char, isValid: bool): EscapeResult =
  ## Process VT100 function keys: ESC O P/Q/R/S (F1-F4)
  if isValid:
    return EscapeResult(isValid: true, keyEvent: mapVT100FunctionKey(ch))
  else:
    return escapeResult()

proc processMultiDigitFunctionKey*(
    firstDigit, secondDigit, tilde: char, isValid: bool
): EscapeResult =
  ## Process multi-digit function keys: ESC[15~ (F5-F12)
  if isValid and tilde == '~':
    let twoDigitSeq = $firstDigit & $secondDigit
    return EscapeResult(isValid: true, keyEvent: mapFunctionKey(twoDigitSeq))
  else:
    return escapeResult()

proc processModifiedKeySequence*(
    digit: char, modChar: char, modValid: bool, keyChar: char, keyValid: bool
): EscapeResult =
  ## Process modified key sequences: ESC[1;2A (Shift/Ctrl/Alt + key)
  if not modValid or not keyValid:
    return escapeResult()

  let modifiers = parseModifierCode(modChar)

  # Try arrow keys with modifiers
  let arrowKey = mapArrowKey(keyChar)
  if arrowKey.code != KeyCode.Escape:
    return EscapeResult(isValid: true, keyEvent: applyModifiers(arrowKey, modifiers))

  # Try navigation keys with modifiers
  let navKey = mapNavigationKey(keyChar)
  if navKey.code != KeyCode.Escape:
    return EscapeResult(isValid: true, keyEvent: applyModifiers(navKey, modifiers))

  # Handle modified special keys (numeric codes with ~)
  if keyChar == '~':
    let numKey = mapNumericKeyCode(digit)
    if numKey.code != KeyCode.Escape:
      return EscapeResult(isValid: true, keyEvent: applyModifiers(numKey, modifiers))

  return escapeResult()

type NumericSequenceKind* = enum
  ## Classification of numeric escape sequences after ESC[digit
  NskSingleDigitWithTilde # ESC[1~
  NskMultiDigit # ESC[15~
  NskModifiedKey # ESC[1;2A
  NskInvalid

proc classifyNumericSequence*(nextChar: char, isValid: bool): NumericSequenceKind =
  ## Classify numeric sequence type by next character: '~' / digit / ';'
  if not isValid:
    return NskInvalid

  if nextChar == '~':
    return NskSingleDigitWithTilde
  elif nextChar in {'0' .. '9'}:
    return NskMultiDigit
  elif nextChar == ';':
    return NskModifiedKey
  else:
    return NskInvalid

type BracketSequenceKind* = enum
  ## Classification of bracket escape sequences after ESC[
  BskArrowKey # ESC[A, ESC[B, ESC[C, ESC[D
  BskNavigationKey # ESC[H, ESC[F, ESC[Z
  BskMouseX10 # ESC[M
  BskMouseSGR # ESC[<
  BskNumeric # ESC[1~, ESC[15~, ESC[1;2A
  BskFocusIn # ESC[I
  BskFocusOut # ESC[O
  BskInvalid

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
  of '1' .. '6':
    return BskNumeric
  else:
    discard

  let arrowKey = mapArrowKey(final)
  if arrowKey.code != KeyCode.Escape:
    return BskArrowKey

  let navKey = mapNavigationKey(final)
  if navKey.code != KeyCode.Escape:
    return BskNavigationKey

  return BskInvalid

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

proc processSingleDigitNumeric*(digit: char): EscapeResult =
  ## Process single digit numeric sequences: ESC[1~ (Home/Insert/Delete etc)
  EscapeResult(isValid: true, keyEvent: mapNumericKeyCode(digit))

# Bracketed paste mode sequence detection

proc isPasteStartSequence*(d1, d2, d3, final: char): bool {.inline.} =
  ## Check if sequence is ESC[200~ (paste start)
  d1 == '2' and d2 == '0' and d3 == '0' and final == '~'

proc isPasteEndSequence*(d1, d2, d3, final: char): bool {.inline.} =
  ## Check if sequence is ESC[201~ (paste end)
  d1 == '2' and d2 == '0' and d3 == '1' and final == '~'

# Bracketed paste content reading (I/O independent state machine)

type PasteEndState* = enum
  ## State machine for detecting paste end sequence ESC[201~
  PesNone ## Not in sequence
  PesEsc ## Saw ESC
  PesBracket ## Saw ESC [
  Pes2 ## Saw ESC [ 2
  Pes20 ## Saw ESC [ 2 0
  Pes201 ## Saw ESC [ 2 0 1

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
