## Tests for key_logic module
##
## This test suite verifies that the shared key event processing utilities
## work correctly for both sync and async implementations.

import unittest
import ../celina/core/key_logic

suite "Ctrl Letter Key Mapping":
  test "Ctrl-A through Ctrl-Z (excluding special keys)":
    # Test Ctrl-A
    let resultA = mapCtrlLetterKey('\x01')
    check resultA.isCtrlKey
    check resultA.keyEvent.code == Char
    check resultA.keyEvent.char == "a"
    check resultA.keyEvent.modifiers == {Ctrl}

    # Test Ctrl-B
    let resultB = mapCtrlLetterKey('\x02')
    check resultB.isCtrlKey
    check resultB.keyEvent.char == "b"

    # Test Ctrl-Z
    let resultZ = mapCtrlLetterKey('\x1a')
    check resultZ.isCtrlKey
    check resultZ.keyEvent.char == "z"

  test "Excluded Ctrl keys (should not be mapped)":
    # \x03 = Ctrl-C (Quit)
    let resultC = mapCtrlLetterKey('\x03')
    check not resultC.isCtrlKey

    # \x08 = Ctrl-H (Backspace)
    let resultH = mapCtrlLetterKey('\x08')
    check not resultH.isCtrlKey

    # \x09 = Ctrl-I (Tab)
    let resultI = mapCtrlLetterKey('\x09')
    check not resultI.isCtrlKey

    # \x0a = Ctrl-J (Line Feed)
    let resultJ = mapCtrlLetterKey('\x0a')
    check not resultJ.isCtrlKey

    # \x0d = Ctrl-M (Enter)
    let resultM = mapCtrlLetterKey('\x0d')
    check not resultM.isCtrlKey

    # \x1b = Ctrl-[ (Escape)
    let resultEsc = mapCtrlLetterKey('\x1b')
    check not resultEsc.isCtrlKey

  test "Non-Ctrl characters":
    # Regular 'a' should not be recognized as Ctrl key
    let resultA = mapCtrlLetterKey('a')
    check not resultA.isCtrlKey

    # Space should not be recognized
    let resultSpace = mapCtrlLetterKey(' ')
    check not resultSpace.isCtrlKey

suite "Ctrl Number Key Mapping":
  test "Ctrl-Space (\\x00)":
    let result = mapCtrlNumberKey('\x00')
    check result.isCtrlKey
    check result.keyEvent.code == Space
    check result.keyEvent.char == " "
    check result.keyEvent.modifiers == {Ctrl}

  test "Ctrl-4 through Ctrl-7":
    # \x1c = Ctrl-4
    let result4 = mapCtrlNumberKey('\x1c')
    check result4.isCtrlKey
    check result4.keyEvent.code == Char
    check result4.keyEvent.char == "4"
    check result4.keyEvent.modifiers == {Ctrl}

    # \x1d = Ctrl-5
    let result5 = mapCtrlNumberKey('\x1d')
    check result5.isCtrlKey
    check result5.keyEvent.char == "5"

    # \x1e = Ctrl-6
    let result6 = mapCtrlNumberKey('\x1e')
    check result6.isCtrlKey
    check result6.keyEvent.char == "6"

    # \x1f = Ctrl-7
    let result7 = mapCtrlNumberKey('\x1f')
    check result7.isCtrlKey
    check result7.keyEvent.char == "7"

  test "Non-Ctrl number characters":
    # Regular '4' should not be recognized
    let result = mapCtrlNumberKey('4')
    check not result.isCtrlKey

suite "Basic Key Mapping":
  test "Enter key":
    let resultCR = mapBasicKey('\r')
    check resultCR.code == Enter
    check resultCR.char == "\r"

    let resultLF = mapBasicKey('\n')
    check resultLF.code == Enter
    check resultLF.char == "\n"

  test "Tab key":
    let result = mapBasicKey('\t')
    check result.code == Tab
    check result.char == "\t"

  test "Space key":
    let result = mapBasicKey(' ')
    check result.code == Space
    check result.char == " "

  test "Backspace key":
    let resultBS = mapBasicKey('\x08')
    check resultBS.code == Backspace

    let resultDEL = mapBasicKey('\x7f')
    check resultDEL.code == Backspace

  test "Regular characters":
    let resultA = mapBasicKey('a')
    check resultA.code == Char
    check resultA.char == "a"

    let result0 = mapBasicKey('0')
    check result0.code == Char
    check result0.char == "0"

suite "Arrow Key Mapping":
  test "Arrow keys":
    check mapArrowKey('A').code == ArrowUp
    check mapArrowKey('B').code == ArrowDown
    check mapArrowKey('C').code == ArrowRight
    check mapArrowKey('D').code == ArrowLeft

  test "Non-arrow characters":
    # Should return Escape for unrecognized characters
    let result = mapArrowKey('Z')
    check result.code == Escape
    check result.char == "\x1b"

suite "Navigation Key Mapping":
  test "Navigation keys":
    check mapNavigationKey('H').code == Home
    check mapNavigationKey('F').code == End
    check mapNavigationKey('Z').code == BackTab

  test "Non-navigation characters":
    let result = mapNavigationKey('X')
    check result.code == Escape

suite "Numeric Key Code Mapping":
  test "Numeric key codes":
    check mapNumericKeyCode('1').code == Home
    check mapNumericKeyCode('2').code == Insert
    check mapNumericKeyCode('3').code == Delete
    check mapNumericKeyCode('4').code == End
    check mapNumericKeyCode('5').code == PageUp
    check mapNumericKeyCode('6').code == PageDown

  test "Invalid numeric codes":
    let result = mapNumericKeyCode('7')
    check result.code == Escape

suite "Modifier Code Parsing":
  test "Shift modifier (2)":
    let modifiers = parseModifierCode('2')
    check modifiers == {Shift}

  test "Alt modifier (3)":
    let modifiers = parseModifierCode('3')
    check modifiers == {Alt}

  test "Shift+Alt modifier (4)":
    let modifiers = parseModifierCode('4')
    check modifiers == {Shift, Alt}

  test "Ctrl modifier (5)":
    let modifiers = parseModifierCode('5')
    check modifiers == {Ctrl}

  test "Ctrl+Shift modifier (6)":
    let modifiers = parseModifierCode('6')
    check modifiers == {Ctrl, Shift}

  test "Ctrl+Alt modifier (7)":
    let modifiers = parseModifierCode('7')
    check modifiers == {Ctrl, Alt}

  test "Ctrl+Shift+Alt modifier (8)":
    let modifiers = parseModifierCode('8')
    check modifiers == {Ctrl, Shift, Alt}

  test "No modifier (1)":
    let modifiers = parseModifierCode('1')
    check modifiers == {}

suite "Apply Modifiers":
  test "Apply Ctrl to arrow key":
    let key = KeyEvent(code: ArrowUp, char: "")
    let modified = applyModifiers(key, {Ctrl})
    check modified.code == ArrowUp
    check modified.modifiers == {Ctrl}

  test "Apply multiple modifiers":
    let key = KeyEvent(code: Home, char: "")
    let modified = applyModifiers(key, {Ctrl, Shift, Alt})
    check modified.code == Home
    check modified.modifiers == {Ctrl, Shift, Alt}

  test "Apply modifiers to character":
    let key = KeyEvent(code: Char, char: "a")
    let modified = applyModifiers(key, {Shift})
    check modified.code == Char
    check modified.char == "a"
    check modified.modifiers == {Shift}
