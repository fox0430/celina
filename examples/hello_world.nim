# Simple hello world example for Celina library

import pkg/celina

proc main() =
  # Create a new application instance
  var app = newApp()

  # Set up the render handler - called each frame to draw the UI
  app.onRender(
    proc(buf: var Buffer) =
      # Center "Hello, World!" message on screen
      let msg = "Hello, World!"
      let x = (buf.area.width - msg.len) div 2
      let y = buf.area.height div 2

      # Draw the message in green color
      buf.setString(x, y, msg, Style(fg: color(Green)))

      # Add usage hint below the main message
      let hint = "Press 'q' to quit"
      let hintX = (buf.area.width - hint.len) div 2
      buf.setString(hintX, y + 2, hint, Style(fg: color(BrightBlack)))
  )

  # Set up the event handler - processes keyboard/mouse input
  app.onEvent(
    proc(event: Event): bool =
      # Check if this is a keyboard event
      if event.kind == EventKind.Key:
        # Quit when 'q' is pressed
        if event.key.code == KeyCode.Char and event.key.char == 'q':
          return false # Returning false exits the app
      return true # Continue running for all other events
  )

  # Start the main event loop
  app.run()

when isMainModule:
  main()
