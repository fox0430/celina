## Async Window Management System
## ==============================
##
## This module provides window management capabilities for async operations,
## allowing for overlapping, resizable, and focusable window areas within the terminal.
##
## Event Handling
## --------------
## Two event handling functions are provided:
##
## - `handleEventSync`: Synchronous handler that **invokes** window event handlers.
##   Mirrors `core/windows.nim:handleEvent` semantics, including modal-window
##   routing. Use this when you need actual event processing. Safe to call from
##   async contexts with `{.cast(gcsafe).}`.
##
## - `handleEventAsync`: Async handler that only **checks** if handlers exist.
##   Due to GC safety constraints, it cannot invoke handlers directly.
##   Returns true if an appropriate handler exists for the event.
##
## For most use cases, prefer `handleEventSync` for actual event processing.

import std/[algorithm, options]

import async_backend, async_buffer
import ../core/[geometry, buffer, events, windows]

export
  WindowId, Window, WindowState, WindowBorder, BorderChars, EventPhase, WindowEvent,
  WindowEventHandler, WindowKeyHandler, WindowMouseHandler, WindowResizeHandler,
  EventHandler, newWindow, WindowInfo, toWindowInfo

type
  ## Async window manager for cooperative multitasking
  AsyncWindowManager* = ref object of BaseWindowManager
    windows: seq[Window]
    nextWindowId: int
    modalWindow*: Option[WindowId]
      ## ID of the currently active modal window, if any.
      ## When set, `handleEventSync` routes all events to this window only.

  AsyncWindowError* = object of CatchableError

# Helper Functions

proc getWindowHelper(awm: AsyncWindowManager, windowId: WindowId): Option[Window] =
  ## Helper function to get a window by ID
  for window in awm.windows:
    if window.id == windowId:
      return some(window)
  return none(Window)

proc focusWindowHelper(awm: AsyncWindowManager, window: Window) =
  ## Internal helper to focus a window and bring it to front.
  ## Does not check visibility - caller must ensure window is visible.
  ##
  ## Bumps `zIndex` above all current windows so the focused window stays on
  ## top under the zIndex-based sort used by `getVisibleWindowsSync/Async` and
  ## the renderers. Mirrors `core/windows.nim:focusWindow`.
  awm.focusedWindow = some(window.id)

  var maxZ = window.zIndex
  for w in awm.windows:
    if not w.isNil and w.zIndex > maxZ:
      maxZ = w.zIndex
  window.zIndex = maxZ + 1

# AsyncWindowManager Creation and Management

proc newAsyncWindowManager*(): AsyncWindowManager =
  ## Create a new async window manager
  result = AsyncWindowManager()
  result.windows = @[]
  result.nextWindowId = 1
  result.focusedWindow = none(WindowId)
  result.modalWindow = none(WindowId)

# Async Window Operations

proc getWindowAsync*(
    awm: AsyncWindowManager, windowId: WindowId
): Future[Option[Window]] {.async.} =
  ## Get a window by ID asynchronously
  if awm.isNil:
    return none(Window)

  await sleepMs(0) # Yield to other tasks

  for window in awm.windows:
    if not window.isNil and window.id == windowId:
      return some(window)

  return none(Window)

proc addWindowAsync*(
    awm: AsyncWindowManager, window: Window, autoFocus: bool = true
): Future[WindowId] {.async.} =
  ## Add a window to the manager and return its ID asynchronously.
  ## The first window added is always auto-focused, and modal windows are
  ## always focused regardless of `autoFocus`. Pass `autoFocus = false`
  ## to add a non-modal subsequent window without taking focus.
  if awm.isNil or window.isNil:
    raise newException(AsyncWindowError, "AsyncWindowManager or Window is nil")

  let newId = awm.nextWindowId
  awm.nextWindowId.inc()

  window.id = WindowId(newId)
  window.manager = awm
  awm.windows.add(window)

  if awm.windows.len == 1 or autoFocus or window.modal:
    awm.focusedWindow = some(window.id)

  if window.modal:
    awm.modalWindow = some(window.id)

  await sleepMs(0)
  return window.id

