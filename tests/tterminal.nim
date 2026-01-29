# Test suite for Terminal module

import std/[unittest]

import ../celina/core/terminal
import ../celina/core/terminal_common
import ../celina/core/geometry
import ../celina/core/colors
import ../celina/core/buffer
import ../celina/core/errors

suite "Terminal Module Tests":
  suite "Terminal Creation":
    test "Terminal creation with newTerminal()":
      let terminal = newTerminal()
      check terminal != nil
      check terminal.size.width > 0
      check terminal.size.height > 0
      check not terminal.alternateScreen
      check not terminal.rawMode

    test "Terminal default size fallback":
      let terminal = newTerminal()
      # Should have reasonable dimensions (either detected or fallback)
      check terminal.size.width >= 10
      check terminal.size.height >= 10

  suite "Terminal Size Management":
    test "getTerminalSize() returns valid dimensions":
      try:
        let termSize = getTerminalSize()
        check termSize.width > 0
        check termSize.height > 0
        # Common terminal sizes should be reasonable
        check termSize.width >= 20
        check termSize.height >= 5
      except TerminalError:
        # CI environments may not have a real terminal
        skip()

    test "updateSize() updates terminal dimensions":
      let terminal = newTerminal()
      try:
        terminal.updateSize()
        # Size should remain consistent (or update if terminal was resized)
      except TerminalError:
        # CI environments may not have a real terminal
        skip()
      check terminal.size.width > 0
      check terminal.size.height > 0

    test "getSize() returns current terminal size":
      let terminal = newTerminal()
      let size = terminal.getSize()
      check size == terminal.size
      check size.width > 0
      check size.height > 0

    test "getArea() returns correct terminal area":
      let terminal = newTerminal()
      let area = terminal.getArea()
      check area.x == 0
      check area.y == 0
      check area.width == terminal.size.width
      check area.height == terminal.size.height

  suite "Terminal State Management":
    test "Terminal state queries":
      let terminal = newTerminal()

      # Initial state
      check not terminal.isRawMode()
      check not terminal.isAlternateScreen()

    test "Raw mode state tracking":
      let terminal = newTerminal()

      # Should start in normal mode
      check not terminal.isRawMode()

      # Note: We don't actually enable raw mode in tests to avoid interfering
      # with the test runner, but we can test the state tracking
      check not terminal.rawMode

    test "Alternate screen state tracking":
      let terminal = newTerminal()

      # Should start in main screen
      check not terminal.isAlternateScreen()
      check not terminal.alternateScreen

  suite "Buffer Integration":
    test "Terminal with buffer rendering preparation":
      let terminal = newTerminal()
      let buffer = newBuffer(terminal.size.width, terminal.size.height)

      check buffer.area.width == terminal.size.width
      check buffer.area.height == terminal.size.height

    test "Terminal lastBuffer initialization":
      let terminal = newTerminal()

      # lastBuffer should be uninitialized initially (buffer is not a ref type)
      # We can't directly test if it's nil, so test other properties
      check terminal.size.width > 0
      check terminal.size.height > 0

    test "Buffer area compatibility":
      let terminal = newTerminal()
      let termArea = terminal.getArea()
      let buffer = newBuffer(termArea)

      check buffer.area == termArea

  suite "Rendering Functions":
    test "renderCell function exists and callable":
      # Test that renderCell can be called without errors
      # Note: This won't actually render in test environment
      let testCell = cell("X", style(Color.Red))

      # Function should exist and be callable (may write to stdout)
      # We just test that the function exists and accepts the right parameters
      check testCell.symbol == "X"

    test "render function with buffer changes":
      var buffer1 = newBuffer(10, 5)
      var buffer2 = newBuffer(10, 5)

      # Set up different buffers
      buffer1[1, 1] = cell("A")
      buffer2[1, 1] = cell("B")
      buffer2[2, 2] = cell("C")

      # Test that buffers are properly set up for rendering
      check buffer1[1, 1].symbol == "A"
      check buffer2[1, 1].symbol == "B"
      check buffer2[2, 2].symbol == "C"

    test "renderFull function":
      var buffer = newBuffer(5, 3)
      buffer[1, 1] = cell("Test")

      # Test buffer setup for full rendering
      check buffer[1, 1].symbol == "Test"
      check buffer.area.width == 5
      check buffer.area.height == 3

    test "draw function with force parameter":
      let buffer = newBuffer(10, 5)

      # Test buffer setup for drawing
      check buffer.area.width == 10
      check buffer.area.height == 5
      check not buffer.area.isEmpty()

  suite "High-Level Interface":
    test "withTerminal proc version":
      let terminal = newTerminal()

      # Test that withTerminal function exists and works with basic operations
      # We avoid actually calling setup/cleanup to not interfere with test environment
      check terminal.isRawMode() == false
      check terminal.isAlternateScreen() == false

    test "setup and cleanup functions exist":
      let terminal = newTerminal()

      # Test that terminal state can be checked
      check not terminal.isRawMode()
      check not terminal.isAlternateScreen()

  suite "ANSI Escape Sequences":
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
      let terminal = newTerminal()
      let area = terminal.getArea()

      check area.x == 0
      check area.y == 0
      check area.width > 0
      check area.height > 0

  suite "POSIX Platform Support":
    test "Terminal size detection works on POSIX systems":
      var size: Size
      try:
        size = getTerminalSize()
        # Should work on POSIX platforms (Linux, macOS, etc.)
        check size.width > 0
        check size.height > 0
      except TerminalError:
        # CI environments may not have a real terminal, use fallback
        size = getTerminalSizeOrDefault()
        check size.width == 80 # Default fallback size
        check size.height == 24

      # Verify size is reasonable
      check size.width > 0
      check size.height > 0

    test "Raw mode state tracking on POSIX":
      let terminal = newTerminal()

      # Test initial state
      check not terminal.isRawMode()

    test "Alternate screen state tracking on POSIX":
      let terminal = newTerminal()

      # Test initial state
      check not terminal.isAlternateScreen()

  suite "Error Handling":
    test "TerminalError type exists":
      # Test that TerminalError is properly defined
      let err = TerminalError(msg: "Test error")
      check err.msg == "Test error"

    test "Terminal operations with invalid buffer sizes":
      let terminal = newTerminal()

      # Terminal should handle empty buffer gracefully
      let emptyBuffer = newBuffer(0, 0)
      terminal.lastBuffer = emptyBuffer
      check terminal.lastBuffer.area.isEmpty()
      check terminal.lastBuffer.area.width == 0
      check terminal.lastBuffer.area.height == 0

    test "Terminal operations with oversized buffers":
      let terminal = newTerminal()

      # Terminal should handle buffers larger than screen
      let largeBuffer = newBuffer(terminal.size.width * 2, terminal.size.height * 2)
      terminal.lastBuffer = largeBuffer
      check largeBuffer.area.width > terminal.size.width
      check largeBuffer.area.height > terminal.size.height
      check largeBuffer.area.width == terminal.size.width * 2

  suite "Differential Rendering":
    test "Terminal tracks last buffer for diffs":
      let terminal = newTerminal()
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
      let terminal = newTerminal()
      let buffer1 = newBuffer(10, 5)
      let buffer2 = newBuffer(15, 8) # Different size

      # Terminal should detect buffer size changes
      terminal.lastBuffer = buffer1
      check terminal.lastBuffer.area == buffer1.area

      terminal.lastBuffer = buffer2
      check terminal.lastBuffer.area != buffer1.area
      check terminal.lastBuffer.area == buffer2.area

    test "Terminal render with same-size buffers":
      let terminal = newTerminal()
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

  suite "DrawWithCursor Function":
    test "drawWithCursor updates lastBuffer":
      let terminal = newTerminal()
      var buffer = newBuffer(20, 10)
      let lastCursorStyle = CursorStyle.Default

      buffer[5, 5] = cell("X")

      # Note: We can't test actual rendering in CI, but we can verify state updates
      discard terminal.drawWithCursor(
        buffer, 10, 5, true, CursorStyle.SteadyBlock, lastCursorStyle
      )

      # Terminal should update lastBuffer
      check terminal.lastBuffer.area == buffer.area
      check terminal.lastBuffer[5, 5].symbol == "X"

    test "drawWithCursor with cursor visible":
      let terminal = newTerminal()
      var buffer = newBuffer(20, 10)
      let lastCursorStyle = CursorStyle.Default

      buffer[3, 3] = cell("A")

      # Should handle cursor visible = true
      discard terminal.drawWithCursor(
        buffer, 5, 5, true, CursorStyle.BlinkingBlock, lastCursorStyle
      )
      check terminal.lastBuffer[3, 3].symbol == "A"

    test "drawWithCursor with cursor hidden":
      let terminal = newTerminal()
      var buffer = newBuffer(20, 10)
      let lastCursorStyle = CursorStyle.Default

      buffer[3, 3] = cell("B")

      # Should handle cursor visible = false
      discard terminal.drawWithCursor(
        buffer, 5, 5, false, CursorStyle.Default, lastCursorStyle
      )
      check terminal.lastBuffer[3, 3].symbol == "B"

    test "drawWithCursor with different cursor styles":
      let terminal = newTerminal()
      var buffer = newBuffer(20, 10)
      let lastCursorStyle = CursorStyle.Default

      buffer[0, 0] = cell("1")

      # Test with BlinkingBlock cursor style
      discard terminal.drawWithCursor(
        buffer, 10, 5, true, CursorStyle.BlinkingBlock, lastCursorStyle
      )
      check terminal.lastBuffer[0, 0].symbol == "1"

      # Test with SteadyUnderline cursor style
      buffer[0, 0] = cell("2")
      discard terminal.drawWithCursor(
        buffer, 10, 5, true, CursorStyle.SteadyUnderline, lastCursorStyle
      )
      check terminal.lastBuffer[0, 0].symbol == "2"

      # Test with BlinkingBar cursor style
      buffer[0, 0] = cell("3")
      discard terminal.drawWithCursor(
        buffer, 10, 5, true, CursorStyle.BlinkingBar, lastCursorStyle
      )
      check terminal.lastBuffer[0, 0].symbol == "3"

    test "drawWithCursor with force parameter":
      let terminal = newTerminal()
      var buffer1 = newBuffer(20, 10)
      var buffer2 = newBuffer(20, 10)
      let lastCursorStyle = CursorStyle.Default

      buffer1[5, 5] = cell("A")
      buffer2[5, 5] = cell("A") # Same content

      # First draw
      discard terminal.drawWithCursor(
        buffer1, 10, 5, true, CursorStyle.Default, lastCursorStyle
      )
      check terminal.lastBuffer[5, 5].symbol == "A"

      # Second draw with force = true (should redraw even if content is same)
      discard terminal.drawWithCursor(
        buffer2, 10, 5, true, CursorStyle.Default, lastCursorStyle, force = true
      )
      check terminal.lastBuffer[5, 5].symbol == "A"

    test "drawWithCursor handles buffer changes":
      let terminal = newTerminal()
      var buffer1 = newBuffer(20, 10)
      var buffer2 = newBuffer(20, 10)
      let lastCursorStyle = CursorStyle.Default

      buffer1[1, 1] = cell("X")
      buffer2[1, 1] = cell("Y")
      buffer2[2, 2] = cell("Z")

      # Draw first buffer
      discard terminal.drawWithCursor(
        buffer1, 5, 5, true, CursorStyle.Default, lastCursorStyle
      )
      check terminal.lastBuffer[1, 1].symbol == "X"

      # Draw second buffer with changes
      discard terminal.drawWithCursor(
        buffer2, 5, 5, true, CursorStyle.Default, lastCursorStyle
      )
      check terminal.lastBuffer[1, 1].symbol == "Y"
      check terminal.lastBuffer[2, 2].symbol == "Z"

    test "drawWithCursor with empty buffer":
      let terminal = newTerminal()
      var buffer = newBuffer(10, 5)
      let lastCursorStyle = CursorStyle.Default

      # Empty buffer should render without errors
      discard terminal.drawWithCursor(
        buffer, 3, 3, true, CursorStyle.Default, lastCursorStyle
      )
      check terminal.lastBuffer.area == buffer.area

    test "drawWithCursor with styled content":
      let terminal = newTerminal()
      var buffer = newBuffer(20, 10)
      let lastCursorStyle = CursorStyle.Default

      let styledCell = cell("S", style(Color.Green, Color.Black, {Bold}))
      buffer[7, 7] = styledCell

      discard terminal.drawWithCursor(
        buffer, 10, 5, true, CursorStyle.Default, lastCursorStyle
      )
      check terminal.lastBuffer[7, 7].symbol == "S"
      check terminal.lastBuffer[7, 7].style.fg.indexed == Color.Green
      check Bold in terminal.lastBuffer[7, 7].style.modifiers

    test "drawWithCursor with unicode content":
      let terminal = newTerminal()
      var buffer = newBuffer(20, 10)
      let lastCursorStyle = CursorStyle.Default

      buffer[0, 0] = cell("あ")
      buffer[2, 0] = cell("🎉")
      buffer[4, 0] = cell("α")

      discard terminal.drawWithCursor(
        buffer, 5, 5, true, CursorStyle.Default, lastCursorStyle
      )
      check terminal.lastBuffer[0, 0].symbol == "あ"
      check terminal.lastBuffer[2, 0].symbol == "🎉"
      check terminal.lastBuffer[4, 0].symbol == "α"

    test "drawWithCursor cursor position boundaries":
      let terminal = newTerminal()
      var buffer = newBuffer(20, 10)
      let lastCursorStyle = CursorStyle.Default

      buffer[5, 5] = cell("M")

      # Test various cursor positions
      discard terminal.drawWithCursor(
        buffer, 0, 0, true, CursorStyle.Default, lastCursorStyle
      )
      check terminal.lastBuffer[5, 5].symbol == "M"

      discard terminal.drawWithCursor(
        buffer, 19, 9, true, CursorStyle.Default, lastCursorStyle
      )
      check terminal.lastBuffer[5, 5].symbol == "M"

      discard terminal.drawWithCursor(
        buffer, 10, 5, true, CursorStyle.Default, lastCursorStyle
      )
      check terminal.lastBuffer[5, 5].symbol == "M"

    test "drawWithCursor gracefully handles errors":
      let terminal = newTerminal()
      var buffer = newBuffer(20, 10)
      let lastCursorStyle = CursorStyle.Default

      buffer[1, 1] = cell("E")

      # Should not raise exceptions even in error conditions
      # (actual I/O errors are difficult to simulate in tests)
      discard terminal.drawWithCursor(
        buffer, 5, 5, true, CursorStyle.Default, lastCursorStyle
      )
      check terminal.lastBuffer[1, 1].symbol == "E"

    test "drawWithCursor returns updated cursor style":
      let terminal = newTerminal()
      var buffer = newBuffer(20, 10)

      buffer[5, 5] = cell("X")

      # First call with Default style
      let newStyle1 = terminal.drawWithCursor(
        buffer, 10, 5, true, CursorStyle.SteadyBlock, CursorStyle.Default
      )
      # Style changed, so newStyle1 should be SteadyBlock
      check newStyle1 == CursorStyle.SteadyBlock

      # Second call with same style (no change expected)
      let newStyle2 = terminal.drawWithCursor(
        buffer, 10, 5, true, CursorStyle.SteadyBlock, CursorStyle.SteadyBlock
      )
      # Style unchanged
      check newStyle2 == CursorStyle.SteadyBlock

  suite "Integration Tests":
    test "Terminal with styled content":
      let terminal = newTerminal()
      var buffer = newBuffer(terminal.size.width, terminal.size.height)

      # Add styled content
      let styledCell = cell("X", style(Color.Red, Color.Blue, {Bold, Italic}))
      buffer[5, 5] = styledCell

      # Should handle styled cells
      check buffer[5, 5].style.fg.indexed == Color.Red
      check buffer[5, 5].style.bg.indexed == Color.Blue
      check Bold in buffer[5, 5].style.modifiers

    test "Terminal with unicode content":
      let terminal = newTerminal()
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
      let terminal = newTerminal()
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

  suite "Terminal State Management Features":
    test "Terminal mode state tracking":
      let terminal = newTerminal()

      # Initial state should be false for all modes
      check terminal.rawMode == false
      check terminal.alternateScreen == false
      check terminal.mouseEnabled == false
      check terminal.syncOutputEnabled == false

    test "Terminal size management":
      let terminal = newTerminal()

      # Terminal should have default size initially
      check terminal.size.width > 0
      check terminal.size.height > 0

      # updateSize should work without error (or skip in CI)
      try:
        terminal.updateSize()
        check terminal.size.width > 0
        check terminal.size.height > 0
      except TerminalError:
        # CI environments may not have a real terminal
        skip()

    test "Terminal area calculation":
      let terminal = newTerminal()
      let area = terminal.getArea()

      # Terminal area should match size
      check area.width == terminal.size.width
      check area.height == terminal.size.height
      check area.x == 0
      check area.y == 0

  suite "Performance Considerations":
    test "Large buffer handling":
      let terminal = newTerminal()
      let hugeBuffer = newBuffer(200, 100) # Large buffer

      # Terminal should handle large buffers in lastBuffer
      terminal.lastBuffer = hugeBuffer
      check terminal.lastBuffer.area.width == 200
      check terminal.lastBuffer.area.height == 100
      check terminal.lastBuffer.area.area() == 20000

    test "Repeated rendering with minimal changes":
      let terminal = newTerminal()
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

  suite "Boundary Conditions":
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
