## Async Application framework
##
## This module provides the main AsyncApp type and async event loop
## implementation using either Chronos or std/asyncdispatch.

import std/[options, monotimes, times, strformat]

import async_backend, async_terminal, async_events, async_renderer
from async_io import
  AsyncInputReader, newAsyncInputReader, closeAsyncInputReader, isLive
import
  ../core/[
    geometry, buffer, events, fps, config, tick_common, cursor, terminal,
    terminal_common, errors, windows, app, app_delegation, app_handlers,
  ]

export config
export tick_common.TickResult

type
  AsyncAppHandlers = object
    ## User-supplied callbacks invoked during the async event loop
    event: proc(event: Event, app: AsyncApp): Future[EventResult] {.async.}
    render: proc(buffer: var Buffer, app: AsyncApp)
    tick: proc(app: AsyncApp): Future[TickResult] {.async.}
    timeout: proc(app: AsyncApp): Future[TickResult] {.async.}

  AsyncAppTimings* = AppTimings
    ## Alias of AppTimings; async event loop reuses the same timing fields.

  AsyncAppState* = AppState
    ## Alias of AppState; async runtime state is structurally identical.

  ## Main async application context for CLI applications
  AsyncApp* = ref object
    terminal: AsyncTerminal
    renderer: AsyncRenderer
    fpsMonitor: FpsMonitor
    windowManager: WindowManager
    inputReader: AsyncInputReader
      ## Per-app non-blocking stdin reader. Owned by the AsyncApp; lazily
      ## created in `setupAsync` (so a `newAsyncApp` that is never run
      ## does not leak a selector fd) and closed in `runAsyncInner`'s
      ## cleanup so the selector/fd resources do not outlive the app
      ## instance.
    config: AppConfig
    handlers: AsyncAppHandlers
    timings: AsyncAppTimings
    state: AsyncAppState
    terminalActive: bool
      ## True from `runAsync`'s setup until its final restore. Unlike
      ## `state.running`, it also covers setup.
    when hasChronos:
      runFuture: Future[void]
        ## Set on runAsync entry, cleared on exit. shutdownAsync targets
        ## this Future via cancelAndWait. nil before/after runAsync.
      runEnding: bool
        ## Set once the run starts to end (cleanup or `shutdownAsync`).
        ## Reset on each `runAsync` entry.
      when defined(posix):
        signalHandles: seq[SignalHandle]
          ## SIGINT/SIGTERM handles registered when
          ## config.installSignalHandler is true. Cleared during runAsync
          ## cleanup so handles do not outlive the AsyncApp instance.
          ## POSIX-only: chronos signal APIs are not available on Windows.
        caughtSignal: cint
          ## Signal that started the stop, 0 if none. Read via `stopSignal`.
          ## Reset on each `runAsync` entry.

  AsyncAppError* = object of CatchableError

# Generated: `$`
defineShow(AsyncApp)

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

  # Initialize window manager if enabled
  if config.windowMode:
    result.windowManager = newWindowManager()

# Event and render handlers
#
# Dispatch order (window-first fallthrough):
#   1. When `windowMode` is enabled, the focused window's handlers run
#      first via the window manager.
#   2. The global handler set here runs only if the window manager
#      returned `erContinue` (i.e. no window/widget consumed the event).
#
# **Behavior change** (vs. pre-`EventResult` releases): previously the
# global handler ran *before* window dispatch and window dispatch was
# unconditional, so both layers saw every event. Now a window handler
# returning `true` (legacy) / `erConsume` (new) stops the event from
# reaching the global handler. Apps that relied on the global handler
# observing keys already consumed by a focused window must either
# (a) return `false` / `erContinue` from the window handler, or
# (b) move the logic into the window handler.
#
# Apps not using `windowMode` are unaffected.
#
# Backward compatibility: `bool`-returning overloads accept legacy
# handlers where `false` signals quit and `true` signals continue. These
# are wrapped to return `erQuit`/`erContinue` respectively.

# Generated: onEventAsync / onRenderAsync / onTickAsync / onTimeoutAsync
# setter families. See `app_handlers.nim` for the template bodies,
# including the legacy `Future[bool]`-returning overloads kept for
# backward compatibility.
defineEventHandlerSettersAsync(AsyncApp)
defineRenderHandlerSettersAsync(AsyncApp)
defineTickHandlerSettersAsync(AsyncApp)
defineTimeoutHandlerSettersAsync(AsyncApp)

