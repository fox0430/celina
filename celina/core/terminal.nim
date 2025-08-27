## Terminal interface
##
## This module provides terminal control and rendering capabilities
## using ANSI escape sequences for POSIX systems (Linux, macOS, etc.).

import std/[termios, posix]
import geometry, colors, buffer, errors, terminal_common

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
  let (width, height, success) = getTerminalSizeFromSystem()
  if not success:
    raise newTerminalError("Failed to get terminal size")
  return size(width, height)

proc getTerminalSizeOrDefault*(): Size =
  ## Get terminal size with fallback to default 80x24
  ## Never raises an exception
  return getTerminalSizeWithFallback(80, 24)

proc updateSize*(terminal: Terminal) =
  ## Update terminal size from current terminal
  ## Raises TerminalError if unable to get size
  try:
    terminal.size = getTerminalSize()
  except CatchableError as e:
    raise newTerminalError("Failed to update terminal size: " & e.msg)

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
    applyTerminalConfig(raw, getRawModeConfig())

    checkSystemCallVoid(
      tcsetattr(STDIN_FILENO, TCSAFLUSH, addr raw), "Failed to set raw mode"
    )
    terminal.rawMode = true
    terminal.rawModeEnabled = true
  except CatchableError as e:
    raise newTerminalError("Failed to enable raw mode: " & e.msg)

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
      stdout.write(AlternateScreenEnter)
      stdout.flushFile()
    terminal.alternateScreen = true

proc disableAlternateScreen*(terminal: Terminal) =
  ## Switch back to main screen buffer
  ## Best effort - doesn't raise on error to ensure cleanup
  if terminal.alternateScreen:
    try:
      stdout.write(AlternateScreenExit)
      stdout.flushFile()
    except CatchableError:
      when defined(celinaDebug):
        stderr.writeLine("Warning: Failed to disable alternate screen")
    terminal.alternateScreen = false

# Mouse control
proc enableMouse*(terminal: Terminal) =
  ## Enable mouse reporting
  if not terminal.mouseEnabled:
    stdout.write(enableMouseMode(MouseSGR))
    stdout.flushFile()
    terminal.mouseEnabled = true

proc disableMouse*(terminal: Terminal) =
  ## Disable mouse reporting
  if terminal.mouseEnabled:
    stdout.write(disableMouseMode(MouseSGR))
    stdout.flushFile()
    terminal.mouseEnabled = false

# Cursor control
proc hideCursor*() =
  ## Hide the cursor
  stdout.write(HideCursorSeq)

proc showCursor*() =
  ## Show the cursor
  stdout.write(ShowCursorSeq)

proc setCursorPos*(x, y: int) =
  ## Set cursor position (1-based coordinates)
  stdout.write(makeCursorPositionSeq(x, y))

proc setCursorPos*(pos: Position) =
  ## Set cursor position
  stdout.write(makeCursorPositionSeq(pos))

proc saveCursor*() =
  ## Save current cursor position
  stdout.write(SaveCursorSeq)

proc restoreCursor*() =
  ## Restore previously saved cursor position
  stdout.write(RestoreCursorSeq)

proc moveCursorUp*(steps: int = 1) =
  ## Move cursor up by specified steps
  stdout.write(makeCursorMoveSeq(CursorUpSeq, steps))

proc moveCursorDown*(steps: int = 1) =
  ## Move cursor down by specified steps
  stdout.write(makeCursorMoveSeq(CursorDownSeq, steps))

proc moveCursorLeft*(steps: int = 1) =
  ## Move cursor left by specified steps
  stdout.write(makeCursorMoveSeq(CursorLeftSeq, steps))

proc moveCursorRight*(steps: int = 1) =
  ## Move cursor right by specified steps
  stdout.write(makeCursorMoveSeq(CursorRightSeq, steps))

proc moveCursor*(dx, dy: int) =
  ## Move cursor relatively by dx, dy
  if dy < 0:
    moveCursorUp(-dy)
  elif dy > 0:
    moveCursorDown(dy)

  if dx < 0:
    moveCursorLeft(-dx)
  elif dx > 0:
    moveCursorRight(dx)

proc setCursorStyle*(style: CursorStyle) =
  ## Set cursor appearance style
  stdout.write(getCursorStyleSeq(style))

# Screen control
proc clearScreen*() =
  ## Clear the entire screen
  ## Raises IOError if unable to write to terminal
  tryIO:
    stdout.write(ClearScreenSeq)
    stdout.flushFile()

proc clearLine*() =
  ## Clear the current line
  ## Raises IOError if unable to write to terminal
  tryIO:
    stdout.write(ClearLineSeq)
    stdout.flushFile()

proc clearToEndOfLine*() =
  ## Clear from cursor to end of line
  ## Raises IOError if unable to write to terminal
  tryIO:
    stdout.write(ClearToEndOfLineSeq)
    stdout.flushFile()

proc clearToStartOfLine*() =
  ## Clear from start of line to cursor
  stdout.write(ClearToStartOfLineSeq)

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
    let output = buildDifferentialOutput(terminal.lastBuffer, buffer)

    if output.len > 0:
      stdout.write(output)
      stdout.flushFile()

    # Update last buffer
    terminal.lastBuffer = buffer
  except IOError as e:
    raise newTerminalError("Failed to render buffer: " & e.msg)
  except CatchableError as e:
    raise newTerminalError("Rendering error: " & e.msg)

proc renderFull*(terminal: Terminal, buffer: Buffer) =
  ## Force a full render of the buffer (useful for initial draw)
  try:
    let output = buildFullRenderOutput(buffer)
    stdout.write(output)
    stdout.flushFile()

    terminal.lastBuffer = buffer
  except IOError as e:
    raise newTerminalError("Failed to render full buffer: " & e.msg)
  except CatchableError as e:
    raise newTerminalError("Full rendering error: " & e.msg)

# Terminal setup and cleanup
proc setup*(terminal: Terminal) =
  ## Setup terminal for CLI mode
  terminal.enableAlternateScreen()
  terminal.enableRawMode()
  clearScreen()
  terminal.updateSize()

proc setupWithHiddenCursor*(terminal: Terminal) =
  ## Setup terminal for CLI mode with cursor hidden (backward compatibility)
  terminal.setup()
  hideCursor()

proc setupWithMouse*(terminal: Terminal) =
  ## Setup terminal for CLI mode with mouse support
  ## Raises TerminalError if setup fails
  try:
    terminal.setup()
    terminal.enableMouse()
  except CatchableError as e:
    raise newTerminalError("Failed to setup terminal with mouse: " & e.msg)

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
    raise newTerminalError("Draw operation failed: " & e.msg)

proc drawWithCursor*(
    terminal: Terminal,
    buffer: Buffer,
    cursorX, cursorY: int,
    cursorVisible: bool,
    cursorStyle: CursorStyle = CursorStyle.Default,
    lastCursorStyle: var CursorStyle,
    force: bool = false,
) =
  ## Draw buffer with cursor positioning in single write operation
  ## This prevents cursor flickering by including cursor commands in the same output
  try:
    let output = buildOutputWithCursor(
      terminal.lastBuffer, buffer, cursorX, cursorY, cursorVisible, cursorStyle,
      lastCursorStyle, force,
    )

    if output.len > 0:
      stdout.write(output)
      stdout.flushFile()

    terminal.lastBuffer = buffer
  except CatchableError as e:
    raise newTerminalError("Draw with cursor operation failed: " & e.msg)

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
    raise newTerminalError("withTerminal operation failed: " & e.msg)
