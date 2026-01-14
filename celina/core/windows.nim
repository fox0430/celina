## Window management system for Celina CLI library
##
## This module provides window management capabilities, allowing for
## overlapping, resizable, and focusable window areas within the terminal.

import std/[algorithm, sequtils, options]

import ../core/[geometry, buffer, colors, events]

type
  WindowId* = distinct int ## Unique identifier for windows

  WindowState* = enum
    wsNormal ## Normal window state
    wsMinimized ## Window is minimized
    wsMaximized ## Window is maximized
    wsHidden ## Window is hidden

  WindowBorder* = object ## Window border configuration
    top*, right*, bottom*, left*: bool
    style*: Style
    chars*: BorderChars

  BorderChars* = object ## Characters used for drawing window borders
    horizontal*: string
    vertical*: string
    topLeft*: string
    topRight*: string
    bottomLeft*: string
    bottomRight*: string

  # Event handling types
  EventPhase* = enum
    epCapture # Event travels down from root to target
    epTarget # Event at target window
    epBubble # Event bubbles up from target to root

  WindowEvent* = object
    originalEvent*: Event
    phase*: EventPhase
    target*: WindowId
    currentTarget*: WindowId
    propagationStopped*: bool
    defaultPrevented*: bool

  WindowEventHandler* = proc(window: Window, event: Event): bool
  WindowKeyHandler* = proc(window: Window, key: KeyEvent): bool
  WindowMouseHandler* = proc(window: Window, mouse: MouseEvent): bool
  WindowResizeHandler* = proc(window: Window, newSize: Size): bool
  EventHandler* = proc(event: var WindowEvent): bool

  Window* = ref object ## Represents a window within the terminal
    id*: WindowId
    area*: Rect ## Window position and size
    contentArea*: Rect ## Internal content area (excluding borders)
    buffer*: Buffer ## Window's rendering buffer
    title*: string ## Window title
    state*: WindowState ## Current window state
    zIndex*: int ## Z-order for overlapping windows
    border*: Option[WindowBorder] ## Border configuration
    visible*: bool ## Whether window is visible
    focused*: bool ## Whether window has focus
    resizable*: bool ## Whether window can be resized
    movable*: bool ## Whether window can be moved
    modal*: bool ## Whether window is modal
    # Event handlers
    eventHandler*: Option[WindowEventHandler] ## General event handler
    keyHandler*: Option[WindowKeyHandler] ## Key-specific handler
    mouseHandler*: Option[WindowMouseHandler] ## Mouse-specific handler
    resizeHandler*: Option[WindowResizeHandler] ## Resize handler
    acceptsEvents*: bool ## Whether window accepts events

  WindowInfo* = object ## Information about a window
    id*: WindowId
    title*: string
    area*: Rect
    state*: WindowState
    zIndex*: int
    visible*: bool
    focused*: bool
    resizable*: bool
    movable*: bool
    modal*: bool

  WindowManager* = ref object ## Manages multiple windows and their interactions
    windows*: seq[Window]
    nextWindowId: int
    focusedWindow*: Option[WindowId]
    modalWindow*: Option[WindowId]

# ============================================================================
# Window ID utilities
# ============================================================================

proc `==`*(a, b: WindowId): bool {.borrow.}
proc `$`*(id: WindowId): string =
  $int(id)

# ============================================================================
# BorderChars defaults
# ============================================================================

proc defaultBorderChars*(): BorderChars =
  ## Default border characters using box drawing
  BorderChars(
    horizontal: "─",
    vertical: "│",
    topLeft: "┌",
    topRight: "┐",
    bottomLeft: "└",
    bottomRight: "┘",
  )

proc defaultBorder*(): WindowBorder =
  ## Default window border configuration
  WindowBorder(
    top: true,
    right: true,
    bottom: true,
    left: true,
    style: style(fg = Color.White),
    chars: defaultBorderChars(),
  )

# ============================================================================
# Window creation and management
# ============================================================================