proc removeWindowAsync*(
    awm: AsyncWindowManager, windowId: WindowId
): Future[bool] {.async.} =
  ## Remove a window from the manager asynchronously
  ## All window resources are automatically freed by Nim's GC
  await sleepMs(0)

  var removed: Window = nil
  for i, window in awm.windows:
    if window.id == windowId:
      removed = window
      awm.windows.delete(i)
      break

  if removed.isNil:
    return false

  removed.manager = nil

  # Update focused window if necessary
  if awm.focusedWindow.isSome() and awm.focusedWindow.get() == windowId:
    # Focus the next available window
    if awm.windows.len > 0:
      let nextWindow = awm.windows[^1] # Focus the top window
      awm.focusedWindow = some(nextWindow.id)
    else:
      awm.focusedWindow = none(WindowId)

  # Clear modal if the modal window was removed
  if awm.modalWindow.isSome() and awm.modalWindow.get() == windowId:
    awm.modalWindow = none(WindowId)

  return true

proc focusWindowAsync*(
    awm: AsyncWindowManager, windowId: WindowId
): Future[bool] {.async.} =
  ## Focus a specific window asynchronously
  if awm.isNil:
    return false

  await sleepMs(0)

  # Focus the target window
  for window in awm.windows:
    if not window.isNil and window.id == windowId and window.visible:
      awm.focusWindowHelper(window)
      if window.modal:
        awm.modalWindow = some(windowId)
      return true

  return false

proc getFocusedWindowAsync*(awm: AsyncWindowManager): Future[Option[Window]] {.async.} =
  ## Get the currently focused window asynchronously
  if awm.isNil:
    return none(Window)

  await sleepMs(0)

  if awm.focusedWindow.isSome():
    let windowId = awm.focusedWindow.get()
    for window in awm.windows:
      if not window.isNil and window.id == windowId:
        return some(window)

  return none(Window)

proc getVisibleWindowsSync*(awm: AsyncWindowManager): seq[Window] {.gcsafe, raises: [].}

proc getVisibleWindowsAsync*(awm: AsyncWindowManager): Future[seq[Window]] {.async.} =
  ## Get all visible windows sorted by Z-index asynchronously.
  ## Delegates to `getVisibleWindowsSync` after yielding so sync/async callers
  ## share one implementation.
  await sleepMs(0)
  return awm.getVisibleWindowsSync()

proc findWindowAtAsync*(
    awm: AsyncWindowManager, pos: Position
): Future[Option[Window]] {.async.} =
  ## Find the topmost window at the given position asynchronously
  let visibleWindows = await awm.getVisibleWindowsAsync()

  # Check windows from top to bottom (reverse order)
  for i in countdown(visibleWindows.len - 1, 0):
    let window = visibleWindows[i]
    if window.area.contains(pos):
      return some(window)

  return none(Window)

# Synchronous helpers (mirror the API in core/windows.nim)

proc getVisibleWindowsSync*(awm: AsyncWindowManager): seq[Window] =
  ## Get all visible windows sorted by Z-index synchronously.
  ## Mirrors `core/windows.nim:getVisibleWindows` and `getVisibleWindowsAsync`
  ## so sync/async queries and the renderers agree on stacking order.
  if awm.isNil or awm.windows.len == 0:
    return @[]
  result = newSeqOfCap[Window](min(awm.windows.len, 16))
  for window in awm.windows:
    if not window.isNil and window.visible:
      result.add(window)
  result.sort(
    proc(a, b: Window): int {.gcsafe, raises: [].} =
      cmp(a.zIndex, b.zIndex)
  )

