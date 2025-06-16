## Basic Hello World Example
##
## This example demonstrates the simplest possible TUI application using Celina.
## It displays "Hello World!" in the center of the terminal and exits when 'q' is pressed.

import ../src/celina

proc main() =
  ## Simple hello world TUI application
  quickRun(
    eventHandler = proc(event: Event): bool =
      case event.kind
      of EventKind.Key:
        if event.key.code == KeyCode.Char and event.key.char == 'q':
          return false # Quit application
        elif event.key.code == KeyCode.Escape:
          return false # Quit on escape
      else:
        discard
      return true # Continue running
    ,
    renderHandler = proc(buffer: var Buffer) =
      buffer.clear()

      # Get buffer dimensions
      let area = buffer.area
      let message = "Hello World!"

      # Calculate center position
      let centerX = area.width div 2 - message.len div 2
      let centerY = area.height div 2

      # Draw the message
      buffer.setString(
        centerX, centerY, message, style(Color.Green, modifiers = {Bold})
      )

      # Add instruction text
      let instruction = "Press 'q' or ESC to quit"
      let instrX = area.width div 2 - instruction.len div 2
      buffer.setString(instrX, centerY + 2, instruction, style(Color.BrightBlack)),
  )

when isMainModule:
  echo "Starting Hello World example..."
  echo "Press 'q' or ESC to quit"
  main()