proc newWindow*(
    area: Rect,
    title: string = "",
    border: Option[WindowBorder] = some(defaultBorder()),
    resizable: bool = true,
    movable: bool = true,
    modal: bool = false,
    acceptsEvents: bool = true,
): Window =
  ## Create a new window
  result = Window(
    id: WindowId(0), # Will be set by WindowManager
    area: area,
    title: title,
    state: wsNormal,
    zIndex: 0,
    border: border,
    visible: true,
    focused: false,
    resizable: resizable,
    movable: movable,
    modal: modal,
    eventHandler: none(WindowEventHandler),
    keyHandler: none(WindowKeyHandler),
    mouseHandler: none(WindowMouseHandler),
    resizeHandler: none(WindowResizeHandler),
    acceptsEvents: acceptsEvents,
  )

  # Calculate content area (excluding borders)
  result.contentArea = area
  if border.isSome():
    let b = border.get()
    # Proper calculation with min size guarantee
    let leftMargin = if b.left: 1 else: 0
    let rightMargin = if b.right: 1 else: 0
    let topMargin = if b.top: 1 else: 0
    let bottomMargin = if b.bottom: 1 else: 0

    result.contentArea = rect(
      area.x + leftMargin,
      area.y + topMargin,
      max(1, area.width - leftMargin - rightMargin),
      max(1, area.height - topMargin - bottomMargin),
    )

  # Create buffer for content area (always use (0,0) origin for window buffers)
  result.buffer = newBuffer(result.contentArea.width, result.contentArea.height)
  # Ensure buffer area starts at (0,0) - window buffers are always relative
  result.buffer.area = rect(0, 0, result.contentArea.width, result.contentArea.height)

proc calculateContentArea(window: Window): Rect =
  ## Calculate the content area based on window area and border
  result = window.area
  if window.border.isSome():
    let border = window.border.get()
    # Correct calculation: shrink by border thickness, not half
    let leftMargin = if border.left: 1 else: 0
    let rightMargin = if border.right: 1 else: 0
    let topMargin = if border.top: 1 else: 0
    let bottomMargin = if border.bottom: 1 else: 0

    result = rect(
      result.x + leftMargin,
      result.y + topMargin,
      max(1, result.width - leftMargin - rightMargin),
      max(1, result.height - topMargin - bottomMargin),
    )

proc updateContentArea(window: Window) =
  ## Update the content area and resize buffer when window area changes
  let newContentArea = window.calculateContentArea()
  if newContentArea != window.contentArea:
    window.contentArea = newContentArea
    # Always resize buffer to start at (0,0) - window buffers are relative coordinate system
    let newBufferArea = rect(0, 0, newContentArea.width, newContentArea.height)
    window.buffer.resize(newBufferArea)
    # Ensure buffer area is always (0,0) based after resize
    window.buffer.area = newBufferArea

# ============================================================================
# Window operations
# ============================================================================

proc move*(window: Window, newPos: Position) =
  ## Move window to a new position
  if not window.movable:
    return

  window.area.x = newPos.x
  window.area.y = newPos.y
  window.updateContentArea()

proc resize*(window: Window, newSize: Size) =
  ## Resize window to new dimensions
  if not window.resizable:
    return

  window.area.width = newSize.width
  window.area.height = newSize.height
  window.updateContentArea()

proc setArea*(window: Window, newArea: Rect) =
  ## Set window area (combines move and resize) - safe coordinate system update
  window.area = newArea
  window.updateContentArea()

proc getContentSize*(window: Window): Size =
  ## Get the current content area size (safe access)
  size(window.contentArea.width, window.contentArea.height)

proc getContentBuffer*(window: Window): Buffer =
  ## Get the window content buffer (always (0,0) based)
  window.buffer

proc show*(window: Window) =
  ## Show the window
  window.visible = true

proc hide*(window: Window) =
  ## Hide the window
  window.visible = false

proc minimize*(window: Window) =
  ## Minimize the window
  window.state = wsMinimized
  window.visible = false

