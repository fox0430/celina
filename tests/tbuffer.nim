# Test suite for Buffer module

import std/[unittest, strutils]

import ../src/core/buffer
import ../src/core/geometry
import ../src/core/colors

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

      # Set Unicode characters
      buffer[0, 0] = cell("α")
      buffer[1, 0] = cell("β")
      buffer[2, 0] = cell("γ")
      buffer[0, 1] = cell("🚀")
      buffer[1, 1] = cell("🌟")

      check buffer[0, 0].symbol == "α"
      check buffer[1, 0].symbol == "β"
      check buffer[2, 0].symbol == "γ"
      check buffer[0, 1].symbol == "🚀"
      check buffer[1, 1].symbol == "🌟"

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
