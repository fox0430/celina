## Window management system for Celina CLI library
##
## This module provides window management capabilities, allowing for
## overlapping, resizable, and focusable window areas within the terminal.

import std/[algorithm, sequtils, options, strformat]

import ../core/[geometry, buffer, colors, events, borders]

export borders.BorderChars, borders.BorderKind

type
  WindowId* = distinct int ## Unique identifier for windows

  WindowState* = enum
    ## Window form (orthogonal to `visible`).
    ## Visibility is expressed by `Window.visible`; this enum only describes the
    ## window's form. Use `hide`/`show` to toggle visibility.
    wsNormal ## Normal window state
    wsMinimized ## Window is minimized
    wsMaximized ## Window is maximized

  WindowBorder* = object ## Window border configuration
    top*, right*, bottom*, left*: bool
    style*: Style
    chars*: BorderChars

  # Event handling types
  #
  # Handlers return `EventResult` to participate in the window-first
  # fallthrough chain:
  #   `erConsume`  - event handled; do not propagate to global handler
  #   `erContinue` - event not handled; allow global handler to run
  #   `erQuit`     - meaningful only from global handlers; window handlers
  #                  should not return this (treated as `erConsume`)
  #
  # `bool`-returning overloads are accepted via `setKeyHandler`/etc. for
  # backward compatibility: `true` is wrapped to `erConsume`, `false` to
  # `erContinue`.
  WindowEventHandler* = proc(window: Window, event: Event): EventResult
  WindowKeyHandler* = proc(window: Window, key: KeyEvent): EventResult
  WindowMouseHandler* = proc(window: Window, mouse: MouseEvent): EventResult
  WindowResizeHandler* = proc(window: Window, newSize: Size): bool
    ## Resize handlers retain `bool` return because resize is broadcast to
    ## every visible window (see `dispatchResize`); consumption semantics
    ## do not apply to a broadcast event.

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
    managerRef {.cursor.}: WindowManager
      ## Owning manager; focus is derived from it. Not exported — read via the
      ## `manager*` getter, mutated only by manager implementations.
      ## `{.cursor.}` makes this a non-counted back-reference so that
      ## the parent/child cycle (manager <-> windows) is broken under
      ## --mm:arc/orc and the window does not keep the manager alive.
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
    focusedWindow*: Option[WindowId]
      ## ID of the currently focused window, if any. Single source of truth
      ## for focus state; `Window.focused` is derived from this field.
    windows*: seq[Window]
    nextWindowId: int
    modalStack*: seq[WindowId]
      ## Stack of modal window IDs, bottom-to-top. The last element (top)
      ## receives all events; lower modals are inert until the top is
      ## removed. Push on `addWindow(modal=true)`, remove on
      ## `removeWindow(id)` regardless of position.

# Window ID utilities

proc `==`*(a, b: WindowId): bool {.borrow.}
proc `$`*(id: WindowId): string =
  $int(id)

proc manager*(window: Window): WindowManager {.inline.} =
  ## The window's owning manager, or nil if not attached.
  window.managerRef

proc `manager=`*(window: Window, m: WindowManager) {.inline.} =
  ## Set the window's owning manager. Intended for use by `WindowManager`
  ## to attach/detach windows; application code should not call this
  ## directly.
  window.managerRef = m

proc focused*(window: Window): bool {.inline.} =
  ## Whether this window currently has focus.
  ## Computed from the owning manager's focusedWindow so there is a
  ## single source of truth.
  window.managerRef != nil and window.managerRef.focusedWindow == some(window.id)

proc `$`*(window: Window): string =
  ## String representation of a Window for debugging
  let titleStr =
    if window.title.len > 0:
      &"\"{window.title}\""
    else:
      "\"\""
  &"Window(id: {window.id}, title: {titleStr}, area: {window.area}, state: {window.state}, z: {window.zIndex}, visible: {window.visible}, focused: {window.focused})"

proc `$`*(info: WindowInfo): string =
  ## String representation of WindowInfo for debugging
  let titleStr =
    if info.title.len > 0:
      &"\"{info.title}\""
    else:
      "\"\""
  &"WindowInfo(id: {info.id}, title: {titleStr}, area: {info.area}, state: {info.state}, z: {info.zIndex}, visible: {info.visible}, focused: {info.focused})"

