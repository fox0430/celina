## Async Application framework
##
## This module provides the main AsyncApp type and async event loop
## implementation using either Chronos or std/asyncdispatch.

import std/[options, unicode, monotimes]

import async_backend, async_terminal, async_events, async_buffer, async_windows
import ../core/[geometry, colors, buffer, events, fps, config, tick_common]
import ../widgets/[text, base]

export
  geometry, colors, buffer, events, text, base, unicode, async_backend, async_terminal,
  async_events, async_buffer, async_windows, config

type
  ## Main async application context for CLI applications
  AsyncApp* = ref object
    terminal: AsyncTerminal
    buffer: async_buffer.AsyncBuffer
    windowManager: AsyncWindowManager
    fpsMonitor: FpsMonitor
    running: bool
    eventHandler: proc(event: Event): Future[bool] {.async.}
    eventHandlerWithApp: proc(event: Event, app: AsyncApp): Future[bool] {.async.}
    renderHandler: proc(buffer: async_buffer.AsyncBuffer): Future[void] {.async.}
    windowMode: bool ## Whether to use window management
    frameCounter: int
    lastFrameTime: MonoTime
    resizeState: ResizeState ## Shared resize detection state (from tick_common)
    forceNextRender: bool ## Force full render on next frame (used after resize)

  ## Deprecated: Use AppConfig instead
  AsyncAppConfig* {.deprecated: "Use AppConfig instead".} = AppConfig

  AsyncAppError* = object of CatchableError

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
  result = AsyncApp(
    terminal: newAsyncTerminal(),
    fpsMonitor: newFpsMonitor(if config.targetFps > 0: config.targetFps else: 60),
    running: false,
    eventHandler: nil,
    eventHandlerWithApp: nil,
    renderHandler: nil,
    windowMode: config.windowMode,
    frameCounter: 0,
    lastFrameTime: getMonoTime(),
    resizeState: initResizeState(async_events.getResizeCounter()),
    forceNextRender: false,
  )

  # Initialize async buffer based on terminal size (GC-safe version)
  let termSize = result.terminal.getSize()
  result.buffer = newAsyncBufferNoRM(termSize.width, termSize.height)

  # Initialize async window manager if enabled
  if config.windowMode:
    result.windowManager = newAsyncWindowManager()

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

proc onRenderAsync*(
    app: AsyncApp,
    handler: proc(buffer: async_buffer.AsyncBuffer): Future[void] {.async.},
) =
  ## Set the async render handler for the application
  ##
  ## This handler is called each frame to update the display buffer.
  ##
  ## Example:
  ## ```nim
  ## app.onRenderAsync proc(buffer: async_buffer.AsyncBuffer): Future[void] {.async.} =
  ##   await buffer.clearAsync()
  ##   let area = buffer.getArea()
  ##   let centerX = area.width div 2 - 5  # Center "Hello!"
  ##   let centerY = area.height div 2
  ##   await buffer.setStringAsync(centerX, centerY, "Hello!", defaultStyle())
  ## ```
  app.renderHandler = handler

# AsyncApp Lifecycle Management

proc setupAsync(app: AsyncApp, config: AppConfig) {.async.} =
  ## Internal async setup procedure to initialize terminal state
  await app.terminal.setupAsync()

  if config.rawMode:
    app.terminal.enableRawMode()

  if config.alternateScreen:
    app.terminal.enableAlternateScreen()

  if config.mouseCapture:
    app.terminal.enableMouse()

  await hideCursor()
  await clearScreen()

  # Initialize async event system
  initAsyncEventSystem()

proc cleanupAsync(app: AsyncApp, config: AppConfig) {.async.} =
  ## Internal async cleanup procedure to restore terminal state
  await showCursor()

  if config.mouseCapture:
    app.terminal.disableMouse()

  if config.alternateScreen:
    app.terminal.disableAlternateScreen()

  if config.rawMode:
    app.terminal.disableRawMode()

  await app.terminal.cleanupAsync()

  # Cleanup async event system
  cleanupAsyncEventSystem()

proc handleResizeAsync(app: AsyncApp) {.async.} =
  ## Handle terminal resize events asynchronously
  app.terminal.updateSize()
  let newSize = app.terminal.getSize()
  let newArea = Rect(x: 0, y: 0, width: newSize.width, height: newSize.height)
  await app.buffer.resizeAsync(newArea)
  # Clear screen to avoid artifacts from old content
  await clearScreen()
  # Force full render on next frame to ensure clean redraw
  app.forceNextRender = true

proc renderAsync(app: AsyncApp) {.async.} =
  ## Render the current frame asynchronously
  # Clear the buffer
  await app.buffer.clearAsync()

  # Call user render handler first (for background content)
  if app.renderHandler != nil:
    await app.renderHandler(app.buffer)

  # If window mode is enabled, render windows on top
  if app.windowMode and not app.windowManager.isNil:
    await app.windowManager.renderAsync(app.buffer)

  # Use async terminal rendering - convert AsyncBuffer to Buffer (GC-safe version)
  let renderBuffer = app.buffer.toBufferAsync()
  # Force render if requested after resize
  if app.forceNextRender:
    await app.terminal.drawAsync(renderBuffer, force = true)
    app.forceNextRender = false
  else:
    await app.terminal.drawAsync(renderBuffer, force = false)

