# Test suite for escape_sequence_logic module

import std/unittest

import ../celina/core/escape_sequence_logic
import ../celina/core/key_logic

suite "Escape Sequence Logic Tests":
  suite "Helper Functions":
    test "escapeKey creates proper escape key event":
      let key = escapeKey()
      check key.code == KeyCode.Escape
      check key.char == "\x1b"

    test "escapeResult creates valid result":
      let result = escapeResult()
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Escape

  suite "VT100 Function Key Processing":
    test "processVT100FunctionKey with valid P (F1)":
      let result = processVT100FunctionKey('P', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.F1

    test "processVT100FunctionKey with valid Q (F2)":
      let result = processVT100FunctionKey('Q', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.F2

    test "processVT100FunctionKey with valid R (F3)":
      let result = processVT100FunctionKey('R', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.F3

    test "processVT100FunctionKey with valid S (F4)":
      let result = processVT100FunctionKey('S', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.F4

    test "processVT100FunctionKey with invalid character":
      let result = processVT100FunctionKey('X', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Escape

    test "processVT100FunctionKey with invalid flag":
      let result = processVT100FunctionKey('P', false)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Escape

  suite "Multi-digit Function Key Processing":
    test "processMultiDigitFunctionKey with valid 15~ (F5)":
      let result = processMultiDigitFunctionKey('1', '5', '~', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.F5

    test "processMultiDigitFunctionKey with valid 17~ (F6)":
      let result = processMultiDigitFunctionKey('1', '7', '~', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.F6

    test "processMultiDigitFunctionKey with valid 18~ (F7)":
      let result = processMultiDigitFunctionKey('1', '8', '~', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.F7

    test "processMultiDigitFunctionKey with valid 19~ (F8)":
      let result = processMultiDigitFunctionKey('1', '9', '~', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.F8

    test "processMultiDigitFunctionKey with valid 20~ (F9)":
      let result = processMultiDigitFunctionKey('2', '0', '~', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.F9

    test "processMultiDigitFunctionKey with valid 21~ (F10)":
      let result = processMultiDigitFunctionKey('2', '1', '~', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.F10

    test "processMultiDigitFunctionKey with invalid tilde":
      let result = processMultiDigitFunctionKey('1', '5', 'X', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Escape

    test "processMultiDigitFunctionKey with invalid flag":
      let result = processMultiDigitFunctionKey('1', '5', '~', false)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Escape

  suite "Modified Key Sequence Processing":
    test "processModifiedKeySequence with Shift+ArrowUp (1;2A)":
      let result = processModifiedKeySequence('1', '2', true, 'A', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.ArrowUp
      check KeyModifier.Shift in result.keyEvent.modifiers

    test "processModifiedKeySequence with Alt+ArrowRight (1;3C)":
      let result = processModifiedKeySequence('1', '3', true, 'C', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.ArrowRight
      check KeyModifier.Alt in result.keyEvent.modifiers

    test "processModifiedKeySequence with Ctrl+ArrowLeft (1;5D)":
      let result = processModifiedKeySequence('1', '5', true, 'D', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.ArrowLeft
      check KeyModifier.Ctrl in result.keyEvent.modifiers

    test "processModifiedKeySequence with Shift+Home (1;2H)":
      let result = processModifiedKeySequence('1', '2', true, 'H', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Home
      check KeyModifier.Shift in result.keyEvent.modifiers

    test "processModifiedKeySequence with invalid modChar":
      let result = processModifiedKeySequence('1', '2', false, 'A', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Escape

    test "processModifiedKeySequence with invalid keyChar":
      let result = processModifiedKeySequence('1', '2', true, 'A', false)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Escape

    test "processModifiedKeySequence with unknown key":
      let result = processModifiedKeySequence('1', '2', true, 'X', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Escape

  suite "Numeric Sequence Classification":
    test "classifyNumericSequence with single digit + tilde":
      let kind = classifyNumericSequence('~', true)
      check kind == NskSingleDigitWithTilde

    test "classifyNumericSequence with multi-digit":
      let kind = classifyNumericSequence('5', true)
      check kind == NskMultiDigit

    test "classifyNumericSequence with modified key":
      let kind = classifyNumericSequence(';', true)
      check kind == NskModifiedKey

    test "classifyNumericSequence with invalid character":
      let kind = classifyNumericSequence('X', true)
      check kind == NskInvalid

    test "classifyNumericSequence with invalid flag":
      let kind = classifyNumericSequence('~', false)
      check kind == NskInvalid

  suite "Bracket Sequence Classification":
    test "classifyBracketSequence with arrow key A (up)":
      let kind = classifyBracketSequence('A')
      check kind == BskArrowKey

    test "classifyBracketSequence with arrow key B (down)":
      let kind = classifyBracketSequence('B')
      check kind == BskArrowKey

    test "classifyBracketSequence with arrow key C (right)":
      let kind = classifyBracketSequence('C')
      check kind == BskArrowKey

    test "classifyBracketSequence with arrow key D (left)":
      let kind = classifyBracketSequence('D')
      check kind == BskArrowKey

    test "classifyBracketSequence with navigation key H (Home)":
      let kind = classifyBracketSequence('H')
      check kind == BskNavigationKey

    test "classifyBracketSequence with navigation key F (End)":
      let kind = classifyBracketSequence('F')
      check kind == BskNavigationKey

    test "classifyBracketSequence with mouse X10 (M)":
      let kind = classifyBracketSequence('M')
      check kind == BskMouseX10

    test "classifyBracketSequence with mouse SGR (<)":
      let kind = classifyBracketSequence('<')
      check kind == BskMouseSGR

    test "classifyBracketSequence with numeric sequence (1-6)":
      for digit in '1' .. '6':
        let kind = classifyBracketSequence(digit)
        check kind == BskNumeric

    test "classifyBracketSequence with focus in (I)":
      let kind = classifyBracketSequence('I')
      check kind == BskFocusIn

    test "classifyBracketSequence with focus out (O)":
      let kind = classifyBracketSequence('O')
      check kind == BskFocusOut

    test "classifyBracketSequence with invalid character":
      let kind = classifyBracketSequence('X')
      check kind == BskInvalid

  suite "Simple Bracket Sequence Processing":
    test "processSimpleBracketSequence with arrow up":
      let result = processSimpleBracketSequence('A', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.ArrowUp

    test "processSimpleBracketSequence with arrow down":
      let result = processSimpleBracketSequence('B', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.ArrowDown

    test "processSimpleBracketSequence with arrow right":
      let result = processSimpleBracketSequence('C', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.ArrowRight

    test "processSimpleBracketSequence with arrow left":
      let result = processSimpleBracketSequence('D', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.ArrowLeft

    test "processSimpleBracketSequence with Home":
      let result = processSimpleBracketSequence('H', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Home

    test "processSimpleBracketSequence with End":
      let result = processSimpleBracketSequence('F', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.End

    test "processSimpleBracketSequence with invalid flag":
      let result = processSimpleBracketSequence('A', false)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Escape

    test "processSimpleBracketSequence with invalid character":
      let result = processSimpleBracketSequence('X', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Escape

  suite "Single Digit Numeric Processing":
    test "processSingleDigitNumeric with 1 (Home)":
      let result = processSingleDigitNumeric('1')
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Home

    test "processSingleDigitNumeric with 2 (Insert)":
      let result = processSingleDigitNumeric('2')
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Insert

    test "processSingleDigitNumeric with 3 (Delete)":
      let result = processSingleDigitNumeric('3')
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Delete

    test "processSingleDigitNumeric with 4 (End)":
      let result = processSingleDigitNumeric('4')
      check result.isValid == true
      check result.keyEvent.code == KeyCode.End

    test "processSingleDigitNumeric with 5 (PageUp)":
      let result = processSingleDigitNumeric('5')
      check result.isValid == true
      check result.keyEvent.code == KeyCode.PageUp

    test "processSingleDigitNumeric with 6 (PageDown)":
      let result = processSingleDigitNumeric('6')
      check result.isValid == true
      check result.keyEvent.code == KeyCode.PageDown

  suite "Edge Cases and Error Handling":
    test "processVT100FunctionKey with null character":
      let result = processVT100FunctionKey('\0', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Escape

    test "processMultiDigitFunctionKey with null characters":
      let result = processMultiDigitFunctionKey('\0', '\0', '\0', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Escape

    test "processModifiedKeySequence with null characters":
      let result = processModifiedKeySequence('\0', '\0', true, '\0', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Escape

    test "classifyNumericSequence with all invalid inputs":
      for ch in ['\0', '\x01', '\x7F', '\xFF']:
        let kind = classifyNumericSequence(ch, false)
        check kind == NskInvalid

    test "processSimpleBracketSequence with control characters":
      for ch in ['\0', '\x01', '\x7F']:
        let result = processSimpleBracketSequence(ch, true)
        check result.isValid == true
        check result.keyEvent.code == KeyCode.Escape

  suite "Consistency Tests":
    test "All escape fallbacks return same key":
      let key1 = escapeKey()
      let key2 = escapeResult().keyEvent
      let key3 = processVT100FunctionKey('X', true).keyEvent
      check key1.code == key2.code
      check key2.code == key3.code
      check key1.char == key2.char
      check key2.char == key3.char

    test "Classification functions are deterministic":
      # Same input should always produce same output
      for i in 1 .. 10:
        check classifyNumericSequence('~', true) == NskSingleDigitWithTilde
        check classifyBracketSequence('A') == BskArrowKey

    test "Invalid flags always produce escape key":
      let r1 = processVT100FunctionKey('P', false)
      let r2 = processMultiDigitFunctionKey('1', '5', '~', false)
      check r1.keyEvent.code == KeyCode.Escape
      check r2.keyEvent.code == KeyCode.Escape
