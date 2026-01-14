## Async Terminal I/O interface
##
## This module provides asynchronous terminal control and rendering capabilities
## using either Chronos or std/asyncdispatch for non-blocking I/O operations.

import std/[termios, posix]

import async_backend, async_buffer
import ../core/[geometry, colors, buffer, terminal_common]

type
  AsyncTerminal* = ref object ## Async terminal interface for screen management
    size*: Size
    alternateScreen*: bool
    rawMode*: bool
    mouseEnabled*: bool
    bracketedPasteEnabled*: bool
    lastBuffer*: Buffer
    stdinFd*: AsyncFD
    stdoutFd*: AsyncFD
    originalTermios: Termios # Store original terminal settings per instance
    suspendState: SuspendState

  AsyncTerminalError* = object of CatchableError

proc getTerminalSizeAsync*(): Size =
  ## Get current terminal size
  return getTerminalSizeWithFallback(80, 24)

proc updateSize*(terminal: AsyncTerminal) =
  ## Update terminal size from current terminal
  terminal.size = getTerminalSizeAsync()

proc newAsyncTerminal*(): AsyncTerminal =
  ## Create a new AsyncTerminal instance
  result = AsyncTerminal(
    size: size(80, 24), # Default size
    alternateScreen: false,
    rawMode: false,
    mouseEnabled: false,
  )

  # Initialize async file descriptors
  result.stdinFd = STDIN_FILENO.AsyncFD
  result.stdoutFd = STDOUT_FILENO.AsyncFD

  # AsyncFD registration is handled automatically by Chronos
  # No manual registration needed

  updateSize(result)

  # Initialize lastBuffer to avoid initial full redraw
  result.lastBuffer = newBuffer(rect(0, 0, result.size.width, result.size.height))

proc enableRawMode*(terminal: AsyncTerminal) =
  ## Enable raw mode for direct key input
  if tcgetattr(STDIN_FILENO, addr terminal.originalTermios) == 0:
    var raw = terminal.originalTermios
    applyTerminalConfig(raw, getRawModeConfig())

    if tcsetattr(STDIN_FILENO, TCSAFLUSH, addr raw) == 0:
      terminal.rawMode = true

proc disableRawMode*(terminal: AsyncTerminal) =
  ## Disable raw mode
  if terminal.rawMode:
    discard tcsetattr(STDIN_FILENO, TCSAFLUSH, addr terminal.originalTermios)
  terminal.rawMode = false

# Alternate screen control
proc enableAlternateScreen*(terminal: AsyncTerminal) =
  ## Switch to alternate screen buffer
  enableAlternateScreenImpl(terminal)

proc disableAlternateScreen*(terminal: AsyncTerminal) =
  ## Switch back to main screen buffer
  disableAlternateScreenImpl(terminal)

# Mouse control
proc enableMouse*(terminal: AsyncTerminal) =
  ## Enable mouse reporting
  enableMouseImpl(terminal)

proc disableMouse*(terminal: AsyncTerminal) =
  ## Disable mouse reporting
  disableMouseImpl(terminal)

# Bracketed paste control
proc enableBracketedPaste*(terminal: AsyncTerminal) =
  ## Enable bracketed paste mode for paste detection
  enableBracketedPasteImpl(terminal)

proc disableBracketedPaste*(terminal: AsyncTerminal) =
  ## Disable bracketed paste mode
  disableBracketedPasteImpl(terminal)

# Async cursor control (using stdout for simplicity)
proc hideCursor*() {.async.} =
  ## Hide the cursor asynchronously
  stdout.write(HideCursorSeq)
  stdout.flushFile()

proc showCursor*() {.async.} =
  ## Show the cursor asynchronously
  stdout.write(ShowCursorSeq)
  stdout.flushFile()

proc setCursorPosition*(x, y: int) {.async.} =
  ## Set cursor position asynchronously (1-based coordinates)
  stdout.write(makeCursorPositionSeq(x, y))
  stdout.flushFile()

proc setCursorPosition*(pos: Position) {.async.} =
  ## Set cursor position asynchronously
  stdout.write(makeCursorPositionSeq(pos))
  stdout.flushFile()

proc showCursorAt*(x, y: int) {.async.} =
  ## Set cursor position and show it asynchronously
  stdout.write(makeCursorPositionSeq(x, y))
  stdout.write(ShowCursorSeq)
  stdout.flushFile()

proc showCursorAt*(pos: Position) {.async.} =
  ## Set cursor position and show it asynchronously
  stdout.write(makeCursorPositionSeq(pos))
  stdout.write(ShowCursorSeq)
  stdout.flushFile()

# Async screen control
proc clearScreen*() {.async.} =
  ## Clear the entire screen asynchronously
  stdout.write(ClearScreenSeq)
  stdout.flushFile()

proc clearLine*() {.async.} =
  ## Clear the current line asynchronously
  stdout.write(ClearLineSeq)
  stdout.flushFile()

# Async buffer rendering
proc renderCell*(cell: Cell, x, y: int) {.async.} =
  ## Render a single cell at the specified position asynchronously
  await setCursorPosition(x, y)

  let styleSeq = cell.style.toAnsiSequence()
  var output = ""

  if styleSeq.len > 0:
    output.add(styleSeq)

  output.add(cell.symbol)

  if styleSeq.len > 0:
    output.add(resetSequence())

  stdout.write(output)
  stdout.flushFile()

