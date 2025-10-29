## Key Event Processing Logic
##
## This module contains pure business logic for key event processing,
## shared between synchronous and asynchronous implementations.
##
## No I/O operations are performed here - only character-to-key mappings.

import mouse_logic # For KeyModifier

export mouse_logic.KeyModifier

type
  KeyCode* = enum
    # Basic keys
    Char # Regular character
    Enter # Enter/Return key
    Escape # Escape key
    Backspace # Backspace key
    Tab # Tab key
    BackTab # Shift+Tab
    Space # Space key
    # Arrow keys
    ArrowUp
    ArrowDown
    ArrowLeft
    ArrowRight
    # Navigation keys
    Home
    End
    PageUp
    PageDown
    Insert
    Delete
    # Function keys
    F1
    F2
    F3
    F4
    F5
    F6
    F7
    F8
    F9
    F10
    F11
    F12

  KeyEvent* = object
    code*: KeyCode
    char*: string
    modifiers*: set[KeyModifier]

  CtrlKeyResult* = object ## Result of Ctrl key mapping
    isCtrlKey*: bool
    keyEvent*: KeyEvent

proc mapCtrlLetterKey*(ch: char): CtrlKeyResult =
  ## Map Ctrl+letter combinations (\x01-\x1a) to key events
  ##
  ## \x01-\x1a = Ctrl-A to Ctrl-Z, but exclude already-handled keys:
  ## \x03 = Ctrl-C (Quit), \x08 = Ctrl-H (Backspace), \x09 = Ctrl-I (Tab)
  ## \x0a = Ctrl-J (Line Feed), \x0d = Ctrl-M (Enter), \x1b = Ctrl-[ (Escape)
  ##
  ## Example:
  ## ```nim
  ## let result = mapCtrlLetterKey('\x01')  # Ctrl-A
  ## assert result.isCtrlKey
  ## assert result.keyEvent.char == "a"
  ## assert result.keyEvent.modifiers == {Ctrl}
  ## ```
  if ch >= '\x01' and ch <= '\x1a' and
      ch notin {'\x03', '\x08', '\x09', '\x0a', '\x0d', '\x1b'}:
    let letter = chr(ch.ord + ord('a') - 1)
    return CtrlKeyResult(
      isCtrlKey: true, keyEvent: KeyEvent(code: Char, char: $letter, modifiers: {Ctrl})
    )

  return CtrlKeyResult(isCtrlKey: false)

proc mapCtrlNumberKey*(ch: char): CtrlKeyResult =
  ## Map Ctrl+number and special control characters
  ##
  ## Following crossterm's mapping:
  ## \x00 = Ctrl-Space, \x1c = Ctrl-4, \x1d = Ctrl-5, \x1e = Ctrl-6, \x1f = Ctrl-7
  ##
  ## Example:
  ## ```nim
  ## let result = mapCtrlNumberKey('\x00')  # Ctrl-Space
  ## assert result.isCtrlKey
  ## assert result.keyEvent.code == Space
  ## ```
  if ch == '\x00':
    return CtrlKeyResult(
      isCtrlKey: true, keyEvent: KeyEvent(code: Space, char: " ", modifiers: {Ctrl})
    )
  elif ch >= '\x1c' and ch <= '\x1f':
    let digit = chr(ch.ord - 0x1c + ord('4'))
    return CtrlKeyResult(
      isCtrlKey: true, keyEvent: KeyEvent(code: Char, char: $digit, modifiers: {Ctrl})
    )

  return CtrlKeyResult(isCtrlKey: false)

proc mapBasicKey*(ch: char): KeyEvent =
  ## Map basic characters to key events
  ##
  ## Handles: Enter, Tab, Space, Backspace, and regular characters
  ##
  ## Example:
  ## ```nim
  ## assert mapBasicKey('\r').code == Enter
  ## assert mapBasicKey('\t').code == Tab
  ## assert mapBasicKey('a').code == Char
  ## ```
  case ch
  of '\r', '\n':
    KeyEvent(code: Enter, char: $ch)
  of '\t':
    KeyEvent(code: Tab, char: $ch)
  of ' ':
    KeyEvent(code: Space, char: $ch)
  of '\x08', '\x7f': # Backspace or DEL
    KeyEvent(code: Backspace, char: $ch)
  else:
    KeyEvent(code: Char, char: $ch)

proc mapArrowKey*(ch: char): KeyEvent =
  ## Map escape sequence final character to arrow key
  ##
  ## ESC [ A/B/C/D -> ArrowUp/Down/Right/Left
  ##
  ## Example:
  ## ```nim
  ## assert mapArrowKey('A').code == ArrowUp
  ## assert mapArrowKey('B').code == ArrowDown
  ## ```
  case ch
  of 'A':
    KeyEvent(code: ArrowUp, char: "")
  of 'B':
    KeyEvent(code: ArrowDown, char: "")
  of 'C':
    KeyEvent(code: ArrowRight, char: "")
  of 'D':
    KeyEvent(code: ArrowLeft, char: "")
  else:
    KeyEvent(code: Escape, char: "\x1b")