proc maximize*(window: Window, screenArea: Rect) =
  ## Maximize the window to fill the screen area
  if window.state != wsMaximized:
    window.state = wsMaximized
    window.area = screenArea
    window.updateContentArea()

proc restore*(window: Window, originalArea: Rect) =
  ## Restore window from minimized/maximized state
  window.state = wsNormal
  window.visible = true
  window.area = originalArea
  window.updateContentArea()

proc setTitle*(window: Window, title: string) =
  ## Set window title
  window.title = title

proc setBorder*(window: Window, border: Option[WindowBorder]) =
  ## Set window border configuration
  window.border = border
  window.updateContentArea()

# ============================================================================
# Window event handling
# ============================================================================

proc setEventHandler*(window: Window, handler: WindowEventHandler) =
  ## Set general event handler for window
  window.eventHandler = some(handler)

proc setKeyHandler*(window: Window, handler: WindowKeyHandler) =
  ## Set key event handler for window
  window.keyHandler = some(handler)

proc setMouseHandler*(window: Window, handler: WindowMouseHandler) =
  ## Set mouse event handler for window  
  window.mouseHandler = some(handler)

proc setResizeHandler*(window: Window, handler: WindowResizeHandler) =
  ## Set resize handler for window
  window.resizeHandler = some(handler)

proc clearEventHandlers*(window: Window) =
  ## Clear all event handlers for window
  window.eventHandler = none(WindowEventHandler)
  window.keyHandler = none(WindowKeyHandler)
  window.mouseHandler = none(WindowMouseHandler)
  window.resizeHandler = none(WindowResizeHandler)

proc handleWindowEvent*(window: Window, event: Event): bool =
  ## Handle event for a specific window, returns true if handled
  if not window.acceptsEvents or not window.visible:
    return false

  # Try specific handlers first
  case event.kind
  of EventKind.Key:
    if window.keyHandler.isSome():
      return window.keyHandler.get()(window, event.key)
  of EventKind.Mouse:
    if window.mouseHandler.isSome():
      # Check if mouse event is within window bounds
      let mousePos = pos(event.mouse.x, event.mouse.y)
      if window.area.contains(mousePos):
        return window.mouseHandler.get()(window, event.mouse)
  else:
    discard

  # Try general event handler
  if window.eventHandler.isSome():
    return window.eventHandler.get()(window, event)

  return false

# ============================================================================
# Window rendering
# ============================================================================

proc drawBorder(window: Window, destBuffer: var Buffer) =
  ## Draw window border to destination buffer
  if window.border.isNone():
    return

  let border = window.border.get()
  let area = window.area
  let chars = border.chars
  let style = border.style

  # Draw corners
  if border.top and border.left:
    destBuffer.setString(area.x, area.y, chars.topLeft, style)
  if border.top and border.right:
    destBuffer.setString(area.right - 1, area.y, chars.topRight, style)
  if border.bottom and border.left:
    destBuffer.setString(area.x, area.bottom - 1, chars.bottomLeft, style)
  if border.bottom and border.right:
    destBuffer.setString(area.right - 1, area.bottom - 1, chars.bottomRight, style)

  # Draw horizontal borders
  if border.top:
    for x in (area.x + 1) ..< (area.right - 1):
      destBuffer.setString(x, area.y, chars.horizontal, style)
  if border.bottom:
    for x in (area.x + 1) ..< (area.right - 1):
      destBuffer.setString(x, area.bottom - 1, chars.horizontal, style)

  # Draw vertical borders
  if border.left:
    for y in (area.y + 1) ..< (area.bottom - 1):
      destBuffer.setString(area.x, y, chars.vertical, style)
  if border.right:
    for y in (area.y + 1) ..< (area.bottom - 1):
      destBuffer.setString(area.right - 1, y, chars.vertical, style)

  # Draw title if present
  if window.title.len > 0 and border.top:
    let titleStart = area.x + 2
    let maxTitleLen = max(0, area.width - 4)
    let displayTitle =
      if window.title.len <= maxTitleLen:
        window.title
      else:
        window.title[0 ..< maxTitleLen - 1] & "…"
    destBuffer.setString(titleStart, area.y, displayTitle, style)

