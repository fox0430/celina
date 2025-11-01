## Cursor Management Module
## ======================
##
## Provides comprehensive cursor control and state management for terminal applications.
## Handles cursor positioning, visibility, and style changes.

import terminal_common

type
  CursorState* = object ## Cursor state management
    x*: int ## Cursor X position (-1 means not set)
    y*: int ## Cursor Y position (-1 means not set)
    visible*: bool ## Whether cursor is visible
    style*: CursorStyle ## Current cursor style
    lastStyle*: CursorStyle ## Previous cursor style (for tracking changes)

  CursorManager* = ref object ## Manages cursor operations and state
    state: CursorState

proc newCursorManager*(): CursorManager =
  ## Create a new cursor manager with default state
  result = CursorManager(
    state: CursorState(
      x: -1,
      y: -1,
      visible: false,
      style: CursorStyle.Default,
      lastStyle: CursorStyle.Default,
    )
  )

proc setPosition*(manager: CursorManager, x, y: int) =
  ## Set cursor position without changing visibility state
  manager.state.x = x
  manager.state.y = y

proc setPosition*(manager: CursorManager, x, y: int, visible: bool) =
  ## Set cursor position with explicit visibility control
  manager.state.x = x
  manager.state.y = y
  manager.state.visible = visible

proc showAt*(manager: CursorManager, x, y: int) =
  ## Set cursor position and make it visible
  manager.state.x = x
  manager.state.y = y
  manager.state.visible = true

proc show*(manager: CursorManager) =
  ## Show the cursor
  manager.state.visible = true

proc hide*(manager: CursorManager) =
  ## Hide the cursor
  manager.state.visible = false

proc setStyle*(manager: CursorManager, style: CursorStyle) =
  ## Set cursor style
  manager.state.lastStyle = manager.state.style
  manager.state.style = style

proc getPosition*(manager: CursorManager): (int, int) =
  ## Get current cursor position
  (manager.state.x, manager.state.y)

proc isVisible*(manager: CursorManager): bool =
  ## Check if cursor is visible
  manager.state.visible

proc getStyle*(manager: CursorManager): CursorStyle =
  ## Get current cursor style
  manager.state.style

proc getState*(manager: CursorManager): CursorState =
  ## Get the full cursor state
  manager.state

proc reset*(manager: CursorManager) =
  ## Reset cursor to default state
  manager.state.x = -1
  manager.state.y = -1
  manager.state.visible = false
  manager.state.style = CursorStyle.Default
  manager.state.lastStyle = CursorStyle.Default

proc hasPosition*(manager: CursorManager): bool =
  ## Check if cursor has a valid position set
  manager.state.x >= 0 and manager.state.y >= 0

proc styleChanged*(manager: CursorManager): bool =
  ## Check if cursor style has changed since last update
  manager.state.style != manager.state.lastStyle

proc updateLastStyle*(manager: CursorManager) =
  ## Update the last style to current style (after applying changes)
  manager.state.lastStyle = manager.state.style
