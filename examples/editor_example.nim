import std/[os]
import ../src/celina
import src/[widget, types]

proc main() =
  var app = newApp(
    AppConfig(
      title: "Celina Editor",
      alternateScreen: true,
      mouseCapture: false,
      rawMode: true,
      windowMode: false,
    )
  )

  let config = defaultEditorConfig()
  let editor = newEditorWidget(config)

  if paramCount() > 0:
    let filename = paramStr(1)
    if not editor.loadFile(filename):
      echo "Failed to load file: ", filename
      quit(1)

  app.onEvent proc(event: Event): bool =
    return editor.handleEvent(event)

  app.onRender proc(buffer: var Buffer) =
    editor.render(buffer.area, buffer)

  app.run()

when isMainModule:
  main()
