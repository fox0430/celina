## Celina CLI Library
## ==================
##
## A powerful Terminal User Interface library for Nim, inspired by Ratatui.
## Provides high-performance, type-safe components for building interactive
## terminal applications with both synchronous and asynchronous support.
##
## Basic Usage:
## ```nim
## import pkg/celina
##
## proc main() =
##   var app = newApp()
##   app.run()
##
## when isMainModule:
##   main()
## ```
##
## Async Usage (requires Chronos and `-d:asyncBackend=chronos`):
## ```nim
## import pkg/celina
##
## proc main() {.async.} =
##   var app = newAsyncApp()
##   await app.runAsync()
##
## when isMainModule:
##   waitFor main()
## ```

import std/[options, unicode, times]

import
  celina/core/[
    geometry, colors, buffer, events, terminal, layout, errors, resources,
    terminal_common,
  ]
import celina/widgets/[text, base, windows]
import celina/async/async_backend

export
  geometry, colors, buffer, events, layout, terminal, windows, text, base, unicode,
  errors, resources, async_backend, hasAsyncSupport, hasChronos, hasAsyncDispatch,
  terminal_common

# ============================================================================
# Synchronous API
# ============================================================================

type
  ## Main application context for CLI applications
  App* = ref object
    terminal: Terminal
    buffer: Buffer
    windowManager: WindowManager
    shouldQuit: bool
    eventHandler: proc(event: Event): bool
    renderHandler: proc(buffer: var Buffer)
    windowMode: bool ## Whether to use window management
    targetFps: int ## Current target FPS
    frameCounter: int ## Frame counter for FPS calculation
    lastFpsTime: float ## Last time FPS was calculated
    cursor: CursorState ## Cursor state management

  ## Application configuration options
  AppConfig* = object
    title*: string
    alternateScreen*: bool
    mouseCapture*: bool
    rawMode*: bool
    windowMode*: bool ## Enable window management
    targetFps*: int ## Target FPS for rendering (default: 60)

# ============================================================================
# App Creation and Configuration
# ============================================================================

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
  ##
  ## Example:
  ## ```nim
  ## let config = AppConfig(
  ##   title: "My App",
  ##   alternateScreen: true,
  ##   mouseCapture: true
  ## )
  ## var app = newApp(config)
  ## ```
  result = App(
    terminal: newTerminal(),
    shouldQuit: false,
    eventHandler: nil,
    renderHandler: nil,
    windowMode: config.windowMode,
    targetFps: if config.targetFps > 0: config.targetFps else: 60,
    frameCounter: 0,
    lastFpsTime: epochTime(),
    cursor: CursorState(
      x: -1, # -1 means not set
      y: -1, # -1 means not set
      visible: false, # Hidden by default
      style: CursorStyle.Default,
      lastStyle: CursorStyle.Default,
    ),
  )

  # Initialize buffer based on terminal size
  let termSize = result.terminal.getSize()
  result.buffer = newBuffer(termSize.width, termSize.height)

  # Initialize window manager if enabled
  if config.windowMode:
    result.windowManager = newWindowManager()

proc onEvent*(app: App, handler: proc(event: Event): bool) =
  ## Set the event handler for the application
  ##
  ## The handler should return true if the event was handled,
  ## false if the application should quit.
  ##
  ## Example:
  ## ```nim
  ## app.onEvent proc(event: Event): bool =
  ##   case event.kind
  ##   of EventKind.Key:
  ##     if event.key.code == KeyCode.Char and event.key.char == 'q':
  ##       return false  # Quit application
  ##     elif event.key.code == KeyCode.Escape:
  ##       return false  # Quit on escape
  ##   else:
  ##     discard
  ##   return true  # Continue running
  ## ```
  app.eventHandler = handler

proc onRender*(app: App, handler: proc(buffer: var Buffer)) =
  ## Set the render handler for the application
  ##
  ## This handler is called each frame to update the display buffer.
  ##
  ## Example:
  ## ```nim
  ## app.onRender proc(buffer: var Buffer) =
  ##   buffer.clear()
  ##   let area = buffer.area
  ##   let centerX = area.width div 2 - 5  # Center "Hello!"
  ##   let centerY = area.height div 2
  ##   buffer.setString(centerX, centerY, "Hello!", defaultStyle())
  ## ```
  app.renderHandler = handler

# ============================================================================
# App Lifecycle Management
# ============================================================================

proc setup(app: App, config: AppConfig) =
  ## Internal setup procedure to initialize terminal state
  app.terminal.setup()

  if config.rawMode:
    app.terminal.enableRawMode()

  if config.alternateScreen:
    app.terminal.enableAlternateScreen()

  if config.mouseCapture:
    app.terminal.enableMouse()

  terminal.hideCursor()
  terminal.clearScreen()

