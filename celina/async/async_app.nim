## Async Application framework
##
## This module provides the main AsyncApp type and async event loop
## implementation using either Chronos or std/asyncdispatch.

import std/[options, monotimes, strformat]

import async_backend, async_terminal, async_events, async_windows, async_renderer
import
  ../core/[
    geometry, buffer, events, fps, config, tick_common, cursor, terminal_common, errors,
    windows,
  ]

export config

type
  ## Main async application context for CLI applications
  AsyncApp* = ref object
    terminal: AsyncTerminal
    renderer: AsyncRenderer
    fpsMonitor: FpsMonitor
    windowManager: AsyncWindowManager
    shouldQuit: bool
    eventHandler: proc(event: Event): Future[bool] {.async.}
    eventHandlerWithApp: proc(event: Event, app: AsyncApp): Future[bool] {.async.}
    renderHandler: proc(buffer: var Buffer)
    windowMode: bool ## Whether to use window management
    config: AppConfig
    resizeState: ResizeState ## Shared resize detection state (from tick_common)
    forceNextRender: bool ## Force full render on next frame (used after resize)
    running: bool ## Whether app is currently running
    frameCounter: int ## Total frame count
    lastFrameTime: MonoTime ## Timestamp of last frame

  AsyncAppError* = object of CatchableError

proc `$`*(app: AsyncApp): string =
  ## String representation of AsyncApp for debugging
  let windowCount =
    if app.windowMode and not app.windowManager.isNil:
      app.windowManager.getWindowCountSync()
    else:
      0
  &"AsyncApp(running: {app.running}, fps: {app.fpsMonitor.getCurrentFps():.1f}, frames: {app.frameCounter}, windows: {windowCount}, config: {app.config})"

# AsyncApp Creation and Configuration

proc newAsyncApp*(config: AppConfig = DefaultAppConfig): AsyncApp =
  ## Create a new async CLI application with the specified configuration
  ##
  ## Example:
  ## ```nim
  ## let config = AppConfig(
  ##   title: "My Async App",
  ##   alternateScreen: true,
  ##   mouseCapture: true,
  ##   targetFps: 30
  ## )
  ## var app = newAsyncApp(config)
  ## ```
  let terminal = newAsyncTerminal()
  result = AsyncApp(
    terminal: terminal,
    renderer: newAsyncRenderer(terminal),
    fpsMonitor: newFpsMonitor(if config.targetFps > 0: config.targetFps else: 60),
    shouldQuit: false,
    eventHandler: nil,
    eventHandlerWithApp: nil,
    renderHandler: nil,
    windowMode: config.windowMode,
    config: config,
    resizeState: initResizeState(async_events.getResizeCounter()),
    forceNextRender: false,
    running: false,
    frameCounter: 0,
    lastFrameTime: getMonoTime(),
  )

  # Initialize async window manager if enabled
  if config.windowMode:
    result.windowManager = newAsyncWindowManager()

# Event and render handlers
proc onEventAsync*(app: AsyncApp, handler: proc(event: Event): Future[bool] {.async.}) =
  ## Set the async event handler for the application
  ##
  ## The handler should return true if the event was handled,
  ## false if the application should quit.
  ##
  ## For access to the AsyncApp object (e.g., for suspend/resume), use the
  ## overload that accepts `proc(event: Event, app: AsyncApp): Future[bool]` instead.
  ##
  ## Example:
  ## ```nim
  ## app.onEventAsync proc(event: Event): Future[bool] {.async.} =
  ##   case event.kind
  ##   of EventKind.Key:
  ##     if event.key.code == KeyCode.Char and event.key.char == "q":
  ##       return false  # Quit application
  ##     elif event.key.code == KeyCode.Escape:
  ##       return false  # Quit on escape
  ##   else:
  ##     discard
  ##   return true  # Continue running
  ## ```
  app.eventHandler = handler
  app.eventHandlerWithApp = nil

proc onEventAsync*(
    app: AsyncApp, handler: proc(event: Event, app: AsyncApp): Future[bool] {.async.}
) =
  ## Set the async event handler with AsyncApp context for the application
  ##
  ## This overload provides access to the AsyncApp object, enabling features like
  ## suspend/resume for shell command execution.
  ##
  ## Example:
  ## ```nim
  ## app.onEventAsync proc(event: Event, app: AsyncApp): Future[bool] {.async.} =
  ##   if event.kind == Key and event.key.char == "!":
  ##     app.withSuspendAsync:
  ##       discard execShellCmd("ls -la")
  ##       echo "Press Enter..."
  ##       discard stdin.readLine()
  ##     return true
  ##   return true
  ## ```
  app.eventHandlerWithApp = handler
  app.eventHandler = nil