proc mapNavigationKey*(ch: char): KeyEvent =
  ## Map escape sequence final character to navigation key
  ##
  ## ESC [ H/F/Z -> Home/End/BackTab
  case ch
  of 'H':
    KeyEvent(code: Home, char: "")
  of 'F':
    KeyEvent(code: End, char: "")
  of 'Z':
    KeyEvent(code: BackTab, char: "")
  else:
    KeyEvent(code: Escape, char: "\x1b")

proc mapNumericKeyCode*(numChar: char): KeyEvent =
  ## Map numeric escape sequences ESC [ n ~
  ##
  ## 1/4 = Home/End, 2 = Insert, 3 = Delete, 5/6 = PageUp/PageDown
  ##
  ## Example:
  ## ```nim
  ## assert mapNumericKeyCode('1').code == Home
  ## assert mapNumericKeyCode('2').code == Insert
  ## ```
  case numChar
  of '1': # Home (alternative)
    KeyEvent(code: Home, char: "")
  of '2': # Insert
    KeyEvent(code: Insert, char: "")
  of '3': # Delete
    KeyEvent(code: Delete, char: "")
  of '4': # End (alternative)
    KeyEvent(code: End, char: "")
  of '5': # PageUp
    KeyEvent(code: PageUp, char: "")
  of '6': # PageDown
    KeyEvent(code: PageDown, char: "")
  else:
    KeyEvent(code: Escape, char: "\x1b")

proc mapFunctionKey*(sequence: string): KeyEvent =
  ## Map multi-digit escape sequences for function keys
  ##
  ## Function keys use ESC [ nn ~ format:
  ## F1-F4: ESC [ 11~, 12~, 13~, 14~ (alternative to ESC O P/Q/R/S)
  ## F5-F12: ESC [ 15~, 17~, 18~, 19~, 20~, 21~, 23~, 24~
  ##
  ## Example:
  ## ```nim
  ## assert mapFunctionKey("11").code == F1
  ## assert mapFunctionKey("15").code == F5
  ## ```
  case sequence
  of "11":
    KeyEvent(code: F1, char: "")
  of "12":
    KeyEvent(code: F2, char: "")
  of "13":
    KeyEvent(code: F3, char: "")
  of "14":
    KeyEvent(code: F4, char: "")
  of "15":
    KeyEvent(code: F5, char: "")
  of "17":
    KeyEvent(code: F6, char: "")
  of "18":
    KeyEvent(code: F7, char: "")
  of "19":
    KeyEvent(code: F8, char: "")
  of "20":
    KeyEvent(code: F9, char: "")
  of "21":
    KeyEvent(code: F10, char: "")
  of "23":
    KeyEvent(code: F11, char: "")
  of "24":
    KeyEvent(code: F12, char: "")
  else:
    KeyEvent(code: Escape, char: "\x1b")

proc mapVT100FunctionKey*(ch: char): KeyEvent =
  ## Map VT100-style function keys ESC O P/Q/R/S
  ##
  ## This is the older format for F1-F4:
  ## P = F1, Q = F2, R = F3, S = F4
  ##
  ## Example:
  ## ```nim
  ## assert mapVT100FunctionKey('P').code == F1
  ## assert mapVT100FunctionKey('Q').code == F2
  ## ```
  case ch
  of 'P':
    KeyEvent(code: F1, char: "")
  of 'Q':
    KeyEvent(code: F2, char: "")
  of 'R':
    KeyEvent(code: F3, char: "")
  of 'S':
    KeyEvent(code: F4, char: "")
  else:
    KeyEvent(code: Escape, char: "\x1b")

proc parseModifierCode*(modChar: char): set[KeyModifier] =
  ## Parse modifier code from escape sequence
  ##
  ## Modifier encoding (1-based, subtract 1 for bit flags):
  ## 1=None, 2=Shift, 3=Alt, 4=Shift+Alt, 5=Ctrl,
  ## 6=Ctrl+Shift, 7=Ctrl+Alt, 8=Ctrl+Shift+Alt
  ##
  ## Example:
  ## ```nim
  ## assert parseModifierCode('2') == {Shift}
  ## assert parseModifierCode('5') == {Ctrl}
  ## assert parseModifierCode('8') == {Ctrl, Shift, Alt}
  ## ```
  let modifierCode = int(modChar) - int('0')
  # Subtract 1 because modifier codes are 1-based (1=no mods, 2=Shift, etc.)
  let modifier = modifierCode - 1
  var modifiers: set[KeyModifier] = {}

  if (modifier and 1) != 0:
    modifiers.incl(Shift)
  if (modifier and 2) != 0:
    modifiers.incl(Alt)
  if (modifier and 4) != 0:
    modifiers.incl(Ctrl)

  return modifiers

proc applyModifiers*(keyEvent: KeyEvent, modifiers: set[KeyModifier]): KeyEvent =
  ## Apply modifiers to a key event
  ##
  ## Example:
  ## ```nim
  ## let key = KeyEvent(code: ArrowUp, char: "")
  ## let modified = applyModifiers(key, {Ctrl, Shift})
  ## assert modified.modifiers == {Ctrl, Shift}
  ## ```
  KeyEvent(code: keyEvent.code, char: keyEvent.char, modifiers: modifiers)
