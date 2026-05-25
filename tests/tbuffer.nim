# Test suite for Buffer module

import std/[unittest, strutils, unicode, importutils]

import ../celina/core/buffer
import ../celina/core/geometry
import ../celina/core/colors

suite "Buffer Module Tests":
  suite "Cell Operations":
    test "Cell creations":
      let cellStr = cell("A")
      check cellStr.symbol == "A"
      check cellStr.style == defaultStyle()

      let cellChar = cell('B')
      check cellChar.symbol == "B"
      check cellChar.style == defaultStyle()

      # With custom style
      let style = Style(
        fg: ColorValue(kind: Indexed, indexed: Color.Red),
        modifiers: {StyleModifier.Bold},
      )
      let styledCell = cell("C", style)
      check styledCell.symbol == "C"
      check styledCell.style.fg == ColorValue(kind: Indexed, indexed: Color.Red)
      check styledCell.style.fg.kind == Indexed
      check styledCell.style.fg.indexed == Color.Red
      check StyleModifier.Bold in styledCell.style.modifiers

    test "Cell utility functions":
      let emptyCell = cell("")
      let spaceCell = cell(" ")
      let nonEmptyCell = cell("X")
      let whitespaceCell = cell("   ")

      # isEmpty test
      check emptyCell.isEmpty()
      check not spaceCell.isEmpty() # Space is content
      check not nonEmptyCell.isEmpty()
      check not whitespaceCell.isEmpty() # Whitespace content is not empty

      # width test
      check emptyCell.width() == 0 # Empty cell has no width
      check spaceCell.width() == 1 # Space has width 1
      check nonEmptyCell.width() == 1
      check cell("").width() == 0

    test "Cell equality and string representation":
      let cell1 = cell("A")
      let cell2 = cell("A")
      let cell3 = cell("B")
      let styledCell =
        cell("A", Style(fg: ColorValue(kind: Indexed, indexed: Color.Red)))

      check cell1 == cell2
      check cell1 != cell3
      check cell1 != styledCell

      # String representation
      let str1 = $cell1
      check str1.contains("A")
      check str1.contains("Cell")

  suite "Buffer Creation":
    test "Buffer creation with Rect":
      let area = rect(5, 10, 20, 15)
      let buffer = newBuffer(area)

      check buffer.area == area
      check buffer.area.width == 20
      check buffer.area.height == 15
      check buffer.area.x == 5
      check buffer.area.y == 10

    test "Buffer creation with width and height":
      let buffer = newBuffer(80, 24)

      check buffer.area.x == 0
      check buffer.area.y == 0
      check buffer.area.width == 80
      check buffer.area.height == 24

    test "Buffer initialization with empty cells":
      let buffer = newBuffer(5, 3)

      for y in 0 ..< 3:
        for x in 0 ..< 5:
          let cell = buffer[x, y]
          check cell.symbol == " "
          check cell.style == defaultStyle()

  suite "Buffer Access":
    test "Cell access with coordinates":
      var buffer = newBuffer(10, 5)
      let testCell = cell("X")

      # Set and get using coordinates
      buffer[3, 2] = testCell
      check buffer[3, 2] == testCell

      # Test bounds checking
      check buffer[3, 2].symbol == "X"
      let outOfBounds = buffer[20, 20] # Should return empty cell
      check outOfBounds.symbol == " "

    test "Cell access with Position":
      var buffer = newBuffer(10, 5)
      let testCell = cell("Y")
      let pos = Position(x: 4, y: 1)

      # Set and get using Position
      buffer[pos] = testCell
      check buffer[pos] == testCell
      check buffer[4, 1] == testCell

    test "Position validation":
      let buffer = newBuffer(10, 5)

      # Valid positions
      check buffer.isValidPos(0, 0)
      check buffer.isValidPos(9, 4)
      check buffer.isValidPos(5, 2)

      # Invalid positions
      check not buffer.isValidPos(-1, 0)
      check not buffer.isValidPos(0, -1)
      check not buffer.isValidPos(10, 0)
      check not buffer.isValidPos(0, 5)

      # Position object version
      check buffer.isValidPos(Position(x: 5, y: 2))
      check not buffer.isValidPos(Position(x: 15, y: 2))

  suite "Buffer Operations":
    test "Buffer clear operation":
      var buffer = newBuffer(5, 3)

      # Fill with some data first
      buffer[1, 1] = cell("X")
      buffer[2, 2] = cell("Y")

      # Clear with default
      buffer.clear()

      for y in 0 ..< 3:
        for x in 0 ..< 5:
          check buffer[x, y].symbol == " "

      # Clear with custom cell
      let fillCell =
        cell("#", Style(fg: ColorValue(kind: Indexed, indexed: Color.Blue)))
      buffer.clear(fillCell)

      for y in 0 ..< 3:
        for x in 0 ..< 5:
          check buffer[x, y].symbol == "#"
          check buffer[x, y].style.fg == ColorValue(kind: Indexed, indexed: Color.Blue)

    test "Buffer fill operation":
      var buffer = newBuffer(10, 8)
      let fillCell = cell("*")
      let fillArea = rect(2, 2, 5, 3) # x=2, y=2, width=5, height=3

      buffer.fill(fillArea, fillCell)

      # Check filled area
      for y in 2 ..< 5: # y from 2 to 4 (height=3)
        for x in 2 ..< 7: # x from 2 to 6 (width=5)
          check buffer[x, y].symbol == "*"

      # Check areas outside fill region are untouched
      check buffer[0, 0].symbol == " "
      check buffer[9, 7].symbol == " "
      check buffer[1, 2].symbol == " "
      check buffer[7, 2].symbol == " "

    test "String setting operations":
      var buffer = newBuffer(20, 5)
      let style = Style(fg: ColorValue(kind: Indexed, indexed: Color.Green))

      # Set string with coordinates
      buffer.setString(5, 2, "Hello", style)

      check buffer[5, 2].symbol == "H"
      check buffer[6, 2].symbol == "e"
      check buffer[7, 2].symbol == "l"
      check buffer[8, 2].symbol == "l"
      check buffer[9, 2].symbol == "o"

      # Check style is applied
      for i in 0 ..< 5:
        let cell = buffer[5 + i, 2]
        check cell.style.fg == ColorValue(kind: Indexed, indexed: Color.Green)
        check cell.style.fg.kind == Indexed
        check cell.style.fg.indexed == Color.Green

      # Set string with Position
      let pos = Position(x: 2, y: 3)
      buffer.setString(pos, "World!")

      check buffer[2, 3].symbol == "W"
      check buffer[3, 3].symbol == "o"
      check buffer[7, 3].symbol == "!"

    test "String setting with alignment":
      var buffer = newBuffer(20, 10)

      # Horizontal center, vertical middle
      buffer.setString(buffer.area, "Hello", hAlign = hCenter, vAlign = vMiddle)
      # "Hello" is 5 chars wide, buffer is 20 wide -> x = (20-5)/2 = 7
      # Buffer is 10 tall -> y = (10-1)/2 = 4
      check buffer[7, 4].symbol == "H"
      check buffer[8, 4].symbol == "e"
      check buffer[11, 4].symbol == "o"

      # Right aligned, bottom
      var buffer2 = newBuffer(20, 10)
      buffer2.setString(buffer2.area, "End", hAlign = hRight, vAlign = vBottom)
      # "End" is 3 chars wide -> x = 20-3 = 17, y = 10-1 = 9
      check buffer2[17, 9].symbol == "E"
      check buffer2[18, 9].symbol == "n"
      check buffer2[19, 9].symbol == "d"

      # Left aligned, top (default)
      var buffer3 = newBuffer(20, 10)
      buffer3.setString(buffer3.area, "Top")
      check buffer3[0, 0].symbol == "T"
      check buffer3[1, 0].symbol == "o"
      check buffer3[2, 0].symbol == "p"

    test "String setting with alignment and wide characters":
      var buffer = newBuffer(20, 10)
      # "日本" has display width 4 (2 wide chars)
      buffer.setString(buffer.area, "日本", hAlign = hCenter, vAlign = vMiddle)
      # x = (20-4)/2 = 8, y = (10-1)/2 = 4
      check buffer[8, 4].symbol == "日"
      check buffer[10, 4].symbol == "本"

    test "String setting with alignment clips to area":
      var buffer = newBuffer(20, 10)
      # Text wider than area — should clip, not fail
      let smallArea = rect(5, 3, 4, 1)
      buffer.setString(smallArea, "TooLongText", hAlign = hCenter)
      # Text is 11 chars, area is 4 wide -> x = 5 + (4-11)/2 = 5 + (-3) = 2
      # Characters before area.x=5 should be skipped, after area.right=9 clipped
      check buffer[5, 3].symbol == "L"
      check buffer[6, 3].symbol == "o"
      check buffer[7, 3].symbol == "n"
      check buffer[8, 3].symbol == "g"
      # Outside area should be untouched
      check buffer[4, 3].symbol == " "
      check buffer[9, 3].symbol == " "

    test "String setting with bounds checking":
      var buffer = newBuffer(5, 3)

      # String that exceeds buffer width
      buffer.setString(3, 1, "TooLong")

      # Should only set characters that fit
      check buffer[3, 1].symbol == "T"
      check buffer[4, 1].symbol == "o"
      # Position [5, 1] should be out of bounds, so original content remains

      # String starting outside buffer
      buffer.setString(10, 1, "Outside")
      # Should not crash, but won't set anything

  suite "Tab and control character handling":
    test "Tab at x=0 expands to next 8-column stop":
      var buffer = newBuffer(20, 1)
      buffer.setString(0, 0, "\tA")
      for x in 0 ..< 8:
        check buffer[x, 0].symbol == " "
      check buffer[8, 0].symbol == "A"

    test "Tab from mid-string aligns to next stop relative to startX":
      var buffer = newBuffer(20, 1)
      buffer.setString(0, 0, "abc\tX")
      # startX=0, after "abc" currentX=3 → stride=5 → fill 3..7, X at col 8
      check buffer[0, 0].symbol == "a"
      check buffer[1, 0].symbol == "b"
      check buffer[2, 0].symbol == "c"
      for x in 3 ..< 8:
        check buffer[x, 0].symbol == " "
      check buffer[8, 0].symbol == "X"

    test "Tab on a tab-stop boundary advances a full stop":
      var buffer = newBuffer(20, 1)
      buffer.setString(8, 0, "\tY")
      # currentX == startX + 8 → mod==0 → stride==8 → fill 8..15, Y at 16
      for x in 8 ..< 16:
        check buffer[x, 0].symbol == " "
      check buffer[16, 0].symbol == "Y"

    test "Consecutive tabs land on consistent stops":
      var buffer = newBuffer(30, 1)
      buffer.setString(0, 0, "a\t\tb")
      check buffer[0, 0].symbol == "a"
      # first tab fills 1..7, second tab fills 8..15, b lands at 16
      for x in 1 ..< 16:
        check buffer[x, 0].symbol == " "
      check buffer[16, 0].symbol == "b"

    test "Custom tabWidth=4 expands to 4-column stops":
      var buffer = newBuffer(20, 1)
      buffer.setString(0, 0, "a\tb", tabWidth = 4)
      check buffer[0, 0].symbol == "a"
      for x in 1 ..< 4:
        check buffer[x, 0].symbol == " "
      check buffer[4, 0].symbol == "b"

    test "Custom tabWidth=2 expands to 2-column stops":
      var buffer = newBuffer(20, 1)
      buffer.setString(0, 0, "a\tb\tc", tabWidth = 2)
      check buffer[0, 0].symbol == "a"
      check buffer[1, 0].symbol == " "
      check buffer[2, 0].symbol == "b"
      check buffer[3, 0].symbol == " "
      check buffer[4, 0].symbol == "c"

    test "tabWidth=0 falls back to single-space substitution":
      var buffer = newBuffer(20, 1)
      buffer.setString(0, 0, "a\tb", tabWidth = 0)
      check buffer[0, 0].symbol == "a"
      check buffer[1, 0].symbol == " "
      check buffer[2, 0].symbol == "b"

    test "Negative tabWidth falls back to single-space substitution":
      var buffer = newBuffer(20, 1)
      buffer.setString(0, 0, "a\tb", tabWidth = -1)
      check buffer[0, 0].symbol == "a"
      check buffer[1, 0].symbol == " "
      check buffer[2, 0].symbol == "b"

    test "Other C0 controls are always single-space, ignoring tabWidth":
      var buffer = newBuffer(10, 1)
      buffer.setString(0, 0, "a\x01b\x1Fc\x7Fd", tabWidth = 4)
      check buffer[0, 0].symbol == "a"
      check buffer[1, 0].symbol == " "
      check buffer[2, 0].symbol == "b"
      check buffer[3, 0].symbol == " "
      check buffer[4, 0].symbol == "c"
      check buffer[5, 0].symbol == " "
      check buffer[6, 0].symbol == "d"

    test "Tab expansion clips at buffer edge":
      var buffer = newBuffer(10, 1)
      buffer.setString(8, 0, "\tX")
      # tab from col 8 wants to fill 8..15 but buffer only has 8,9
      check buffer[8, 0].symbol == " "
      check buffer[9, 0].symbol == " "
      # X is dropped because we've run out of room

    test "Consecutive tabs past the right edge stop early":
      # Once currentX has run off the right edge, additional tabs must
      # not iterate their stride writing nothing — they should break
      # out of the rune loop immediately.
      var buffer = newBuffer(10, 1)
      buffer.setString(0, 0, "abcdefgh\t\t\tZ")
      for x, ch in "abcdefgh":
        check buffer[x, 0].symbol == $ch
      # First tab clips into 8..9; further tabs / 'Z' have no room.
      check buffer[8, 0].symbol == " "
      check buffer[9, 0].symbol == " "

    test "setRunes honors tabWidth parameter":
      var buffer = newBuffer(20, 1)
      let runes = "a\tb".toRunes
      buffer.setRunes(0, 0, runes, tabWidth = 4)
      check buffer[0, 0].symbol == "a"
      for x in 1 ..< 4:
        check buffer[x, 0].symbol == " "
      check buffer[4, 0].symbol == "b"

    test "setString Position overload honors tabWidth":
      var buffer = newBuffer(20, 1)
      buffer.setString(pos(0, 0), "a\tb", tabWidth = 4)
      check buffer[0, 0].symbol == "a"
      check buffer[4, 0].symbol == "b"

    test "DefaultTabWidth is 8":
      check DefaultTabWidth == 8

    test "Tab-expanded cells inherit hyperlink":
      var buffer = newBuffer(20, 1)
      buffer.setString(0, 0, "a\tb", hyperlink = "http://example.com")
      check buffer[0, 0].symbol == "a"
      check buffer[0, 0].hyperlink == "http://example.com"
      # tab expands to spaces filling cols 1..7, b at col 8
      for x in 1 ..< 8:
        check buffer[x, 0].symbol == " "
        check buffer[x, 0].hyperlink == "http://example.com"
      check buffer[8, 0].symbol == "b"
      check buffer[8, 0].hyperlink == "http://example.com"

    test "area setString: tab in centered text becomes single space":
      var buffer = newBuffer(20, 1)
      # textWidth counts tab as 1 column → 5; x = 0 + (10 - 5) div 2 = 2
      buffer.setString(rect(0, 0, 10, 1), "ab\tcd", hAlign = hCenter)
      check buffer[2, 0].symbol == "a"
      check buffer[3, 0].symbol == "b"
      check buffer[4, 0].symbol == " "
      check buffer[5, 0].symbol == "c"
      check buffer[6, 0].symbol == "d"

    test "area setString: C0 controls inside area are substituted with single space":
      var buffer = newBuffer(20, 1)
      buffer.setString(rect(0, 0, 10, 1), "abc\x01\x1Fd")
      check buffer[0, 0].symbol == "a"
      check buffer[1, 0].symbol == "b"
      check buffer[2, 0].symbol == "c"
      check buffer[3, 0].symbol == " "
      check buffer[4, 0].symbol == " "
      check buffer[5, 0].symbol == "d"

    test "area setString: C0 control before area boundary is skipped":
      var buffer = newBuffer(20, 1)
      # Pre-fill so we can detect any unwanted writes outside the area.
      buffer.setString(0, 0, "..........")
      # area at x=5, width=1; text="\x01ab" with hRight → x=3.
      # \x01 at currentX=3 (before area) → skipped; 'a' at currentX=4 (still
      # before area) → skipped; 'b' at currentX=5 → written.
      buffer.setString(rect(5, 0, 1, 1), "\x01ab", hAlign = hRight)
      check buffer[3, 0].symbol == "."
      check buffer[4, 0].symbol == "."
      check buffer[5, 0].symbol == "b"
      check buffer[6, 0].symbol == "."

  suite "setCell Operations":
    test "setCell with narrow character":
      var buffer = newBuffer(10, 5)
      buffer.setCell(3, 2, "A", 1)
      check buffer[3, 2].symbol == "A"
      check buffer[3, 2].style == defaultStyle()

    test "setCell with wide character":
      var buffer = newBuffer(10, 5)
      buffer.setCell(2, 1, "日", 2)
      check buffer[2, 1].symbol == "日"
      check buffer[3, 1].symbol == "" # shadow cell
      check buffer[3, 1].style == defaultStyle()

    test "setCell with style and hyperlink":
      var buffer = newBuffer(10, 5)
      let style = Style(
        fg: ColorValue(kind: Indexed, indexed: Color.Red),
        modifiers: {StyleModifier.Bold},
      )
      buffer.setCell(1, 0, "本", 2, style, "https://example.com")
      check buffer[1, 0].symbol == "本"
      check buffer[1, 0].style == style
      check buffer[1, 0].hyperlink == "https://example.com"
      # shadow cell inherits style and hyperlink
      check buffer[2, 0].symbol == ""
      check buffer[2, 0].style == style
      check buffer[2, 0].hyperlink == "https://example.com"

    test "setCell out of bounds is ignored":
      var buffer = newBuffer(5, 3)
      buffer.setCell(-1, 0, "X", 1)
      buffer.setCell(5, 0, "X", 1)
      buffer.setCell(0, -1, "X", 1)
      buffer.setCell(0, 3, "X", 1)
      # No crash, buffer unchanged
      check buffer[0, 0].symbol == " "

    test "setCell wide character at right edge is skipped":
      var buffer = newBuffer(5, 3)
      buffer.setCell(4, 0, "日", 2)
      # No room for shadow cell, character not written at all
      check buffer[4, 0].symbol == " "

    test "setCell with Rune":
      var buffer = newBuffer(10, 5)
      let r = "語".runeAt(0)
      buffer.setCell(0, 0, r, 2)
      check buffer[0, 0].symbol == "語"
      check buffer[1, 0].symbol == "" # shadow cell

    test "setCell with Position":
      var buffer = newBuffer(10, 5)
      buffer.setCell(pos(3, 2), "A", 1)
      check buffer[3, 2].symbol == "A"

      let r = "本".runeAt(0)
      buffer.setCell(pos(5, 1), r, 2)
      check buffer[5, 1].symbol == "本"
      check buffer[6, 1].symbol == "" # shadow cell

    test "setCell marks dirty region":
      privateAccess(Buffer)
      var buffer = newBuffer(80, 24)
      buffer.setCell(10, 5, "X", 1)
      check buffer.dirty.isDirty
      check buffer.dirty.minX == 10
      check buffer.dirty.maxX == 10
      check buffer.dirty.minY == 5

    test "setCell wide character includes shadow cell in dirty region":
      privateAccess(Buffer)
      var buffer = newBuffer(80, 24)
      buffer.setCell(10, 5, "日", 2)
      check buffer.dirty.isDirty
      check buffer.dirty.minX == 10
      check buffer.dirty.maxX == 11 # shadow cell at x+1
      check buffer.dirty.minY == 5
      check buffer.dirty.maxY == 5

    test "setCell narrow character at last column":
      var buffer = newBuffer(5, 3)
      buffer.setCell(4, 2, "Z", 1)
      check buffer[4, 2].symbol == "Z"

    test "setCell overwrites existing cell":
      var buffer = newBuffer(10, 5)
      buffer.setCell(3, 1, "A", 1)
      check buffer[3, 1].symbol == "A"
      buffer.setCell(3, 1, "B", 1)
      check buffer[3, 1].symbol == "B"

    test "setCell changes detected by diff":
      var oldBuf = newBuffer(10, 5)
      var newBuf = newBuffer(10, 5)
      newBuf.setCell(2, 1, "X", 1)
      newBuf.setCell(4, 3, "日", 2)

      let changes = oldBuf.diff(newBuf)
      var foundX = false
      var foundWide = false
      var foundShadow = false
      for change in changes:
        if change.pos == pos(2, 1) and change.cell.symbol == "X":
          foundX = true
        if change.pos == pos(4, 3) and change.cell.symbol == "日":
          foundWide = true
        if change.pos == pos(5, 3) and change.cell.symbol == "":
          foundShadow = true
      check foundX
      check foundWide
      check foundShadow

    test "setCell overwriting shadow cell clears orphaned wide-char lead":
      var buffer = newBuffer(10, 5)
      buffer.setCell(2, 0, "日", 2)
      check buffer[2, 0].symbol == "日"
      check buffer[3, 0].symbol == "" # shadow

      # Overwriting the shadow cell must crush the orphaned lead to a space
      buffer.setCell(3, 0, "A", 1)
      check buffer[3, 0].symbol == "A"
      check buffer[2, 0].symbol == " "

    test "setCell wide character on width=1 buffer is skipped":
      var buffer = newBuffer(1, 1)
      buffer.setCell(0, 0, "日", 2)
      check buffer[0, 0].symbol == " " # not written

  suite "Wide-character consistency":
    test "[]= overwriting shadow with narrow clears orphaned lead":
      var buffer = newBuffer(10, 1)
      buffer.setCell(2, 0, "日", 2)
      buffer[3, 0] = cell("A")
      check buffer[2, 0].symbol == " "
      check buffer[3, 0].symbol == "A"

    test "[]= overwriting wide lead with narrow clears orphaned shadow":
      var buffer = newBuffer(10, 1)
      buffer.setCell(2, 0, "日", 2)
      buffer[2, 0] = cell("A")
      check buffer[2, 0].symbol == "A"
      check buffer[3, 0].symbol == " "

    test "[]= overwriting wide lead with another wide leaves no orphan":
      var buffer = newBuffer(10, 1)
      buffer.setCell(2, 0, "日", 2)
      buffer.setCell(2, 0, "本", 2)
      check buffer[2, 0].symbol == "本"
      check buffer[3, 0].symbol == "" # new shadow, not orphan space

    test "[]= wide on shadow installs new wide and clears old lead":
      var buffer = newBuffer(10, 1)
      buffer.setCell(2, 0, "日", 2)
      check buffer[3, 0].symbol == ""
      # Place a wide char starting on the old shadow position
      buffer.setCell(3, 0, "英", 2)
      check buffer[2, 0].symbol == " " # old lead cleared
      check buffer[3, 0].symbol == "英"
      check buffer[4, 0].symbol == ""

    test "[]= cleanup preserves style of crushed wide lead":
      var buffer = newBuffer(10, 1)
      let style = Style(
        fg: ColorValue(kind: Indexed, indexed: Color.Red),
        modifiers: {StyleModifier.Bold},
      )
      buffer.setCell(2, 0, "日", 2, style, "https://example.com")
      # Overwrite the shadow to trigger crushing the lead
      buffer[3, 0] = cell("A")
      check buffer[2, 0].symbol == " "
      check buffer[2, 0].style == style
      # Hyperlink is dropped because the anchor char is gone
      check buffer[2, 0].hyperlink == ""

    test "[]= cleanup preserves style of crushed wide shadow":
      var buffer = newBuffer(10, 1)
      let style = Style(
        fg: ColorValue(kind: Indexed, indexed: Color.Green),
        modifiers: {StyleModifier.Underline},
      )
      buffer.setCell(2, 0, "本", 2, style, "https://example.com")
      # Overwrite the lead with a narrow char - shadow should be crushed
      buffer[2, 0] = cell("X")
      check buffer[3, 0].symbol == " "
      check buffer[3, 0].style == style
      check buffer[3, 0].hyperlink == ""

    test "setString writing consecutive wide chars stays consistent":
      var buffer = newBuffer(10, 1)
      buffer.setString(0, 0, "日本語")
      check buffer[0, 0].symbol == "日"
      check buffer[1, 0].symbol == ""
      check buffer[2, 0].symbol == "本"
      check buffer[3, 0].symbol == ""
      check buffer[4, 0].symbol == "語"
      check buffer[5, 0].symbol == ""

    test "setString overwriting wide chars with wide chars stays consistent":
      var buffer = newBuffer(10, 1)
      buffer.setString(0, 0, "日本")
      buffer.setString(1, 0, "英") # straddles shadow of 日 and lead of 本
      check buffer[0, 0].symbol == " " # old 日 lead crushed
      check buffer[1, 0].symbol == "英"
      check buffer[2, 0].symbol == ""
      check buffer[3, 0].symbol == " " # old 本 shadow crushed

    test "setString of ASCII over wide chars leaves no orphans":
      var buffer = newBuffer(10, 1)
      buffer.setString(0, 0, "日本")
      buffer.setString(1, 0, "AB")
      check buffer[0, 0].symbol == " " # old 日 lead crushed
      check buffer[1, 0].symbol == "A"
      check buffer[2, 0].symbol == "B"
      check buffer[3, 0].symbol == " " # old 本 shadow crushed

    test "fill over wide chars produces a consistent buffer":
      var buffer = newBuffer(6, 1)
      buffer.setString(0, 0, "日本")
      buffer.fill(rect(0, 0, 6, 1), cell(" "))
      for x in 0 ..< 6:
        check buffer[x, 0].symbol == " "

    test "[]= cleanup marks neighbour cells dirty":
      privateAccess(Buffer)
      var buffer = newBuffer(10, 1)
      buffer.setCell(2, 0, "日", 2)
      buffer.clearDirty()
      buffer[3, 0] = cell("A") # overwrites shadow; (2,0) must also become dirty
      check buffer.dirty.isDirty
      check buffer.dirty.minX == 2
      check buffer.dirty.maxX == 3

  suite "Buffer Resizing":
    test "Resize to larger buffer":
      var buffer = newBuffer(5, 3)

      # Set some content
      buffer[1, 1] = cell("A")
      buffer[3, 2] = cell("B")

      # Resize to larger
      let newArea = rect(0, 0, 8, 5)
      buffer.resize(newArea)

      # Check new size
      check buffer.area.width == 8
      check buffer.area.height == 5

      # Check preserved content
      check buffer[1, 1].symbol == "A"
      check buffer[3, 2].symbol == "B"

      # Check new areas are empty
      check buffer[6, 3].symbol == " "
      check buffer[7, 4].symbol == " "

    test "Resize to smaller buffer":
      var buffer = newBuffer(10, 6)

      # Set content
      buffer[2, 2] = cell("X")
      buffer[8, 5] = cell("Y") # This will be lost

      # Resize to smaller
      let newArea = rect(0, 0, 5, 4)
      buffer.resize(newArea)

      # Check new size
      check buffer.area.width == 5
      check buffer.area.height == 4

      # Content within new bounds should be preserved
      check buffer[2, 2].symbol == "X"

      # Content outside new bounds is lost, can't check it

    test "Resize with position offset":
      var buffer = newBuffer(rect(2, 3, 5, 4))
      buffer[1, 1] = cell("Z") # Relative to buffer area

      let newArea = rect(1, 2, 7, 6)
      buffer.resize(newArea)

      check buffer.area == newArea
      # Content should be preserved where areas overlap

  suite "Buffer Comparison and Diffing":
    test "Buffer equality":
      let buffer1 = newBuffer(5, 3)
      let buffer2 = newBuffer(5, 3)
      var buffer3 = newBuffer(5, 3)
      let buffer4 = newBuffer(6, 3) # Different size

      # Initially equal
      check buffer1 == buffer2
      check buffer1 == buffer3

      # Different size
      check buffer1 != buffer4

      # Different content
      buffer3[2, 1] = cell("X")
      check buffer1 != buffer3

    test "Buffer diff calculation":
      var oldBuffer = newBuffer(5, 3)
      var newBuffer = newBuffer(5, 3)

      # No changes
      let diff1 = oldBuffer.diff(newBuffer)
      check diff1.len == 0

      # Add some changes
      newBuffer[1, 1] = cell("A")
      newBuffer[3, 2] = cell("B")

      let diff2 = oldBuffer.diff(newBuffer)
      check diff2.len == 2

      # Check diff contents
      var foundA = false
      var foundB = false
      for change in diff2:
        if change.pos == Position(x: 1, y: 1) and change.cell.symbol == "A":
          foundA = true
        if change.pos == Position(x: 3, y: 2) and change.cell.symbol == "B":
          foundB = true

      check foundA
      check foundB

    test "Buffer diff with size change":
      let oldBuffer = newBuffer(3, 2)
      let newBuffer = newBuffer(4, 3)

      let diff = oldBuffer.diff(newBuffer)
      # Should return all cells of new buffer when sizes differ
      check diff.len == 12 # 4 * 3 = 12 cells

  suite "Buffer Merging":
    test "Basic buffer merge":
      var destBuffer = newBuffer(10, 6)
      var srcBuffer = newBuffer(4, 3)

      # Set up source content
      srcBuffer[0, 0] = cell("A")
      srcBuffer[1, 1] = cell("B")
      srcBuffer[2, 2] = cell("C")

      # Merge at position (2, 1)
      destBuffer.merge(srcBuffer, Position(x: 2, y: 1))

      # Check merged content
      check destBuffer[2, 1].symbol == "A" # srcBuffer[0,0] -> destBuffer[2,1]
      check destBuffer[3, 2].symbol == "B" # srcBuffer[1,1] -> destBuffer[3,2]
      check destBuffer[4, 3].symbol == "C" # srcBuffer[2,2] -> destBuffer[4,3]

    test "Partial buffer merge with clipping":
      var destBuffer = newBuffer(5, 5)
      var srcBuffer = newBuffer(4, 4)

      # Fill source buffer
      for y in 0 ..< 4:
        for x in 0 ..< 4:
          srcBuffer[x, y] = cell($((y * 4 + x) mod 10))

      # Merge near edge - should clip
      destBuffer.merge(srcBuffer, Position(x: 3, y: 3))

      # Only the overlapping portion should be copied
      check destBuffer[3, 3].symbol == "0" # srcBuffer[0,0]
      check destBuffer[4, 3].symbol == "1" # srcBuffer[1,0]
      check destBuffer[3, 4].symbol == "4" # srcBuffer[0,1]
      check destBuffer[4, 4].symbol == "5" # srcBuffer[1,1]

    test "Merge with area specification":
      var destBuffer = newBuffer(8, 6)
      var srcBuffer = newBuffer(6, 4)

      # Set up source
      for y in 0 ..< 4:
        for x in 0 ..< 6:
          srcBuffer[x, y] = cell("*")

      # Merge only a portion of source
      let srcArea = rect(1, 1, 3, 2) # 3x2 area starting at (1,1) in source
      destBuffer.merge(srcBuffer, srcArea, Position(x: 2, y: 2))

      # Check that only the specified area was merged
      check destBuffer[2, 2].symbol == "*"
      check destBuffer[3, 2].symbol == "*"
      check destBuffer[4, 2].symbol == "*"
      check destBuffer[2, 3].symbol == "*"
      check destBuffer[3, 3].symbol == "*"
      check destBuffer[4, 3].symbol == "*"

      # Areas outside the merge should be empty
      check destBuffer[1, 2].symbol == " "
      check destBuffer[5, 2].symbol == " "

  suite "Buffer Rendering Utilities":
    test "Buffer to strings conversion":
      var buffer = newBuffer(4, 3)

      # Set up a pattern
      buffer.setString(0, 0, "ABCD")
      buffer.setString(0, 1, "1234")
      buffer.setString(0, 2, "    ") # Spaces

      let strings = buffer.toStrings()

      check strings.len == 3
      check strings[0] == "ABCD"
      check strings[1] == "1234"
      check strings[2] == "    "

    test "Buffer string representation":
      let buffer = newBuffer(rect(2, 3, 4, 2))
      let str = $buffer

      # Should contain buffer info
      check str.contains("Buffer")
      check str.contains("2") # x coordinate
      check str.contains("3") # y coordinate
      check str.contains("4") # width
      check str.contains("2") # height

  suite "Unicode and Special Content":
    test "Unicode character handling":
      var buffer = newBuffer(10, 3)

      # Set Unicode characters - wide chars go through setCell so the shadow
      # cells are placed correctly; using []= directly for wide chars without
      # a shadow leaves the buffer in an inconsistent state.
      buffer[0, 0] = cell("α")
      buffer[1, 0] = cell("β")
      buffer[2, 0] = cell("γ")
      buffer.setCell(0, 1, "🚀", 2)
      buffer.setCell(2, 1, "🌟", 2)

      check buffer[0, 0].symbol == "α"
      check buffer[1, 0].symbol == "β"
      check buffer[2, 0].symbol == "γ"
      check buffer[0, 1].symbol == "🚀"
      check buffer[2, 1].symbol == "🌟"

      # Unicode width handling
      check buffer[0, 0].width() == 1 # α is narrow
      check buffer[0, 1].width() == 2 # 🚀 is wide (emoji)

    test "Empty and whitespace content":
      var buffer = newBuffer(5, 2)

      # Various empty/whitespace cells
      buffer[0, 0] = cell("")
      buffer[1, 0] = cell(" ")
      buffer[2, 0] = cell("\t")
      buffer[3, 0] = cell("   ")
      buffer[4, 0] = cell("X")

      check buffer[0, 0].isEmpty()
      check not buffer[1, 0].isEmpty() # Space is content
      check not buffer[2, 0].isEmpty() # Tab is content
      check not buffer[3, 0].isEmpty() # Multiple spaces are content
      check not buffer[4, 0].isEmpty()

  suite "Dirty Region Tracking":
    privateAccess(Buffer)

    test "New buffer has no dirty region":
      let buf = newBuffer(80, 24)
      check(not buf.dirty.isDirty)
      check(buf.getDirtyRegionSize() == 0)

    test "Single cell change marks dirty region":
      var buf = newBuffer(80, 24)
      buf[10, 5] = cell("X")

      check(buf.dirty.isDirty)
      check(buf.dirty.minX == 10)
      check(buf.dirty.maxX == 10)
      check(buf.dirty.minY == 5)
      check(buf.dirty.maxY == 5)
      check(buf.getDirtyRegionSize() == 1)

    test "setString marks dirty region":
      var buf = newBuffer(80, 24)
      buf.setString(10, 5, "Hello")

      check(buf.dirty.isDirty)
      check(buf.dirty.minX == 10)
      check(buf.dirty.maxX == 14) # "Hello" is 5 chars
      check(buf.dirty.minY == 5)
      check(buf.dirty.maxY == 5)

    test "setString with wide characters marks dirty region including shadow cells":
      var buf = newBuffer(80, 24)
      buf.setString(10, 5, "日本")
      # "日本" = 2 wide runes, each occupying 2 cells (rune + shadow)
      # Cells written: x=10 ('日'), x=11 (shadow), x=12 ('本'), x=13 (shadow)
      check(buf.dirty.isDirty)
      check(buf.dirty.minX == 10)
      check(buf.dirty.maxX == 13)
      check(buf.dirty.minY == 5)
      check(buf.dirty.maxY == 5)

    test "setRunes marks dirty region with exact range":
      var buf = newBuffer(80, 24)
      let runes = "Hello".toRunes()
      buf.setRunes(10, 5, runes)

      check(buf.dirty.isDirty)
      check(buf.dirty.minX == 10)
      check(buf.dirty.maxX == 14) # 5 ASCII runes
      check(buf.dirty.minY == 5)
      check(buf.dirty.maxY == 5)

    test "setRunes with wide characters marks dirty region including shadow cells":
      var buf = newBuffer(80, 24)
      let runes = "日本".toRunes()
      buf.setRunes(10, 5, runes)

      check(buf.dirty.isDirty)
      check(buf.dirty.minX == 10)
      check(buf.dirty.maxX == 13) # 2 wide runes + 2 shadow cells
      check(buf.dirty.minY == 5)
      check(buf.dirty.maxY == 5)

    test "multiple setString calls extend bounding box across rows":
      var buf = newBuffer(80, 24)
      buf.setString(5, 2, "abc") # x=5..7, y=2
      buf.setString(20, 8, "xyz") # x=20..22, y=8

      check(buf.dirty.isDirty)
      check(buf.dirty.minX == 5)
      check(buf.dirty.maxX == 22)
      check(buf.dirty.minY == 2)
      check(buf.dirty.maxY == 8)

    test "fill marks rectangular dirty region":
      var buf = newBuffer(80, 24)
      let fillArea = rect(10, 5, 20, 10)
      buf.fill(fillArea, cell("#"))

      check(buf.dirty.isDirty)
      check(buf.dirty.minX == 10)
      check(buf.dirty.maxX == 29) # 10 + 20 - 1
      check(buf.dirty.minY == 5)
      check(buf.dirty.maxY == 14) # 5 + 10 - 1

    test "clearDirty resets region":
      var buf = newBuffer(80, 24)
      buf[10, 5] = cell("Test")
      check(buf.dirty.isDirty)

      buf.clearDirty()
      check(not buf.dirty.isDirty)
      check(buf.getDirtyRegionSize() == 0)

    test "diff with no changes returns empty":
      var buf1 = newBuffer(50, 20)
      var buf2 = newBuffer(50, 20)

      # Fill both with same content
      buf1.setString(0, 0, "Same")
      buf2.setString(0, 0, "Same")

      # Clear dirty on buf2 to simulate no changes
      buf2.clearDirty()

      let changes = buf1.diff(buf2)
      check(changes.len == 0)

    test "diff with single change":
      var buf1 = newBuffer(50, 20)
      var buf2 = newBuffer(50, 20)

      buf1.setString(10, 5, "A")
      buf2.setString(10, 5, "B")

      let changes = buf1.diff(buf2)
      check(changes.len > 0)

    test "diff benefits from dirty region optimization":
      var oldBuf = newBuffer(300, 100)
      var newBuf = newBuffer(300, 100)

      # Fill both with same initial content
      for y in 0 ..< 100:
        oldBuf.setString(0, y, ".")
        newBuf.setString(0, y, ".")

      # Clear dirty on both to simulate previous frame
      oldBuf.clearDirty()
      newBuf.clearDirty()

      # Make small change in new buffer
      newBuf.setString(150, 50, "X")

      # Should have small dirty region
      check(newBuf.dirty.isDirty)
      check(newBuf.getDirtyRegionSize() < 100)

      let changes = oldBuf.diff(newBuf)
      check(changes.len > 0)
      check(changes.len < 50)

    test "merge marks merged region as dirty":
      var destBuf = newBuffer(80, 24)
      var srcBuf = newBuffer(20, 10)

      # Clear dest dirty region first
      destBuf.clearDirty()
      check(not destBuf.dirty.isDirty)

      # Fill source with content
      srcBuf.fill(rect(0, 0, 20, 10), cell("#"))

      # Merge into destination
      destBuf.merge(srcBuf, pos(10, 5))

      # Destination should now be dirty
      check(destBuf.dirty.isDirty)
      check(destBuf.getDirtyRegionSize() > 0)

    test "sparse vertical updates yield exact dirty span count":
      # Per-row tracking: only the touched cells count, not the bounding box.
      # The previous rectangular tracker reported (22-5+1)*(8-2+1) = 126.
      var buf = newBuffer(80, 24)
      buf.setString(5, 2, "abc")
      buf.setString(20, 8, "xyz")
      check buf.getDirtyRegionSize() == 6

    test "rows between dirty rows stay clean":
      var buf = newBuffer(80, 24)
      buf.setString(5, 2, "abc")
      buf.setString(20, 8, "xyz")
      check buf.isRowDirty(2)
      check buf.isRowDirty(8)
      for y in 3 .. 7:
        check(not buf.isRowDirty(y))
      check(not buf.isRowDirty(0))
      check(not buf.isRowDirty(23))

    test "isRowDirty rejects out-of-range rows":
      var buf = newBuffer(80, 24)
      buf.setString(5, 2, "abc")
      check(not buf.isRowDirty(-1))
      check(not buf.isRowDirty(24))
      check(not buf.isRowDirty(1000))

    test "dirty accessors return 0 on a clean buffer":
      # Documented contract: when no row is dirty, min/max coordinate
      # accessors return 0. Callers must gate on `isDirty` before
      # treating these as meaningful. Guard against silent regressions
      # if a future refactor changes the sentinel.
      let buf = newBuffer(80, 24)
      check(not buf.dirty.isDirty)
      check(buf.dirty.minX == 0)
      check(buf.dirty.maxX == 0)
      check(buf.dirty.minY == 0)
      check(buf.dirty.maxY == 0)

    test "markDirtyRect clips region extending past buffer edges":
      var buf = newBuffer(20, 10)
      buf.markDirtyRect(rect(15, 8, 100, 100))
      check buf.dirty.isDirty
      check buf.dirty.minX == 15
      check buf.dirty.maxX == 19
      check buf.dirty.minY == 8
      check buf.dirty.maxY == 9
      check(not buf.isRowDirty(7))

    test "markDirtyRect ignores rects fully outside buffer":
      var buf = newBuffer(20, 10)
      buf.markDirtyRect(rect(100, 100, 5, 5))
      check(not buf.dirty.isDirty)
      check buf.getDirtyRegionSize() == 0

    test "diff skips clean rows in sparse updates":
      var oldBuf = newBuffer(80, 24)
      var newBuf = newBuffer(80, 24)
      for y in 0 ..< 24:
        oldBuf.setString(0, y, ".")
        newBuf.setString(0, y, ".")
      oldBuf.clearDirty()
      newBuf.clearDirty()

      newBuf.setString(5, 2, "abc")
      newBuf.setString(20, 8, "xyz")

      let changes = oldBuf.diff(newBuf)
      check changes.len == 6
      for ch in changes:
        check(ch.pos.y == 2 or ch.pos.y == 8)

    test "diff falls back to full scan above the dirty-size threshold":
      # MaxDirtyRegionBeforeFullScan = 2000. A 100x50 fill marks 5000
      # dirty cells, so the diff path takes the full-scan branch. The
      # actual character change is isolated to one cell — the test
      # exercises that the fallback still produces the correct minimal
      # diff, not a redundant full-buffer dump.
      var oldBuf = newBuffer(100, 50)
      var newBuf = newBuffer(100, 50)
      oldBuf.fill(rect(0, 0, 100, 50), cell("."))
      newBuf.fill(rect(0, 0, 100, 50), cell("."))
      oldBuf.clearDirty()
      newBuf.clearDirty()

      newBuf.fill(rect(0, 0, 100, 50), cell("."))
      newBuf[50, 25] = cell("X")

      check newBuf.getDirtyRegionSize() > 2000
      let changes = oldBuf.diff(newBuf)
      check changes.len == 1
      check changes[0].pos == pos(50, 25)
      check changes[0].cell.symbol == "X"

    test "resize wipes old dirty rows and marks the new area dirty":
      var buf = newBuffer(20, 10)
      buf[1, 1] = cell("A")
      check buf.isRowDirty(1)

      buf.resize(rect(0, 0, 30, 5))
      # Every row in the new area is dirty (resize marks newArea).
      for y in 0 ..< 5:
        check buf.isRowDirty(y)
      check buf.dirty.rows.len == 5
      check buf.getDirtyRegionSize() == 30 * 5

      # Now grow taller: rows beyond the previous height should start
      # clean (no stale dirty bits leaking from the prior layout).
      buf.clearDirty()
      buf.resize(rect(0, 0, 30, 8))
      check buf.dirty.rows.len == 8
      for y in 0 ..< 8:
        check buf.isRowDirty(y)

      buf.clearDirty()
      check(not buf.dirty.isDirty)
      check buf.dirty.rows.len == 8
      for y in 0 ..< 8:
        check(not buf.isRowDirty(y))

    test "boundingBox returns single-pass envelope across dirty rows":
      var buf = newBuffer(80, 24)
      buf.setString(5, 2, "abc") # x=5..7, y=2
      buf.setString(20, 8, "xyz") # x=20..22, y=8
      buf.setString(1, 15, "longer") # x=1..6, y=15

      let bb = buf.dirty.boundingBox
      check bb.isDirty
      check bb.minX == 1
      check bb.maxX == 22
      check bb.minY == 2
      check bb.maxY == 15

    test "boundingBox on a clean buffer reports false with zero envelope":
      let buf = newBuffer(80, 24)
      let bb = buf.dirty.boundingBox
      check(not bb.isDirty)
      check bb.minX == 0
      check bb.maxX == 0
      check bb.minY == 0
      check bb.maxY == 0

  suite "Hyperlink (OSC 8) Support":
    test "Cell with hyperlink creation":
      let linkCell = cell("Click", defaultStyle(), "https://example.com")
      check linkCell.symbol == "Click"
      check linkCell.hyperlink == "https://example.com"
      check linkCell.style == defaultStyle()

    test "Cell without hyperlink has empty string":
      let normalCell = cell("Normal")
      check normalCell.hyperlink == ""

    test "Cell equality includes hyperlink":
      let cell1 = cell("A", defaultStyle(), "https://a.com")
      let cell2 = cell("A", defaultStyle(), "https://a.com")
      let cell3 = cell("A", defaultStyle(), "https://b.com")
      let cell4 = cell("A", defaultStyle(), "")

      check cell1 == cell2
      check cell1 != cell3
      check cell1 != cell4

    test "setString with hyperlink":
      var buf = newBuffer(80, 24)
      buf.setString(0, 0, "Link", defaultStyle(), "https://example.com")

      check buf[0, 0].symbol == "L"
      check buf[0, 0].hyperlink == "https://example.com"
      check buf[1, 0].symbol == "i"
      check buf[1, 0].hyperlink == "https://example.com"
      check buf[2, 0].symbol == "n"
      check buf[2, 0].hyperlink == "https://example.com"
      check buf[3, 0].symbol == "k"
      check buf[3, 0].hyperlink == "https://example.com"

    test "setString without hyperlink has empty hyperlink":
      var buf = newBuffer(80, 24)
      buf.setString(0, 0, "Plain")

      check buf[0, 0].hyperlink == ""
      check buf[1, 0].hyperlink == ""

    test "Wide characters with hyperlink":
      var buf = newBuffer(80, 24)
      buf.setString(0, 0, "日本語", defaultStyle(), "https://example.jp")

      # First character "日" (width 2)
      check buf[0, 0].symbol == "日"
      check buf[0, 0].hyperlink == "https://example.jp"
      # Shadow cell for wide character
      check buf[1, 0].symbol == ""
      check buf[1, 0].hyperlink == "https://example.jp"
      # Second character "本" (width 2)
      check buf[2, 0].symbol == "本"
      check buf[2, 0].hyperlink == "https://example.jp"
      # Shadow cell
      check buf[3, 0].symbol == ""
      check buf[3, 0].hyperlink == "https://example.jp"

    test "diff detects hyperlink changes":
      var buf1 = newBuffer(80, 24)
      var buf2 = newBuffer(80, 24)

      buf1.setString(0, 0, "Link")
      buf2.setString(0, 0, "Link", defaultStyle(), "https://new.com")

      let changes = buf1.diff(buf2)
      check changes.len > 0
      # All cells should be in changes because hyperlink changed
      check changes.len >= 4

    test "Cell string representation includes hyperlink":
      let linkCell = cell("A", defaultStyle(), "https://test.com")
      let str = $linkCell
      check "hyperlink" in str
      check "https://test.com" in str

  suite "Buffer Clone and Access":
    test "clone creates independent copy":
      var original = newBuffer(10, 5)
      original.setString(0, 0, "Hello")
      original.setString(0, 1, "World")

      let cloned = original.clone()

      # Content matches
      check cloned[0, 0].symbol == "H"
      check cloned[4, 0].symbol == "o"
      check cloned[0, 1].symbol == "W"
      check cloned.area == original.area

      # Modifying original doesn't affect clone
      original.setString(0, 0, "XXXXX")
      check cloned[0, 0].symbol == "H"

    test "clone preserves styles and hyperlinks":
      var original = newBuffer(10, 3)
      let style = Style(
        fg: ColorValue(kind: Indexed, indexed: Color.Red),
        modifiers: {StyleModifier.Bold},
      )
      original.setString(0, 0, "Link", style, "https://example.com")

      let cloned = original.clone()
      check cloned[0, 0].symbol == "L"
      check cloned[0, 0].style == style
      check cloned[0, 0].hyperlink == "https://example.com"

    test "getCell returns cell at coordinates":
      var buffer = newBuffer(10, 5)
      buffer.setString(2, 3, "Test")

      check buffer.getCell(2, 3).symbol == "T"
      check buffer.getCell(3, 3).symbol == "e"

    test "getCell out of bounds returns empty cell":
      let buffer = newBuffer(5, 5)
      let outCell = buffer.getCell(10, 10)
      check outCell.symbol == " "

    test "toStrings returns text content":
      var buffer = newBuffer(5, 2)
      buffer.setString(0, 0, "Hello")
      buffer.setString(0, 1, "World")

      let content = buffer.toStrings()
      check content.len == 2
      check content[0] == "Hello"
      check content[1] == "World"

  suite "Display Width Utilities":
    test "displayWidth handles ASCII":
      check displayWidth("") == 0
      check displayWidth("hello") == 5
      check displayWidth(" abc ") == 5

    test "displayWidth counts wide CJK characters as 2 columns":
      check displayWidth("日本語") == 6
      check displayWidth("あ") == 2
      check displayWidth("hello世界") == 9

    test "displayWidth treats emoji as wide":
      # Ambiguous-width symbol (U+263A) is treated as narrow (1 col)
      check displayWidth("☺") == 1
      # CJK Unified Ideograph is wide (2 cols)
      check displayWidth("漢") == 2
      # Emoji from the Supplementary Multilingual Plane is wide (2 cols)
      check displayWidth("😀") == 2

    test "truncateToWidth on ASCII":
      check truncateToWidth("hello", 0) == ""
      check truncateToWidth("hello", 3) == "hel"
      check truncateToWidth("hello", 10) == "hello"
      check truncateToWidth("hello", -1) == ""

    test "truncateToWidth keeps wide characters whole":
      # Each CJK char is 2 cols; with maxWidth=3 we keep one and stop
      check truncateToWidth("日本語", 3) == "日"
      check truncateToWidth("日本語", 4) == "日本"
      check truncateToWidth("日本語", 6) == "日本語"

    test "truncateToWidth drops a wide character that doesn't fit":
      # maxWidth=1 cannot fit a 2-col character; result is empty
      check truncateToWidth("日", 1) == ""
      # Narrow prefix fits; following wide character drops
      check truncateToWidth("a日", 2) == "a"
