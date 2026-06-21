# Panel Demo
##
## Demonstrates the Panel framing widget: borders on different sides, border
## kinds, titles with alignment, padding, fill, and hosting a child widget.

import ../celina
import ../celina/widgets/[panel, text]

proc main() =
  let config = AppConfig(
    title: "Panel Demo",
    alternateScreen: true,
    mouseCapture: false,
    rawMode: true,
    targetFps: 30,
  )

  var app = newApp(config)

  app.onEvent(
    proc(event: Event): EventResult =
      if event.kind == EventKind.Key:
        case event.key.code
        of KeyCode.Char:
          if event.key.char in ["q", "Q"]:
            return erQuit
        of KeyCode.Escape:
          return erQuit
        else:
          discard
      return erContinue
  )

  app.onRender(
    proc(buffer: var Buffer) =
      buffer.clear()

      buffer.setString(
        2, 0, "Panel Demo — press q to quit", style(Cyan, Reset, {Bold})
      )

      # Single border with a left-aligned title, hosting a text child.
      let single = newPanel(
        borderKind = bkSingle,
        title = "Single",
        child = newText("Single-line border\nwith a child widget"),
      )
      single.render(rect(2, 2, 30, 6), buffer)

      # Rounded border, centered title, colored border, padded content.
      let rounded = newPanel(
        borderKind = bkRounded,
        title = "Rounded",
        titleAlignment = taCenter,
        borderStyle = style(Green),
        padding = padding(2, 1),
        child = newText("Padded content"),
      )
      rounded.render(rect(34, 2, 30, 6), buffer)

      # Double border, right-aligned title with a filled background.
      let double = newPanel(
        borderKind = bkDouble,
        title = "Double",
        titleAlignment = taRight,
        titleStyle = style(Yellow, Reset, {Bold}),
        style = style(White, Blue),
        child = newText("Filled background"),
      )
      double.render(rect(2, 9, 30, 6), buffer)

      # Only top and bottom borders (a horizontal rule frame).
      let rule = newPanel(
        borders = {bsTop, bsBottom},
        title = "Top & bottom only",
        child = newText("No side borders"),
      )
      rule.render(rect(34, 9, 30, 6), buffer)
  )

  app.run()

when isMainModule:
  main()