proc findWindowAtSync*(awm: AsyncWindowManager, pos: Position): Option[Window] =
  ## Find the topmost window at the given position synchronously
  let visibleWindows = awm.getVisibleWindowsSync()
  for i in countdown(visibleWindows.high, 0):
    let window = visibleWindows[i]
    if window.area.contains(pos):
      return some(window)
  return none(Window)

proc focusWindowSync*(awm: AsyncWindowManager, windowId: WindowId): bool =
  ## Focus a specific window synchronously
  if awm.isNil:
    return false

  # Find and focus the target window
  for window in awm.windows:
    if not window.isNil and window.id == windowId and window.visible:
      awm.focusWindowHelper(window)
      if window.modal:
        awm.modalWindow = some(windowId)
      return true

  return false

proc getFocusedWindowSync*(awm: AsyncWindowManager): Option[Window] =
  ## Get the currently focused window synchronously
  if awm.isNil:
    return none(Window)

  if awm.focusedWindow.isSome():
    let windowId = awm.focusedWindow.get()
    for window in awm.windows:
      if not window.isNil and window.id == windowId:
        return some(window)

  return none(Window)

# Async Event Handling

proc handleEventAsync*(awm: AsyncWindowManager, event: Event): Future[bool] {.async.} =
  ## Handle an event asynchronously - checks if a window can handle the event.
  ##
  ## Note: Due to GC safety constraints in async contexts, this function only
  ## checks if an appropriate handler exists but does not invoke it.
  ## For actual event handling, use handleEventSync which can safely invoke handlers.
  ##
  ## Returns true if a window has an appropriate handler for the event.

  if awm.isNil:
    return false

  try:
    case event.kind
    of Key:
      # Check if focused window has a key handler
      let focusedWindowOpt = await awm.getFocusedWindowAsync()
      if focusedWindowOpt.isSome():
        let window = focusedWindowOpt.get()
        return window.keyHandler.isSome()
      return false
    of Mouse:
      # Check if window at position has a mouse handler
      let windowOpt = await awm.findWindowAtAsync(pos(event.mouse.x, event.mouse.y))
      if windowOpt.isSome():
        let window = windowOpt.get()
        return window.mouseHandler.isSome()
      return false
    of Resize:
      # Check if any visible window has a resize handler
      let visibleWindows = await awm.getVisibleWindowsAsync()
      for window in visibleWindows:
        if window.resizeHandler.isSome():
          return true
      return false
    else:
      return false
  except CatchableError:
    # Handler check failed - window state may be invalid
    return false

proc handleEventSync*(awm: AsyncWindowManager, event: Event): bool =
  ## Synchronous event handling for AsyncWindowManager.
  ## Routes events to appropriate windows and invokes their handlers,
  ## mirroring `core/windows.nim:handleEvent`.
  ##
  ## Unlike handleEventAsync, this function actually invokes the event handlers.
  ## Safe to call from async contexts with `{.cast(gcsafe).}`.
  ##
  ## Returns true if the event was handled by a window.
  if awm.isNil:
    return false

  try:
    # If there's a modal window, only it can handle events
    if awm.modalWindow.isSome():
      let modalOpt = getWindowHelper(awm, awm.modalWindow.get())
      if modalOpt.isSome():
        return modalOpt.get().handleWindowEvent(event)

    # For mouse events, find the topmost window at mouse position
    if event.kind == EventKind.Mouse:
      let mousePos = pos(event.mouse.x, event.mouse.y)
      let windowAtPos = awm.findWindowAtSync(mousePos)
      if windowAtPos.isSome():
        let window = windowAtPos.get()
        # Auto-focus window on mouse click. zIndex bump alone is enough — the
        # zIndex-based sort in getVisibleWindows{Sync,Async} keeps the focused
        # window on top without reordering `awm.windows`.
        if event.mouse.kind == Press:
          awm.focusWindowHelper(window)
          if window.modal:
            awm.modalWindow = some(window.id)
        return window.handleWindowEvent(event)
      return false

    # For other events, route to focused window
    let focused = awm.getFocusedWindowSync()
    if focused.isSome():
      return focused.get().handleWindowEvent(event)

    return false
  except Exception:
    # User-supplied window handler raised - treat as unhandled.
    #
    # We catch `Exception` (rather than `CatchableError`) intentionally:
    # window callbacks have no `{.raises.}` annotation, so Nim's effect
    # system infers they may raise bare `Exception`. Chronos's `{.async.}`
    # in particular requires this proc to close over those effects so the
    # caller (`async_app.tickAsync`) does not inherit an unlisted raise.
    #
    # `Defect`s (IndexDefect, nil dereference, etc.) inherit from
    # `Exception` and are thus also caught here when `--panics:off` (the
    # current default); with `--panics:on` they terminate the program and
    # never reach this handler. Either way, downstream code does not rely
    # on observing defects through this path.
    return false

