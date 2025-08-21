## Async Terminal I/O interface
##
## This module provides asynchronous terminal control and rendering capabilities
## using Chronos async framework for non-blocking I/O operations.

import std/[strformat, termios, posix]

import pkg/chronos

import async_buffer
import ../core/[geometry, colors, buffer]

type
  AsyncTerminal* = ref object ## Async terminal interface for screen management
    size*: Size
    alternateScreen*: bool
    rawMode*: bool
    mouseEnabled*: bool
    lastBuffer*: Buffer
    stdinFd*: AsyncFD
    stdoutFd*: AsyncFD

  AsyncTerminalError* = object of CatchableError

# Raw mode control (for key input)
var originalTermios: Termios

proc getTerminalSizeAsync*(): Size =
  ## Get current terminal size
  var w: IOctl_WinSize
  if ioctl(STDOUT_FILENO, TIOCGWINSZ, addr w) == 0:
    return size(w.ws_col.int, w.ws_row.int)
  else:
    return size(80, 24) # Fallback

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
  if tcgetattr(STDIN_FILENO, addr originalTermios) == 0:
    var raw = originalTermios
    raw.c_lflag = raw.c_lflag and not (ECHO or ICANON or ISIG or IEXTEN)
    raw.c_iflag = raw.c_iflag and not (IXON or ICRNL or BRKINT or INPCK or ISTRIP)
    raw.c_cflag = raw.c_cflag or CS8
    raw.c_oflag = raw.c_oflag and not OPOST
    raw.c_cc[VMIN] = 1.char
    raw.c_cc[VTIME] = 0.char

    if tcsetattr(STDIN_FILENO, TCSAFLUSH, addr raw) == 0:
      terminal.rawMode = true

proc disableRawMode*(terminal: AsyncTerminal) =
  ## Disable raw mode
  if terminal.rawMode:
    discard tcsetattr(STDIN_FILENO, TCSAFLUSH, addr originalTermios)
  terminal.rawMode = false

# Alternate screen control
proc enableAlternateScreen*(terminal: AsyncTerminal) =
  ## Switch to alternate screen buffer
  if not terminal.alternateScreen:
    stdout.write("\e[?1049h") # Enable alternate screen
    stdout.flushFile()
    terminal.alternateScreen = true

proc disableAlternateScreen*(terminal: AsyncTerminal) =
  ## Switch back to main screen buffer
  if terminal.alternateScreen:
    stdout.write("\e[?1049l") # Disable alternate screen
    stdout.flushFile()
    terminal.alternateScreen = false

# Mouse control
proc enableMouse*(terminal: AsyncTerminal) =
  ## Enable mouse reporting
  if not terminal.mouseEnabled:
    # Enable mouse event sequences
    stdout.write("\e[?9h") # X10 mouse reporting
    stdout.write("\e[?1000h") # Mouse button tracking
    stdout.write("\e[?1002h") # Mouse motion tracking
    stdout.write("\e[?1003h") # All mouse events
    stdout.write("\e[?1006h") # SGR extended mouse mode
    stdout.flushFile()
    terminal.mouseEnabled = true

proc disableMouse*(terminal: AsyncTerminal) =
  ## Disable mouse reporting
  if terminal.mouseEnabled:
    # Disable all mouse modes in reverse order
    stdout.write("\e[?1006l")
    stdout.write("\e[?1003l")
    stdout.write("\e[?1002l")
    stdout.write("\e[?1000l")
    stdout.write("\e[?9l")
    stdout.flushFile()
    terminal.mouseEnabled = false

# Async cursor control (using stdout for simplicity)
proc hideCursor*() {.async.} =
  ## Hide the cursor asynchronously
  stdout.write("\e[?25l")
  stdout.flushFile()

proc showCursor*() {.async.} =
  ## Show the cursor asynchronously
  stdout.write("\e[?25h")
  stdout.flushFile()

proc setCursorPos*(x, y: int) {.async.} =
  ## Set cursor position asynchronously (1-based coordinates)
  stdout.write(&"\e[{y + 1};{x + 1}H")
  stdout.flushFile()

proc setCursorPos*(pos: Position) {.async.} =
  ## Set cursor position asynchronously
  await setCursorPos(pos.x, pos.y)

# Async screen control
proc clearScreen*() {.async.} =
  ## Clear the entire screen asynchronously
  stdout.write("\e[2J")
  stdout.flushFile()

proc clearLine*() {.async.} =
  ## Clear the current line asynchronously
  stdout.write("\e[2K")
  stdout.flushFile()

# Async buffer rendering
proc renderCell*(cell: Cell, x, y: int) {.async.} =
  ## Render a single cell at the specified position asynchronously
  await setCursorPos(x, y)

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
  if terminal.lastBuffer.area != buffer.area:
    # Size changed, full redraw needed
    await clearScreen()
    terminal.lastBuffer = newBuffer(buffer.area)

  # Calculate differences and render only changed cells
  let changes = terminal.lastBuffer.diff(buffer)

  if changes.len > 0:
    # Batch render changes efficiently
    var output = ""

    for change in changes:
      let absolutePos = pos(buffer.area.x + change.pos.x, buffer.area.y + change.pos.y)

      # Add cursor position
      output.add(&"\e[{absolutePos.y + 1};{absolutePos.x + 1}H")

      # Add style if needed
      let styleSeq = change.cell.style.toAnsiSequence()
      if styleSeq.len > 0:
        output.add(styleSeq)

      # Add the character
      output.add(change.cell.symbol)

      # Reset style if needed
      if styleSeq.len > 0:
        output.add(resetSequence())

    # Write everything at once
    stdout.write(output)
    stdout.flushFile()

  # Update last buffer
  terminal.lastBuffer = buffer

proc renderFullAsync*(terminal: AsyncTerminal, buffer: Buffer) {.async.} =
  ## Force a full async render of the buffer
  await clearScreen()

  for y in 0 ..< buffer.area.height:
    for x in 0 ..< buffer.area.width:
      let cell = buffer[x, y]
      if not cell.isEmpty or cell.style != defaultStyle():
        await renderCell(cell, buffer.area.x + x, buffer.area.y + y)

  terminal.lastBuffer = buffer

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

proc cleanupAsync*(terminal: AsyncTerminal) {.async.} =
  ## Cleanup and restore terminal asynchronously
  await showCursor()
  terminal.disableMouse()
  terminal.disableRawMode()
  terminal.disableAlternateScreen()

  # AsyncFD cleanup is handled automatically by Chronos
  # No manual unregistration needed

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
  let buffer = asyncBuffer.toBuffer()
  await terminal.drawAsync(buffer, force)

# Terminal state queries
proc isRawMode*(terminal: AsyncTerminal): bool =
  ## Check if terminal is in raw mode
  terminal.rawMode

proc isAlternateScreen*(terminal: AsyncTerminal): bool =
  ## Check if alternate screen is active
  terminal.alternateScreen

proc isMouseEnabled*(terminal: AsyncTerminal): bool =
  ## Check if mouse reporting is enabled
  terminal.mouseEnabled

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