# BorderChars defaults

export borders.defaultBorderChars

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

# Window creation and management

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
    managerRef: nil,
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
    # Clamp to 0, never 1: when the window is too small to hold both borders
    # and any content, the content area collapses to an empty rect rather than
    # a 1-cell strip that would overlap (and be drawn over) the border itself.
    let leftMargin = if b.left: 1 else: 0
    let rightMargin = if b.right: 1 else: 0
    let topMargin = if b.top: 1 else: 0
    let bottomMargin = if b.bottom: 1 else: 0

    result.contentArea = rect(
      area.x + leftMargin,
      area.y + topMargin,
      max(0, area.width - leftMargin - rightMargin),
      max(0, area.height - topMargin - bottomMargin),
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
    # Shrink by border thickness, clamping to 0 (not 1) so an undersized
    # window yields an empty content area instead of one cell laid over the
    # border. Mirrors the calculation in `newWindow`.
    let leftMargin = if border.left: 1 else: 0
    let rightMargin = if border.right: 1 else: 0
    let topMargin = if border.top: 1 else: 0
    let bottomMargin = if border.bottom: 1 else: 0

    result = rect(
      result.x + leftMargin,
      result.y + topMargin,
      max(0, result.width - leftMargin - rightMargin),
      max(0, result.height - topMargin - bottomMargin),
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

# Window operations

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

# Window event handling

proc setEventHandler*(window: Window, handler: WindowEventHandler) =
  ## Set general event handler for window
  window.eventHandler = some(handler)

proc setEventHandler*(
    window: Window, handler: proc(w: Window, e: Event): bool
) {.deprecated: "Use a handler returning EventResult instead of bool".} =
  ## `bool`-returning overload (backward compatibility).
  ## `true` is treated as `erConsume`, `false` as `erContinue`.
  if handler.isNil:
    window.eventHandler = none(WindowEventHandler)
  else:
    let captured = handler
    window.eventHandler = some(
      proc(w: Window, e: Event): EventResult =
        if captured(w, e): erConsume else: erContinue
    )

proc setKeyHandler*(window: Window, handler: WindowKeyHandler) =
  ## Set key event handler for window
  window.keyHandler = some(handler)

proc setKeyHandler*(
    window: Window, handler: proc(w: Window, k: KeyEvent): bool
) {.deprecated: "Use a handler returning EventResult instead of bool".} =
  ## `bool`-returning overload (backward compatibility).
  ## `true` is treated as `erConsume`, `false` as `erContinue`.
  if handler.isNil:
    window.keyHandler = none(WindowKeyHandler)
  else:
    let captured = handler
    window.keyHandler = some(
      proc(w: Window, k: KeyEvent): EventResult =
        if captured(w, k): erConsume else: erContinue
    )

proc setMouseHandler*(window: Window, handler: WindowMouseHandler) =
  ## Set mouse event handler for window
  window.mouseHandler = some(handler)

proc setMouseHandler*(
    window: Window, handler: proc(w: Window, m: MouseEvent): bool
) {.deprecated: "Use a handler returning EventResult instead of bool".} =
  ## `bool`-returning overload (backward compatibility).
  ## `true` is treated as `erConsume`, `false` as `erContinue`.
  if handler.isNil:
    window.mouseHandler = none(WindowMouseHandler)
  else:
    let captured = handler
    window.mouseHandler = some(
      proc(w: Window, m: MouseEvent): EventResult =
        if captured(w, m): erConsume else: erContinue
    )

proc setResizeHandler*(window: Window, handler: WindowResizeHandler) =
  ## Set resize handler for window
  window.resizeHandler = some(handler)

proc clearEventHandlers*(window: Window) =
  ## Clear all event handlers for window
  window.eventHandler = none(WindowEventHandler)
  window.keyHandler = none(WindowKeyHandler)
  window.mouseHandler = none(WindowMouseHandler)
  window.resizeHandler = none(WindowResizeHandler)

proc handleWindowEvent*(window: Window, event: Event): EventResult =
  ## Handle event for a specific window.
  ##
  ## Returns:
  ## - `erConsume` when a handler accepted the event (no further propagation).
  ## - `erContinue` when no handler matched, the handler returned
  ##   `erContinue`, or the window is not accepting events.
  ##
  ## Handlers are tried in order: specific (key/mouse) → general
  ## `eventHandler`. A specific handler returning `erContinue` falls back
  ## to the general handler.
  ##
  ## `erQuit` from a window handler is normalized to `erConsume` here:
  ## only the global `App.onEvent` handler can signal quit (see
  ## `EventResult` in `events.nim`).
  if not window.acceptsEvents or not window.visible:
    return erContinue

  template normalize(r: EventResult): EventResult =
    if r == erQuit: erConsume else: r

  # Try specific handlers first
  case event.kind
  of EventKind.Key:
    if window.keyHandler.isSome():
      let r = window.keyHandler.get()(window, event.key)
      if r != erContinue:
        return normalize(r)
  of EventKind.Mouse:
    if window.mouseHandler.isSome():
      # Check if mouse event is within window bounds
      let mousePos = pos(event.mouse.x, event.mouse.y)
      if window.area.contains(mousePos):
        let r = window.mouseHandler.get()(window, event.mouse)
        if r != erContinue:
          return normalize(r)
  else:
    discard

  # Try general event handler
  if window.eventHandler.isSome():
    return normalize(window.eventHandler.get()(window, event))

  return erContinue

template bindWidget*(window: Window, widget: untyped) =
  ## Forward this window's key and mouse events to `widget`.
  ##
  ## Two binding shapes are supported, tried in order:
  ##
  ## 1. **Unified dispatch** — when `widget.handleEvent(Event, Rect)`
  ##    compiles (the case for all built-in `Widget` subclasses, which
  ##    inherit the base method). Both the key and mouse handlers wrap
  ##    the kind-specific event into an `Event` and dispatch through the
  ##    single method. Widgets that don't care about a given kind return
  ##    `erContinue` and the window falls through to its general
  ##    `eventHandler`.
  ## 2. **Legacy duck-typed dispatch** — for widget-shaped types that do
  ##    not inherit from `Widget` but provide `handleKeyEvent` and/or
  ##    `handleMouseEvent` procs. Whichever proc the type provides is
  ##    bound; the other handler is skipped, preserving the original
  ##    behavior where mouse events on a key-only widget fall through to
  ##    the window's `eventHandler`.
  ##
  ## The mouse area passed to the widget is the window's `contentArea`.
  when compiles(widget.handleEvent(Event(), Rect())):
    window.setKeyHandler proc(w: Window, k: KeyEvent): EventResult =
      widget.handleEvent(Event(kind: EventKind.Key, key: k), w.contentArea)
    window.setMouseHandler proc(w: Window, m: MouseEvent): EventResult =
      widget.handleEvent(Event(kind: EventKind.Mouse, mouse: m), w.contentArea)
  else:
    when compiles(widget.handleKeyEvent(KeyEvent())):
      window.setKeyHandler proc(w: Window, k: KeyEvent): EventResult =
        widget.handleKeyEvent(k)
    when compiles(widget.handleMouseEvent(MouseEvent(), Rect())):
      window.setMouseHandler proc(w: Window, m: MouseEvent): EventResult =
        widget.handleMouseEvent(m, w.contentArea)

# Window rendering

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

  # Draw title if present. `maxTitleLen` is a column budget, so compare and
  # truncate by display width — never by byte length — so a multibyte or
  # wide-character title is not split mid-codepoint (which would emit invalid
  # UTF-8) and never overflows the border.
  if window.title.len > 0 and border.top:
    let maxTitleLen = max(0, area.width - 4)
    if maxTitleLen > 0:
      let titleStart = area.x + 2
      let displayTitle =
        if window.title.displayWidth <= maxTitleLen:
          window.title
        else:
          # Reserve one column for the ellipsis (width 1) and truncate the
          # rest on rune boundaries.
          window.title.truncateToWidth(maxTitleLen - 1) & "…"
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

# WindowManager implementation

proc newWindowManager*(): WindowManager =
  ## Create a new window manager
  WindowManager(
    windows: @[], nextWindowId: 1, focusedWindow: none(WindowId), modalStack: @[]
  )

proc currentModal*(wm: WindowManager): Option[WindowId] {.inline.} =
  ## Top of the modal stack, or `none` when no modal is active.
  if wm.modalStack.len > 0:
    some(wm.modalStack[^1])
  else:
    none(WindowId)

proc getWindow*(wm: WindowManager, windowId: WindowId): Option[Window] =
  ## Get a window by ID
  for window in wm.windows:
    if window.id == windowId:
      return some(window)
  return none(Window)

proc focusWindow*(wm: WindowManager, windowId: WindowId): bool =
  ## Focus a specific window.
  ## Returns true if the window was found and focused, false otherwise.
  ##
  ## Note: focusing a modal window does **not** push it onto `modalStack`.
  ## Modal status is bound to `addWindow`/`removeWindow` only — `focusWindow`
  ## just moves the focus pointer. (Prior versions re-asserted modal state
  ## here; that behavior was removed to make the modal-stack the single
  ## source of truth.)
  let windowOpt = wm.getWindow(windowId)
  if windowOpt.isSome():
    let window = windowOpt.get()
    wm.focusedWindow = some(windowId)

    # Bring window to front (highest z-index) only when explicitly focusing
    let maxZ =
      if wm.windows.len > 0:
        wm.windows.mapIt(it.zIndex).max
      else:
        0
    window.zIndex = maxZ + 1

    return true
  return false

proc addWindow*(wm: WindowManager, window: Window, autoFocus: bool = true): WindowId =
  ## Add a window to the manager and return its ID.
  ## The first window added is always auto-focused, and modal windows are
  ## always focused regardless of `autoFocus` (a modal that is not focused
  ## would silently grab events). For other windows, `autoFocus = true`
  ## (default) takes focus; pass `false` to add without disturbing the
  ## current focus.
  ##
  ## Modal windows are pushed onto `modalStack` so nested modals stack
  ## correctly; the top of the stack receives events until removed.
  window.id = WindowId(wm.nextWindowId)
  inc wm.nextWindowId

  # Set Z-index based on current window count (before adding)
  window.zIndex = wm.windows.len

  window.managerRef = wm
  wm.windows.add(window)

  if wm.windows.len == 1 or autoFocus or window.modal:
    wm.focusedWindow = some(window.id)

  # Push onto modal stack if the window is modal
  if window.modal:
    wm.modalStack.add(window.id)

  return window.id

proc removeWindow*(wm: WindowManager, windowId: WindowId): bool =
  ## Remove a window from the manager
  ## Returns true if the window was found and removed, false otherwise
  ## All window resources (buffer, title, etc.) are automatically freed by Nim's GC
  ##
  ## When a modal window is removed (whether top of stack or not), it is
  ## erased from `modalStack`. The next-highest remaining modal (if any)
  ## becomes the new active modal.
  var removed: Window = nil
  for i, w in wm.windows:
    if w.id == windowId:
      removed = w
      wm.windows.delete(i)
      break

  if removed.isNil:
    return false

  removed.managerRef = nil

  # Remove from modal stack regardless of stack position. This runs
  # *before* the refocus step so that, when the removed window was the
  # focused (and possibly top-of-stack) modal, the refocus logic can
  # see the remaining stack and prefer the next-highest modal.
  for i in countdown(wm.modalStack.high, 0):
    if wm.modalStack[i] == windowId:
      wm.modalStack.delete(i)
      break

  # Update focus if the focused window was removed
  if wm.focusedWindow.isSome():
    let focusedId = wm.focusedWindow.get()
    if focusedId == windowId:
      let topModal = wm.currentModal()
      if topModal.isSome():
        # Prefer the next active modal so focus and the modal stack
        # stay in sync — otherwise focus could land on a window that
        # the modal routing immediately overrides.
        discard wm.focusWindow(topModal.get())
      elif wm.windows.len > 0:
        discard wm.focusWindow(wm.windows[^1].id) # Focus last window
      else:
        wm.focusedWindow = none(WindowId)

  return true

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

proc handleEvent*(wm: WindowManager, event: Event): EventResult =
  ## Route an event to the appropriate window and return the propagation
  ## outcome.
  ##
  ## Routing order:
  ## 1. The highest *visible* modal on `modalStack` receives the event
  ##    exclusively. Mouse clicks outside the modal's bounds are dropped
  ##    here (`erConsume`) so they neither reach lower windows nor the
  ##    global handler — this preserves modal semantics even when the
  ##    modal sets only a general `eventHandler` (which would otherwise
  ##    bypass the mouse-bounds check inside `handleWindowEvent`).
  ## 2. Mouse events go to the topmost visible window at the cursor
  ##    position; on `Press`, that window is auto-focused.
  ## 3. All other events go to the currently focused window.
  ##
  ## Returns `erConsume` when a window's handler accepted the event, or
  ## `erContinue` otherwise (no window, no handler, or handler returned
  ## `erContinue`).

  # Route to the highest *visible* modal: a minimized/hidden one stays on
  # `modalStack` to be restored later, but must not capture events.
  for i in countdown(wm.modalStack.high, 0):
    let modalWindow = wm.getWindow(wm.modalStack[i])
    if modalWindow.isSome() and modalWindow.get().visible:
      let modal = modalWindow.get()
      # Drop mouse clicks outside the modal's area so a general
      # eventHandler on the modal doesn't observe out-of-bounds clicks.
      if event.kind == EventKind.Mouse:
        let mousePos = pos(event.mouse.x, event.mouse.y)
        if not modal.area.contains(mousePos):
          return erConsume
      return modal.handleWindowEvent(event)

  # For mouse events, find the topmost window at mouse position
  if event.kind == EventKind.Mouse:
    let mousePos = pos(event.mouse.x, event.mouse.y)
    let windowAtPos = wm.findWindowAt(mousePos)
    if windowAtPos.isSome():
      let window = windowAtPos.get()
      # Auto-focus window on mouse click
      if event.mouse.kind == Press:
        discard wm.focusWindow(window.id)
      return window.handleWindowEvent(event)
    # No window under the cursor: the click is outside every window. Do not
    # fall through to the focused window, whose general `eventHandler` would
    # otherwise observe (and could `erConsume`) an out-of-bounds click (its
    # specific `mouseHandler` is already bounds-checked). Let the event
    # propagate to the global handler instead.
    #
    # Note: this intentionally differs from the modal path above. Modals trap
    # outside clicks (`erConsume`) to preserve modal semantics, while ordinary
    # windows allow outside clicks to reach the global handler (`erContinue`).
    return erContinue

  # For non-mouse events, route to the focused window
  let focusedWindow = wm.getFocusedWindow()
  if focusedWindow.isSome():
    return focusedWindow.get().handleWindowEvent(event)

  return erContinue

proc dispatchResize*(wm: WindowManager, newSize: Size) =
  ## Broadcast a resize event to every visible window's `resizeHandler`.
  ##
  ## Intended to be called from the application tick after the terminal
  ## size change is detected. The return value of each handler is
  ## ignored because resize is a broadcast event, not a routed one.
  ##
  ## Exceptions raised by a handler are swallowed so one window's
  ## failure does not block the others. We catch `Exception` (rather
  ## than the narrower `CatchableError`) because resize handlers have
  ## no `{.raises.}` annotation, so the effect system treats them as
  ## potentially raising bare `Exception`. This also lets the same
  ## proc be called from chronos `{.async.}` contexts without leaking
  ## an unlisted raise effect to the caller.
  ##
  ## With `--panics:on` (recommended for production) `Defect`s terminate
  ## the program before reaching this handler, so programmer bugs still
  ## surface. With `--panics:off` (default) Defects are caught and the
  ## broadcast continues.
  for window in wm.windows:
    if window.resizeHandler.isSome() and window.visible:
      try:
        discard window.resizeHandler.get()(window, newSize)
      except Exception:
        discard

proc render*(wm: WindowManager, destBuffer: var Buffer) =
  ## Render all windows to the destination buffer
  let visibleWindows = wm.getVisibleWindows()

  for window in visibleWindows:
    window.render(destBuffer)

# Utility functions

proc bringToFront*(wm: WindowManager, windowId: WindowId): bool =
  ## Bring a window to the front
  ## Returns true if the window was found and brought to front, false otherwise
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
