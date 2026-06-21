## Tests for the Panel widget

import std/unittest

import ../celina/widgets/[panel, text, base]
import ../celina/core/[buffer, geometry, colors, borders, events]

type StubChild = ref object of Widget
  ## Minimal focusable child used to verify Panel forwards the Widget
  ## contract (focus + events) to whatever it hosts.
  focused: bool
  gotEvent: bool
  lastArea: Rect

method canFocus(w: StubChild): bool =
  true

method setFocus(w: StubChild, focused: bool) =
  w.focused = focused

method isFocused(w: StubChild): bool =
  w.focused

method handleEvent(w: StubChild, event: Event, area: Rect): EventResult =
  w.gotEvent = true
  w.lastArea = area
  erConsume

suite "Panel Widget Tests":
  suite "Panel Creation":
    test "Default panel":
      let p = newPanel()
      check p != nil
      check p.borders == allBorders
      check p.borderKind == bkSingle
      check p.title == ""
      check p.titleAlignment == taLeft
      check p.child == nil

    test "Panel with title and alignment":
      let p = newPanel(title = "Hello", titleAlignment = taCenter)
      check p.title == "Hello"
      check p.titleAlignment == taCenter

    test "Panel with subset of borders":
      let p = newPanel(borders = {bsTop, bsBottom})
      check p.borders == {bsTop, bsBottom}

  suite "Padding helpers":
    test "Uniform padding":
      let p = padding(2)
      check p.top == 2 and p.right == 2 and p.bottom == 2 and p.left == 2

    test "Symmetric padding":
      let p = padding(3, 1)
      check p.left == 3 and p.right == 3
      check p.top == 1 and p.bottom == 1

    test "Per-side padding":
      let p = padding(1, 2, 3, 4)
      check p.top == 1 and p.right == 2 and p.bottom == 3 and p.left == 4

  suite "Inner area":
    test "Full border shrinks one cell per side":
      let p = newPanel()
      let inner = p.inner(rect(0, 0, 10, 6))
      check inner == rect(1, 1, 8, 4)

    test "No border leaves full area":
      let p = newPanel(borders = {})
      let inner = p.inner(rect(0, 0, 10, 6))
      check inner == rect(0, 0, 10, 6)

    test "Partial borders only shrink drawn sides":
      let p = newPanel(borders = {bsLeft})
      let inner = p.inner(rect(0, 0, 10, 6))
      check inner == rect(1, 0, 9, 6)

    test "Padding adds to border thickness":
      let p = newPanel(padding = padding(2))
      let inner = p.inner(rect(0, 0, 20, 20))
      check inner == rect(3, 3, 14, 14)

    test "Inner area clamps to non-negative size":
      let p = newPanel(padding = padding(10))
      let inner = p.inner(rect(0, 0, 4, 4))
      check inner.width == 0
      check inner.height == 0

  suite "Border rendering":
    test "Corners and edges drawn for full single border":
      let p = newPanel()
      var buf = newBuffer(5, 3)
      p.render(rect(0, 0, 5, 3), buf)
      check buf[0, 0].symbol == "┌"
      check buf[4, 0].symbol == "┐"
      check buf[0, 2].symbol == "└"
      check buf[4, 2].symbol == "┘"
      check buf[1, 0].symbol == "─"
      check buf[0, 1].symbol == "│"

    test "Rounded border uses rounded corners":
      let p = newPanel(borderKind = bkRounded)
      var buf = newBuffer(5, 3)
      p.render(rect(0, 0, 5, 3), buf)
      check buf[0, 0].symbol == "╭"
      check buf[4, 2].symbol == "╯"

    test "bkNone draws nothing":
      let p = newPanel(borderKind = bkNone)
      var buf = newBuffer(5, 3)
      p.render(rect(0, 0, 5, 3), buf)
      check buf[0, 0].symbol == " "

    test "Only top border drawn when selected":
      let p = newPanel(borders = {bsTop})
      var buf = newBuffer(5, 3)
      p.render(rect(0, 0, 5, 3), buf)
      check buf[0, 0].symbol == "─"
      # No left edge, so the left column below the top stays blank.
      check buf[0, 1].symbol == " "
      check buf[0, 2].symbol == " "

  suite "Title rendering":
    test "Left aligned title appears after the corner":
      let p = newPanel(title = "Hi")
      var buf = newBuffer(10, 3)
      p.render(rect(0, 0, 10, 3), buf)
      check buf[1, 0].symbol == "H"
      check buf[2, 0].symbol == "i"

    test "Right aligned title ends before the corner":
      let p = newPanel(title = "Hi", titleAlignment = taRight)
      var buf = newBuffer(10, 3)
      p.render(rect(0, 0, 10, 3), buf)
      check buf[7, 0].symbol == "H"
      check buf[8, 0].symbol == "i"

    test "Long title is truncated with an ellipsis":
      let p = newPanel(title = "VeryLongTitle")
      var buf = newBuffer(8, 3)
      p.render(rect(0, 0, 8, 3), buf)
      # Available span is 6 cells (8 - 2 corners); last visible is the ellipsis.
      check buf[6, 0].symbol == "…"

    test "No title drawn without a top border":
      let p = newPanel(borders = {bsBottom}, title = "Hi")
      var buf = newBuffer(10, 3)
      p.render(rect(0, 0, 10, 3), buf)
      check buf[1, 0].symbol == " "

  suite "Child rendering":
    test "Child renders inside the content area":
      let p = newPanel(child = newText("X"))
      var buf = newBuffer(5, 3)
      p.render(rect(0, 0, 5, 3), buf)
      check buf[1, 1].symbol == "X"

  suite "Builders":
    test "Builders return a modified copy":
      let p = newPanel()
      let p2 = p.withTitle("T", taRight).withBorderKind(bkDouble)
      check p2.title == "T"
      check p2.titleAlignment == taRight
      check p2.borderKind == bkDouble
      # Original untouched.
      check p.title == ""
      check p.borderKind == bkSingle

  suite "Geometry":
    test "Minimum size accounts for borders and padding":
      let p = newPanel(padding = padding(2))
      let m = p.getMinSize()
      # 1 border + 2 padding per side = 3 per side -> 6 total each axis.
      check m.width == 6
      check m.height == 6

    test "Empty area renders nothing":
      let p = newPanel()
      var buf = newBuffer(5, 3)
      p.render(rect(0, 0, 0, 0), buf)
      check buf[0, 0].symbol == " "

  suite "bkNone consistency":
    test "bkNone reserves no layout space":
      # bkNone means 'no border' for layout too, not just painting, even
      # when the borders set still names every side (the default).
      let p = newPanel(borderKind = bkNone)
      check p.inner(rect(0, 0, 10, 6)) == rect(0, 0, 10, 6)
      check p.getMinSize() == size(0, 0)

    test "bkNone draws no floating title":
      let p = newPanel(borderKind = bkNone, title = "Hi")
      var buf = newBuffer(10, 3)
      p.render(rect(0, 0, 10, 3), buf)
      check buf[0, 0].symbol == " "
      check buf[1, 0].symbol == " "
      check buf[2, 0].symbol == " "

  suite "Degenerate sizes":
    test "Bottom-only border draws on a one-row area":
      let p = newPanel(borders = {bsBottom})
      var buf = newBuffer(5, 1)
      p.render(rect(0, 0, 5, 1), buf)
      check buf[0, 0].symbol == "─"
      check buf[4, 0].symbol == "─"

    test "Right-only border draws on a one-column area":
      let p = newPanel(borders = {bsRight})
      var buf = newBuffer(1, 4)
      p.render(rect(0, 0, 1, 4), buf)
      check buf[0, 0].symbol == "│"
      check buf[0, 3].symbol == "│"

    test "Top wins the single row when both top and bottom are requested":
      let p = newPanel(borders = {bsTop, bsBottom})
      var buf = newBuffer(5, 1)
      p.render(rect(0, 0, 5, 1), buf)
      check buf[0, 0].symbol == "─"

    test "Collapsed corner still draws a corner glyph, not a straight edge":
      # bottom + left on a one-row area: the bottom rule and the (height-1)
      # left edge meet at (0,0). The join must be a corner, drawn last, never
      # left as the bare vertical/horizontal glyph.
      let p = newPanel(borders = {bsBottom, bsLeft})
      var buf = newBuffer(5, 1)
      p.render(rect(0, 0, 5, 1), buf)
      check buf[0, 0].symbol == "└"
      check buf[4, 0].symbol == "─"

      # Symmetric one-column case: top + right meet at (0,0) -> a corner.
      let q = newPanel(borders = {bsTop, bsRight})
      var buf2 = newBuffer(1, 4)
      q.render(rect(0, 0, 1, 4), buf2)
      check buf2[0, 0].symbol == "┐"
      check buf2[0, 3].symbol == "│"

  suite "Wide-character title":
    test "Wide title is centered by display width":
      # Each CJK rune occupies 2 columns.
      let p = newPanel(title = "あ", titleAlignment = taCenter)
      var buf = newBuffer(10, 3)
      p.render(rect(0, 0, 10, 3), buf)
      # available = 8, titleWidth = 2 -> startX = 1 + (8 - 2) div 2 = 4
      check buf[4, 0].symbol == "あ"

    test "Wide title truncates on a rune boundary with an ellipsis":
      let p = newPanel(title = "ああああ") # 8 columns wide, available = 6
      var buf = newBuffer(8, 3)
      p.render(rect(0, 0, 8, 3), buf)
      # truncateToWidth(5) keeps "ああ" (4 cols); + "…" -> width 5 at cols 1..5
      check buf[1, 0].symbol == "あ"
      check buf[3, 0].symbol == "あ"
      check buf[5, 0].symbol == "…"

  suite "Fill style":
    test "Interior fill applies the panel style":
      let p = newPanel(borders = {}, style = style(White, Blue))
      var buf = newBuffer(4, 3)
      p.render(rect(0, 0, 4, 3), buf)
      check buf[1, 1].symbol == " "
      check buf[1, 1].style == style(White, Blue)

  suite "Title builders preserve unrelated fields":
    test "withTitle keeps the existing alignment":
      let p = newPanel(titleAlignment = taCenter)
      let p2 = p.withTitle("Hello")
      check p2.title == "Hello"
      check p2.titleAlignment == taCenter

    test "withTitle with explicit alignment overrides":
      let p2 = newPanel().withTitle("Hello", taRight)
      check p2.titleAlignment == taRight

    test "withTitleAlignment changes only the alignment":
      let p = newPanel(title = "Keep")
      let p2 = p.withTitleAlignment(taRight)
      check p2.title == "Keep"
      check p2.titleAlignment == taRight

  suite "Child interaction":
    test "Panel forwards focus and events to its child":
      let child = StubChild()
      let p = newPanel(child = child)
      check p.canFocus()
      p.setFocus(true)
      check child.focused
      check p.isFocused()
      let r = p.handleEvent(
        Event(kind: Key, key: KeyEvent(code: KeyCode.Char, char: "x")),
        rect(0, 0, 10, 6),
      )
      check r == erConsume
      check child.gotEvent
      # The child is handed the content rect, not the outer frame.
      check child.lastArea == p.inner(rect(0, 0, 10, 6))

    test "Childless panel is inert":
      let p = newPanel()
      check not p.canFocus()
      let r = p.handleEvent(
        Event(kind: Key, key: KeyEvent(code: KeyCode.Char, char: "x")),
        rect(0, 0, 10, 6),
      )
      check r == erContinue