proc cleanup(app: App, config: AppConfig) =
  ## Internal cleanup procedure to restore terminal state
  terminal.showCursor()

  if config.mouseCapture:
    app.terminal.disableMouse()

  if config.alternateScreen:
    app.terminal.disableAlternateScreen()

  if config.rawMode:
    app.terminal.disableRawMode()

  app.terminal.cleanup()

proc handleResize(app: App) =
  ## Handle terminal resize events
  app.terminal.updateSize()
  let newSize = app.terminal.getSize()
  let newArea = Rect(x: 0, y: 0, width: newSize.width, height: newSize.height)
  app.buffer.resize(newArea)

proc render(app: App) =
  ## Render the current frame
  # Clear the buffer
  app.buffer.clear()

  # Call user render handler first (for background content)
  if app.renderHandler != nil:
    app.renderHandler(app.buffer)

  # If window mode is enabled, render windows on top
  if app.windowMode and not app.windowManager.isNil:
    app.windowManager.render(app.buffer)

  # Use new single-write rendering with cursor support
  # This prevents cursor flickering by including cursor positioning in the same output
  app.terminal.drawWithCursor(
    app.buffer,
    app.cursor.x,
    app.cursor.y,
    app.cursor.visible,
    app.cursor.style,
    app.cursor.lastStyle,
    force = false,
  )

proc tick(app: App): bool =
  ## Process one application tick (events + render)
  ## Returns false if application should quit
  try:
    # Check for resize event first
    let resizeOpt = events.checkResize()
    if resizeOpt.isSome():
      let resizeEvent = resizeOpt.get
      app.handleResize()

      # Also pass resize event to user handler
      if app.eventHandler != nil:
        if not app.eventHandler(resizeEvent):
          return false

    # Calculate frame timeout based on target FPS
    let frameTimeoutMs = 1000 div app.targetFps

    # Event polling with dynamic timeout based on FPS
    if events.pollEvents(frameTimeoutMs):
      # Events are available - process them in batch
      var eventCount = 0
      const maxEventsPerTick = 5 # Limit events per frame for smooth rendering

      while eventCount < maxEventsPerTick:
        let eventOpt = events.readKeyInput()
        if eventOpt.isSome():
          let event = eventOpt.get
          eventCount.inc()

          # Always call user event handler first for application-level control
          var shouldContinue = true
          if app.eventHandler != nil:
            shouldContinue = app.eventHandler(event)
            if not shouldContinue:
              return false

          # Then try window manager event handling
          if app.windowMode and not app.windowManager.isNil:
            discard app.windowManager.handleEvent(event)
        else:
          break # No more events available
    # If no events available (timeout), we continue to render

    # Always render - either after processing events or on timeout
    app.render

    # Update frame counter for FPS calculation
    app.frameCounter.inc()

    return not app.shouldQuit
  except TerminalError:
    # Terminal errors should propagate up
    raise
  except CatchableError:
    # Other errors in tick should not crash the application
    # but indicate to quit
    return false

proc run*(
    app: App,
    config: AppConfig = AppConfig(
      title: "Celina App",
      alternateScreen: true,
      mouseCapture: false,
      rawMode: true,
      windowMode: false,
      targetFps: 60,
    ),
) =
  ## Run the application main loop
  ##
  ## This will:
  ## 1. Setup terminal state
  ## 2. Enter main event loop
  ## 3. Cleanup terminal state on exit
  ##
  ## Example:
  ## ```nim
  ## var app = newApp()
  ##
  ## app.onEvent proc(event: Event): bool =
  ##   # Handle events
  ##   return true
  ##
  ## app.onRender proc(buffer: var Buffer) =
  ##   # Render UI
  ##   buffer.drawString(0, 0, "Hello!", defaultStyle())
  ##
  ## app.run()
  ## ```

  try:
    app.setup(config)

    # Initialize signal handling for resize detection
    events.initSignalHandling()

    # Main application loop with event polling
    while app.tick():
      # No sleep needed - polling timeout controls frame rate
      discard
  except TerminalError as e:
    # Terminal errors are critical, ensure cleanup and re-raise
    try:
      app.cleanup(config)
    except:
      discard # Ignore cleanup errors in error state
    raise e
  except CatchableError as e:
    # Other errors should also trigger cleanup
    try:
      app.cleanup(config)
    except:
      discard # Ignore cleanup errors in error state
    raise e
  finally:
    # Always try cleanup in normal termination
    try:
      app.cleanup(config)
    except CatchableError:
      # Cleanup errors in normal flow should not crash
      discard

proc quit*(app: App) =
  ## Signal the application to quit gracefully
  app.shouldQuit = true

proc setTargetFps*(app: App, fps: int) =
  ## Set the target FPS for the application
  ## FPS must be between 1 and 120
  if fps >= 1 and fps <= 120:
    app.targetFps = fps
  else:
    raise newException(ValueError, "FPS must be between 1 and 120")

