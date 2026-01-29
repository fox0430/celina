## Async Window management system
##
## This module provides window management capabilities for async operations,
## allowing for overlapping, resizable, and focusable window areas within the terminal.

import std/[sequtils, options]

import async_backend, async_buffer
import ../core/[geometry, buffer, colors, events, windows]

export
  WindowId, Window, WindowState, WindowBorder, BorderChars, EventPhase, WindowEvent,
  WindowEventHandler, WindowKeyHandler, WindowMouseHandler, WindowResizeHandler,
  EventHandler, newWindow, WindowInfo, toWindowInfo

type
  ## Async window manager for cooperative multitasking
  AsyncWindowManager* = ref object
    windows: seq[Window]
    nextWindowId: int
    focusedWindow: Option[WindowId]

  AsyncWindowError* = object of CatchableError

# Helper Functions

proc getWindowHelper(awm: AsyncWindowManager, windowId: WindowId): Option[Window] =
  ## Helper function to get a window by ID
  for window in awm.windows:
    if window.id == windowId:
      return some(window)
  return none(Window)

# AsyncWindowManager Creation and Management

proc newAsyncWindowManager*(): AsyncWindowManager =
  ## Create a new async window manager
  result = AsyncWindowManager()
  result.windows = @[]
  result.nextWindowId = 1
  result.focusedWindow = none(WindowId)

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
    awm: AsyncWindowManager, window: Window
): Future[WindowId] {.async.} =
  ## Add a window to the manager and return its ID asynchronously
  if awm.isNil or window.isNil:
    raise newException(AsyncWindowError, "AsyncWindowManager or Window is nil")

  let newId = awm.nextWindowId
  awm.nextWindowId.inc()

  window.id = WindowId(newId)
  awm.windows.add(window)

  # Auto-focus if it's the first window or marked for focus
  if awm.windows.len == 1 or window.focused:
    awm.focusedWindow = some(window.id)
    window.focused = true

  await sleepMs(0)
  return window.id

proc removeWindowAsync*(
    awm: AsyncWindowManager, windowId: WindowId
): Future[bool] {.async.} =
  ## Remove a window from the manager asynchronously
  ## All window resources are automatically freed by Nim's GC
  await sleepMs(0)

  var windowToRemove: Option[Window] = none(Window)
  for window in awm.windows:
    if window.id == windowId:
      windowToRemove = some(window)
      break

  if windowToRemove.isSome():
    # Remove from windows list
    awm.windows = awm.windows.filterIt(it.id != windowId)

    # Update focused window if necessary
    if awm.focusedWindow.isSome() and awm.focusedWindow.get() == windowId:
      # Focus the next available window
      if awm.windows.len > 0:
        let nextWindow = awm.windows[^1] # Focus the top window
        awm.focusedWindow = some(nextWindow.id)
        nextWindow.focused = true
      else:
        awm.focusedWindow = none(WindowId)

    return true
  else:
    return false

proc focusWindowAsync*(
    awm: AsyncWindowManager, windowId: WindowId
): Future[bool] {.async.} =
  ## Focus a specific window asynchronously
  if awm.isNil:
    return false

  await sleepMs(0)

  # Unfocus all windows
  for window in awm.windows:
    if not window.isNil:
      window.focused = false

  # Focus the target window
  for i, window in awm.windows:
    if not window.isNil and window.id == windowId and window.visible:
      window.focused = true
      awm.focusedWindow = some(windowId)

      # Bring to front by moving to end of sequence
      awm.windows.delete(i)
      awm.windows.add(window)

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

proc getVisibleWindowsAsync*(awm: AsyncWindowManager): Future[seq[Window]] {.async.} =
  ## Get all visible windows sorted by Z-index asynchronously
  if awm.isNil:
    return @[]

  await sleepMs(0)

  for window in awm.windows:
    if not window.isNil and window.visible and window.state != wsHidden:
      result.add(window)

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

# Async Event Handling

proc handleEventAsync*(awm: AsyncWindowManager, event: Event): Future[bool] {.async.} =
  ## Handle an event, routing it to the appropriate window asynchronously
  ## Returns true if the event was handled
  ## Note: Event handlers are executed synchronously for GC safety

  try:
    case event.kind
    of Key:
      # Route keyboard events to focused window
      let focusedWindowOpt = await awm.getFocusedWindowAsync()
      if focusedWindowOpt.isSome():
        let window = focusedWindowOpt.get()
        # For now, just return true if window can handle keys
        # Real handler invocation would need GC-safe redesign
        return window.keyHandler.isSome()
    of Mouse:
      # Route mouse events to window under cursor
      let windowOpt = await awm.findWindowAtAsync(pos(event.mouse.x, event.mouse.y))
      if windowOpt.isSome():
        let window = windowOpt.get()
        # For now, just return true if window can handle mouse
        return window.mouseHandler.isSome()
    of Resize:
      # Broadcast resize to all windows with resize handlers
      let visibleWindows = await awm.getVisibleWindowsAsync()
      var handlerCount = 0
      for window in visibleWindows:
        if window.resizeHandler.isSome():
          handlerCount.inc()
      # Return true if any window has resize handlers
      return handlerCount > 0
    else:
      discard

    return false
  except:
    return false