proc render*(window: Window, destBuffer: var Buffer) =
  ## Render window to destination buffer
  if not window.visible:
    return

  # Draw border first
  window.drawBorder(destBuffer)

  # Merge window content buffer into destination at content area position
  let contentPos = pos(window.contentArea.x, window.contentArea.y)

  # Window buffer should always be (0,0) based - no need for runtime checks
  # This is guaranteed by updateContentArea and window creation
  destBuffer.merge(window.buffer, contentPos)

# ============================================================================
# WindowManager implementation
# ============================================================================

proc newWindowManager*(): WindowManager =
  ## Create a new window manager
  WindowManager(
    windows: @[],
    nextWindowId: 1,
    focusedWindow: none(WindowId),
    modalWindow: none(WindowId),
  )

proc getWindow*(wm: WindowManager, windowId: WindowId): Option[Window] =
  ## Get a window by ID
  for window in wm.windows:
    if window.id == windowId:
      return some(window)
  return none(Window)

proc focusWindow*(wm: WindowManager, windowId: WindowId) =
  ## Focus a specific window
  # Unfocus all windows
  for window in wm.windows:
    window.focused = false

  # Focus the specified window
  let windowOpt = wm.getWindow(windowId)
  if windowOpt.isSome():
    let window = windowOpt.get()
    window.focused = true
    wm.focusedWindow = some(windowId)

    # Bring window to front (highest z-index) only when explicitly focusing
    let maxZ =
      if wm.windows.len > 0:
        wm.windows.mapIt(it.zIndex).max
      else:
        0
    window.zIndex = maxZ + 1

    # Set as modal if the window is modal
    if window.modal:
      wm.modalWindow = some(windowId)

proc addWindow*(wm: WindowManager, window: Window): WindowId =
  ## Add a window to the manager and return its ID
  window.id = WindowId(wm.nextWindowId)
  inc wm.nextWindowId

  # Set Z-index based on current window count (before adding)
  window.zIndex = wm.windows.len

  wm.windows.add(window)

  # Unfocus all other windows
  for w in wm.windows:
    if w.id != window.id:
      w.focused = false

  # Focus the new window and update manager state
  window.focused = true
  wm.focusedWindow = some(window.id)

  # Set as modal if the window is modal
  if window.modal:
    wm.modalWindow = some(window.id)

  return window.id

proc removeWindow*(wm: WindowManager, windowId: WindowId) =
  ## Remove a window from the manager
  ## All window resources (buffer, title, etc.) are automatically freed by Nim's GC
  wm.windows = wm.windows.filterIt(it.id != windowId)

  # Update focus if the focused window was removed
  if wm.focusedWindow.isSome():
    let focusedId = wm.focusedWindow.get()
    if focusedId == windowId:
      if wm.windows.len > 0:
        wm.focusWindow(wm.windows[^1].id) # Focus last window
      else:
        wm.focusedWindow = none(WindowId)

  # Clear modal if modal window was removed
  if wm.modalWindow.isSome():
    let modalId = wm.modalWindow.get()
    if modalId == windowId:
      wm.modalWindow = none(WindowId)

proc getFocusedWindow*(wm: WindowManager): Option[Window] =
  ## Get the currently focused window
  if wm.focusedWindow.isSome():
    let windowId = wm.focusedWindow.get()
    return wm.getWindow(windowId)
  return none(Window)

proc getVisibleWindows*(wm: WindowManager): seq[Window] =
  ## Get all visible windows sorted by Z-index (memory-efficient)
  result = @[]
  # Pre-allocate for typical window counts
  if wm.windows.len > 0:
    result = newSeqOfCap[Window](min(wm.windows.len, 16))

  for window in wm.windows:
    if window.visible:
      result.add(window)

  # Most windows will already be in Z-index order, so this should be fast
  result.sort(
    proc(a, b: Window): int =
      cmp(a.zIndex, b.zIndex)
  )