proc onRenderAsync*(app: AsyncApp, handler: proc(buffer: var Buffer)) =
  ## Set the render handler for the application
  ##
  ## This handler is called each frame to update the display buffer.
  ##
  ## Example:
  ## ```nim
  ## app.onRenderAsync proc(buffer: var Buffer) =
  ##   buffer.setString(10, 5, "Hello!", defaultStyle())
  ## ```
  app.renderHandler = handler

# AsyncApp Lifecycle Management

proc setupAsync(app: AsyncApp) {.async.} =
  ## Internal async setup procedure to initialize terminal state
  await app.terminal.setupAsync()

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

  await hideCursorAsync()
  await clearScreenAsync()

proc cleanupAsync(app: AsyncApp) {.async.} =
  ## Internal async cleanup procedure to restore terminal state
  await showCursorAsync()

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

  await app.terminal.cleanupAsync()

proc handleResizeAsync(app: AsyncApp) {.async.} =
  ## Handle terminal resize events asynchronously
  app.terminal.updateSize()
  app.renderer.resize()
  # Clear screen to avoid artifacts from old content
  await clearScreenAsync()
  # Force full render on next frame to ensure clean redraw
  app.forceNextRender = true

proc renderAsync(app: AsyncApp) {.async.} =
  ## Render the current frame asynchronously
  # Clear the buffer
  app.renderer.clear()

  # Call user render handler first (for background content)
  if app.renderHandler != nil:
    {.cast(gcsafe).}:
      {.cast(raises: []).}:
        app.renderHandler(app.renderer.getBuffer())

  # If window mode is enabled, render windows on top
  if app.windowMode and not app.windowManager.isNil:
    app.windowManager.renderSync(app.renderer.getBuffer())

  # Render to terminal (force if requested after resize)
  if app.forceNextRender:
    await app.renderer.renderAsync(force = true)
    app.forceNextRender = false
  else:
    await app.renderer.renderAsync()

proc dispatchEventAsync(app: AsyncApp, event: Event): Future[bool] {.async.} =
  ## Helper to dispatch event to the appropriate handler
  if app.eventHandlerWithApp != nil:
    return await app.eventHandlerWithApp(event, app)
  elif app.eventHandler != nil:
    return await app.eventHandler(event)
  else:
    return true

proc tickAsync(app: AsyncApp): Future[bool] {.async.} =
  ## Process one async application tick (events + render).
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
    if app.resizeState.checkResize(async_events.getResizeCounter()):
      let resizeEvent = Event(kind: Resize)
      await app.handleResizeAsync()

      # Pass resize event to user handler
      if not (await app.dispatchEventAsync(resizeEvent)):
        return false

    # Calculate remaining time until next render (used as poll timeout)
    let remainingTime = app.fpsMonitor.getRemainingFrameTime()

    # Use remaining time as timeout, minimum 1ms to avoid busy waiting
    let timeout = clampTimeout(remainingTime, 1)

    # Poll for events with timeout - blocks until event arrives OR timeout expires
    let eventsAvailable = await pollEventsAsync(timeout)

    if eventsAvailable:
      var eventCount = 0

      while eventCount < maxEventsPerTick:
        let eventOpt = await pollKeyAsync()
        if eventOpt.isSome():
          let event = eventOpt.get()
          eventCount.inc()

          # User event handler first
          if not (await app.dispatchEventAsync(event)):
            return false

          # Window manager event handling
          if app.windowMode and not app.windowManager.isNil:
            {.cast(gcsafe).}:
              discard app.windowManager.handleEventSync(event)
        else:
          break

    # Render only if enough time has passed for target FPS
    if app.fpsMonitor.shouldRender():
      app.fpsMonitor.startFrame()
      await app.renderAsync()
      app.fpsMonitor.endFrame()
      app.frameCounter.inc()
      app.lastFrameTime = getMonoTime()

    return not app.shouldQuit
  except TerminalError as e:
    raise e
  except CatchableError:
    return false

