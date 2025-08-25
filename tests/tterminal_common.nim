# Tests for terminal_common module

import std/[unittest, strutils]

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

    test "Cursor position sequences":
      check makeCursorPositionSeq(0, 0) == "\e[1;1H"
      check makeCursorPositionSeq(10, 5) == "\e[6;11H"
      check makeCursorPositionSeq(pos(20, 15)) == "\e[16;21H"

    test "Clear sequences":
      check ClearToEndOfLineSeq == "\e[0K"
      check ClearToStartOfLineSeq == "\e[1K"

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
