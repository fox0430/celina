## Async Hello World Example
## =====================================================

import ../src/celina

when not defined(asyncBackend) or asyncBackend != "chronos":
  {.fatal: "This example require `-d:asyncBackend=chronos`".}

proc main() {.async.} =
  # Configure the async app
  let config = AsyncAppConfig(
    title: "Async Hello World",
    alternateScreen: true,
    mouseCapture: false,
    rawMode: true,
    windowMode: false,
    targetFps: 60,
  )

  # Create the async app
  var app = newAsyncApp(config)

  # Set up async event handler
  app.onEventAsync proc(event: Event): Future[bool] {.async.} =
    case event.kind
    of EventKind.Key:
      case event.key.code
      of KeyCode.Char:
        if event.key.char == 'q':
          return false # Quit on 'q'
      of KeyCode.Escape:
        return false # Quit on Escape
      else:
        discard
    else:
      discard
    return true # Continue running

  # Set up async render handler
  app.onRenderAsync proc(buffer: async_buffer.AsyncBuffer): Future[void] {.async.} =
    # Clear the buffer
    await buffer.clearAsync()

    # Get the buffer area
    let area = buffer.getArea()

    # Text to display
    let
      title = "🚀 Async Hello World!"
      instructions = "Press 'q' or ESC to quit"

    # Calculate positions for center alignment
    let
      centerX = area.width div 2
      centerY = area.height div 2

    # Draw title with green color
    buffer.setString(
      centerX - title.len div 2,
      centerY - 2,
      title,
      style(fg = Color.Green, modifiers = {StyleModifier.Bold}),
    )

    # Draw instructions with gray color
    buffer.setString(
      centerX - instructions.len div 2,
      centerY,
      instructions,
      style(fg = Color.BrightBlack, modifiers = {StyleModifier.Italic}),
    )

  # Run the async application
  await app.runAsync(config)

when isMainModule:
  # Run the async main function
  waitFor main()
