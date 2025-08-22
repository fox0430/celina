# Tests for async_terminal module

import std/unittest

import pkg/chronos

import ../celina/async/async_buffer
import ../celina/core/[geometry, colors, buffer, errors]

import ../celina/async/async_terminal {.all.}

# Test helpers
proc createTestBuffer(width, height: int, fillChar: string = " "): Buffer =
  result = newBuffer(rect(0, 0, width, height))
  for y in 0 ..< height:
    for x in 0 ..< width:
      result[x, y] = cell(fillChar, defaultStyle())

# Helper to create terminal without fd registration for testing
proc createTestTerminal(): AsyncTerminal =
  result = AsyncTerminal(
    size: size(80, 24), alternateScreen: false, rawMode: false, mouseEnabled: false
  )
  # Initialize lastBuffer without fd registration
  result.lastBuffer = newBuffer(rect(0, 0, result.size.width, result.size.height))

suite "AsyncTerminal Basic Operations":
  test "newAsyncTerminal creates terminal with default state":
    # Test the structure without fd registration
    let terminal = createTestTerminal()
    check:
      terminal.size.width == 80 # Test terminal default
      terminal.size.height == 24 # Test terminal default
      not terminal.alternateScreen
      not terminal.rawMode
      not terminal.mouseEnabled
      terminal.lastBuffer.area.width > 0

  test "updateSize gets terminal dimensions":
    let terminal = createTestTerminal()
    try:
      terminal.updateSize()
      # Size should change to actual terminal size
      check terminal.size.width > 0
      check terminal.size.height > 0
    except TerminalError:
      # CI environments may not have a real terminal
      skip()

  test "getTerminalSizeAsync returns valid size":
    let size = getTerminalSizeAsync()
    check:
      size.width > 0
      size.height > 0
      # Should be at least minimum reasonable terminal size (or fallback)
      size.width >= 10
      size.height >= 5

suite "AsyncTerminal State Management":
  test "alternate screen state tracking":
    let terminal = createTestTerminal()
    check not terminal.isAlternateScreen()

    terminal.enableAlternateScreen()
    check terminal.isAlternateScreen()

    terminal.disableAlternateScreen()
    check not terminal.isAlternateScreen()

  test "mouse enabled state tracking":
    let terminal = createTestTerminal()
    check not terminal.isMouseEnabled()

    terminal.enableMouse()
    check terminal.isMouseEnabled()

    terminal.disableMouse()
    check not terminal.isMouseEnabled()

  test "getSize and getArea consistency":
    let terminal = createTestTerminal()
    let size = terminal.getSize()
    let area = terminal.getArea()

    check:
      area.x == 0
      area.y == 0
      area.width == size.width
      area.height == size.height

# Terminal display affecting tests removed to prevent interference

suite "AsyncTerminal Rendering":
  test "buffer operations without async terminal":
    # Test basic buffer operations without real terminal
    let terminal = createTestTerminal()
    let buffer = createTestBuffer(10, 5, "T")

    # Test buffer state management
    terminal.lastBuffer = buffer
    check terminal.lastBuffer.area == buffer.area

    # Test with AsyncBuffer
    let asyncBuffer = newAsyncBuffer(rect(0, 0, 8, 4))
    try:
      waitFor(asyncBuffer.setCellAsync(0, 0, cell("A")))
      waitFor(asyncBuffer.setCellAsync(1, 1, cell("B")))

      # Verify cells were set
      check asyncBuffer.getCell(0, 0).symbol == "A"
      check asyncBuffer.getCell(1, 1).symbol == "B"
    except CatchableError:
      check false

suite "AsyncTerminal Buffer Management":
  test "buffer state management":
    let terminal = createTestTerminal()

    # Test basic buffer management
    let buffer1 = createTestBuffer(5, 3, "1")
    terminal.lastBuffer = buffer1
    check terminal.lastBuffer.area == buffer1.area

    # Test buffer modification
    var buffer2 = createTestBuffer(5, 3, "1")
    buffer2[0, 0] = cell("2", defaultStyle())
    buffer2[2, 1] = cell("3", defaultStyle())

    terminal.lastBuffer = buffer2
    check terminal.lastBuffer[0, 0].symbol == "2"
    check terminal.lastBuffer[2, 1].symbol == "3"

  test "buffer area management":
    let terminal = createTestTerminal()

    # Test size change handling
    let buffer1 = createTestBuffer(5, 3)
    terminal.lastBuffer = buffer1

    let buffer2 = createTestBuffer(7, 4)
    terminal.lastBuffer = buffer2
    check terminal.lastBuffer.area == buffer2.area

