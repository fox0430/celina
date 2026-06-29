# Scrollbar Demo
##
## Demonstrates the standalone Scrollbar widget driving a scrollable text
## viewport: arrow keys / j,k scroll, PageUp/PageDown jump a page, mouse wheel
## and clicking the bar work too. The scrollbar is rendered on the right edge
## of the content panel and kept in sync with the scroll offset.

import std/strformat

import pkg/celina
import pkg/celina/widgets/[panel, scrollbar]

proc main() =
  let config = AppConfig(
    title: "Scrollbar Demo",
    alternateScreen: true,
    mouseCapture: true,
    rawMode: true,
    targetFps: 30,
  )

  var app = newApp(config)

  # The content: 100 numbered lines.
  var lines: seq[string] = @[]
  for i in 1 .. 100:
    lines.add(&"Line {i:>3} — the quick brown fox jumps over the lazy dog")

  var offset = 0
  const viewport = 16

  let bar = newScrollbar(
      sbVerticalRight, contentLength = lines.len, viewportLength = viewport
    )
    .withSymbols(`begin` = "▲", `end` = "▼")

  proc maxOffset(): int =
    max(0, lines.len - viewport)

  app.onEvent(
    proc(event: Event): EventResult =
      case event.kind
      of EventKind.Key:
        case event.key.code
        of KeyCode.Char:
          case event.key.char
          of "q", "Q":
            return erQuit
          of "j":
            offset = min(maxOffset(), offset + 1)
          of "k":
            offset = max(0, offset - 1)
          else:
            discard
        of KeyCode.Escape:
          return erQuit
        of KeyCode.ArrowDown:
          offset = min(maxOffset(), offset + 1)
        of KeyCode.ArrowUp:
          offset = max(0, offset - 1)
        of KeyCode.PageDown:
          offset = min(maxOffset(), offset + viewport)
        of KeyCode.PageUp:
          offset = max(0, offset - viewport)
        of KeyCode.Home:
          offset = 0
        of KeyCode.End:
          offset = maxOffset()
        else:
          discard
        return erContinue
      of EventKind.Mouse:
        # Let the scrollbar react to wheel/click, then read back its position.
        bar.position = offset
        let frame = rect(2, 2, 64, viewport + 2)
        let inner = newPanel(borderKind = bkRounded).inner(frame)
        discard bar.handleMouseEvent(event.mouse, inner)
        offset = bar.position
        return erContinue
      else:
        return erContinue
  )

  app.onRender(
    proc(buffer: var Buffer) =
      buffer.clear()

      buffer.setString(
        2,
        0,
        "Scrollbar Demo — ↑/↓ j/k scroll, PgUp/PgDn page, wheel/click, q to quit",
        style(Cyan, Reset, {Bold}),
      )

      let frame = rect(2, 2, 64, viewport + 2)
      let outer = newPanel(
        borderKind = bkRounded,
        title = &"Lines {offset + 1}-{min(offset + viewport, lines.len)} / {lines.len}",
      )
      outer.render(frame, buffer)

      let content = outer.inner(frame)
      # Reserve the rightmost column for the scrollbar.
      let textArea = rect(content.x, content.y, content.width - 1, content.height)
      for row in 0 ..< textArea.height:
        let idx = offset + row
        if idx >= lines.len:
          break
        buffer.setString(textArea.x, textArea.y + row, lines[idx])

      let barArea = rect(content.x, content.y, content.width, content.height)
      bar.withPosition(offset).render(barArea, buffer)
  )

  app.run()

when isMainModule:
  main()
