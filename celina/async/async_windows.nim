## Async Window Management System
## ==============================
##
## This module provides window management capabilities for async operations,
## allowing for overlapping, resizable, and focusable window areas within the terminal.
##
## Event Handling
## --------------
## `handleEventSync` is the canonical entry point for routing events
## through the manager. It mirrors `core/windows.nim:handleEvent` —
## including modal-stack routing — and returns `EventResult` so callers
## can participate in the window-first fallthrough chain. Safe to call
## from async contexts under `{.cast(gcsafe).}`.

import std/[algorithm, options]

import async_backend, async_buffer
import ../core/[geometry, buffer, events, windows]

export
  WindowId, Window, WindowState, WindowBorder, BorderChars, WindowEventHandler,
  WindowKeyHandler, WindowMouseHandler, WindowResizeHandler, newWindow, WindowInfo,
  toWindowInfo

type
  ## Async window manager for cooperative multitasking
  AsyncWindowManager* = ref object of BaseWindowManager
    windows: seq[Window]
    nextWindowId: int
    modalStack*: seq[WindowId]
      ## Stack of modal window IDs, bottom-to-top. Mirrors the sync
      ## `WindowManager.modalStack`. The top of the stack receives all
      ## events; lower modals are inert until the top is removed.

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
  result.modalStack = @[]

proc currentModal*(awm: AsyncWindowManager): Option[WindowId] {.inline.} =
  ## Top of the modal stack, or `none` when no modal is active.
  if awm.modalStack.len > 0:
    some(awm.modalStack[^1])
  else:
    none(WindowId)

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
    awm.modalStack.add(window.id)

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

  # Remove from modal stack first so the refocus step below can prefer
  # the next-highest remaining modal. Mirrors `core/windows.nim`.
  for i in countdown(awm.modalStack.high, 0):
    if awm.modalStack[i] == windowId:
      awm.modalStack.delete(i)
      break

  # Update focused window if necessary
  if awm.focusedWindow.isSome() and awm.focusedWindow.get() == windowId:
    let topModal = awm.currentModal()
    if topModal.isSome():
      # Prefer the next active modal so focus stays in sync with modal
      # routing.
      awm.focusedWindow = topModal
    elif awm.windows.len > 0:
      let nextWindow = awm.windows[^1] # Focus the top window
      awm.focusedWindow = some(nextWindow.id)
    else:
      awm.focusedWindow = none(WindowId)

  return true

proc focusWindowAsync*(
    awm: AsyncWindowManager, windowId: WindowId
): Future[bool] {.async.} =
  ## Focus a specific window asynchronously.
  ##
  ## Note: focusing a modal window does **not** modify `modalStack`. Modal
  ## status is bound to `addWindow`/`removeWindow` only. (Prior versions
  ## re-asserted modal state here.)
  if awm.isNil:
    return false

  await sleepMs(0)

  # Focus the target window
  for window in awm.windows:
    if not window.isNil and window.id == windowId and window.visible:
      awm.focusWindowHelper(window)
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
  ## Focus a specific window synchronously.
  ##
  ## Note: focusing a modal window does **not** modify `modalStack`. Modal
  ## status is bound to `addWindow`/`removeWindow` only. (Prior versions
  ## re-asserted modal state here.)
  if awm.isNil:
    return false

  # Find and focus the target window
  for window in awm.windows:
    if not window.isNil and window.id == windowId and window.visible:
      awm.focusWindowHelper(window)
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

# Event Handling
#
# `handleEventSync` is the canonical entry point. The previous
# `handleEventAsync` only checked handler presence (never invoked them)
# due to a GC-safety workaround and was never called from the async tick
# loop — it has been removed. Async callers (`async_app.tickAsync`) use
# `handleEventSync` under `{.cast(gcsafe).}`.

proc handleEventSync*(awm: AsyncWindowManager, event: Event): EventResult =
  ## Route an event through the async window manager and return the
  ## propagation outcome. Mirrors `core/windows.nim:handleEvent`.
  ##
  ## Routing order: modal stack top -> mouse position -> focused window.
  ## Returns `erConsume` when a window's handler accepted the event, or
  ## `erContinue` otherwise (no window, no handler, or handler returned
  ## `erContinue`). A handler that raises is treated as `erContinue`.
  if awm.isNil:
    return erContinue

  try:
    # If there's a modal window, only it can handle events
    let modalOpt = awm.currentModal()
    if modalOpt.isSome():
      let modalWindow = getWindowHelper(awm, modalOpt.get())
      if modalWindow.isSome():
        let modal = modalWindow.get()
        # Drop mouse clicks outside the modal's area so a general
        # eventHandler on the modal doesn't observe out-of-bounds clicks.
        # Mirrors `core/windows.nim:handleEvent`.
        if event.kind == EventKind.Mouse:
          let mousePos = pos(event.mouse.x, event.mouse.y)
          if not modal.area.contains(mousePos):
            return erConsume
        return modal.handleWindowEvent(event)

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
        return window.handleWindowEvent(event)
      return erContinue

    # For other events, route to focused window
    let focused = awm.getFocusedWindowSync()
    if focused.isSome():
      return focused.get().handleWindowEvent(event)

    return erContinue
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
    return erContinue

proc dispatchResize*(awm: AsyncWindowManager, newSize: Size) =
  ## Broadcast a resize event to every visible window's `resizeHandler`.
  ## Mirrors `core/windows.nim:dispatchResize` exactly — see that proc's
  ## docstring for the rationale on catching `Exception` (rather than
  ## `CatchableError`) and the `--panics:on/off` interaction with Defects.
  if awm.isNil:
    return
  for window in awm.windows:
    if not window.isNil and window.resizeHandler.isSome() and window.visible:
      try:
        discard window.resizeHandler.get()(window, newSize)
      except Exception:
        discard

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
    awm.modalStack.add(window.id)

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

  # Remove from modal stack first so the refocus step can prefer the
  # next-highest remaining modal. Mirrors `core/windows.nim`.
  for i in countdown(awm.modalStack.high, 0):
    if awm.modalStack[i] == windowId:
      awm.modalStack.delete(i)
      break

  # Update focused window if necessary
  if awm.focusedWindow.isSome() and awm.focusedWindow.get() == windowId:
    let topModal = awm.currentModal()
    if topModal.isSome():
      awm.focusedWindow = topModal
    elif awm.windows.len > 0:
      let nextWindow = awm.windows[^1]
      awm.focusedWindow = some(nextWindow.id)
    else:
      awm.focusedWindow = none(WindowId)

  return true
