## Window Management Demo
##
## This example demonstrates multiple window functionality.

import ../src/celina
import std/[strformat, options]

type AppState = ref object
  windowIds: seq[WindowId]
  currentWindow: int

proc main() =
  let state = AppState(windowIds: @[], currentWindow: 0)

  var app = newApp(
    AppConfig(
      title: "Celina Multi-Window Demo",
      alternateScreen: true,
      rawMode: true,
      windowMode: true, # Enable window management
    )
  )

  # Create main window
  let mainWindow = newWindow(rect(10, 5, 50, 13), "Demo Window")
  mainWindow.buffer.setString(
    2, 2, "Multi Window Demo", style(fg = Color.Cyan, modifiers = {Bold})
  )
  mainWindow.buffer.setString(2, 4, "This is a simple window demonstration.")
  mainWindow.buffer.setString(2, 5, "q - Quit application")
  let mainId = app.addWindow(mainWindow)
  state.windowIds.add(mainId)

  # Create info window (overlapping)
  let infoWindow =
    newWindow(rect(40, 15, 35, 10), "Info Window", resizable = true, movable = true)
  infoWindow.buffer.setString(
    2, 2, "Information Panel", style(fg = Color.Yellow, modifiers = {Bold})
  )
  infoWindow.buffer.setString(2, 4, "Features:")
  infoWindow.buffer.setString(4, 5, "• Multiple windows")
  infoWindow.buffer.setString(4, 6, "• Focus management")
  infoWindow.buffer.setString(4, 7, "• Z-order rendering")
  let infoId = app.addWindow(infoWindow)
  state.windowIds.add(infoId)

  let # Create status window (no border) - positioned below other windows

    statusWindow = newWindow(
      rect(5, 28, 40, 3),
      "",
      border = none(WindowBorder),
      resizable = false,
      movable = false,
    )
  statusWindow.buffer.setString(0, 0, "Status: Ready", style(fg = Color.Green))
  statusWindow.buffer.setString(0, 1, "Windows: 3")
  let statusId = app.addWindow(statusWindow)
  state.windowIds.add(statusId)

  app.onEvent proc(event: Event): bool =
    case event.kind
    of EventKind.Key:
      case event.key.code
      of KeyCode.Tab:
        # Cycle through windows
        if state.windowIds.len > 0:
          state.currentWindow = (state.currentWindow + 1) mod state.windowIds.len
          app.focusWindow(state.windowIds[state.currentWindow])
        return true
      of KeyCode.Char:
        if event.key.char == 'q':
          return false # Quit
      of KeyCode.Escape:
        return false # Quit
      else:
        discard
    else:
      discard
    return true

  app.onRender proc(buffer: var Buffer) =
    # Draw simple background without pattern that interferes with windows
    # Just draw title
    let title = "Celina Multi-Window Demo - Tab to cycle"
    let titleX = max(0, (buffer.area.width - title.len) div 2)
    buffer.setString(titleX, 1, title, style(fg = Color.White, modifiers = {Bold}))

  # Run the application
  app.run()

when isMainModule:
  main()
