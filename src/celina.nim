## Celina TUI Library
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

import std/[os, options, unicode]

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
  ## Main application context for TUI applications
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
  ## Create a new TUI application with the specified configuration
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
  ##   buffer.setString(centerX, centerY, "Hello!", Style.default())
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

  # Note: Mouse capture not implemented in terminal.nim yet
  # if config.mouseCapture:
  #   app.terminal.enableMouse()

  hideCursor()
  clearScreen()

proc cleanup(app: App, config: AppConfig) =
  ## Internal cleanup procedure to restore terminal state
  showCursor()

  # Note: Mouse capture not implemented in terminal.nim yet
  # if config.mouseCapture:
  #   app.terminal.disableMouse()

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

# Additional imports for input handling
import posix

# Add event reading functionality
proc readKeyInput(): Option[Event] =
  ## Read a single key input event (non-blocking)
  let event = pollKey()
  if event.kind != EventKind.Unknown:
    return some(event)
  return none(Event)

proc tick(app: App): bool =
  ## Process one application tick (events + render)
  ## Returns false if application should quit

  # Handle pending events
  let eventOpt = readKeyInput()
  if eventOpt.isSome():
    let event = eventOpt.get()

    # Try window manager event handling first
    var eventHandled = false
    if app.windowMode and not app.windowManager.isNil:
      eventHandled = app.windowManager.handleEvent(event)

    # If not handled by windows, call user event handler
    if not eventHandled and app.eventHandler != nil:
      if not app.eventHandler(event):
        return false

  # Render frame
  app.render()

  return not app.shouldQuit

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
  ##   buffer.drawString(0, 0, "Hello!", Style.default())
  ##
  ## app.run()
  ## ```

  try:
    app.setup(config)

    # Main application loop
    while app.tick():
      # Optional: Add frame rate limiting here
      sleep(16) # ~60 FPS
  finally:
    app.cleanup(config)

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
  ## Quick way to run a simple TUI application
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
  ##     buffer.setString(10, area.height div 2, "Press 'q' to quit", Style.default())
  ## )
  ## ```
  var app = newApp(config)
  app.onEvent(eventHandler)
  app.onRender(renderHandler)
  app.run(config)

# ============================================================================
# Version Information
# ============================================================================

const
  CelinaVersion* = "0.1.0"
  CelinaVersionInfo* = "Celina TUI Library v" & CelinaVersion

proc version*(): string =
  ## Get the library version string
  CelinaVersionInfo