proc handleEventSync*(awm: AsyncWindowManager, event: Event): bool =
  ## Synchronous event handling for AsyncWindowManager
  ## Returns true if the event could be handled (window has appropriate handler)
  if awm.isNil:
    return false

  case event.kind
  of Key:
    # Check focused window for key handler
    if awm.focusedWindow.isSome():
      let windowId = awm.focusedWindow.get()
      for window in awm.windows:
        if window.id == windowId:
          return window.keyHandler.isSome()
  of Mouse:
    # Check window at mouse position for mouse handler
    let mousePos = pos(event.mouse.x, event.mouse.y)
    for i in countdown(awm.windows.len - 1, 0):
      let window = awm.windows[i]
      if window.visible and window.area.contains(mousePos):
        return window.mouseHandler.isSome()
  of Resize:
    # Check if any window has resize handler
    for window in awm.windows:
      if window.visible and window.resizeHandler.isSome():
        return true
  else:
    discard

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

  # Render windows from bottom to top
  for i, window in visibleWindows:
    if window.state != wsMinimized and window.state != wsHidden:
      # Create a buffer for the complete window (including borders)
      var windowBuffer = newBuffer(window.area)

      # Draw window border first if enabled
      if window.border.isSome():
        drawAsyncWindowBorder(window, windowBuffer)

      # Then, copy the window's content buffer to the content area (on top of border)
      if window.buffer.area.width > 0 and window.buffer.area.height > 0:
        let contentPos = pos(
          window.contentArea.x - window.area.x, window.contentArea.y - window.area.y
        )
        windowBuffer.merge(window.buffer, contentPos)

      # Convert to AsyncBuffer and merge
      let asyncWindowBuffer = newAsyncBufferNoRM(window.area)
      asyncWindowBuffer.updateFromBufferAsync(windowBuffer)

      await destBuffer.mergeAsync(asyncWindowBuffer, pos(window.area.x, window.area.y))

  # Yield to allow other async operations
  await sleepMs(0)

proc renderSync*(awm: AsyncWindowManager, destBuffer: var Buffer) =
  ## Synchronous render for compatibility with existing sync code
  var visibleWindows: seq[Window] = @[]
  for window in awm.windows:
    if window.visible and window.state != wsHidden:
      visibleWindows.add(window)

  for window in visibleWindows:
    if window.state != wsMinimized and window.state != wsHidden:
      var windowBuffer = newBuffer(window.area)

      # Render basic window content (placeholder)
      windowBuffer.setString(
        1, 1, window.title, Style(fg: color(White), modifiers: {Bold})
      )

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

proc addWindowSync*(awm: AsyncWindowManager, window: Window): WindowId =
  ## Add a window to the manager synchronously and return its ID
  if awm.isNil or window.isNil:
    raise newException(AsyncWindowError, "AsyncWindowManager or Window is nil")

  let newId = awm.nextWindowId
  awm.nextWindowId.inc()

  window.id = WindowId(newId)
  awm.windows.add(window)

  # Auto-focus if it's the first window or marked for focus
  if awm.windows.len == 1 or window.focused:
    awm.focusedWindow = some(window.id)
    window.focused = true

  return window.id

proc removeWindowSync*(awm: AsyncWindowManager, windowId: WindowId): bool =
  ## Remove a window from the manager synchronously
  var windowToRemove: Option[Window] = none(Window)
  for window in awm.windows:
    if window.id == windowId:
      windowToRemove = some(window)
      break

  if windowToRemove.isSome():
    # Remove from windows list
    awm.windows = awm.windows.filterIt(it.id != windowId)

    # Update focused window if necessary
    if awm.focusedWindow.isSome() and awm.focusedWindow.get() == windowId:
      # Focus the next available window
      if awm.windows.len > 0:
        let nextWindow = awm.windows[^1]
        awm.focusedWindow = some(nextWindow.id)
        nextWindow.focused = true
      else:
        awm.focusedWindow = none(WindowId)

    return true
  else:
    return false

proc focusWindowSync*(awm: AsyncWindowManager, windowId: WindowId): bool =
  ## Focus a specific window synchronously
  if awm.isNil:
    return false

  # Unfocus all windows
  for window in awm.windows:
    if not window.isNil:
      window.focused = false

  # Focus the target window
  for i, window in awm.windows:
    if not window.isNil and window.id == windowId and window.visible:
      window.focused = true
      awm.focusedWindow = some(windowId)

      # Bring to front by moving to end of sequence
      awm.windows.delete(i)
      awm.windows.add(window)

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
