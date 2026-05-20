## App Module
## ==========
##
## Core application management, lifecycle, and event loop handling.
## Provides the main App type and orchestrates all components.

import std/[options, monotimes, times, strformat]

import
  terminal, buffer, events, renderer, fps, cursor, geometry, errors, terminal_common,
  windows, config, tick_common

export config

type
  AppHandlers = object ## User-supplied callbacks invoked during the event loop
    event: proc(event: Event, app: App): EventResult
    render: proc(buffer: var Buffer, app: App)
    tick: proc(app: App): bool
    timeout: proc(app: App): bool

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

proc `$`*(app: App): string =
  ## String representation of App for debugging
  let windowCount =
    if app.state.windowMode and not app.windowManager.isNil:
      app.windowManager.windows.len
    else:
      0
  &"App(running: {app.state.running}, fps: {app.fpsMonitor.getCurrentFps():.1f}, frames: {app.timings.frameCounter}, windows: {windowCount}, config: {app.config})"

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

proc onEvent*(app: App, handler: proc(event: Event): EventResult) =
  ## Set the event handler for the application.
  ##
  ## Returning `erQuit` from the handler exits the application loop.
  ## `erConsume` and `erContinue` are equivalent at the global layer
  ## because no further layer follows it.
  ##
  ## Example:
  ## ```nim
  ## app.onEvent proc(event: Event): EventResult =
  ##   if event.kind == Key and event.key.code == KeyCode.Char and
  ##       event.key.char == "q":
  ##     return erQuit
  ##   return erContinue
  ## ```
  app.handlers.event =
    if handler.isNil:
      nil
    else:
      let captured = handler
      proc(event: Event, app: App): EventResult =
        captured(event)

proc onEvent*(app: App, handler: proc(event: Event, app: App): EventResult) =
  ## Set the event handler with `App` context for the application.
  ##
  ## See the single-arg overload for the return-value contract.
  app.handlers.event = handler

proc onEvent*(
    app: App, handler: proc(event: Event): bool
) {.deprecated: "Use a handler returning EventResult instead of bool".} =
  ## Legacy `bool`-returning overload. `false` -> `erQuit`,
  ## `true` -> `erContinue`. Prefer the `EventResult`-returning overload
  ## in new code.
  app.handlers.event =
    if handler.isNil:
      nil
    else:
      let captured = handler
      proc(event: Event, app: App): EventResult =
        if captured(event): erContinue else: erQuit

proc onEvent*(
    app: App, handler: proc(event: Event, app: App): bool
) {.deprecated: "Use a handler returning EventResult instead of bool".} =
  ## Legacy `bool`-returning overload with `App` context.
  ## `false` -> `erQuit`, `true` -> `erContinue`.
  ## Prefer the `EventResult`-returning overload in new code; see its
  ## docstring for example usage.
  app.handlers.event =
    if handler.isNil:
      nil
    else:
      let captured = handler
      proc(event: Event, app: App): EventResult =
        if captured(event, app): erContinue else: erQuit

proc onRender*(app: App, handler: proc(buffer: var Buffer)) =
  ## Set the render handler for the application
  ##
  ## For access to the App object (e.g., to query FPS, window state,
  ## or terminal size during rendering), use the overload that accepts
  ## `proc(buffer: var Buffer, app: App)` instead.
  app.handlers.render =
    if handler.isNil:
      nil
    else:
      let captured = handler
      proc(buffer: var Buffer, app: App) =
        captured(buffer)

proc onRender*(app: App, handler: proc(buffer: var Buffer, app: App)) =
  ## Set the render handler with App context for the application
  ##
  ## This overload provides access to the App object, enabling the
  ## render handler to query runtime state such as current FPS,
  ## terminal size, or window manager information.
  ##
  ## Example:
  ## ```nim
  ## app.onRender proc(buffer: var Buffer, app: App) =
  ##   let fps = app.getCurrentFps()
  ##   buffer.setString(0, 0, &"FPS: {fps:.1f}", defaultStyle())
  ## ```
  app.handlers.render = handler

proc onTick*(app: App, handler: proc(): bool) =
  ## Set the tick handler called each frame between event processing and rendering.
  ##
  ## Return true to continue running, false to quit.
  app.handlers.tick =
    if handler.isNil:
      nil
    else:
      let captured = handler
      proc(app: App): bool =
        captured()

proc onTick*(app: App, handler: proc(app: App): bool) =
  ## Set the tick handler with App context called each frame between event processing and rendering.
  ##
  ## Return true to continue running, false to quit.
  app.handlers.tick = handler

# Application timeout
proc onTimeout*(app: App, handler: proc(): bool) =
  ## Set the timeout handler for the application.
  ##
  ## The handler is called when no input events are received within
  ## the application timeout period. Return true to continue running,
  ## false to quit the application.
  ##
  ## For access to the App object, use the overload that accepts
  ## `proc(app: App): bool` instead.
  app.handlers.timeout =
    if handler.isNil:
      nil
    else:
      let captured = handler
      proc(app: App): bool =
        captured()

proc onTimeout*(app: App, handler: proc(app: App): bool) =
  ## Set the timeout handler with App context for the application.
  ##
  ## The handler is called when no input events are received within
  ## the application timeout period. Return true to continue running,
  ## false to quit the application.
  app.handlers.timeout = handler

