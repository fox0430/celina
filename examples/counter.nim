## Interactive Counter Example
##
## This example demonstrates a simple interactive counter that responds to key presses.
## Use arrow keys or +/- to increment/decrement the counter.

import ../src/celina

type CounterApp = object
  counter: int

proc main() =
  var appState = CounterApp(counter: 0)

  quickRun(
    eventHandler = proc(event: Event): bool =
      case event.kind
      of EventKind.Key:
        case event.key.code
        of KeyCode.Char:
          case event.key.char
          of 'q':
            return false # Quit
          of '+', '=':
            inc appState.counter
          of '-', '_':
            dec appState.counter
          of 'r':
            appState.counter = 0 # Reset
          else:
            discard
        of KeyCode.Escape:
          return false
        of KeyCode.ArrowUp:
          inc appState.counter
        of KeyCode.ArrowDown:
          dec appState.counter
        of KeyCode.Space:
          inc appState.counter
        else:
          discard
      else:
        discard
      return true,
    renderHandler = proc(buffer: var Buffer) =
      buffer.clear()

      let area = buffer.area
      let centerX = area.width div 2
      let centerY = area.height div 2

      # Draw title
      let title = "Interactive Counter"
      buffer.setString(
        centerX - title.len div 2,
        centerY - 3,
        title,
        style(Color.Cyan, modifiers = {Bold, Underline}),
      )

      # Draw counter value
      let counterText = $appState.counter
      let counterColor =
        if appState.counter > 0:
          Color.Green
        elif appState.counter < 0:
          Color.Red
        else:
          Color.White

      buffer.setString(
        centerX - counterText.len div 2,
        centerY,
        counterText,
        style(counterColor, modifiers = {Bold}),
      )

      # Draw instructions
      let instructions = [
        "Controls:", "↑/↓ or +/- : Increment/Decrement", "Space      : Increment",
        "r          : Reset to zero", "q/ESC      : Quit",
      ]

      for i, instruction in instructions:
        let instrColor = if i == 0: Color.Yellow else: Color.BrightBlack
        let instrStyle =
          if i == 0:
            {Bold}
          else:
            {}

        buffer.setString(
          centerX - instruction.len div 2,
          centerY + 3 + i,
          instruction,
          style(instrColor, modifiers = instrStyle),
        ),
  )

when isMainModule:
  echo "Starting Counter example..."
  echo "Use arrow keys, +/-, or space to change the counter"
  echo "Press 'r' to reset, 'q' or ESC to quit"
  main()
