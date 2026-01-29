import std/unittest

import ../celina/async/async_backend

when hasAsyncSupport:
  import ../celina/async/[async_renderer, async_terminal]
  import ../celina/core/[buffer, cursor, geometry, colors, terminal_common, errors]

  suite "AsyncRenderer Module Tests":
    suite "AsyncRenderer Creation":
      test "Create async renderer with terminal":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          check rend != nil
        except TerminalError:
          skip()

    suite "Buffer Access":
      test "Get buffer from async renderer":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          var buf = rend.getBuffer()
          check buf.area.width > 0
          check buf.area.height > 0
        except TerminalError:
          skip()

    suite "Cursor Manager Access":
      test "Get cursor manager from async renderer":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          let cursorMgr = rend.getCursorManager()
          check cursorMgr != nil
        except TerminalError:
          skip()

    suite "AsyncRenderer Resizing":
      test "Resize async renderer with explicit dimensions":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          rend.resize(80, 24)

          var buf = rend.getBuffer()
          check buf.area.width == 80
          check buf.area.height == 24
        except TerminalError:
          skip()

      test "Resize async renderer based on terminal size":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          rend.resize()

          var buf = rend.getBuffer()
          let termSize = term.getSize()
          check buf.area.width == termSize.width
          check buf.area.height == termSize.height
        except TerminalError:
          skip()

    suite "Buffer Operations":
      test "Clear async renderer buffer":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          var buf = rend.getBuffer()
          buf.setString(0, 0, "Test", defaultStyle())

          rend.clear()

          buf = rend.getBuffer()
          let cell = buf[0, 0]
          check cell.symbol.len <= 1
        except TerminalError:
          skip()

      test "Set string in async renderer buffer":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          rend.setString(5, 5, "Hello", style(Red))

          var buf = rend.getBuffer()
          let cell = buf[5, 5]
          check cell.symbol.len > 0
        except TerminalError:
          skip()

    suite "Cursor Control via AsyncRenderer":
      test "Set cursor position with coordinates":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          rend.showCursorAt(10, 20)

          let (x, y) = rend.getCursorPosition()
          check x == 10
          check y == 20
        except TerminalError:
          skip()

      test "Set cursor position with Position type":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          let pos = Position(x: 15, y: 25)
          rend.showCursorAt(pos)

          let (x, y) = rend.getCursorPosition()
          check x == 15
          check y == 25
        except TerminalError:
          skip()

      test "Show and hide cursor":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          rend.showCursor()
          check rend.isCursorVisible() == true

          rend.hideCursor()
          check rend.isCursorVisible() == false
        except TerminalError:
          skip()

      test "Set cursor style":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          rend.setCursorStyle(CursorStyle.SteadyBlock)

          let cursorMgr = rend.getCursorManager()
          check cursorMgr.getStyle() == CursorStyle.SteadyBlock
        except TerminalError:
          skip()

      test "setCursorPosition without changing visibility":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          rend.hideCursor()
          check rend.isCursorVisible() == false

          rend.setCursorPosition(5, 10)

          let (x, y) = rend.getCursorPosition()
          check x == 5
          check y == 10
          check rend.isCursorVisible() == false
        except TerminalError:
          skip()

      test "setCursorPosition with Position type":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          let pos = Position(x: 7, y: 14)
          rend.setCursorPosition(pos)

          let (x, y) = rend.getCursorPosition()
          check x == 7
          check y == 14
        except TerminalError:
          skip()

    suite "Async Rendering Operations":
      test "renderAsync does not crash":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          rend.setString(0, 0, "Test", defaultStyle())

          waitFor rend.renderAsync()
        except TerminalError:
          skip()

      test "renderAsync with force flag":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          rend.setString(0, 0, "Test", defaultStyle())
          waitFor rend.renderAsync(force = true)
        except TerminalError:
          skip()

      test "forceRenderAsync":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          rend.setString(0, 0, "Test", defaultStyle())
          waitFor rend.forceRenderAsync()
        except TerminalError:
          skip()

      test "renderDiffAsync":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          rend.setString(0, 0, "Test", defaultStyle())
          waitFor rend.renderDiffAsync()
        except TerminalError:
          skip()

    suite "Integration Tests":
      test "Full async render cycle":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          rend.clear()

          rend.setString(0, 0, "Line 1", style(Red))
          rend.setString(0, 1, "Line 2", style(Green))
          rend.setString(0, 2, "Line 3", style(Blue))

          rend.showCursorAt(0, 3)

          waitFor rend.renderAsync()

          var buf = rend.getBuffer()
          let cell0 = buf[0, 0]
          let cell1 = buf[0, 1]
          let cell2 = buf[0, 2]

          check cell0.symbol.len > 0
          check cell1.symbol.len > 0
          check cell2.symbol.len > 0
        except TerminalError:
          skip()

      test "Multiple async render cycles":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          for i in 0 ..< 5:
            rend.clear()
            rend.setString(0, 0, "Frame " & $i, defaultStyle())
            waitFor rend.renderAsync()
        except TerminalError:
          skip()

      test "Resize and async render":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          rend.setString(0, 0, "Before resize", defaultStyle())
          waitFor rend.renderAsync()

          rend.resize(100, 30)

          rend.clear()
          rend.setString(0, 0, "After resize", defaultStyle())
          waitFor rend.renderAsync()

          var buf = rend.getBuffer()
          check buf.area.width == 100
          check buf.area.height == 30
        except TerminalError:
          skip()

    suite "Edge Cases":
      test "Render with cursor outside buffer":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          var buf = rend.getBuffer()
          rend.setCursorPosition(buf.area.width + 10, buf.area.height + 10)

          waitFor rend.renderAsync()
        except TerminalError:
          skip()

      test "Multiple cursor style changes":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          rend.setCursorStyle(CursorStyle.SteadyBlock)
          waitFor rend.renderAsync()

          rend.setCursorStyle(CursorStyle.SteadyUnderline)
          waitFor rend.renderAsync()

          rend.setCursorStyle(CursorStyle.SteadyBar)
          waitFor rend.renderAsync()

          let cursorMgr = rend.getCursorManager()
          check cursorMgr.getStyle() == CursorStyle.SteadyBar
        except TerminalError:
          skip()

      test "Render empty buffer":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          rend.clear()
          waitFor rend.renderAsync()
        except TerminalError:
          skip()

      test "Zero-size buffer":
        try:
          let term = newAsyncTerminal()
          let rend = newAsyncRenderer(term)

          rend.resize(1, 1)

          rend.setString(0, 0, "X", defaultStyle())
          waitFor rend.renderAsync()

          var buf = rend.getBuffer()
          check buf.area.width == 1
          check buf.area.height == 1
        except TerminalError:
          skip()
