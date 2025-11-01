## Renderer Module
## ===============
##
## Handles all rendering operations including buffer management,
## differential rendering, and terminal output coordination.

import terminal, buffer, cursor, terminal_common, geometry, colors

type Renderer* = ref object ## Manages rendering operations and buffer management
  terminal: Terminal
  buffer: Buffer
  cursorManager: CursorManager
  lastRenderTime: float

proc newRenderer*(terminal: Terminal): Renderer =
  ## Create a new renderer with the given terminal
  let termSize = terminal.getSize()
  result = Renderer(
    terminal: terminal,
    buffer: newBuffer(termSize.width, termSize.height),
    cursorManager: newCursorManager(),
    lastRenderTime: 0.0,
  )

proc getBuffer*(renderer: Renderer): var Buffer =
  ## Get mutable reference to the internal buffer
  renderer.buffer

proc getCursorManager*(renderer: Renderer): CursorManager =
  ## Get the cursor manager
  renderer.cursorManager

proc resize*(renderer: Renderer, width, height: int) =
  ## Resize the internal buffer
  let newArea = Rect(x: 0, y: 0, width: width, height: height)
  renderer.buffer.resize(newArea)

proc resize*(renderer: Renderer) =
  ## Resize based on current terminal size
  let size = renderer.terminal.getSize()
  renderer.resize(size.width, size.height)

proc clear*(renderer: Renderer) =
  ## Clear the buffer
  renderer.buffer.clear()

proc render*(renderer: Renderer, force: bool = false) =
  ## Render the buffer to terminal with cursor support
  var cursorState = renderer.cursorManager.getState()

  renderer.terminal.drawWithCursor(
    renderer.buffer,
    cursorState.x,
    cursorState.y,
    cursorState.visible,
    cursorState.style,
    cursorState.lastStyle,
    force = force,
  )

  # Update cursor manager after render
  renderer.cursorManager.updateLastStyle()

proc renderDiff*(renderer: Renderer) =
  ## Render only the differences from last frame
  renderer.render(force = false)

proc forceRender*(renderer: Renderer) =
  ## Force full screen redraw
  renderer.render(force = true)

# Cursor control delegation
proc setCursorPosition*(renderer: Renderer, x, y: int) =
  ## Set cursor position without changing visibility
  renderer.cursorManager.setPosition(x, y)

proc setCursorPosition*(renderer: Renderer, pos: Position) =
  ## Set cursor position using Position type without changing visibility
  renderer.cursorManager.setPosition(pos.x, pos.y)

proc showCursorAt*(renderer: Renderer, x, y: int) =
  ## Set cursor position and make it visible
  renderer.cursorManager.showAt(x, y)

proc showCursorAt*(renderer: Renderer, pos: Position) =
  ## Set cursor position using Position type and make it visible
  renderer.cursorManager.showAt(pos.x, pos.y)

proc showCursor*(renderer: Renderer) =
  ## Show cursor at current position
  renderer.cursorManager.show()

proc hideCursor*(renderer: Renderer) =
  ## Hide cursor
  renderer.cursorManager.hide()

proc setCursorStyle*(renderer: Renderer, style: CursorStyle) =
  ## Set cursor style
  renderer.cursorManager.setStyle(style)

proc getCursorPosition*(renderer: Renderer): (int, int) =
  ## Get current cursor position
  renderer.cursorManager.getPosition()

proc isCursorVisible*(renderer: Renderer): bool =
  ## Check if cursor is visible
  renderer.cursorManager.isVisible()

# Direct buffer operations
proc setString*(renderer: Renderer, x, y: int, text: string, style: Style) =
  ## Set string directly in buffer
  renderer.buffer.setString(x, y, text, style)