proc runAsync*(app: AsyncApp) {.async.} =
  ## Run the async application main loop
  ##
  ## This will:
  ## 1. Setup terminal state asynchronously using config from newAsyncApp
  ## 2. Enter main async event loop
  ## 3. Cleanup terminal state on exit
  ##
  ## Example:
  ## ```nim
  ## var app = newAsyncApp(AppConfig(mouseCapture: true))
  ##
  ## app.onEventAsync proc(event: Event): Future[bool] {.async.} =
  ##   # Handle events asynchronously
  ##   return true
  ##
  ## app.onRenderAsync proc(buffer: var Buffer) =
  ##   # Render UI
  ##   buffer.setString(0, 0, "Hello Async!", defaultStyle())
  ##
  ## await app.runAsync()
  ## ```
  try:
    await app.setupAsync()
    app.running = true

    # Initialize async event system for resize detection
    initAsyncEventSystem()

    # Main async application loop
    while await app.tickAsync():
      discard
  except TerminalError as e:
    try:
      await app.cleanupAsync()
    except:
      discard
    raise e
  except CatchableError as e:
    try:
      await app.cleanupAsync()
    except:
      discard
    raise e
  finally:
    app.running = false
    # Cleanup async event system
    cleanupAsyncEventSystem()
    try:
      await app.cleanupAsync()
    except CatchableError:
      discard

proc quit*(app: AsyncApp) =
  ## Signal the async application to quit gracefully
  app.shouldQuit = true

# Mouse control
proc enableMouse*(app: AsyncApp) =
  ## Enable mouse reporting at runtime
  app.terminal.enableMouse()

proc disableMouse*(app: AsyncApp) =
  ## Disable mouse reporting at runtime
  app.terminal.disableMouse()

# Suspend/Resume for shell command execution
proc suspendAsync*(app: AsyncApp) {.async.} =
  ## Temporarily suspend the TUI, restoring normal terminal mode.
  ##
  ## Use this to run shell commands or interact with the terminal normally.
  ## Call `resumeAsync()` to return to TUI mode.
  ##
  ## Example:
  ## ```nim
  ## await app.suspendAsync()
  ## discard execShellCmd("vim myfile.txt")
  ## await app.resumeAsync()
  ## ```
  await app.terminal.suspendAsync()

proc resumeAsync*(app: AsyncApp) {.async.} =
  ## Resume the TUI after a `suspendAsync()` call.
  ##
  ## Restores terminal state and forces a full redraw on the next frame.
  await app.terminal.resumeAsync()
  app.forceNextRender = true

proc isSuspended*(app: AsyncApp): bool =
  ## Check if the application is currently suspended
  app.terminal.isSuspended

template withSuspendAsync*(app: AsyncApp, body: untyped) =
  ## Suspend the TUI, execute body, then resume.
  ##
  ## This is the recommended way to run shell commands as it ensures
  ## `resumeAsync()` is always called, even if an exception occurs.
  ##
  ## Note: The body should be synchronous code (like execShellCmd).
  ## For async operations, use suspendAsync/resumeAsync directly.
  ##
  ## Example:
  ## ```nim
  ## app.withSuspendAsync:
  ##   let exitCode = execShellCmd("git commit")
  ##   echo "Press Enter to continue..."
  ##   discard stdin.readLine()
  ## ```
  await app.suspendAsync()
  try:
    body
  finally:
    await app.resumeAsync()

# FPS control delegation
proc setTargetFps*(app: AsyncApp, fps: int) =
  ## Set the target FPS for the application
  app.fpsMonitor.setTargetFps(fps)

proc getTargetFps*(app: AsyncApp): int =
  ## Get the current target FPS
  app.fpsMonitor.getTargetFps()

proc getCurrentFps*(app: AsyncApp): float =
  ## Get the current actual FPS
  app.fpsMonitor.getCurrentFps()

# Cursor control delegation
proc setCursorPosition*(app: AsyncApp, x, y: int) =
  ## Set cursor position without changing visibility state
  app.renderer.setCursorPosition(x, y)

proc setCursorPosition*(app: AsyncApp, pos: Position) =
  ## Set cursor position using Position type without changing visibility
  app.renderer.setCursorPosition(pos)

proc showCursorAt*(app: AsyncApp, x, y: int) =
  ## Set cursor position and make it visible
  app.renderer.showCursorAt(x, y)

proc showCursorAt*(app: AsyncApp, pos: Position) =
  ## Set cursor position using Position type and make it visible
  app.renderer.showCursorAt(pos)

proc showCursor*(app: AsyncApp) =
  ## Show cursor at current position
  app.renderer.showCursor()

proc hideCursor*(app: AsyncApp) =
  ## Hide cursor
  app.renderer.hideCursor()

proc setCursorStyle*(app: AsyncApp, style: CursorStyle) =
  ## Set cursor style for next render
  app.renderer.setCursorStyle(style)

proc getCursorPosition*(app: AsyncApp): (int, int) =
  ## Get current cursor position
  app.renderer.getCursorPosition()

