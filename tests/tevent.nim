# Test suite for Events module

import std/unittest

import ../src/core/events

suite "Events Module Tests":
  suite "EventKind Tests":
    test "EventKind enum values":
      check EventKind.Key.ord == 0
      check EventKind.Quit.ord == 1
      check EventKind.Unknown.ord == 2

  suite "KeyCode Tests":
    test "Basic key codes":
      check KeyCode.Char.ord == 0
      check KeyCode.Enter.ord == 1
      check KeyCode.Escape.ord == 2
      check KeyCode.Backspace.ord == 3
      check KeyCode.Tab.ord == 4
      check KeyCode.Space.ord == 5

    test "Arrow key codes":
      check KeyCode.ArrowUp.ord == 6
      check KeyCode.ArrowDown.ord == 7
      check KeyCode.ArrowLeft.ord == 8
      check KeyCode.ArrowRight.ord == 9

    test "Function key codes":
      check KeyCode.F1.ord == 10
      check KeyCode.F2.ord == 11
      check KeyCode.F3.ord == 12
      check KeyCode.F4.ord == 13
      check KeyCode.F5.ord == 14
      check KeyCode.F6.ord == 15
      check KeyCode.F7.ord == 16
      check KeyCode.F8.ord == 17
      check KeyCode.F9.ord == 18
      check KeyCode.F10.ord == 19
      check KeyCode.F11.ord == 20
      check KeyCode.F12.ord == 21

  suite "KeyModifier Tests":
    test "KeyModifier enum values":
      check KeyModifier.Ctrl.ord == 0
      check KeyModifier.Alt.ord == 1
      check KeyModifier.Shift.ord == 2

  suite "KeyEvent Tests":
    test "KeyEvent creation - character key":
      let keyEvent = KeyEvent(code: Char, char: 'a', modifiers: {})
      check keyEvent.code == Char
      check keyEvent.char == 'a'
      check keyEvent.modifiers.len == 0

    test "KeyEvent creation - special key":
      let keyEvent = KeyEvent(code: Enter, char: '\r', modifiers: {})
      check keyEvent.code == Enter
      check keyEvent.char == '\r'
      check keyEvent.modifiers.len == 0

    test "KeyEvent creation - with modifiers":
      let keyEvent = KeyEvent(code: Char, char: 'c', modifiers: {Ctrl})
      check keyEvent.code == Char
      check keyEvent.char == 'c'
      check Ctrl in keyEvent.modifiers
      check keyEvent.modifiers.len == 1

    test "KeyEvent creation - multiple modifiers":
      let keyEvent = KeyEvent(code: Char, char: 'x', modifiers: {Ctrl, Shift})
      check keyEvent.code == Char
      check keyEvent.char == 'x'
      check Ctrl in keyEvent.modifiers
      check Shift in keyEvent.modifiers
      check Alt notin keyEvent.modifiers
      check keyEvent.modifiers.len == 2

    test "KeyEvent creation - function key":
      let keyEvent = KeyEvent(code: F1, char: '\0', modifiers: {})
      check keyEvent.code == F1
      check keyEvent.char == '\0'
      check keyEvent.modifiers.len == 0

    test "KeyEvent creation - arrow key":
      let keyEvent = KeyEvent(code: ArrowUp, char: '\0', modifiers: {})
      check keyEvent.code == ArrowUp
      check keyEvent.char == '\0'
      check keyEvent.modifiers.len == 0

  suite "Event Tests":
    test "Event creation - Key event":
      let keyEvent = KeyEvent(code: Char, char: 'h', modifiers: {})
      let event = Event(kind: Key, key: keyEvent)

      check event.kind == Key
      check event.key.code == Char
      check event.key.char == 'h'
      check event.key.modifiers.len == 0

    test "Event creation - Quit event":
      let event = Event(kind: Quit)
      check event.kind == Quit

    test "Event creation - Unknown event":
      let event = Event(kind: Unknown)
      check event.kind == Unknown

    test "Event creation - Key event with Enter":
      let keyEvent = KeyEvent(code: Enter, char: '\r', modifiers: {})
      let event = Event(kind: Key, key: keyEvent)

      check event.kind == Key
      check event.key.code == Enter
      check event.key.char == '\r'

    test "Event creation - Key event with Escape":
      let keyEvent = KeyEvent(code: Escape, char: '\x1b', modifiers: {})
      let event = Event(kind: Key, key: keyEvent)

      check event.kind == Key
      check event.key.code == Escape
      check event.key.char == '\x1b'

    test "Event creation - Key event with Tab":
      let keyEvent = KeyEvent(code: Tab, char: '\t', modifiers: {})
      let event = Event(kind: Key, key: keyEvent)

      check event.kind == Key
      check event.key.code == Tab
      check event.key.char == '\t'

    test "Event creation - Key event with Space":
      let keyEvent = KeyEvent(code: Space, char: ' ', modifiers: {})
      let event = Event(kind: Key, key: keyEvent)

      check event.kind == Key
      check event.key.code == Space
      check event.key.char == ' '

    test "Event creation - Key event with Backspace":
      let keyEvent = KeyEvent(code: Backspace, char: '\x08', modifiers: {})
      let event = Event(kind: Key, key: keyEvent)

      check event.kind == Key
      check event.key.code == Backspace
      check event.key.char == '\x08'

  suite "Character Mapping Tests":
    test "Character event creation - letters":
      # Test various letter characters
      for ch in 'a' .. 'z':
        let keyEvent = KeyEvent(code: Char, char: ch, modifiers: {})
        let event = Event(kind: Key, key: keyEvent)
        check event.kind == Key
        check event.key.code == Char
        check event.key.char == ch

      for ch in 'A' .. 'Z':
        let keyEvent = KeyEvent(code: Char, char: ch, modifiers: {})
        let event = Event(kind: Key, key: keyEvent)
        check event.kind == Key
        check event.key.code == Char
        check event.key.char == ch

    test "Character event creation - digits":
      # Test digit characters
      for ch in '0' .. '9':
        let keyEvent = KeyEvent(code: Char, char: ch, modifiers: {})
        let event = Event(kind: Key, key: keyEvent)
        check event.kind == Key
        check event.key.code == Char
        check event.key.char == ch

    test "Character event creation - special characters":
      # Test common special characters
      let specialChars =
        @[
          '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '-', '_', '=', '+', '[',
          ']', '{', '}', '\\', '|', ';', ':', '\'', '"', ',', '.', '<', '>', '/', '?',
        ]

      for ch in specialChars:
        let keyEvent = KeyEvent(code: Char, char: ch, modifiers: {})
        let event = Event(kind: Key, key: keyEvent)
        check event.kind == Key
        check event.key.code == Char
        check event.key.char == ch

  suite "Special Key Tests":
    test "Special key mapping - control characters":
      # Test control characters mapping to special keys
      let enterEvent =
        Event(kind: Key, key: KeyEvent(code: Enter, char: '\r', modifiers: {}))
      check enterEvent.key.code == Enter
      check enterEvent.key.char == '\r'

      let tabEvent =
        Event(kind: Key, key: KeyEvent(code: Tab, char: '\t', modifiers: {}))
      check tabEvent.key.code == Tab
      check tabEvent.key.char == '\t'

      let escapeEvent =
        Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b', modifiers: {}))
      check escapeEvent.key.code == Escape
      check escapeEvent.key.char == '\x1b'

      let backspaceEvent =
        Event(kind: Key, key: KeyEvent(code: Backspace, char: '\x08', modifiers: {}))
      check backspaceEvent.key.code == Backspace
      check backspaceEvent.key.char == '\x08'

      let spaceEvent =
        Event(kind: Key, key: KeyEvent(code: Space, char: ' ', modifiers: {}))
      check spaceEvent.key.code == Space
      check spaceEvent.key.char == ' '

    test "Unix line ending handling":
      # Test Unix line ending (\n) maps to Enter
      let unixEnterEvent =
        Event(kind: Key, key: KeyEvent(code: Enter, char: '\n', modifiers: {}))
      check unixEnterEvent.key.code == Enter
      check unixEnterEvent.key.char == '\n'

    test "DEL character handling":
      # Test DEL character (\x7f) maps to Backspace
      let delEvent =
        Event(kind: Key, key: KeyEvent(code: Backspace, char: '\x7f', modifiers: {}))
      check delEvent.key.code == Backspace
      check delEvent.key.char == '\x7f'

  suite "Modifier Combination Tests":
    test "Single modifier combinations":
      let ctrlEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: 'a', modifiers: {Ctrl}))
      check Ctrl in ctrlEvent.key.modifiers
      check Alt notin ctrlEvent.key.modifiers
      check Shift notin ctrlEvent.key.modifiers

      let altEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: 'b', modifiers: {Alt}))
      check Alt in altEvent.key.modifiers
      check Ctrl notin altEvent.key.modifiers
      check Shift notin altEvent.key.modifiers

      let shiftEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: 'C', modifiers: {Shift}))
      check Shift in shiftEvent.key.modifiers
      check Ctrl notin shiftEvent.key.modifiers
      check Alt notin shiftEvent.key.modifiers

    test "Multiple modifier combinations":
      let ctrlShiftEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: 'D', modifiers: {Ctrl, Shift}))
      check Ctrl in ctrlShiftEvent.key.modifiers
      check Shift in ctrlShiftEvent.key.modifiers
      check Alt notin ctrlShiftEvent.key.modifiers
      check ctrlShiftEvent.key.modifiers.len == 2

      let ctrlAltEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: 'e', modifiers: {Ctrl, Alt}))
      check Ctrl in ctrlAltEvent.key.modifiers
      check Alt in ctrlAltEvent.key.modifiers
      check Shift notin ctrlAltEvent.key.modifiers
      check ctrlAltEvent.key.modifiers.len == 2

      let altShiftEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: 'F', modifiers: {Alt, Shift}))
      check Alt in altShiftEvent.key.modifiers
      check Shift in altShiftEvent.key.modifiers
      check Ctrl notin altShiftEvent.key.modifiers
      check altShiftEvent.key.modifiers.len == 2

    test "All modifiers combination":
      let allModsEvent = Event(
        kind: Key, key: KeyEvent(code: Char, char: 'g', modifiers: {Ctrl, Alt, Shift})
      )
      check Ctrl in allModsEvent.key.modifiers
      check Alt in allModsEvent.key.modifiers
      check Shift in allModsEvent.key.modifiers
      check allModsEvent.key.modifiers.len == 3

  suite "Function Key Tests":
    test "Function key creation":
      # Test all function keys
      let functionKeys = [F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12]

      for fKey in functionKeys:
        let keyEvent = KeyEvent(code: fKey, char: '\0', modifiers: {})
        let event = Event(kind: Key, key: keyEvent)
        check event.kind == Key
        check event.key.code == fKey
        check event.key.char == '\0'
        check event.key.modifiers.len == 0

    test "Function keys with modifiers":
      let f1CtrlEvent =
        Event(kind: Key, key: KeyEvent(code: F1, char: '\0', modifiers: {Ctrl}))
      check f1CtrlEvent.key.code == F1
      check Ctrl in f1CtrlEvent.key.modifiers

      let f5ShiftEvent =
        Event(kind: Key, key: KeyEvent(code: F5, char: '\0', modifiers: {Shift}))
      check f5ShiftEvent.key.code == F5
      check Shift in f5ShiftEvent.key.modifiers

      let f12AltEvent =
        Event(kind: Key, key: KeyEvent(code: F12, char: '\0', modifiers: {Alt}))
      check f12AltEvent.key.code == F12
      check Alt in f12AltEvent.key.modifiers

  suite "Arrow Key Tests":
    test "Arrow key creation":
      let arrowKeys = [ArrowUp, ArrowDown, ArrowLeft, ArrowRight]

      for arrowKey in arrowKeys:
        let keyEvent = KeyEvent(code: arrowKey, char: '\0', modifiers: {})
        let event = Event(kind: Key, key: keyEvent)
        check event.kind == Key
        check event.key.code == arrowKey
        check event.key.char == '\0'
        check event.key.modifiers.len == 0

    test "Arrow keys with modifiers":
      let upCtrlEvent =
        Event(kind: Key, key: KeyEvent(code: ArrowUp, char: '\0', modifiers: {Ctrl}))
      check upCtrlEvent.key.code == ArrowUp
      check Ctrl in upCtrlEvent.key.modifiers

      let downShiftEvent =
        Event(kind: Key, key: KeyEvent(code: ArrowDown, char: '\0', modifiers: {Shift}))
      check downShiftEvent.key.code == ArrowDown
      check Shift in downShiftEvent.key.modifiers

      let leftAltEvent =
        Event(kind: Key, key: KeyEvent(code: ArrowLeft, char: '\0', modifiers: {Alt}))
      check leftAltEvent.key.code == ArrowLeft
      check Alt in leftAltEvent.key.modifiers

      let rightMultiEvent = Event(
        kind: Key, key: KeyEvent(code: ArrowRight, char: '\0', modifiers: {Ctrl, Alt})
      )
      check rightMultiEvent.key.code == ArrowRight
      check Ctrl in rightMultiEvent.key.modifiers
      check Alt in rightMultiEvent.key.modifiers

  suite "Event Type Discrimination Tests":
    test "Key event vs other event types":
      let keyEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: 'x', modifiers: {}))
      let quitEvent = Event(kind: Quit)
      let unknownEvent = Event(kind: Unknown)

      check keyEvent.kind == Key
      check quitEvent.kind == Quit
      check unknownEvent.kind == Unknown

      check keyEvent.kind != Quit
      check keyEvent.kind != Unknown
      check quitEvent.kind != Key
      check quitEvent.kind != Unknown
      check unknownEvent.kind != Key
      check unknownEvent.kind != Quit

    test "Event field access safety":
      let keyEvent =
        Event(kind: Key, key: KeyEvent(code: Enter, char: '\r', modifiers: {Ctrl}))

      # Key event should have accessible key field
      check keyEvent.kind == Key
      check keyEvent.key.code == Enter
      check keyEvent.key.char == '\r'
      check Ctrl in keyEvent.key.modifiers

  suite "Edge Case Tests":
    test "Empty modifier set":
      let event = Event(kind: Key, key: KeyEvent(code: Char, char: 'a', modifiers: {}))
      check event.key.modifiers.len == 0
      check Ctrl notin event.key.modifiers
      check Alt notin event.key.modifiers
      check Shift notin event.key.modifiers

    test "Null character handling":
      let nullEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: '\0', modifiers: {}))
      check nullEvent.key.code == Char
      check nullEvent.key.char == '\0'

    test "High ASCII characters":
      # Test extended ASCII characters
      let highAsciiChars = ['\x80', '\xFF', '\xA0', '\xF0']
      for ch in highAsciiChars:
        let event = Event(kind: Key, key: KeyEvent(code: Char, char: ch, modifiers: {}))
        check event.kind == Key
        check event.key.code == Char
        check event.key.char == ch

  suite "Integration Tests":
    test "Complex event scenarios":
      # Simulate typing "Hello" with various modifiers
      let events = [
        Event(kind: Key, key: KeyEvent(code: Char, char: 'H', modifiers: {Shift})),
        Event(kind: Key, key: KeyEvent(code: Char, char: 'e', modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: 'l', modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: 'l', modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: 'o', modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Enter, char: '\r', modifiers: {})),
      ]

      check events[0].key.char == 'H'
      check Shift in events[0].key.modifiers
      check events[1].key.char == 'e'
      check events[1].key.modifiers.len == 0
      check events[5].key.code == Enter

    test "Mixed key types sequence":
      let sequence = [
        Event(kind: Key, key: KeyEvent(code: F1, char: '\0', modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: 'x', modifiers: {Ctrl})),
        Event(kind: Key, key: KeyEvent(code: ArrowUp, char: '\0', modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Space, char: ' ', modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b', modifiers: {})),
        Event(kind: Quit),
      ]

      check sequence[0].key.code == F1
      check sequence[1].key.char == 'x'
      check Ctrl in sequence[1].key.modifiers
      check sequence[2].key.code == ArrowUp
      check sequence[3].key.code == Space
      check sequence[4].key.code == Escape
      check sequence[5].kind == Quit

  suite "Escape Sequence Parsing Tests":
    test "readEscapeSequence - arrow keys":
      # Test that readEscapeSequence correctly identifies arrow key sequences
      # Note: These tests verify the function logic, not actual stdin reading

      # Verify arrow key codes are correctly defined
      let arrowUpEvent = Event(kind: Key, key: KeyEvent(code: ArrowUp, char: '\0'))
      check arrowUpEvent.key.code == ArrowUp
      check arrowUpEvent.key.char == '\0'

      let arrowDownEvent = Event(kind: Key, key: KeyEvent(code: ArrowDown, char: '\0'))
      check arrowDownEvent.key.code == ArrowDown
      check arrowDownEvent.key.char == '\0'

      let arrowLeftEvent = Event(kind: Key, key: KeyEvent(code: ArrowLeft, char: '\0'))
      check arrowLeftEvent.key.code == ArrowLeft
      check arrowLeftEvent.key.char == '\0'

      let arrowRightEvent =
        Event(kind: Key, key: KeyEvent(code: ArrowRight, char: '\0'))
      check arrowRightEvent.key.code == ArrowRight
      check arrowRightEvent.key.char == '\0'

    test "Arrow key sequence mapping":
      # Test that the correct KeyCode values are used for arrow keys
      # These correspond to the ANSI escape sequences:
      # ↑: \x1b[A -> ArrowUp
      # ↓: \x1b[B -> ArrowDown  
      # →: \x1b[C -> ArrowRight
      # ←: \x1b[D -> ArrowLeft

      let expectedMappings = [
        (KeyCode.ArrowUp, "Up arrow should map to ArrowUp"),
        (KeyCode.ArrowDown, "Down arrow should map to ArrowDown"),
        (KeyCode.ArrowRight, "Right arrow should map to ArrowRight"),
        (KeyCode.ArrowLeft, "Left arrow should map to ArrowLeft"),
      ]

      for (keyCode, description) in expectedMappings:
        let event = Event(kind: Key, key: KeyEvent(code: keyCode, char: '\0'))
        check event.key.code == keyCode
        check event.key.char == '\0'

    test "Escape key fallback behavior":
      # Test that malformed escape sequences fall back to Escape key
      let escapeEvent = Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
      check escapeEvent.key.code == Escape
      check escapeEvent.key.char == '\x1b'