# Async Window Border Drawing

proc drawAsyncWindowBorder(window: Window, destBuffer: var Buffer) =
  ## Draw window border to destination buffer (async-compatible)
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

# Async Rendering

proc renderAsync*(
    awm: AsyncWindowManager, destBuffer: async_buffer.AsyncBuffer
): Future[void] {.async.} =
  ## Render all windows to the destination buffer asynchronously
  let visibleWindows = await awm.getVisibleWindowsAsync()

  # Render windows from bottom to top (ascending zIndex from getVisibleWindowsAsync)
  for window in visibleWindows:
    if window.state == wsMinimized:
      continue
    # Create a buffer for the complete window (including borders)
    var windowBuffer = newBuffer(window.area)

    # Draw window border first if enabled
    if window.border.isSome():
      drawAsyncWindowBorder(window, windowBuffer)

    # Then, copy the window's content buffer to the content area (on top of border)
    if window.buffer.area.width > 0 and window.buffer.area.height > 0:
      let contentPos =
        pos(window.contentArea.x - window.area.x, window.contentArea.y - window.area.y)
      windowBuffer.merge(window.buffer, contentPos)

    # Convert to AsyncBuffer and merge
    let asyncWindowBuffer = newAsyncBuffer(window.area)
    asyncWindowBuffer.updateFromBufferAsync(windowBuffer)

    await destBuffer.mergeAsync(asyncWindowBuffer, pos(window.area.x, window.area.y))

  # Yield to allow other async operations
  await sleepMs(0)

proc renderSync*(awm: AsyncWindowManager, destBuffer: var Buffer) =
  ## Synchronous render for compatibility with existing sync code.
  ## Uses window.buffer content which should be updated by the application.
  ## Windows are drawn in ascending Z-index order so the top window (highest
  ## zIndex) is painted last, matching `findWindowAtSync`'s pick order.
  let visibleWindows = awm.getVisibleWindowsSync()

  for window in visibleWindows:
    if window.state == wsMinimized:
      continue
    # Use window's buffer content directly
    var windowBuffer = window.buffer

    # Draw border if configured
    if window.border.isSome():
      drawAsyncWindowBorder(window, windowBuffer)

    destBuffer.merge(windowBuffer, pos(window.area.x, window.area.y))

# Window Layout and Management

proc bringToFrontAsync*(
    awm: AsyncWindowManager, windowId: WindowId
): Future[bool] {.async.} =
  ## Bring a window to the front asynchronously
  return await awm.focusWindowAsync(windowId)

proc sendToBackAsync*(
    awm: AsyncWindowManager, windowId: WindowId
): Future[bool] {.async.} =
  ## Send a window to the back asynchronously
  await sleepMs(0)

  let windowOpt = getWindowHelper(awm, windowId)
  if windowOpt.isSome():
    let window = windowOpt.get()
    let windowIndex = awm.windows.find(window)
    if windowIndex >= 0:
      awm.windows.delete(windowIndex)
      awm.windows.insert(window, 0) # Insert at beginning
      return true
  return false

