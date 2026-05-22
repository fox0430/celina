## App Delegation Templates
## ========================
##
## Reusable `untyped` templates that generate the pass-through delegation
## procs shared by `App` (`core/app.nim`) and `AsyncApp` (`async/async_app.nim`).
##
## **How to use:** invoke a `defineXxxDelegation*` template from within the
## owning App module, passing the App type as `AppT`. The template expands
## in the caller's scope so private fields (`renderer`, `terminal`,
## `windowManager`, ...) remain accessible without exposing them outside
## the module.
##
## The templates intentionally do not import anything: every symbol they
## reference (`Position`, `CursorStyle`, `renderer.setCursorPosition`, ...)
## is resolved against the call site's imports.

template defineCursorDelegation*(AppT: untyped) =
  ## Generate the cursor control delegation procs for `AppT`.
  ##
  ## Produces 12 procs that forward to `app.renderer`:
  ##   - setCursorPosition (x,y) / (Position)
  ##   - showCursorAt (x,y) / (Position)
  ##   - showCursor / hideCursor
  ##   - setCursorStyle / getCursorStyle / getCursorPosition
  ##   - moveCursorBy / isCursorVisible / resetCursor

  proc setCursorPosition*(app: AppT, x, y: int) =
    ## Set cursor position without changing visibility state
    app.renderer.setCursorPosition(x, y)

  proc setCursorPosition*(app: AppT, pos: Position) =
    ## Set cursor position using Position type without changing visibility
    app.renderer.setCursorPosition(pos)

  proc showCursorAt*(app: AppT, x, y: int) =
    ## Set cursor position and make it visible
    app.renderer.showCursorAt(x, y)

  proc showCursorAt*(app: AppT, pos: Position) =
    ## Set cursor position using Position type and make it visible
    app.renderer.showCursorAt(pos)

  proc showCursor*(app: AppT) =
    ## Show cursor at current position
    app.renderer.showCursor()

  proc hideCursor*(app: AppT) =
    ## Hide cursor
    app.renderer.hideCursor()

  proc setCursorStyle*(app: AppT, style: CursorStyle) =
    ## Set cursor style for next render
    app.renderer.setCursorStyle(style)

  proc getCursorPosition*(app: AppT): (int, int) =
    ## Get current cursor position
    app.renderer.getCursorPosition()

  proc moveCursorBy*(app: AppT, dx, dy: int) =
    ## Move cursor relatively by dx, dy
    let (x, y) = app.getCursorPosition()
    app.setCursorPosition(x + dx, y + dy)

  proc isCursorVisible*(app: AppT): bool =
    ## Check if cursor is visible
    app.renderer.isCursorVisible()

  proc getCursorStyle*(app: AppT): CursorStyle =
    ## Get current cursor style
    app.renderer.getCursorManager().getStyle()

  proc resetCursor*(app: AppT) =
    ## Reset cursor to default state
    app.renderer.getCursorManager().reset()

template defineStateQueries*(AppT: untyped) =
  ## Generate the runtime state query procs for `AppT`:
  ## `isRunning`, `getTerminalSize`, `getConfig`, `getFrameCount`,
  ## `getLastFrameTime`.

  proc isRunning*(app: AppT): bool =
    ## Check if app is currently running
    app.state.running

  proc getTerminalSize*(app: AppT): Size =
    ## Get current terminal size
    app.terminal.getSize()

  proc getConfig*(app: AppT): AppConfig =
    ## Get the stored configuration
    app.config

  proc getFrameCount*(app: AppT): int =
    ## Get total frame count
    app.timings.frameCounter

  proc getLastFrameTime*(app: AppT): MonoTime =
    ## Get timestamp of last frame
    app.timings.lastFrameTime

template defineBufferDelegation*(AppT: untyped) =
  ## Generate the buffer inspection procs for `AppT`:
  ## `getBuffer` (cloned snapshot), `getBufferCell`, `getBufferContent`.

  proc getBuffer*(app: AppT): Buffer =
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

  proc getBufferCell*(app: AppT, x, y: int): Cell =
    ## Get a specific cell from the current display buffer
    app.renderer.getBuffer()[x, y]

  proc getBufferContent*(app: AppT): seq[string] =
    ## Get the text content of the current display buffer as a sequence of strings
    ##
    ## Each string represents one row of the buffer. Useful for debugging
    ## and testing to verify what is displayed on screen.
    app.renderer.getBuffer().toStrings()

template defineFpsDelegation*(AppT: untyped) =
  ## Generate FPS control procs for `AppT`:
  ## `setTargetFps`, `getTargetFps`, `getCurrentFps`.

  proc setTargetFps*(app: AppT, fps: int) =
    ## Set the target FPS for the application
    app.fpsMonitor.setTargetFps(fps)

  proc getTargetFps*(app: AppT): int =
    ## Get the current target FPS
    app.fpsMonitor.getTargetFps()

  proc getCurrentFps*(app: AppT): float =
    ## Get the current actual FPS
    app.fpsMonitor.getCurrentFps()

template defineMouseDelegation*(AppT: untyped) =
  ## Generate mouse runtime toggles for `AppT`: `enableMouse`, `disableMouse`.

  proc enableMouse*(app: AppT) =
    ## Enable mouse reporting at runtime
    app.terminal.enableMouse()

  proc disableMouse*(app: AppT) =
    ## Disable mouse reporting at runtime
    app.terminal.disableMouse()

