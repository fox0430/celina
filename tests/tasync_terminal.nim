# Tests for async_terminal module

import std/[unittest, strutils]

import ../celina/async/[async_backend, async_buffer]
import ../celina/core/[geometry, colors, buffer, errors]

import ../celina/async/async_terminal {.all.}
import ../celina/core/terminal_common

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

suite "Async Adopt Rendering":
  test "drawWithCursorAdoptAsync swaps AsyncBuffer when areas match":
    let terminal = createTestTerminal()
    terminal.lastBuffer = newBuffer(10, 5)
    terminal.lastBuffer[0, 0] = cell("OLD")

    let asyncBuffer = newAsyncBuffer(10, 5)
    asyncBuffer.withBuffer:
      buffer[0, 0] = cell("NEW")

    discard waitFor terminal.drawWithCursorAdoptAsync(
      asyncBuffer, 0, 0, false, CursorStyle.Default, CursorStyle.Default, force = true
    )

    check terminal.lastBuffer[0, 0].symbol == "NEW"
    asyncBuffer.withBuffer:
      check buffer[0, 0].symbol == "OLD"

  test "drawWithCursorAdoptAsync copies AsyncBuffer when areas differ":
    let terminal = createTestTerminal()
    terminal.lastBuffer = newBuffer(5, 5)
    terminal.lastBuffer[0, 0] = cell("OLD")

    let asyncBuffer = newAsyncBuffer(10, 5)
    asyncBuffer.withBuffer:
      buffer[0, 0] = cell("NEW")

    discard waitFor terminal.drawWithCursorAdoptAsync(
      asyncBuffer, 0, 0, false, CursorStyle.Default, CursorStyle.Default, force = true
    )

    check terminal.lastBuffer[0, 0].symbol == "NEW"
    asyncBuffer.withBuffer:
      check buffer[0, 0].symbol == "NEW"
      check buffer.area == terminal.lastBuffer.area

  test "drawWithCursorAdoptAsync recycles AsyncBuffer across frames":
    let terminal = createTestTerminal()
    let asyncBuffer = newAsyncBuffer(10, 5)

    for i in 0 ..< 3:
      asyncBuffer.withBuffer:
        buffer.clear()
        buffer[0, 0] = cell($i)
      discard waitFor terminal.drawWithCursorAdoptAsync(
        asyncBuffer, 0, 0, false, CursorStyle.Default, CursorStyle.Default, force = true
      )
      check terminal.lastBuffer[0, 0].symbol == $i

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

suite "AsyncTerminal Common Module Integration":
  test "Terminal uses common ANSI sequences":
    # Test that common sequences are accessible
    check AlternateScreenEnter == "\e[?1049h"
    check AlternateScreenExit == "\e[?1049l"
    check HideCursorSeq == "\e[?25l"
    check ShowCursorSeq == "\e[?25h"

  test "Terminal size detection integration":
    let (width, height, success) = getTerminalSizeFromSystem()
    let asyncSize = getTerminalSizeAsync()

    # Both should return reasonable values
    check asyncSize.width > 0
    check asyncSize.height > 0

    if success:
      # If system detection works, both should agree
      check asyncSize.width == width
      check asyncSize.height == height
    else:
      # Fallback should be used
      check asyncSize.width >= 10
      check asyncSize.height >= 5

  test "Mouse mode integration":
    let enableSeq = enableMouseMode(MouseSGR)
    let disableSeq = disableMouseMode(MouseSGR)

    check enableSeq.len > 0
    check disableSeq.len > 0
    check enableSeq != disableSeq

  test "Render batch integration":
    var buffer1 = newBuffer(5, 3)
    var buffer2 = newBuffer(5, 3)

    buffer2[1, 1] = cell("T", defaultStyle())
    buffer2[2, 2] = cell("E", defaultStyle())

    let output = buildDifferentialOutput(buffer1, buffer2)
    check output.len > 0
    check output.find("T") >= 0
    check output.find("E") >= 0

