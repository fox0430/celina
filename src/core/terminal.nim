## Terminal interface for Celina TUI library
##
## This module provides terminal control and rendering capabilities
## using ANSI escape sequences for POSIX systems (Linux, macOS, etc.).

import std/[strformat, termios, posix]
import geometry, colors, buffer

type
  Terminal* = ref object ## Terminal interface for screen management
    size*: Size
    alternateScreen*: bool
    rawMode*: bool
    lastBuffer*: Buffer

  TerminalError* = object of CatchableError

# Raw mode control (for key input)
var originalTermios: Termios

proc getTerminalSize*(): Size =
  ## Get current terminal size
  var w: IOctl_WinSize
  if ioctl(STDOUT_FILENO, TIOCGWINSZ, addr w) == 0:
    return size(w.ws_col.int, w.ws_row.int)
  else:
    return size(80, 24) # Fallback

proc updateSize*(terminal: Terminal) =
  ## Update terminal size from current terminal
  terminal.size = getTerminalSize()

# Terminal creation and cleanup
proc newTerminal*(): Terminal =
  ## Create a new Terminal instance
  result = Terminal(
    size: size(80, 24), # Default size
    alternateScreen: false,
    rawMode: false,
  )
  result.updateSize()

proc enableRawMode*(terminal: Terminal) =
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

proc disableRawMode*(terminal: Terminal) =
  ## Disable raw mode
  if terminal.rawMode:
    discard tcsetattr(STDIN_FILENO, TCSAFLUSH, addr originalTermios)
  terminal.rawMode = false

# Alternate screen control
proc enableAlternateScreen*(terminal: Terminal) =
  ## Switch to alternate screen buffer
  if not terminal.alternateScreen:
    stdout.write("\e[?1049h") # Enable alternate screen
    stdout.flushFile()
    terminal.alternateScreen = true

proc disableAlternateScreen*(terminal: Terminal) =
  ## Switch back to main screen buffer
  if terminal.alternateScreen:
    stdout.write("\e[?1049l") # Disable alternate screen
    stdout.flushFile()
    terminal.alternateScreen = false

# Cursor control
proc hideCursor*() =
  ## Hide the cursor
  stdout.write("\e[?25l")

proc showCursor*() =
  ## Show the cursor
  stdout.write("\e[?25h")

proc setCursorPos*(x, y: int) =
  ## Set cursor position (1-based coordinates)
  stdout.write(&"\e[{y + 1};{x + 1}H")

proc setCursorPos*(pos: Position) =
  ## Set cursor position
  setCursorPos(pos.x, pos.y)

# Screen control
proc clearScreen*() =
  ## Clear the entire screen
  stdout.write("\e[2J")

proc clearLine*() =
  ## Clear the current line
  stdout.write("\e[2K")

proc clearToEndOfLine*() =
  ## Clear from cursor to end of line
  stdout.write("\e[0K")

proc clearToStartOfLine*() =
  ## Clear from start of line to cursor
  stdout.write("\e[1K")

# Buffer rendering
proc renderCell*(cell: Cell, x, y: int) =
  ## Render a single cell at the specified position
  setCursorPos(x, y)

  let styleSeq = cell.style.toAnsiSequence()
  if styleSeq.len > 0:
    stdout.write(styleSeq)

  stdout.write(cell.symbol)

  if styleSeq.len > 0:
    stdout.write(resetSequence())

proc render*(terminal: Terminal, buffer: Buffer) =
  ## Render a buffer to the terminal using differential updates
  try:
    if terminal.lastBuffer.area != buffer.area:
      # Size changed, full redraw needed
      clearScreen()
      terminal.lastBuffer = newBuffer(buffer.area)

    # Calculate differences and render only changed cells
    let changes = terminal.lastBuffer.diff(buffer)

    for change in changes:
      let absolutePos = pos(buffer.area.x + change.pos.x, buffer.area.y + change.pos.y)
      renderCell(change.cell, absolutePos.x, absolutePos.y)

    # Update last buffer
    terminal.lastBuffer = buffer
    stdout.flushFile()
  except IOError as e:
    raise newException(TerminalError, "Failed to render buffer: " & e.msg)
  except CatchableError as e:
    raise newException(TerminalError, "Rendering error: " & e.msg)

proc renderFull*(terminal: Terminal, buffer: Buffer) =
  ## Force a full render of the buffer (useful for initial draw)
  try:
    clearScreen()

    for y in 0 ..< buffer.area.height:
      for x in 0 ..< buffer.area.width:
        let cell = buffer[x, y]
        if not cell.isEmpty or cell.style != defaultStyle():
          renderCell(cell, buffer.area.x + x, buffer.area.y + y)

    terminal.lastBuffer = buffer
    stdout.flushFile()
  except IOError as e:
    raise newException(TerminalError, "Failed to render full buffer: " & e.msg)
  except CatchableError as e:
    raise newException(TerminalError, "Full rendering error: " & e.msg)

# Terminal setup and cleanup
proc setup*(terminal: Terminal) =
  ## Setup terminal for TUI mode
  terminal.enableAlternateScreen()
  terminal.enableRawMode()
  hideCursor()
  clearScreen()
  terminal.updateSize()

proc cleanup*(terminal: Terminal) =
  ## Cleanup and restore terminal
  showCursor()
  terminal.disableRawMode()
  terminal.disableAlternateScreen()

# High-level rendering interface
proc draw*(terminal: Terminal, buffer: Buffer, force: bool = false) =
  ## Draw a buffer to the terminal
  ## 
  ## Parameters:
  ## - buffer: The buffer to render to the terminal
  ## - force: If true, forces a full redraw regardless of changes
  ##
  ## Raises:
  ## - TerminalError: If rendering fails due to I/O errors or terminal issues
  try:
    if force or terminal.lastBuffer.area.isEmpty:
      terminal.renderFull(buffer)
    else:
      terminal.render(buffer)
  except TerminalError:
    # Re-raise terminal errors
    raise
  except CatchableError as e:
    raise newException(TerminalError, "Draw operation failed: " & e.msg)

# Terminal state queries
proc isRawMode*(terminal: Terminal): bool =
  ## Check if terminal is in raw mode
  terminal.rawMode

proc isAlternateScreen*(terminal: Terminal): bool =
  ## Check if alternate screen is active
  terminal.alternateScreen

proc getSize*(terminal: Terminal): Size =
  ## Get current terminal size
  terminal.size

proc getArea*(terminal: Terminal): Rect =
  ## Get terminal area as a Rect
  rect(0, 0, terminal.size.width, terminal.size.height)

# Utility procedures
proc withTerminal*[T](terminal: Terminal, body: proc(): T): T =
  ## Execute code with terminal setup/cleanup
  terminal.setup()
  try:
    result = body()
  finally:
    terminal.cleanup()

template withTerminal*(terminal: Terminal, body: untyped): untyped =
  ## Template version for convenient usage
  terminal.setup()
  try:
    body
  finally:
    terminal.cleanup()
