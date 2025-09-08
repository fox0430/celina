## Button Demo
##
## A example demonstrating basic button functionality

import pkg/celina
import pkg/celina/widgets/button

proc main() =
  var clickCount = 0

  # Create a simple button with better sizing
  var btn = newButton(
    "    Click Here!    ",
    normalStyle = style(White, Blue),
    hoveredStyle = style(White, Cyan),
    pressedStyle = style(Black, White),
    focusedStyle = style(Yellow, Blue),
    minWidth = 20,
    padding = 2,
  )
  btn.onClick = proc() =
    clickCount.inc()

  let config = AppConfig(
    title: "Button Demo", alternateScreen: true, mouseCapture: true, rawMode: true
  )

  var app = newApp(config)

  # Store button position and size for consistent handling
  let buttonWidth = 24
  let buttonHeight = 3
  var lastBufferWidth = 80
  var lastBufferHeight = 24

  # Start with button focused for keyboard interaction
  btn.setState(Focused)

  app.onEvent proc(event: Event): bool =
    case event.kind
    of EventKind.Key:
      case event.key.code
      of KeyCode.Escape:
        return false
      of KeyCode.Char:
        if event.key.char == 'q':
          return false
      of KeyCode.Enter, KeyCode.Space:
        # Button-specific activation keys
        discard btn.handleKeyEvent(event.key)
      else:
        # Other keys can be handled here if needed
        discard
    of EventKind.Mouse:
      # Calculate button position based on last known buffer size
      let btnX = (lastBufferWidth - buttonWidth) div 2
      let btnY = (lastBufferHeight - buttonHeight) div 2
      let btnArea = rect(btnX, btnY, buttonWidth, buttonHeight)

      if btn.handleMouseEvent(event.mouse, btnArea):
        # Button handled the event
        discard
    of EventKind.Resize:
      # Window was resized, we'll update on next render
      discard
    else:
      discard
    return true

  app.onRender proc(buffer: var Buffer) =
    buffer.clear()
    let area = buffer.area

    # Update last known buffer size for mouse handling
    lastBufferWidth = area.width
    lastBufferHeight = area.height

    # Calculate center position for the button
    let btnX = (area.width - buttonWidth) div 2
    let btnY = (area.height - buttonHeight) div 2

    # Render centered button
    let btnArea = rect(btnX, btnY, buttonWidth, buttonHeight)
    btn.render(btnArea, buffer)

    # Show click count below the button
    let countText = "Click count: " & $clickCount
    let countX = (area.width - countText.len) div 2
    buffer.setString(countX, btnY + buttonHeight + 2, countText, defaultStyle())

    # Show instructions at the bottom
    let instructions = "Press Space/Enter to click, Q or Escape to quit"
    let instrX = (area.width - instructions.len) div 2
    buffer.setString(instrX, area.height - 2, instructions, style(BrightBlack))

  app.run()

when isMainModule:
  main()