# Generated: application timeout setter/getter
defineTimeoutAccessors(AsyncApp)

# AsyncApp Lifecycle Management

proc isInputReaderLive*(app: AsyncApp): bool =
  ## Whether the app currently holds a live input reader. Outside an active
  ## run this is false (the reader is created in `setupAsync` and dropped in
  ## `runAsyncInner` cleanup). Mainly useful for tests asserting that a second
  ## `runAsync` re-creates a usable reader instead of reusing a closed one.
  app.inputReader.isLive()

proc setupAsync(app: AsyncApp) {.async.} =
  if app.inputReader.isNil:
    app.inputReader = newAsyncInputReader()

  if app.config.alternateScreen:
    await app.terminal.enableAlternateScreenAsync()

  if app.config.rawMode:
    app.terminal.enableRawMode(app.inputReader)

  app.terminal.updateSize()

  if app.config.mouseCapture:
    await app.terminal.enableMouseAsync()

  if app.config.bracketedPaste:
    await app.terminal.enableBracketedPasteAsync()

  if app.config.focusEvents:
    await app.terminal.enableFocusEventsAsync()

  await hideCursorAsync()
  await clearScreenAsync()

proc cleanupAsync(app: AsyncApp) {.async.} =
  ## Internal async cleanup procedure to restore terminal state.
  ##
  ## Delegates the disable sequence to `terminal.cleanupAsync()` so the LIFO
  ## ordering (raw mode before alternate screen) is defined in one place.
  ## Each underlying `disableX` is idempotent and state-gated, so calling
  ## the full sequence is safe regardless of `app.config` flags.
  await app.terminal.cleanupAsync(app.inputReader)

proc handleResizeAsync(app: AsyncApp) {.async.} =
  ## Handle terminal resize events asynchronously
  app.terminal.updateSize()
  app.renderer.resize()
  # Clear screen to avoid artifacts from old content
  await clearScreenAsync()
  # Force full render on next frame to ensure clean redraw
  app.state.forceNextRender = true

proc dispatchEventAsync*(app: AsyncApp, event: Event): Future[EventResult] {.async.} =
  ## Invoke the configured async event handler for the given event.
  ##
  ## Returns `erContinue` when no handler is configured. Primarily used
  ## internally by `tickAsync`, but exported so tests and callers can
  ## trigger the handler directly.
  if app.handlers.event != nil:
    return await app.handlers.event(event, app)
  else:
    return erContinue

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

proc dispatchTickAsync*(app: AsyncApp): Future[TickResult] {.async.} =
  ## Invoke the configured async tick handler.
  ##
  ## Returns `trContinue` when no handler is configured. Primarily used
  ## internally by `tickAsync`, but exported so tests and callers can trigger
  ## the handler directly.
  if app.handlers.tick != nil:
    return await app.handlers.tick(app)
  else:
    return trContinue

