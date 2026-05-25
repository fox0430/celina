## Tests for the unified widget event dispatch (handleEvent) and the
## Container abstraction introduced in widgets/base.nim and
## widgets/container.nim.

import std/unittest

import ../celina/core/[geometry, events]
import ../celina/widgets/[base, button, input, text, container, tabs]

proc keyEv(code: KeyCode, ch: string = "", mods: set[KeyModifier] = {}): Event =
  Event(kind: EventKind.Key, key: KeyEvent(code: code, char: ch, modifiers: mods))

proc mouseEv(kind: MouseEventKind, button: MouseButton, x, y: int): Event =
  Event(
    kind: EventKind.Mouse,
    mouse: MouseEvent(kind: kind, button: button, x: x, y: y, modifiers: {}),
  )

suite "Widget base handleEvent":
  test "Default handleEvent returns erContinue":
    # Text has no event handling; the base method is reached.
    let widget: Widget = newText("hello")
    let area = rect(0, 0, 10, 1)
    check widget.handleEvent(keyEv(Enter), area) == erContinue
    check widget.handleEvent(
      mouseEv(MouseEventKind.Press, MouseButton.Left, 0, 0), area
    ) == erContinue

  test "Default setFocus / isFocused are no-ops":
    let widget: Widget = newText("hello")
    widget.setFocus(true)
    check widget.isFocused() == false

suite "Button handleEvent dispatch":
  test "Key Enter consumes and triggers onClick":
    var clicked = 0
    var btn = newButton("OK")
    btn.onClick = proc() =
      clicked.inc()
    let area = rect(0, 0, 10, 3)
    let r = btn.handleEvent(keyEv(Enter), area)
    check r == erConsume
    check clicked == 1

  test "Non-key/mouse event returns erContinue":
    var btn = newButton("OK")
    let area = rect(0, 0, 10, 3)
    let r = btn.handleEvent(Event(kind: EventKind.Resize), area)
    check r == erContinue

  test "Button works through Widget base reference":
    var clicked = 0
    var btn = newButton("OK")
    btn.onClick = proc() =
      clicked.inc()
    let asBase: Widget = btn
    let area = rect(0, 0, 10, 3)
    check asBase.handleEvent(keyEv(Enter), area) == erConsume
    check clicked == 1

  test "setFocus updates Button visual state":
    var btn = newButton("OK")
    btn.setFocus(true)
    check btn.isFocused()
    btn.setFocus(false)
    check not btn.isFocused()

suite "Input handleEvent dispatch":
  test "Input consumes character keys when focused":
    var inp = newInput()
    inp.setFocus(true)
    let area = rect(0, 0, 20, 1)
    let r = inp.handleEvent(keyEv(Char, "a"), area)
    check r == erConsume
    check inp.getText() == "a"

  test "Input ignores keys when not focused":
    var inp = newInput()
    let area = rect(0, 0, 20, 1)
    let r = inp.handleEvent(keyEv(Char, "a"), area)
    check r == erContinue
    check inp.getText() == ""

  test "Input ignores mouse events":
    var inp = newInput()
    inp.setFocus(true)
    let area = rect(0, 0, 20, 1)
    let r = inp.handleEvent(mouseEv(MouseEventKind.Press, MouseButton.Left, 0, 0), area)
    check r == erContinue

suite "Container dispatch":
  test "Empty container does not forward events":
    let c = newContainer()
    check c.focusedChild() == nil
    check c.handleEvent(keyEv(Enter), rect(0, 0, 10, 3)) == erContinue

  test "Focused child receives the event":
    var btn1Clicks = 0
    var btn2Clicks = 0
    var b1 = newButton("A")
    b1.onClick = proc() =
      btn1Clicks.inc()
    var b2 = newButton("B")
    b2.onClick = proc() =
      btn2Clicks.inc()
    let c = newContainer(@[Widget(b1), Widget(b2)], focusedIndex = 1)
    let area = rect(0, 0, 10, 3)
    check c.handleEvent(keyEv(Enter), area) == erConsume
    check btn1Clicks == 0
    check btn2Clicks == 1

  test "Focus switching notifies children":
    var b1 = newButton("A")
    var b2 = newButton("B")
    let c = newContainer(@[Widget(b1), Widget(b2)], focusedIndex = 0)
    check b1.isFocused()
    check not b2.isFocused()
    c.setFocusedIndex(1)
    check not b1.isFocused()
    check b2.isFocused()

  test "focusNext / focusPrev wrap around focusable children":
    var b1 = newButton("A")
    var b2 = newButton("B")
    var b3 = newButton("C")
    let c = newContainer(@[Widget(b1), Widget(b2), Widget(b3)], focusedIndex = 0)
    check c.focusNext()
    check c.focusedIndex == 1
    check c.focusNext()
    check c.focusedIndex == 2
    check c.focusNext()
    check c.focusedIndex == 0 # wrap
    check c.focusPrev()
    check c.focusedIndex == 2 # wrap backward

  test "Non-focusable children are skipped":
    # Text widget is not focusable; Button is.
    let txt: Widget = newText("label")
    var btn = newButton("OK")
    let c = newContainer(@[txt, Widget(btn)], focusedIndex = 1)
    # Cycling from button should land back on button (text not focusable).
    check c.focusNext()
    check c.focusedIndex == 1

  test "setFocus(true) auto-selects first focusable child when none focused":
    var b1 = newButton("A")
    var b2 = newButton("B")
    let c = newContainer(@[Widget(b1), Widget(b2)]) # focusedIndex = -1
    check c.focusedIndex == -1
    c.setFocus(true)
    # First focusable child is picked, and the widget actually receives focus.
    check c.focusedIndex == 0
    check b1.isFocused()

  test "setFocus(true) auto-select skips non-focusable children":
    let txt: Widget = newText("label")
    var btn = newButton("OK")
    let c = newContainer(@[txt, Widget(btn)]) # focusedIndex = -1
    c.setFocus(true)
    check c.focusedIndex == 1
    check btn.isFocused()

  test "setFocus(false) preserves focusedIndex":
    var b1 = newButton("A")
    let c = newContainer(@[Widget(b1)], focusedIndex = 0)
    check b1.isFocused()
    c.setFocus(false)
    check not b1.isFocused()
    check c.focusedIndex == 0 # preserved for re-entry
    c.setFocus(true)
    check b1.isFocused()

