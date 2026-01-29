## App Module
## ==========
##
## Core application management, lifecycle, and event loop handling.
## Provides the main App type and orchestrates all components.

import std/[options, monotimes]

import
  terminal, buffer, events, renderer, fps, cursor, geometry, errors, terminal_common,
  windows, config, tick_common

export config

type App* = ref object ## Main application context for CLI applications
  terminal: Terminal
  renderer: Renderer
  fpsMonitor: FpsMonitor
  windowManager: WindowManager
  shouldQuit: bool
  eventHandler: proc(event: Event): bool
  eventHandlerWithApp: proc(event: Event, app: App): bool
  renderHandler: proc(buffer: var Buffer)
  windowMode: bool
  config: AppConfig
  resizeState: ResizeState ## Shared resize detection state (from tick_common)
  forceNextRender: bool ## Force full render on next frame (used after resize)
  running: bool ## Whether app is currently running
  frameCounter: int ## Total frame count
  lastFrameTime: MonoTime ## Timestamp of last frame

proc newApp*(config: AppConfig = DefaultAppConfig): App =
  ## Create a new CLI application with the specified configuration
  let terminal = newTerminal()
  result = App(
    terminal: terminal,
    renderer: newRenderer(terminal),
    fpsMonitor: newFpsMonitor(if config.targetFps > 0: config.targetFps else: 60),
    shouldQuit: false,
    eventHandler: nil,
    eventHandlerWithApp: nil,
    renderHandler: nil,
    windowMode: config.windowMode,
    config: config,
    resizeState: initResizeState(events.getResizeCounter()),
    forceNextRender: false,
    running: false,
    frameCounter: 0,
    lastFrameTime: getMonoTime(),
  )

  # Initialize window manager if enabled
  if config.windowMode:
    result.windowManager = newWindowManager()

# Event and render handlers
proc onEvent*(app: App, handler: proc(event: Event): bool) =
  ## Set the event handler for the application
  ##
  ## For access to the App object (e.g., for suspend/resume), use the
  ## overload that accepts `proc(event: Event, app: App): bool` instead.
  app.eventHandler = handler
  app.eventHandlerWithApp = nil

proc onEvent*(app: App, handler: proc(event: Event, app: App): bool) =
  ## Set the event handler with App context for the application
  ##
  ## This overload provides access to the App object, enabling features like
  ## suspend/resume for shell command execution.
  ##
  ## Example:
  ## ```nim
  ## app.onEvent proc(event: Event, app: App): bool =
  ##   if event.kind == Key and event.key.char == "!":
  ##     app.withSuspend:
  ##       discard execShellCmd("ls -la")
  ##       echo "Press Enter..."
  ##       discard stdin.readLine()
  ##     return true
  ##   return true
  ## ```
  app.eventHandlerWithApp = handler
  app.eventHandler = nil

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

  if app.config.bracketedPaste:
    app.terminal.enableBracketedPaste()

  if app.config.focusEvents:
    app.terminal.enableFocusEvents()

  terminal.hideCursor()
  terminal.clearScreen()

proc cleanup(app: App) =
  ## Internal cleanup procedure to restore terminal state
  terminal.showCursor()

  if app.config.focusEvents:
    app.terminal.disableFocusEvents()

  if app.config.bracketedPaste:
    app.terminal.disableBracketedPaste()

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
  # Clear screen to avoid artifacts from old content
  terminal.clearScreen()
  # Force full render on next frame to ensure clean redraw
  app.forceNextRender = true

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

  # Render to terminal (force if requested after resize)
  if app.forceNextRender:
    app.renderer.render(force = true)
    app.forceNextRender = false
  else:
    app.renderer.render()

proc dispatchEvent(app: App, event: Event): bool =
  ## Helper to dispatch event to the appropriate handler
  if app.eventHandlerWithApp != nil:
    app.eventHandlerWithApp(event, app)
  elif app.eventHandler != nil:
    app.eventHandler(event)
  else:
    true

