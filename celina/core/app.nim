## App Module
## ==========
##
## Core application management, lifecycle, and event loop handling.
## Provides the main App type and orchestrates all components.

import std/[options, monotimes, times, strformat]

import
  terminal, buffer, events, renderer, fps, cursor, geometry, errors, terminal_common,
  windows, config, tick_common, app_delegation, app_handlers

export config
export tick_common.TickResult

type
  AppHandlers = object ## User-supplied callbacks invoked during the event loop
    event: proc(event: Event, app: App): EventResult
    render: proc(buffer: var Buffer, app: App)
    tick: proc(app: App): TickResult
    timeout: proc(app: App): TickResult

  AppTimings* = object
    ## Frame and event timing/counters used by the event loop.
    ##
    ## Exported with public fields so `async_app.nim` can reuse this type via
    ## `AsyncAppTimings = AppTimings`. The owning `App.timings` field is
    ## private, so this exposure is internal to the library; user code should
    ## query timing via `getFrameCount` / `getLastFrameTime` instead.
    frameCounter*: int ## Total frame count
    lastFrameTime*: MonoTime ## Timestamp of last frame
    lastEventTime*: MonoTime ## Timestamp of last received event
    applicationTimeout*: int ## Application timeout in ms (0 = disabled)

  AppState* = object
    ## Mutable runtime state of the application.
    ##
    ## Exported with public fields so `async_app.nim` can reuse this type via
    ## `AsyncAppState = AppState`. The owning `App.state` field is private, so
    ## this exposure is internal to the library; user code should drive state
    ## via `quit` / `isRunning` and related procs rather than touching fields.
    shouldQuit*: bool
    running*: bool ## Whether app is currently running
    forceNextRender*: bool ## Force full render on next frame (used after resize)
    windowMode*: bool ## Whether to use window management
    resizeState*: ResizeState ## Shared resize detection state (from tick_common)

  App* = ref object ## Main application context for CLI applications
    terminal: Terminal
    renderer: Renderer
    fpsMonitor: FpsMonitor
    windowManager: WindowManager
    config: AppConfig
    handlers: AppHandlers
    timings: AppTimings
    state: AppState

# Generated: `$`
defineShow(App)