suite "Tabs dispatch":
  test "Tab key cycles forward; Shift+Tab cycles backward":
    let widget =
      newTabs(@[tab("a", newText("A")), tab("b", newText("B")), tab("c", newText("C"))])
    let area = rect(0, 0, 20, 10)
    check widget.activeIndex == 0
    check widget.handleEvent(keyEv(KeyCode.Tab), area) == erConsume
    check widget.activeIndex == 1
    check widget.handleEvent(keyEv(KeyCode.Tab), area) == erConsume
    check widget.activeIndex == 2
    check widget.handleEvent(keyEv(KeyCode.Tab), area) == erConsume
    check widget.activeIndex == 0 # wrap
    check widget.handleEvent(keyEv(KeyCode.Tab, mods = {Shift}), area) == erConsume
    check widget.activeIndex == 2
    # BackTab (emitted by ESC[Z on Shift+Tab) is also handled.
    check widget.handleEvent(keyEv(KeyCode.BackTab), area) == erConsume
    check widget.activeIndex == 1

  test "Active tab content receives non-Tab key events":
    var inp = newInput()
    inp.setFocus(true)
    let widget = newTabs(@[tab("input", inp), tab("text", newText("static"))])
    let area = rect(0, 0, 30, 10)
    check widget.handleEvent(keyEv(Char, "x"), area) == erConsume
    check inp.getText() == "x"

  test "Empty Tabs returns erContinue":
    let widget = newTabs()
    let area = rect(0, 0, 10, 5)
    check widget.handleEvent(keyEv(Enter), area) == erContinue

  test "Left-click on tab heading switches active tab":
    let widget = newTabs(
      @[tab("aaa", newText("A")), tab("bbb", newText("B")), tab("ccc", newText("C"))],
      showBorder = false,
    )
    let area = rect(0, 0, 30, 5)
    check widget.activeIndex == 0
    # Each heading is 5 cells wide (" aaa " etc.), then a 1-cell divider.
    # Click in the middle of the third tab's heading.
    let thirdTabX = 5 + 1 + 5 + 1 + 2 # tab0(5) + div + tab1(5) + div + offset
    check widget.handleEvent(
      mouseEv(MouseEventKind.Press, MouseButton.Left, thirdTabX, 0), area
    ) == erConsume
    check widget.activeIndex == 2

  test "Click on tab divider does not switch":
    let widget =
      newTabs(@[tab("aa", newText("A")), tab("bb", newText("B"))], showBorder = false)
    let area = rect(0, 0, 20, 5)
    # tab0 occupies x=0..3 (" aa "), divider at x=4, tab1 from x=5.
    let dividerX = 4
    let before = widget.activeIndex
    let r = widget.handleEvent(
      mouseEv(MouseEventKind.Press, MouseButton.Left, dividerX, 0), area
    )
    # Divider falls through: not consumed by tabs, forwarded to content
    # (Text), which returns erContinue.
    check r == erContinue
    check widget.activeIndex == before

  test "Click outside tab bar is forwarded to active content":
    var inp = newInput()
    inp.setFocus(true)
    let widget = newTabs(@[tab("input", inp)], showBorder = false)
    let area = rect(0, 0, 30, 5)
    # y=2 is inside content area, not the tab bar row (y=0).
    let r =
      widget.handleEvent(mouseEv(MouseEventKind.Press, MouseButton.Left, 5, 2), area)
    # Input ignores mouse, returns erContinue — but importantly the
    # active tab is unchanged (no spurious switch).
    check r == erContinue
    check widget.activeIndex == 0

  test "Right-click on tab heading does not switch":
    let widget =
      newTabs(@[tab("aa", newText("A")), tab("bb", newText("B"))], showBorder = false)
    let area = rect(0, 0, 20, 5)
    let r =
      widget.handleEvent(mouseEv(MouseEventKind.Press, MouseButton.Right, 1, 0), area)
    check r == erContinue
    check widget.activeIndex == 0