proc moveCursorBy*(app: AsyncApp, dx, dy: int) =
  ## Move cursor relatively by dx, dy
  let (x, y) = app.getCursorPosition()
  app.setCursorPosition(x + dx, y + dy)

proc isCursorVisible*(app: AsyncApp): bool =
  ## Check if cursor is visible
  app.renderer.isCursorVisible()

proc getCursorStyle*(app: AsyncApp): CursorStyle =
  ## Get current cursor style
  app.renderer.getCursorManager().getStyle()

proc resetCursor*(app: AsyncApp) =
  ## Reset cursor to default state
  app.renderer.getCursorManager().reset()

# Window management
proc enableWindowMode*(app: AsyncApp) =
  ## Enable window management mode
  app.windowMode = true
  if app.windowManager.isNil:
    app.windowManager = newAsyncWindowManager()

proc addWindow*(app: AsyncApp, window: Window): WindowId =
  ## Add a window to the application
  if not app.windowMode:
    app.enableWindowMode()
  return app.windowManager.addWindowSync(window)

proc removeWindow*(app: AsyncApp, windowId: WindowId): bool =
  ## Remove a window from the application
  ## Returns true if the window was found and removed, false otherwise
  if app.windowMode and not app.windowManager.isNil:
    return app.windowManager.removeWindowSync(windowId)

proc getWindow*(app: AsyncApp, windowId: WindowId): Option[Window] =
  ## Get a window by ID
  if app.windowMode and not app.windowManager.isNil:
    return app.windowManager.getWindowSync(windowId)
  return none(Window)

proc focusWindow*(app: AsyncApp, windowId: WindowId): bool =
  ## Focus a specific window
  ## Returns true if the window was found and focused, false otherwise
  if app.windowMode and not app.windowManager.isNil:
    return app.windowManager.focusWindowSync(windowId)

proc getFocusedWindow*(app: AsyncApp): Option[Window] =
  ## Get the currently focused window
  if app.windowMode and not app.windowManager.isNil:
    return app.windowManager.getFocusedWindowSync()
  return none(Window)

proc getWindows*(app: AsyncApp): seq[Window] =
  ## Get all windows in the application
  if app.windowMode and not app.windowManager.isNil:
    return app.windowManager.getWindowsSync()
  return @[]

proc getWindowCount*(app: AsyncApp): int =
  ## Get the total number of windows
  if app.windowMode and not app.windowManager.isNil:
    return app.windowManager.getWindowCountSync()
  return 0

proc getFocusedWindowId*(app: AsyncApp): Option[WindowId] =
  ## Get the ID of the currently focused window
  if app.windowMode and not app.windowManager.isNil:
    return app.windowManager.getFocusedWindowIdSync()
  return none(WindowId)

proc getWindowInfo*(app: AsyncApp, windowId: WindowId): Option[WindowInfo] =
  ## Get window information by ID
  if app.windowMode and not app.windowManager.isNil:
    let windowOpt = app.windowManager.getWindowSync(windowId)
    if windowOpt.isSome():
      return some(windowOpt.get.toWindowInfo())
  return none(WindowInfo)

proc handleWindowEvent*(app: AsyncApp, event: Event): bool =
  ## Handle an event through the window manager
  if app.windowMode and not app.windowManager.isNil:
    return app.windowManager.handleEventSync(event)

# State and info queries

proc isRunning*(app: AsyncApp): bool =
  ## Check if app is currently running
  app.running

proc getTerminalSize*(app: AsyncApp): Size =
  ## Get current terminal size
  app.terminal.getSize()

proc getConfig*(app: AsyncApp): AppConfig =
  ## Get the stored configuration
  app.config

proc getFrameCount*(app: AsyncApp): int =
  ## Get total frame count
  app.frameCounter

proc getLastFrameTime*(app: AsyncApp): MonoTime =
  ## Get timestamp of last frame
  app.lastFrameTime

# Convenience functions

proc quickRunAsync*(
    eventHandler: proc(event: Event): Future[bool] {.async.},
    renderHandler: proc(buffer: var Buffer),
    config: AppConfig = DefaultAppConfig,
) {.async.} =
  ## Quick way to run a simple async CLI application
  ##
  ## Example:
  ## ```nim
  ## await quickRunAsync(
  ##   eventHandler = proc(event: Event): Future[bool] {.async.} =
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
  var app = newAsyncApp(config)
  app.onEventAsync(eventHandler)
  app.onRenderAsync(renderHandler)
  await app.runAsync()
