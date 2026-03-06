# Simple hello world example for Celina

import pkg/celina

proc main() =
  # Create a new application instance
  var app = newApp()

  # Set up the render handler - called each frame to draw the UI
  app.onRender(
    proc(buf: var Buffer) =
      # Center "Hello, World!" message on screen
      buf.setString(
        buf.area,
        "Hello, World!",
        Style(fg: color(Green)),
        hAlign = hCenter,
        vAlign = vMiddle,
      )

      # Add usage hint 2 lines below the main message
      buf.setString(
        rect(0, 2, buf.area.width, buf.area.height),
        "Press 'q' to quit",
        Style(fg: color(BrightBlack)),
        hAlign = hCenter,
        vAlign = vMiddle,
      )
  )

  # Set up the event handler - processes keyboard/mouse input
  app.onEvent(
    proc(event: Event): bool =
      # Check if this is a keyboard event
      if event.kind == EventKind.Key:
        if event.key.code == KeyCode.Char and event.key.char == "q":
          # Quit when 'q' is pressed
          return false # Returning false exits the app
      return true # Continue running for all other events
  )

  # Start the main event loop
  app.run()

when isMainModule:
  main()
