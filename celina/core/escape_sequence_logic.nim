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

type EscapeResult* = object
  ## Result of escape sequence processing
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
  BskInvalid

proc classifyBracketSequence*(final: char): BracketSequenceKind =
  ## Classify bracket sequence type by character after ESC[
  let arrowKey = mapArrowKey(final)
  if arrowKey.code != KeyCode.Escape:
    return BskArrowKey

  let navKey = mapNavigationKey(final)
  if navKey.code != KeyCode.Escape:
    return BskNavigationKey

  case final
  of 'M':
    return BskMouseX10
  of '<':
    return BskMouseSGR
  of '1' .. '6':
    return BskNumeric
  else:
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