proc setApplicationTimeout*(app: App, timeoutMs: int) =
  ## Set the application timeout in milliseconds.
  ##
  ## When set to a positive value, the timeout handler will be called
  ## if no input events are received within this duration.
  ## Set to 0 to disable the application timeout.
  app.timings.applicationTimeout = timeoutMs

proc getApplicationTimeout*(app: App): int =
  ## Get the current application timeout in milliseconds.
  ##
  ## Returns 0 if the timeout is disabled.
  app.timings.applicationTimeout

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

proc dispatchTick*(app: App): bool =
  ## Invoke the configured tick handler.
  ##
  ## Returns `true` when no handler is configured. Primarily used internally
  ## by `tick`, but exported so tests and callers can trigger the handler
  ## directly.
  if app.handlers.tick != nil:
    app.handlers.tick(app)
  else:
    true

proc dispatchTimeout*(app: App): bool =
  ## Invoke the configured timeout handler.
  ##
  ## Returns `true` when no handler is configured. Primarily used internally
  ## by `tick`, but exported so tests and callers can trigger the handler
  ## directly.
  if app.handlers.timeout != nil:
    app.handlers.timeout(app)
  else:
    true

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
        if not app.dispatchTimeout():
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
    if not app.dispatchTick():
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

proc quit*(app: App) =
  ## Signal the application to quit gracefully
  app.state.shouldQuit = true

# Mouse control
proc enableMouse*(app: App) =
  ## Enable mouse reporting at runtime
  app.terminal.enableMouse()

proc disableMouse*(app: App) =
  ## Disable mouse reporting at runtime
  app.terminal.disableMouse()

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
  app.state.windowMode = true
  if app.windowManager.isNil:
    app.windowManager = newWindowManager()

proc addWindow*(app: App, window: Window, autoFocus: bool = true): WindowId =
  ## Add a window to the application.
  ##
  ## The first window added is always auto-focused, and modal windows are
  ## always focused regardless of `autoFocus`. The default (`autoFocus = true`)
  ## takes focus on add; pass `false` to add a non-modal window without
  ## disturbing the current focus. See `WindowManager.addWindow` for the full
  ## semantics.
  if not app.state.windowMode:
    app.enableWindowMode()
  return app.windowManager.addWindow(window, autoFocus)

proc removeWindow*(app: App, windowId: WindowId): bool =
  ## Remove a window from the application
  ## Returns true if the window was found and removed, false otherwise
  if app.state.windowMode and not app.windowManager.isNil:
    return app.windowManager.removeWindow(windowId)

proc getWindow*(app: App, windowId: WindowId): Option[Window] =
  ## Get a window by ID
  if app.state.windowMode and not app.windowManager.isNil:
    return app.windowManager.getWindow(windowId)
  return none(Window)

proc focusWindow*(app: App, windowId: WindowId): bool =
  ## Focus a specific window
  ## Returns true if the window was found and focused, false otherwise
  if app.state.windowMode and not app.windowManager.isNil:
    return app.windowManager.focusWindow(windowId)

proc getFocusedWindow*(app: App): Option[Window] =
  ## Get the currently focused window
  if app.state.windowMode and not app.windowManager.isNil:
    return app.windowManager.getFocusedWindow()
  return none(Window)

proc getWindows*(app: App): seq[Window] =
  ## Get all windows in the application
  if app.state.windowMode and not app.windowManager.isNil:
    return app.windowManager.windows
  return @[]

proc getWindowCount*(app: App): int =
  ## Get the total number of windows
  if app.state.windowMode and not app.windowManager.isNil:
    return app.windowManager.windows.len
  return 0

proc getFocusedWindowId*(app: App): Option[WindowId] =
  ## Get the ID of the currently focused window
  if app.state.windowMode and not app.windowManager.isNil:
    return app.windowManager.focusedWindow
  return none(WindowId)

proc getWindowInfo*(app: App, windowId: WindowId): Option[WindowInfo] =
  ## Get window information by ID
  if app.state.windowMode and not app.windowManager.isNil:
    let windowOpt = app.windowManager.getWindow(windowId)
    if windowOpt.isSome():
      return some(windowOpt.get.toWindowInfo())
  return none(WindowInfo)

proc handleWindowEvent*(app: App, event: Event): EventResult =
  ## Handle an event through the window manager.
  ## Returns `erContinue` when window mode is disabled or no manager is set.
  if app.state.windowMode and not app.windowManager.isNil:
    return app.windowManager.handleEvent(event)
  return erContinue

# State and info queries

proc isRunning*(app: App): bool =
  ## Check if app is currently running
  app.state.running

proc getTerminalSize*(app: App): Size =
  ## Get current terminal size
  app.terminal.getSize()

proc getConfig*(app: App): AppConfig =
  ## Get the stored configuration
  app.config

proc getFrameCount*(app: App): int =
  ## Get total frame count
  app.timings.frameCounter

proc getLastFrameTime*(app: App): MonoTime =
  ## Get timestamp of last frame
  app.timings.lastFrameTime

# Buffer access for debugging and testing

proc getBuffer*(app: App): Buffer =
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

proc getBufferCell*(app: App, x, y: int): Cell =
  ## Get a specific cell from the current display buffer
  app.renderer.getBuffer()[x, y]

proc getBufferContent*(app: App): seq[string] =
  ## Get the text content of the current display buffer as a sequence of strings
  ##
  ## Each string represents one row of the buffer. Useful for debugging
  ## and testing to verify what is displayed on screen.
  app.renderer.getBuffer().toStrings()

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