suite "AsyncTerminal Basic Error Handling":
  test "terminal creation":
    let terminal = createTestTerminal()
    check terminal != nil
    check terminal.size.width == 80
    check terminal.size.height == 24

  test "AsyncTerminalError type exists":
    # Test that AsyncTerminalError is properly defined
    let err = AsyncTerminalError(msg: "Test error")
    check err.msg == "Test error"

  test "Terminal operations with invalid buffer sizes":
    let terminal = createTestTerminal()

    # Terminal should handle empty buffer gracefully
    let emptyBuffer = newBuffer(0, 0)
    terminal.lastBuffer = emptyBuffer
    check terminal.lastBuffer.area.isEmpty()
    check terminal.lastBuffer.area.width == 0
    check terminal.lastBuffer.area.height == 0

  test "Terminal operations with oversized buffers":
    let terminal = createTestTerminal()

    # Terminal should handle buffers larger than screen
    let largeBuffer = newBuffer(terminal.size.width * 2, terminal.size.height * 2)
    terminal.lastBuffer = largeBuffer
    check largeBuffer.area.width > terminal.size.width
    check largeBuffer.area.height > terminal.size.height
    check largeBuffer.area.width == terminal.size.width * 2

suite "AsyncTerminal ANSI Escape Sequences":
  test "Position creation for cursor control":
    # Test position creation which would be used for cursor control
    let pos1 = pos(10, 20)
    let pos2 = pos(5, 15)

    check pos1.x == 10
    check pos1.y == 20
    check pos2.x == 5
    check pos2.y == 15

  test "Terminal coordinates":
    # Test coordinate handling
    let terminal = createTestTerminal()
    let area = terminal.getArea()

    check area.x == 0
    check area.y == 0
    check area.width > 0
    check area.height > 0

suite "AsyncTerminal POSIX Platform Support":
  test "Terminal size detection works on POSIX systems":
    let size = getTerminalSizeAsync()

    # Should work on POSIX platforms (Linux, macOS, etc.)
    # In CI environments, this might be fallback size
    check size.width > 0
    check size.height > 0
    check size.width >= 10 # Reasonable minimum
    check size.height >= 5

    # Common fallback values
    if size.width == 80 and size.height == 24:
      # Likely using fallback values, which is acceptable
      discard
    else:
      # Using actual terminal dimensions
      check size.width >= 20
      check size.height >= 5

  test "Raw mode state tracking on POSIX":
    let terminal = createTestTerminal()

    # Test initial state
    check not terminal.isRawMode()

  test "Alternate screen state tracking on POSIX":
    let terminal = createTestTerminal()

    # Test initial state
    check not terminal.isAlternateScreen()

suite "AsyncTerminal Differential Rendering":
  test "Terminal tracks last buffer for diffs":
    let terminal = createTestTerminal()
    let buffer1 = newBuffer(10, 5)
    let buffer2 = newBuffer(10, 5)

    # Terminal should track last buffer for differential rendering
    terminal.lastBuffer = buffer1
    check terminal.lastBuffer.area.width == 10
    check terminal.lastBuffer.area.height == 5

    # Change to different buffer
    terminal.lastBuffer = buffer2
    check terminal.lastBuffer.area == buffer2.area

  test "Buffer size changes trigger full redraw":
    let terminal = createTestTerminal()
    let buffer1 = newBuffer(10, 5)
    let buffer2 = newBuffer(15, 8) # Different size

    # Terminal should detect buffer size changes
    terminal.lastBuffer = buffer1
    check terminal.lastBuffer.area == buffer1.area

    terminal.lastBuffer = buffer2
    check terminal.lastBuffer.area != buffer1.area
    check terminal.lastBuffer.area == buffer2.area

  test "Terminal render with same-size buffers":
    let terminal = createTestTerminal()
    var buffer1 = newBuffer(10, 5)
    var buffer2 = newBuffer(10, 5)

    # Terminal should handle same-size buffer transitions
    terminal.lastBuffer = buffer1
    check terminal.lastBuffer.area == buffer1.area

    terminal.lastBuffer = buffer2
    check terminal.lastBuffer.area == buffer2.area
    check terminal.lastBuffer.area == buffer1.area # Same size

    # Same size, different content
    buffer1[1, 1] = cell("A")
    buffer2[1, 1] = cell("B")
    buffer2[2, 2] = cell("C")

    # Should detect differences
    let changes = buffer1.diff(buffer2)
    check changes.len > 0

