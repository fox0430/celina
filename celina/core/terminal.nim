## Terminal interface
##
## This module provides terminal control and rendering capabilities
## using ANSI escape sequences for POSIX systems (Linux, macOS, etc.).

import std/[strformat, termios, posix]
import geometry, colors, buffer, errors

export errors.TerminalError

type Terminal* = ref object ## Terminal interface for screen management
  size*: Size
  alternateScreen*: bool
  rawMode*: bool
  mouseEnabled*: bool
  lastBuffer*: Buffer
  rawModeEnabled: bool # Track raw mode state internally

# Raw mode control (for key input)
var originalTermios: Termios

proc getTerminalSize*(): Size =
  ## Get current terminal size with error handling
  ## Raises TerminalError if unable to get size from system
  var w: IOctl_WinSize
  discard checkSystemCall(
    ioctl(STDOUT_FILENO, TIOCGWINSZ, addr w), "Failed to get terminal size"
  )
  return size(w.ws_col.int, w.ws_row.int)

proc getTerminalSizeOrDefault*(): Size =
  ## Get terminal size with fallback to default 80x24
  ## Never raises an exception
  try:
    return getTerminalSize()
  except CatchableError:
    return size(80, 24) # Fallback size

proc updateSize*(terminal: Terminal) =
  ## Update terminal size from current terminal
  ## Raises TerminalError if unable to get size
  try:
    terminal.size = getTerminalSize()
  except CatchableError as e:
    raise newTerminalError("Failed to update terminal size", inner = e)

# Terminal creation and cleanup
proc newTerminal*(): Terminal =
  ## Create a new Terminal instance
  ## Uses default size if unable to get actual terminal size
  result = Terminal(
    size: size(80, 24), # Default size
    alternateScreen: false,
    rawMode: false,
    mouseEnabled: false,
    rawModeEnabled: false,
  )
  # Try to get actual size, but don't fail if we can't
  result.size = getTerminalSizeOrDefault()

proc enableRawMode*(terminal: Terminal) =
  ## Enable raw mode for direct key input
  ## Raises TerminalError if unable to configure terminal
  if terminal.rawModeEnabled:
    return # Already enabled

  try:
    checkSystemCallVoid(
      tcgetattr(STDIN_FILENO, addr originalTermios), "Failed to get terminal attributes"
    )

    var raw = originalTermios
    raw.c_lflag = raw.c_lflag and not (ECHO or ICANON or ISIG or IEXTEN)
    raw.c_iflag = raw.c_iflag and not (IXON or ICRNL or BRKINT or INPCK or ISTRIP)
    raw.c_cflag = raw.c_cflag or CS8
    raw.c_oflag = raw.c_oflag and not OPOST
    raw.c_cc[VMIN] = 1.char
    raw.c_cc[VTIME] = 0.char

    checkSystemCallVoid(
      tcsetattr(STDIN_FILENO, TCSAFLUSH, addr raw), "Failed to set raw mode"
    )
    terminal.rawMode = true
    terminal.rawModeEnabled = true
  except CatchableError as e:
    raise newTerminalError("Failed to enable raw mode", inner = e)

proc disableRawMode*(terminal: Terminal) =
  ## Disable raw mode, restoring original terminal settings
  ## Best effort - doesn't raise on error to ensure cleanup
  if not terminal.rawModeEnabled:
    return # Not enabled

  # Best effort restoration - log but don't raise
  if tcsetattr(STDIN_FILENO, TCSAFLUSH, addr originalTermios) == -1:
    when defined(celinaDebug):
      stderr.writeLine("Warning: Failed to restore terminal settings")
  terminal.rawMode = false
  terminal.rawModeEnabled = false

# Alternate screen control
proc enableAlternateScreen*(terminal: Terminal) =
  ## Switch to alternate screen buffer
  ## Raises IOError if unable to write to terminal
  if not terminal.alternateScreen:
    tryIO:
      stdout.write("\e[?1049h") # Enable alternate screen
      stdout.flushFile()
    terminal.alternateScreen = true

