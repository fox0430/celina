# Tests for async_terminal module

import std/unittest

import pkg/chronos

import ../celina/async/async_buffer
import ../celina/core/[geometry, colors, buffer]

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
    terminal.updateSize()
    # Size should change to actual terminal size
    check terminal.size.width > 0
    check terminal.size.height > 0

  test "getTerminalSizeAsync returns valid size":
    let size = getTerminalSizeAsync()
    check:
      size.width > 0
      size.height > 0
      # Should be at least minimum reasonable terminal size
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