proc dispatchTimeoutAsync*(app: AsyncApp): Future[TickResult] {.async.} =
  ## Invoke the configured async timeout handler.
  ##
  ## Returns `trContinue` when no handler is configured. Primarily used
  ## internally by `tickAsync`, but exported so tests and callers can trigger
  ## the handler directly.
  if app.handlers.timeout != nil:
    return await app.handlers.timeout(app)
  else:
    return trContinue

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
    app.windowManager.render(app.renderer.getBuffer())

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

      # Broadcast to per-window resize handlers before the global handler
      # (same ordering as the sync App; see `core/app.nim`).
      if app.state.windowMode and not app.windowManager.isNil:
        {.cast(gcsafe).}:
          app.windowManager.dispatchResize(currentSize)

      # Pass resize event to user handler
      case (await app.dispatchEventAsync(resizeEvent))
      of erQuit:
        return false
      else:
        discard

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
    let eventsAvailable = await app.inputReader.pollEventsAsync(timeout)

    if eventsAvailable:
      app.timings.lastEventTime = getMonoTime()
    elif hasTimeout:
      # Check if enough idle time has passed to fire timeout handler
      let elapsedAfterPoll =
        (getMonoTime() - app.timings.lastEventTime).inMilliseconds.int
      if isTimeoutReached(app.timings.applicationTimeout, elapsedAfterPoll):
        # Reset timer to prevent busy-loop and enable periodic callbacks
        app.timings.lastEventTime = getMonoTime()
        if (await app.dispatchTimeoutAsync()) == trQuit:
          return false

    if eventsAvailable:
      var eventCount = 0

      while eventCount < maxEventsPerTick:
        let eventOpt = await app.inputReader.pollKeyAsync()
        if eventOpt.isSome():
          let event = eventOpt.get()
          eventCount.inc()

          # Window-first fallthrough: route through the window manager
          # first; only fall through to the global handler when no
          # window consumed the event.
          #
          # `try/except Exception` is required here because window
          # handlers carry no `{.raises.}` annotation, so chronos's
          # `{.async.}` effect inference would otherwise propagate a
          # bare `Exception` raise out of `tickAsync`. A handler that
          # raises is treated as `erContinue` so the global handler can
          # still react. `Defect`s are caught under `--panics:off`
          # (default) and propagate under `--panics:on`.
          var winConsumed = false
          if app.state.windowMode and not app.windowManager.isNil:
            {.cast(gcsafe).}:
              try:
                if app.windowManager.handleEvent(event) == erConsume:
                  winConsumed = true
              except Exception:
                discard

          if not winConsumed:
            case (await app.dispatchEventAsync(event))
            of erQuit:
              return false
            else:
              discard
        else:
          break

    # Call tick handler between event processing and rendering
    if (await app.dispatchTickAsync()) == trQuit:
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
  except CatchableError as e:
    # Surface unexpected errors instead of silently dropping out of the
    # loop (mirrors the sync `App.tick`). The cleanup in
    # `runAsyncInner`'s finally still restores the terminal before the
    # exception reaches the caller.
    logTickFailure("tickAsync", e)
    raise e

proc cleanupQuietly(app: AsyncApp) {.async.} =
  ## Run cleanupAsync, swallowing exceptions. Used so cleanup failures do
  ## not replace whatever exception (CancelledError, TerminalError, etc.)
  ## the caller is propagating. With `-d:celinaDebug`, the failure is
  ## logged to stderr for diagnostics.
  ##
  ## A cancel during cleanup is dropped too: the terminal is restored by then.
  try:
    await app.cleanupAsync()
  except CancelledError:
    discard
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
    app.terminalActive = true
    await app.setupAsync()
    app.state.running = true

    # Main async application loop
    while await app.tickAsync():
      discard
  finally:
    app.state.running = false
    when hasChronos:
      app.runEnding = true
    try:
      await cleanupQuietly(app)
    finally:
      # Cleared even if the await is cancelled.
      app.terminalActive = false
    app.inputReader.closeAsyncInputReader()
    app.inputReader = nil
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
  ## **Behavior change:** an unexpected `CatchableError` raised from
  ## inside the tick loop is now re-raised to the awaiter after
  ## cleanup runs, instead of being swallowed and silently exiting the
  ## loop. `CancelledError` and `TerminalError` continue to propagate
  ## as before. Wrap `await app.runAsync()` in a `try`/`except` if you
  ## need to recover or report.
  ##
  ## With `config.installSignalHandler`, a SIGINT/SIGTERM cancels the run
  ## through `shutdownAsync`, so it usually ends with `CancelledError`
  ## after cleanup (it can also return normally; see `stopSignal`).
  ## `stopSignal` tells which signal it was, and `exitIfStoppedBySignal`
  ## passes it on to the parent process.
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
    app.runEnding = false
    when defined(posix):
      app.caughtSignal = 0
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