proc getTargetFps*(app: App): int =
  ## Get the current target FPS
  app.targetFps

# ============================================================================
# Cursor Control API
# ============================================================================

proc setCursor*(app: App, x, y: int) =
  ## Set cursor position for next render
  ## Position will be applied after buffer rendering
  app.cursor.x = x
  app.cursor.y = y
  app.cursor.visible = true

proc setCursor*(app: App, pos: Position) =
  ## Set cursor position using Position type
  app.setCursor(pos.x, pos.y)

proc setCursorPos*(app: App, x, y: int) =
  ## Set cursor position without affecting visibility state
  app.cursor.x = x
  app.cursor.y = y

proc showCursor*(app: App) =
  ## Show cursor in next render
  app.cursor.visible = true

proc hideCursor*(app: App) =
  ## Hide cursor in next render
  app.cursor.visible = false

proc setCursorStyle*(app: App, style: CursorStyle) =
  ## Set cursor style for next render
  app.cursor.style = style

proc getCursorPos*(app: App): (int, int) =
  ## Get current cursor position
  (app.cursor.x, app.cursor.y)

proc isCursorVisible*(app: App): bool =
  ## Check if cursor is visible
  app.cursor.visible

proc getCursorStyle*(app: App): CursorStyle =
  ## Get current cursor style
  app.cursor.style

proc resetCursor*(app: App) =
  ## Reset cursor to default state (hidden, default style, position -1,-1)
  app.cursor.x = -1
  app.cursor.y = -1
  app.cursor.visible = false
  app.cursor.style = CursorStyle.Default
  app.cursor.lastStyle = CursorStyle.Default

proc getCurrentFps*(app: App): float =
  ## Get the current actual FPS based on frame counter
  let currentTime = epochTime()
  let elapsed = currentTime - app.lastFpsTime
  if elapsed >= 1.0: # Update FPS every second
    let fps = app.frameCounter.float / elapsed
    app.lastFpsTime = currentTime
    app.frameCounter = 0
    return fps
  return 0.0 # Not enough time elapsed for accurate measurement

# ============================================================================
# Window Management Integration
# ============================================================================

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

# ============================================================================
# Convenience Functions
# ============================================================================

proc quickRun*(
    eventHandler: proc(event: Event): bool,
    renderHandler: proc(buffer: var Buffer),
    config: AppConfig = AppConfig(
      title: "Celina App",
      alternateScreen: true,
      mouseCapture: false,
      rawMode: true,
      windowMode: false,
      targetFps: 60,
    ),
) =
  ## Quick way to run a simple CLI application
  ##
  ## Example:
  ## ```nim
  ## quickRun(
  ##   eventHandler = proc(event: Event): bool =
  ##     case event.kind
  ##     of EventKind.Key:
  ##       if event.key.code == KeyCode.Char and event.key.char == 'q':
  ##         return false
  ##     else: discard
  ##     return true,
  ##
  ##   renderHandler = proc(buffer: var Buffer) =
  ##     buffer.clear()
  ##     let area = buffer.area
  ##     buffer.setString(10, area.height div 2, "Press 'q' to quit", defaultStyle())
  ## )
  ## ```
  var app = newApp(config)
  app.onEvent(eventHandler)
  app.onRender(renderHandler)
  app.run(config)

# ============================================================================
# Async API (when Chronos is available)
# ============================================================================

when hasAsyncSupport and hasChronos:
  type AsyncPerfMonitor* = ref object
    frameCount: int
    eventCount: int
    startTime: float
    lastUpdate: float

  # Utility function to convert async to sync
  proc asyncToSync*[T](asyncProc: Future[T]): T =
    ## Convert async procedure to synchronous (blocks until complete)
    return waitFor asyncProc

  # Performance monitoring for async apps
  proc newAsyncPerfMonitor*(): AsyncPerfMonitor =
    let now = epochTime()
    result =
      AsyncPerfMonitor(frameCount: 0, eventCount: 0, startTime: now, lastUpdate: now)

  proc recordFrame*(monitor: AsyncPerfMonitor) =
    monitor.frameCount.inc()
    monitor.lastUpdate = epochTime()

  proc recordEvent*(monitor: AsyncPerfMonitor) =
    monitor.eventCount.inc()

  proc getFPS*(monitor: AsyncPerfMonitor): float =
    let elapsed = epochTime() - monitor.startTime
    if elapsed > 0:
      return monitor.frameCount.float / elapsed
    else:
      return 0.0

  proc getEventRate*(monitor: AsyncPerfMonitor): float =
    let elapsed = epochTime() - monitor.startTime
    if elapsed > 0:
      return monitor.eventCount.float / elapsed
    else:
      return 0.0

  # Async window management functions are available through async_app module

# ============================================================================
# Version Information
# ============================================================================

proc version*(): string =
  ## Get the library version string
  return "0.1.0"
