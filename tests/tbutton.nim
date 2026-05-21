## Test for Button widget

import std/unittest

import ../celina/core/[geometry, buffer, colors, events]
import ../celina/widgets/button

suite "Button Widget Tests":
  suite "Button Creation Tests":
    test "Basic button creation":
      let btn = newButton("Test Button")
      check btn.text == "Test Button"
      check btn.state == Normal
      check btn.enabled == true
      check btn.padding == 1
      check btn.minWidth == 0

    test "Button with custom parameters":
      let btn = newButton("Custom", minWidth = 10, padding = 2)
      check btn.text == "Custom"
      check btn.minWidth == 10
      check btn.padding == 2

    test "Convenience constructors":
      let primaryBtn = primaryButton("Primary")
      let secondaryBtn = secondaryButton("Secondary")
      let dangerBtn = dangerButton("Danger")
      let successBtn = successButton("Success")

      check primaryBtn.text == "Primary"
      check secondaryBtn.text == "Secondary"
      check dangerBtn.text == "Danger"
      check successBtn.text == "Success"

  suite "Button State Management Tests":
    test "Button state changes":
      var btn = newButton("Test")
      check btn.state == Normal

      btn.setState(Hovered)
      check btn.state == Hovered

      btn.setState(Pressed)
      check btn.state == Pressed

      btn.setState(Focused)
      check btn.state == Focused

    test "Disabled button state":
      var btn = newButton("Test")
      btn.setEnabled(false)
      check not btn.isEnabled()
      check btn.state == Disabled

      # Disabled buttons shouldn't change state
      btn.setState(Hovered)
      check btn.state == Disabled

    test "Button enable/disable":
      var btn = newButton("Test")
      check btn.isEnabled()

      btn.setEnabled(false)
      check not btn.isEnabled()

      btn.setEnabled(true)
      check btn.isEnabled()
      check btn.state == Normal

  suite "Button Event Handling Tests":
    test "Button click handling":
      var clickCount = 0
      var btn = newButton("Test")
      btn.onClick = proc() =
        clickCount.inc()

      btn.handleClick()
      check clickCount == 1

      btn.handleClick()
      check clickCount == 2

    test "Disabled button click handling":
      var clickCount = 0
      var btn = newButton("Test")
      btn.onClick = proc() =
        clickCount.inc()
      btn.setEnabled(false)

      btn.handleClick()
      check clickCount == 0 # Should not increment

    test "Keyboard event handling - Enter key":
      var clickCount = 0
      var btn = newButton("Test")
      btn.onClick = proc() =
        clickCount.inc()
      btn.setState(Focused)

      let enterEvent = KeyEvent(code: Enter, char: "", modifiers: {})

      let handled = btn.handleKeyEvent(enterEvent)
      check handled == erConsume
      check clickCount == 1

    test "Keyboard event handling - Space key":
      var clickCount = 0
      var btn = newButton("Test")
      btn.onClick = proc() =
        clickCount.inc()
      btn.setState(Focused)

      let spaceEvent = KeyEvent(code: Space, char: " ", modifiers: {})

      let handled = btn.handleKeyEvent(spaceEvent)
      check handled == erConsume
      check clickCount == 1

    test "Custom key press handler":
      var customKeyPressed = false
      var btn = newButton("Test")
      btn.onKeyPress = proc(key: KeyEvent): EventResult =
        if key.code == Char and key.char == "x":
          customKeyPressed = true
          return erConsume
        return erContinue

      let customEvent = KeyEvent(code: Char, char: "x", modifiers: {})

      let handled = btn.handleKeyEvent(customEvent)
      check handled == erConsume
      check customKeyPressed == true

  suite "Button Event Callbacks Tests":
    test "Mouse enter/leave events":
      var enterCalled = false
      var leaveCalled = false
      var btn = newButton("Test")

      btn.onMouseEnter = proc() =
        enterCalled = true
      btn.onMouseLeave = proc() =
        leaveCalled = true

      btn.setState(Hovered) # Should trigger onMouseEnter
      check enterCalled == true

      btn.setState(Normal) # Should trigger onMouseLeave
      check leaveCalled == true

    test "Focus/blur events":
      var focusCalled = false
      var blurCalled = false
      var btn = newButton("Test")

      btn.onFocus = proc() =
        focusCalled = true
      btn.onBlur = proc() =
        blurCalled = true

      btn.setState(Focused) # Should trigger onFocus
      check focusCalled == true

      btn.setState(Normal) # Should trigger onBlur
      check blurCalled == true

  suite "Button Mouse Event Tests":
    test "Mouse click in bounds":
      var clickCount = 0
      var btn = newButton("Test")
      btn.onClick = proc() =
        clickCount.inc()

      let area = rect(10, 10, 20, 3)

      # Mouse press
      let pressEvent =
        MouseEvent(kind: Press, button: Left, x: 15, y: 11, modifiers: {})

      let pressHandled = btn.handleMouseEvent(pressEvent, area)
      check pressHandled == erConsume
      check btn.state == Pressed

      # Mouse release
      let releaseEvent =
        MouseEvent(kind: Release, button: Left, x: 15, y: 11, modifiers: {})

      let releaseHandled = btn.handleMouseEvent(releaseEvent, area)
      check releaseHandled == erConsume
      check clickCount == 1

    test "Mouse click outside bounds":
      var clickCount = 0
      var btn = newButton("Test")
      btn.onClick = proc() =
        clickCount.inc()

      let area = rect(10, 10, 20, 3)

      # Mouse press outside bounds
      let pressEvent = MouseEvent(
        kind: Press,
        button: Left,
        x: 5,
        y: 5, # Outside the button area
        modifiers: {},
      )

      let handled = btn.handleMouseEvent(pressEvent, area)
      check handled == erContinue
      check clickCount == 0

  suite "Button Text and Styling Tests":
    test "Button text formatting":
      let btn = newButton("Test", padding = 2)
      let formattedText = btn.getButtonText()
      check formattedText == "  Test  "

    test "Button text without padding":
      let btn = newButton("Test", padding = 0)
      let formattedText = btn.getButtonText()
      check formattedText == "Test"

    test "Button current style":
      let btn = newButton(
        "Test", normalStyle = style(White, Blue), hoveredStyle = style(White, Cyan)
      )

      check btn.getCurrentStyle() == style(White, Blue)

      btn.setState(Hovered)
      check btn.getCurrentStyle() == style(White, Cyan)

  suite "Button Size Calculation Tests":
    test "Minimum size calculation":
      let btn = newButton("Test Button", padding = 1)
      let minSize = btn.getMinSize()
      check minSize.width == "Test Button".len + 2 # Text + padding
      check minSize.height == 1

    test "Minimum size with minWidth":
      let btn = newButton("Hi", minWidth = 20, padding = 1)
      let minSize = btn.getMinSize()
      check minSize.width == 20 # minWidth takes precedence
      check minSize.height == 1

  suite "Button Builder Methods Tests":
    test "withText builder":
      let originalBtn = newButton("Original")
      let newBtn = originalBtn.withText("New Text")

      check originalBtn.text == "Original"
      check newBtn.text == "New Text"

    test "withOnClick builder":
      var clickCount = 0
      let originalBtn = newButton("Test")
      let newBtn = originalBtn.withOnClick(
        proc() =
          clickCount.inc()
      )

      newBtn.handleClick()
      check clickCount == 1

    test "withEventHandlers builder":
      var focusCalled = false
      var clickCount = 0

      let originalBtn = newButton("Test")
      let newBtn = originalBtn.withEventHandlers(
        onClick = proc() =
          clickCount.inc(),
        onFocus = proc() =
          focusCalled = true,
      )

      newBtn.handleClick()
      check clickCount == 1

      newBtn.setState(Focused)
      check focusCalled == true

  suite "Button Focus Tests":
    test "Button can focus when enabled":
      let btn = newButton("Test")
      check btn.canFocus() == true

    test "Button cannot focus when disabled":
      var btn = newButton("Test")
      btn.setEnabled(false)
      check btn.canFocus() == false

  suite "Wide Character Layout":
    test "getMinSize counts CJK as 2 columns each":
      let btn = newButton("送信", padding = 0) # 2 CJK chars * 2 cols = 4
      check btn.getMinSize().width == 4

    test "padding adds narrow space on each side around wide text":
      let btn = newButton("送信", padding = 1)
      # " 送信 " = 1 + 4 + 1 = 6 columns
      check btn.getMinSize().width == 6

    test "Wide-character button renders without overflow":
      let btn = newButton("日本", padding = 0)
      var buf = newBuffer(4, 1)
      btn.render(rect(0, 0, 4, 1), buf)
      check buf[0, 0].symbol == "日"
      check buf[1, 0].isShadow()
      check buf[2, 0].symbol == "本"
      check buf[3, 0].isShadow()

    test "Wide-character button truncates to area width":
      let btn = newButton("日本語", padding = 0)
      var buf = newBuffer(4, 1)
      btn.render(rect(0, 0, 4, 1), buf)
      # Only "日本" fits in 4 columns
      check buf[0, 0].symbol == "日"
      check buf[2, 0].symbol == "本"