proc stopSignal*(app: AsyncApp): cint =
  ## The SIGINT/SIGTERM whose `installSignalHandler` handler stopped the
  ## last `runAsync`, or 0 if none. Only the signal that starts the stop is
  ## recorded; later ones still cancel (a second Ctrl-C can break a stuck
  ## cleanup) but are not recorded. Valid until the next `runAsync`.
  ## Always 0 unless built with chronos on POSIX.
  ##
  ## `runAsync` then usually raises `CancelledError` but can also return
  ## normally; see `exitIfStoppedBySignal`.
  when hasChronos and defined(posix): app.caughtSignal else: 0

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
    app.runEnding = true
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

  proc onShutdownSignal(app: AsyncApp, sig: cint) {.gcsafe, raises: [].} =
    ## Shared body of the chronos signal callbacks. Runs on the dispatcher
    ## thread; asyncSpawn from here is safe. A signal that arrives once the
    ## run is ending still cancels (a cancelled cleanup falls back to the
    ## emergency reset) but is not recorded.
    if not app.runEnding:
      app.caughtSignal = sig
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
      app.runEnding = true
      app.state.shouldQuit = true
      return
    try:
      # shutdownAsync sets runEnding before its first await.
      asyncSpawn shutdownAsync(app)
    except CatchableError:
      # asyncSpawn can reject when the dispatcher is shutting down. Fall
      # back to a cooperative quit so the loop still exits at the next
      # tick boundary.
      app.runEnding = true
      app.state.shouldQuit = true

  proc onSigint(udata: pointer) {.gcsafe, raises: [].} =
    ## chronos CallbackFunc for SIGINT.
    if not udata.isNil:
      onShutdownSignal(cast[AsyncApp](udata), SIGINT)

  proc onSigterm(udata: pointer) {.gcsafe, raises: [].} =
    ## chronos CallbackFunc for SIGTERM.
    if not udata.isNil:
      onShutdownSignal(cast[AsyncApp](udata), SIGTERM)

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
        app.signalHandles.add(addSignal(SIGINT, onSigint, udata))
        app.signalHandles.add(addSignal(SIGTERM, onSigterm, udata))
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

  proc exitIfStoppedBySignal*(app: AsyncApp) =
    ## If `stopSignal` is set, end the process by that signal so the
    ## parent sees it (a shell reports 130 for SIGINT); otherwise return.
    ## `quit(128 + sig)` cannot do this: Nim clamps POSIX exit codes to 127.
    ##
    ## Call it after `runAsync` ends, once nothing else uses the terminal
    ## (it only checks this app, and returns while `runAsync` owns it).
    ## stdout and stderr are flushed; exit procs, `finally` and `defer` do
    ## not run. Falls back to exit status 128 + signal. No-op unless built
    ## with chronos on POSIX.
    ##
    ## ```nim
    ## try:
    ##   await app.runAsync()
    ## except CancelledError as e:
    ##   if app.stopSignal == 0:
    ##     raise e
    ## app.exitIfStoppedBySignal()
    ## ```
    let sig = app.caughtSignal
    if sig == 0 or app.terminalActive:
      # Dying while runAsync owns the terminal would leave it raw.
      return
    try:
      stdout.flushFile()
      stderr.flushFile()
    except IOError:
      discard
    # Default action first, so a pending signal released by the unblock
    # below does not run an app handler (e.g. setControlCHook) instead.
    discard signal(sig, SIG_DFL)
    var mask, oldMask: Sigset
    discard sigemptyset(mask)
    discard sigaddset(mask, sig)
    discard pthread_sigmask(SIG_UNBLOCK, mask, oldMask)
    # To this thread: kill(getpid()) may hand it to another thread and
    # return before the process dies.
    discard pthread_kill(pthread_self(), sig)
    exitnow(128 + sig)

else:
  proc exitIfStoppedBySignal*(app: AsyncApp) =
    ## No-op: signals are only handled with chronos on POSIX.
    discard

proc restoreTerminal*(app: AsyncApp) =
  ## Synchronously restore terminal state for use in crash handlers.
  ##
  ## Best-effort, non-async cleanup intended for situations where the async
  ## event loop is unavailable (e.g., unhandled exception hooks). Delegates
  ## to `terminal.cleanup()` (the sync variant on `AsyncTerminal`) so the
  ## disable sequence — and its LIFO ordering — stays defined in one place
  ## alongside `cleanupAsync`.
  ##
  ## From a signal handler, prefer `emergencyRestore`, which also aborts a
  ## half-written escape sequence.
  app.terminal.cleanup()

proc emergencyRestore*(app: AsyncApp) =
  ## Restore the terminal from a signal handler or crash hook. While
  ## `runAsync` owns the terminal, delegates to `terminal.emergencyRestore()`;
  ## otherwise (including while suspended) falls back to `restoreTerminal`
  ## so the full reset stays out of piped output and a child's screen.
  ## Never raises.
  ##
  ## Example:
  ## ```nim
  ## proc onCrash() {.noconv.} =
  ##   app.emergencyRestore()
  ##   quit(1)
  ## setControlCHook(onCrash)
  ## ```
  if app.terminalActive and not app.terminal.isSuspended:
    app.terminal.emergencyRestore(app.inputReader)
  else:
    app.restoreTerminal()

# Mouse control
# Generated: mouse runtime toggles
defineMouseDelegation(AsyncApp)

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
  await app.terminal.suspendAsync(app.inputReader)