proc resizeWindowAsync*(
    awm: AsyncWindowManager, windowId: WindowId, newSize: Size
): Future[bool] {.async.} =
  ## Resize a window asynchronously
  await sleepMs(0)

  let windowOpt = getWindowHelper(awm, windowId)
  if windowOpt.isSome():
    let window = windowOpt.get()
    window.area.width = newSize.width
    window.area.height = newSize.height

    # Note: Resize handlers not called in async mode for GC safety
    # Handler invocation would require careful design to be GC-safe

    return true
  return false

proc moveWindowAsync*(
    awm: AsyncWindowManager, windowId: WindowId, newPos: Position
): Future[bool] {.async.} =
  ## Move a window to a new position asynchronously
  await sleepMs(0)

  let windowOpt = getWindowHelper(awm, windowId)
  if windowOpt.isSome():
    let window = windowOpt.get()
    window.area.x = newPos.x
    window.area.y = newPos.y
    return true
  return false

# Compatibility Layer

proc getWindowSync*(awm: AsyncWindowManager, windowId: WindowId): Option[Window] =
  ## Synchronous getWindow for compatibility with sync code
  ## For async code, use getWindowAsync instead
  for window in awm.windows:
    if window.id == windowId:
      return some(window)
  return none(Window)

# Statistics and Debugging

proc getStats*(awm: AsyncWindowManager): tuple[windowCount: int, focusedId: int] =
  ## Get window manager statistics
  let focusedId =
    if awm.focusedWindow.isSome():
      awm.focusedWindow.get().int
    else:
      -1
  return (awm.windows.len, focusedId)

proc getWindowsSync*(awm: AsyncWindowManager): seq[Window] =
  ## Get all windows synchronously
  if awm.isNil:
    return @[]
  result = awm.windows

proc getWindowCountSync*(awm: AsyncWindowManager): int =
  ## Get the number of windows synchronously
  if awm.isNil:
    return 0
  result = awm.windows.len

proc getFocusedWindowIdSync*(awm: AsyncWindowManager): Option[WindowId] =
  ## Get the ID of the focused window synchronously
  if awm.isNil:
    return none(WindowId)
  result = awm.focusedWindow

proc addWindowSync*(
    awm: AsyncWindowManager, window: Window, autoFocus: bool = true
): WindowId =
  ## Add a window to the manager synchronously and return its ID.
  ## The first window added is always auto-focused, and modal windows are
  ## always focused regardless of `autoFocus`. Pass `autoFocus = false`
  ## to add a non-modal subsequent window without taking focus.
  if awm.isNil or window.isNil:
    raise newException(AsyncWindowError, "AsyncWindowManager or Window is nil")

  let newId = awm.nextWindowId
  awm.nextWindowId.inc()

  window.id = WindowId(newId)
  window.manager = awm
  awm.windows.add(window)

  if awm.windows.len == 1 or autoFocus or window.modal:
    awm.focusedWindow = some(window.id)

  if window.modal:
    awm.modalWindow = some(window.id)

  return window.id

proc removeWindowSync*(awm: AsyncWindowManager, windowId: WindowId): bool =
  ## Remove a window from the manager synchronously
  var removed: Window = nil
  for i, window in awm.windows:
    if window.id == windowId:
      removed = window
      awm.windows.delete(i)
      break

  if removed.isNil:
    return false

  removed.manager = nil

  # Update focused window if necessary
  if awm.focusedWindow.isSome() and awm.focusedWindow.get() == windowId:
    # Focus the next available window
    if awm.windows.len > 0:
      let nextWindow = awm.windows[^1]
      awm.focusedWindow = some(nextWindow.id)
    else:
      awm.focusedWindow = none(WindowId)

  # Clear modal if the modal window was removed
  if awm.modalWindow.isSome() and awm.modalWindow.get() == windowId:
    awm.modalWindow = none(WindowId)

  return true
