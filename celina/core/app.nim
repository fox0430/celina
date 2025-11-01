## App Module
## ==========
##
## Core application management, lifecycle, and event loop handling.
## Provides the main App type and orchestrates all components.

import std/options

import
  terminal, buffer, events, renderer, fps, cursor, geometry, errors, terminal_common,
  windows

type
  AppConfig* = object ## Application configuration options
    title*: string
    alternateScreen*: bool
    mouseCapture*: bool
    rawMode*: bool
    windowMode*: bool ## Enable window management
    targetFps*: int ## Target FPS for rendering (default: 60)

  App* = ref object ## Main application context for CLI applications
    terminal: Terminal
    renderer: Renderer
    fpsMonitor: FpsMonitor
    windowManager: WindowManager
    shouldQuit: bool
    eventHandler: proc(event: Event): bool
    renderHandler: proc(buffer: var Buffer)
    windowMode: bool
    config: AppConfig

proc newApp*(
    config: AppConfig = AppConfig(
      title: "Celina App",
      alternateScreen: true,
      mouseCapture: false,
      rawMode: true,
      windowMode: false,
      targetFps: 60,
    )
): App =
  ## Create a new CLI application with the specified configuration
  let terminal = newTerminal()
  result = App(
    terminal: terminal,
    renderer: newRenderer(terminal),
    fpsMonitor: newFpsMonitor(if config.targetFps > 0: config.targetFps else: 60),
    shouldQuit: false,
    eventHandler: nil,
    renderHandler: nil,
    windowMode: config.windowMode,
    config: config,
  )

  # Initialize window manager if enabled
  if config.windowMode:
    result.windowManager = newWindowManager()

# Event and render handlers
proc onEvent*(app: App, handler: proc(event: Event): bool) =
  ## Set the event handler for the application
  app.eventHandler = handler

proc onRender*(app: App, handler: proc(buffer: var Buffer)) =
  ## Set the render handler for the application
  app.renderHandler = handler

# Lifecycle management
proc setup(app: App) =
  ## Internal setup procedure to initialize terminal state
  app.terminal.setup()

  if app.config.rawMode:
    app.terminal.enableRawMode()

  if app.config.alternateScreen:
    app.terminal.enableAlternateScreen()

  if app.config.mouseCapture:
    app.terminal.enableMouse()

  terminal.hideCursor()
  terminal.clearScreen()

proc cleanup(app: App) =
  ## Internal cleanup procedure to restore terminal state
  terminal.showCursor()

  if app.config.mouseCapture:
    app.terminal.disableMouse()

  if app.config.alternateScreen:
    app.terminal.disableAlternateScreen()

  if app.config.rawMode:
    app.terminal.disableRawMode()

  app.terminal.cleanup()

proc handleResize(app: App) =
  ## Handle terminal resize events
  app.terminal.updateSize()
  app.renderer.resize()

proc render(app: App) =
  ## Render the current frame
  # Clear the buffer
  app.renderer.clear()

  # Call user render handler first (for background content)
  if app.renderHandler != nil:
    app.renderHandler(app.renderer.getBuffer())

  # If window mode is enabled, render windows on top
  if app.windowMode and not app.windowManager.isNil:
    app.windowManager.render(app.renderer.getBuffer())

  # Render to terminal
  app.renderer.render()

proc tick(app: App): bool =
  ## Process one application tick (events + render)
  try:
    app.fpsMonitor.startFrame()

    # Check for resize event first
    let resizeOpt = events.checkResize()
    if resizeOpt.isSome():
      let resizeEvent = resizeOpt.get
      app.handleResize()

      # Pass resize event to user handler
      if app.eventHandler != nil:
        if not app.eventHandler(resizeEvent):
          return false

    # Event polling with dynamic timeout based on FPS
    let frameTimeout = app.fpsMonitor.getFrameTimeout()

    if events.pollEvents(frameTimeout):
      # Process events in batch
      var eventCount = 0
      const maxEventsPerTick = 5

      while eventCount < maxEventsPerTick:
        let eventOpt = events.readKeyInput()
        if eventOpt.isSome():
          let event = eventOpt.get
          eventCount.inc()

          # User event handler first
          var shouldContinue = true
          if app.eventHandler != nil:
            shouldContinue = app.eventHandler(event)
            if not shouldContinue:
              return false

          # Window manager event handling
          if app.windowMode and not app.windowManager.isNil:
            discard app.windowManager.handleEvent(event)
        else:
          break

    # Always render
    app.render()
    app.fpsMonitor.endFrame()

    return not app.shouldQuit
  except TerminalError:
    raise
  except CatchableError:
    return false

