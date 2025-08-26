# Example cursor control

import std/strformat

import pkg/celina

const styles = [
  CursorStyle.Default, CursorStyle.BlinkingBlock, CursorStyle.SteadyBlock,
  CursorStyle.BlinkingUnderline, CursorStyle.SteadyUnderline, CursorStyle.BlinkingBar,
  CursorStyle.SteadyBar,
]

const styleNames = [
  "Default", "Blinking Block", "Steady Block", "Blinking Underline", "Steady Underline",
  "Blinking Bar", "Steady Bar",
]

proc main() =
  var cursorX = 37
  var cursorY = 19
  var styleIndex = 0

  var app = newApp()

  # Configure initial cursor
  app.setCursor(cursorX, cursorY)
  app.setCursorStyle(styles[styleIndex])

  # By default, the cursor is hidden
  app.showCursor()

  app.onRender(
    proc(buf: var Buffer) =
      buf.clear()

      # Title
      buf.setString(
        2, 1, "Celina Cursor Demo", Style(fg: color(BrightCyan), modifiers: {Bold})
      )

      # Instructions
      buf.setString(2, 4, "Controls:", Style(fg: color(Yellow)))
      buf.setString(4, 5, "Arrow keys/h, j, k, l: Move cursor", Style(fg: color(White)))
      buf.setString(4, 6, "Space: Change cursor style", Style(fg: color(White)))
      buf.setString(4, 7, "v: Toggle visibility", Style(fg: color(White)))
      buf.setString(4, 8, "q/ESC: Quit", Style(fg: color(White)))

      # Status display
      buf.setString(2, 10, &"Position: ({cursorX}, {cursorY})", Style(fg: color(Cyan)))
      buf.setString(2, 11, &"Style: {styleNames[styleIndex]}", Style(fg: color(Cyan)))
      buf.setString(2, 12, &"Visible: {app.isCursorVisible()}", Style(fg: color(Cyan)))

      # Draw boundary
      for x in 15 .. 60:
        buf.setString(x, 14, "═", Style(fg: color(BrightBlack)))
        buf.setString(x, 24, "═", Style(fg: color(BrightBlack)))
      for y in 14 .. 24:
        buf.setString(15, y, "║", Style(fg: color(BrightBlack)))
        buf.setString(60, y, "║", Style(fg: color(BrightBlack)))

      # Corners
      buf.setString(15, 14, "╔", Style(fg: color(BrightBlack)))
      buf.setString(60, 14, "╗", Style(fg: color(BrightBlack)))
      buf.setString(15, 24, "╚", Style(fg: color(BrightBlack)))
      buf.setString(60, 24, "╝", Style(fg: color(BrightBlack)))

      # Update cursor position only (don't override visibility or style)
      # Position will be applied automatically after buffer rendering
      let (oldX, oldY) = app.getCursorPos()
      if oldX != cursorX or oldY != cursorY:
        app.setCursorPos(cursorX, cursorY) # Use position-only method
  )

  app.onEvent(
    proc(event: Event): bool =
      case event.kind
      of EventKind.Key:
        case event.key.code

        # Movement
        of KeyCode.ArrowLeft:
          if cursorX > 16:
            cursorX -= 1
        of KeyCode.ArrowRight:
          if cursorX < 59:
            cursorX += 1
        of KeyCode.ArrowUp:
          if cursorY > 15:
            cursorY -= 1
        of KeyCode.ArrowDown:
          if cursorY < 23:
            cursorY += 1
        of KeyCode.Space:
          # Space key for cursor style change
          styleIndex = (styleIndex + 1) mod styles.len
          app.setCursorStyle(styles[styleIndex])
        of KeyCode.Char:
          case event.key.char
          of 'v', 'V':
            # Toggle visibility
            if app.isCursorVisible():
              app.hideCursor()
            else:
              app.showCursor()

          # Vim-style movement
          of 'h':
            if cursorX > 16:
              cursorX -= 1
          of 'l':
            if cursorX < 59:
              cursorX += 1
          of 'k':
            if cursorY > 15:
              cursorY -= 1
          of 'j':
            if cursorY < 23:
              cursorY += 1

          # Quit
          of 'q', 'Q':
            return false
          else:
            discard
        of KeyCode.Escape:
          return false
        else:
          discard
      else:
        discard

      return true
  )

  app.run()

when isMainModule:
  main()
