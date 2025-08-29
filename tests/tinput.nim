## Test for Input widget

import std/[unittest, unicode]

import ../celina/core/[geometry, colors, buffer, events]
import ../celina/widgets/input {.all.}

suite "Input Widget Tests":
  suite "Input Creation Tests":
    test "Basic input creation":
      let input = newInput()
      check input.state.text == ""
      check input.state.cursor == 0
      check input.state.selection == (0, 0)
      check input.state.offset == 0
      check input.state.focused == false
      check input.placeholder == ""
      check input.maxLength == 0
      check input.readOnly == false
      check input.password == false
      check input.borderStyle == NoBorder

    test "Input with placeholder":
      let input = newInput(placeholder = "Enter text...")
      check input.placeholder == "Enter text..."
      check input.state.text == ""

    test "Input with custom styles":
      let input = newInput(
        normalStyle = style(White, Black),
        focusedStyle = style(Yellow, Blue),
        placeholderStyle = style(BrightBlack, Reset),
        cursorStyle = style(Black, White),
        selectionStyle = style(White, Blue),
      )
      check input.normalStyle == style(White, Black)
      check input.focusedStyle == style(Yellow, Blue)
      check input.placeholderStyle == style(BrightBlack, Reset)
      check input.cursorStyle == style(Black, White)
      check input.selectionStyle == style(White, Blue)

    test "Input with border":
      let input = newInput(borderStyle = SingleBorder)
      check input.borderStyle == SingleBorder

    test "Input with max length":
      let input = newInput(maxLength = 10)
      check input.maxLength == 10

    test "Read-only input":
      let input = newInput(readOnly = true)
      check input.readOnly == true
      check input.canFocus() == false

    test "Password input":
      let input = passwordInput()
      check input.password == true
      check input.placeholder == "Password"

    test "Search input":
      let input = searchInput()
      check input.placeholder == "Search..."

    test "Read-only input with text":
      let input = readOnlyInput("Read only text")
      check input.readOnly == true
      check input.state.text == "Read only text"

  suite "Text Manipulation Tests":
    test "Set and get text":
      var input = newInput()
      input.setText("Hello World")
      check input.getText() == "Hello World"
      # setText keeps cursor at its current position (0)
      check input.state.cursor == 0

    test "Set text with max length":
      var input = newInput(maxLength = 5)
      input.setText("Hello World")
      check input.getText() == "Hello"
      # setText keeps cursor at its current position (0)
      check input.state.cursor == 0

    test "Insert text at cursor":
      var input = newInput()
      input.setText("Hello")
      input.setCursor(5)
      input.insertText(" World")
      check input.getText() == "Hello World"
      check input.state.cursor == 11

    test "Insert text at specific position":
      var input = newInput()
      input.setText("Hello World")
      input.insertText(" Beautiful", 5)
      check input.getText() == "Hello Beautiful World"

    test "Insert text with max length":
      var input = newInput(maxLength = 10)
      input.setText("Hello")
      input.setCursor(5) # Move cursor to end of "Hello"
      input.insertText(" World!")
      check input.getText() == "Hello Worl"
      check input.state.cursor == 10

    test "Delete text":
      var input = newInput()
      input.setText("Hello World")
      input.deleteText(5, 6)
      check input.getText() == "Hello"

    test "Delete text beyond bounds":
      var input = newInput()
      input.setText("Hello")
      input.deleteText(3, 10)
      check input.getText() == "Hel"

    test "Read-only prevents modification":
      var input = newInput(readOnly = true)
      input.setText("Initial")
      input.insertText(" Text")
      check input.getText() == "Initial"
      input.deleteText(0, 3)
      check input.getText() == "Initial"

  suite "Cursor Management Tests":
    test "Set and get cursor":
      var input = newInput()
      input.setText("Hello")
      input.setCursor(3)
      check input.getCursor() == 3

    test "Cursor clamping":
      var input = newInput()
      input.setText("Hello")
      input.setCursor(10)
      check input.getCursor() == 5
      input.setCursor(-5)
      check input.getCursor() == 0

    test "Cursor moves with text insertion":
      var input = newInput()
      input.setText("Hello")
      input.setCursor(2)
      input.insertText("XX")
      check input.getCursor() == 4
      check input.getText() == "HeXXllo"

  suite "Selection Tests":
    test "Basic selection":
      var input = newInput()
      input.setText("Hello World")
      input.state.selection = (0, 5)
      check input.hasSelection() == true
      check input.getSelection() == (0, 5)

    test "Inverted selection normalization":
      var input = newInput()
      input.setText("Hello World")
      input.state.selection = (5, 0)
      check input.getSelection() == (0, 5)

    test "Clear selection":
      var input = newInput()
      input.setText("Hello World")
      input.state.selection = (0, 5)
      input.clearSelection()
      check input.hasSelection() == false
      check input.state.selection == (0, 0)

    test "Select all":
      var input = newInput()
      input.setText("Hello World")
      input.selectAll()
      check input.hasSelection() == true
      check input.getSelection() == (0, 11)
      check input.state.cursor == 11

    test "Delete selection":
      var input = newInput()
      input.setText("Hello World")
      input.state.selection = (0, 6)
      input.deleteSelection()
      check input.getText() == "World"
      check input.state.cursor == 0
      check input.hasSelection() == false

  suite "Focus Management Tests":
    test "Set and get focus":
      var input = newInput()
      check input.hasFocus() == false
      input.setFocus(true)
      check input.hasFocus() == true
      input.setFocus(false)
      check input.hasFocus() == false

    test "Focus callbacks":
      var focusCalled = false
      var blurCalled = false
      var input = newInput(
        onFocus = proc() =
          focusCalled = true,
        onBlur = proc() =
          blurCalled = true,
      )

      input.setFocus(true)
      check focusCalled == true
      check blurCalled == false

      focusCalled = false
      input.setFocus(false)
      check focusCalled == false
      check blurCalled == true

  suite "Event Handling Tests":
    test "Character input":
      var input = newInput()
      input.setFocus(true)
      let event = KeyEvent(code: Char, char: 'A', modifiers: {})
      check input.handleKeyEvent(event) == true
      check input.getText() == "A"
      check input.state.cursor == 1

    test "Character input with selection":
      var input = newInput()
      input.setFocus(true)
      input.setText("Hello World")
      input.state.selection = (0, 6)
      let event = KeyEvent(code: Char, char: 'X', modifiers: {})
      check input.handleKeyEvent(event) == true
      check input.getText() == "XWorld"
      check input.state.cursor == 1

    test "Backspace key":
      var input = newInput()
      input.setFocus(true)
      input.setText("Hello")
      input.setCursor(5)
      let event = KeyEvent(code: Backspace, modifiers: {})
      check input.handleKeyEvent(event) == true
      check input.getText() == "Hell"
      check input.state.cursor == 4

    test "Backspace with selection":
      var input = newInput()
      input.setFocus(true)
      input.setText("Hello World")
      input.state.selection = (0, 6)
      let event = KeyEvent(code: Backspace, modifiers: {})
      check input.handleKeyEvent(event) == true
      check input.getText() == "World"
      check input.state.cursor == 0

    test "Delete key":
      var input = newInput()
      input.setFocus(true)
      input.setText("Hello")
      input.setCursor(2)
      let event = KeyEvent(code: Delete, modifiers: {})
      check input.handleKeyEvent(event) == true
      check input.getText() == "Helo"
      check input.state.cursor == 2

    test "Arrow navigation":
      var input = newInput()
      input.setFocus(true)
      input.setText("Hello")
      input.setCursor(3)

      let leftEvent = KeyEvent(code: ArrowLeft, modifiers: {})
      check input.handleKeyEvent(leftEvent) == true
      check input.state.cursor == 2

      let rightEvent = KeyEvent(code: ArrowRight, modifiers: {})
      check input.handleKeyEvent(rightEvent) == true
      check input.state.cursor == 3

    test "Home and End keys":
      var input = newInput()
      input.setFocus(true)
      input.setText("Hello World")
      input.setCursor(5)

      let homeEvent = KeyEvent(code: Home, modifiers: {})
      check input.handleKeyEvent(homeEvent) == true
      check input.state.cursor == 0

      let endEvent = KeyEvent(code: End, modifiers: {})
      check input.handleKeyEvent(endEvent) == true
      check input.state.cursor == 11

    test "Selection with shift+arrow":
      var input = newInput()
      input.setFocus(true)
      input.setText("Hello")
      input.setCursor(2)

      let rightEvent = KeyEvent(code: ArrowRight, modifiers: {Shift})
      check input.handleKeyEvent(rightEvent) == true
      check input.state.cursor == 3
      check input.state.selection == (2, 3)

      check input.handleKeyEvent(rightEvent) == true
      check input.state.cursor == 4
      check input.state.selection == (2, 4)

    test "Ctrl+A select all":
      var input = newInput()
      input.setFocus(true)
      input.setText("Hello World")
      let event = KeyEvent(code: Char, char: 'a', modifiers: {Ctrl})
      check input.handleKeyEvent(event) == true
      check input.getSelection() == (0, 11)
      check input.state.cursor == 11

    test "Enter key callback":
      var enterText = ""
      var input = newInput(
        onEnter = proc(text: string) =
          enterText = text
      )
      input.setFocus(true)
      input.setText("Hello")
      let event = KeyEvent(code: Enter, modifiers: {})
      check input.handleKeyEvent(event) == true
      check enterText == "Hello"

    test "Custom key handler":
      var customHandled = false
      var input = newInput(
        onKeyPress = proc(key: KeyEvent): bool =
          if key.code == Escape:
            customHandled = true
            return true
          return false
      )
      input.setFocus(true)

      let escEvent = KeyEvent(code: Escape, modifiers: {})
      check input.handleKeyEvent(escEvent) == true
      check customHandled == true

      customHandled = false
      let charEvent = KeyEvent(code: Char, char: 'A', modifiers: {})
      check input.handleKeyEvent(charEvent) == true
      check customHandled == false
      check input.getText() == "A"

    test "Unfocused input ignores events":
      var input = newInput()
      input.setText("Hello")
      let event = KeyEvent(code: Char, char: 'A', modifiers: {})
      check input.handleKeyEvent(event) == false
      check input.getText() == "Hello"

    test "Read-only input ignores modification":
      var input = newInput(readOnly = true)
      input.setFocus(true)
      input.setText("Hello")

      let charEvent = KeyEvent(code: Char, char: 'A', modifiers: {})
      check input.handleKeyEvent(charEvent) == false
      check input.getText() == "Hello"

      let backspaceEvent = KeyEvent(code: Backspace, modifiers: {})
      check input.handleKeyEvent(backspaceEvent) == false
      check input.getText() == "Hello"

  suite "Password Mode Tests":
    test "Password display text":
      var input = newInput(password = true)
      input.setText("secret")
      check input.getDisplayText() == "******"
      check input.getText() == "secret"

    test "Empty password display":
      var input = newInput(password = true)
      check input.getDisplayText() == ""

  suite "Visible Range Calculation Tests":
    test "Basic visible range":
      var input = newInput()
      input.setText("Hello World")
      let (offset, visStart, visEnd, cursorX) = input.calculateVisibleRange(5)
      check offset == 0
      check visStart == 0
      check visEnd == 5
      check cursorX == 0

    test "Scrolled visible range":
      var input = newInput()
      input.setText("This is a very long text that won't fit")
      input.setCursor(20)
      let (offset, visStart, visEnd, cursorX) = input.calculateVisibleRange(10)
      check offset >= 11
      check visEnd - visStart <= 10
      check cursorX >= 0
      check cursorX < 10

    test "Empty text visible range":
      var input = newInput()
      let (offset, visStart, visEnd, cursorX) = input.calculateVisibleRange(10)
      check offset == 0
      check visStart == 0
      check visEnd == 0
      check cursorX == 0

  suite "Rendering Tests":
    test "Basic rendering":
      var input = newInput()
      input.setText("Hello")
      var buf = newBuffer(10, 1)
      input.render(rect(0, 0, 10, 1), buf)
      # Check that something was rendered
      check buf[0, 0] != Cell()

    test "Rendering with border":
      var input = newInput(borderStyle = SingleBorder)
      input.setText("Hi")
      var buf = newBuffer(10, 3)
      input.render(rect(0, 0, 10, 3), buf)
      # Check that corners are rendered
      check buf[0, 0].symbol == "┌"
      check buf[9, 0].symbol == "┐"
      check buf[0, 2].symbol == "└"
      check buf[9, 2].symbol == "┘"

    test "Placeholder rendering":
      var input = newInput(placeholder = "Enter text...")
      var buf = newBuffer(15, 1)
      input.render(rect(0, 0, 15, 1), buf)
      # The placeholder should be visible when no text
      # Check first few characters of placeholder
      check buf[0, 0].symbol == "E"
      check buf[1, 0].symbol == "n"
      check buf[2, 0].symbol == "t"

    test "Password rendering":
      var input = newInput(password = true)
      input.setText("secret")
      var buf = newBuffer(10, 1)
      input.render(rect(0, 0, 10, 1), buf)
      # Should render asterisks
      check buf[0, 0].symbol == "*"
      check buf[1, 0].symbol == "*"
      check buf[2, 0].symbol == "*"

    test "Get minimum size":
      var input = newInput()
      check input.getMinSize() == size(1, 1)

      var borderedInput = newInput(borderStyle = SingleBorder)
      check borderedInput.getMinSize() == size(3, 3)

    test "Get preferred size":
      var input = newInput()
      check input.getPreferredSize(size(20, 10)) == size(20, 1)

      var borderedInput = newInput(borderStyle = SingleBorder)
      check borderedInput.getPreferredSize(size(20, 10)) == size(20, 3)

  suite "Cursor Position Tests":
    test "Get cursor position when focused":
      var input = newInput()
      input.setFocus(true)
      input.setText("Hello")
      input.setCursor(3)
      let (x, y, visible) = input.getCursorPosition(rect(5, 2, 10, 1))
      check visible == true
      check x == 8 # 5 (area.x) + 3 (cursor)
      check y == 2

    test "Cursor hidden when unfocused":
      var input = newInput()
      input.setText("Hello")
      let (x, y, visible) = input.getCursorPosition(rect(5, 2, 10, 1))
      check visible == false
      check x == -1
      check y == -1

    test "Cursor position with border":
      var input = newInput(borderStyle = SingleBorder)
      input.setFocus(true)
      input.setText("Hello")
      input.setCursor(2)
      let (x, y, visible) = input.getCursorPosition(rect(5, 2, 10, 3))
      check visible == true
      check x == 8 # 5 (area.x) + 1 (border) + 2 (cursor)
      check y == 3 # 2 (area.y) + 1 (border)

  suite "Builder Pattern Tests":
    test "With text builder":
      let input = newInput().withText("Hello")
      check input.getText() == "Hello"

    test "With placeholder builder":
      let input = newInput().withPlaceholder("Enter name...")
      check input.placeholder == "Enter name..."

    test "With max length builder":
      let input = newInput().withMaxLength(20)
      check input.maxLength == 20

    test "With styles builder":
      let input =
        newInput().withStyles(normal = style(Red, Black), focused = style(Yellow, Blue))
      check input.normalStyle == style(Red, Black)
      check input.focusedStyle == style(Yellow, Blue)

    test "With event handlers builder":
      var textChanged = false
      var enterPressed = false
      let input = newInput().withEventHandlers(
          onTextChanged = proc(text: string) =
            textChanged = true,
          onEnter = proc(text: string) =
            enterPressed = true,
        )

      if input.onTextChanged != nil:
        input.onTextChanged("test")
        check textChanged == true

      if input.onEnter != nil:
        input.onEnter("test")
        check enterPressed == true

  suite "Text Changed Callback Tests":
    test "Text changed on setText":
      var changedText = ""
      var input = newInput(
        onTextChanged = proc(text: string) =
          changedText = text
      )
      input.setText("Hello")
      check changedText == "Hello"

    test "Text changed on insert":
      var changedText = ""
      var input = newInput(
        onTextChanged = proc(text: string) =
          changedText = text
      )
      input.insertText("World")
      check changedText == "World"

    test "Text changed on delete":
      var changedText = ""
      var input = newInput(
        onTextChanged = proc(text: string) =
          changedText = text
      )
      input.setText("Hello")
      input.deleteText(0, 2)
      check changedText == "llo"

  suite "Unicode Support Tests":
    test "Unicode text handling":
      var input = newInput()
      input.setText("こんにちは")
      check input.getText() == "こんにちは"
      check input.state.text.runeLen == 5

    test "Unicode cursor movement":
      var input = newInput()
      input.setText("👋🌍🎉")
      input.setCursor(2)
      check input.getCursor() == 2
      input.insertText("🚀")
      check input.getText() == "👋🌍🚀🎉"
      check input.getCursor() == 3

    test "Unicode deletion":
      var input = newInput()
      input.setText("Hello 世界")
      input.deleteText(6, 1)
      check input.getText() == "Hello 界"

  suite "Border Style Tests":
    test "Border character retrieval":
      let single = getBorderChars(SingleBorder)
      check single.topLeft == "┌"
      check single.horizontal == "─"
      check single.vertical == "│"

      let double = getBorderChars(DoubleBorder)
      check double.topLeft == "╔"
      check double.horizontal == "═"
      check double.vertical == "║"

      let rounded = getBorderChars(RoundedBorder)
      check rounded.topLeft == "╭"
      check rounded.horizontal == "─"
      check rounded.vertical == "│"

      let none = getBorderChars(NoBorder)
      check none.topLeft == ""
      check none.horizontal == ""
      check none.vertical == ""