proc run*(app: App) =
  ## Run the application main loop
  try:
    app.setup()

    # Initialize signal handling for resize detection
    events.initSignalHandling()

    # Main application loop
    while app.tick():
      discard
  except TerminalError as e:
    try:
      app.cleanup()
    except:
      discard
    raise e
  except CatchableError as e:
    try:
      app.cleanup()
    except:
      discard
    raise e
  finally:
    try:
      app.cleanup()
    except CatchableError:
      discard

proc quit*(app: App) =
  ## Signal the application to quit gracefully
  app.shouldQuit = true

# FPS control delegation
proc setTargetFps*(app: App, fps: int) =
  ## Set the target FPS for the application
  app.fpsMonitor.setTargetFps(fps)

proc getTargetFps*(app: App): int =
  ## Get the current target FPS
  app.fpsMonitor.getTargetFps()

proc getCurrentFps*(app: App): float =
  ## Get the current actual FPS
  app.fpsMonitor.getCurrentFps()

# Cursor control delegation
proc setCursorPosition*(app: App, x, y: int) =
  ## Set cursor position without changing visibility state
  app.renderer.setCursorPosition(x, y)

proc setCursorPosition*(app: App, pos: Position) =
  ## Set cursor position using Position type without changing visibility
  app.renderer.setCursorPosition(pos)

proc showCursorAt*(app: App, x, y: int) =
  ## Set cursor position and make it visible
  app.renderer.showCursorAt(x, y)

proc showCursorAt*(app: App, pos: Position) =
  ## Set cursor position using Position type and make it visible
  app.renderer.showCursorAt(pos)

proc showCursor*(app: App) =
  ## Show cursor at current position
  app.renderer.showCursor()

proc hideCursor*(app: App) =
  ## Hide cursor
  app.renderer.hideCursor()

proc setCursorStyle*(app: App, style: CursorStyle) =
  ## Set cursor style for next render
  app.renderer.setCursorStyle(style)

proc getCursorPosition*(app: App): (int, int) =
  ## Get current cursor position
  app.renderer.getCursorPosition()

proc moveCursorBy*(app: App, dx, dy: int) =
  ## Move cursor relatively by dx, dy
  let (x, y) = app.getCursorPosition()
  app.setCursorPosition(x + dx, y + dy)

proc isCursorVisible*(app: App): bool =
  ## Check if cursor is visible
  app.renderer.isCursorVisible()

proc getCursorStyle*(app: App): CursorStyle =
  ## Get current cursor style
  app.renderer.getCursorManager().getStyle()

proc resetCursor*(app: App) =
  ## Reset cursor to default state
  app.renderer.getCursorManager().reset()

# Window management
proc enableWindowMode*(app: App) =
  ## Enable window management mode
  app.windowMode = true
  if app.windowManager.isNil:
    app.windowManager = newWindowManager()

proc addWindow*(app: App, window: Window): WindowId =
  ## Add a window to the application
  if not app.windowMode:
    app.enableWindowMode()
  return app.windowManager.addWindow(window)

proc removeWindow*(app: App, windowId: WindowId) =
  ## Remove a window from the application
  if app.windowMode and not app.windowManager.isNil:
    app.windowManager.removeWindow(windowId)

proc getWindow*(app: App, windowId: WindowId): Option[Window] =
  ## Get a window by ID
  if app.windowMode and not app.windowManager.isNil:
    return app.windowManager.getWindow(windowId)
  return none(Window)

proc focusWindow*(app: App, windowId: WindowId) =
  ## Focus a specific window
  if app.windowMode and not app.windowManager.isNil:
    app.windowManager.focusWindow(windowId)

proc getFocusedWindow*(app: App): Option[Window] =
  ## Get the currently focused window
  if app.windowMode and not app.windowManager.isNil:
    return app.windowManager.getFocusedWindow()
  return none(Window)

proc getWindows*(app: App): seq[Window] =
  ## Get all windows in the application
  if app.windowMode and not app.windowManager.isNil:
    return app.windowManager.windows
  return @[]

proc getWindowCount*(app: App): int =
  ## Get the total number of windows
  if app.windowMode and not app.windowManager.isNil:
    return app.windowManager.windows.len
  return 0

proc getFocusedWindowId*(app: App): Option[WindowId] =
  ## Get the ID of the currently focused window
  if app.windowMode and not app.windowManager.isNil:
    return app.windowManager.focusedWindow
  return none(WindowId)

proc getWindowInfo*(app: App, windowId: WindowId): Option[WindowInfo] =
  ## Get window information by ID
  if app.windowMode and not app.windowManager.isNil:
    let windowOpt = app.windowManager.getWindow(windowId)
    if windowOpt.isSome():
      return some(windowOpt.get.toWindowInfo())
  return none(WindowInfo)

proc handleWindowEvent*(app: App, event: Event): bool =
  ## Handle an event through the window manager
  if app.windowMode and not app.windowManager.isNil:
    return app.windowManager.handleEvent(event)
  return false