suite "AsyncTerminal Cursor Control":
  test "Cursor movement sequences are valid":
    # Test that cursor movement sequences are properly formatted
    let upSeq = makeCursorMoveSeq(CursorUpSeq, 3)
    let downSeq = makeCursorMoveSeq(CursorDownSeq, 5)
    let leftSeq = makeCursorMoveSeq(CursorLeftSeq, 2)
    let rightSeq = makeCursorMoveSeq(CursorRightSeq, 4)

    check upSeq.contains("3")
    check downSeq.contains("5")
    check leftSeq.contains("2")
    check rightSeq.contains("4")

    # Single step uses shorter sequence
    let singleUp = makeCursorMoveSeq(CursorUpSeq, 1)
    check singleUp == CursorUpSeq

  test "Save and restore cursor sequences":
    check SaveCursorSeq == "\e[s"
    check RestoreCursorSeq == "\e[u"

  test "Cursor style sequences are valid":
    check getCursorStyleSeq(CursorStyle.Default) == CursorStyleDefault
    check getCursorStyleSeq(CursorStyle.BlinkingBlock) == CursorStyleBlinkingBlock
    check getCursorStyleSeq(CursorStyle.SteadyBlock) == CursorStyleSteadyBlock
    check getCursorStyleSeq(CursorStyle.BlinkingUnderline) ==
      CursorStyleBlinkingUnderline
    check getCursorStyleSeq(CursorStyle.SteadyUnderline) == CursorStyleSteadyUnderline
    check getCursorStyleSeq(CursorStyle.BlinkingBar) == CursorStyleBlinkingBar
    check getCursorStyleSeq(CursorStyle.SteadyBar) == CursorStyleSteadyBar

suite "AsyncTerminal Line Clearing":
  test "Clear line sequences are valid":
    check ClearLineSeq == "\e[2K"
    check ClearToEndOfLineSeq == "\e[0K"
    check ClearToStartOfLineSeq == "\e[1K"

  test "Clear sequences are different":
    check ClearLineSeq != ClearToEndOfLineSeq
    check ClearLineSeq != ClearToStartOfLineSeq
    check ClearToEndOfLineSeq != ClearToStartOfLineSeq

suite "AsyncTerminal Setup Variants":
  test "setupWithHiddenCursorAsync exists":
    # Test that the proc exists and has correct signature
    let terminal = createTestTerminal()
    # We can't actually call it without a real terminal, but we can verify it compiles
    when compiles(terminal.setupWithHiddenCursorAsync()):
      check true
    else:
      check false

suite "AsyncTerminal Cleanup":
  # Note: rawMode is exercised separately because enableRawMode calls
  # tcsetattr() on the real terminal. The flags toggled below only
  # require stdout writes and are safe in tests.

  test "cleanup resets all toggleable flags":
    let terminal = createTestTerminal()

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
    let terminal = createTestTerminal()
    terminal.enableMouse()
    terminal.enableBracketedPaste()

    terminal.cleanup()
    check not terminal.mouseEnabled
    check not terminal.bracketedPasteEnabled

    terminal.cleanup()
    check not terminal.mouseEnabled
    check not terminal.bracketedPasteEnabled

  test "cleanup with partial state disables only enabled flags":
    let terminal = createTestTerminal()
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
    let terminal = createTestTerminal()
    terminal.cleanup()
    check not terminal.alternateScreen
    check not terminal.mouseEnabled
    check not terminal.bracketedPasteEnabled
    check not terminal.focusEventsEnabled
    check not terminal.syncOutputEnabled

  test "cleanup disables flag enabled last (LIFO end of sequence)":
    # alternateScreen is the final disable step in cleanup's LIFO order,
    # so this guards against accidentally truncating the sequence.
    let terminal = createTestTerminal()
    terminal.enableAlternateScreen()
    check terminal.alternateScreen

    terminal.cleanup()
    check not terminal.alternateScreen

suite "AsyncTerminal cleanupAsync":
  test "cleanupAsync resets all toggleable flags":
    let terminal = createTestTerminal()

    terminal.enableAlternateScreen()
    terminal.enableMouse()
    terminal.enableBracketedPaste()
    terminal.enableFocusEvents()
    terminal.enableSyncOutput()

    waitFor terminal.cleanupAsync()

    check not terminal.alternateScreen
    check not terminal.mouseEnabled
    check not terminal.bracketedPasteEnabled
    check not terminal.focusEventsEnabled
    check not terminal.syncOutputEnabled

  test "cleanupAsync is idempotent":
    let terminal = createTestTerminal()
    terminal.enableMouse()

    waitFor terminal.cleanupAsync()
    check not terminal.mouseEnabled

    waitFor terminal.cleanupAsync()
    check not terminal.mouseEnabled
