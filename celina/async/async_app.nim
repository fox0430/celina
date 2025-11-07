## Async Application framework
##
## This module provides the main AsyncApp type and async event loop
## implementation using either Chronos or std/asyncdispatch.

import std/[options, unicode, times, monotimes]

import async_backend, async_terminal, async_events, async_buffer, async_windows
import ../core/[geometry, colors, buffer, events]
import ../widgets/[text, base]

export
  geometry, colors, buffer, events, text, base, unicode, async_backend, async_terminal,
  async_events, async_buffer, async_windows

type
  ## Main async application context for CLI applications
  AsyncApp* = ref object
    terminal: AsyncTerminal
    buffer: async_buffer.AsyncBuffer
    windowManager: AsyncWindowManager
    running: bool
    eventHandler: proc(event: Event): Future[bool] {.async.}
    renderHandler: proc(buffer: async_buffer.AsyncBuffer): Future[void] {.async.}
    windowMode: bool ## Whether to use window management
    frameCounter: int
    lastFrameTime: MonoTime
    lastResizeCounter: int
      ## Track last seen resize counter for independent resize detection

  ## Async application configuration options
  AsyncAppConfig* = object
    title*: string
    alternateScreen*: bool
    mouseCapture*: bool
    rawMode*: bool
    windowMode*: bool ## Enable window management
    targetFps*: int ## Target FPS for rendering (default: 60)

  AsyncAppError* = object of CatchableError

# ============================================================================
# AsyncApp Creation and Configuration
# ============================================================================

proc newAsyncApp*(
    config: AsyncAppConfig = AsyncAppConfig(
      title: "Async Celina App",
      alternateScreen: true,
      mouseCapture: false,
      rawMode: true,
      windowMode: false,
      targetFps: 60,
    )
): AsyncApp =
  ## Create a new async CLI application with the specified configuration
  ##
  ## Example:
  ## ```nim
  ## let config = AsyncAppConfig(
  ##   title: "My Async App",
  ##   alternateScreen: true,
  ##   mouseCapture: true,
  ##   targetFps: 30
  ## )
  ## var app = newAsyncApp(config)
  ## ```
  result = AsyncApp(
    terminal: newAsyncTerminal(),
    running: false,
    eventHandler: nil,
    renderHandler: nil,
    windowMode: config.windowMode,
    frameCounter: 0,
    lastFrameTime: getMonoTime(),
    lastResizeCounter: async_events.getResizeCounter(),
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

# ============================================================================
# AsyncApp Lifecycle Management
# ============================================================================

proc setupAsync(app: AsyncApp, config: AsyncAppConfig) {.async.} =
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

proc cleanupAsync(app: AsyncApp, config: AsyncAppConfig) {.async.} =
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
  await app.terminal.drawAsync(renderBuffer, force = false)

proc tickAsync(app: AsyncApp, targetFps: int): Future[bool] {.async.} =
  ## Process one async application tick (events + render)
  ## Returns false if application should quit
  try:
    # Calculate frame timing
    let now = getMonoTime()
    let targetFrameTime = 1000 div targetFps # Target frame time in milliseconds

    # Check for resize event using counter-based detection
    # This approach supports multiple AsyncApp instances without race conditions
    let currentResizeCounter = async_events.getResizeCounter()
    if currentResizeCounter != app.lastResizeCounter:
      # Resize occurred since last check
      app.lastResizeCounter = currentResizeCounter
      let resizeEvent = Event(kind: Resize)
      await app.handleResizeAsync()

      # Also pass resize event to user handler
      if app.eventHandler != nil:
        if not (await app.eventHandler(resizeEvent)):
          return false

    # Poll for events with short timeout
    let eventsAvailable = await pollEventsAsync(1) # 1ms timeout

    if eventsAvailable:
      # Events are available - process them
      var eventCount = 0
      const maxEventsPerTick = 5 # Limit events per frame for smooth rendering

      while eventCount < maxEventsPerTick:
        let eventOpt = await pollKeyAsync()
        if eventOpt.isSome():
          let event = eventOpt.get()
          eventCount.inc()

          # Always call user event handler first for application-level control
          var shouldContinue = true
          if app.eventHandler != nil:
            shouldContinue = await app.eventHandler(event)
            if not shouldContinue:
              return false

          # Window manager event handling
          if app.windowMode and not app.windowManager.isNil:
            try:
              let handled = await app.windowManager.handleEventAsync(event)
              if handled:
                continue # Event was handled by window manager
            except:
              discard # Ignore window manager errors
        else:
          break # No more events available

    # Always render - either after processing events or on timeout
    await app.renderAsync()

    # Frame timing control
    let frameTime = (getMonoTime() - now).inMilliseconds()
    if frameTime < targetFrameTime:
      let sleepTime = int(targetFrameTime - frameTime)
      await sleepMs(sleepTime)

    app.frameCounter.inc()
    app.lastFrameTime = now

    return app.running
  except Exception:
    # Any errors in tick should not crash the application
    # but indicate to quit
    return false

proc runAsync*(
    app: AsyncApp,
    config: AsyncAppConfig = AsyncAppConfig(
      title: "Async Celina App",
      alternateScreen: true,
      mouseCapture: false,
      rawMode: true,
      windowMode: false,
      targetFps: 60,
    ),
) {.async.} =
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

# ============================================================================
# Window Management Integration
# ============================================================================

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

# ============================================================================
# Async Convenience Functions
# ============================================================================

proc quickRunAsync*(
    eventHandler: proc(event: Event): Future[bool] {.async.},
    renderHandler: proc(buffer: async_buffer.AsyncBuffer): Future[void] {.async.},
    config: AsyncAppConfig = AsyncAppConfig(
      title: "Async Celina App",
      alternateScreen: true,
      mouseCapture: false,
      rawMode: true,
      windowMode: false,
      targetFps: 60,
    ),
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

# ============================================================================
# Version Information
# ============================================================================

proc asyncVersion*(): string =
  ## Get the async library version string
  return "0.1.0-async"
