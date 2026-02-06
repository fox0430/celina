# Test suite for async_buffer module

import std/[unittest, strutils, unicode]

import ../celina/async/async_backend
import ../celina/async/async_buffer
import ../celina/core/resources

# AsyncDispatch compatibility
when hasAsyncDispatch:
  template allFutures*[T](futs: seq[Future[T]]): untyped =
    all(futs)

suite "AsyncBuffer Module Tests":
  suite "AsyncBuffer Creation":
    test "AsyncBuffer creation with Rect":
      let area = rect(5, 10, 20, 15)
      let asyncBuffer = newAsyncBuffer(area)

      check asyncBuffer.getArea() == area
      # Lock state testing removed - proper locks don't expose lock state

    test "AsyncBuffer creation with dimensions":
      let asyncBuffer = newAsyncBuffer(80, 24)

      let bufferArea = asyncBuffer.getArea()
      check bufferArea.x == 0
      check bufferArea.y == 0
      check bufferArea.width == 80
      check bufferArea.height == 24

    test "AsyncBuffer clone":
      let original = newAsyncBuffer(10, 5)
      original.setString(2, 2, "test")

      let cloned = original.clone()

      check cloned.getArea() == original.getArea()
      check cloned.getCell(2, 2).symbol == "t"
      # Lock state testing removed - proper locks don't expose lock state

  suite "Thread-Safe Access":
    test "withBuffer template basic usage":
      let asyncBuffer = newAsyncBuffer(10, 5)

      asyncBuffer.withBuffer:
        buffer.setString(0, 0, "Hello")
        buffer[3, 2] = cell("X")

      check asyncBuffer.getCell(0, 0).symbol == "H"
      check asyncBuffer.getCell(3, 2).symbol == "X"

    test "getArea and getSize":
      let asyncBuffer = newAsyncBuffer(rect(2, 3, 15, 10))

      let area = asyncBuffer.getArea()
      check area.x == 2
      check area.y == 3
      check area.width == 15
      check area.height == 10

      let size = asyncBuffer.getSize()
      check size.width == 15
      check size.height == 10

    test "Lock functionality":
      let asyncBuffer = newAsyncBuffer(5, 5)

      # Lock state testing removed - proper locks don't expose lock state
      # Instead test that withBuffer works (implying lock works)
      asyncBuffer.withBuffer:
        buffer.clear()

      # Test that operation succeeded
      check asyncBuffer.getCell(0, 0).symbol == " "

  suite "Synchronous Operations":
    test "Synchronous cell access":
      let asyncBuffer = newAsyncBuffer(10, 5)
      let testCell = cell("Y", Style(fg: ColorValue(kind: Indexed, indexed: Color.Red)))

      asyncBuffer.withBuffer:
        buffer[4, 2] = testCell

      let retrievedCell = asyncBuffer.getCell(4, 2)
      check retrievedCell.symbol == "Y"
      check retrievedCell.style.fg == ColorValue(kind: Indexed, indexed: Color.Red)

      let posCell = asyncBuffer.getCell(pos(4, 2))
      check posCell == testCell

    test "Synchronous string setting":
      let asyncBuffer = newAsyncBuffer(20, 5)
      let style = Style(fg: ColorValue(kind: Indexed, indexed: Color.Green))

      asyncBuffer.setString(5, 2, "Hello", style)

      check asyncBuffer.getCell(5, 2).symbol == "H"
      check asyncBuffer.getCell(6, 2).symbol == "e"
      check asyncBuffer.getCell(7, 2).symbol == "l"
      check asyncBuffer.getCell(8, 2).symbol == "l"
      check asyncBuffer.getCell(9, 2).symbol == "o"

      for i in 0 .. 4:
        let cellStyle = asyncBuffer.getCell(5 + i, 2).style
        check cellStyle.fg == ColorValue(kind: Indexed, indexed: Color.Green)

      # Test Position version
      asyncBuffer.setString(pos(2, 3), "World")
      check asyncBuffer.getCell(2, 3).symbol == "W"
      check asyncBuffer.getCell(6, 3).symbol == "d"

    test "Synchronous string setting with hyperlink":
      let asyncBuffer = newAsyncBuffer(20, 5)
      let hyperlink = "https://example.com"

      asyncBuffer.setString(1, 1, "Click", defaultStyle(), hyperlink)

      check asyncBuffer.getCell(1, 1).symbol == "C"
      check asyncBuffer.getCell(1, 1).hyperlink == hyperlink
      check asyncBuffer.getCell(5, 1).symbol == "k"
      check asyncBuffer.getCell(5, 1).hyperlink == hyperlink

    test "Synchronous clear operation":
      let asyncBuffer = newAsyncBuffer(5, 3)

      # Set some content
      asyncBuffer.setString(0, 0, "ABCDE")
      asyncBuffer.setString(0, 1, "12345")

      # Clear with default cell
      asyncBuffer.clear()

      for y in 0 ..< 3:
        for x in 0 ..< 5:
          check asyncBuffer.getCell(x, y).symbol == " "

      # Clear with custom cell
      let fillCell =
        cell("#", Style(fg: ColorValue(kind: Indexed, indexed: Color.Blue)))
      asyncBuffer.clear(fillCell)

      for y in 0 ..< 3:
        for x in 0 ..< 5:
          let cell = asyncBuffer.getCell(x, y)
          check cell.symbol == "#"
          check cell.style.fg == ColorValue(kind: Indexed, indexed: Color.Blue)

  suite "Asynchronous Operations":
    test "Async clear operation":
      let asyncBuffer = newAsyncBuffer(5, 3)

      # Set some content first
      asyncBuffer.setString(0, 0, "test")

      let clearFuture = asyncBuffer.clearAsync(cell())
      waitFor clearFuture

      for y in 0 ..< 3:
        for x in 0 ..< 5:
          check asyncBuffer.getCell(x, y).symbol == " "

      # Test with custom cell
      let fillCell = cell("*")
      let clearFuture2 = asyncBuffer.clearAsync(fillCell)
      waitFor clearFuture2

      for y in 0 ..< 3:
        for x in 0 ..< 5:
          check asyncBuffer.getCell(x, y).symbol == "*"

    test "Async string setting":
      let asyncBuffer = newAsyncBuffer(20, 5)
      let style = Style(fg: ColorValue(kind: Indexed, indexed: Color.Yellow))

      waitFor asyncBuffer.setStringAsync(3, 1, "Async", style)

      check asyncBuffer.getCell(3, 1).symbol == "A"
      check asyncBuffer.getCell(4, 1).symbol == "s"
      check asyncBuffer.getCell(5, 1).symbol == "y"
      check asyncBuffer.getCell(6, 1).symbol == "n"
      check asyncBuffer.getCell(7, 1).symbol == "c"

      for i in 0 ..< 5:
        let cellStyle = asyncBuffer.getCell(3 + i, 1).style
        check cellStyle.fg == ColorValue(kind: Indexed, indexed: Color.Yellow)

      # Test Position version
      waitFor asyncBuffer.setStringAsync(pos(1, 2), "Test")
      check asyncBuffer.getCell(1, 2).symbol == "T"
      check asyncBuffer.getCell(4, 2).symbol == "t"

    test "Async string setting with hyperlink":
      let asyncBuffer = newAsyncBuffer(20, 5)
      let hyperlink = "https://nim-lang.org"

      waitFor asyncBuffer.setStringAsync(2, 2, "Link", defaultStyle(), hyperlink)

      check asyncBuffer.getCell(2, 2).symbol == "L"
      check asyncBuffer.getCell(2, 2).hyperlink == hyperlink
      check asyncBuffer.getCell(5, 2).symbol == "k"
      check asyncBuffer.getCell(5, 2).hyperlink == hyperlink

    test "Async cell operations":
      let asyncBuffer = newAsyncBuffer(10, 5)
      let testCell =
        cell("X", Style(fg: ColorValue(kind: Indexed, indexed: Color.Magenta)))

      waitFor asyncBuffer.setCellAsync(4, 2, testCell)
      check asyncBuffer.getCell(4, 2) == testCell

      # Position version
      let testCell2 = cell("Y")
      waitFor asyncBuffer.setCellAsync(pos(6, 3), testCell2)
      check asyncBuffer.getCell(6, 3) == testCell2

    test "Async fill operation":
      let asyncBuffer = newAsyncBuffer(10, 8)
      let fillCell = cell("*", Style(fg: ColorValue(kind: Indexed, indexed: Color.Red)))
      let fillArea = rect(2, 2, 5, 3)

      waitFor asyncBuffer.fillAsync(fillArea, fillCell)

      # Check filled area
      for y in 2 ..< 5:
        for x in 2 ..< 7:
          let cell = asyncBuffer.getCell(x, y)
          check cell.symbol == "*"
          check cell.style.fg == ColorValue(kind: Indexed, indexed: Color.Red)

      # Check areas outside fill region are untouched
      check asyncBuffer.getCell(0, 0).symbol == " "
      check asyncBuffer.getCell(9, 7).symbol == " "
      check asyncBuffer.getCell(1, 2).symbol == " "
      check asyncBuffer.getCell(7, 2).symbol == " "

    test "Async resize operation":
      let asyncBuffer = newAsyncBuffer(5, 3)

      # Set some content
      asyncBuffer.setString(1, 1, "AB")
      asyncBuffer.setString(3, 2, "C")

      # Resize to larger
      let newArea = rect(0, 0, 8, 5)
      waitFor asyncBuffer.resizeAsync(newArea)

      # Check new size
      let area = asyncBuffer.getArea()
      check area.width == 8
      check area.height == 5

      # Check preserved content
      check asyncBuffer.getCell(1, 1).symbol == "A"
      check asyncBuffer.getCell(2, 1).symbol == "B"
      check asyncBuffer.getCell(3, 2).symbol == "C"

      # Check new areas are empty
      check asyncBuffer.getCell(6, 3).symbol == " "
      check asyncBuffer.getCell(7, 4).symbol == " "

  suite "Buffer Conversion and Integration":
    test "Buffer conversion":
      let asyncBuffer = newAsyncBuffer(5, 3)
      asyncBuffer.setString(0, 0, "Hello")
      asyncBuffer.setString(0, 1, "World")

      let regularBuffer = asyncBuffer.toBuffer()

      check regularBuffer.area == asyncBuffer.getArea()
      check regularBuffer[0, 0].symbol == "H"
      check regularBuffer[4, 0].symbol == "o"
      check regularBuffer[0, 1].symbol == "W"
      check regularBuffer[4, 1].symbol == "d"

    test "Update from buffer":
      let asyncBuffer = newAsyncBuffer(5, 3)
      var regularBuffer = newBuffer(5, 3)

      regularBuffer.setString(0, 0, "Test")
      regularBuffer.setString(0, 1, "Data")

      asyncBuffer.updateFromBuffer(regularBuffer)

      check asyncBuffer.getCell(0, 0).symbol == "T"
      check asyncBuffer.getCell(3, 0).symbol == "t"
      check asyncBuffer.getCell(0, 1).symbol == "D"
      check asyncBuffer.getCell(3, 1).symbol == "a"

    test "Async merge operation":
      let destBuffer = newAsyncBuffer(10, 6)
      let srcBuffer = newAsyncBuffer(4, 3)

      # Set up source content
      srcBuffer.setString(0, 0, "ABCD")
      srcBuffer.setString(0, 1, "1234")
      srcBuffer.setString(0, 2, "WXYZ")

      waitFor destBuffer.mergeAsync(srcBuffer, pos(2, 1))

      # Check merged content
      check destBuffer.getCell(2, 1).symbol == "A"
      check destBuffer.getCell(3, 1).symbol == "B"
      check destBuffer.getCell(5, 1).symbol == "D"
      check destBuffer.getCell(2, 2).symbol == "1"
      check destBuffer.getCell(5, 2).symbol == "4"
      check destBuffer.getCell(2, 3).symbol == "W"
      check destBuffer.getCell(5, 3).symbol == "Z"

  suite "AsyncBuffer Pool":
    test "Pool creation and basic operations":
      let pool = newAsyncBufferPool(5)
      let area = rect(0, 0, 10, 5)

      let buffer1 = pool.getBuffer(area)
      check buffer1.getArea() == area

      let buffer2 = pool.getBuffer(area)
      check buffer2.getArea() == area

      # Return buffers
      pool.returnBuffer(buffer1)
      pool.returnBuffer(buffer2)

    test "Pool buffer reuse":
      let pool = newAsyncBufferPool(2)
      let area = rect(0, 0, 5, 3)

      # Get buffer and add content
      let buffer1 = pool.getBuffer(area)
      buffer1.setString(0, 0, "Test")

      # Return buffer
      pool.returnBuffer(buffer1)

      # Get buffer again - should be cleared
      let buffer2 = pool.getBuffer(area)
      check buffer2.getCell(0, 0).symbol == " " # Should be cleared

    test "Pool buffer resize":
      let pool = newAsyncBufferPool(3)
      let smallArea = rect(0, 0, 3, 2)
      let largeArea = rect(0, 0, 8, 5)

      let buffer = pool.getBuffer(smallArea)
      check buffer.getArea() == smallArea

      pool.returnBuffer(buffer)

      # Get buffer with different size
      let resizedBuffer = pool.getBuffer(largeArea)
      check resizedBuffer.getArea() == largeArea

  suite "Async-Safe Rendering Utilities":
    test "Async toStrings":
      let asyncBuffer = newAsyncBuffer(4, 3)

      asyncBuffer.setString(0, 0, "ABCD")
      asyncBuffer.setString(0, 1, "1234")
      asyncBuffer.setString(0, 2, "    ")

      let strings = waitFor asyncBuffer.toStringsAsync()

      check strings.len == 3
      check strings[0] == "ABCD"
      check strings[1] == "1234"
      check strings[2] == "    "

    test "Async diff calculation":
      let oldBuffer = newAsyncBuffer(5, 3)
      let newBuffer = newAsyncBuffer(5, 3)

      # No changes
      let diff1 = waitFor diffAsync(oldBuffer, newBuffer)
      check diff1.len == 0

      # Add changes
      newBuffer.setString(1, 1, "AB")
      newBuffer.setString(3, 2, "C")

      let diff2 = waitFor diffAsync(oldBuffer, newBuffer)
      check diff2.len == 3

      # Verify diff contents
      var foundA, foundB, foundC = false
      for change in diff2:
        case change.cell.symbol
        of "A":
          check change.pos == pos(1, 1)
          foundA = true
        of "B":
          check change.pos == pos(2, 1)
          foundB = true
        of "C":
          check change.pos == pos(3, 2)
          foundC = true
        else:
          discard

      check foundA and foundB and foundC

  suite "Utilities and Debugging":
    test "String representation":
      let asyncBuffer = newAsyncBuffer(rect(2, 3, 10, 5))
      let str = $asyncBuffer

      check str.contains("AsyncBuffer")
      check str.contains("2") # x coordinate
      check str.contains("3") # y coordinate
      check str.contains("10") # width
      check str.contains("5") # height

    test "Buffer stats":
      let asyncBuffer = newAsyncBuffer(15, 8)
      let stats = asyncBuffer.stats()

      check stats.area.width == 15
      check stats.area.height == 8
      # Lock state removed from stats - test resource ID instead
      check stats.resourceId != ResourceId(0)

  suite "Concurrent Access Simulation":
    test "Multiple async operations":
      let asyncBuffer = newAsyncBuffer(20, 10)

      # Start multiple async operations
      let futures =
        @[
          asyncBuffer.setStringAsync(0, 0, "Line1"),
          asyncBuffer.setStringAsync(0, 1, "Line2"),
          asyncBuffer.setStringAsync(0, 2, "Line3"),
          asyncBuffer.fillAsync(rect(10, 5, 5, 3), cell("*")),
        ]

      waitFor allFutures(futures)

      # Verify all operations completed
      check asyncBuffer.getCell(0, 0).symbol == "L"
      check asyncBuffer.getCell(4, 0).symbol == "1"
      check asyncBuffer.getCell(0, 1).symbol == "L"
      check asyncBuffer.getCell(4, 1).symbol == "2"
      check asyncBuffer.getCell(0, 2).symbol == "L"
      check asyncBuffer.getCell(4, 2).symbol == "3"
      check asyncBuffer.getCell(10, 5).symbol == "*"
      check asyncBuffer.getCell(14, 7).symbol == "*"

  suite "Dirty Region Tracking":
    test "New async buffer has no dirty region":
      let asyncBuf = newAsyncBufferNoRM(80, 24)
      check(not asyncBuf.isDirty())
      check(asyncBuf.getDirtyRegionSize() == 0)
      asyncBuf.destroyAsync()

    test "setString marks dirty region":
      let asyncBuf = newAsyncBufferNoRM(80, 24)
      asyncBuf.setString(10, 5, "Hello")

      check(asyncBuf.isDirty())
      check(asyncBuf.getDirtyRegionSize() > 0)
      asyncBuf.destroyAsync()

    test "clearDirty resets region":
      let asyncBuf = newAsyncBufferNoRM(80, 24)
      asyncBuf.setString(10, 5, "Test")
      check(asyncBuf.isDirty())

      asyncBuf.clearDirty()
      check(not asyncBuf.isDirty())
      check(asyncBuf.getDirtyRegionSize() == 0)
      asyncBuf.destroyAsync()

    test "clearDirtyAsync resets region":
      let asyncBuf = newAsyncBufferNoRM(80, 24)
      waitFor asyncBuf.setStringAsync(10, 5, "Test")
      check(asyncBuf.isDirty())

      waitFor asyncBuf.clearDirtyAsync()
      check(not asyncBuf.isDirty())
      check(asyncBuf.getDirtyRegionSize() == 0)
      asyncBuf.destroyAsync()

    test "fillAsync marks rectangular dirty region":
      let asyncBuf = newAsyncBufferNoRM(80, 24)
      let fillArea = rect(10, 5, 20, 10)
      waitFor asyncBuf.fillAsync(fillArea, cell("#"))

      check(asyncBuf.isDirty())
      let dirtySize = asyncBuf.getDirtyRegionSize()
      check(dirtySize >= fillArea.area)
      asyncBuf.destroyAsync()

    test "toBuffer preserves dirty state":
      let asyncBuf = newAsyncBufferNoRM(80, 24)
      asyncBuf.setString(10, 5, "Test")
      check(asyncBuf.isDirty())

      let normalBuf = asyncBuf.toBuffer()
      check(normalBuf.isDirty)
      asyncBuf.destroyAsync()

    test "diffAsync benefits from dirty region optimization":
      let oldBuf = newAsyncBufferNoRM(300, 100)
      let newBuf = newAsyncBufferNoRM(300, 100)

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
      check(newBuf.isDirty())
      check(newBuf.getDirtyRegionSize() < 100)

      let changes = waitFor diffAsync(oldBuf, newBuf)
      check(changes.len > 0)
      check(changes.len < 50)

      oldBuf.destroyAsync()
      newBuf.destroyAsync()

  suite "Runes Operations":
    test "Synchronous setRunes with coordinates":
      let asyncBuffer = newAsyncBuffer(20, 5)
      let runes = "Hello".toRunes()
      let style = Style(fg: ColorValue(kind: Indexed, indexed: Color.Cyan))

      asyncBuffer.setRunes(3, 1, runes, style)

      check asyncBuffer.getCell(3, 1).symbol == "H"
      check asyncBuffer.getCell(4, 1).symbol == "e"
      check asyncBuffer.getCell(5, 1).symbol == "l"
      check asyncBuffer.getCell(6, 1).symbol == "l"
      check asyncBuffer.getCell(7, 1).symbol == "o"

      for i in 0 ..< 5:
        let cellStyle = asyncBuffer.getCell(3 + i, 1).style
        check cellStyle.fg == ColorValue(kind: Indexed, indexed: Color.Cyan)

    test "Synchronous setRunes with Position":
      let asyncBuffer = newAsyncBuffer(20, 5)
      let runes = "World".toRunes()

      asyncBuffer.setRunes(pos(2, 2), runes)

      check asyncBuffer.getCell(2, 2).symbol == "W"
      check asyncBuffer.getCell(3, 2).symbol == "o"
      check asyncBuffer.getCell(4, 2).symbol == "r"
      check asyncBuffer.getCell(5, 2).symbol == "l"
      check asyncBuffer.getCell(6, 2).symbol == "d"

    test "Synchronous setRunes with hyperlink":
      let asyncBuffer = newAsyncBuffer(20, 5)
      let runes = "Link".toRunes()
      let hyperlink = "https://example.com"

      asyncBuffer.setRunes(1, 1, runes, defaultStyle(), hyperlink)

      check asyncBuffer.getCell(1, 1).symbol == "L"
      check asyncBuffer.getCell(1, 1).hyperlink == hyperlink
      check asyncBuffer.getCell(4, 1).symbol == "k"
      check asyncBuffer.getCell(4, 1).hyperlink == hyperlink

    test "Async setRunes with coordinates":
      let asyncBuffer = newAsyncBuffer(20, 5)
      let runes = "Async".toRunes()
      let style = Style(fg: ColorValue(kind: Indexed, indexed: Color.Yellow))

      waitFor asyncBuffer.setRunesAsync(2, 3, runes, style)

      check asyncBuffer.getCell(2, 3).symbol == "A"
      check asyncBuffer.getCell(3, 3).symbol == "s"
      check asyncBuffer.getCell(4, 3).symbol == "y"
      check asyncBuffer.getCell(5, 3).symbol == "n"
      check asyncBuffer.getCell(6, 3).symbol == "c"

      for i in 0 ..< 5:
        let cellStyle = asyncBuffer.getCell(2 + i, 3).style
        check cellStyle.fg == ColorValue(kind: Indexed, indexed: Color.Yellow)

    test "Async setRunes with Position":
      let asyncBuffer = newAsyncBuffer(20, 5)
      let runes = "Test".toRunes()

      waitFor asyncBuffer.setRunesAsync(pos(5, 2), runes)

      check asyncBuffer.getCell(5, 2).symbol == "T"
      check asyncBuffer.getCell(6, 2).symbol == "e"
      check asyncBuffer.getCell(7, 2).symbol == "s"
      check asyncBuffer.getCell(8, 2).symbol == "t"

    test "setRunes with wide characters (CJK)":
      let asyncBuffer = newAsyncBuffer(20, 5)
      let runes = "日本".toRunes()

      asyncBuffer.setRunes(1, 1, runes)

      # Wide characters take 2 cells each
      check asyncBuffer.getCell(1, 1).symbol == "日"
      # Cell 2 is empty (continuation of wide char)
      check asyncBuffer.getCell(2, 1).symbol == ""
      check asyncBuffer.getCell(3, 1).symbol == "本"
      # Cell 4 is empty (continuation of wide char)
      check asyncBuffer.getCell(4, 1).symbol == ""

    test "Async setRunes with wide characters":
      let asyncBuffer = newAsyncBuffer(20, 5)
      let runes = "中文".toRunes()

      waitFor asyncBuffer.setRunesAsync(0, 0, runes)

      check asyncBuffer.getCell(0, 0).symbol == "中"
      check asyncBuffer.getCell(1, 0).symbol == "" # Continuation
      check asyncBuffer.getCell(2, 0).symbol == "文"
      check asyncBuffer.getCell(3, 0).symbol == "" # Continuation

    test "setRunes marks dirty region":
      let asyncBuf = newAsyncBufferNoRM(80, 24)
      let runes = "Test".toRunes()

      asyncBuf.setRunes(10, 5, runes)

      check asyncBuf.isDirty()
      check asyncBuf.getDirtyRegionSize() > 0
      asyncBuf.destroyAsync()
