## Celina CLI Library
## ==================
##
## A powerful Terminal User Interface library for Nim, inspired by Ratatui.
## Provides high-performance, type-safe components for building interactive
## terminal applications.
##
## Basic Usage:
## ```nim
## import celina
##
## proc main() =
##   var app = newApp()
##   app.run()
##
## when isMainModule:
##   main()
## ```

import std/[os, options, unicode, strutils]

import core/[geometry, colors, buffer, events, terminal, layout, windows]
import widgets/[text, base]

# Re-export all public APIs from core modules
export geometry
export colors
export buffer
export events
export layout
export terminal
export windows
export text
export base
export unicode

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

  ## Application configuration options
  AppConfig* = object
    title*: string
    alternateScreen*: bool
    mouseCapture*: bool
    rawMode*: bool
    windowMode*: bool ## Enable window management

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

  hideCursor()
  clearScreen()

proc cleanup(app: App, config: AppConfig) =
  ## Internal cleanup procedure to restore terminal state
  showCursor()

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

  # Use terminal's built-in rendering for efficiency
  # The terminal.draw() method should handle diff calculation internally
  app.terminal.draw(app.buffer, force = false)

proc tick(app: App): bool =
  ## Process one application tick (events + render)
  ## Returns false if application should quit
  try:
    # Check for resize event first
    let resizeOpt = checkResize()
    if resizeOpt.isSome():
      let resizeEvent = resizeOpt.get()
      app.handleResize()

      # Also pass resize event to user handler
      if app.eventHandler != nil:
        if not app.eventHandler(resizeEvent):
          return false

    # Handle pending events using centralized event handling
    let eventOpt = readKeyInput()
    if eventOpt.isSome():
      let event = eventOpt.get()

      # Always call user event handler first for application-level control
      var shouldContinue = true
      if app.eventHandler != nil:
        shouldContinue = app.eventHandler(event)
        if not shouldContinue:
          return false

      # Then try window manager event handling
      if app.windowMode and not app.windowManager.isNil:
        discard app.windowManager.handleEvent(event)

    # Render frame
    app.render()

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
    initSignalHandling()

    # Main application loop
    while app.tick():
      # Optional: Add frame rate limiting here
      sleep(8) # ~120 FPS for better mouse responsiveness
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
      return some(windowOpt.get().toWindowInfo())
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
# Version Information
# ============================================================================

proc parseVersionFromNimble(): string {.compileTime.} =
  ## Parse version from nimble file content at compile time
  const nimbleContent = staticRead("../celina.nimble")
  for line in nimbleContent.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("version"):
      # Extract version from line like: version = "0.1.0"
      let parts = trimmed.split("=")
      if parts.len >= 2:
        let versionPart = parts[1].strip()
        # Remove quotes
        return versionPart.strip(chars = {'"', ' ', '\t'})
  return "unknown"

proc version*(): string =
  ## Get the library version string
  const CelinaVersion = parseVersionFromNimble()
  return CelinaVersion