suite "AsyncTerminal Integration Tests":
  test "Terminal with styled content":
    let terminal = createTestTerminal()
    var buffer = newBuffer(terminal.size.width, terminal.size.height)

    # Add styled content
    let styledCell = cell("X", style(Color.Red, Color.Blue, {Bold, Italic}))
    buffer[5, 5] = styledCell

    # Should handle styled cells
    check buffer[5, 5].style.fg.indexed == Color.Red
    check buffer[5, 5].style.bg.indexed == Color.Blue
    check Bold in buffer[5, 5].style.modifiers

  test "Terminal with unicode content":
    let terminal = createTestTerminal()
    var buffer = newBuffer(20, 10)

    # Add unicode characters
    buffer[0, 0] = cell("α")
    buffer[1, 0] = cell("β")
    buffer[2, 0] = cell("🚀")
    buffer[3, 0] = cell("🌟")

    # Terminal should handle unicode content in lastBuffer
    terminal.lastBuffer = buffer
    check terminal.lastBuffer[0, 0].symbol == "α"
    check terminal.lastBuffer[2, 0].symbol == "🚀"

  test "Terminal buffer operations":
    let terminal = createTestTerminal()
    var buffer = newBuffer(terminal.getArea())

    # Fill buffer with pattern
    for y in 0 ..< buffer.area.height:
      for x in 0 ..< buffer.area.width:
        if (x + y) mod 2 == 0:
          buffer[x, y] = cell("#")
        else:
          buffer[x, y] = cell(".")

    # Terminal should work with its own area-sized buffer
    terminal.lastBuffer = buffer
    check terminal.lastBuffer.area == terminal.getArea()
    check terminal.lastBuffer[0, 0].symbol == "#"
    check terminal.lastBuffer[1, 0].symbol == "."
    check terminal.lastBuffer[0, 1].symbol == "."
    check terminal.lastBuffer[1, 1].symbol == "#"

suite "AsyncTerminal Performance Considerations":
  test "Large buffer handling":
    let terminal = createTestTerminal()
    let hugeBuffer = newBuffer(200, 100) # Large buffer

    # Terminal should handle large buffers in lastBuffer
    terminal.lastBuffer = hugeBuffer
    check terminal.lastBuffer.area.width == 200
    check terminal.lastBuffer.area.height == 100
    check terminal.lastBuffer.area.area() == 20000

  test "Repeated rendering with minimal changes":
    let terminal = createTestTerminal()
    var buffer1 = newBuffer(50, 20)
    var buffer2 = newBuffer(50, 20)

    # Terminal should track buffer changes for efficient rendering
    terminal.lastBuffer = buffer1
    let originalArea = terminal.lastBuffer.area

    terminal.lastBuffer = buffer2
    check terminal.lastBuffer.area == originalArea # Same dimensions

    # Identical buffers should have no differences
    let noDiff = buffer1.diff(buffer2)
    check noDiff.len == 0

    # Small change should have minimal diff
    buffer2[10, 10] = cell("X")
    let smallDiff = buffer1.diff(buffer2)
    check smallDiff.len == 1

  test "Buffer memory efficiency":
    # Test that buffers don't use excessive memory
    let smallBuffer = newBuffer(1, 1)
    let mediumBuffer = newBuffer(80, 24)

    # Should create buffers efficiently
    check smallBuffer.area.area() == 1
    check mediumBuffer.area.area() == 1920

suite "AsyncTerminal Boundary Conditions":
  test "Minimum size terminal":
    # Test with very small terminal size
    var minBuffer = newBuffer(1, 1)
    check minBuffer.area.width == 1
    check minBuffer.area.height == 1

    minBuffer[0, 0] = cell("X")
    check minBuffer[0, 0].symbol == "X"

  test "Terminal position edge cases":
    # Test position values for cursor positioning
    let pos1 = pos(0, 0) # Top-left
    let pos2 = pos(-1, -1) # Negative
    let pos3 = pos(1000, 1000) # Large values

    check pos1.x == 0 and pos1.y == 0
    check pos2.x == -1 and pos2.y == -1
    check pos3.x == 1000 and pos3.y == 1000

  test "Buffer overflow protection":
    var buffer = newBuffer(5, 3)

    # Accessing out-of-bounds should be safe
    let outOfBounds = buffer[100, 100]
    check outOfBounds.symbol == " " # Should return empty cell