proc findWindowAt*(wm: WindowManager, pos: Position): Option[Window] =
  ## Find the topmost window at the given position
  let visibleWindows = wm.getVisibleWindows()

  # Check from highest to lowest Z-index
  for i in countdown(visibleWindows.high, 0):
    let window = visibleWindows[i]
    if window.area.contains(pos):
      return some(window)

  return none(Window)

proc handleEvent*(wm: WindowManager, event: Event): bool =
  ## Handle an event, routing it to the appropriate window
  ## Returns true if the event was handled

  # If there's a modal window, only it can handle events
  if wm.modalWindow.isSome():
    let modalWindowId = wm.modalWindow.get()
    let modalWindow = wm.getWindow(modalWindowId)
    if modalWindow.isSome():
      return modalWindow.get().handleWindowEvent(event)

  # For mouse events, find the topmost window at mouse position
  if event.kind == EventKind.Mouse:
    let mousePos = pos(event.mouse.x, event.mouse.y)
    let windowAtPos = wm.findWindowAt(mousePos)
    if windowAtPos.isSome():
      let window = windowAtPos.get()
      # Auto-focus window on mouse click
      if event.mouse.kind == Press:
        wm.focusWindow(window.id)
      return window.handleWindowEvent(event)

  # For other events, route to focused window
  let focusedWindow = wm.getFocusedWindow()
  if focusedWindow.isSome():
    return focusedWindow.get().handleWindowEvent(event)

  return false

proc dispatchResize*(wm: WindowManager, newSize: Size) =
  ## Dispatch resize event to all windows with resize handlers
  for window in wm.windows:
    if window.resizeHandler.isSome() and window.visible:
      discard window.resizeHandler.get()(window, newSize)

proc render*(wm: WindowManager, destBuffer: var Buffer) =
  ## Render all windows to the destination buffer
  let visibleWindows = wm.getVisibleWindows()

  for window in visibleWindows:
    window.render(destBuffer)

# ============================================================================
# Window Event System
# ============================================================================

proc stopPropagation*(event: var WindowEvent) =
  ## Stop event from propagating further
  event.propagationStopped = true

proc preventDefault*(event: var WindowEvent) =
  ## Prevent default action for this event
  event.defaultPrevented = true

proc dispatchEvent*(wm: WindowManager, event: Event): bool =
  ## Dispatch event through window hierarchy with bubbling

  # Find target window based on event type
  var targetWindow: Option[Window]

  case event.kind
  of EventKind.Mouse:
    targetWindow = wm.findWindowAt(pos(event.mouse.x, event.mouse.y))
  of EventKind.Key, EventKind.Paste:
    targetWindow = wm.getFocusedWindow()
  of EventKind.Resize, EventKind.Quit, EventKind.Unknown:
    targetWindow = wm.getFocusedWindow()

  # Dispatch to target window's event handlers
  if targetWindow.isSome():
    result = targetWindow.get().handleWindowEvent(event)

# ============================================================================
# Utility functions
# ============================================================================

proc bringToFront*(wm: WindowManager, windowId: WindowId) =
  ## Bring a window to the front
  wm.focusWindow(windowId) # focusWindow already brings to front

proc sendToBack*(wm: WindowManager, windowId: WindowId) =
  ## Send a window to the back
  let windowOpt = wm.getWindow(windowId)
  if windowOpt.isSome():
    let window = windowOpt.get()
    let minZ =
      if wm.windows.len > 0:
        wm.windows.mapIt(it.zIndex).min
      else:
        0
    window.zIndex = minZ - 1

proc toWindowInfo*(window: Window): WindowInfo =
  ## Convert a Window to WindowInfo
  WindowInfo(
    id: window.id,
    title: window.title,
    area: window.area,
    state: window.state,
    zIndex: window.zIndex,
    visible: window.visible,
    focused: window.focused,
    resizable: window.resizable,
    movable: window.movable,
    modal: window.modal,
  )
