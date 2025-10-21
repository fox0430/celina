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

# Safe write helper that handles EAGAIN
proc writeWithRetry(data: string): bool =
  ## Write data with retry logic for EAGAIN/EINTR errors
  ## Returns true if successful, false if failed
  ## This is a low-level helper that handles transient I/O errors

  # Early return for empty data
  if data.len == 0:
    return true

  try:
    var
      written = 0
      retries = 0
    let dataLen = data.len
    const maxRetries = 3

    while written < dataLen:
      let
        fd = cint(stdout.getFileHandle())
        n = write(fd, unsafeAddr data[written], dataLen - written)

      if n == -1:
        let err = errno
        if err == EINTR:
          # Interrupted by signal, retry immediately
          continue
        elif err == EAGAIN or err == EWOULDBLOCK:
          # Resource temporarily unavailable, retry with backoff
          retries.inc
          if retries >= maxRetries:
            when defined(celinaDebug):
              stderr.writeLine(
                "Warning: writeWithRetry failed after max retries (EAGAIN)"
              )
            return false
          discard usleep(1000) # 1ms backoff
          continue
        else:
          # Other error, give up
          when defined(celinaDebug):
            stderr.writeLine("Warning: writeWithRetry failed with error: " & $err)
          return false
      elif n > 0:
        written += n
        retries = 0
      else:
        # Unexpected EOF, give up
        when defined(celinaDebug):
          stderr.writeLine("Warning: writeWithRetry encountered unexpected EOF")
        return false

    stdout.flushFile()
    return true
  except CatchableError as e:
    when defined(celinaDebug):
      stderr.writeLine("Warning: writeWithRetry exception: " & e.msg)
    else:
      discard e # Avoid "declared but not used" warning
    return false

proc tryWrite(data: string) =
  ## Try to write data, ignoring transient errors
  ## For cursor control sequences, we prefer to silently skip on EAGAIN
  ## rather than crashing, since they're often non-critical
  discard writeWithRetry(data)

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
    tryWrite(enableMouseMode(MouseSGR))
    terminal.mouseEnabled = true

proc disableMouse*(terminal: Terminal) =
  ## Disable mouse reporting
  if terminal.mouseEnabled:
    tryWrite(disableMouseMode(MouseSGR))
    terminal.mouseEnabled = false

# Cursor control
proc hideCursor*() =
  ## Hide the cursor
  tryWrite(HideCursorSeq)

proc showCursor*() =
  ## Show the cursor
  tryWrite(ShowCursorSeq)

proc setCursorPos*(x, y: int) =
  ## Set cursor position (1-based coordinates)
  tryWrite(makeCursorPositionSeq(x, y))

proc setCursorPos*(pos: Position) =
  ## Set cursor position
  tryWrite(makeCursorPositionSeq(pos))

proc saveCursor*() =
  ## Save current cursor position
  tryWrite(SaveCursorSeq)

proc restoreCursor*() =
  ## Restore previously saved cursor position
  tryWrite(RestoreCursorSeq)

proc moveCursorUp*(steps: int = 1) =
  ## Move cursor up by specified steps
  tryWrite(makeCursorMoveSeq(CursorUpSeq, steps))

proc moveCursorDown*(steps: int = 1) =
  ## Move cursor down by specified steps
  tryWrite(makeCursorMoveSeq(CursorDownSeq, steps))

proc moveCursorLeft*(steps: int = 1) =
  ## Move cursor left by specified steps
  tryWrite(makeCursorMoveSeq(CursorLeftSeq, steps))

proc moveCursorRight*(steps: int = 1) =
  ## Move cursor right by specified steps
  tryWrite(makeCursorMoveSeq(CursorRightSeq, steps))

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
  tryWrite(getCursorStyleSeq(style))

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
  tryWrite(ClearToStartOfLineSeq)

