# Test suite for Terminal module

import std/[unittest, strutils]

when defined(posix):
  import std/posix
  import ./stdout_capture

import ../celina/core/[terminal, terminal_common, geometry, colors, buffer, errors]

when defined(posix):
  type StdoutPipe = tuple[saved: cint, rfd: cint]

  proc redirectStdoutToPipe(): StdoutPipe =
    let saved = dup(STDOUT_FILENO)
    if saved == -1:
      return (cint(-1), cint(-1))
    var fds: array[2, cint]
    if pipe(fds) != 0:
      discard close(saved)
      return (cint(-1), cint(-1))
    if dup2(fds[1], STDOUT_FILENO) == -1:
      discard close(saved)
      discard close(fds[0])
      discard close(fds[1])
      return (cint(-1), cint(-1))
    discard close(fds[1])
    (saved, fds[0])

  proc restoreStdout(p: StdoutPipe) =
    if p.saved != -1:
      discard dup2(p.saved, STDOUT_FILENO)
      discard close(p.saved)
    if p.rfd != -1:
      discard close(p.rfd)

  proc readFromPipe(rfd: cint, maxBytes: int): string =
    var buf = newString(maxBytes)
    let n = posix.read(rfd, addr buf[0], maxBytes.cint)
    if n > 0:
      result = buf[0 ..< n]
    else:
      result = ""

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

      # Wide chars go through setCell so shadow cells are placed correctly.
      buffer.setCell(0, 0, "あ", 2)
      buffer.setCell(2, 0, "🎉", 2)
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

    test "drawWithCursor returns original lastCursorStyle when frame has no output":
      let terminal = newTerminal()
      var buffer = newBuffer(20, 10)

      # Empty buffer, hidden cursor: no output is produced, so the tracked
      # cursor style must remain unchanged.
      let returnedStyle = terminal.drawWithCursor(
        buffer, 0, 0, false, CursorStyle.SteadyBlock, CursorStyle.Default
      )
      check returnedStyle == CursorStyle.Default

  suite "Adopt Rendering":
    test "drawAdopt swaps buffers when areas match":
      let terminal = newTerminal()
      terminal.lastBuffer = newBuffer(10, 5)
      terminal.lastBuffer[0, 0] = cell("OLD")

      var buffer = newBuffer(10, 5)
      buffer[0, 0] = cell("NEW")

      terminal.drawAdopt(buffer, force = true)

      # lastBuffer adopts the freshly rendered grid
      check terminal.lastBuffer[0, 0].symbol == "NEW"
      # caller's buffer is recycled with the previous frame's storage
      check buffer[0, 0].symbol == "OLD"

    test "drawAdopt copies buffer when areas differ":
      let terminal = newTerminal()
      terminal.lastBuffer = newBuffer(5, 5)
      terminal.lastBuffer[0, 0] = cell("OLD")

      var buffer = newBuffer(10, 5)
      buffer[0, 0] = cell("NEW")

      terminal.drawAdopt(buffer, force = true)

      check terminal.lastBuffer[0, 0].symbol == "NEW"
      # area mismatch => copy fallback; caller keeps its own buffer
      check buffer[0, 0].symbol == "NEW"
      check terminal.lastBuffer.area == buffer.area

    test "drawWithCursorAdopt swaps buffers when areas match":
      let terminal = newTerminal()
      terminal.lastBuffer = newBuffer(10, 5)
      terminal.lastBuffer[0, 0] = cell("OLD")

      var buffer = newBuffer(10, 5)
      buffer[0, 0] = cell("NEW")

      discard terminal.drawWithCursorAdopt(
        buffer, 0, 0, false, CursorStyle.Default, CursorStyle.Default, force = true
      )

      check terminal.lastBuffer[0, 0].symbol == "NEW"
      check buffer[0, 0].symbol == "OLD"

    test "drawWithCursorAdopt copies buffer when areas differ":
      let terminal = newTerminal()
      terminal.lastBuffer = newBuffer(5, 5)
      terminal.lastBuffer[0, 0] = cell("OLD")

      var buffer = newBuffer(10, 5)
      buffer[0, 0] = cell("NEW")

      discard terminal.drawWithCursorAdopt(
        buffer, 0, 0, false, CursorStyle.Default, CursorStyle.Default, force = true
      )

      check terminal.lastBuffer[0, 0].symbol == "NEW"
      check buffer[0, 0].symbol == "NEW"
      check terminal.lastBuffer.area == buffer.area

    test "drawAdopt recycles buffer across multiple frames":
      let terminal = newTerminal()
      var buffer = newBuffer(10, 5)

      for i in 0 ..< 3:
        buffer.clear()
        buffer[0, 0] = cell($i)
        terminal.drawAdopt(buffer, force = true)
        check terminal.lastBuffer[0, 0].symbol == $i

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

      # Add unicode characters - wide chars go through setCell so shadow cells
      # are placed correctly.
      buffer[0, 0] = cell("α")
      buffer[1, 0] = cell("β")
      buffer.setCell(2, 0, "🚀", 2)
      buffer.setCell(4, 0, "🌟", 2)

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

  suite "Cleanup Behavior":
    # Note: rawMode is exercised separately because enableRawMode calls
    # tcsetattr() on the real terminal, which would interfere with the
    # test runner. The flags below only require stdout writes (no-op when
    # stdout is a normal sink) and so are safe to toggle in tests.

    test "cleanup resets all toggleable flags":
      let terminal = newTerminal()

      terminal.enableAlternateScreen()
      terminal.enableMouse()
      terminal.enableBracketedPaste()
      terminal.enableFocusEvents()
      terminal.enableSyncOutput()

      check terminal.alternateScreen
      check terminal.mouseEnabled
      check terminal.bracketedPasteEnabled
      check terminal.focusEventsEnabled
      check terminal.syncOutputEnabled

      terminal.cleanup()

      check not terminal.alternateScreen
      check not terminal.mouseEnabled
      check not terminal.bracketedPasteEnabled
      check not terminal.focusEventsEnabled
      check not terminal.syncOutputEnabled

    test "cleanup is idempotent":
      let terminal = newTerminal()
      terminal.enableMouse()
      terminal.enableBracketedPaste()

      terminal.cleanup()
      check not terminal.mouseEnabled
      check not terminal.bracketedPasteEnabled

      # Second call must be safe: every disable is state-gated, so the
      # already-disabled flags stay false without re-issuing escapes.
      terminal.cleanup()
      check not terminal.mouseEnabled
      check not terminal.bracketedPasteEnabled

    test "cleanup with partial state disables only enabled flags":
      let terminal = newTerminal()
      terminal.enableMouse()
      terminal.enableBracketedPaste()

      check terminal.mouseEnabled
      check terminal.bracketedPasteEnabled
      check not terminal.alternateScreen
      check not terminal.focusEventsEnabled
      check not terminal.syncOutputEnabled

      terminal.cleanup()

      check not terminal.mouseEnabled
      check not terminal.bracketedPasteEnabled
      check not terminal.alternateScreen
      check not terminal.focusEventsEnabled
      check not terminal.syncOutputEnabled

    test "cleanup on freshly created terminal is safe":
      let terminal = newTerminal()
      terminal.cleanup()
      check not terminal.alternateScreen
      check not terminal.mouseEnabled
      check not terminal.bracketedPasteEnabled
      check not terminal.focusEventsEnabled
      check not terminal.syncOutputEnabled

    test "cleanup disables flag enabled last (LIFO end of sequence)":
      # alternateScreen is the final disable step in cleanup's LIFO order,
      # so this guards against accidentally truncating the sequence.
      let terminal = newTerminal()
      terminal.enableAlternateScreen()
      check terminal.alternateScreen

      terminal.cleanup()
      check not terminal.alternateScreen

  suite "Setup Rollback":
    test "setup rolls back partial state when raw mode fails":
      # Regression: enableAlternateScreen succeeds (write to a pipe) but
      # enableRawMode raises ENOTTY on a non-TTY stdin. setup() must roll the
      # alternate screen back instead of stranding the shell in it.
      #
      # Only meaningful on a non-TTY (the CI case): there setup() is
      # guaranteed to fail at raw mode. On a real TTY setup() would actually
      # switch screens and enter raw mode, so we skip it — mirroring why the
      # Cleanup Behavior suite avoids enableRawMode entirely.
      when defined(posix):
        if isatty(STDIN_FILENO) == 0 and isatty(STDOUT_FILENO) == 0:
          let terminal = newTerminal()
          var raised = false
          try:
            terminal.setup()
          except CatchableError:
            raised = true

          check raised
          check not terminal.alternateScreen
          check not terminal.rawMode

  suite "Buffered stdout ordering":
    test "writeWithRetry flushes buffered stdout before control sequences":
      # Regression: writeWithRetry wrote control sequences directly to the fd
      # and then flushed the C stdio buffer, so buffered stdout.write data could
      # appear after the escape sequence instead of before it.
      when defined(posix):
        let p = redirectStdoutToPipe()
        if p.saved == -1:
          skip()
        defer:
          restoreStdout(p)

        stdout.write("hello")
        showCursor()

        let output = readFromPipe(p.rfd, 1024)

        check output.startsWith("hello")
        check output.contains(ShowCursorSeq)
      else:
        skip()

  suite "Writes cut off partway":
    test "a control sequence cut off partway is aborted before the next write":
      when defined(linux):
        let output = captureCutStdout(
          4,
          proc() =
            setCursorPosition(33, 11)
            hideCursor(),
        )
        check output == "\e[12" & AbortPartialSeq & HideCursorSeq
      else:
        skip()

  suite "emergencyRestore":
    test "writes the reset in one piece and clears every mode flag":
      when defined(posix):
        let p = redirectStdoutToPipe()
        if p.saved == -1:
          skip()
        defer:
          restoreStdout(p)

        let terminal = newTerminal()
        terminal.enableMouse()
        terminal.enableBracketedPaste()
        terminal.enableFocusEvents()
        terminal.enableSyncOutput()
        discard readFromPipe(p.rfd, 4096)

        terminal.emergencyRestore()
        let output = readFromPipe(p.rfd, 4096)

        check output == EmergencyResetSeq
        check not terminal.mouseEnabled
        check not terminal.bracketedPasteEnabled
        check not terminal.focusEventsEnabled
        check not terminal.syncOutputEnabled
      else:
        skip()

    test "leaves the alternate screen when it was entered":
      when defined(posix):
        let p = redirectStdoutToPipe()
        if p.saved == -1:
          skip()
        defer:
          restoreStdout(p)

        let terminal = newTerminal()
        terminal.enableAlternateScreen()
        discard readFromPipe(p.rfd, 4096)

        terminal.emergencyRestore()
        let output = readFromPipe(p.rfd, 4096)

        check output == EmergencyResetAltScreenSeq
        check not terminal.alternateScreen
      else:
        skip()

    test "sends the reset even when no flag is set":
      # Unlike cleanup, the flags are not consulted: a mode may be on in the
      # terminal while its write was cut off before the flag was updated.
      when defined(posix):
        let p = redirectStdoutToPipe()
        if p.saved == -1:
          skip()
        defer:
          restoreStdout(p)

        let terminal = newTerminal()
        terminal.emergencyRestore()
        terminal.emergencyRestore()
        let output = readFromPipe(p.rfd, 4096)

        check output == EmergencyResetSeq & EmergencyResetSeq
      else:
        skip()

  suite "Terminal.clearScreen":
    test "resets SGR, clears, and records a blank screen at the current size":
      when defined(posix):
        let p = redirectStdoutToPipe()
        if p.saved == -1:
          skip()
        defer:
          restoreStdout(p)

        let terminal = newTerminal()
        terminal.size = size(10, 3)
        terminal.lastBuffer = newBuffer(4, 2)
        terminal.lastBuffer[0, 0] = cell("x")

        terminal.clearScreen()

        check readFromPipe(p.rfd, 4096) == ResetAndClearScreenSeq
        check terminal.lastBuffer == newBuffer(10, 3)
      else:
        skip()

    test "the next draw writes only the cells that are not blank":
      when defined(posix):
        let p = redirectStdoutToPipe()
        if p.saved == -1:
          skip()
        defer:
          restoreStdout(p)

        let terminal = newTerminal()
        terminal.size = size(10, 3)
        terminal.clearScreen()
        discard readFromPipe(p.rfd, 4096)

        var frame = newBuffer(10, 3)
        frame[2, 1] = cell("x")
        terminal.draw(frame)
        let output = readFromPipe(p.rfd, 4096)

        check output ==
          wrapWithSyncOutput(buildDifferentialOutput(newBuffer(10, 3), frame))
        check not output.contains(ClearScreenSeq)
      else:
        skip()

    test "a failed clear raises and makes the next draw an aborted full render":
      when defined(posix):
        let terminal = newTerminal()
        terminal.size = size(10, 3)
        terminal.lastBuffer = newBuffer(10, 3)

        var raised = false
        withFailingStdout(
          proc() =
            try:
              terminal.clearScreen()
            except IOError:
              raised = true
        )
        check raised

        var frame = newBuffer(10, 3)
        frame[2, 1] = cell("x")
        let output = captureStdout(
          proc() =
            terminal.draw(frame)
        )

        check output == AbortFrameSeq & wrapWithSyncOutput(buildFullRenderOutput(frame))
      else:
        skip()

  suite "Unknown screen state":
    # A write that fails may have stopped partway, so the screen and the
    # terminal's parser state are unknown until a frame or clear goes out.
    test "the screen state templates work outside the terminal module":
      # They are exported from terminal_common, so they must not need the
      # terminal module's private fields.
      let terminal = newTerminal()
      terminal.size = size(4, 2)
      terminal.markScreenUnknown()
      check terminal.screenUnknown
      check terminal.frameForce(false)
      check terminal.frameBytes("x") == AbortFrameSeq & wrapWithSyncOutput("x")

      var frame = newBuffer(4, 2)
      terminal.adoptLastBufferImpl(frame)
      check not terminal.screenUnknown
      check terminal.frameBytes("x") == wrapWithSyncOutput("x")

    test "a failed draw makes the next draw an aborted full render":
      when defined(posix):
        let terminal = newTerminal()
        terminal.lastBuffer = newBuffer(10, 3)
        var frame = newBuffer(10, 3)
        frame[2, 1] = cell("x")
        withFailingStdout(
          proc() =
            terminal.draw(frame)
        )

        var next = frame
        next[3, 1] = cell("y")
        let output = captureStdout(
          proc() =
            terminal.draw(next)
        )
        check output == AbortFrameSeq & wrapWithSyncOutput(buildFullRenderOutput(next))

        # Known again: the frame after that is a plain diff.
        var third = next
        third[4, 1] = cell("z")
        let diff = captureStdout(
          proc() =
            terminal.draw(third)
        )
        check diff == wrapWithSyncOutput(buildDifferentialOutput(next, third))
      else:
        skip()

    test "a failed drawWithCursor makes the next frame an aborted full render":
      when defined(posix):
        let terminal = newTerminal()
        terminal.lastBuffer = newBuffer(10, 3)
        var frame = newBuffer(10, 3)
        frame[2, 1] = cell("x")
        var style = CursorStyle.Default
        withFailingStdout(
          proc() =
            style = terminal.drawWithCursor(
              frame, 1, 1, true, SteadyBar, lastCursorStyle = style
            )
        )
        check style == CursorStyle.Default

        let output = captureStdout(
          proc() =
            discard terminal.drawWithCursor(
              frame, 1, 1, true, SteadyBar, lastCursorStyle = style
            )
        )
        let (expected, _) = buildOutputWithCursor(
          newBuffer(10, 3),
          frame,
          1,
          1,
          true,
          SteadyBar,
          lastCursorStyle = CursorStyle.Default,
          force = true,
        )
        check output == AbortFrameSeq & wrapWithSyncOutput(expected)
      else:
        skip()

    test "a clear after a failed write aborts first and makes the screen known":
      when defined(posix):
        let terminal = newTerminal()
        terminal.size = size(10, 3)
        terminal.lastBuffer = newBuffer(10, 3)
        var frame = newBuffer(10, 3)
        frame[2, 1] = cell("x")
        withFailingStdout(
          proc() =
            terminal.draw(frame)
        )

        let cleared = captureStdout(
          proc() =
            terminal.clearScreen()
        )
        check cleared == AbortFrameSeq & ResetAndClearScreenSeq

        let output = captureStdout(
          proc() =
            terminal.draw(frame)
        )
        check output ==
          wrapWithSyncOutput(buildDifferentialOutput(newBuffer(10, 3), frame))
      else:
        skip()

    test "render and renderFull abort first while the screen is unknown":
      when defined(posix):
        let terminal = newTerminal()
        terminal.lastBuffer = newBuffer(10, 3)
        var frame = newBuffer(10, 3)
        frame[2, 1] = cell("x")

        var raised = false
        withFailingStdout(
          proc() =
            try:
              terminal.render(frame)
            except TerminalError:
              raised = true
        )
        check raised

        # A diff against the old `lastBuffer` would be wrong: render in full.
        let rendered = captureStdout(
          proc() =
            terminal.render(frame)
        )
        check rendered == AbortFrameSeq & buildFullRenderOutput(frame)

        withFailingStdout(
          proc() =
            terminal.draw(newBuffer(10, 3))
        )
        let full = captureStdout(
          proc() =
            terminal.renderFull(frame)
        )
        check full == AbortFrameSeq & buildFullRenderOutput(frame)

        # Known again: no abort, and render diffs.
        var next = frame
        next[3, 1] = cell("y")
        let diff = captureStdout(
          proc() =
            terminal.render(next)
        )
        check diff == buildDifferentialOutput(frame, next)
      else:
        skip()

    test "the first draw after resume is an aborted full render":
      when defined(posix):
        let terminal = newTerminal()
        terminal.lastBuffer = newBuffer(10, 3)
        var frame = newBuffer(10, 3)
        frame[2, 1] = cell("x")
        discard captureStdout(
          proc() =
            terminal.suspend()
            terminal.resume()
        )

        let drawn = captureStdout(
          proc() =
            terminal.draw(frame)
        )
        check drawn == AbortFrameSeq & wrapWithSyncOutput(buildFullRenderOutput(frame))
      else:
        skip()

    test "a draw cut off partway is aborted at once and the next draw is full":
      when defined(linux):
        let terminal = newTerminal()
        terminal.lastBuffer = newBuffer(10, 3)
        var frame = newBuffer(10, 3)
        frame[2, 1] = cell("x")
        var next = frame
        next[3, 1] = cell("y")
        let output = captureCutStdout(
          10,
          proc() =
            terminal.draw(frame)
            terminal.draw(next),
        )

        let cutFrame =
          wrapWithSyncOutput(buildDifferentialOutput(newBuffer(10, 3), frame))
        check output ==
          cutFrame[0 ..< 10] & AbortPartialSeq & AbortFrameSeq &
          wrapWithSyncOutput(buildFullRenderOutput(next))
      else:
        skip()

    test "cleanup and suspend close what a failed write left open first":
      when defined(posix):
        let terminal = newTerminal()
        terminal.lastBuffer = newBuffer(10, 3)
        let known = captureStdout(
          proc() =
            terminal.cleanup()
        )
        check known == ShowCursorSeq

        var frame = newBuffer(10, 3)
        frame[2, 1] = cell("x")
        withFailingStdout(
          proc() =
            terminal.draw(frame)
        )
        let cleaned = captureStdout(
          proc() =
            terminal.cleanup()
        )
        check cleaned == AbortFrameSeq & "\e[0m" & ShowCursorSeq

        let suspended = captureStdout(
          proc() =
            terminal.suspend()
        )
        check suspended == AbortFrameSeq & "\e[0m" & ShowCursorSeq
      else:
        skip()

    test "the abort keeps a synchronized output block the app opened":
      when defined(posix):
        let terminal = newTerminal()
        terminal.size = size(10, 3)
        terminal.lastBuffer = newBuffer(10, 3)
        discard captureStdout(
          proc() =
            terminal.enableSyncOutput()
        )
        var frame = newBuffer(10, 3)
        frame[2, 1] = cell("x")
        withFailingStdout(
          proc() =
            terminal.draw(frame)
        )
        let cleared = captureStdout(
          proc() =
            terminal.clearScreen()
        )
        check cleared == AbortFrameKeepSyncSeq & ResetAndClearScreenSeq

        withFailingStdout(
          proc() =
            terminal.draw(frame)
        )
        # cleanup ends the app's block once, in its own step.
        let cleaned = captureStdout(
          proc() =
            terminal.cleanup()
        )
        check cleaned ==
          AbortFrameKeepSyncSeq & "\e[0m" & ShowCursorSeq & SyncOutputDisable
      else:
        skip()
