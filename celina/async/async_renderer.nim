## Async Renderer Module
## =====================
##
## Handles all async rendering operations including buffer management,
## differential rendering, and terminal output coordination.
## This mirrors the sync Renderer but uses AsyncTerminal.

import async_backend, async_terminal
import ../core/[buffer, cursor, terminal_common, geometry, colors]

type AsyncRenderer* = ref object
  ## Manages async rendering operations and buffer management
  terminal: AsyncTerminal
  buffer: Buffer
  cursorManager: CursorManager
  lastRenderTime: float

proc newAsyncRenderer*(terminal: AsyncTerminal): AsyncRenderer =
  ## Create a new async renderer with the given terminal
  let termSize = terminal.getSize()
  result = AsyncRenderer(
    terminal: terminal,
    buffer: newBuffer(termSize.width, termSize.height),
    cursorManager: newCursorManager(),
    lastRenderTime: 0.0,
  )

proc getBuffer*(renderer: AsyncRenderer): var Buffer =
  ## Get mutable reference to the internal buffer
  renderer.buffer

proc getCursorManager*(renderer: AsyncRenderer): CursorManager =
  ## Get the cursor manager
  renderer.cursorManager

proc resize*(renderer: AsyncRenderer, width, height: int) =
  ## Resize the internal buffer
  let newArea = Rect(x: 0, y: 0, width: width, height: height)
  renderer.buffer.resize(newArea)

proc resize*(renderer: AsyncRenderer) =
  ## Resize based on current terminal size
  let size = renderer.terminal.getSize()
  renderer.resize(size.width, size.height)

proc clear*(renderer: AsyncRenderer) =
  ## Clear the buffer
  renderer.buffer.clear()

proc renderAsync*(renderer: AsyncRenderer, force: bool = false) {.async.} =
  ## Render the buffer to terminal with cursor support
  let cursorState = renderer.cursorManager.getState()

  let newLastStyle = await renderer.terminal.drawWithCursorAsync(
    renderer.buffer,
    cursorState.x,
    cursorState.y,
    cursorState.visible,
    cursorState.style,
    cursorState.lastStyle,
    force = force,
  )

  # Update cursor manager with the new last style from render
  renderer.cursorManager.setLastStyle(newLastStyle)

proc renderDiffAsync*(renderer: AsyncRenderer) {.async.} =
  ## Render only the differences from last frame
  await renderer.renderAsync(force = false)

proc forceRenderAsync*(renderer: AsyncRenderer) {.async.} =
  ## Force full screen redraw
  await renderer.renderAsync(force = true)

# Cursor control delegation
proc setCursorPosition*(renderer: AsyncRenderer, x, y: int) =
  ## Set cursor position without changing visibility
  renderer.cursorManager.setPosition(x, y)

proc setCursorPosition*(renderer: AsyncRenderer, pos: Position) =
  ## Set cursor position using Position type without changing visibility
  renderer.cursorManager.setPosition(pos.x, pos.y)

proc showCursorAt*(renderer: AsyncRenderer, x, y: int) =
  ## Set cursor position and make it visible
  renderer.cursorManager.showAt(x, y)

proc showCursorAt*(renderer: AsyncRenderer, pos: Position) =
  ## Set cursor position using Position type and make it visible
  renderer.cursorManager.showAt(pos.x, pos.y)

proc showCursor*(renderer: AsyncRenderer) =
  ## Show cursor at current position
  renderer.cursorManager.show()

proc hideCursor*(renderer: AsyncRenderer) =
  ## Hide cursor
  renderer.cursorManager.hide()

proc setCursorStyle*(renderer: AsyncRenderer, style: CursorStyle) =
  ## Set cursor style
  renderer.cursorManager.setStyle(style)

proc getCursorPosition*(renderer: AsyncRenderer): (int, int) =
  ## Get current cursor position
  renderer.cursorManager.getPosition()

proc isCursorVisible*(renderer: AsyncRenderer): bool =
  ## Check if cursor is visible
  renderer.cursorManager.isVisible()

# Direct buffer operations
proc setString*(
    renderer: AsyncRenderer,
    x, y: int,
    text: string,
    style: Style,
    hyperlink: string = "",
) =
  ## Set string directly in buffer
  ## If hyperlink is provided, the text becomes a clickable link (OSC 8)
  renderer.buffer.setString(x, y, text, style, hyperlink)
