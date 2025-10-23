import std/unittest

import
  ../celina/core/
    [renderer, terminal, buffer, cursor, geometry, colors, terminal_common, errors]

# Test suite for Renderer module
suite "Renderer Module Tests":
  suite "Renderer Creation":
    test "Create renderer with terminal":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        check rend != nil
        # Renderer should have initialized with terminal size
      except TerminalError:
        # CI environments may not have a real terminal
        skip()

  suite "Buffer Access":
    test "Get buffer from renderer":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        var buf = rend.getBuffer()
        check buf.area.width > 0
        check buf.area.height > 0
      except TerminalError:
        skip()

  suite "Cursor Manager Access":
    test "Get cursor manager from renderer":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        let cursorMgr = rend.getCursorManager()
        check cursorMgr != nil
      except TerminalError:
        skip()

  suite "Renderer Resizing":
    test "Resize renderer with explicit dimensions":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        rend.resize(80, 24)

        var buf = rend.getBuffer()
        check buf.area.width == 80
        check buf.area.height == 24
      except TerminalError:
        skip()

    test "Resize renderer based on terminal size":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        rend.resize()

        var buf = rend.getBuffer()
        let termSize = term.getSize()
        check buf.area.width == termSize.width
        check buf.area.height == termSize.height
      except TerminalError:
        skip()

  suite "Buffer Operations":
    test "Clear renderer buffer":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        var buf = rend.getBuffer()
        buf.setString(0, 0, "Test", defaultStyle())

        rend.clear()

        buf = rend.getBuffer()
        let cell = buf[0, 0]
        # After clear, content should be space or empty
        check cell.symbol.len <= 1
      except TerminalError:
        skip()

    test "Set string in renderer buffer":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        rend.setString(5, 5, "Hello", style(Red))

        var buf = rend.getBuffer()
        let cell = buf[5, 5]
        check cell.symbol.len > 0
      except TerminalError:
        skip()

  suite "Cursor Control via Renderer":
    test "Set cursor position with coordinates":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        rend.setCursor(10, 20)

        let (x, y) = rend.getCursorPos()
        check x == 10
        check y == 20
      except TerminalError:
        skip()

    test "Set cursor position with Position type":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        let pos = Position(x: 15, y: 25)
        rend.setCursor(pos)

        let (x, y) = rend.getCursorPos()
        check x == 15
        check y == 25
      except TerminalError:
        skip()

    test "Show and hide cursor":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        rend.showCursor()
        check rend.isCursorVisible() == true

        rend.hideCursor()
        check rend.isCursorVisible() == false
      except TerminalError:
        skip()

    test "Set cursor style":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        rend.setCursorStyle(CursorStyle.SteadyBlock)

        let cursorMgr = rend.getCursorManager()
        check cursorMgr.getStyle() == CursorStyle.SteadyBlock
      except TerminalError:
        skip()

  suite "Rendering Operations":
    test "Basic render does not crash":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        rend.setString(0, 0, "Test", defaultStyle())

        # This should not crash even in test environment
        # Note: May not actually output to terminal in CI
        rend.render()
      except TerminalError:
        skip()

    test "Render with force flag":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        rend.setString(0, 0, "Test", defaultStyle())
        rend.forceRender()
      except TerminalError:
        skip()

    test "Render diff":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        rend.setString(0, 0, "Test", defaultStyle())
        rend.renderDiff()
      except TerminalError:
        skip()

  suite "Integration Tests":
    test "Full render cycle":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        # Clear buffer
        rend.clear()

        # Add some content
        rend.setString(0, 0, "Line 1", style(Red))
        rend.setString(0, 1, "Line 2", style(Green))
        rend.setString(0, 2, "Line 3", style(Blue))

        # Set cursor
        rend.setCursor(0, 3)
        rend.showCursor()

        # Render
        rend.render()

        # Verify buffer state
        var buf = rend.getBuffer()
        let cell0 = buf[0, 0]
        let cell1 = buf[0, 1]
        let cell2 = buf[0, 2]

        check cell0.symbol.len > 0
        check cell1.symbol.len > 0
        check cell2.symbol.len > 0
      except TerminalError:
        skip()

    test "Multiple render cycles":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        for i in 0 ..< 5:
          rend.clear()
          rend.setString(0, 0, "Frame " & $i, defaultStyle())
          rend.render()

        # Should complete without crashing
      except TerminalError:
        skip()

    test "Resize and render":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        # Initial render
        rend.setString(0, 0, "Before resize", defaultStyle())
        rend.render()

        # Resize
        rend.resize(100, 30)

        # Render after resize
        rend.clear()
        rend.setString(0, 0, "After resize", defaultStyle())
        rend.render()

        var buf = rend.getBuffer()
        check buf.area.width == 100
        check buf.area.height == 30
      except TerminalError:
        skip()

  suite "Edge Cases":
    test "Render with cursor outside buffer":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        var buf = rend.getBuffer()
        rend.setCursor(buf.area.width + 10, buf.area.height + 10)

        # Should not crash even with invalid cursor position
        rend.render()
      except TerminalError:
        skip()

    test "Multiple cursor style changes":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        rend.setCursorStyle(CursorStyle.SteadyBlock)
        rend.render()

        rend.setCursorStyle(CursorStyle.SteadyUnderline)
        rend.render()

        rend.setCursorStyle(CursorStyle.SteadyBar)
        rend.render()

        let cursorMgr = rend.getCursorManager()
        check cursorMgr.getStyle() == CursorStyle.SteadyBar
      except TerminalError:
        skip()

    test "Render empty buffer":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        rend.clear()
        rend.render()
        # Should handle empty buffer gracefully
      except TerminalError:
        skip()

    test "Zero-size buffer":
      try:
        let term = newTerminal()
        let rend = newRenderer(term)

        # Try to resize to very small dimensions
        rend.resize(1, 1)

        rend.setString(0, 0, "X", defaultStyle())
        rend.render()

        var buf = rend.getBuffer()
        check buf.area.width == 1
        check buf.area.height == 1
      except TerminalError:
        skip()
