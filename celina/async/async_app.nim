## Async Application framework
##
## This module provides the main AsyncApp type and async event loop
## implementation using either Chronos or std/asyncdispatch.

import std/[options, monotimes, times, strformat]

import async_backend, async_terminal, async_events, async_windows, async_renderer
import
  ../core/[
    geometry, buffer, events, fps, config, tick_common, cursor, terminal,
    terminal_common, errors, windows, app,
  ]

export config

type
  AsyncAppHandlers = object
    ## User-supplied callbacks invoked during the async event loop
    event: proc(event: Event, app: AsyncApp): Future[bool] {.async.}
    render: proc(buffer: var Buffer, app: AsyncApp)
    tick: proc(app: AsyncApp): Future[bool] {.async.}
    timeout: proc(app: AsyncApp): Future[bool] {.async.}

  AsyncAppTimings* = AppTimings
    ## Alias of AppTimings; async event loop reuses the same timing fields.

  AsyncAppState* = AppState
    ## Alias of AppState; async runtime state is structurally identical.

  ## Main async application context for CLI applications
  AsyncApp* = ref object
    terminal: AsyncTerminal
    renderer: AsyncRenderer
    fpsMonitor: FpsMonitor
    windowManager: AsyncWindowManager
    config: AppConfig
    handlers: AsyncAppHandlers
    timings: AsyncAppTimings
    state: AsyncAppState
    when hasChronos:
      runFuture: Future[void]
        ## Set on runAsync entry, cleared on exit. shutdownAsync targets
        ## this Future via cancelAndWait. nil before/after runAsync.
      when defined(posix):
        signalHandles: seq[SignalHandle]
          ## SIGINT/SIGTERM handles registered when
          ## config.installSignalHandler is true. Cleared during runAsync
          ## cleanup so handles do not outlive the AsyncApp instance.
          ## POSIX-only: chronos signal APIs are not available on Windows.

  AsyncAppError* = object of CatchableError