proc dispatchEventAsync(app: AsyncApp, event: Event): Future[bool] {.async.} =
  ## Helper to dispatch event to the appropriate handler
  if app.eventHandlerWithApp != nil:
    return await app.eventHandlerWithApp(event, app)
  elif app.eventHandler != nil:
    return await app.eventHandler(event)
  else:
    return true

proc tickAsync(app: AsyncApp, targetFps: int): Future[bool] {.async.} =
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
  ##   false if application should quit, true to continue
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
            try:
              let handled = await app.windowManager.handleEventAsync(event)
              if handled:
                continue
            except:
              discard
        else:
          break

    # Render only if enough time has passed for target FPS
    if app.fpsMonitor.shouldRender():
      app.fpsMonitor.startFrame()
      await app.renderAsync()
      app.fpsMonitor.endFrame()
      app.frameCounter.inc()
      app.lastFrameTime = getMonoTime()

    return app.running
  except Exception:
    return false

proc runAsync*(app: AsyncApp, config: AppConfig = DefaultAppConfig) {.async.} =
  ## Run the async application main loop
  ##
  ## This will:
  ## 1. Setup terminal state asynchronously
  ## 2. Enter main async event loop
  ## 3. Cleanup terminal state on exit
  ##
  ## Example:
  ## ```nim
  ## var app = newAsyncApp()
  ##
  ## app.onEventAsync proc(event: Event): Future[bool] {.async.} =
  ##   # Handle events asynchronously
  ##   return true
  ##
  ## app.onRenderAsync proc(buffer: var Buffer): Future[void] {.async.} =
  ##   # Render UI asynchronously
  ##   buffer.setString(0, 0, "Hello Async!", defaultStyle())
  ##
  ## await app.runAsync()
  ## ```

  try:
    await app.setupAsync(config)
    app.running = true

    # Main async application loop
    while await app.tickAsync(config.targetFps):
      # The tick function controls timing and frame rate
      discard
  except:
    # Any errors should trigger cleanup
    try:
      await app.cleanupAsync(config)
    except:
      discard # Ignore cleanup errors in error state
  finally:
    # Always try cleanup in normal termination
    try:
      await app.cleanupAsync(config)
    except:
      # Cleanup errors in normal flow should not crash
      discard

proc quitAsync*(app: AsyncApp) {.async.} =
  ## Signal the async application to quit gracefully
  app.running = false

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

# Window Management Integration

proc enableWindowMode*(app: AsyncApp) =
  ## Enable window management mode
  app.windowMode = true
  if app.windowManager.isNil:
    app.windowManager = newAsyncWindowManager()

proc addWindowAsync*(app: AsyncApp, window: Window): Future[WindowId] {.async.} =
  ## Add a window to the application asynchronously
  if not app.windowMode:
    app.enableWindowMode()
  return await app.windowManager.addWindowAsync(window)

proc removeWindowAsync*(app: AsyncApp, windowId: WindowId): Future[bool] {.async.} =
  ## Remove a window from the application asynchronously
  if app.windowMode and not app.windowManager.isNil:
    return await app.windowManager.removeWindowAsync(windowId)
  return false

proc getWindowAsync*(
    app: AsyncApp, windowId: WindowId
): Future[Option[Window]] {.async.} =
  ## Get a window by ID asynchronously
  if app.windowMode and not app.windowManager.isNil:
    return await app.windowManager.getWindowAsync(windowId)
  return none(Window)

proc focusWindowAsync*(app: AsyncApp, windowId: WindowId): Future[bool] {.async.} =
  ## Focus a specific window asynchronously
  if app.windowMode and not app.windowManager.isNil:
    return await app.windowManager.focusWindowAsync(windowId)
  return false

proc getFocusedWindowAsync*(app: AsyncApp): Future[Option[Window]] {.async.} =
  ## Get the currently focused window asynchronously
  if app.windowMode and not app.windowManager.isNil:
    return await app.windowManager.getFocusedWindowAsync()
  return none(Window)

# Async Convenience Functions

proc quickRunAsync*(
    eventHandler: proc(event: Event): Future[bool] {.async.},
    renderHandler: proc(buffer: async_buffer.AsyncBuffer): Future[void] {.async.},
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
  ##   renderHandler = proc(buffer: async_buffer.AsyncBuffer): Future[void] {.async.} =
  ##     await buffer.clearAsync()
  ##     let area = buffer.getArea()
  ##     await buffer.setStringAsync(10, area.height div 2, "Press 'q' to quit", defaultStyle())
  ## )
  ## ```
  var app = newAsyncApp(config)
  app.onEventAsync(eventHandler)
  app.onRenderAsync(renderHandler)
  await app.runAsync(config)

# ============================================================================
# Performance Monitoring
# ============================================================================

proc getFrameCount*(app: AsyncApp): int =
  ## Get total frame count
  app.frameCounter

proc getLastFrameTime*(app: AsyncApp): MonoTime =
  ## Get timestamp of last frame
  app.lastFrameTime

proc isRunning*(app: AsyncApp): bool =
  ## Check if app is currently running
  app.running

proc getTerminalSize*(app: AsyncApp): Size =
  ## Get current terminal size
  app.terminal.getSize()

# FPS Control Delegation

proc setTargetFps*(app: AsyncApp, fps: int) =
  ## Set the target FPS for the application
  app.fpsMonitor.setTargetFps(fps)

proc getTargetFps*(app: AsyncApp): int =
  ## Get the current target FPS
  app.fpsMonitor.getTargetFps()

proc getCurrentFps*(app: AsyncApp): float =
  ## Get the current actual FPS
  app.fpsMonitor.getCurrentFps()
