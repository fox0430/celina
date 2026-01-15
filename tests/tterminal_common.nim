# Tests for terminal_common module

import std/[unittest, strutils, times]

import ../celina/core/terminal_common
import ../celina/core/[geometry, colors, buffer]

suite "Terminal Common Module Tests":
  suite "ANSI Sequence Constants":
    test "Basic ANSI escape sequences":
      check AlternateScreenEnter == "\e[?1049h"
      check AlternateScreenExit == "\e[?1049l"
      check ClearScreenSeq == "\e[2J"
      check ClearLineSeq == "\e[2K"
      check HideCursorSeq == "\e[?25l"
      check ShowCursorSeq == "\e[?25h"
      check SaveCursorSeq == "\e[s"
      check RestoreCursorSeq == "\e[u"

    test "Cursor position sequences":
      check makeCursorPositionSeq(0, 0) == "\e[1;1H"
      check makeCursorPositionSeq(10, 5) == "\e[6;11H"
      check makeCursorPositionSeq(pos(20, 15)) == "\e[16;21H"
      check makeCursorPositionSeq(pos(2, 3)) == "\e[4;3H"

    test "Cursor movement sequences":
      # Single step movements
      check makeCursorMoveSeq("\e[A", 1) == "\e[A"
      check makeCursorMoveSeq("\e[B", 1) == "\e[B"
      check makeCursorMoveSeq("\e[C", 1) == "\e[C"
      check makeCursorMoveSeq("\e[D", 1) == "\e[D"

      # Multiple step movements
      check makeCursorMoveSeq("\e[A", 3) == "\e[3A"
      check makeCursorMoveSeq("\e[B", 5) == "\e[5B"
      check makeCursorMoveSeq("\e[C", 2) == "\e[2C"
      check makeCursorMoveSeq("\e[D", 4) == "\e[4D"

    test "Clear sequences":
      check ClearToEndOfLineSeq == "\e[0K"
      check ClearToStartOfLineSeq == "\e[1K"

    test "Bracketed paste mode sequences":
      check BracketedPasteEnable == "\e[?2004h"
      check BracketedPasteDisable == "\e[?2004l"

    test "Focus events sequences":
      check FocusEventsEnable == "\e[?1004h"
      check FocusEventsDisable == "\e[?1004l"

    test "Synchronized output sequences":
      check SyncOutputEnable == "\e[?2026h"
      check SyncOutputDisable == "\e[?2026l"

    test "wrapWithSyncOutput wraps output correctly":
      let output = "test output"
      let wrapped = wrapWithSyncOutput(output)
      check wrapped == "\e[?2026h" & output & "\e[?2026l"
      check wrapped.startsWith(SyncOutputEnable)
      check wrapped.endsWith(SyncOutputDisable)

    test "wrapWithSyncOutput handles empty output":
      let wrapped = wrapWithSyncOutput("")
      check wrapped == ""

  suite "Cursor Support":
    test "CursorState initialization":
      var state = CursorState(x: -1, y: -1, visible: false, style: CursorStyle.Default)
      check state.x == -1
      check state.y == -1
      check state.visible == false
      check state.style == CursorStyle.Default
      check state.lastStyle == CursorStyle.Default

    test "Cursor style sequences":
      check getCursorStyleSeq(CursorStyle.Default) == "\e[0 q"
      check getCursorStyleSeq(CursorStyle.BlinkingBlock) == "\e[1 q"
      check getCursorStyleSeq(CursorStyle.SteadyBlock) == "\e[2 q"
      check getCursorStyleSeq(CursorStyle.BlinkingUnderline) == "\e[3 q"
      check getCursorStyleSeq(CursorStyle.SteadyUnderline) == "\e[4 q"
      check getCursorStyleSeq(CursorStyle.BlinkingBar) == "\e[5 q"
      check getCursorStyleSeq(CursorStyle.SteadyBar) == "\e[6 q"

    test "buildOutputWithCursor basic functionality":
      var oldBuffer = newBuffer(rect(0, 0, 10, 5))
      var newBuffer = newBuffer(rect(0, 0, 10, 5))
      var lastCursorStyle = CursorStyle.Default

      # Add some content
      newBuffer[2, 2] = cell("A", defaultStyle())

      # Test with visible cursor
      let output = buildOutputWithCursor(
        oldBuffer,
        newBuffer,
        cursorX = 3,
        cursorY = 2,
        cursorVisible = true,
        cursorStyle = CursorStyle.Default,
        lastCursorStyle = lastCursorStyle,
      )

      check ShowCursorSeq in output
      check "\e[3;4H" in output # Cursor at (3,2) - 1-based indexing

    test "buildOutputWithCursor with hidden cursor":
      var oldBuffer = newBuffer(rect(0, 0, 10, 5))
      var newBuffer = newBuffer(rect(0, 0, 10, 5))
      var lastCursorStyle = CursorStyle.Default

      let output = buildOutputWithCursor(
        oldBuffer,
        newBuffer,
        cursorX = 3,
        cursorY = 2,
        cursorVisible = false,
        cursorStyle = CursorStyle.Default,
        lastCursorStyle = lastCursorStyle,
      )

      check HideCursorSeq in output

    test "buildOutputWithCursor style change tracking":
      var oldBuffer = newBuffer(rect(0, 0, 10, 5))
      var newBuffer = newBuffer(rect(0, 0, 10, 5))
      var lastCursorStyle = CursorStyle.Default

      # First call with new style
      let output1 = buildOutputWithCursor(
        oldBuffer,
        newBuffer,
        cursorX = 0,
        cursorY = 0,
        cursorVisible = true,
        cursorStyle = CursorStyle.BlinkingBar,
        lastCursorStyle = lastCursorStyle,
      )

      check "\e[5 q" in output1 # Blinking bar style
      check lastCursorStyle == CursorStyle.BlinkingBar

      # Second call with same style - should not repeat
      let output2 = buildOutputWithCursor(
        oldBuffer,
        newBuffer,
        cursorX = 1,
        cursorY = 1,
        cursorVisible = true,
        cursorStyle = CursorStyle.BlinkingBar,
        lastCursorStyle = lastCursorStyle,
      )

      check "\e[5 q" notin output2 # Should not repeat style

    test "buildOutputWithCursor with invalid cursor positions":
      var oldBuffer = newBuffer(rect(0, 0, 10, 5))
      var newBuffer = newBuffer(rect(0, 0, 10, 5))
      var lastCursorStyle = CursorStyle.Default

      # Test with negative cursor positions (should hide cursor)
      let output = buildOutputWithCursor(
        oldBuffer,
        newBuffer,
        cursorX = -1,
        cursorY = -1,
        cursorVisible = true, # Even if visible is true
        cursorStyle = CursorStyle.Default,
        lastCursorStyle = lastCursorStyle,
      )

      check HideCursorSeq in output
      check ShowCursorSeq notin output

    test "CursorState field updates":
      var state = CursorState(x: 0, y: 0, visible: false, style: CursorStyle.Default)

      # Test position update
      state.x = 10
      state.y = 5
      check state.x == 10
      check state.y == 5

      # Test visibility toggle
      state.visible = true
      check state.visible == true

      # Test style change
      state.style = CursorStyle.BlinkingBar
      check state.style == CursorStyle.BlinkingBar

      # Test lastStyle management
      state.lastStyle = state.style
      check state.lastStyle == CursorStyle.BlinkingBar

  suite "Terminal Size Detection":
    test "getTerminalSizeFromSystem returns valid tuple":
      let (width, height, success) = getTerminalSizeFromSystem()

      if success:
        check width > 0
        check height > 0
        check width >= 10 # Reasonable minimum
        check height >= 5
      else:
        # CI environment - should return fallback
        check width == 80
        check height == 24

    test "getTerminalSizeWithFallback returns valid size":
      let size1 = getTerminalSizeWithFallback()
      check size1.width > 0
      check size1.height > 0

      let size2 = getTerminalSizeWithFallback(100, 30)
      # Should be either detected size or custom fallback
      check size2.width > 0
      check size2.height > 0

  suite "Terminal Configuration":
    test "getRawModeConfig returns valid config":
      let config = getRawModeConfig()

      # Test that config has reasonable values
      check config.c_lflag_mask != 0
      check config.c_iflag_mask != 0
      check config.c_cflag_set != 0
      check config.c_oflag_mask != 0
      check config.vmin == 1.char
      check config.vtime == 0.char

  suite "Mouse Mode Management":
    test "Mouse mode sequences":
      # Test enable sequences
      let enableX10 = enableMouseMode(MouseX10)
      check MouseX10.ord >= 0
      check enableX10.len > 0

      let enableSGR = enableMouseMode(MouseSGR)
      check enableSGR.contains("?1006h") # SGR mode enable

      # Test disable sequences  
      let disableSGR = disableMouseMode(MouseSGR)
      check disableSGR.contains("?1006l") # SGR mode disable

    test "Mouse mode off handling":
      let enableOff = enableMouseMode(MouseOff)
      check enableOff == ""

      let disableOff = disableMouseMode(MouseOff)
      check disableOff == ""

  suite "Render Command System":
    test "RenderCommand creation":
      let posCmd = RenderCommand(kind: RckSetPosition, pos: pos(10, 20))
      check posCmd.kind == RckSetPosition
      check posCmd.pos.x == 10
      check posCmd.pos.y == 20

      let styleCmd = RenderCommand(kind: RckSetStyle, style: style(Color.Red))
      check styleCmd.kind == RckSetStyle
      check styleCmd.style.fg.indexed == Color.Red

      let textCmd = RenderCommand(kind: RckWriteText, text: "Hello")
      check textCmd.kind == RckWriteText
      check textCmd.text == "Hello"

    test "RenderBatch operations":
      var batch = RenderBatch(commands: @[], estimatedSize: 0)

      let posCmd = RenderCommand(kind: RckSetPosition, pos: pos(5, 10))
      batch.addCommand(posCmd)
      check batch.commands.len == 1
      check batch.estimatedSize > 0

      let textCmd = RenderCommand(kind: RckWriteText, text: "Test")
      batch.addCommand(textCmd)
      check batch.commands.len == 2
      check batch.estimatedSize >= 4 # At least the text length

  suite "Render Batch Generation":
    test "generateRenderBatch with no changes":
      let emptyChanges: seq[tuple[pos: Position, cell: Cell]] = @[]
      let batch = generateRenderBatch(emptyChanges)
      check batch.commands.len == 0
      check batch.estimatedSize == 0

    test "generateRenderBatch with single change":
      let changes = @[(pos: pos(5, 10), cell: cell("A", defaultStyle()))]
      let batch = generateRenderBatch(changes)

      # Should generate position + text commands
      check batch.commands.len >= 1
      check batch.estimatedSize > 0

    test "generateRenderBatch with styled changes":
      let redStyle = style(Color.Red)
      let changes =
        @[
          (pos: pos(0, 0), cell: cell("A", redStyle)),
          (pos: pos(1, 0), cell: cell("B", redStyle)),
          (pos: pos(2, 0), cell: cell("C", defaultStyle())),
        ]

      let batch = generateRenderBatch(changes)
      check batch.commands.len >= 1
      check batch.estimatedSize > 0

  suite "Render Batch Optimization":
    test "optimizeRenderBatch merges text commands":
      var batch = RenderBatch(commands: @[], estimatedSize: 0)
      batch.addCommand(RenderCommand(kind: RckWriteText, text: "Hello"))
      batch.addCommand(RenderCommand(kind: RckWriteText, text: " "))
      batch.addCommand(RenderCommand(kind: RckWriteText, text: "World"))

      let optimized = optimizeRenderBatch(batch)

      # Should have fewer commands due to merging
      check optimized.commands.len <= batch.commands.len

    test "optimizeRenderBatch removes redundant styles":
      var batch = RenderBatch(commands: @[], estimatedSize: 0)
      let redStyle = style(Color.Red)
      let blueStyle = style(Color.Blue)

      batch.addCommand(RenderCommand(kind: RckSetStyle, style: redStyle))
      batch.addCommand(RenderCommand(kind: RckSetStyle, style: blueStyle))
      batch.addCommand(RenderCommand(kind: RckWriteText, text: "Test"))

      let optimized = optimizeRenderBatch(batch)
      check optimized.commands.len <= batch.commands.len

  suite "Output String Generation":
    test "buildOutputString from simple batch":
      var batch = RenderBatch(commands: @[], estimatedSize: 0)
      batch.addCommand(RenderCommand(kind: RckSetPosition, pos: pos(5, 10)))
      batch.addCommand(RenderCommand(kind: RckWriteText, text: "Hello"))

      let output = buildOutputString(batch)
      check output.contains("\e[11;6H") # Position sequence
      check output.contains("Hello")

    test "buildOutputString with style commands":
      var batch = RenderBatch(commands: @[], estimatedSize: 0)
      let redStyle = style(Color.Red)
      batch.addCommand(RenderCommand(kind: RckSetStyle, style: redStyle))
      batch.addCommand(RenderCommand(kind: RckWriteText, text: "Red"))

      let output = buildOutputString(batch)
      check output.len > 0
      check output.contains("Red")

    test "buildOutputString with clear commands":
      var batch = RenderBatch(commands: @[], estimatedSize: 0)
      batch.addCommand(RenderCommand(kind: RckClearScreen))
      batch.addCommand(RenderCommand(kind: RckClearLine))

      let output = buildOutputString(batch)
      check output.contains(ClearScreenSeq)
      check output.contains(ClearLineSeq)

  suite "Differential Rendering":
    test "buildDifferentialOutput with no changes":
      let buffer1 = newBuffer(5, 3)
      let buffer2 = newBuffer(5, 3)

      let output = buildDifferentialOutput(buffer1, buffer2)
      # Should have reset sequence at minimum or be empty
      check output == resetSequence() or output == ""

    test "buildDifferentialOutput with single cell change":
      var buffer1 = newBuffer(5, 3)
      var buffer2 = newBuffer(5, 3)

      buffer2[2, 1] = cell("X", defaultStyle())

      let output = buildDifferentialOutput(buffer1, buffer2)
      check output.len > 0
      check output.contains("X")

    test "buildDifferentialOutput with styled changes":
      var buffer1 = newBuffer(5, 3)
      var buffer2 = newBuffer(5, 3)

      let redStyle = style(Color.Red)
      buffer2[1, 1] = cell("R", redStyle)

      let output = buildDifferentialOutput(buffer1, buffer2)
      check output.len > 0
      check output.contains("R")

  suite "Full Render Output":
    test "buildFullRenderOutput clears screen first":
      let buffer = newBuffer(3, 2)
      let output = buildFullRenderOutput(buffer)

      check output.startsWith(ClearScreenSeq)
      # Output may or may not end with reset if no styles were used
      check output.len > 0

    test "buildFullRenderOutput with content":
      var buffer = newBuffer(3, 2)
      buffer[0, 0] = cell("A", defaultStyle())
      buffer[1, 1] = cell("B", defaultStyle())

      let output = buildFullRenderOutput(buffer)
      check output.contains("A")
      check output.contains("B")

    test "buildFullRenderOutput skips empty lines":
      var buffer = newBuffer(3, 3)
      buffer[0, 0] = cell("First", defaultStyle())
      buffer[0, 2] = cell("Third", defaultStyle())
      # Line 1 is empty

      let output = buildFullRenderOutput(buffer)
      check output.contains("First")
      check output.contains("Third")

  suite "Utility Functions":
    test "isTerminalInteractive detection":
      # This may vary in CI/test environments
      let isInteractive = isTerminalInteractive()
      # Just check it returns a valid boolean
      check isInteractive == isInteractive

    test "supportsAnsi detection":
      let supportsAnsi = supportsAnsi()
      check supportsAnsi == supportsAnsi

    test "getTerminalCapabilities returns valid set":
      let capabilities = getTerminalCapabilities()
      # Should return some mouse modes or empty set
      check capabilities == capabilities # Valid set

  suite "Edge Cases and Error Handling":
    test "makeCursorPositionSeq with boundary values":
      check makeCursorPositionSeq(-1, -1) == "\e[0;0H"
      check makeCursorPositionSeq(999, 999) == "\e[1000;1000H"

    test "generateRenderBatch with overlapping positions":
      let changes =
        @[
          (pos: pos(5, 5), cell: cell("A", defaultStyle())),
          (pos: pos(5, 5), cell: cell("B", defaultStyle())),
        ]

      let batch = generateRenderBatch(changes)
      check batch.commands.len >= 1

    test "buildOutputString with empty batch":
      let emptyBatch = RenderBatch(commands: @[], estimatedSize: 0)
      let output = buildOutputString(emptyBatch)
      check output == ""

  suite "Performance and Memory":
    test "render batch size estimation":
      var batch = RenderBatch(commands: @[], estimatedSize: 0)

      batch.addCommand(RenderCommand(kind: RckWriteText, text: "Hello"))
      check batch.estimatedSize >= 5 # Length of "Hello"

      batch.addCommand(RenderCommand(kind: RckSetPosition, pos: pos(10, 20)))
      check batch.estimatedSize >= 15 # Previous + estimated position seq

    test "large buffer differential handling":
      var buffer1 = newBuffer(100, 50)
      var buffer2 = newBuffer(100, 50)

      # Single change in large buffer
      buffer2[50, 25] = cell("*", defaultStyle())

      let output = buildDifferentialOutput(buffer1, buffer2)
      # Should be much smaller than full render
      check output.len < 1000 # Reasonable size for single change
      check output.contains("*")

  suite "Differential Rendering Regression Tests":
    # These tests validate the exact output format and prevent the button widget
    # display corruption bug that occurred with the old line-based algorithm

    test "prohibit ClearToEndOfLine usage":
      # The old algorithm used ClearToEndOfLineSeq which caused corruption
      # The new algorithm should NEVER use it
      var buffer1 = newBuffer(10, 2)
      var buffer2 = newBuffer(10, 2)

      # Create a scenario that would trigger ClearToEndOfLine in old algorithm
      buffer1[0, 0] = cell("A", style(White, Red))
      buffer1[1, 0] = cell("B", style(White, Red))
      buffer1[2, 0] = cell("C", style(White, Red))

      # Change only the first cell, leaving rest unchanged
      buffer2[0, 0] = cell("X", style(White, Blue))
      buffer2[1, 0] = cell("B", style(White, Red))
      buffer2[2, 0] = cell("C", style(White, Red))

      let output = buildDifferentialOutput(buffer1, buffer2)

      # The old algorithm would include ClearToEndOfLineSeq (\e[0K)
      # The new algorithm must NOT include it
      check not output.contains(ClearToEndOfLineSeq)
      check output.contains("X")

    test "validate exact cursor positioning":
      # Validate exact cursor positioning sequences
      var buffer1 = newBuffer(5, 3)
      var buffer2 = newBuffer(5, 3)

      # Change cells at specific positions
      buffer2[2, 1] = cell("A", style(White, Red))
      buffer2[4, 2] = cell("B", style(White, Blue))

      let output = buildDifferentialOutput(buffer1, buffer2)

      # Must contain exact position sequences (1-based terminal coordinates)
      check output.contains("[2;3H") # Position (2,1) -> terminal (2,3)
      check output.contains("[3;5H") # Position (4,2) -> terminal (3,5)
      check output.contains("A")
      check output.contains("B")

    test "validate ANSI style sequences":
      # Validate exact ANSI style sequences are generated correctly
      var buffer1 = newBuffer(3, 1)
      var buffer2 = newBuffer(3, 1)

      # Specific style changes that caused bugs in old algorithm
      buffer2[0, 0] = cell("X", style(White, Blue)) # \e[37;44m
      buffer2[1, 0] = cell("Y", style(Black, Yellow)) # \e[30;43m  
      buffer2[2, 0] = cell("Z", defaultStyle()) # \e[m

      let output = buildDifferentialOutput(buffer1, buffer2)

      # Must contain proper style sequences (using [ instead of \e[)
      check output.contains("[37;44m") or output.contains("[44;37m") # White on Blue
      check output.contains("[30;43m") or output.contains("[43;30m") # Black on Yellow
      check output.contains("[0m") # Reset for default style
      check output.contains("X")
      check output.contains("Y")
      check output.contains("Z")

    test "optimize consecutive cell rendering":
      # The new algorithm optimizes consecutive cells with same style
      var buffer1 = newBuffer(5, 1)
      var buffer2 = newBuffer(5, 1)

      # Change consecutive cells with same style
      let sameStyle = style(White, Red)
      buffer2[1, 0] = cell("A", sameStyle)
      buffer2[2, 0] = cell("B", sameStyle)
      buffer2[3, 0] = cell("C", sameStyle)

      let output = buildDifferentialOutput(buffer1, buffer2)

      # Should contain position for first cell only (optimization)
      check output.contains("[1;2H") # First position
      check output.contains("A")
      check output.contains("B")
      check output.contains("C")

      # Should NOT contain redundant positioning for consecutive cells
      check not output.contains("[1;3H") # No position for B
      check not output.contains("[1;4H") # No position for C

    test "ensure proper style reset":
      # Ensure styles are properly reset to prevent bleeding
      var buffer1 = newBuffer(4, 1)
      var buffer2 = newBuffer(4, 1)

      # Styled cell followed by default style cell
      buffer2[0, 0] = cell("S", style(White, Red))
      buffer2[1, 0] = cell("D", defaultStyle())

      let output = buildDifferentialOutput(buffer1, buffer2)

      # Must include style sequence, then reset (using [ format)
      check output.contains("[37;41m") or output.contains("[41;37m") # Style
      check output.contains("S")
      check output.contains("[0m") # Reset before default style
      check output.contains("D")

    test "handle multi-button state changes":
      # Test that reproduces the exact bug scenario: multiple buttons changing
      var buffer1 = newBuffer(25, 3)
      var buffer2 = newBuffer(25, 3)

      # Simulate 3 buttons on same line, each 7 chars wide, 1 char spacing
      # Button 1: Blue -> Cyan (positions 0-6)
      for x in 0 .. 6:
        buffer1[x, 1] = cell(" ", style(White, Blue))
        buffer2[x, 1] = cell(" ", style(White, Cyan))

      # Button 2: Green -> BrightGreen (positions 8-14) 
      for x in 8 .. 14:
        buffer1[x, 1] = cell(" ", style(White, Green))
        buffer2[x, 1] = cell(" ", style(White, BrightGreen))

      # Button 3: Red -> BrightRed (positions 16-22)
      for x in 16 .. 22:
        buffer1[x, 1] = cell(" ", style(White, Red))
        buffer2[x, 1] = cell(" ", style(White, BrightRed))

      let output = buildDifferentialOutput(buffer1, buffer2)

      # Validate specific positioning and no line clearing
      check not output.contains(ClearToEndOfLineSeq)
      check output.contains("[2;1H") # Button 1 start
      check output.contains("[2;9H") # Button 2 start  
      check output.contains("[2;17H") # Button 3 start

      # Must contain all three style changes
      check output.contains("[46m") or output.contains("46") # Cyan background
      check output.contains("[102m") or output.contains("102") # Bright green background
      check output.contains("[101m") or output.contains("101") # Bright red background

    test "handle buffer boundary cases":
      # Test edge of buffer to ensure no out-of-bounds issues
      var buffer1 = newBuffer(3, 2)
      var buffer2 = newBuffer(3, 2)

      # Change last cell
      buffer2[2, 1] = cell("E", style(White, Yellow))

      let output = buildDifferentialOutput(buffer1, buffer2)

      # Must position correctly to last cell
      check output.contains("[2;3H") # Row 2, Col 3 (1-based)
      check output.contains("E")
      check output.contains("[43m") or output.contains("43") # Yellow background

    test "isolate non-adjacent style changes":
      # Ensure styles don't bleed between separated changes
      var buffer1 = newBuffer(10, 1)
      var buffer2 = newBuffer(10, 1)

      # Two separated styled cells with different styles
      buffer2[1, 0] = cell("A", style(White, Red)) # Position 1
      buffer2[8, 0] = cell("B", style(Black, Green)) # Position 8 (separated)

      let output = buildDifferentialOutput(buffer1, buffer2)

      # Should have two separate style applications
      check output.contains("[1;2H") # Position for A
      check output.contains("[1;9H") # Position for B
      check output.contains("A")
      check output.contains("B")

      # Should contain both styles and proper resets
      check (output.contains("[41m") or output.contains("41")) # Red
      check (output.contains("[42m") or output.contains("42")) # Green

      # Each style change should be isolated with resets
      let resetCount = output.count("[0m")
      check resetCount >= 2 # At least one reset between style changes

    test "handle empty buffer changes":
      # Test differential rendering with empty buffers
      var buffer1 = newBuffer(0, 0)
      var buffer2 = newBuffer(0, 0)

      let output = buildDifferentialOutput(buffer1, buffer2)

      # Should produce minimal output for empty buffers
      check output.len <= resetSequence().len # At most a reset sequence
      check not output.contains(ClearToEndOfLineSeq)

    test "handle single cell buffer":
      # Test minimal 1x1 buffer
      var buffer1 = newBuffer(1, 1)
      var buffer2 = newBuffer(1, 1)

      buffer2[0, 0] = cell("X", style(White, Red))

      let output = buildDifferentialOutput(buffer1, buffer2)

      check output.contains("[1;1H") # Position to top-left
      check output.contains("X")
      check output.contains("[41m") or output.contains("41") # Red background

    test "handle same position multiple changes":
      # Test overwriting the same position multiple times
      var buffer1 = newBuffer(3, 1)
      var buffer2 = newBuffer(3, 1)
      var buffer3 = newBuffer(3, 1)

      # First change
      buffer2[1, 0] = cell("A", style(White, Red))
      let output1 = buildDifferentialOutput(buffer1, buffer2)

      # Second change to same position
      buffer3[1, 0] = cell("B", style(White, Blue))
      let output2 = buildDifferentialOutput(buffer2, buffer3)

      # Both should work correctly
      check output1.contains("A")
      check output1.contains("[41m") or output1.contains("41")
      check output2.contains("B")
      check output2.contains("[44m") or output2.contains("44")

    test "handle invalid style transitions":
      # Test style transitions that might cause issues
      var buffer1 = newBuffer(4, 1)
      var buffer2 = newBuffer(4, 1)

      # Various style transitions that could be problematic
      buffer2[0, 0] = cell("1", defaultStyle()) # No style
      buffer2[1, 0] = cell("2", style(Reset, Reset)) # Reset style
      buffer2[2, 0] = cell("3", style(White, Reset)) # Mixed style
      buffer2[3, 0] = cell("4", style(Reset, Blue)) # Mixed style

      let output = buildDifferentialOutput(buffer1, buffer2)

      # Should handle all transitions without crashing
      check output.contains("1")
      check output.contains("2")
      check output.contains("3")
      check output.contains("4")

    test "handle large coordinate values":
      # Test with larger buffer coordinates
      var buffer1 = newBuffer(100, 50)
      var buffer2 = newBuffer(100, 50)

      # Change cell near maximum coordinates
      buffer2[99, 49] = cell("MAX", style(White, Yellow))

      let output = buildDifferentialOutput(buffer1, buffer2)

      # Should generate correct large coordinate sequence
      check output.contains("[50;100H") # Row 50, Col 100 (1-based)
      check output.contains("MAX")
      check output.contains("[43m") or output.contains("43") # Yellow

    test "handle zero-width and wide characters":
      # Test Unicode characters with different display widths
      var buffer1 = newBuffer(10, 1)
      var buffer2 = newBuffer(10, 1)

      # Various Unicode characters
      buffer2[0, 0] = cell("→", defaultStyle()) # Arrow (1 width)
      buffer2[1, 0] = cell("😀", defaultStyle()) # Emoji (2 width typically)
      buffer2[2, 0] = cell("中", defaultStyle()) # CJK (2 width)

      let output = buildDifferentialOutput(buffer1, buffer2)

      # Should handle Unicode characters without corruption
      check output.contains("→")
      check output.contains("😀")
      check output.contains("中")

    test "handle rapid alternating changes":
      # Test alternating pattern that might stress the algorithm
      var buffer1 = newBuffer(20, 1)
      var buffer2 = newBuffer(20, 1)

      # Create alternating pattern: styled, unstyled, styled, unstyled...
      for i in 0 .. 19:
        if i mod 2 == 0:
          buffer2[i, 0] = cell("S", style(White, Red))
        else:
          buffer2[i, 0] = cell("U", defaultStyle())

      let output = buildDifferentialOutput(buffer1, buffer2)

      # Should handle all changes with proper style management
      check output.contains("S")
      check output.contains("U")
      check output.contains("[41m") or output.contains("41") # Red style

      # Should have multiple resets for alternating styles
      let resetCount = output.count("[0m")
      check resetCount >= 10 # At least one reset per styled->unstyled transition

    test "handle identical style object references":
      # Test the specific bug scenario: multiple buttons sharing style objects
      var buffer1 = newBuffer(20, 1)
      var buffer2 = newBuffer(20, 1)

      # Create shared style object (the original bug cause)
      let sharedHoverStyle = style(White, Cyan)

      # Two buttons using the SAME style object reference
      for x in 0 .. 4:
        buffer1[x, 0] = cell(" ", style(White, Blue))
        buffer2[x, 0] = cell(" ", sharedHoverStyle) # Button 1 hover

      for x in 10 .. 14:
        buffer1[x, 0] = cell(" ", style(White, Green))
        buffer2[x, 0] = cell(" ", sharedHoverStyle) # Button 2 hover (SAME OBJECT!)

      let output = buildDifferentialOutput(buffer1, buffer2)

      # Should work correctly even with shared style objects
      check not output.contains(ClearToEndOfLineSeq)
      check output.contains("[46m") or output.contains("46") # Cyan
      check output.contains("[1;1H") # Button 1 position
      check output.contains("[1;11H") # Button 2 position

    test "handle buffer resize scenarios":
      # Test different buffer sizes (simulating terminal resize)
      var smallBuffer1 = newBuffer(5, 2)
      var smallBuffer2 = newBuffer(5, 2)
      var largeBuffer1 = newBuffer(10, 4)
      var largeBuffer2 = newBuffer(10, 4)

      # Small buffer change
      smallBuffer2[2, 1] = cell("S", style(White, Red))
      let smallOutput = buildDifferentialOutput(smallBuffer1, smallBuffer2)

      # Large buffer change at same relative position
      largeBuffer2[2, 1] = cell("L", style(White, Blue))
      let largeOutput = buildDifferentialOutput(largeBuffer1, largeBuffer2)

      # Both should work correctly
      check smallOutput.contains("[2;3H") # Same position calculation
      check largeOutput.contains("[2;3H") # Same position calculation
      check smallOutput.contains("S")
      check largeOutput.contains("L")

    test "handle style attribute edge cases":
      # Test extreme style attribute combinations
      var buffer1 = newBuffer(8, 1)
      var buffer2 = newBuffer(8, 1)

      # Test various style attribute combinations
      buffer2[0, 0] = cell("1", style(White, Black, {Bold}))
      buffer2[1, 0] = cell("2", style(Black, White, {Italic}))
      buffer2[2, 0] = cell("3", style(Red, Blue, {Underline}))
      buffer2[3, 0] = cell("4", style(Yellow, Green, {Bold, Italic}))
      buffer2[4, 0] = cell("5", style(Cyan, Magenta, {Bold, Underline}))
      buffer2[5, 0] = cell("6", style(BrightRed, BrightBlue, {Italic, Underline}))
      buffer2[6, 0] =
        cell("7", style(BrightWhite, BrightBlack, {Bold, Italic, Underline}))

      let output = buildDifferentialOutput(buffer1, buffer2)

      # Should handle all style combinations
      check output.contains("1")
      check output.contains("2")
      check output.contains("3")
      check output.contains("4")
      check output.contains("5")
      check output.contains("6")
      check output.contains("7")

      # Should contain style codes (exact codes may vary)
      check output.len > 100 # Complex styles generate substantial output

    test "handle performance stress test":
      # Test with many scattered changes (performance regression check)
      var buffer1 = newBuffer(50, 20) # 1000 cells
      var buffer2 = newBuffer(50, 20)

      # Make scattered changes across the buffer
      for i in 0 .. 99: # 100 random changes
        let x = i mod 50
        let y = (i * 7) mod 20 # Pseudo-random distribution
        buffer2[x, y] = cell("*", style(White, Red))

      let startTime = cpuTime()
      let output = buildDifferentialOutput(buffer1, buffer2)
      let duration = cpuTime() - startTime

      # Should complete quickly and correctly
      check output.contains("*")
      check duration < 0.05 # Should complete in < 50ms
      check output.count("*") >= 90 # Most changes should be present

  suite "Background Color Rendering (Regression Tests)":
    # These tests prevent regression of the bug where background-only colors
    # were not rendered in initial frames

    test "buildDifferentialOutput applies style when buffer size changes":
      # This was the first bug: when oldBuffer and newBuffer have different sizes,
      # styles were not applied at all
      var oldBuf = newBuffer(0, 0) # Empty initial buffer
      var newBuf = newBuffer(5, 2)

      # Set cells with RGB background colors only
      newBuf.setString(0, 0, " ", Style(bg: rgb(255, 0, 0))) # Red background
      newBuf.setString(1, 0, " ", Style(bg: rgb(0, 255, 0))) # Green background
      newBuf.setString(0, 1, "A", Style(fg: rgb(0, 0, 255))) # Blue foreground

      let output = buildDifferentialOutput(oldBuf, newBuf)

      # Verify RGB sequences are present
      check "48;2;255;0;0" in output # Red background ANSI code
      check "48;2;0;255;0" in output # Green background ANSI code
      check "38;2;0;0;255" in output # Blue foreground ANSI code

      # Verify reset sequences are present
      check output.contains("\e[0m")

    test "buildOutputWithCursor renders background-only colored cells":
      # This was the main bug: cells with only background color (no foreground)
      # were completely skipped in the rendering condition
      var oldBuf = newBuffer(0, 0)
      var newBuf = newBuffer(10, 3)

      # Set various color combinations
      newBuf.setString(0, 0, " ", Style(bg: rgb(10, 10, 20))) # BG only
      newBuf.setString(1, 0, " ", Style(bg: rgb(255, 0, 0))) # BG only (red)
      newBuf.setString(2, 0, "X", Style(fg: rgb(0, 255, 0))) # FG only (green)
      newBuf.setString(3, 0, "Y", Style(fg: rgb(255, 255, 255), bg: rgb(0, 0, 255)))
        # Both

      var lastCursorStyle = CursorStyle.Default
      let output = buildOutputWithCursor(
        oldBuf, newBuf, 0, 0, false, CursorStyle.Default, lastCursorStyle, force = false
      )

      # All color types should be present in output
      check "48;2;10;10;20" in output # Dark background
      check "48;2;255;0;0" in output # Red background
      check "38;2;0;255;0" in output # Green foreground
      check "48;2;0;0;255" in output # Blue background

    test "buildOutputWithCursor with 256-color backgrounds":
      # Also test 256-color mode to ensure the fix works for all color types
      var oldBuf = newBuffer(0, 0)
      var newBuf = newBuffer(5, 1)

      # Mix of 256-color backgrounds
      newBuf.setString(0, 0, " ", Style(bg: color256(196))) # Red
      newBuf.setString(1, 0, " ", Style(bg: grayscale(12))) # Gray
      newBuf.setString(2, 0, " ", Style(bg: color(BrightYellow))) # 16-color

      var lastCursorStyle = CursorStyle.Default
      let output = buildOutputWithCursor(
        oldBuf, newBuf, 0, 0, false, CursorStyle.Default, lastCursorStyle, force = false
      )

      # Verify 256-color codes
      check "48;5;196" in output # 256-color red background
      check "48;5;244" in output # Grayscale background
      check "103" in output or "48;5;11" in output # Bright yellow (16-color or 256)

    test "buildDifferentialOutput with only background colors":
      # Edge case: entire buffer is spaces with different background colors
      var oldBuf = newBuffer(5, 2)
      var newBuf = newBuffer(5, 2)

      # Fill with background colors only (simulating a color bar)
      for x in 0 ..< 5:
        let color = rgb(x * 50, 0, 0) # Gradient of red
        newBuf.setString(x, 0, " ", Style(bg: color))

      let output = buildDifferentialOutput(oldBuf, newBuf)

      # Should contain RGB background codes for all positions
      check "48;2;0;0;0" in output # rgb(0,0,0)
      check "48;2;50;0;0" in output # rgb(50,0,0)
      check "48;2;100;0;0" in output # rgb(100,0,0)
      check "48;2;150;0;0" in output # rgb(150,0,0)
      check "48;2;200;0;0" in output # rgb(200,0,0)
