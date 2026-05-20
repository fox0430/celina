## Async Hello World Example
##
## `nimble install chronos`
## `nim c -d:asyncBackend=chronos examples/async_hello_world.nim`

import pkg/celina

when not hasAsyncSupport and not hasAsyncDispatch and not hasChronos:
  {.fatal: "This example require `-d:asyncBackend=asyncdispatch|chronos`".}

proc main() {.async.} =
  # Configure the async app. With the chronos backend on POSIX,
  # `installSignalHandler: true` installs SIGINT/SIGTERM handlers that
  # call `shutdownAsync` and restore the terminal on exit. Ignored
  # under asyncdispatch and on non-POSIX platforms.
  let config = AppConfig(
    title: "Async Hello World",
    alternateScreen: true,
    mouseCapture: false,
    rawMode: true,
    windowMode: false,
    targetFps: 60,
    installSignalHandler: true,
  )

  # Create the async app
  var app = newAsyncApp(config)

  # Set up async event handler
  app.onEventAsync proc(event: Event): Future[EventResult] {.async.} =
    case event.kind
    of EventKind.Key:
      case event.key.code
      of KeyCode.Char:
        if event.key.char == "q":
          return erQuit # Quit on 'q'
      of KeyCode.Escape:
        return erQuit # Quit on Escape
      else:
        discard
    else:
      discard
    return erContinue # Continue running

  # Set up render handler
  app.onRenderAsync proc(buffer: var Buffer) =
    # Clear the buffer
    buffer.clear()

    # Get the buffer area
    let area = buffer.area

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

  # Run the async application (uses config from newAsyncApp)
  await app.runAsync()

when isMainModule:
  # Run the async main function
  waitFor main()
