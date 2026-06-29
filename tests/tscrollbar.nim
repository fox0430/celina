## Unit tests for Scrollbar widget

import std/unittest

import ../celina/core/[geometry, buffer, colors, events]
import ../celina/widgets/scrollbar

suite "Scrollbar Widget Tests":
  suite "Creation and builders":
    test "default construction":
      let sb = newScrollbar()
      check sb.orientation == sbVerticalRight
      check sb.contentLength == 0
      check sb.viewportLength == 0
      check sb.position == 0
      check sb.thumbSymbol == ""
      check sb.trackSymbol == ""
      check sb.beginSymbol == ""
      check sb.endSymbol == ""

    test "short constructor":
      let sb = scrollbar(sbHorizontalBottom, 100, 20, 5)
      check sb.orientation == sbHorizontalBottom
      check sb.contentLength == 100
      check sb.viewportLength == 20
      check sb.position == 5

    test "builders return copies without mutating original":
      let base = scrollbar(sbVerticalRight, 50, 10, 0)
      let moved = base.withPosition(7).withOrientation(sbVerticalLeft)
      check base.position == 0
      check base.orientation == sbVerticalRight
      check moved.position == 7
      check moved.orientation == sbVerticalLeft

    test "withState sets all three numbers":
      let sb = newScrollbar().withState(200, 40, 13)
      check sb.contentLength == 200
      check sb.viewportLength == 40
      check sb.position == 13

    test "withSymbols keeps existing on empty args":
      let sb = newScrollbar().withSymbols(thumb = "#", track = ".")
      check sb.thumbSymbol == "#"
      check sb.trackSymbol == "."
      let sb2 = sb.withSymbols(`begin` = "^")
      check sb2.thumbSymbol == "#" # unchanged
      check sb2.beginSymbol == "^"

  suite "State helpers":
    test "isVertical":
      check sbVerticalRight.isVertical
      check sbVerticalLeft.isVertical
      check not sbHorizontalTop.isVertical
      check not sbHorizontalBottom.isVertical

    test "maxPosition and isScrollable":
      let sb = scrollbar(sbVerticalRight, 100, 20, 0)
      check sb.maxPosition == 80
      check sb.isScrollable

      let fits = scrollbar(sbVerticalRight, 10, 20, 0)
      check fits.maxPosition == 0
      check not fits.isScrollable

    test "clampPosition":
      let sb = scrollbar(sbVerticalRight, 100, 20, 999)
      sb.clampPosition()
      check sb.position == 80
      sb.position = -5
      sb.clampPosition()
      check sb.position == 0

    test "setPosition fires onChange only on change":
      var calls: seq[int] = @[]
      let sb = scrollbar(sbVerticalRight, 100, 20, 0)
      sb.onChange = proc(p: int) =
        calls.add(p)

      sb.setPosition(30)
      check sb.position == 30
      check calls == @[30]

      sb.setPosition(30) # no change → no callback
      check calls == @[30]

      sb.setPosition(999) # clamped to 80
      check sb.position == 80
      check calls == @[30, 80]

    test "scrollBy clamps at both ends":
      let sb = scrollbar(sbVerticalRight, 100, 20, 0)
      sb.scrollBy(-1)
      check sb.position == 0
      sb.scrollBy(5)
      check sb.position == 5
      sb.scrollBy(1000)
      check sb.position == 80

  suite "Thumb metrics":
    test "content fits viewport → thumb fills track":
      let sb = scrollbar(sbVerticalRight, 5, 10, 0)
      let (size, pos) = sb.thumbMetrics(10)
      check size == 10
      check pos == 0

    test "thumb size is proportional":
      let sb = scrollbar(sbVerticalRight, 100, 50, 0)
      let (size, _) = sb.thumbMetrics(10)
      check size == 5

    test "thumb at top and bottom":
      let sb = scrollbar(sbVerticalRight, 100, 20, 0)
      let (sizeTop, posTop) = sb.thumbMetrics(10)
      check posTop == 0

      sb.position = sb.maxPosition
      let (sizeBot, posBot) = sb.thumbMetrics(10)
      check sizeBot == sizeTop
      check posBot == 10 - sizeBot # flush against the end

    test "zero-length track":
      let sb = scrollbar(sbVerticalRight, 100, 20, 0)
      let (size, pos) = sb.thumbMetrics(0)
      check size == 0
      check pos == 0

  suite "Rendering":
    test "vertical right draws on the right column":
      var buf = newBuffer(4, 10)
      let sb = scrollbar(sbVerticalRight, 100, 20, 0)
      sb.render(rect(0, 0, 4, 10), buf)
      # Bar lives in the rightmost column only.
      check buf[3, 0].symbol == "█" # thumb at top
      check buf[0, 0].symbol == " " # other columns untouched
      # Track somewhere below the thumb.
      check buf[3, 9].symbol == "│"

    test "vertical left draws on the left column":
      var buf = newBuffer(4, 10)
      let sb = scrollbar(sbVerticalLeft, 100, 20, 0)
      sb.render(rect(0, 0, 4, 10), buf)
      check buf[0, 0].symbol == "█"
      check buf[3, 0].symbol == " "

    test "horizontal bottom draws on the bottom row":
      var buf = newBuffer(10, 4)
      let sb = scrollbar(sbHorizontalBottom, 100, 20, 0)
      sb.render(rect(0, 0, 10, 4), buf)
      check buf[0, 3].symbol == "█" # thumb at start, bottom row
      check buf[0, 0].symbol == " " # top rows untouched
      check buf[9, 3].symbol == "─" # default horizontal track glyph

    test "thumb moves to the bottom when scrolled to end":
      var buf = newBuffer(1, 10)
      let sb = scrollbar(sbVerticalRight, 100, 20, 0)
      sb.position = sb.maxPosition
      sb.render(rect(0, 0, 1, 10), buf)
      check buf[0, 9].symbol == "█" # last cell is thumb
      check buf[0, 0].symbol == "│" # top is track

    test "begin/end caps occupy the ends":
      var buf = newBuffer(1, 10)
      let sb = newScrollbar(sbVerticalRight, 100, 20, 0).withSymbols(
          `begin` = "▲", `end` = "▼"
        )
      sb.render(rect(0, 0, 1, 10), buf)
      check buf[0, 0].symbol == "▲"
      check buf[0, 9].symbol == "▼"

    test "custom symbols are used":
      var buf = newBuffer(1, 10)
      let sb =
        scrollbar(sbVerticalRight, 100, 20, 0).withSymbols(thumb = "#", track = ".")
      sb.render(rect(0, 0, 1, 10), buf)
      check buf[0, 0].symbol == "#"
      check buf[0, 9].symbol == "."

    test "empty area renders nothing":
      var buf = newBuffer(5, 5)
      let sb = scrollbar(sbVerticalRight, 100, 20, 0)
      sb.render(rect(0, 0, 0, 0), buf)
      check buf[0, 0].symbol == " "

  suite "Sizing":
    test "min and preferred size":
      let v = scrollbar(sbVerticalRight)
      check v.getMinSize() == size(1, 1)
      check v.getPreferredSize(size(10, 20)) == size(1, 20)

      let h = scrollbar(sbHorizontalBottom)
      check h.getPreferredSize(size(30, 10)) == size(30, 1)

  suite "Mouse interaction":
    test "wheel scrolls by one":
      let sb = scrollbar(sbVerticalRight, 100, 20, 5)
      let area = rect(0, 0, 1, 10)

      let down = MouseEvent(kind: Press, button: WheelDown, x: 0, y: 0)
      check sb.handleMouseEvent(down, area) == erConsume
      check sb.position == 6

      let up = MouseEvent(kind: Press, button: WheelUp, x: 0, y: 0)
      check sb.handleMouseEvent(up, area) == erConsume
      check sb.position == 5

    test "non-scrollable ignores events":
      let sb = scrollbar(sbVerticalRight, 5, 20, 0)
      let area = rect(0, 0, 1, 10)
      let down = MouseEvent(kind: Press, button: WheelDown, x: 0, y: 0)
      check sb.handleMouseEvent(down, area) == erContinue
      check sb.position == 0

    test "click on the bar jumps the thumb":
      var changed = -1
      let sb = scrollbar(sbVerticalRight, 100, 20, 0)
      sb.onChange = proc(p: int) =
        changed = p
      let area = rect(0, 0, 1, 10)

      # Click at the very bottom of a 10-cell bar → end position.
      let click = MouseEvent(kind: Press, button: Left, x: 0, y: 9)
      check sb.handleMouseEvent(click, area) == erConsume
      check sb.position == sb.maxPosition
      check changed == sb.maxPosition

      # Click at the top → position 0.
      let top = MouseEvent(kind: Press, button: Left, x: 0, y: 0)
      check sb.handleMouseEvent(top, area) == erConsume
      check sb.position == 0

    test "click off the bar is ignored":
      let sb = scrollbar(sbVerticalRight, 100, 20, 3)
      let area = rect(0, 0, 4, 10) # bar is column 3
      let click = MouseEvent(kind: Press, button: Left, x: 1, y: 5)
      check sb.handleMouseEvent(click, area) == erContinue
      check sb.position == 3

    test "handleEvent forwards mouse only":
      let sb = scrollbar(sbVerticalRight, 100, 20, 5)
      let area = rect(0, 0, 1, 10)
      let wheel = Event(
        kind: EventKind.Mouse,
        mouse: MouseEvent(kind: Press, button: WheelDown, x: 0, y: 0),
      )
      check sb.handleEvent(wheel, area) == erConsume
      check sb.position == 6

      let key = Event(kind: EventKind.Key, key: KeyEvent(code: Enter))
      check sb.handleEvent(key, area) == erContinue
