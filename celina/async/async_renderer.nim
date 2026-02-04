## Async Renderer Module
## =====================
##
## Handles all async rendering operations including buffer management,
## differential rendering, and terminal output coordination.
## This mirrors the sync Renderer but uses AsyncTerminal and AsyncBuffer.

import async_backend, async_terminal, async_buffer
import ../core/[buffer, cursor, terminal_common, geometry, colors]

when hasChronos:
  # Name collision avoidance
  type AsyncBuffer = async_buffer.AsyncBuffer

type AsyncRenderer* = ref object
  ## Manages async rendering operations and buffer management
  terminal: AsyncTerminal
  asyncBuffer: AsyncBuffer
  cursorManager: CursorManager
  lastRenderTime: float

proc newAsyncRenderer*(terminal: AsyncTerminal): AsyncRenderer =
  ## Create a new async renderer with the given terminal
  let termSize = terminal.getSize()
  result = AsyncRenderer(
    terminal: terminal,
    asyncBuffer: newAsyncBufferNoRM(termSize.width, termSize.height),
    cursorManager: newCursorManager(),
    lastRenderTime: 0.0,
  )

proc getAsyncBuffer*(renderer: AsyncRenderer): AsyncBuffer {.inline.} =
  ## Get the internal async buffer for thread-safe operations
  renderer.asyncBuffer

proc getBuffer*(renderer: AsyncRenderer): var Buffer =
  ## Get mutable reference to the internal buffer for synchronous operations
  ## Note: This provides direct access to the underlying buffer and should be used
  ## carefully in async contexts. For thread-safe access, use getAsyncBuffer().
  renderer.asyncBuffer.withBufferAsync:
    return buffer

proc getCursorManager*(renderer: AsyncRenderer): CursorManager {.inline.} =
  ## Get the cursor manager
  renderer.cursorManager

proc resize*(renderer: AsyncRenderer, width, height: int) =
  ## Resize the internal buffer
  let newArea = Rect(x: 0, y: 0, width: width, height: height)
  renderer.asyncBuffer.withBufferAsync:
    buffer.resize(newArea)

proc resize*(renderer: AsyncRenderer) =
  ## Resize based on current terminal size
  let size = renderer.terminal.getSize()
  renderer.resize(size.width, size.height)

proc clear*(renderer: AsyncRenderer) {.inline.} =
  ## Clear the buffer
  renderer.asyncBuffer.clear()

proc renderAsync*(renderer: AsyncRenderer, force: bool = false) {.async.} =
  ## Render the buffer to terminal with cursor support
  let cursorState = renderer.cursorManager.getState()

  # Get buffer snapshot for rendering (thread-safe)
  let bufferSnapshot = renderer.asyncBuffer.toBufferAsync()

  let newLastStyle = await renderer.terminal.drawWithCursorAsync(
    bufferSnapshot,
    cursorState.x,
    cursorState.y,
    cursorState.visible,
    cursorState.style,
    cursorState.lastStyle,
    force = force,
  )

  # Clear dirty region after successful render
  renderer.asyncBuffer.withBufferAsync:
    buffer.clearDirty()

  # Update cursor manager with the new last style from render
  renderer.cursorManager.setLastStyle(newLastStyle)

proc renderDiffAsync*(renderer: AsyncRenderer) {.async.} =
  ## Render only the differences from last frame
  await renderer.renderAsync(force = false)

proc forceRenderAsync*(renderer: AsyncRenderer) {.async.} =
  ## Force full screen redraw
  await renderer.renderAsync(force = true)

# Cursor control delegation
proc setCursorPosition*(renderer: AsyncRenderer, x, y: int) {.inline.} =
  ## Set cursor position without changing visibility
  renderer.cursorManager.setPosition(x, y)

proc setCursorPosition*(renderer: AsyncRenderer, pos: Position) {.inline.} =
  ## Set cursor position using Position type without changing visibility
  renderer.cursorManager.setPosition(pos.x, pos.y)

proc showCursorAt*(renderer: AsyncRenderer, x, y: int) {.inline.} =
  ## Set cursor position and make it visible
  renderer.cursorManager.showAt(x, y)

proc showCursorAt*(renderer: AsyncRenderer, pos: Position) {.inline.} =
  ## Set cursor position using Position type and make it visible
  renderer.cursorManager.showAt(pos.x, pos.y)

proc showCursor*(renderer: AsyncRenderer) {.inline.} =
  ## Show cursor at current position
  renderer.cursorManager.show()

proc hideCursor*(renderer: AsyncRenderer) {.inline.} =
  ## Hide cursor
  renderer.cursorManager.hide()

proc setCursorStyle*(renderer: AsyncRenderer, style: CursorStyle) {.inline.} =
  ## Set cursor style
  renderer.cursorManager.setStyle(style)

proc getCursorPosition*(renderer: AsyncRenderer): (int, int) {.inline.} =
  ## Get current cursor position
  renderer.cursorManager.getPosition()

proc isCursorVisible*(renderer: AsyncRenderer): bool {.inline.} =
  ## Check if cursor is visible
  renderer.cursorManager.isVisible()

# Direct buffer operations
proc setString*(
    renderer: AsyncRenderer,
    x, y: int,
    text: string,
    style: Style,
    hyperlink: string = "",
) {.inline.} =
  ## Set string directly in buffer (thread-safe)
  ## If hyperlink is provided, the text becomes a clickable link (OSC 8)
  renderer.asyncBuffer.setString(x, y, text, style, hyperlink)

proc setStringAsync*(
    renderer: AsyncRenderer,
    x, y: int,
    text: string,
    style: Style = defaultStyle(),
    hyperlink: string = "",
) {.async.} =
  ## Set string directly in buffer asynchronously
  ## If hyperlink is provided, the text becomes a clickable link (OSC 8)
  await renderer.asyncBuffer.setStringAsync(x, y, text, style, hyperlink)