proc `$`*(app: AsyncApp): string =
  ## String representation of AsyncApp for debugging
  let windowCount =
    if app.state.windowMode and not app.windowManager.isNil:
      app.windowManager.getWindowCountSync()
    else:
      0
  &"AsyncApp(running: {app.state.running}, fps: {app.fpsMonitor.getCurrentFps():.1f}, frames: {app.timings.frameCounter}, windows: {windowCount}, config: {app.config})"

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
  let termSize = terminal.getSize()
  result = AsyncApp(
    terminal: terminal,
    renderer: newAsyncRenderer(terminal),
    fpsMonitor: newFpsMonitor(if config.targetFps > 0: config.targetFps else: 60),
    config: config,
    handlers: AsyncAppHandlers(event: nil, render: nil, tick: nil, timeout: nil),
    timings: AsyncAppTimings(
      frameCounter: 0,
      lastFrameTime: getMonoTime(),
      lastEventTime: getMonoTime(),
      applicationTimeout: 0,
    ),
    state: AsyncAppState(
      shouldQuit: false,
      running: false,
      forceNextRender: false,
      windowMode: config.windowMode,
      resizeState: initResizeState(termSize.width, termSize.height),
    ),
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
  app.handlers.event =
    if handler.isNil:
      nil
    else:
      # Bind to a local so the wrapping closure captures the handler value.
      let captured = handler
      proc(event: Event, app: AsyncApp): Future[bool] {.async.} =
        return await captured(event)

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
  app.handlers.event = handler

proc onRenderAsync*(app: AsyncApp, handler: proc(buffer: var Buffer)) =
  ## Set the render handler for the application
  ##
  ## This handler is called each frame to update the display buffer.
  ##
  ## For access to the AsyncApp object (e.g., to query FPS, window state,
  ## or terminal size during rendering), use the overload that accepts
  ## `proc(buffer: var Buffer, app: AsyncApp)` instead.
  ##
  ## Example:
  ## ```nim
  ## app.onRenderAsync proc(buffer: var Buffer) =
  ##   buffer.setString(10, 5, "Hello!", defaultStyle())
  ## ```
  app.handlers.render =
    if handler.isNil:
      nil
    else:
      let captured = handler
      proc(buffer: var Buffer, app: AsyncApp) =
        captured(buffer)

proc onRenderAsync*(app: AsyncApp, handler: proc(buffer: var Buffer, app: AsyncApp)) =
  ## Set the render handler with AsyncApp context for the application
  ##
  ## This overload provides access to the AsyncApp object, enabling the
  ## render handler to query runtime state such as current FPS,
  ## terminal size, or window manager information.
  ##
  ## Example:
  ## ```nim
  ## app.onRenderAsync proc(buffer: var Buffer, app: AsyncApp) =
  ##   let fps = app.getCurrentFps()
  ##   buffer.setString(0, 0, &"FPS: {fps:.1f}", defaultStyle())
  ## ```
  app.handlers.render = handler

proc onTickAsync*(app: AsyncApp, handler: proc(): Future[bool] {.async.}) =
  ## Set the async tick handler called each frame between event processing and rendering.
  ##
  ## Return true to continue running, false to quit.
  app.handlers.tick =
    if handler.isNil:
      nil
    else:
      let captured = handler
      proc(app: AsyncApp): Future[bool] {.async.} =
        return await captured()

proc onTickAsync*(app: AsyncApp, handler: proc(app: AsyncApp): Future[bool] {.async.}) =
  ## Set the async tick handler with AsyncApp context called each frame between event processing and rendering.
  ##
  ## Return true to continue running, false to quit.
  app.handlers.tick = handler

# Application timeout
proc onTimeoutAsync*(app: AsyncApp, handler: proc(): Future[bool] {.async.}) =
  ## Set the async timeout handler for the application.
  ##
  ## The handler is called when no input events are received within
  ## the application timeout period. Return true to continue running,
  ## false to quit the application.
  ##
  ## For access to the AsyncApp object, use the overload that accepts
  ## `proc(app: AsyncApp): Future[bool]` instead.
  app.handlers.timeout =
    if handler.isNil:
      nil
    else:
      let captured = handler
      proc(app: AsyncApp): Future[bool] {.async.} =
        return await captured()

proc onTimeoutAsync*(
    app: AsyncApp, handler: proc(app: AsyncApp): Future[bool] {.async.}
) =
  ## Set the async timeout handler with AsyncApp context for the application.
  ##
  ## The handler is called when no input events are received within
  ## the application timeout period. Return true to continue running,
  ## false to quit the application.
  app.handlers.timeout = handler

proc setApplicationTimeout*(app: AsyncApp, timeoutMs: int) =
  ## Set the application timeout in milliseconds.
  ##
  ## When set to a positive value, the timeout handler will be called
  ## if no input events are received within this duration.
  ## Set to 0 to disable the application timeout.
  app.timings.applicationTimeout = timeoutMs

proc getApplicationTimeout*(app: AsyncApp): int =
  ## Get the current application timeout in milliseconds.
  ##
  ## Returns 0 if the timeout is disabled.
  app.timings.applicationTimeout

# AsyncApp Lifecycle Management

proc setupAsync(app: AsyncApp) {.async.} =
  if app.config.alternateScreen:
    app.terminal.enableAlternateScreen()

  if app.config.rawMode:
    app.terminal.enableRawMode()

  app.terminal.updateSize()

  if app.config.mouseCapture:
    app.terminal.enableMouse()

  if app.config.bracketedPaste:
    app.terminal.enableBracketedPaste()

  if app.config.focusEvents:
    app.terminal.enableFocusEvents()

  await hideCursorAsync()
  await clearScreenAsync()

proc cleanupAsync(app: AsyncApp) {.async.} =
  ## Internal async cleanup procedure to restore terminal state.
  ##
  ## Delegates the disable sequence to `terminal.cleanupAsync()` so the LIFO
  ## ordering (raw mode before alternate screen) is defined in one place.
  ## Each underlying `disableX` is idempotent and state-gated, so calling
  ## the full sequence is safe regardless of `app.config` flags.
  await app.terminal.cleanupAsync()

proc handleResizeAsync(app: AsyncApp) {.async.} =
  ## Handle terminal resize events asynchronously
  app.terminal.updateSize()
  app.renderer.resize()
  # Clear screen to avoid artifacts from old content
  await clearScreenAsync()
  # Force full render on next frame to ensure clean redraw
  app.state.forceNextRender = true

proc dispatchEventAsync*(app: AsyncApp, event: Event): Future[bool] {.async.} =
  ## Invoke the configured async event handler for the given event.
  ##
  ## Returns `true` when no handler is configured. Primarily used internally
  ## by `tickAsync`, but exported so tests and callers can trigger the handler
  ## directly.
  if app.handlers.event != nil:
    return await app.handlers.event(event, app)
  else:
    return true

proc dispatchRenderAsync*(app: AsyncApp) =
  ## Invoke the configured render handler against the app's current buffer.
  ##
  ## Does nothing when no handler is configured. Primarily used internally
  ## by `renderAsync`, but exported so tests and callers can trigger the
  ## handler directly.
  if app.handlers.render != nil:
    {.cast(gcsafe).}:
      {.cast(raises: []).}:
        app.handlers.render(app.renderer.getBuffer(), app)

proc dispatchTickAsync*(app: AsyncApp): Future[bool] {.async.} =
  ## Invoke the configured async tick handler.
  ##
  ## Returns `true` when no handler is configured. Primarily used internally
  ## by `tickAsync`, but exported so tests and callers can trigger the handler
  ## directly.
  if app.handlers.tick != nil:
    return await app.handlers.tick(app)
  else:
    return true

proc dispatchTimeoutAsync*(app: AsyncApp): Future[bool] {.async.} =
  ## Invoke the configured async timeout handler.
  ##
  ## Returns `true` when no handler is configured. Primarily used internally
  ## by `tickAsync`, but exported so tests and callers can trigger the handler
  ## directly.
  if app.handlers.timeout != nil:
    return await app.handlers.timeout(app)
  else:
    return true

proc hasTimeoutHandler(app: AsyncApp): bool {.inline.} =
  app.handlers.timeout != nil

proc renderAsync(app: AsyncApp) {.async.} =
  ## Render the current frame asynchronously
  # Clear the buffer
  app.renderer.clear()

  # Call user render handler first (for background content)
  app.dispatchRenderAsync()

  # If window mode is enabled, render windows on top
  if app.state.windowMode and not app.windowManager.isNil:
    app.windowManager.renderSync(app.renderer.getBuffer())

  # Render to terminal (force if requested after resize)
  if app.state.forceNextRender:
    await app.renderer.renderAsync(force = true)
    app.state.forceNextRender = false
  else:
    await app.renderer.renderAsync()

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
    # Check for resize event by polling terminal size
    let currentSize = getTerminalSizeOrDefault()
    if app.state.resizeState.checkResize(currentSize.width, currentSize.height):
      let resizeEvent = Event(kind: Resize)
      await app.handleResizeAsync()

      # Pass resize event to user handler
      if not (await app.dispatchEventAsync(resizeEvent)):
        return false

    # Calculate remaining time until next render (used as poll timeout)
    let remainingTime = app.fpsMonitor.getRemainingFrameTime()

    # Calculate poll timeout, integrating application timeout if set
    let (rawTimeout, hasTimeout) = computePollTimeoutWithState(
      remainingTime,
      app.timings.applicationTimeout,
      app.timings.lastEventTime,
      app.hasTimeoutHandler(),
    )
    let timeout = clampTimeout(rawTimeout, 1)

    # Poll for events with timeout - blocks until event arrives OR timeout expires
    let eventsAvailable = await pollEventsAsync(timeout)

    if eventsAvailable:
      app.timings.lastEventTime = getMonoTime()
    elif hasTimeout:
      # Check if enough idle time has passed to fire timeout handler
      let elapsedAfterPoll =
        (getMonoTime() - app.timings.lastEventTime).inMilliseconds.int
      if isTimeoutReached(app.timings.applicationTimeout, elapsedAfterPoll):
        # Reset timer to prevent busy-loop and enable periodic callbacks
        app.timings.lastEventTime = getMonoTime()
        if not (await app.dispatchTimeoutAsync()):
          return false

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
          if app.state.windowMode and not app.windowManager.isNil:
            {.cast(gcsafe).}:
              discard app.windowManager.handleEventSync(event)
        else:
          break

    # Call tick handler between event processing and rendering
    if not (await app.dispatchTickAsync()):
      return false

    # Render only if enough time has passed for target FPS
    if app.fpsMonitor.shouldRender():
      app.fpsMonitor.startFrame()
      await app.renderAsync()
      app.fpsMonitor.endFrame()
      app.timings.frameCounter.inc()
      app.timings.lastFrameTime = getMonoTime()

    return not app.state.shouldQuit
  except CancelledError as e:
    # Must precede the CatchableError catch-all so chronos cancellation
    # propagates instead of being silently swallowed. runAsync re-raises
    # after cleanup so callers observe the cancel. Under asyncdispatch
    # this branch is unreachable (the placeholder type is never raised),
    # so re-raising is safe on both backends.
    raise e
  except TerminalError as e:
    raise e
  except CatchableError:
    return false

proc cleanupQuietly(app: AsyncApp) {.async.} =
  ## Run cleanupAsync, swallowing exceptions. Used so cleanup failures do
  ## not replace whatever exception (CancelledError, TerminalError, etc.)
  ## the caller is propagating. With `-d:celinaDebug`, the failure is
  ## logged to stderr for diagnostics.
  try:
    await app.cleanupAsync()
  except CatchableError as e:
    when defined(celinaDebug):
      try:
        stderr.writeLine("[celina] cleanupAsync failed: " & e.msg)
      except IOError:
        discard
    discard

when hasChronos and defined(posix):
  proc installSignalHandlersIfRequested(app: AsyncApp) {.gcsafe, raises: [].}
  proc removeSignalHandlers(app: AsyncApp) {.gcsafe, raises: [].}

proc runAsyncInner(app: AsyncApp) {.async.} =
  ## Inner body of runAsync. Separated so the outer wrapper can capture the
  ## Future before any await suspends, exposing it via app.runFuture for
  ## shutdownAsync / cancelAndWait.
  ##
  ## The body has no explicit catch — CancelledError, TerminalError, and
  ## any other CatchableError all propagate through `finally` after
  ## cleanup runs, so the caller observes them.
  when hasChronos and defined(posix):
    installSignalHandlersIfRequested(app)
  try:
    await app.setupAsync()
    app.state.running = true

    # Initialize async event system for resize detection
    initAsyncEventSystem()

    # Main async application loop
    while await app.tickAsync():
      discard
  finally:
    app.state.running = false
    cleanupAsyncEventSystem()
    await cleanupQuietly(app)
    when hasChronos and defined(posix):
      removeSignalHandlers(app)

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
  when hasChronos:
    # chronos creates the Future eagerly when runAsyncInner is called, so we
    # can capture it before awaiting. shutdownAsync targets this Future.
    let inner = runAsyncInner(app)
    app.runFuture = inner
    try:
      await inner
    finally:
      app.runFuture = nil
  else:
    await runAsyncInner(app)

proc quit*(app: AsyncApp) =
  ## Signal the async application to quit gracefully
  app.state.shouldQuit = true

when hasChronos:
  proc shutdownAsync*(app: AsyncApp) {.async.} =
    ## Asynchronously cancel a running runAsync and await its cleanup.
    ##
    ## Unlike `app.quit()` (cooperative; sets shouldQuit and waits for the
    ## current tick to finish), `shutdownAsync` requests immediate
    ## cancellation via chronos and returns only after cleanupAsync has
    ## completed, so the terminal is restored by the time it returns.
    ##
    ## Safe to call when runAsync is not active (no-op) and safe to call
    ## twice concurrently.
    ##
    ## **Do NOT `await` this from inside a user event/tick/render/timeout
    ## handler.** Those handlers run as part of `runAsync`'s Future, so
    ## `cancelAndWait(app.runFuture)` would wait for the very handler
    ## that is awaiting it, causing a deadlock. Use `app.quit()` from
    ## inside handlers; reserve `shutdownAsync` for external callers
    ## such as signal handlers or supervisor coroutines.
    ##
    ## Only available with `-d:asyncBackend=chronos`.
    if app.runFuture.isNil or app.runFuture.finished():
      return
    await cancelAndWait(app.runFuture)

when hasChronos and defined(posix):
  import std/posix

  var installedSignalAppCount: int
    ## Counts AsyncApp instances that currently own SIGINT/SIGTERM
    ## handlers in this process. Bumped by installSignalHandlersIfRequested
    ## on success, decremented by removeSignalHandlers. A second concurrent
    ## installer is rejected so signal delivery to a specific app stays
    ## well-defined (chronos would otherwise register multiple callbacks
    ## with no contract over ordering or udata routing).

  proc onShutdownSignal(udata: pointer) {.gcsafe, raises: [].} =
    ## chronos signal callback. Runs on the dispatcher thread; asyncSpawn
    ## from here is safe. Matches chronos CallbackFunc signature.
    if udata.isNil:
      return
    let app = cast[AsyncApp](udata)
    if app.runFuture.isNil:
      # Handler registration happens inside runAsyncInner's synchronous
      # prologue (before the first await), so app.runFuture is briefly
      # nil between addSignal and the `app.runFuture = inner` assignment
      # in runAsync. The chronos dispatcher does not invoke callbacks
      # during that prologue — it only fires them while polling — so
      # this branch is essentially unreachable in practice. The
      # cooperative-quit fallback is kept defensively: if a signal does
      # somehow arrive here, the next tick observes shouldQuit and the
      # loop exits at its boundary instead of silently dropping the
      # request.
      app.state.shouldQuit = true
      return
    if app.runFuture.finished():
      return
    try:
      asyncSpawn shutdownAsync(app)
    except CatchableError:
      # asyncSpawn can reject when the dispatcher is shutting down. Fall
      # back to a cooperative quit so the loop still exits at the next
      # tick boundary.
      app.state.shouldQuit = true

  proc installSignalHandlersIfRequested(app: AsyncApp) {.gcsafe, raises: [].} =
    ## Register SIGINT and SIGTERM handlers if the config opts in.
    ##
    ## POSIX-only: chronos exposes `addSignal` via std/posix on Linux,
    ## macOS, and other POSIX systems. On Windows this proc and the
    ## surrounding signal-handling block are not compiled at all (no
    ## stub is emitted), so `config.installSignalHandler` has no
    ## effect there.
    ##
    ## Only one AsyncApp per process may install handlers at a time.
    ## A second concurrent installer is rejected (and logged under
    ## `-d:celinaDebug`); the loop still runs but ignores SIGINT/SIGTERM.
    if not app.config.installSignalHandler:
      return
    {.cast(gcsafe).}:
      if installedSignalAppCount > 0:
        when defined(celinaDebug):
          try:
            stderr.writeLine(
              "[celina] installSignalHandler skipped: another AsyncApp " &
                "instance already owns SIGINT/SIGTERM handlers in this process"
            )
          except IOError:
            discard
        return
    let udata = cast[pointer](app)
    try:
      {.cast(gcsafe).}:
        # addSignal raises OSError on epoll/kqueue under POSIX. We catch
        # CatchableError to stay backend-agnostic across chronos versions.
        app.signalHandles.add(addSignal(SIGINT, onShutdownSignal, udata))
        app.signalHandles.add(addSignal(SIGTERM, onShutdownSignal, udata))
    except CatchableError as e:
      when defined(celinaDebug):
        try:
          stderr.writeLine("[celina] addSignal failed: " & e.msg)
        except IOError:
          discard
      discard
    {.cast(gcsafe).}:
      if app.signalHandles.len > 0:
        # Only claim ownership when at least one handler was registered;
        # partial success (e.g., SIGINT ok, SIGTERM failed) still counts
        # so removeSignalHandlers releases the slot.
        inc installedSignalAppCount

  proc removeSignalHandlers(app: AsyncApp) {.gcsafe, raises: [].} =
    ## Unregister handles installed by installSignalHandlersIfRequested.
    ## Safe to call when none were installed.
    let hadHandlers = app.signalHandles.len > 0
    for h in app.signalHandles:
      try:
        {.cast(gcsafe).}:
          removeSignal(h)
      except CatchableError:
        discard
    app.signalHandles.setLen(0)
    {.cast(gcsafe).}:
      if hadHandlers and installedSignalAppCount > 0:
        dec installedSignalAppCount

proc restoreTerminal*(app: AsyncApp) =
  ## Synchronously restore terminal state for use in crash handlers.
  ##
  ## Best-effort, non-async cleanup intended for situations where the async
  ## event loop is unavailable (e.g., signal handlers, unhandled exception
  ## hooks). Delegates to `terminal.cleanup()` (the sync variant on
  ## `AsyncTerminal`) so the disable sequence — and its LIFO ordering —
  ## stays defined in one place alongside `cleanupAsync`.
  ##
  ## Example:
  ## ```nim
  ## proc onCrash() {.noconv.} =
  ##   app.restoreTerminal()
  ##   quit(1)
  ## setControlCHook(onCrash)
  ## ```
  app.terminal.cleanup()

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
  app.state.forceNextRender = true

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
  app.state.windowMode = true
  if app.windowManager.isNil:
    app.windowManager = newAsyncWindowManager()

proc addWindow*(app: AsyncApp, window: Window, autoFocus: bool = true): WindowId =
  ## Add a window to the application.
  ##
  ## The first window added is always auto-focused, and modal windows are
  ## always focused regardless of `autoFocus`. The default (`autoFocus = true`)
  ## takes focus on add; pass `false` to add a non-modal window without
  ## disturbing the current focus. See `AsyncWindowManager.addWindowSync` /
  ## `addWindowAsync` for the full semantics.
  if not app.state.windowMode:
    app.enableWindowMode()
  return app.windowManager.addWindowSync(window, autoFocus)

proc removeWindow*(app: AsyncApp, windowId: WindowId): bool =
  ## Remove a window from the application
  ## Returns true if the window was found and removed, false otherwise
  if app.state.windowMode and not app.windowManager.isNil:
    return app.windowManager.removeWindowSync(windowId)

proc getWindow*(app: AsyncApp, windowId: WindowId): Option[Window] =
  ## Get a window by ID
  if app.state.windowMode and not app.windowManager.isNil:
    return app.windowManager.getWindowSync(windowId)
  return none(Window)

proc focusWindow*(app: AsyncApp, windowId: WindowId): bool =
  ## Focus a specific window
  ## Returns true if the window was found and focused, false otherwise
  if app.state.windowMode and not app.windowManager.isNil:
    return app.windowManager.focusWindowSync(windowId)

proc getFocusedWindow*(app: AsyncApp): Option[Window] =
  ## Get the currently focused window
  if app.state.windowMode and not app.windowManager.isNil:
    return app.windowManager.getFocusedWindowSync()
  return none(Window)

proc getWindows*(app: AsyncApp): seq[Window] =
  ## Get all windows in the application
  if app.state.windowMode and not app.windowManager.isNil:
    return app.windowManager.getWindowsSync()
  return @[]

proc getWindowCount*(app: AsyncApp): int =
  ## Get the total number of windows
  if app.state.windowMode and not app.windowManager.isNil:
    return app.windowManager.getWindowCountSync()
  return 0

proc getFocusedWindowId*(app: AsyncApp): Option[WindowId] =
  ## Get the ID of the currently focused window
  if app.state.windowMode and not app.windowManager.isNil:
    return app.windowManager.getFocusedWindowIdSync()
  return none(WindowId)

proc getWindowInfo*(app: AsyncApp, windowId: WindowId): Option[WindowInfo] =
  ## Get window information by ID
  if app.state.windowMode and not app.windowManager.isNil:
    let windowOpt = app.windowManager.getWindowSync(windowId)
    if windowOpt.isSome():
      return some(windowOpt.get.toWindowInfo())
  return none(WindowInfo)

proc handleWindowEvent*(app: AsyncApp, event: Event): bool =
  ## Handle an event through the window manager
  if app.state.windowMode and not app.windowManager.isNil:
    return app.windowManager.handleEventSync(event)

# State and info queries

proc isRunning*(app: AsyncApp): bool =
  ## Check if app is currently running
  app.state.running

proc getTerminalSize*(app: AsyncApp): Size =
  ## Get current terminal size
  app.terminal.getSize()

proc getConfig*(app: AsyncApp): AppConfig =
  ## Get the stored configuration
  app.config

proc getFrameCount*(app: AsyncApp): int =
  ## Get total frame count
  app.timings.frameCounter

proc getLastFrameTime*(app: AsyncApp): MonoTime =
  ## Get timestamp of last frame
  app.timings.lastFrameTime

# Buffer access for debugging and testing

proc getBuffer*(app: AsyncApp): Buffer =
  ## Get a snapshot (deep copy) of the current display buffer
  ##
  ## Returns a copy of the buffer, safe to inspect without affecting rendering.
  ## Useful for debugging and testing to verify rendered content.
  ##
  ## Example:
  ## ```nim
  ## let buf = app.getBuffer()
  ## echo buf.toStrings()  # Get text content of each row
  ## echo buf[5, 3]        # Get cell at x=5, y=3
  ## ```
  app.renderer.getBuffer().clone()

proc getBufferCell*(app: AsyncApp, x, y: int): Cell =
  ## Get a specific cell from the current display buffer
  app.renderer.getBuffer()[x, y]

proc getBufferContent*(app: AsyncApp): seq[string] =
  ## Get the text content of the current display buffer as a sequence of strings
  ##
  ## Each string represents one row of the buffer. Useful for debugging
  ## and testing to verify what is displayed on screen.
  app.renderer.getBuffer().toStrings()

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

proc quickRunAsync*(
    eventHandler: proc(event: Event, app: AsyncApp): Future[bool] {.async.},
    renderHandler: proc(buffer: var Buffer, app: AsyncApp),
    config: AppConfig = DefaultAppConfig,
) {.async.} =
  ## Quick way to run a simple async CLI application with AsyncApp context handlers.
  ##
  ## Both handlers receive the AsyncApp reference, enabling features like
  ## `app.quit()`, `app.withSuspendAsync`, FPS queries, and window state access.
  ##
  ## Example:
  ## ```nim
  ## import std/strformat
  ##
  ## await quickRunAsync(
  ##   eventHandler = proc(event: Event, app: AsyncApp): Future[bool] {.async.} =
  ##     if event.kind == EventKind.Key and
  ##        event.key.code == KeyCode.Char and event.key.char == "q":
  ##       app.quit()
  ##     return true,
  ##
  ##   renderHandler = proc(buffer: var Buffer, app: AsyncApp) =
  ##     let size = app.getTerminalSize()
  ##     buffer.setString(0, 0, &"{size.width}x{size.height}", defaultStyle())
  ## )
  ## ```
  var app = newAsyncApp(config)
  app.onEventAsync(eventHandler)
  app.onRenderAsync(renderHandler)
  await app.runAsync()