proc renderAsync*(terminal: AsyncTerminal, buffer: Buffer) {.async.} =
  ## Render a buffer to the terminal asynchronously using differential updates
  let output = buildDifferentialOutput(terminal.lastBuffer, buffer)

  if output.len > 0:
    stdout.write(output)
    stdout.flushFile()

  # Update last buffer and clear dirty region for next frame
  terminal.lastBuffer = buffer
  terminal.lastBuffer.clearDirty()

proc renderFullAsync*(terminal: AsyncTerminal, buffer: Buffer) {.async.} =
  ## Force a full async render of the buffer
  let output = buildFullRenderOutput(buffer)

  stdout.write(output)
  stdout.flushFile()

  # Update last buffer and clear dirty region
  terminal.lastBuffer = buffer
  terminal.lastBuffer.clearDirty()

# Terminal setup and cleanup
proc setupAsync*(terminal: AsyncTerminal) {.async.} =
  ## Setup terminal for CLI mode asynchronously
  terminal.enableAlternateScreen()
  terminal.enableRawMode()
  await hideCursor()
  await clearScreen()
  terminal.updateSize()

proc setupWithMouseAsync*(terminal: AsyncTerminal) {.async.} =
  ## Setup terminal for CLI mode with mouse support asynchronously
  await terminal.setupAsync()
  terminal.enableMouse()

proc setupWithPasteAsync*(terminal: AsyncTerminal) {.async.} =
  ## Setup terminal for CLI mode with bracketed paste support asynchronously
  await terminal.setupAsync()
  terminal.enableBracketedPaste()

proc setupWithMouseAndPasteAsync*(terminal: AsyncTerminal) {.async.} =
  ## Setup terminal for CLI mode with mouse and bracketed paste support asynchronously
  await terminal.setupAsync()
  terminal.enableMouse()
  terminal.enableBracketedPaste()

proc cleanupAsync*(terminal: AsyncTerminal) {.async.} =
  ## Cleanup and restore terminal asynchronously
  await showCursor()
  terminal.disableBracketedPaste()
  terminal.disableMouse()
  terminal.disableRawMode()
  terminal.disableAlternateScreen()

  # AsyncFD cleanup is handled automatically by Chronos
  # No manual unregistration needed

proc isSuspended*(terminal: AsyncTerminal): bool =
  ## Check if terminal is currently suspended
  terminal.suspendState.isSuspended

proc suspendAsync*(terminal: AsyncTerminal) {.async.} =
  ## Suspend terminal to return to shell mode temporarily
  ##
  ## Saves current terminal state and restores normal shell mode.
  ## Use `resumeAsync()` to return to program mode.
  ##
  ## Example:
  ## ```nim
  ## await terminal.suspendAsync()
  ## discard execShellCmd("ls ./")
  ## await terminal.resumeAsync()
  ## ```
  if terminal.isSuspended:
    return # Already suspended

  # Save current state
  saveSuspendState(terminal)

  # Return to shell mode
  await showCursor()
  terminal.disableBracketedPaste()
  terminal.disableMouse()
  terminal.disableRawMode()
  terminal.disableAlternateScreen()

  terminal.suspendState.isSuspended = true

proc resumeAsync*(terminal: AsyncTerminal) {.async.} =
  ## Resume terminal after suspend, restoring program mode
  ##
  ## Restores terminal state that was saved by `suspendAsync()`.
  ## After resume, call `drawAsync(buffer, force = true)` to redraw the screen.
  if not terminal.isSuspended:
    return # Not suspended

  # Restore saved state
  restoreSuspendedFeatures(terminal)
  await hideCursor()

  # Clear lastBuffer to force full redraw on next drawAsync()
  clearLastBufferForResume(terminal)

# High-level async rendering interface
proc drawAsync*(
    terminal: AsyncTerminal, buffer: Buffer, force: bool = false
) {.async.} =
  ## Draw a buffer to the terminal asynchronously
  if force or terminal.lastBuffer.area.isEmpty:
    await terminal.renderFullAsync(buffer)
  else:
    await terminal.renderAsync(buffer)

proc drawAsync*(
    terminal: AsyncTerminal, asyncBuffer: async_buffer.AsyncBuffer, force: bool = false
) {.async.} =
  ## Draw an AsyncBuffer to the terminal asynchronously
  let buffer = asyncBuffer.toBufferAsync()
  await terminal.drawAsync(buffer, force)

# Terminal state queries
# Note: getSize and getArea need explicit proc definitions to avoid conflicts
# with async_buffer.getSize in async_app.nim.

proc getSize*(terminal: AsyncTerminal): Size =
  ## Get current terminal size
  terminal.size

proc getArea*(terminal: AsyncTerminal): Rect =
  ## Get terminal area as a Rect
  rect(0, 0, terminal.size.width, terminal.size.height)

# Async utility templates
template withAsyncTerminal*(terminal: AsyncTerminal, body: untyped): untyped =
  ## Template for convenient async terminal usage with automatic cleanup
  await terminal.setupAsync()
  try:
    body
  finally:
    await terminal.cleanupAsync()