template defineTimeoutAccessors*(AppT: untyped) =
  ## Generate application-timeout setter/getter for `AppT`.

  proc setApplicationTimeout*(app: AppT, timeoutMs: int) =
    ## Set the application timeout in milliseconds.
    ##
    ## When set to a positive value, the timeout handler will be called
    ## if no input events are received within this duration.
    ## Set to 0 to disable the application timeout.
    app.timings.applicationTimeout = timeoutMs

  proc getApplicationTimeout*(app: AppT): int =
    ## Get the current application timeout in milliseconds.
    ##
    ## Returns 0 if the timeout is disabled.
    app.timings.applicationTimeout

template defineQuit*(AppT: untyped) =
  ## Generate the cooperative `quit` proc for `AppT`.

  proc quit*(app: AppT) =
    ## Signal the application to quit gracefully
    app.state.shouldQuit = true

template defineWindowDelegation*(AppT: untyped) =
  ## Generate the window-manager passthrough procs for `AppT` (11 procs).
  ##
  ## `enableWindowMode` lazily creates the WindowManager on first use; the
  ## remaining procs short-circuit to a safe default when window mode is
  ## disabled or the manager is nil.

  proc enableWindowMode*(app: AppT) =
    ## Enable window management mode
    app.state.windowMode = true
    if app.windowManager.isNil:
      app.windowManager = newWindowManager()

  proc addWindow*(app: AppT, window: Window, autoFocus: bool = true): WindowId =
    ## Add a window to the application.
    ##
    ## The first window added is always auto-focused, and modal windows are
    ## always focused regardless of `autoFocus`. The default (`autoFocus = true`)
    ## takes focus on add; pass `false` to add a non-modal window without
    ## disturbing the current focus. See `WindowManager.addWindow` for the
    ## full semantics.
    if not app.state.windowMode:
      app.enableWindowMode()
    return app.windowManager.addWindow(window, autoFocus)

  proc removeWindow*(app: AppT, windowId: WindowId): bool =
    ## Remove a window from the application
    ## Returns true if the window was found and removed, false otherwise
    if app.state.windowMode and not app.windowManager.isNil:
      return app.windowManager.removeWindow(windowId)

  proc getWindow*(app: AppT, windowId: WindowId): Option[Window] =
    ## Get a window by ID
    if app.state.windowMode and not app.windowManager.isNil:
      return app.windowManager.getWindow(windowId)
    return none(Window)

  proc focusWindow*(app: AppT, windowId: WindowId): bool =
    ## Focus a specific window
    ## Returns true if the window was found and focused, false otherwise
    if app.state.windowMode and not app.windowManager.isNil:
      return app.windowManager.focusWindow(windowId)

  proc getFocusedWindow*(app: AppT): Option[Window] =
    ## Get the currently focused window
    if app.state.windowMode and not app.windowManager.isNil:
      return app.windowManager.getFocusedWindow()
    return none(Window)

  proc getWindows*(app: AppT): seq[Window] =
    ## Get all windows in the application
    if app.state.windowMode and not app.windowManager.isNil:
      return app.windowManager.windows
    return @[]

  proc getWindowCount*(app: AppT): int =
    ## Get the total number of windows
    if app.state.windowMode and not app.windowManager.isNil:
      return app.windowManager.windows.len
    return 0

  proc getFocusedWindowId*(app: AppT): Option[WindowId] =
    ## Get the ID of the currently focused window
    if app.state.windowMode and not app.windowManager.isNil:
      return app.windowManager.focusedWindow
    return none(WindowId)

  proc getWindowInfo*(app: AppT, windowId: WindowId): Option[WindowInfo] =
    ## Get window information by ID
    if app.state.windowMode and not app.windowManager.isNil:
      let windowOpt = app.windowManager.getWindow(windowId)
      if windowOpt.isSome():
        return some(windowOpt.get.toWindowInfo())
    return none(WindowInfo)

  proc handleWindowEvent*(app: AppT, event: Event): EventResult =
    ## Handle an event through the window manager.
    ## Returns `erContinue` when window mode is disabled or no manager is set.
    if app.state.windowMode and not app.windowManager.isNil:
      return app.windowManager.handleEvent(event)
    return erContinue

template defineShow*(AppT: untyped) =
  ## Generate the `$` debug-formatter for `AppT`. The leading type name
  ## ("App" / "AsyncApp" / ...) is derived from `astToStr(AppT)`.
  ##
  ## Locals are `{.inject.}` because `&"..."` re-parses placeholders in
  ## the call-site scope, where hygienically renamed identifiers from a
  ## template body are not visible.

  proc `$`*(app: AppT): string =
    ## String representation for debugging
    let windowCount {.inject.} =
      if app.state.windowMode and not app.windowManager.isNil:
        app.windowManager.windows.len
      else:
        0
    let running {.inject.} = app.state.running
    let fps {.inject.} = app.fpsMonitor.getCurrentFps()
    let frames {.inject.} = app.timings.frameCounter
    let cfg {.inject.} = app.config
    astToStr(AppT) &
      &"(running: {running}, fps: {fps:.1f}, frames: {frames}, windows: {windowCount}, config: {cfg})"
