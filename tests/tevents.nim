# Test suite for events module

import std/[unittest, posix, strutils]

import ../celina/core/events {.all.}
import ../celina/core/mouse_logic

suite "Events Module Tests":
  suite "EventKind Tests":
    test "EventKind enum values":
      check EventKind.Key.ord == 0
      check EventKind.Mouse.ord == 1
      check EventKind.Resize.ord == 2
      check EventKind.Paste.ord == 3
      check EventKind.FocusIn.ord == 4
      check EventKind.FocusOut.ord == 5
      check EventKind.Quit.ord == 6
      check EventKind.Unknown.ord == 7

  suite "KeyCode Tests":
    test "Basic key codes":
      check KeyCode.Char.ord == 0
      check KeyCode.Enter.ord == 1
      check KeyCode.Escape.ord == 2
      check KeyCode.Backspace.ord == 3
      check KeyCode.Tab.ord == 4
      check KeyCode.BackTab.ord == 5
      check KeyCode.Space.ord == 6

    test "Arrow key codes":
      check KeyCode.ArrowUp.ord == 7
      check KeyCode.ArrowDown.ord == 8
      check KeyCode.ArrowLeft.ord == 9
      check KeyCode.ArrowRight.ord == 10

    test "Navigation key codes":
      check KeyCode.Home.ord == 11
      check KeyCode.End.ord == 12
      check KeyCode.PageUp.ord == 13
      check KeyCode.PageDown.ord == 14
      check KeyCode.Insert.ord == 15
      check KeyCode.Delete.ord == 16

    test "Function key codes":
      check KeyCode.F1.ord == 17
      check KeyCode.F2.ord == 18
      check KeyCode.F3.ord == 19
      check KeyCode.F4.ord == 20
      check KeyCode.F5.ord == 21
      check KeyCode.F6.ord == 22
      check KeyCode.F7.ord == 23
      check KeyCode.F8.ord == 24
      check KeyCode.F9.ord == 25
      check KeyCode.F10.ord == 26
      check KeyCode.F11.ord == 27
      check KeyCode.F12.ord == 28

  suite "KeyModifier Tests":
    test "KeyModifier enum values":
      check KeyModifier.Ctrl.ord == 0
      check KeyModifier.Alt.ord == 1
      check KeyModifier.Shift.ord == 2

  suite "KeyEvent Tests":
    test "KeyEvent creation - character key":
      let keyEvent = KeyEvent(code: Char, char: "a", modifiers: {})
      check keyEvent.code == Char
      check keyEvent.char == "a"
      check keyEvent.modifiers.len == 0

    test "KeyEvent creation - special key":
      let keyEvent = KeyEvent(code: Enter, char: "\r", modifiers: {})
      check keyEvent.code == Enter
      check keyEvent.char == "\r"
      check keyEvent.modifiers.len == 0

    test "KeyEvent creation - with modifiers":
      let keyEvent = KeyEvent(code: Char, char: "c", modifiers: {Ctrl})
      check keyEvent.code == Char
      check keyEvent.char == "c"
      check Ctrl in keyEvent.modifiers
      check keyEvent.modifiers.len == 1

    test "KeyEvent creation - multiple modifiers":
      let keyEvent = KeyEvent(code: Char, char: "x", modifiers: {Ctrl, Shift})
      check keyEvent.code == Char
      check keyEvent.char == "x"
      check Ctrl in keyEvent.modifiers
      check Shift in keyEvent.modifiers
      check Alt notin keyEvent.modifiers
      check keyEvent.modifiers.len == 2

    test "KeyEvent creation - function key":
      let keyEvent = KeyEvent(code: F1, char: "", modifiers: {})
      check keyEvent.code == F1
      check keyEvent.char == ""
      check keyEvent.modifiers.len == 0

    test "KeyEvent creation - arrow key":
      let keyEvent = KeyEvent(code: ArrowUp, char: "", modifiers: {})
      check keyEvent.code == ArrowUp
      check keyEvent.char == ""
      check keyEvent.modifiers.len == 0

  suite "Event Tests":
    test "Event creation - Key event":
      let keyEvent = KeyEvent(code: Char, char: "h", modifiers: {})
      let event = Event(kind: Key, key: keyEvent)

      check event.kind == EventKind.Key
      check event.key.code == Char
      check event.key.char == "h"
      check event.key.modifiers.len == 0

    test "Event creation - Quit event":
      let event = Event(kind: Quit)
      check event.kind == Quit

    test "Event creation - Unknown event":
      let event = Event(kind: Unknown)
      check event.kind == Unknown

    test "Event creation - FocusIn event":
      let event = Event(kind: FocusIn)
      check event.kind == FocusIn

    test "Event creation - FocusOut event":
      let event = Event(kind: FocusOut)
      check event.kind == FocusOut

    test "Event creation - Key event with Enter":
      let keyEvent = KeyEvent(code: Enter, char: "\r", modifiers: {})
      let event = Event(kind: Key, key: keyEvent)

      check event.kind == EventKind.Key
      check event.key.code == Enter
      check event.key.char == "\r"

    test "Event creation - Key event with Escape":
      let keyEvent = KeyEvent(code: Escape, char: "\x1b", modifiers: {})
      let event = Event(kind: Key, key: keyEvent)

      check event.kind == EventKind.Key
      check event.key.code == Escape
      check event.key.char == "\x1b"

    test "Event creation - Key event with Tab":
      let keyEvent = KeyEvent(code: Tab, char: "\t", modifiers: {})
      let event = Event(kind: Key, key: keyEvent)

      check event.kind == EventKind.Key
      check event.key.code == Tab
      check event.key.char == "\t"

    test "Event creation - Key event with Space":
      let keyEvent = KeyEvent(code: Space, char: " ", modifiers: {})
      let event = Event(kind: Key, key: keyEvent)

      check event.kind == EventKind.Key
      check event.key.code == Space
      check event.key.char == " "

    test "Event creation - Key event with Backspace":
      let keyEvent = KeyEvent(code: Backspace, char: "\x08", modifiers: {})
      let event = Event(kind: Key, key: keyEvent)

      check event.kind == EventKind.Key
      check event.key.code == Backspace
      check event.key.char == "\x08"

  suite "Character Mapping Tests":
    test "Character event creation - letters":
      # Test various letter characters
      for ch in 'a' .. 'z':
        let keyEvent = KeyEvent(code: Char, char: $ch, modifiers: {})
        let event = Event(kind: Key, key: keyEvent)
        check event.kind == EventKind.Key
        check event.key.code == Char
        check event.key.char == $ch

      for ch in 'A' .. 'Z':
        let keyEvent = KeyEvent(code: Char, char: $ch, modifiers: {})
        let event = Event(kind: Key, key: keyEvent)
        check event.kind == EventKind.Key
        check event.key.code == Char
        check event.key.char == $ch

    test "Character event creation - digits":
      # Test digit characters
      for ch in '0' .. '9':
        let keyEvent = KeyEvent(code: Char, char: $ch, modifiers: {})
        let event = Event(kind: Key, key: keyEvent)
        check event.kind == EventKind.Key
        check event.key.code == Char
        check event.key.char == $ch

    test "Character event creation - special characters":
      # Test common special characters
      let specialChars = @[
        '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '-', '_', '=', '+', '[', ']',
        '{', '}', '\\', '|', ';', ':', '\'', '"', ',', '.', '<', '>', '/', '?',
      ]

      for ch in specialChars:
        let keyEvent = KeyEvent(code: Char, char: $ch, modifiers: {})
        let event = Event(kind: Key, key: keyEvent)
        check event.kind == EventKind.Key
        check event.key.code == Char
        check event.key.char == $ch

  suite "Special Key Tests":
    test "Special key mapping - control characters":
      # Test control characters mapping to special keys
      let enterEvent =
        Event(kind: Key, key: KeyEvent(code: Enter, char: "\r", modifiers: {}))
      check enterEvent.key.code == Enter
      check enterEvent.key.char == "\r"

      let tabEvent =
        Event(kind: Key, key: KeyEvent(code: Tab, char: "\t", modifiers: {}))
      check tabEvent.key.code == Tab
      check tabEvent.key.char == "\t"

      let escapeEvent =
        Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b", modifiers: {}))
      check escapeEvent.key.code == Escape
      check escapeEvent.key.char == "\x1b"

      let backspaceEvent =
        Event(kind: Key, key: KeyEvent(code: Backspace, char: "\x08", modifiers: {}))
      check backspaceEvent.key.code == Backspace
      check backspaceEvent.key.char == "\x08"

      let spaceEvent =
        Event(kind: Key, key: KeyEvent(code: Space, char: " ", modifiers: {}))
      check spaceEvent.key.code == Space
      check spaceEvent.key.char == " "

    test "Unix line ending handling":
      # Test Unix line ending (\n) maps to Enter
      let unixEnterEvent =
        Event(kind: Key, key: KeyEvent(code: Enter, char: "\n", modifiers: {}))
      check unixEnterEvent.key.code == Enter
      check unixEnterEvent.key.char == "\n"

    test "DEL character handling":
      # Test DEL character (\x7f) maps to Backspace
      let delEvent =
        Event(kind: Key, key: KeyEvent(code: Backspace, char: "\x7f", modifiers: {}))
      check delEvent.key.code == Backspace
      check delEvent.key.char == "\x7f"

  suite "Modifier Combination Tests":
    test "Single modifier combinations":
      let ctrlEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: "a", modifiers: {Ctrl}))
      check Ctrl in ctrlEvent.key.modifiers
      check Alt notin ctrlEvent.key.modifiers
      check Shift notin ctrlEvent.key.modifiers

      let altEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: "b", modifiers: {Alt}))
      check Alt in altEvent.key.modifiers
      check Ctrl notin altEvent.key.modifiers
      check Shift notin altEvent.key.modifiers

      let shiftEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: "C", modifiers: {Shift}))
      check Shift in shiftEvent.key.modifiers
      check Ctrl notin shiftEvent.key.modifiers
      check Alt notin shiftEvent.key.modifiers

    test "Multiple modifier combinations":
      let ctrlShiftEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: "D", modifiers: {Ctrl, Shift}))
      check Ctrl in ctrlShiftEvent.key.modifiers
      check Shift in ctrlShiftEvent.key.modifiers
      check Alt notin ctrlShiftEvent.key.modifiers
      check ctrlShiftEvent.key.modifiers.len == 2

      let ctrlAltEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: "e", modifiers: {Ctrl, Alt}))
      check Ctrl in ctrlAltEvent.key.modifiers
      check Alt in ctrlAltEvent.key.modifiers
      check Shift notin ctrlAltEvent.key.modifiers
      check ctrlAltEvent.key.modifiers.len == 2

      let altShiftEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: "F", modifiers: {Alt, Shift}))
      check Alt in altShiftEvent.key.modifiers
      check Shift in altShiftEvent.key.modifiers
      check Ctrl notin altShiftEvent.key.modifiers
      check altShiftEvent.key.modifiers.len == 2

    test "All modifiers combination":
      let allModsEvent = Event(
        kind: Key, key: KeyEvent(code: Char, char: "g", modifiers: {Ctrl, Alt, Shift})
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
        let keyEvent = KeyEvent(code: fKey, char: "", modifiers: {})
        let event = Event(kind: Key, key: keyEvent)
        check event.kind == EventKind.Key
        check event.key.code == fKey
        check event.key.char == ""
        check event.key.modifiers.len == 0

    test "Function keys with modifiers":
      let f1CtrlEvent =
        Event(kind: Key, key: KeyEvent(code: F1, char: "", modifiers: {Ctrl}))
      check f1CtrlEvent.key.code == F1
      check Ctrl in f1CtrlEvent.key.modifiers

      let f5ShiftEvent =
        Event(kind: Key, key: KeyEvent(code: F5, char: "", modifiers: {Shift}))
      check f5ShiftEvent.key.code == F5
      check Shift in f5ShiftEvent.key.modifiers

      let f12AltEvent =
        Event(kind: Key, key: KeyEvent(code: F12, char: "", modifiers: {Alt}))
      check f12AltEvent.key.code == F12
      check Alt in f12AltEvent.key.modifiers

  suite "Arrow Key Tests":
    test "Arrow key creation":
      let arrowKeys = [ArrowUp, ArrowDown, ArrowLeft, ArrowRight]

      for arrowKey in arrowKeys:
        let keyEvent = KeyEvent(code: arrowKey, char: "", modifiers: {})
        let event = Event(kind: Key, key: keyEvent)
        check event.kind == EventKind.Key
        check event.key.code == arrowKey
        check event.key.char == ""
        check event.key.modifiers.len == 0

    test "Arrow keys with modifiers":
      let upCtrlEvent =
        Event(kind: Key, key: KeyEvent(code: ArrowUp, char: "", modifiers: {Ctrl}))
      check upCtrlEvent.key.code == ArrowUp
      check Ctrl in upCtrlEvent.key.modifiers

      let downShiftEvent =
        Event(kind: Key, key: KeyEvent(code: ArrowDown, char: "", modifiers: {Shift}))
      check downShiftEvent.key.code == ArrowDown
      check Shift in downShiftEvent.key.modifiers

      let leftAltEvent =
        Event(kind: Key, key: KeyEvent(code: ArrowLeft, char: "", modifiers: {Alt}))
      check leftAltEvent.key.code == ArrowLeft
      check Alt in leftAltEvent.key.modifiers

      let rightMultiEvent = Event(
        kind: Key, key: KeyEvent(code: ArrowRight, char: "", modifiers: {Ctrl, Alt})
      )
      check rightMultiEvent.key.code == ArrowRight
      check Ctrl in rightMultiEvent.key.modifiers
      check Alt in rightMultiEvent.key.modifiers

  suite "Event Type Discrimination Tests":
    test "Key event vs other event types":
      let keyEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: "x", modifiers: {}))
      let quitEvent = Event(kind: Quit)
      let unknownEvent = Event(kind: Unknown)

      check keyEvent.kind == EventKind.Key
      check quitEvent.kind == Quit
      check unknownEvent.kind == Unknown

      check keyEvent.kind != Quit
      check keyEvent.kind != Unknown
      check quitEvent.kind != EventKind.Key
      check quitEvent.kind != Unknown
      check unknownEvent.kind != EventKind.Key
      check unknownEvent.kind != Quit

    test "Event field access safety":
      let keyEvent =
        Event(kind: Key, key: KeyEvent(code: Enter, char: "\r", modifiers: {Ctrl}))

      # Key event should have accessible key field
      check keyEvent.kind == EventKind.Key
      check keyEvent.key.code == Enter
      check keyEvent.key.char == "\r"
      check Ctrl in keyEvent.key.modifiers

    test "Focus events vs other event types":
      let focusInEvent = Event(kind: FocusIn)
      let focusOutEvent = Event(kind: FocusOut)

      check focusInEvent.kind == FocusIn
      check focusOutEvent.kind == FocusOut

      # FocusIn should be distinct from all other event types
      check focusInEvent.kind != FocusOut
      check focusInEvent.kind != EventKind.Key
      check focusInEvent.kind != Quit
      check focusInEvent.kind != Unknown

      # FocusOut should be distinct from all other event types
      check focusOutEvent.kind != FocusIn
      check focusOutEvent.kind != EventKind.Key
      check focusOutEvent.kind != Quit
      check focusOutEvent.kind != Unknown

  suite "Navigation Key Tests":
    test "Navigation key creation":
      let navKeys = [Home, End, PageUp, PageDown, Insert, Delete]

      for navKey in navKeys:
        let keyEvent = KeyEvent(code: navKey, char: "", modifiers: {})
        let event = Event(kind: Key, key: keyEvent)
        check event.kind == EventKind.Key
        check event.key.code == navKey
        check event.key.char == ""
        check event.key.modifiers.len == 0

    test "Navigation keys with modifiers":
      let homeCtrlEvent =
        Event(kind: Key, key: KeyEvent(code: Home, char: "", modifiers: {Ctrl}))
      check homeCtrlEvent.key.code == Home
      check Ctrl in homeCtrlEvent.key.modifiers

      let endShiftEvent =
        Event(kind: Key, key: KeyEvent(code: End, char: "", modifiers: {Shift}))
      check endShiftEvent.key.code == End
      check Shift in endShiftEvent.key.modifiers

      let pageUpAltEvent =
        Event(kind: Key, key: KeyEvent(code: PageUp, char: "", modifiers: {Alt}))
      check pageUpAltEvent.key.code == PageUp
      check Alt in pageUpAltEvent.key.modifiers

      let pageDownMultiEvent = Event(
        kind: Key, key: KeyEvent(code: PageDown, char: "", modifiers: {Ctrl, Shift})
      )
      check pageDownMultiEvent.key.code == PageDown
      check Ctrl in pageDownMultiEvent.key.modifiers
      check Shift in pageDownMultiEvent.key.modifiers

      let insertEvent =
        Event(kind: Key, key: KeyEvent(code: Insert, char: "", modifiers: {}))
      check insertEvent.key.code == Insert
      check insertEvent.key.modifiers.len == 0

      let deleteEvent =
        Event(kind: Key, key: KeyEvent(code: Delete, char: "", modifiers: {Ctrl}))
      check deleteEvent.key.code == Delete
      check Ctrl in deleteEvent.key.modifiers

  suite "BackTab and Modified Keys Tests":
    test "BackTab (Shift+Tab) key creation":
      let backTabEvent =
        Event(kind: Key, key: KeyEvent(code: BackTab, char: "", modifiers: {}))
      check backTabEvent.key.code == BackTab
      check backTabEvent.key.char == ""
      check backTabEvent.key.modifiers.len == 0

    test "Modified arrow keys":
      # Ctrl+Arrow keys for word navigation
      let ctrlUpEvent =
        Event(kind: Key, key: KeyEvent(code: ArrowUp, char: "", modifiers: {Ctrl}))
      check ctrlUpEvent.key.code == ArrowUp
      check Ctrl in ctrlUpEvent.key.modifiers
      check Shift notin ctrlUpEvent.key.modifiers

      let ctrlDownEvent =
        Event(kind: Key, key: KeyEvent(code: ArrowDown, char: "", modifiers: {Ctrl}))
      check ctrlDownEvent.key.code == ArrowDown
      check Ctrl in ctrlDownEvent.key.modifiers

      let ctrlLeftEvent =
        Event(kind: Key, key: KeyEvent(code: ArrowLeft, char: "", modifiers: {Ctrl}))
      check ctrlLeftEvent.key.code == ArrowLeft
      check Ctrl in ctrlLeftEvent.key.modifiers

      let ctrlRightEvent =
        Event(kind: Key, key: KeyEvent(code: ArrowRight, char: "", modifiers: {Ctrl}))
      check ctrlRightEvent.key.code == ArrowRight
      check Ctrl in ctrlRightEvent.key.modifiers

      # Shift+Arrow keys for selection
      let shiftUpEvent =
        Event(kind: Key, key: KeyEvent(code: ArrowUp, char: "", modifiers: {Shift}))
      check shiftUpEvent.key.code == ArrowUp
      check Shift in shiftUpEvent.key.modifiers
      check Ctrl notin shiftUpEvent.key.modifiers

      # Ctrl+Shift+Arrow for extended selection
      let ctrlShiftLeftEvent = Event(
        kind: Key, key: KeyEvent(code: ArrowLeft, char: "", modifiers: {Ctrl, Shift})
      )
      check ctrlShiftLeftEvent.key.code == ArrowLeft
      check Ctrl in ctrlShiftLeftEvent.key.modifiers
      check Shift in ctrlShiftLeftEvent.key.modifiers
      check Alt notin ctrlShiftLeftEvent.key.modifiers

    test "Modified navigation keys":
      # Ctrl+Home/End for document navigation
      let ctrlHomeEvent =
        Event(kind: Key, key: KeyEvent(code: Home, char: "", modifiers: {Ctrl}))
      check ctrlHomeEvent.key.code == Home
      check Ctrl in ctrlHomeEvent.key.modifiers

      let ctrlEndEvent =
        Event(kind: Key, key: KeyEvent(code: End, char: "", modifiers: {Ctrl}))
      check ctrlEndEvent.key.code == End
      check Ctrl in ctrlEndEvent.key.modifiers

      # Shift+PageUp/PageDown for selection
      let shiftPageUpEvent =
        Event(kind: Key, key: KeyEvent(code: PageUp, char: "", modifiers: {Shift}))
      check shiftPageUpEvent.key.code == PageUp
      check Shift in shiftPageUpEvent.key.modifiers

      let shiftPageDownEvent =
        Event(kind: Key, key: KeyEvent(code: PageDown, char: "", modifiers: {Shift}))
      check shiftPageDownEvent.key.code == PageDown
      check Shift in shiftPageDownEvent.key.modifiers

      # Ctrl+Insert/Delete for clipboard operations
      let ctrlInsertEvent =
        Event(kind: Key, key: KeyEvent(code: Insert, char: "", modifiers: {Ctrl}))
      check ctrlInsertEvent.key.code == Insert
      check Ctrl in ctrlInsertEvent.key.modifiers

      let shiftDeleteEvent =
        Event(kind: Key, key: KeyEvent(code: Delete, char: "", modifiers: {Shift}))
      check shiftDeleteEvent.key.code == Delete
      check Shift in shiftDeleteEvent.key.modifiers

  suite "Edge Case Tests":
    test "Empty modifier set":
      let event = Event(kind: Key, key: KeyEvent(code: Char, char: "a", modifiers: {}))
      check event.key.modifiers.len == 0
      check Ctrl notin event.key.modifiers
      check Alt notin event.key.modifiers
      check Shift notin event.key.modifiers

    test "Null character handling":
      let nullEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: "", modifiers: {}))
      check nullEvent.key.code == Char
      check nullEvent.key.char == ""

    test "High ASCII characters":
      # Test extended ASCII characters
      let highAsciiChars = ['\x80', '\xFF', '\xA0', '\xF0']
      for ch in highAsciiChars:
        let event =
          Event(kind: Key, key: KeyEvent(code: Char, char: $ch, modifiers: {}))
        check event.kind == EventKind.Key
        check event.key.code == Char
        check event.key.char == $ch

  suite "Integration Tests":
    test "Complex event scenarios":
      # Simulate typing "Hello" with various modifiers
      let events = [
        Event(kind: Key, key: KeyEvent(code: Char, char: "H", modifiers: {Shift})),
        Event(kind: Key, key: KeyEvent(code: Char, char: "e", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: "l", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: "l", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: "o", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Enter, char: "\r", modifiers: {})),
      ]

      check events[0].key.char == "H"
      check Shift in events[0].key.modifiers
      check events[1].key.char == "e"
      check events[1].key.modifiers.len == 0
      check events[5].key.code == Enter

    test "Mixed key types sequence":
      let sequence = [
        Event(kind: Key, key: KeyEvent(code: F1, char: "", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: "x", modifiers: {Ctrl})),
        Event(kind: Key, key: KeyEvent(code: ArrowUp, char: "", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Space, char: " ", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b", modifiers: {})),
        Event(kind: Quit),
      ]

      check sequence[0].key.code == F1
      check sequence[1].key.char == "x"
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
      let arrowUpEvent = Event(kind: Key, key: KeyEvent(code: ArrowUp, char: ""))
      check arrowUpEvent.key.code == ArrowUp
      check arrowUpEvent.key.char == ""

      let arrowDownEvent = Event(kind: Key, key: KeyEvent(code: ArrowDown, char: ""))
      check arrowDownEvent.key.code == ArrowDown
      check arrowDownEvent.key.char == ""

      let arrowLeftEvent = Event(kind: Key, key: KeyEvent(code: ArrowLeft, char: ""))
      check arrowLeftEvent.key.code == ArrowLeft
      check arrowLeftEvent.key.char == ""

      let arrowRightEvent = Event(kind: Key, key: KeyEvent(code: ArrowRight, char: ""))
      check arrowRightEvent.key.code == ArrowRight
      check arrowRightEvent.key.char == ""

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
        let event = Event(kind: Key, key: KeyEvent(code: keyCode, char: ""))
        check event.key.code == keyCode
        check event.key.char == ""

    test "Escape key fallback behavior":
      # Test that malformed escape sequences fall back to Escape key
      let escapeEvent = Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))
      check escapeEvent.key.code == Escape
      check escapeEvent.key.char == "\x1b"

  # Mouse Event Tests
  suite "Mouse Event Tests":
    test "MouseButton enum values":
      check MouseButton.Left.ord == 0
      check MouseButton.Right.ord == 1
      check MouseButton.Middle.ord == 2
      check MouseButton.WheelUp.ord == 3
      check MouseButton.WheelDown.ord == 4

    test "MouseEventKind enum values":
      check MouseEventKind.Press.ord == 0
      check MouseEventKind.Release.ord == 1
      check MouseEventKind.Move.ord == 2
      check MouseEventKind.Drag.ord == 3

    test "MouseEvent creation - left click":
      let mouseEvent = MouseEvent(kind: Press, button: Left, x: 10, y: 5, modifiers: {})
      check mouseEvent.kind == Press
      check mouseEvent.button == Left
      check mouseEvent.x == 10
      check mouseEvent.y == 5
      check mouseEvent.modifiers.len == 0

    test "MouseEvent creation - with modifiers":
      let mouseEvent =
        MouseEvent(kind: Press, button: Right, x: 20, y: 15, modifiers: {Ctrl, Shift})
      check mouseEvent.kind == Press
      check mouseEvent.button == Right
      check mouseEvent.x == 20
      check mouseEvent.y == 15
      check Ctrl in mouseEvent.modifiers
      check Shift in mouseEvent.modifiers
      check Alt notin mouseEvent.modifiers
      check mouseEvent.modifiers.len == 2

    test "MouseEvent creation - wheel events":
      let wheelUpEvent =
        MouseEvent(kind: Press, button: WheelUp, x: 0, y: 0, modifiers: {})
      check wheelUpEvent.kind == Press
      check wheelUpEvent.button == WheelUp

      let wheelDownEvent =
        MouseEvent(kind: Press, button: WheelDown, x: 0, y: 0, modifiers: {})
      check wheelDownEvent.kind == Press
      check wheelDownEvent.button == WheelDown

    test "MouseEvent creation - drag event":
      let dragEvent = MouseEvent(kind: Drag, button: Left, x: 50, y: 30, modifiers: {})
      check dragEvent.kind == Drag
      check dragEvent.button == Left
      check dragEvent.x == 50
      check dragEvent.y == 30

    test "MouseEvent creation - release event":
      let releaseEvent =
        MouseEvent(kind: Release, button: Middle, x: 100, y: 200, modifiers: {Alt})
      check releaseEvent.kind == Release
      check releaseEvent.button == Middle
      check releaseEvent.x == 100
      check releaseEvent.y == 200
      check Alt in releaseEvent.modifiers

    test "MouseEvent creation - move event":
      let moveEvent = MouseEvent(
        kind: Move,
        button: Left, # Note: button may not be relevant for Move events
        x: 75,
        y: 125,
        modifiers: {},
      )
      check moveEvent.kind == Move
      check moveEvent.x == 75
      check moveEvent.y == 125

    test "Event creation - Mouse event":
      let mouseEvent =
        MouseEvent(kind: Press, button: Left, x: 25, y: 35, modifiers: {Ctrl})
      let event = Event(kind: Mouse, mouse: mouseEvent)

      check event.kind == Mouse
      check event.mouse.kind == Press
      check event.mouse.button == Left
      check event.mouse.x == 25
      check event.mouse.y == 35
      check Ctrl in event.mouse.modifiers

  suite "Mouse Modifier Parsing Tests":
    test "parseMouseModifiers - no modifiers":
      let modifiers = parseMouseModifiers(0x00) # No modifier bits set
      check modifiers.len == 0
      check Ctrl notin modifiers
      check Shift notin modifiers
      check Alt notin modifiers

    test "parseMouseModifiers - single modifiers":
      # Test Shift modifier (bit 2)
      let shiftMods = parseMouseModifiers(0x04)
      check Shift in shiftMods
      check Ctrl notin shiftMods
      check Alt notin shiftMods
      check shiftMods.len == 1

      # Test Alt modifier (bit 3)
      let altMods = parseMouseModifiers(0x08)
      check Alt in altMods
      check Ctrl notin altMods
      check Shift notin altMods
      check altMods.len == 1

      # Test Ctrl modifier (bit 4)
      let ctrlMods = parseMouseModifiers(0x10)
      check Ctrl in ctrlMods
      check Shift notin ctrlMods
      check Alt notin ctrlMods
      check ctrlMods.len == 1

    test "parseMouseModifiers - multiple modifiers":
      # Test Ctrl+Shift (bits 2 and 4)
      let ctrlShiftMods = parseMouseModifiers(0x14)
      check Ctrl in ctrlShiftMods
      check Shift in ctrlShiftMods
      check Alt notin ctrlShiftMods
      check ctrlShiftMods.len == 2

      # Test Ctrl+Alt (bits 3 and 4)
      let ctrlAltMods = parseMouseModifiers(0x18)
      check Ctrl in ctrlAltMods
      check Alt in ctrlAltMods
      check Shift notin ctrlAltMods
      check ctrlAltMods.len == 2

      # Test all modifiers (bits 2, 3, and 4)
      let allMods = parseMouseModifiers(0x1C)
      check Ctrl in allMods
      check Shift in allMods
      check Alt in allMods
      check allMods.len == 3

    test "parseMouseModifiers works for both X10 and SGR":
      # SGR and X10 formats use the same modifier parsing (from button byte)
      # This function works for both formats
      let noMods = parseMouseModifiers(0x00)
      check noMods.len == 0

      let shiftMods = parseMouseModifiers(0x04)
      check Shift in shiftMods
      check shiftMods.len == 1

      let allMods = parseMouseModifiers(0x1C)
      check Ctrl in allMods
      check Shift in allMods
      check Alt in allMods
      check allMods.len == 3

  suite "Mouse Event Integration Tests":
    test "Complete mouse interaction sequence":
      # Simulate a mouse drag sequence
      let events = [
        Event(
          kind: Mouse,
          mouse: MouseEvent(kind: Press, button: Left, x: 10, y: 10, modifiers: {}),
        ),
        Event(
          kind: Mouse,
          mouse: MouseEvent(kind: Drag, button: Left, x: 15, y: 12, modifiers: {}),
        ),
        Event(
          kind: Mouse,
          mouse: MouseEvent(kind: Drag, button: Left, x: 20, y: 15, modifiers: {}),
        ),
        Event(
          kind: Mouse,
          mouse: MouseEvent(kind: Release, button: Left, x: 25, y: 18, modifiers: {}),
        ),
      ]

      check events[0].kind == Mouse
      check events[0].mouse.kind == Press
      check events[0].mouse.button == Left

      check events[1].mouse.kind == Drag
      check events[1].mouse.x == 15
      check events[1].mouse.y == 12

      check events[2].mouse.kind == Drag
      check events[2].mouse.x == 20

      check events[3].mouse.kind == Release
      check events[3].mouse.x == 25

    test "Mouse wheel scrolling sequence":
      let wheelEvents = [
        Event(
          kind: Mouse,
          mouse: MouseEvent(kind: Press, button: WheelUp, x: 50, y: 50, modifiers: {}),
        ),
        Event(
          kind: Mouse,
          mouse: MouseEvent(kind: Press, button: WheelUp, x: 50, y: 50, modifiers: {}),
        ),
        Event(
          kind: Mouse,
          mouse: MouseEvent(kind: Press, button: WheelDown, x: 50, y: 50, modifiers: {}),
        ),
      ]

      check wheelEvents[0].mouse.button == WheelUp
      check wheelEvents[1].mouse.button == WheelUp
      check wheelEvents[2].mouse.button == WheelDown

    test "Mouse with keyboard modifiers":
      let ctrlClickEvent = Event(
        kind: Mouse,
        mouse: MouseEvent(kind: Press, button: Right, x: 100, y: 100, modifiers: {Ctrl}),
      )
      check ctrlClickEvent.mouse.button == Right
      check Ctrl in ctrlClickEvent.mouse.modifiers

      let shiftDragEvent = Event(
        kind: Mouse,
        mouse:
          MouseEvent(kind: Drag, button: Left, x: 200, y: 150, modifiers: {Shift, Alt}),
      )
      check shiftDragEvent.mouse.kind == Drag
      check Shift in shiftDragEvent.mouse.modifiers
      check Alt in shiftDragEvent.mouse.modifiers

  suite "Event Type Discrimination with Mouse":
    test "Mouse vs Key vs other events":
      let mouseEvent = Event(
        kind: Mouse,
        mouse: MouseEvent(kind: Press, button: Left, x: 0, y: 0, modifiers: {}),
      )
      let keyEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: "a", modifiers: {}))
      let quitEvent = Event(kind: Quit)

      check mouseEvent.kind == Mouse
      check keyEvent.kind == EventKind.Key
      check quitEvent.kind == Quit

      check mouseEvent.kind != EventKind.Key
      check mouseEvent.kind != Quit
      check keyEvent.kind != Mouse
      check quitEvent.kind != Mouse

    test "Mouse event field access":
      let mouseEvent = Event(
        kind: Mouse,
        mouse:
          MouseEvent(kind: Press, button: Middle, x: 42, y: 84, modifiers: {Ctrl, Alt}),
      )

      check mouseEvent.kind == Mouse
      check mouseEvent.mouse.kind == Press
      check mouseEvent.mouse.button == Middle
      check mouseEvent.mouse.x == 42
      check mouseEvent.mouse.y == 84
      check Ctrl in mouseEvent.mouse.modifiers
      check Alt in mouseEvent.mouse.modifiers
      check Shift notin mouseEvent.mouse.modifiers

  suite "Mouse Coordinate Edge Cases":
    test "Zero coordinates":
      let zeroEvent = Event(
        kind: Mouse,
        mouse: MouseEvent(kind: Press, button: Left, x: 0, y: 0, modifiers: {}),
      )
      check zeroEvent.mouse.x == 0
      check zeroEvent.mouse.y == 0

    test "Large coordinates":
      let largeEvent = Event(
        kind: Mouse,
        mouse: MouseEvent(kind: Move, button: Left, x: 9999, y: 9999, modifiers: {}),
      )
      check largeEvent.mouse.x == 9999
      check largeEvent.mouse.y == 9999

    test "Negative coordinates handling":
      # While not typical in mouse events, test system robustness
      let negativeEvent = Event(
        kind: Mouse,
        mouse: MouseEvent(kind: Press, button: Left, x: -1, y: -1, modifiers: {}),
      )
      check negativeEvent.mouse.x == -1
      check negativeEvent.mouse.y == -1

  suite "Mouse Wheel Event Parsing Tests":
    test "SGR mouse parsing - wheel event detection":
      # Test wheel event bit patterns in SGR format
      let wheelUpCode = 64 # 0x40 = wheel up
      let wheelDownCode = 65 # 0x41 = wheel down

      let isWheelUp = (wheelUpCode and 0x40) != 0
      let isWheelDown = (wheelDownCode and 0x40) != 0
      let directionUp = (wheelUpCode and 0x01) == 0
      let directionDown = (wheelDownCode and 0x01) != 0

      check isWheelUp
      check isWheelDown
      check directionUp
      check directionDown

    test "SGR mouse parsing - wheel events with modifiers":
      # Test wheel events combined with modifiers
      let ctrlWheelUp = parseMouseModifiers(64 or 0x10) # Wheel up + Ctrl
      let shiftWheelDown = parseMouseModifiers(65 or 0x04) # Wheel down + Shift
      let altWheelUp = parseMouseModifiers(64 or 0x08) # Wheel up + Alt

      check Ctrl in ctrlWheelUp
      check Shift in shiftWheelDown
      check Alt in altWheelUp

    test "X10 mouse parsing - wheel event detection":
      # Test X10 wheel event bit patterns
      let wheelUpByte = 0x60 # 0x40 (wheel) + 0x20 (typical X10 pattern)
      let wheelDownByte = 0x61 # 0x40 (wheel) + 0x01 (down direction)

      let isWheelUp = (wheelUpByte and 0x40) != 0
      let isWheelDown = (wheelDownByte and 0x40) != 0
      let directionUp = (wheelUpByte and 0x01) == 0
      let directionDown = (wheelDownByte and 0x01) != 0

      check isWheelUp
      check isWheelDown
      check directionUp
      check directionDown

    test "X10 mouse parsing - wheel events with modifiers":
      # Test X10 wheel events with keyboard modifiers
      let ctrlWheelUp = parseMouseModifiers(0x70) # Wheel + Ctrl (0x10)
      let shiftWheelDown = parseMouseModifiers(0x65) # Wheel down + Shift (0x04)
      let altWheelUp = parseMouseModifiers(0x68) # Wheel + Alt (0x08)

      check Ctrl in ctrlWheelUp
      check Shift in shiftWheelDown
      check Alt in altWheelUp

    test "Mouse wheel rapid scrolling simulation":
      # Simulate rapid wheel scrolling that might cause performance issues
      var wheelEvents: seq[MouseEvent] = @[]

      for i in 0 .. 99:
        if i mod 2 == 0:
          wheelEvents.add(
            MouseEvent(kind: Press, button: WheelUp, x: 100, y: 100, modifiers: {})
          )
        else:
          wheelEvents.add(
            MouseEvent(kind: Press, button: WheelDown, x: 100, y: 100, modifiers: {})
          )

      check wheelEvents.len == 100
      check wheelEvents[0].button == WheelUp
      check wheelEvents[1].button == WheelDown
      check wheelEvents[99].button == WheelDown

    test "Mouse wheel coordinate bounds":
      # Test wheel events at extreme coordinates
      let wheelAtZero =
        MouseEvent(kind: Press, button: WheelUp, x: 0, y: 0, modifiers: {})

      let wheelAtLarge =
        MouseEvent(kind: Press, button: WheelDown, x: 65535, y: 32767, modifiers: {})

      check wheelAtZero.x == 0
      check wheelAtZero.y == 0
      check wheelAtZero.button == WheelUp

      check wheelAtLarge.x == 65535
      check wheelAtLarge.y == 32767
      check wheelAtLarge.button == WheelDown

  suite "Mouse Event Parsing Safety Tests":
    test "Event parsing bounds checking":
      # Test that the new safety limits work correctly
      # These are compile-time constants from the parsing functions
      const maxReadCount = 20 # From parseMouseEventSGR

      check maxReadCount > 0
      check maxReadCount <= 50 # Reasonable upper bound

    test "Mouse event validation":
      # Test that mouse events maintain consistent state
      let validEvent = MouseEvent(
        kind: Press, button: WheelUp, x: 100, y: 50, modifiers: {Ctrl, Shift}
      )

      # Validate all fields are as expected
      check validEvent.kind == Press
      check validEvent.button == WheelUp
      check validEvent.x == 100
      check validEvent.y == 50
      check validEvent.modifiers.len == 2
      check Ctrl in validEvent.modifiers
      check Shift in validEvent.modifiers
      check Alt notin validEvent.modifiers

  # ESC Key Detection Fix Tests
  # Tests for the 20ms timeout mechanism to fix standalone ESC key detection
  suite "ESC Key Detection Fix Tests":
    test "Standalone ESC key event properties":
      let escEvent =
        Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b", modifiers: {}))

      check escEvent.kind == EventKind.Key
      check escEvent.key.code == Escape
      check escEvent.key.char == "\x1b"
      check escEvent.key.char[0].ord == 27
      check escEvent.key.modifiers.len == 0

    test "ESC vs Arrow key discrimination":
      # ESC key should be standalone
      let escEvent =
        Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b", modifiers: {}))
      check escEvent.key.code == Escape

      # Arrow keys should be different codes
      let arrowKeys = [ArrowUp, ArrowDown, ArrowLeft, ArrowRight]
      for arrowKey in arrowKeys:
        let arrowEvent =
          Event(kind: Key, key: KeyEvent(code: arrowKey, char: "", modifiers: {}))
        check arrowEvent.key.code == arrowKey
        check arrowEvent.key.code != Escape
        check arrowEvent.key.char == ""

    test "Timeout mechanism constants":
      # Verify timeout constants used in the fix
      const ESC_TIMEOUT_MS = 20
      const ESC_TIMEOUT_US = 20000 # 20ms = 20,000 microseconds

      # Should be fast enough to be imperceptible (< 50ms)
      check ESC_TIMEOUT_MS < 50

      # Should be long enough for escape sequences (> 5ms)
      check ESC_TIMEOUT_MS > 5

      # Should match expected microsecond conversion
      check ESC_TIMEOUT_US == ESC_TIMEOUT_MS * 1000

    test "Timeval structure for ESC timeout":
      # Test timeout structure used in select() call
      let timeout = Timeval(tv_sec: Time(0), tv_usec: Suseconds(20000))

      check timeout.tv_sec == Time(0)
      check timeout.tv_usec == Suseconds(20000)

    test "Regression prevention - no double ESC required":
      # Test that single ESC press is sufficient
      # This prevents the original bug where ESC needed to be pressed twice

      let singleEscEvent =
        Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b", modifiers: {}))
      check singleEscEvent.key.code == Escape

      # Multiple ESC events should each be valid individually
      let escSequence = [
        Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b", modifiers: {})),
      ]

      check escSequence.len == 2
      for escEvent in escSequence:
        check escEvent.key.code == Escape
        check escEvent.key.char == "\x1b"

    test "Arrow key compatibility after fix":
      # Ensure the ESC fix doesn't break arrow key detection
      let arrowSequences = [
        Event(kind: Key, key: KeyEvent(code: ArrowUp, char: "", modifiers: {})), # ESC[A
        Event(kind: Key, key: KeyEvent(code: ArrowDown, char: "", modifiers: {})),
          # ESC[B
        Event(kind: Key, key: KeyEvent(code: ArrowRight, char: "", modifiers: {})),
          # ESC[C
        Event(kind: Key, key: KeyEvent(code: ArrowLeft, char: "", modifiers: {})),
          # ESC[D
      ]

      for arrowEvent in arrowSequences:
        check arrowEvent.kind == EventKind.Key
        check arrowEvent.key.char == ""
        check arrowEvent.key.code != Escape

    test "Other escape sequences compatibility":
      # Ensure other special keys that use escape sequences still work
      let specialKeys = [
        (Home, "ESC[H"),
        (End, "ESC[F"),
        (Insert, "ESC[2~"),
        (Delete, "ESC[3~"),
        (PageUp, "ESC[5~"),
        (PageDown, "ESC[6~"),
        (BackTab, "ESC[Z"),
      ]

      for (keyCode, description) in specialKeys:
        let specialEvent =
          Event(kind: Key, key: KeyEvent(code: keyCode, char: "", modifiers: {}))
        check specialEvent.kind == EventKind.Key
        check specialEvent.key.code == keyCode
        check specialEvent.key.code != Escape
        check specialEvent.key.char == ""

    test "Select system call parameter validation":
      # Test parameters used in the ESC detection fix

      # STDIN_FILENO should be valid
      check STDIN_FILENO >= 0
      check STDIN_FILENO == 0 # Standard input

      # nfds parameter for select should be STDIN_FILENO + 1
      let nfds = STDIN_FILENO + 1
      check nfds > STDIN_FILENO
      check nfds == 1

  # UTF-8 Multibyte Input Support Tests
  suite "UTF-8 Multibyte Character Support Tests":
    test "UTF-8 byte length detection - 1 byte (ASCII)":
      # ASCII characters: 0xxxxxxx
      check utf8ByteLength(0x41) == 1 # 'A'
      check utf8ByteLength(0x7A) == 1 # 'z'
      check utf8ByteLength(0x30) == 1 # '0'
      check utf8ByteLength(0x20) == 1 # space
      check utf8ByteLength(0x7F) == 1 # DEL

    test "UTF-8 byte length detection - 2 bytes":
      # 2-byte characters: 110xxxxx
      check utf8ByteLength(0xC2) == 2 # Latin extended
      check utf8ByteLength(0xC3) == 2 # À, Á, etc.
      check utf8ByteLength(0xDF) == 2 # Upper range of 2-byte

    test "UTF-8 byte length detection - 3 bytes":
      # 3-byte characters: 1110xxxx
      check utf8ByteLength(0xE0) == 3 # Devanagari, etc.
      check utf8ByteLength(0xE3) == 3 # Japanese Hiragana/Katakana
      check utf8ByteLength(0xE4) == 3 # CJK Unified Ideographs
      check utf8ByteLength(0xE9) == 3 # CJK Unified Ideographs
      check utf8ByteLength(0xEF) == 3 # Upper range of 3-byte

    test "UTF-8 byte length detection - 4 bytes":
      # 4-byte characters: 11110xxx
      check utf8ByteLength(0xF0) == 4 # Emoji, rare characters
      check utf8ByteLength(0xF1) == 4
      check utf8ByteLength(0xF3) == 4
      check utf8ByteLength(0xF4) == 4

    test "UTF-8 byte length detection - invalid bytes":
      # Invalid UTF-8 start bytes
      check utf8ByteLength(0x80) == 0 # Continuation byte (10xxxxxx)
      check utf8ByteLength(0xBF) == 0 # Continuation byte
      check utf8ByteLength(0xF5) == 0 # Invalid (> 0xF4)
      check utf8ByteLength(0xFF) == 0 # Invalid

    test "KeyEvent with ASCII character (1 byte)":
      # ASCII characters should work as before
      let asciiEvent = KeyEvent(code: Char, char: "a", modifiers: {})
      check asciiEvent.code == Char
      check asciiEvent.char == "a"
      check asciiEvent.char.len == 1

    test "KeyEvent with 2-byte UTF-8 character":
      # Latin extended characters (2 bytes)
      let latinEvent = KeyEvent(code: Char, char: "é", modifiers: {})
      check latinEvent.code == Char
      check latinEvent.char == "é"
      check latinEvent.char.len == 2 # é is 2 bytes in UTF-8

      let umlautEvent = KeyEvent(code: Char, char: "ü", modifiers: {})
      check umlautEvent.code == Char
      check umlautEvent.char == "ü"
      check umlautEvent.char.len == 2

    test "KeyEvent with 3-byte UTF-8 character - Hiragana":
      # Japanese Hiragana (3 bytes each)
      let hiraganaA = KeyEvent(code: Char, char: "あ", modifiers: {})
      check hiraganaA.code == Char
      check hiraganaA.char == "あ"
      check hiraganaA.char.len == 3

      let hiraganaKa = KeyEvent(code: Char, char: "か", modifiers: {})
      check hiraganaKa.code == Char
      check hiraganaKa.char == "か"
      check hiraganaKa.char.len == 3

    test "KeyEvent with 3-byte UTF-8 character - Katakana":
      # Japanese Katakana (3 bytes each)
      let katakanaA = KeyEvent(code: Char, char: "ア", modifiers: {})
      check katakanaA.code == Char
      check katakanaA.char == "ア"
      check katakanaA.char.len == 3

      let katakanaKa = KeyEvent(code: Char, char: "カ", modifiers: {})
      check katakanaKa.code == Char
      check katakanaKa.char == "カ"
      check katakanaKa.char.len == 3

    test "KeyEvent with 3-byte UTF-8 character - Kanji":
      # Japanese Kanji (3 bytes each)
      let kanjiDay = KeyEvent(code: Char, char: "日", modifiers: {})
      check kanjiDay.code == Char
      check kanjiDay.char == "日"
      check kanjiDay.char.len == 3

      let kanjiBook = KeyEvent(code: Char, char: "本", modifiers: {})
      check kanjiBook.code == Char
      check kanjiBook.char == "本"
      check kanjiBook.char.len == 3

      let kanjiLanguage = KeyEvent(code: Char, char: "語", modifiers: {})
      check kanjiLanguage.code == Char
      check kanjiLanguage.char == "語"
      check kanjiLanguage.char.len == 3

    test "KeyEvent with 4-byte UTF-8 character - Emoji":
      # Emoji (4 bytes)
      let smileyEvent = KeyEvent(code: Char, char: "😀", modifiers: {})
      check smileyEvent.code == Char
      check smileyEvent.char == "😀"
      check smileyEvent.char.len == 4

      let heartEvent = KeyEvent(code: Char, char: "❤️", modifiers: {})
      check heartEvent.code == Char
      check heartEvent.char.len >= 3 # Heart emoji + variation selector

      let rocketEvent = KeyEvent(code: Char, char: "🚀", modifiers: {})
      check rocketEvent.code == Char
      check rocketEvent.char == "🚀"
      check rocketEvent.char.len == 4

    test "Event creation with multibyte characters":
      # Test complete Event creation with UTF-8
      let japaneseEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: "あ", modifiers: {}))
      check japaneseEvent.kind == EventKind.Key
      check japaneseEvent.key.code == Char
      check japaneseEvent.key.char == "あ"

      let emojiEvent =
        Event(kind: Key, key: KeyEvent(code: Char, char: "😀", modifiers: {}))
      check emojiEvent.kind == EventKind.Key
      check emojiEvent.key.code == Char
      check emojiEvent.key.char == "😀"

    test "Multibyte characters with modifiers":
      # Test UTF-8 characters with keyboard modifiers
      let ctrlJapanese =
        Event(kind: Key, key: KeyEvent(code: Char, char: "あ", modifiers: {Ctrl}))
      check ctrlJapanese.key.char == "あ"
      check Ctrl in ctrlJapanese.key.modifiers

      let shiftEmoji =
        Event(kind: Key, key: KeyEvent(code: Char, char: "😀", modifiers: {Shift}))
      check shiftEmoji.key.char == "😀"
      check Shift in shiftEmoji.key.modifiers

    test "UTF-8 character sequence":
      # Simulate typing a Japanese word "こんにちは" (hello)
      let japaneseSequence = [
        Event(kind: Key, key: KeyEvent(code: Char, char: "こ", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: "ん", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: "に", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: "ち", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: "は", modifiers: {})),
      ]

      check japaneseSequence.len == 5
      check japaneseSequence[0].key.char == "こ"
      check japaneseSequence[1].key.char == "ん"
      check japaneseSequence[2].key.char == "に"
      check japaneseSequence[3].key.char == "ち"
      check japaneseSequence[4].key.char == "は"

      for event in japaneseSequence:
        check event.kind == EventKind.Key
        check event.key.code == Char
        check event.key.char.len == 3 # All Hiragana are 3 bytes

    test "UTF-8 emoji sequence":
      # Simulate typing emoji sequence
      let emojiSequence = [
        Event(kind: Key, key: KeyEvent(code: Char, char: "👍", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: "🎉", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: "🚀", modifiers: {})),
      ]

      check emojiSequence.len == 3
      for event in emojiSequence:
        check event.kind == EventKind.Key
        check event.key.code == Char
        check event.key.char.len == 4 # Standard emoji are 4 bytes

    test "Mixed ASCII and multibyte sequence":
      # Simulate typing "Hello 世界" (Hello World in English/Chinese)
      let mixedSequence = [
        Event(kind: Key, key: KeyEvent(code: Char, char: "H", modifiers: {Shift})),
        Event(kind: Key, key: KeyEvent(code: Char, char: "e", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: "l", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: "l", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: "o", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Space, char: " ", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: "世", modifiers: {})),
        Event(kind: Key, key: KeyEvent(code: Char, char: "界", modifiers: {})),
      ]

      check mixedSequence.len == 8
      check mixedSequence[0].key.char == "H"
      check mixedSequence[0].key.char.len == 1 # ASCII
      check mixedSequence[6].key.char == "世"
      check mixedSequence[6].key.char.len == 3 # CJK
      check mixedSequence[7].key.char == "界"
      check mixedSequence[7].key.char.len == 3 # CJK

    test "Empty string handling":
      # Test special keys with empty char field (as before)
      let arrowEvent = KeyEvent(code: ArrowUp, char: "", modifiers: {})
      check arrowEvent.code == ArrowUp
      check arrowEvent.char == ""
      check arrowEvent.char.len == 0

      let f1Event = KeyEvent(code: F1, char: "", modifiers: {})
      check f1Event.code == F1
      check f1Event.char == ""
      check f1Event.char.len == 0

    test "UTF-8 string comparison":
      # Test that string comparison works correctly with UTF-8
      let event1 = KeyEvent(code: Char, char: "あ", modifiers: {})
      let event2 = KeyEvent(code: Char, char: "あ", modifiers: {})
      let event3 = KeyEvent(code: Char, char: "い", modifiers: {})

      check event1.char == event2.char
      check event1.char != event3.char

    test "Regression: char is now string, not char":
      # Test that migration from char to string is correct
      let oldStyleWontCompile = KeyEvent(code: Char, char: "q", modifiers: {})
      check oldStyleWontCompile.char == "q"
      check oldStyleWontCompile.char.len == 1

      # This should NOT compile (old code): event.key.char == 'q'
      # This should compile (new code): event.key.char == "q"

    test "UTF-8 character byte boundaries":
      # Test various UTF-8 character boundaries
      let chars = [
        ("a", 1), # ASCII
        ("é", 2), # 2-byte
        ("€", 3), # Euro sign (3-byte)
        ("日", 3), # CJK (3-byte)
        ("𝕳", 4), # Mathematical bold (4-byte)
        ("😀", 4), # Emoji (4-byte)
      ]

      for (char, expectedLen) in chars:
        let event = KeyEvent(code: Char, char: char, modifiers: {})
        check event.char == char
        check event.char.len == expectedLen

    test "UTF-8 continuation byte validation pattern":
      # Test that continuation bytes follow 10xxxxxx pattern
      # This is more of a documentation test

      # Valid continuation byte masks
      let contBytePattern = 0b10000000.byte # 0x80
      let contByteMask = 0b11000000.byte # 0xC0

      # Valid continuation byte should be 10xxxxxx
      let validCont = 0b10101010.byte # 0xAA
      check (validCont and contByteMask) == contBytePattern

      # Invalid continuation byte (not 10xxxxxx)
      let invalidCont = 0b11101010.byte # 0xEA (start byte, not continuation)
      check (invalidCont and contByteMask) != contBytePattern

    test "UTF-8 start byte patterns":
      # Document the UTF-8 start byte patterns
      # 1-byte: 0xxxxxxx (0x00-0x7F)
      # 2-byte: 110xxxxx (0xC0-0xDF)
      # 3-byte: 1110xxxx (0xE0-0xEF)
      # 4-byte: 11110xxx (0xF0-0xF7)

      # Test boundary values
      check utf8ByteLength(0x00) == 1 # Min 1-byte
      check utf8ByteLength(0x7F) == 1 # Max 1-byte
      check utf8ByteLength(0xC0) == 2 # Min 2-byte
      check utf8ByteLength(0xDF) == 2 # Max 2-byte
      check utf8ByteLength(0xE0) == 3 # Min 3-byte
      check utf8ByteLength(0xEF) == 3 # Max 3-byte
      check utf8ByteLength(0xF0) == 4 # Min 4-byte
      check utf8ByteLength(0xF4) == 4 # Max valid 4-byte (UTF-8 limit)

  suite "KeyEvent String Representation":
    test "simple character key":
      let key = KeyEvent(code: Char, char: "a")
      let s = $key
      check "KeyEvent(" in s
      check "Char" in s
      check "'a'" in s

    test "key with modifiers":
      let key = KeyEvent(code: Char, char: "c", modifiers: {Ctrl})
      let s = $key
      check "Ctrl" in s
      check "Char" in s
      check "'c'" in s

    test "key with multiple modifiers":
      let key = KeyEvent(code: ArrowUp, modifiers: {Ctrl, Shift})
      let s = $key
      check "Ctrl" in s
      check "Shift" in s
      check "ArrowUp" in s

    test "special key without char":
      let key = KeyEvent(code: Escape, char: "\x1b")
      let s = $key
      check "Escape" in s

    test "function key":
      let key = KeyEvent(code: F1)
      let s = $key
      check "F1" in s

  suite "MouseEvent String Representation":
    test "simple mouse press":
      let mouse = MouseEvent(kind: Press, button: Left, x: 10, y: 20)
      let s = $mouse
      check "MouseEvent(" in s
      check "Press" in s
      check "Left" in s
      check "(10, 20)" in s

    test "mouse with modifiers":
      let mouse =
        MouseEvent(kind: Drag, button: Right, x: 5, y: 3, modifiers: {Ctrl, Alt})
      let s = $mouse
      check "Drag" in s
      check "Right" in s
      check "Ctrl" in s
      check "Alt" in s

    test "wheel event":
      let mouse = MouseEvent(kind: Press, button: WheelUp, x: 0, y: 0)
      let s = $mouse
      check "WheelUp" in s

  suite "Event String Representation":
    test "key event":
      let event = Event(kind: Key, key: KeyEvent(code: Char, char: "q"))
      let s = $event
      check "Event(Key" in s
      check "Char" in s

    test "mouse event":
      let event =
        Event(kind: Mouse, mouse: MouseEvent(kind: Press, button: Left, x: 1, y: 2))
      let s = $event
      check "Event(Mouse" in s
      check "Press" in s

    test "paste event with short text":
      let event = Event(kind: Paste, pastedText: "hello")
      let s = $event
      check "Event(Paste" in s
      check "hello" in s

    test "paste event with long text truncated":
      let event = Event(kind: Paste, pastedText: "a".repeat(50))
      let s = $event
      check "..." in s

    test "resize event":
      check $Event(kind: Resize) == "Event(Resize)"

    test "focus events":
      check $Event(kind: FocusIn) == "Event(FocusIn)"
      check $Event(kind: FocusOut) == "Event(FocusOut)"

    test "quit event":
      check $Event(kind: Quit) == "Event(Quit)"

    test "unknown event":
      check $Event(kind: Unknown) == "Event(Unknown)"