proc tick(app: App): bool =
  ## Process one application tick (events + render).
  ##
  ## This method:
  ##   1. Checks for resize events
  ##   2. Calculates time remaining until next render
  ##   3. Polls for input events with timeout = remaining time
  ##   4. Processes events (max per tick defined in tick_common)
  ##   5. Renders only if target FPS interval reached
  ##
  ## See tick_common module for details on CPU efficiency and FPS control.
  ##
  ## Returns:
  ##   true to continue running, false to exit the application loop
  try:
    # Check for resize event using shared counter-based detection
    if app.resizeState.checkResize(events.getResizeCounter()):
      let resizeEvent = Event(kind: Resize)
      app.handleResize()

      # Pass resize event to user handler
      if not app.dispatchEvent(resizeEvent):
        return false

    # Calculate remaining time until next render (used as poll timeout)
    let remainingTime = app.fpsMonitor.getRemainingFrameTime()

    # Poll for events with timeout - blocks until event arrives OR timeout expires
    if events.pollEvents(remainingTime):
      var eventCount = 0

      while eventCount < maxEventsPerTick:
        let eventOpt = events.readKeyInput()
        if eventOpt.isSome():
          let event = eventOpt.get
          eventCount.inc()

          # User event handler first
          if not app.dispatchEvent(event):
            return false

          # Window manager event handling
          if app.windowMode and not app.windowManager.isNil:
            discard app.windowManager.handleEvent(event)
        else:
          break

    # Render only if enough time has passed for target FPS
    if app.fpsMonitor.shouldRender():
      app.fpsMonitor.startFrame()
      app.render()
      app.fpsMonitor.endFrame()
      app.frameCounter.inc()
      app.lastFrameTime = getMonoTime()

    return not app.shouldQuit
  except TerminalError:
    raise
  except CatchableError:
    return false

proc run*(app: App) =
  ## Run the application main loop
  try:
    app.setup()
    app.running = true

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
    app.running = false
    try:
      app.cleanup()
    except CatchableError:
      discard

proc quit*(app: App) =
  ## Signal the application to quit gracefully
  app.shouldQuit = true

# Suspend/Resume for shell command execution
proc suspend*(app: App) =
  ## Temporarily suspend the TUI, restoring normal terminal mode.
  ##
  ## Use this to run shell commands or interact with the terminal normally.
  ## Call `resume()` to return to TUI mode.
  ##
  ## Example:
  ## ```nim
  ## app.suspend()
  ## discard execShellCmd("vim myfile.txt")
  ## app.resume()
  ## ```
  app.terminal.suspend()

proc resume*(app: App) =
  ## Resume the TUI after a `suspend()` call.
  ##
  ## Restores terminal state and forces a full redraw on the next frame.
  app.terminal.resume()
  app.forceNextRender = true

proc isSuspended*(app: App): bool =
  ## Check if the application is currently suspended
  app.terminal.isSuspended

template withSuspend*(app: App, body: untyped) =
  ## Suspend the TUI, execute body, then resume.
  ##
  ## This is the recommended way to run shell commands as it ensures
  ## `resume()` is always called, even if an exception occurs.
  ##
  ## Example:
  ## ```nim
  ## app.withSuspend:
  ##   let exitCode = execShellCmd("git commit")
  ##   echo "Press Enter to continue..."
  ##   discard stdin.readLine()
  ## ```
  app.suspend()
  try:
    body
  finally:
    app.resume()

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

proc removeWindow*(app: App, windowId: WindowId): bool =
  ## Remove a window from the application
  ## Returns true if the window was found and removed, false otherwise
  if app.windowMode and not app.windowManager.isNil:
    return app.windowManager.removeWindow(windowId)

proc getWindow*(app: App, windowId: WindowId): Option[Window] =
  ## Get a window by ID
  if app.windowMode and not app.windowManager.isNil:
    return app.windowManager.getWindow(windowId)
  return none(Window)

proc focusWindow*(app: App, windowId: WindowId): bool =
  ## Focus a specific window
  ## Returns true if the window was found and focused, false otherwise
  if app.windowMode and not app.windowManager.isNil:
    return app.windowManager.focusWindow(windowId)

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

# State and info queries

proc isRunning*(app: App): bool =
  ## Check if app is currently running
  app.running

proc getTerminalSize*(app: App): Size =
  ## Get current terminal size
  app.terminal.getSize()

proc getConfig*(app: App): AppConfig =
  ## Get the stored configuration
  app.config

proc getFrameCount*(app: App): int =
  ## Get total frame count
  app.frameCounter

proc getLastFrameTime*(app: App): MonoTime =
  ## Get timestamp of last frame
  app.lastFrameTime

# Convenience functions

proc quickRun*(
    eventHandler: proc(event: Event): bool,
    renderHandler: proc(buffer: var Buffer),
    config: AppConfig = DefaultAppConfig,
) =
  ## Quick way to run a simple CLI application
  ##
  ## Example:
  ## ```nim
  ## quickRun(
  ##   eventHandler = proc(event: Event): bool =
  ##     case event.kind
  ##     of EventKind.Key:
  ##       if event.key.code == KeyCode.Char and event.key.char == "q":
  ##         return false
  ##     else: discard
  ##     return true,
  ##
  ##   renderHandler = proc(buffer: var Buffer) =
  ##     buffer.setString(10, 5, "Press 'q' to quit", defaultStyle())
  ## )
  ## ```
  var app = newApp(config)
  app.onEvent(eventHandler)
  app.onRender(renderHandler)
  app.run()