proc resumeAsync*(app: AsyncApp) {.async.} =
  ## Resume the TUI after a `suspendAsync()` call.
  ##
  ## Restores terminal state and forces a full redraw on the next frame.
  await app.terminal.resumeAsync(app.inputReader)
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
# Generated: FPS control delegation
defineFpsDelegation(AsyncApp)

# Cursor control delegation (generated via `defineCursorDelegation`)
defineCursorDelegation(AsyncApp)

# Generated: window management delegation (11 procs)
defineWindowDelegation(AsyncApp)

# State queries + buffer access (generated)
defineStateQueries(AsyncApp)
defineBufferDelegation(AsyncApp)

# Convenience functions

proc quickRunAsync*(
    eventHandler: proc(event: Event): Future[EventResult] {.async.},
    renderHandler: proc(buffer: var Buffer),
    config: AppConfig = DefaultAppConfig,
) {.async.} =
  ## Quick way to run a simple async CLI application.
  ##
  ## With `config.installSignalHandler`, a SIGINT/SIGTERM usually ends it
  ## with `CancelledError`, and the app is not reachable for `stopSignal`.
  ## Use `newAsyncApp` + `runAsync` when the signal matters.
  ##
  ## Example:
  ## ```nim
  ## await quickRunAsync(
  ##   eventHandler = proc(event: Event): Future[EventResult] {.async.} =
  ##     if event.kind == EventKind.Key and
  ##         event.key.code == KeyCode.Char and event.key.char == "q":
  ##       return erQuit
  ##     return erContinue,
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
    eventHandler: proc(event: Event, app: AsyncApp): Future[EventResult] {.async.},
    renderHandler: proc(buffer: var Buffer, app: AsyncApp),
    config: AppConfig = DefaultAppConfig,
) {.async.} =
  ## Quick way to run a simple async CLI application with AsyncApp context handlers.
  ##
  ## With `config.installSignalHandler`, a SIGINT/SIGTERM usually ends it
  ## with `CancelledError`; keep the `app` passed to a handler to read
  ## `stopSignal` or call `exitIfStoppedBySignal` afterwards.
  ##
  ## Both handlers receive the AsyncApp reference, enabling features like
  ## `app.quit()`, `app.withSuspendAsync`, FPS queries, and window state access.
  ##
  ## Example:
  ## ```nim
  ## import std/strformat
  ##
  ## await quickRunAsync(
  ##   eventHandler = proc(event: Event, app: AsyncApp): Future[EventResult] {.async.} =
  ##     if event.kind == EventKind.Key and
  ##         event.key.code == KeyCode.Char and event.key.char == "q":
  ##       app.quit()
  ##     return erContinue,
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

proc quickRunAsync*(
    eventHandler: proc(event: Event): Future[bool] {.async.},
    renderHandler: proc(buffer: var Buffer),
    config: AppConfig = DefaultAppConfig,
) {.
    async,
    deprecated: "Use a handler returning Future[EventResult] instead of Future[bool]"
.} =
  ## Legacy `bool`-returning overload. `false` -> `erQuit`,
  ## `true` -> `erContinue`. Prefer the `EventResult`-returning overload.
  var app = newAsyncApp(config)
  let captured = eventHandler
  app.onEventAsync(
    proc(event: Event): Future[EventResult] {.async.} =
      let cont = await captured(event)
      return if cont: erContinue else: erQuit
  )
  app.onRenderAsync(renderHandler)
  await app.runAsync()

proc quickRunAsync*(
    eventHandler: proc(event: Event, app: AsyncApp): Future[bool] {.async.},
    renderHandler: proc(buffer: var Buffer, app: AsyncApp),
    config: AppConfig = DefaultAppConfig,
) {.
    async,
    deprecated: "Use a handler returning Future[EventResult] instead of Future[bool]"
.} =
  ## Legacy `bool`-returning overload with AsyncApp context.
  ## `false` -> `erQuit`, `true` -> `erContinue`. Prefer the
  ## `EventResult`-returning overload.
  var app = newAsyncApp(config)
  let captured = eventHandler
  app.onEventAsync(
    proc(event: Event, app: AsyncApp): Future[EventResult] {.async.} =
      let cont = await captured(event, app)
      return if cont: erContinue else: erQuit
  )
  app.onRenderAsync(renderHandler)
  await app.runAsync()