# Buffer rendering
proc renderCell*(cell: Cell, x, y: int) =
  ## Render a single cell at the specified position
  setCursorPos(x, y)

  let styleSeq = cell.style.toAnsiSequence()
  if styleSeq.len > 0:
    tryWrite(styleSeq)

  tryWrite(cell.symbol)

  if styleSeq.len > 0:
    tryWrite(resetSequence())

proc render*(terminal: Terminal, buffer: Buffer) =
  ## Render a buffer to the terminal using differential updates (low-level API)
  ##
  ## This is a low-level rendering function that raises exceptions on errors.
  ## For most use cases, prefer the high-level `draw()` or `drawWithCursor()` instead.
  ##
  ## Raises:
  ## - TerminalError: If rendering fails due to I/O errors or terminal issues
  ##
  ## Use cases:
  ## - Testing and debugging where explicit error handling is needed
  ## - Initialization sequences where failures should halt execution
  ## - Custom rendering pipelines with specific error recovery strategies
  ##
  ## For main application loops, use `draw()` which handles transient errors gracefully.
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
  ## Force a full render of the buffer (low-level API)
  ##
  ## This is a low-level rendering function that raises exceptions on errors.
  ## For most use cases, prefer the high-level `draw()` or `drawWithCursor()` instead.
  ##
  ## Raises:
  ## - TerminalError: If rendering fails due to I/O errors or terminal issues
  ##
  ## Use cases:
  ## - Testing and debugging where explicit error handling is needed
  ## - Initialization sequences where failures should halt execution
  ## - Custom rendering pipelines with specific error recovery strategies
  ##
  ## For main application loops, use `draw()` which handles transient errors gracefully.
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
  ## Draw a buffer to the terminal (high-level API)
  ##
  ## This is the recommended high-level rendering function for main application loops.
  ## Unlike `render()` and `renderFull()`, this function silently ignores I/O errors
  ## to prevent crashes from transient terminal issues. Failed renders will be retried
  ## in the next frame.
  ##
  ## Parameters:
  ## - buffer: The buffer to render to the terminal
  ## - force: If true, forces a full redraw regardless of changes
  ##
  ## Note: For rendering with cursor positioning, use `drawWithCursor()` instead.
  ## For low-level rendering with explicit error handling, use `render()` or `renderFull()`.
  try:
    let output =
      if force or terminal.lastBuffer.area.isEmpty:
        buildFullRenderOutput(buffer)
      else:
        buildDifferentialOutput(terminal.lastBuffer, buffer)

    if output.len > 0:
      # Use writeWithRetry for robust I/O handling
      # Only update lastBuffer if write was successful
      if writeWithRetry(output):
        terminal.lastBuffer = buffer
      # else: keep lastBuffer unchanged so next frame can retry the diff
    else:
      # No output means no changes - safe to update lastBuffer
      terminal.lastBuffer = buffer
  except CatchableError as e:
    # Silently ignore errors for rendering - next frame will retry
    # This prevents crashes from transient terminal I/O issues
    when defined(celinaDebug):
      stderr.writeLine("Warning: draw() failed: " & e.msg)
    else:
      discard e # Avoid "declared but not used" warning

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
  ##
  ## Note: This procedure silently ignores I/O errors to prevent crashes from transient
  ## terminal issues. Failed renders will be retried in the next frame.
  try:
    let output = buildOutputWithCursor(
      terminal.lastBuffer, buffer, cursorX, cursorY, cursorVisible, cursorStyle,
      lastCursorStyle, force,
    )

    if output.len > 0:
      # Use writeWithRetry for robust I/O handling
      # Only update lastBuffer if write was successful
      if writeWithRetry(output):
        terminal.lastBuffer = buffer
      # else: keep lastBuffer unchanged so next frame can retry the diff
    else:
      # No output means no changes - safe to update lastBuffer
      terminal.lastBuffer = buffer
  except CatchableError as e:
    # Silently ignore errors for rendering - next frame will retry
    # This prevents crashes from transient terminal I/O issues
    when defined(celinaDebug):
      stderr.writeLine("Warning: drawWithCursor() failed: " & e.msg)
    else:
      discard e # Avoid "declared but not used" warning

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
