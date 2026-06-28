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
      check input.keyboardFocused == false
      check input.placeholder == ""
      check input.maxLength == 0
      check input.readOnly == false
      check input.password == false
      check input.borderStyle == bkNone

    test "Input with placeholder":
      let input = newInput(placeholder = "Enter text...")
      check input.placeholder == "Enter text..."
      check input.state.text == ""

    test "Input with custom styles":
      let input = newInput(
        style = InputStyle(
          normal: style(White, Black),
          focused: style(Yellow, Blue),
          placeholder: style(BrightBlack, Reset),
          cursor: style(Black, White),
          selection: style(White, Blue),
          borderNormal: style(BrightBlack, Reset),
          borderFocused: style(Blue, Reset),
        )
      )
      check input.normalStyle == style(White, Black)
      check input.focusedStyle == style(Yellow, Blue)
      check input.placeholderStyle == style(BrightBlack, Reset)
      check input.cursorStyle == style(Black, White)
      check input.selectionStyle == style(White, Blue)

    test "Input with border":
      let input = newInput(border = bkSingle)
      check input.borderStyle == bkSingle

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

    test "isFocused/keyboardFocused stay in sync":
      var input = newInput()
      check not input.isFocused()
      check not input.keyboardFocused

      input.setFocus(true)
      check input.isFocused()
      check input.keyboardFocused

      input.setFocus(false)
      check not input.isFocused()
      check not input.keyboardFocused

    test "handleKeyEvent ignores keys when not focused":
      var input = newInput()
      # Not focused: typed characters are not consumed and the text is unchanged.
      let event = KeyEvent(code: Char, char: "a", modifiers: {})
      check input.handleKeyEvent(event) == erContinue
      check input.getText() == ""

      # Focused: the same key is consumed and inserts the character.
      input.setFocus(true)
      check input.handleKeyEvent(event) == erConsume
      check input.getText() == "a"

    test "Focus callbacks":
      var focusCalled = false
      var blurCalled = false
      var input = newInput(
        callbacks = InputCallbacks(
          onFocus: proc() =
            focusCalled = true,
          onBlur: proc() =
            blurCalled = true,
        )
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
      let event = KeyEvent(code: Char, char: "A", modifiers: {})
      check input.handleKeyEvent(event) == erConsume
      check input.getText() == "A"
      check input.state.cursor == 1

    test "Character input with selection":
      var input = newInput()
      input.setFocus(true)
      input.setText("Hello World")
      input.state.selection = (0, 6)
      let event = KeyEvent(code: Char, char: "X", modifiers: {})
      check input.handleKeyEvent(event) == erConsume
      check input.getText() == "XWorld"
      check input.state.cursor == 1

    test "Backspace key":
      var input = newInput()
      input.setFocus(true)
      input.setText("Hello")
      input.setCursor(5)
      let event = KeyEvent(code: Backspace, modifiers: {})
      check input.handleKeyEvent(event) == erConsume
      check input.getText() == "Hell"
      check input.state.cursor == 4

    test "Backspace with selection":
      var input = newInput()
      input.setFocus(true)
      input.setText("Hello World")
      input.state.selection = (0, 6)
      let event = KeyEvent(code: Backspace, modifiers: {})
      check input.handleKeyEvent(event) == erConsume
      check input.getText() == "World"
      check input.state.cursor == 0

    test "Delete key":
      var input = newInput()
      input.setFocus(true)
      input.setText("Hello")
      input.setCursor(2)
      let event = KeyEvent(code: Delete, modifiers: {})
      check input.handleKeyEvent(event) == erConsume
      check input.getText() == "Helo"
      check input.state.cursor == 2

    test "Arrow navigation":
      var input = newInput()
      input.setFocus(true)
      input.setText("Hello")
      input.setCursor(3)

      let leftEvent = KeyEvent(code: ArrowLeft, modifiers: {})
      check input.handleKeyEvent(leftEvent) == erConsume
      check input.state.cursor == 2

      let rightEvent = KeyEvent(code: ArrowRight, modifiers: {})
      check input.handleKeyEvent(rightEvent) == erConsume
      check input.state.cursor == 3

    test "Home and End keys":
      var input = newInput()
      input.setFocus(true)
      input.setText("Hello World")
      input.setCursor(5)

      let homeEvent = KeyEvent(code: Home, modifiers: {})
      check input.handleKeyEvent(homeEvent) == erConsume
      check input.state.cursor == 0

      let endEvent = KeyEvent(code: End, modifiers: {})
      check input.handleKeyEvent(endEvent) == erConsume
      check input.state.cursor == 11

    test "Selection with shift+arrow":
      var input = newInput()
      input.setFocus(true)
      input.setText("Hello")
      input.setCursor(2)

      let rightEvent = KeyEvent(code: ArrowRight, modifiers: {Shift})
      check input.handleKeyEvent(rightEvent) == erConsume
      check input.state.cursor == 3
      check input.state.selection == (2, 3)

      check input.handleKeyEvent(rightEvent) == erConsume
      check input.state.cursor == 4
      check input.state.selection == (2, 4)

    test "Ctrl+A select all":
      var input = newInput()
      input.setFocus(true)
      input.setText("Hello World")
      let event = KeyEvent(code: Char, char: "a", modifiers: {Ctrl})
      check input.handleKeyEvent(event) == erConsume
      check input.getSelection() == (0, 11)
      check input.state.cursor == 11

    test "Enter key callback":
      var enterText = ""
      var input = newInput(
        callbacks = InputCallbacks(
          onEnter: proc(text: string) =
            enterText = text
        )
      )
      input.setFocus(true)
      input.setText("Hello")
      let event = KeyEvent(code: Enter, modifiers: {})
      check input.handleKeyEvent(event) == erConsume
      check enterText == "Hello"

    test "Custom key handler":
      var customHandled = false
      var input = newInput(
        callbacks = InputCallbacks(
          onKeyPress: proc(key: KeyEvent): EventResult =
            if key.code == Escape:
              customHandled = true
              return erConsume
            return erContinue
        )
      )
      input.setFocus(true)

      let escEvent = KeyEvent(code: Escape, modifiers: {})
      check input.handleKeyEvent(escEvent) == erConsume
      check customHandled == true

      customHandled = false
      let charEvent = KeyEvent(code: Char, char: "A", modifiers: {})
      check input.handleKeyEvent(charEvent) == erConsume
      check customHandled == false
      check input.getText() == "A"

    test "Unfocused input ignores events":
      var input = newInput()
      input.setText("Hello")
      let event = KeyEvent(code: Char, char: "A", modifiers: {})
      check input.handleKeyEvent(event) == erContinue
      check input.getText() == "Hello"

    test "Read-only input ignores modification":
      var input = newInput(readOnly = true)
      input.setFocus(true)
      input.setText("Hello")

      let charEvent = KeyEvent(code: Char, char: "A", modifiers: {})
      check input.handleKeyEvent(charEvent) == erContinue
      check input.getText() == "Hello"

      let backspaceEvent = KeyEvent(code: Backspace, modifiers: {})
      check input.handleKeyEvent(backspaceEvent) == erContinue
      check input.getText() == "Hello"

  suite "Password Mode Tests":
    test "Password display text":
      # Verify the rendered buffer cells (the renderer masks inline); there is no
      # intermediate display string to inspect.
      var input = newInput(password = true)
      input.setText("secret")
      var buf = newBuffer(10, 1)
      input.render(rect(0, 0, 10, 1), buf)
      for x in 0 ..< 6:
        check buf[x, 0].symbol == "*"
      check buf[6, 0].symbol == " " # nothing past the six masked cells
      check input.getText() == "secret"

    test "Empty password display":
      # Empty input must not render any mask glyph anywhere in the row (the
      # default buffer cell is already a space, so asserting one cell is " " would
      # pass even if masking ran — scan the whole width instead).
      var input = newInput(password = true)
      var buf = newBuffer(10, 1)
      input.render(rect(0, 0, 10, 1), buf)
      for x in 0 ..< 10:
        check buf[x, 0].symbol != "*"
        check buf[x, 0].symbol != "＊"

    test "Password display preserves width for wide runes":
      # Mask must match each cluster's display width so the masked text occupies
      # the same number of columns as the original. Wide runes (CJK) become
      # fullwidth asterisks (width 2 + shadow cell); narrow runes become regular
      # asterisks, keeping the renderer aligned with calculateVisibleRange.
      var input = newInput(password = true)
      input.setText("あa日")
      var buf = newBuffer(10, 1)
      input.render(rect(0, 0, 10, 1), buf)
      check buf[0, 0].symbol == "＊"
      check buf[0, 0].width == 2
      check buf[1, 0].symbol == "" # shadow of the leading fullwidth mask
      check buf[2, 0].symbol == "*"
      check buf[2, 0].width == 1
      check buf[3, 0].symbol == "＊"
      check buf[3, 0].width == 2
      check buf[4, 0].symbol == "" # shadow of the trailing fullwidth mask

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
      var input = newInput(border = bkSingle)
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

    test "Wide-character placeholder truncates by display width":
      # "日本語入力" = 10 cols. Area width 5 fits only "日本" (4 cols).
      var input = newInput(placeholder = "日本語入力")
      var buf = newBuffer(5, 1)
      input.render(rect(0, 0, 5, 1), buf)
      check buf[0, 0].symbol == "日"
      check buf[2, 0].symbol == "本"
      # 5th column has no wide char that fits; remains the cleared space
      check buf[4, 0].symbol == " "

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

      var borderedInput = newInput(border = bkSingle)
      check borderedInput.getMinSize() == size(3, 3)

    test "Get preferred size":
      var input = newInput()
      check input.getPreferredSize(size(20, 10)) == size(20, 1)

      var borderedInput = newInput(border = bkSingle)
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
      var input = newInput(border = bkSingle)
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

    test "Builders preserve border fields":
      let styled = InputStyle(
        normal: style(White, Reset),
        focused: style(White, Blue),
        placeholder: style(BrightBlack, Reset),
        cursor: style(Black, White),
        selection: style(White, BrightBlue),
        borderNormal: style(Red, Reset),
        borderFocused: style(Green, Reset),
      )
      let base = newInput("ph", style = styled, border = bkSingle)
      check base.borderStyle == bkSingle

      let derived = [
        base.withText("hi"),
        base.withPlaceholder("new"),
        base.withMaxLength(5),
        base.withStyles(normal = style(Cyan, Black)),
        base.withEventHandlers(
          onEnter = proc(text: string) =
            discard
        ),
      ]
      for input in derived:
        check input.borderStyle == bkSingle
        check input.borderNormalStyle == style(Red, Reset)
        check input.borderFocusedStyle == style(Green, Reset)

  suite "Text Changed Callback Tests":
    test "Text changed on setText":
      var changedText = ""
      var input = newInput(
        callbacks = InputCallbacks(
          onTextChanged: proc(text: string) =
            changedText = text
        )
      )
      input.setText("Hello")
      check changedText == "Hello"

    test "Text changed on insert":
      var changedText = ""
      var input = newInput(
        callbacks = InputCallbacks(
          onTextChanged: proc(text: string) =
            changedText = text
        )
      )
      input.insertText("World")
      check changedText == "World"

    test "Text changed on delete":
      var changedText = ""
      var input = newInput(
        callbacks = InputCallbacks(
          onTextChanged: proc(text: string) =
            changedText = text
        )
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

  suite "Grapheme Cluster (CJK / emoji) Tests":
    # The editing model stores positions as rune indices, but layout and
    # navigation are grapheme-cluster aware so combining sequences, VS16/ZWJ
    # emoji, and CJK characters are rendered, measured, moved over, and deleted
    # as one unit instead of one code point at a time.

    test "Wide CJK renders with shadow cell":
      var input = newInput()
      input.setText("AB日C")
      var buf = newBuffer(10, 1)
      input.render(rect(0, 0, 10, 1), buf)
      check buf[0, 0].symbol == "A"
      check buf[1, 0].symbol == "B"
      check buf[2, 0].symbol == "日" # wide lead
      check buf[3, 0].symbol == "" # shadow cell for the wide char
      check buf[4, 0].symbol == "C"

    test "Combining mark folds into the base cell":
      # "e" + U+0301 (combining acute) is one cluster of width 1. A per-rune
      # renderer dropped the mark; cluster rendering keeps both runes in one cell.
      var input = newInput()
      input.setText(("e" & $Rune(0x0301)) & "x")
      var buf = newBuffer(10, 1)
      input.render(rect(0, 0, 10, 1), buf)
      check buf[0, 0].symbol.toRunes.len == 2 # base + combining mark
      check buf[0, 0].symbol == ("e" & $Rune(0x0301))
      check buf[1, 0].symbol == "x" # mark did not consume a column

    test "VS16 emoji renders as a width-2 cluster":
      # U+26A0 U+FE0F renders in two columns; a per-code-point renderer kept it
      # at width 1 and dropped the VS16, leaving a ghost column.
      var input = newInput()
      input.setText(($Rune(0x26A0) & $Rune(0xFE0F)) & "X")
      var buf = newBuffer(10, 1)
      input.render(rect(0, 0, 10, 1), buf)
      check buf[0, 0].symbol == ($Rune(0x26A0) & $Rune(0xFE0F))
      check buf[0, 0].width == 2
      check buf[1, 0].symbol == "" # shadow cell
      check buf[2, 0].symbol == "X" # next char clears the column past the cluster

    test "Visible range measures cursor by cluster width":
      var input = newInput()
      input.setText(($Rune(0x26A0) & $Rune(0xFE0F)) & "AB")
      # Cluster boundaries (rune indices): 0 (warn, 2 runes), 2 (A), 3 (B).
      input.setCursor(2) # just past the width-2 VS16 cluster
      let (_, _, _, cursorX) = input.calculateVisibleRange(10)
      check cursorX == 2

    test "Visible range never splits a wide cluster at the edge":
      var input = newInput()
      input.setText("日本語入力") # 5 CJK, 10 cols
      input.setCursor(0)
      # Width 5 fits two wide chars (4 cols); the third would split, so it is
      # excluded rather than half-drawn.
      let (offset, visStart, visEnd, _) = input.calculateVisibleRange(5)
      check offset == 0
      check visStart == 0
      check visEnd == 2

    test "Arrow keys move by whole cluster":
      var input = newInput()
      input.setFocus(true)
      input.setText(("e" & $Rune(0x0301)) & "x") # clusters at rune 0 and 2
      input.setCursor(3)
      check input.handleKeyEvent(KeyEvent(code: ArrowLeft, modifiers: {})) == erConsume
      check input.getCursor() == 2
      check input.handleKeyEvent(KeyEvent(code: ArrowLeft, modifiers: {})) == erConsume
      check input.getCursor() == 0 # jumped over the combining cluster, not the mark
      check input.handleKeyEvent(KeyEvent(code: ArrowRight, modifiers: {})) == erConsume
      check input.getCursor() == 2

    test "Backspace deletes a whole cluster":
      var input = newInput()
      input.setFocus(true)
      input.setText(("e" & $Rune(0x0301)) & "x")
      input.setCursor(2) # after the combining cluster
      check input.handleKeyEvent(KeyEvent(code: Backspace, modifiers: {})) == erConsume
      check input.getText() == "x" # base + mark removed together
      check input.getCursor() == 0

    test "Delete removes a whole cluster":
      var input = newInput()
      input.setFocus(true)
      input.setText(("e" & $Rune(0x0301)) & "x")
      input.setCursor(0)
      check input.handleKeyEvent(KeyEvent(code: Delete, modifiers: {})) == erConsume
      check input.getText() == "x"
      check input.getCursor() == 0

    test "setCursor snaps to a cluster boundary":
      # A rune index that lands inside a multi-rune cluster is snapped back to the
      # cluster's start so the cursor never rests between a base and its mark.
      var input = newInput()
      input.setText(("e" & $Rune(0x0301)) & "x") # clusters at rune 0 and 2
      input.setCursor(1) # inside the combining cluster
      check input.getCursor() == 0 # snapped to the cluster start
      input.setCursor(2) # already a boundary
      check input.getCursor() == 2
      input.setCursor(3) # end of text is a boundary
      check input.getCursor() == 3

    test "Insert before an isolated combining mark snaps cursor forward":
      # Regression: inserting a base in front of a lone combining mark merges them
      # into one cluster. A backward cursor snap left the cursor before the typed
      # base (at rune 0), so Backspace could not remove it. The cursor must land
      # after the inserted text so the cluster is deletable.
      var input = newInput()
      input.setFocus(true)
      input.setText($Rune(0x0301)) # lone combining acute accent
      input.setCursor(0)
      input.insertText("X") # text becomes "X" + U+0301, one cluster
      check input.getText() == "X" & $Rune(0x0301)
      check input.getCursor() == 2 # past the merged cluster, not 0
      check input.handleKeyEvent(KeyEvent(code: Backspace, modifiers: {})) == erConsume
      check input.getText() == "" # the whole cluster is removed

    test "Backspace off a boundary still deletes the whole cluster":
      # Regression: setCursor used to allow a mid-cluster cursor, after which
      # Backspace deleted only the base rune and orphaned the combining mark.
      var input = newInput()
      input.setFocus(true)
      input.setText(("e" & $Rune(0x0301)) & "x")
      input.setCursor(1) # snapped to 0
      check input.handleKeyEvent(KeyEvent(code: Backspace, modifiers: {})) == erConsume
      check input.getText() == ("e" & $Rune(0x0301)) & "x" # nothing before cluster 0
      check input.getCursor() == 0

    test "Delete off a boundary removes the whole VS16 cluster":
      var input = newInput()
      input.setFocus(true)
      input.setText(($Rune(0x26A0) & $Rune(0xFE0F)) & "x") # warn(2 runes) + x
      input.setCursor(1) # inside the emoji cluster -> snapped to 0
      check input.getCursor() == 0
      check input.handleKeyEvent(KeyEvent(code: Delete, modifiers: {})) == erConsume
      check input.getText() == "x" # base + VS16 removed together, no orphan selector

    test "Password masks per cluster (combining mark)":
      # The mask keeps the original cluster count and per-cluster width, so layout
      # (over the original text) and the renderer (which masks inline) stay aligned.
      var input = newInput(password = true)
      input.setText(("e" & $Rune(0x0301)) & "x") # one width-1 cluster + "x"
      var buf = newBuffer(10, 1)
      input.render(rect(0, 0, 10, 1), buf)
      check buf[0, 0].symbol == "*" # combining cluster -> one mask, not one per rune
      check buf[1, 0].symbol == "*" # the trailing "x"
      check buf[2, 0].symbol == " " # nothing past the two clusters

    test "Password VS16 emoji renders as one width-2 masked cell":
      var input = newInput(password = true)
      input.setText($Rune(0x26A0) & $Rune(0xFE0F)) # one width-2 cluster
      var buf = newBuffer(10, 1)
      input.render(rect(0, 0, 10, 1), buf)
      check buf[0, 0].symbol == "＊"
      check buf[0, 0].width == 2
      check buf[1, 0].symbol == "" # shadow cell, no ghost column

  suite "Border Style Tests":
    test "Border character retrieval":
      let single = getBorderChars(bkSingle)
      check single.topLeft == "┌"
      check single.horizontal == "─"
      check single.vertical == "│"

      let double = getBorderChars(bkDouble)
      check double.topLeft == "╔"
      check double.horizontal == "═"
      check double.vertical == "║"

      let rounded = getBorderChars(bkRounded)
      check rounded.topLeft == "╭"
      check rounded.horizontal == "─"
      check rounded.vertical == "│"

      let none = getBorderChars(bkNone)
      check none.topLeft == ""
      check none.horizontal == ""
      check none.vertical == ""
