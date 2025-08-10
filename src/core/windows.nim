## Window management system for Celina TUI library
##
## This module provides window management capabilities, allowing for
## overlapping, resizable, and focusable window areas within the terminal.

import std/[algorithm, sequtils, options]
import geometry, buffer, colors, events

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
  )

  # Calculate content area (excluding borders)
  result.contentArea = area
  if border.isSome():
    let b = border.get()
    result.contentArea =
      area.shrink(if b.left or b.right: 1 else: 0, if b.top or b.bottom: 1 else: 0)

  # Create buffer for content area (using size only, not absolute position)
  result.buffer = newBuffer(result.contentArea.width, result.contentArea.height)

proc calculateContentArea(window: Window): Rect =
  ## Calculate the content area based on window area and border
  result = window.area
  if window.border.isSome():
    let border = window.border.get()
    let hMargin = (if border.left: 1 else: 0) + (if border.right: 1 else: 0)
    let vMargin = (if border.top: 1 else: 0) + (if border.bottom: 1 else: 0)
    result = result.shrink(hMargin div 2, vMargin div 2)

proc updateContentArea(window: Window) =
  ## Update the content area and resize buffer when window area changes
  let newContentArea = window.calculateContentArea()
  if newContentArea != window.contentArea:
    window.contentArea = newContentArea
    # Resize buffer to new dimensions (width/height only, not absolute position)
    let newBufferArea = rect(0, 0, newContentArea.width, newContentArea.height)
    window.buffer.resize(newBufferArea)

# ============================================================================
# Window operations
# ============================================================================

proc move*(window: Window, newPos: Position) =
  ## Move window to a new position
  if not window.movable:
    return

  let offset = newPos - window.area.position
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
  ## Set window area (combines move and resize)
  window.area = newArea
  window.updateContentArea()

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

  # Ensure window buffer area starts at (0,0) for correct merging
  if window.buffer.area.x != 0 or window.buffer.area.y != 0:
    let fixedArea = rect(0, 0, window.buffer.area.width, window.buffer.area.height)
    window.buffer.area = fixedArea

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
  wm.windows = wm.windows.filterIt(it.id != windowId)

  # Update focus if the focused window was removed
  if wm.focusedWindow.isSome() and wm.focusedWindow.get() == windowId:
    if wm.windows.len > 0:
      wm.focusWindow(wm.windows[^1].id) # Focus last window
    else:
      wm.focusedWindow = none(WindowId)

  # Clear modal if modal window was removed
  if wm.modalWindow.isSome() and wm.modalWindow.get() == windowId:
    wm.modalWindow = none(WindowId)

proc getFocusedWindow*(wm: WindowManager): Option[Window] =
  ## Get the currently focused window
  if wm.focusedWindow.isSome():
    return wm.getWindow(wm.focusedWindow.get())
  return none(Window)

proc getVisibleWindows*(wm: WindowManager): seq[Window] =
  ## Get all visible windows sorted by Z-index
  result = wm.windows.filterIt(it.visible).sortedByIt(it.zIndex)

proc handleEvent*(wm: WindowManager, event: Event): bool =
  ## Handle an event, routing it to the appropriate window
  ## Returns true if the event was handled

  # If there's a modal window, only it can handle events
  if wm.modalWindow.isSome():
    let modalWindow = wm.getWindow(wm.modalWindow.get())
    if modalWindow.isSome():
      # Modal window exists - event handling would go here
      # For now, we don't handle events at the window level
      return false

  # Otherwise, route to focused window
  let focusedWindow = wm.getFocusedWindow()
  if focusedWindow.isSome():
    # Focused window exists - event handling would go here
    # For now, we don't handle events at the window level
    return false

  return false

proc render*(wm: WindowManager, destBuffer: var Buffer) =
  ## Render all windows to the destination buffer
  let visibleWindows = wm.getVisibleWindows()

  for window in visibleWindows:
    window.render(destBuffer)

# ============================================================================
# Utility functions
# ============================================================================

proc findWindowAt*(wm: WindowManager, pos: Position): Option[Window] =
  ## Find the topmost window at the given position
  let visibleWindows = wm.getVisibleWindows()

  # Check from highest to lowest Z-index
  for i in countdown(visibleWindows.high, 0):
    let window = visibleWindows[i]
    if window.area.contains(pos):
      return some(window)

  return none(Window)

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
