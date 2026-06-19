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
      btn.setFocus(true)

      let enterEvent = KeyEvent(code: Enter, char: "", modifiers: {})

      let handled = btn.handleKeyEvent(enterEvent)
      check handled == erConsume
      check clickCount == 1

    test "Keyboard event handling - Space key":
      var clickCount = 0
      var btn = newButton("Test")
      btn.onClick = proc() =
        clickCount.inc()
      btn.setFocus(true)

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

      # Unfocused: the custom handler is not reached and the key falls through.
      check btn.handleKeyEvent(customEvent) == erContinue
      check customKeyPressed == false

      # Focused: the custom handler fires and consumes the key.
      btn.setFocus(true)
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

      btn.setFocus(true) # Should trigger onFocus
      check focusCalled == true
      check btn.state == Focused

      btn.setFocus(false) # Should trigger onBlur
      check blurCalled == true
      check btn.state == Normal

    test "setState is render-only and does not fire focus callbacks":
      var focusCalled = 0
      var blurCalled = 0
      var btn = newButton("Test")

      btn.onFocus = proc() =
        focusCalled.inc()
      btn.onBlur = proc() =
        blurCalled.inc()

      # setState drives the visual only; focus is owned by setFocus.
      btn.setState(Focused)
      btn.setState(Normal)
      check focusCalled == 0
      check blurCalled == 0
      check not btn.isFocused()

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

    test "Keyboard focus survives mouse hover and leave":
      var btn = newButton("Test")
      btn.setFocus(true)
      check btn.isFocused()
      check btn.state == Focused

      let area = rect(10, 10, 20, 3)

      # Hovering shows the hover visual but keeps keyboard focus.
      let moveIn = MouseEvent(kind: Move, button: Left, x: 15, y: 11, modifiers: {})
      check btn.handleMouseEvent(moveIn, area) == erConsume
      check btn.state == Hovered
      check btn.isFocused()

      # Leaving restores the focus visual instead of dropping to Normal.
      let moveOut = MouseEvent(kind: Move, button: Left, x: 1, y: 1, modifiers: {})
      check btn.handleMouseEvent(moveOut, area) == erContinue
      check btn.isFocused()
      check btn.state == Focused

    test "Hover callbacks fire while keeping focus":
      var enterCalled = 0
      var leaveCalled = 0
      var focusCalled = 0
      var btn = newButton("Test")
      btn.onMouseEnter = proc() =
        enterCalled.inc()
      btn.onMouseLeave = proc() =
        leaveCalled.inc()
      btn.onFocus = proc() =
        focusCalled.inc()
      btn.setFocus(true)
      check focusCalled == 1

      let area = rect(10, 10, 20, 3)
      let moveIn = MouseEvent(kind: Move, button: Left, x: 15, y: 11, modifiers: {})
      discard btn.handleMouseEvent(moveIn, area)
      let moveOut = MouseEvent(kind: Move, button: Left, x: 1, y: 1, modifiers: {})
      discard btn.handleMouseEvent(moveOut, area)

      check enterCalled == 1
      check leaveCalled == 1
      # Leaving the hover must not re-fire onFocus.
      check focusCalled == 1
      check btn.isFocused()

    test "Click on focused button preserves keyboard focus":
      var btn = newButton("Test")
      btn.setFocus(true)
      let area = rect(10, 10, 20, 3)

      let pressEvent =
        MouseEvent(kind: Press, button: Left, x: 15, y: 11, modifiers: {})
      let releaseEvent =
        MouseEvent(kind: Release, button: Left, x: 15, y: 11, modifiers: {})
      discard btn.handleMouseEvent(pressEvent, area)
      discard btn.handleMouseEvent(releaseEvent, area)
      check btn.isFocused()

      # Moving away after the click restores the focus visual.
      let moveOut = MouseEvent(kind: Move, button: Left, x: 1, y: 1, modifiers: {})
      discard btn.handleMouseEvent(moveOut, area)
      check btn.state == Focused
      check btn.isFocused()

    test "Release outside bounds cancels the press without clicking":
      var clickCount = 0
      var leaveCount = 0
      var btn = newButton("Test")
      btn.onClick = proc() =
        clickCount.inc()
      btn.onMouseLeave = proc() =
        leaveCount.inc()
      btn.setFocus(true)
      let area = rect(10, 10, 20, 3)

      # Press inside, then release after the pointer has left the button.
      discard btn.handleMouseEvent(
        MouseEvent(kind: Press, button: Left, x: 15, y: 11, modifiers: {}), area
      )
      check btn.state == Pressed
      discard btn.handleMouseEvent(
        MouseEvent(kind: Release, button: Left, x: 1, y: 1, modifiers: {}), area
      )

      # No click fires, the Pressed visual is reset, and focus is restored.
      check clickCount == 0
      check leaveCount == 1
      check btn.state == Focused
      check btn.isFocused()

    test "A full click fires onMouseEnter exactly once":
      var enterCount = 0
      var btn = newButton("Test")
      btn.onMouseEnter = proc() =
        enterCount.inc()
      let area = rect(10, 10, 20, 3)

      # Hover, press, release -- the Release must not re-fire onMouseEnter.
      discard btn.handleMouseEvent(
        MouseEvent(kind: Move, button: Left, x: 15, y: 11, modifiers: {}), area
      )
      discard btn.handleMouseEvent(
        MouseEvent(kind: Press, button: Left, x: 15, y: 11, modifiers: {}), area
      )
      discard btn.handleMouseEvent(
        MouseEvent(kind: Release, button: Left, x: 15, y: 11, modifiers: {}), area
      )
      check btn.state == Hovered
      check enterCount == 1

    test "Click without a preceding Move still fires onMouseEnter once":
      var enterCount = 0
      var clickCount = 0
      var btn = newButton("Test")
      btn.onMouseEnter = proc() =
        enterCount.inc()
      btn.onClick = proc() =
        clickCount.inc()
      let area = rect(10, 10, 20, 3)

      # Terminals in press/release-only mode never send Move: the press must
      # still surface a single onMouseEnter.
      discard btn.handleMouseEvent(
        MouseEvent(kind: Press, button: Left, x: 15, y: 11, modifiers: {}), area
      )
      discard btn.handleMouseEvent(
        MouseEvent(kind: Release, button: Left, x: 15, y: 11, modifiers: {}), area
      )
      check enterCount == 1
      check clickCount == 1

    test "Drag out and back in still completes the click":
      var clickCount = 0
      var btn = newButton("Test")
      btn.onClick = proc() =
        clickCount.inc()
      let area = rect(10, 10, 20, 3)

      discard btn.handleMouseEvent(
        MouseEvent(kind: Press, button: Left, x: 15, y: 11, modifiers: {}), area
      )
      # Dragging out while held keeps the press alive (so it can be resumed).
      discard btn.handleMouseEvent(
        MouseEvent(kind: Move, button: Left, x: 1, y: 1, modifiers: {}), area
      )
      check btn.state == Pressed
      # Dragging back in keeps it pressed, and releasing inside clicks.
      discard btn.handleMouseEvent(
        MouseEvent(kind: Move, button: Left, x: 15, y: 11, modifiers: {}), area
      )
      check btn.state == Pressed
      discard btn.handleMouseEvent(
        MouseEvent(kind: Release, button: Left, x: 15, y: 11, modifiers: {}), area
      )
      check clickCount == 1

    test "Keyboard activation keeps focus visual":
      var btn = newButton("Test")
      btn.setFocus(true)
      check btn.handleKeyEvent(KeyEvent(code: Enter, char: "", modifiers: {})) ==
        erConsume
      check btn.state == Focused
      check btn.isFocused()

    test "handleKeyEvent ignores keys when not focused":
      var clickCount = 0
      var btn = newButton("Test")
      btn.onClick = proc() =
        clickCount.inc()

      # Not focused: Enter/Space fall through (erContinue) and onClick is not run.
      check btn.handleKeyEvent(KeyEvent(code: Enter, char: "", modifiers: {})) ==
        erContinue
      check btn.handleKeyEvent(KeyEvent(code: Space, char: " ", modifiers: {})) ==
        erContinue
      check clickCount == 0

      # Focused: the same keys are consumed and trigger onClick.
      btn.setFocus(true)
      check btn.handleKeyEvent(KeyEvent(code: Enter, char: "", modifiers: {})) ==
        erConsume
      check clickCount == 1

    test "Keyboard activation does not re-fire onFocus":
      var focusCount = 0
      var btn = newButton("Test")
      btn.onFocus = proc() =
        focusCount.inc()
      btn.setFocus(true)
      check focusCount == 1

      check btn.handleKeyEvent(KeyEvent(code: Enter, char: "", modifiers: {})) ==
        erConsume
      check btn.handleKeyEvent(KeyEvent(code: Space, char: " ", modifiers: {})) ==
        erConsume
      check focusCount == 1

    test "Keyboard activation that disables the button keeps the Disabled visual":
      # A submit handler that disables itself (double-submit guard) must keep
      # the Disabled visual: the post-click visual restore must not clobber it.
      var btn = newButton("Submit")
      btn.onClick = proc() =
        btn.setEnabled(false)
      btn.setFocus(true)
      check btn.handleKeyEvent(KeyEvent(code: Enter, char: "", modifiers: {})) ==
        erConsume
      check not btn.isEnabled()
      check btn.state == Disabled
      check not btn.isFocused()

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

      newBtn.setFocus(true)
      check focusCalled == true

    test "Builders preserve all callbacks":
      var enterCalled = false
      var leaveCalled = false
      var focusCalled = false
      var blurCalled = false
      var keyHandled = false
      let base = newButton(
        "Base",
        callbacks = ButtonCallbacks(
          onMouseEnter: proc() =
            enterCalled = true,
          onMouseLeave: proc() =
            leaveCalled = true,
          onFocus: proc() =
            focusCalled = true,
          onBlur: proc() =
            blurCalled = true,
          onKeyPress: proc(key: KeyEvent): EventResult =
            keyHandled = true
            erConsume,
        ),
      )

      let derived = [
        base.withText("New"),
        base.withStyles(normal = style(Red, Black)),
        base.withPadding(3),
        base.withMinWidth(10),
      ]
      for btn in derived:
        check btn.onMouseEnter != nil
        check btn.onMouseLeave != nil
        check btn.onFocus != nil
        check btn.onBlur != nil
        check btn.onKeyPress != nil

      # Confirm the preserved callbacks are the originals, not stubs.
      enterCalled = false
      leaveCalled = false
      focusCalled = false
      blurCalled = false
      keyHandled = false
      let b = base.withText("New")
      b.onMouseEnter()
      b.onMouseLeave()
      b.onFocus()
      b.onBlur()
      check b.onKeyPress(KeyEvent(code: Enter, char: "", modifiers: {})) == erConsume
      check enterCalled
      check leaveCalled
      check focusCalled
      check blurCalled
      check keyHandled

  suite "Button Focus Tests":
    test "Button can focus when enabled":
      let btn = newButton("Test")
      check btn.canFocus() == true

    test "Button cannot focus when disabled":
      var btn = newButton("Test")
      btn.setEnabled(false)
      check btn.canFocus() == false

    test "Disabling clears focus and fires blur":
      var focusCount = 0
      var blurCount = 0
      var btn = newButton("Test")
      btn.onFocus = proc() =
        focusCount.inc()
      btn.onBlur = proc() =
        blurCount.inc()

      btn.setFocus(true)
      check btn.isFocused()
      check focusCount == 1
      check blurCount == 0

      btn.setEnabled(false)
      check not btn.isFocused()
      check btn.state == Disabled
      check blurCount == 1

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