proc newApp*(config: AppConfig = DefaultAppConfig): App =
  ## Create a new CLI application with the specified configuration
  let terminal = newTerminal()
  let termSize = terminal.getSize()
  result = App(
    terminal: terminal,
    renderer: newRenderer(terminal),
    fpsMonitor: newFpsMonitor(if config.targetFps > 0: config.targetFps else: 60),
    config: config,
    handlers: AppHandlers(event: nil, render: nil, tick: nil, timeout: nil),
    timings: AppTimings(
      frameCounter: 0,
      lastFrameTime: getMonoTime(),
      lastEventTime: getMonoTime(),
      applicationTimeout: 0,
    ),
    state: AppState(
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

# Generated: onEvent / onRender / onTick / onTimeout setter families.
# See `app_handlers.nim` for the template bodies, including the legacy
# `bool`-returning overloads kept for backward compatibility.
defineEventHandlerSetters(App)
defineRenderHandlerSetters(App)
defineTickHandlerSetters(App)
defineTimeoutHandlerSetters(App)

# Generated: application timeout setter/getter
defineTimeoutAccessors(App)

# Lifecycle management
proc setup(app: App) =
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

  terminal.hideCursor()
  terminal.clearScreen()

proc handleResize(app: App) =
  ## Handle terminal resize events
  app.terminal.updateSize()
  app.renderer.resize()
  # Clear screen to avoid artifacts from old content
  terminal.clearScreen()
  # Force full render on next frame to ensure clean redraw
  app.state.forceNextRender = true

proc dispatchEvent*(app: App, event: Event): EventResult =
  ## Invoke the configured event handler for the given event.
  ##
  ## Returns `erContinue` when no handler is configured. Primarily used
  ## internally by `tick`, but exported so tests and callers can trigger
  ## the handler directly.
  if app.handlers.event != nil:
    app.handlers.event(event, app)
  else:
    erContinue

proc dispatchRender*(app: App) =
  ## Invoke the configured render handler against the app's current buffer.
  ##
  ## Does nothing when no handler is configured. Primarily used internally
  ## by `render`, but exported so tests and callers can trigger the handler
  ## directly.
  if app.handlers.render != nil:
    app.handlers.render(app.renderer.getBuffer(), app)

proc dispatchTick*(app: App): TickResult =
  ## Invoke the configured tick handler.
  ##
  ## Returns `trContinue` when no handler is configured. Primarily used
  ## internally by `tick`, but exported so tests and callers can trigger
  ## the handler directly.
  if app.handlers.tick != nil:
    app.handlers.tick(app)
  else:
    trContinue

proc dispatchTimeout*(app: App): TickResult =
  ## Invoke the configured timeout handler.
  ##
  ## Returns `trContinue` when no handler is configured. Primarily used
  ## internally by `tick`, but exported so tests and callers can trigger
  ## the handler directly.
  if app.handlers.timeout != nil:
    app.handlers.timeout(app)
  else:
    trContinue

proc hasTimeoutHandler(app: App): bool {.inline.} =
  app.handlers.timeout != nil

proc render(app: App) =
  ## Render the current frame
  # Clear the buffer
  app.renderer.clear()

  # Call user render handler first (for background content)
  app.dispatchRender()

  # If window mode is enabled, render windows on top
  if app.state.windowMode and not app.windowManager.isNil:
    app.windowManager.render(app.renderer.getBuffer())

  # Render to terminal (force if requested after resize)
  if app.state.forceNextRender:
    app.renderer.render(force = true)
    app.state.forceNextRender = false
  else:
    app.renderer.render()

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
    # Check for resize event by polling terminal size
    let currentSize = getTerminalSizeOrDefault()
    if app.state.resizeState.checkResize(currentSize.width, currentSize.height):
      let resizeEvent = Event(kind: Resize)
      app.handleResize()

      # Broadcast to per-window resize handlers before the global handler.
      # Windows that need to relayout (e.g. flex panels) act first, then
      # the global handler observes the final state.
      if app.state.windowMode and not app.windowManager.isNil:
        app.windowManager.dispatchResize(currentSize)

      # Pass resize event to user handler
      case app.dispatchEvent(resizeEvent)
      of erQuit:
        return false
      else:
        discard

    # Calculate remaining time until next render (used as poll timeout)
    let remainingTime = app.fpsMonitor.getRemainingFrameTime()

    # Calculate poll timeout, integrating application timeout if set
    let (timeout, hasTimeout) = computePollTimeoutWithState(
      remainingTime,
      app.timings.applicationTimeout,
      app.timings.lastEventTime,
      app.hasTimeoutHandler(),
    )

    # Poll for events with timeout - blocks until event arrives OR timeout expires
    let eventsAvailable = events.pollEvents(timeout)

    if eventsAvailable:
      app.timings.lastEventTime = getMonoTime()
    elif hasTimeout:
      # Check if enough idle time has passed to fire timeout handler
      let elapsedAfterPoll =
        (getMonoTime() - app.timings.lastEventTime).inMilliseconds.int
      if isTimeoutReached(app.timings.applicationTimeout, elapsedAfterPoll):
        # Reset timer to prevent busy-loop and enable periodic callbacks
        app.timings.lastEventTime = getMonoTime()
        if app.dispatchTimeout() == trQuit:
          return false

    if eventsAvailable:
      var eventCount = 0

      while eventCount < maxEventsPerTick:
        let eventOpt = events.readKeyInput()
        if eventOpt.isSome():
          let event = eventOpt.get
          eventCount.inc()

          # Window-first fallthrough: route through the window manager
          # first; only fall through to the global handler when no
          # window consumed the event.
          var winConsumed = false
          if app.state.windowMode and not app.windowManager.isNil:
            if app.windowManager.handleEvent(event) == erConsume:
              winConsumed = true

          if not winConsumed:
            case app.dispatchEvent(event)
            of erQuit:
              return false
            else:
              discard
        else:
          break

    # Call tick handler between event processing and rendering
    if app.dispatchTick() == trQuit:
      return false

    # Render only if enough time has passed for target FPS
    if app.fpsMonitor.shouldRender():
      app.fpsMonitor.startFrame()
      app.render()
      app.fpsMonitor.endFrame()
      app.timings.frameCounter.inc()
      app.timings.lastFrameTime = getMonoTime()

    return not app.state.shouldQuit
  except TerminalError:
    raise
  except CatchableError as e:
    # Surface unexpected errors instead of silently dropping out of the
    # loop. The previous behavior (`return false`) left users wondering
    # why the app exited; now we log to stderr and re-raise so `run`'s
    # finally block can restore the terminal before the exception
    # propagates to the caller.
    logTickFailure("tick", e)
    raise

proc restoreTerminal*(app: App) =
  ## Best-effort terminal state restoration.
  ##
  ## Used internally by `run()` on exit and safe to call from crash handlers
  ## (signal handlers, unhandled exception hooks). Delegates to
  ## `terminal.cleanup()`, which guards each disable individually and
  ## therefore does not raise. The LIFO disable sequence (synchronized
  ## output, focus events, bracketed paste, mouse, raw mode, alternate
  ## screen) stays defined in one place.
  ##
  ## Example:
  ## ```nim
  ## proc onCrash() {.noconv.} =
  ##   app.restoreTerminal()
  ##   quit(1)
  ## setControlCHook(onCrash)
  ## ```
  app.terminal.cleanup()

# Default Ctrl-C terminal guard
#
# Opt-in via `installDefaultCrashGuard`. Sync App cannot use chronos's
# `addSignal`, so we rely on Nim's `setControlCHook` to restore the
# terminal if Ctrl-C arrives while `run` is active. The install is an
# explicit function call rather than a config flag because
# `setControlCHook` has no `unset` counterpart: once installed, the
# hook is process-wide and outlives `run`. Surfacing the install at
# the call site (instead of hiding it behind a boolean) makes that
# permanence visible.
#
# Unhandled exceptions raised from inside the tick loop are restored
# by `run`'s own `try/finally`, so there is no `onUnhandledException`
# hook here — by the time it would fire, the terminal has already
# been restored and the hook would have no work to do.

var crashGuardApp: App
  ## Currently registered crash-guard owner. Nil until the first
  ## `installDefaultCrashGuard` call; a later call with a different
  ## `App` replaces this slot. The C-level Ctrl-C hook itself is
  ## registered only once per process. Plain global (not
  ## `{.threadvar.}`) because the signal callback may fire on any
  ## thread; running multiple sync `App`s in parallel within one
  ## process is unsupported.

proc onCelinaControlC() {.noconv.} =
  ## Default Ctrl-C hook: restore the registered app's terminal, then
  ## `quit(1)`. Safe to be invoked re-entrantly — a second SIGINT
  ## during `quit` terminates the process directly.
  {.cast(gcsafe).}:
    if crashGuardApp != nil:
      try:
        crashGuardApp.restoreTerminal()
      except CatchableError:
        discard
  quit(1)

proc installDefaultCrashGuard*(app: App) =
  ## Register a process-global Ctrl-C handler that restores `app`'s
  ## terminal before exiting with `quit(1)`.
  ##
  ## **Lifecycle:** the hook is process-wide and permanent. Nim does
  ## not expose `unsetControlCHook`, so it stays installed after
  ## `run` returns. A subsequent call with a different `App` replaces
  ## the active reference; the C-level hook is registered only once.
  ##
  ## **Caveat:** any prior Ctrl-C handler installed by the
  ## application is overwritten and cannot be restored.
  ##
  ## Call once during startup, before `run`:
  ## ```nim
  ## var app = newApp()
  ## installDefaultCrashGuard(app)
  ## app.run()
  ## ```
  ##
  ## Unhandled exceptions raised from the tick loop are restored by
  ## `run`'s `try/finally` regardless of whether this guard is
  ## installed.
  if crashGuardApp == nil:
    setControlCHook(onCelinaControlC)
  crashGuardApp = app

proc run*(app: App) =
  ## Run the application main loop.
  ##
  ## Returns normally when the app quits via `app.quit()` or when the
  ## quit handler signals shutdown.
  ##
  ## **Behavior change:** an unexpected `CatchableError` raised from
  ## inside the tick loop (event handler, render, tick callback) is
  ## now re-raised to the caller after the terminal is restored,
  ## instead of being swallowed and silently exiting the loop.
  ## `TerminalError` continues to propagate as before. Wrap `run` in a
  ## `try`/`except` if you need to recover or report; without it, the
  ## program will terminate with the exception trace once `run`
  ## returns.
  ##
  ## For Ctrl-C safety, call `installDefaultCrashGuard(app)` once
  ## during startup before invoking `run`.
  when defined(celinaDebug):
    if app.config.installSignalHandler:
      try:
        stderr.writeLine(
          "[celina] config.installSignalHandler is ignored by the sync " &
            "App; call installDefaultCrashGuard(app) instead"
        )
      except IOError:
        discard
  try:
    app.setup()
    app.state.running = true

    # Main application loop
    while app.tick():
      discard
  finally:
    app.state.running = false
    app.restoreTerminal()

# Generated: quit + mouse runtime toggles
defineQuit(App)
defineMouseDelegation(App)

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
  app.state.forceNextRender = true

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

# Generated: FPS control delegation
defineFpsDelegation(App)

# Cursor control delegation (generated via `defineCursorDelegation`)
defineCursorDelegation(App)

# Generated: window management delegation (11 procs)
defineWindowDelegation(App)

# State queries + buffer access (generated)
defineStateQueries(App)
defineBufferDelegation(App)

# Convenience functions

proc quickRun*(
    eventHandler: proc(event: Event): EventResult,
    renderHandler: proc(buffer: var Buffer),
    config: AppConfig = DefaultAppConfig,
) =
  ## Quick way to run a simple CLI application.
  ##
  ## Example:
  ## ```nim
  ## quickRun(
  ##   eventHandler = proc(event: Event): EventResult =
  ##     if event.kind == EventKind.Key and
  ##         event.key.code == KeyCode.Char and event.key.char == "q":
  ##       return erQuit
  ##     return erContinue,
  ##
  ##   renderHandler = proc(buffer: var Buffer) =
  ##     buffer.setString(10, 5, "Press 'q' to quit", defaultStyle())
  ## )
  ## ```
  var app = newApp(config)
  app.onEvent(eventHandler)
  app.onRender(renderHandler)
  app.run()

proc quickRun*(
    eventHandler: proc(event: Event, app: App): EventResult,
    renderHandler: proc(buffer: var Buffer, app: App),
    config: AppConfig = DefaultAppConfig,
) =
  ## Quick way to run a simple CLI application with App context handlers.
  ##
  ## Both handlers receive the App reference, enabling features like
  ## `app.quit()`, `app.withSuspend`, FPS queries, and window state access.
  ##
  ## Example:
  ## ```nim
  ## import std/strformat
  ##
  ## quickRun(
  ##   eventHandler = proc(event: Event, app: App): EventResult =
  ##     if event.kind == EventKind.Key and
  ##         event.key.code == KeyCode.Char and event.key.char == "q":
  ##       app.quit()
  ##     return erContinue,
  ##
  ##   renderHandler = proc(buffer: var Buffer, app: App) =
  ##     let size = app.getTerminalSize()
  ##     buffer.setString(0, 0, &"{size.width}x{size.height}", defaultStyle())
  ## )
  ## ```
  var app = newApp(config)
  app.onEvent(eventHandler)
  app.onRender(renderHandler)
  app.run()

proc quickRun*(
    eventHandler: proc(event: Event): bool,
    renderHandler: proc(buffer: var Buffer),
    config: AppConfig = DefaultAppConfig,
) {.deprecated: "Use a handler returning EventResult instead of bool".} =
  ## Legacy `bool`-returning overload. `false` -> `erQuit`,
  ## `true` -> `erContinue`. Prefer the `EventResult`-returning overload.
  var app = newApp(config)
  let captured = eventHandler
  app.onEvent(
    proc(event: Event): EventResult =
      if captured(event): erContinue else: erQuit
  )
  app.onRender(renderHandler)
  app.run()

proc quickRun*(
    eventHandler: proc(event: Event, app: App): bool,
    renderHandler: proc(buffer: var Buffer, app: App),
    config: AppConfig = DefaultAppConfig,
) {.deprecated: "Use a handler returning EventResult instead of bool".} =
  ## Legacy `bool`-returning overload with App context. `false` -> `erQuit`,
  ## `true` -> `erContinue`. Prefer the `EventResult`-returning overload.
  var app = newApp(config)
  let captured = eventHandler
  app.onEvent(
    proc(event: Event, app: App): EventResult =
      if captured(event, app): erContinue else: erQuit
  )
  app.onRender(renderHandler)
  app.run()