proc disableAlternateScreen*(terminal: Terminal) =
  ## Switch back to main screen buffer
  ## Best effort - doesn't raise on error to ensure cleanup
  if terminal.alternateScreen:
    try:
      stdout.write("\e[?1049l") # Disable alternate screen
      stdout.flushFile()
    except CatchableError:
      when defined(celinaDebug):
        stderr.writeLine("Warning: Failed to disable alternate screen")
    terminal.alternateScreen = false

# Mouse control
proc enableMouse*(terminal: Terminal) =
  ## Enable mouse reporting
  if not terminal.mouseEnabled:
    # Enable X10 mouse reporting
    stdout.write("\e[?9h")
    # Enable mouse button tracking
    stdout.write("\e[?1000h")
    # Enable mouse motion tracking
    stdout.write("\e[?1002h")
    # Enable all mouse events including focus
    stdout.write("\e[?1003h")
    # Enable SGR extended mouse mode
    stdout.write("\e[?1006h")
    stdout.flushFile()
    terminal.mouseEnabled = true

proc disableMouse*(terminal: Terminal) =
  ## Disable mouse reporting
  if terminal.mouseEnabled:
    # Disable all mouse modes in reverse order
    stdout.write("\e[?1006l") # Disable SGR extended mode
    stdout.write("\e[?1003l") # Disable all mouse events
    stdout.write("\e[?1002l") # Disable mouse motion tracking
    stdout.write("\e[?1000l") # Disable mouse button tracking
    stdout.write("\e[?9l") # Disable X10 mouse reporting
    stdout.flushFile()
    terminal.mouseEnabled = false

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
  ## Raises IOError if unable to write to terminal
  tryIO:
    stdout.write("\e[2J")
    stdout.flushFile()

proc clearLine*() =
  ## Clear the current line
  ## Raises IOError if unable to write to terminal
  tryIO:
    stdout.write("\e[2K")
    stdout.flushFile()

proc clearToEndOfLine*() =
  ## Clear from cursor to end of line
  ## Raises IOError if unable to write to terminal
  tryIO:
    stdout.write("\e[0K")
    stdout.flushFile()

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
  except CelinaIOError as e:
    raise newTerminalError("Failed to render buffer", inner = e)
  except CatchableError as e:
    raise newTerminalError("Rendering error", inner = e)

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
  except CelinaIOError as e:
    raise newTerminalError("Failed to render full buffer", inner = e)
  except CatchableError as e:
    raise newTerminalError("Full rendering error", inner = e)

# Terminal setup and cleanup
proc setup*(terminal: Terminal) =
  ## Setup terminal for CLI mode
  terminal.enableAlternateScreen()
  terminal.enableRawMode()
  hideCursor()
  clearScreen()
  terminal.updateSize()

proc setupWithMouse*(terminal: Terminal) =
  ## Setup terminal for CLI mode with mouse support
  ## Raises TerminalError if setup fails
  try:
    terminal.setup()
    terminal.enableMouse()
  except CatchableError as e:
    raise newTerminalError("Failed to setup terminal with mouse", inner = e)

proc cleanup*(terminal: Terminal) =
  ## Cleanup terminal, restoring original settings
  ## Best effort - tries to restore everything even if some operations fail
  try:
    showCursor()
  except CatchableError:
    discard

  terminal.disableMouse()
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
  except CatchableError as e:
    raise newTerminalError("Draw operation failed", inner = e)

# Terminal state queries
proc isRawMode*(terminal: Terminal): bool =
  ## Check if terminal is in raw mode
  terminal.rawMode

proc isAlternateScreen*(terminal: Terminal): bool =
  ## Check if alternate screen is active
  terminal.alternateScreen

proc isMouseEnabled*(terminal: Terminal): bool =
  ## Check if mouse reporting is enabled
  terminal.mouseEnabled

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
  ## Ensures cleanup even if setup or body fails
  try:
    terminal.setup()
    try:
      body
    finally:
      terminal.cleanup()
  except CatchableError as e:
    raise newTerminalError("withTerminal operation failed", inner = e)
