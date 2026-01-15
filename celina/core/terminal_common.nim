## Common terminal algorithms and utilities
##
## This module contains shared algorithms and data structures used by both
## synchronous (terminal.nim) and asynchronous (async_terminal.nim) implementations.

import std/[strformat, termios, posix, strutils, os]
import geometry, colors, buffer

# ANSI Escape Sequences

type
  AnsiSequence* = distinct string

  MouseMode* = enum
    ## Mouse reporting modes
    MouseOff
    MouseX10 # Basic mouse reporting
    MouseButton # Button tracking
    MouseMotion # Motion tracking
    MouseAll # All events
    MouseSGR # SGR extended mode

  CursorStyle* = enum
    ## Cursor appearance styles
    Default
    BlinkingBlock
    SteadyBlock
    BlinkingUnderline
    SteadyUnderline
    BlinkingBar
    SteadyBar

  ## Cursor state management for terminal applications
  CursorState* = object
    x*: int ## Current cursor X position (-1 = not set)
    y*: int ## Current cursor Y position (-1 = not set)
    visible*: bool ## Whether cursor should be visible
    style*: CursorStyle ## Current cursor style
    lastStyle*: CursorStyle ## Last applied cursor style (to avoid redundant updates)

  SuspendState* = object ## Suspended state tracking (for suspend/resume)
    isSuspended*: bool
    suspendedRawMode*: bool
    suspendedAlternateScreen*: bool
    suspendedMouseEnabled*: bool
    suspendedBracketedPaste*: bool
    suspendedFocusEvents*: bool

const
  # Screen control sequences
  AlternateScreenEnter* = "\e[?1049h"
  AlternateScreenExit* = "\e[?1049l"
  ClearScreenSeq* = "\e[2J"
  ClearLineSeq* = "\e[2K"
  ClearToEndOfLineSeq* = "\e[0K"
  ClearToStartOfLineSeq* = "\e[1K"

  # Cursor control sequences
  HideCursorSeq* = "\e[?25l"
  ShowCursorSeq* = "\e[?25h"
  SaveCursorSeq* = "\e[s"
  RestoreCursorSeq* = "\e[u"

  # Cursor movement sequences (relative)
  CursorUpSeq* = "\e[A"
  CursorDownSeq* = "\e[B"
  CursorRightSeq* = "\e[C"
  CursorLeftSeq* = "\e[D"

  # Cursor style sequences (DECSCUSR - DEC Set Cursor Style)
  CursorStyleDefault* = "\e[0 q" # Default cursor
  CursorStyleBlinkingBlock* = "\e[1 q" # Blinking block
  CursorStyleSteadyBlock* = "\e[2 q" # Steady block
  CursorStyleBlinkingUnderline* = "\e[3 q" # Blinking underline
  CursorStyleSteadyUnderline* = "\e[4 q" # Steady underline
  CursorStyleBlinkingBar* = "\e[5 q" # Blinking vertical bar
  CursorStyleSteadyBar* = "\e[6 q" # Steady vertical bar

  # Mouse mode sequences
  MouseSequences* = [
    MouseX10: ("\e[?9h", "\e[?9l"),
    MouseButton: ("\e[?1000h", "\e[?1000l"),
    MouseMotion: ("\e[?1002h", "\e[?1002l"),
    MouseAll: ("\e[?1003h", "\e[?1003l"),
    MouseSGR: ("\e[?1006h", "\e[?1006l"),
  ]

  # Bracketed paste mode sequences (DEC private mode 2004)
  BracketedPasteEnable* = "\e[?2004h"
  BracketedPasteDisable* = "\e[?2004l"

  # Focus events sequences (DEC private mode 1004)
  FocusEventsEnable* = "\e[?1004h"
  FocusEventsDisable* = "\e[?1004l"

proc makeCursorPositionSeq*(x, y: int): string {.inline.} =
  ## Generate ANSI sequence for cursor positioning (1-based)
  &"\e[{y + 1};{x + 1}H"

proc makeCursorPositionSeq*(pos: Position): string {.inline.} =
  ## Generate ANSI sequence for cursor positioning
  makeCursorPositionSeq(pos.x, pos.y)

proc makeCursorMoveSeq*(direction: string, steps: int): string {.inline.} =
  ## Generate ANSI sequence for cursor movement with steps
  if steps == 1:
    direction
  else:
    &"\e[{steps}{direction[direction.len-1]}"

proc getCursorStyleSeq*(style: CursorStyle): string =
  ## Get ANSI sequence for cursor style
  case style
  of Default: CursorStyleDefault
  of BlinkingBlock: CursorStyleBlinkingBlock
  of SteadyBlock: CursorStyleSteadyBlock
  of BlinkingUnderline: CursorStyleBlinkingUnderline
  of SteadyUnderline: CursorStyleSteadyUnderline
  of BlinkingBar: CursorStyleBlinkingBar
  of SteadyBar: CursorStyleSteadyBar

# Terminal Configuration

type TerminalConfig* = object ## Shared terminal configuration structure
  c_lflag_mask*: Cflag
  c_iflag_mask*: Cflag
  c_cflag_set*: Cflag
  c_oflag_mask*: Cflag
  vmin*: char
  vtime*: char

proc getRawModeConfig*(): TerminalConfig =
  ## Get raw mode configuration
  TerminalConfig(
    c_lflag_mask: not (ECHO or ICANON or ISIG or IEXTEN),
    c_iflag_mask: not (IXON or ICRNL or BRKINT or INPCK or ISTRIP),
    c_cflag_set: CS8,
    c_oflag_mask: not OPOST,
    vmin: 1.char,
    vtime: 0.char,
  )

proc applyTerminalConfig*(termios: var Termios, config: TerminalConfig) =
  ## Apply terminal configuration to termios structure
  termios.c_lflag = termios.c_lflag and config.c_lflag_mask
  termios.c_iflag = termios.c_iflag and config.c_iflag_mask
  termios.c_cflag = termios.c_cflag or config.c_cflag_set
  termios.c_oflag = termios.c_oflag and config.c_oflag_mask
  termios.c_cc[VMIN] = config.vmin
  termios.c_cc[VTIME] = config.vtime

# Terminal Size Detection

proc getTerminalSizeFromSystem*(): tuple[width: int, height: int, success: bool] =
  ## Get terminal size from system, returns (width, height, success)
  var w: IOctl_WinSize
  if ioctl(STDOUT_FILENO, TIOCGWINSZ, addr w) == 0:
    result = (w.ws_col.int, w.ws_row.int, true)
  else:
    result = (80, 24, false) # Default fallback size

proc getTerminalSizeWithFallback*(defaultWidth = 80, defaultHeight = 24): Size =
  ## Get terminal size with custom fallback values
  let (width, height, success) = getTerminalSizeFromSystem()
  if success:
    size(width, height)
  else:
    size(defaultWidth, defaultHeight)

# Render Optimization

type
  RenderCommandKind* = enum
    RckSetPosition
    RckSetStyle
    RckWriteText
    RckClearScreen
    RckClearLine

  RenderCommand* = object ## A single rendering command
    case kind*: RenderCommandKind
    of RckSetPosition:
      pos*: Position
    of RckSetStyle:
      style*: Style
    of RckWriteText:
      text*: string
    of RckClearScreen:
      discard
    of RckClearLine:
      discard

  RenderBatch* = object ## Batch of render commands for efficient output
    commands*: seq[RenderCommand]
    estimatedSize*: int # Estimated output buffer size

proc addCommand*(batch: var RenderBatch, cmd: RenderCommand) =
  ## Add a command to the render batch
  batch.commands.add(cmd)

  # Update estimated size
  case cmd.kind
  of RckSetPosition:
    batch.estimatedSize += 10 # Typical cursor position sequence
  of RckSetStyle:
    batch.estimatedSize += 20 # Style sequences can vary
  of RckWriteText:
    batch.estimatedSize += cmd.text.len
  of RckClearScreen, RckClearLine:
    batch.estimatedSize += 5

proc generateRenderBatch*(changes: seq[tuple[pos: Position, cell: Cell]]): RenderBatch =
  ## Generate optimized render commands from cell changes
  result = RenderBatch(commands: @[], estimatedSize: 0)

  if changes.len == 0:
    return

  var lastPos = Position(x: -1, y: -1)
  var lastStyle = defaultStyle()
  var currentText = ""
  var currentRow = -1

  for change in changes:
    # Check if we need to move cursor
    let needsMove =
      change.pos.y != currentRow or
      (change.pos.y == currentRow and change.pos.x != lastPos.x + 1)

    if needsMove:
      # Flush any pending text
      if currentText.len > 0:
        result.addCommand(RenderCommand(kind: RckWriteText, text: currentText))
        currentText = ""

      # Add position command
      result.addCommand(RenderCommand(kind: RckSetPosition, pos: change.pos))
      currentRow = change.pos.y
      lastPos = change.pos

    # Check if style changed
    if change.cell.style != lastStyle:
      # Flush any pending text
      if currentText.len > 0:
        result.addCommand(RenderCommand(kind: RckWriteText, text: currentText))
        currentText = ""

      # Add style command
      result.addCommand(RenderCommand(kind: RckSetStyle, style: change.cell.style))
      lastStyle = change.cell.style

    # Accumulate text
    currentText.add(change.cell.symbol)
    lastPos.x = change.pos.x

  # Flush final text
  if currentText.len > 0:
    result.addCommand(RenderCommand(kind: RckWriteText, text: currentText))

proc optimizeRenderBatch*(batch: RenderBatch): RenderBatch =
  ## Optimize render batch by merging adjacent commands
  result = RenderBatch(commands: @[], estimatedSize: 0)

  var i = 0
  while i < batch.commands.len:
    let cmd = batch.commands[i]

    case cmd.kind
    of RckWriteText:
      # Merge consecutive text writes
      var mergedText = cmd.text
      var j = i + 1
      while j < batch.commands.len and batch.commands[j].kind == RckWriteText:
        mergedText.add(batch.commands[j].text)
        j.inc

      result.addCommand(RenderCommand(kind: RckWriteText, text: mergedText))
      i = j - 1
    of RckSetStyle:
      # Skip redundant style changes
      if i + 1 < batch.commands.len and batch.commands[i + 1].kind == RckSetStyle:
        # Skip this style change as it will be immediately overridden
        discard
      else:
        result.addCommand(cmd)
    else:
      result.addCommand(cmd)

    i.inc

proc buildOutputString*(batch: RenderBatch): string =
  ## Build the final output string from render commands
  result = newStringOfCap(batch.estimatedSize)

  for cmd in batch.commands:
    case cmd.kind
    of RckSetPosition:
      result.add(makeCursorPositionSeq(cmd.pos))
    of RckSetStyle:
      result.add(cmd.style.toAnsiSequence())
    of RckWriteText:
      result.add(cmd.text)
    of RckClearScreen:
      result.add(ClearScreenSeq)
    of RckClearLine:
      result.add(ClearLineSeq)

# Differential Rendering

proc calculateSimpleDiff*(
    oldBuffer, newBuffer: Buffer
): seq[tuple[pos: Position, cell: Cell]] =
  ## Calculate simple cell-by-cell differences
  ## This is a fallback when the optimized diff is not suitable
  result = @[]

  if oldBuffer.area != newBuffer.area:
    # Size changed, need full redraw
    for y in 0 ..< newBuffer.area.height:
      for x in 0 ..< newBuffer.area.width:
        let cell = newBuffer[x, y]
        result.add((pos: pos(x, y), cell: cell))
  else:
    # Same size, find differences
    for y in 0 ..< newBuffer.area.height:
      for x in 0 ..< newBuffer.area.width:
        let oldCell = oldBuffer[x, y]
        let newCell = newBuffer[x, y]

        if oldCell != newCell:
          result.add((pos: pos(x, y), cell: newCell))

proc buildDifferentialOutput*(oldBuffer, newBuffer: Buffer): string =
  ## Build output string using simple cell-by-cell differential rendering

  if oldBuffer.area != newBuffer.area:
    # Different sizes, use simple approach
    let changes = calculateSimpleDiff(oldBuffer, newBuffer)
    for change in changes:
      result.add(makeCursorPositionSeq(change.pos.x, change.pos.y))

      # Apply style if present
      let styleSeq = change.cell.style.toAnsiSequence()
      if styleSeq.len > 0:
        result.add(styleSeq)

      result.add(change.cell.symbol)

      # Reset style if it was applied
      if styleSeq.len > 0:
        result.add(resetSequence())
    return result

  var lastCursorPos = (-1, -1) # Track cursor position to minimize cursor moves

  # Simple cell-by-cell approach - write each changed cell individually
  for y in 0 ..< newBuffer.area.height:
    for x in 0 ..< newBuffer.area.width:
      let oldCell = oldBuffer[x, y]
      let newCell = newBuffer[x, y]

      if oldCell != newCell:
        # Only move cursor if we're not at the right position
        if lastCursorPos != (x, y):
          result.add(makeCursorPositionSeq(x, y))
          lastCursorPos = (x, y)

        # Apply style and write character
        let styleSeq = newCell.style.toAnsiSequence()
        if styleSeq.len > 0:
          result.add(styleSeq)

        result.add(newCell.symbol)

        # Reset style if it was applied
        if styleSeq.len > 0:
          result.add(resetSequence())

        # Update cursor position (we wrote one character)
        lastCursorPos = (x + 1, y)

proc buildFullRenderOutput*(buffer: Buffer): string =
  ## Build output string for full buffer render
  result = newStringOfCap(buffer.area.width * buffer.area.height * 10)

  # Clear screen first
  result.add(ClearScreenSeq)

  var lastStyle = defaultStyle()
  var lastNonEmptyX = -1

  for y in 0 ..< buffer.area.height:
    var lineHasContent = false
    var lineBuffer = ""
    lastNonEmptyX = -1

    # Check if line has any content
    for x in 0 ..< buffer.area.width:
      let cell = buffer[x, y]
      if not cell.isEmpty or cell.style != defaultStyle():
        lineHasContent = true
        break

    if not lineHasContent:
      # For empty lines, still need to clear them if they had content before
      # Add minimal clear sequence for the line
      result.add(makeCursorPositionSeq(buffer.area.x, buffer.area.y + y))
      result.add(ClearToEndOfLineSeq)
      continue

    # Position cursor at start of line
    result.add(makeCursorPositionSeq(buffer.area.x, buffer.area.y + y))

    for x in 0 ..< buffer.area.width:
      let cell = buffer[x, y]

      # Handle gaps between non-empty cells
      if cell.isEmpty and cell.style == defaultStyle():
        lineBuffer.add(" ") # Add space for empty cell
      else:
        # Update style if changed
        if cell.style != lastStyle:
          if lastStyle != defaultStyle():
            lineBuffer.add(resetSequence())
          if cell.style != defaultStyle():
            lineBuffer.add(cell.style.toAnsiSequence())
          lastStyle = cell.style

        # Add the character
        lineBuffer.add(cell.symbol)
        lastNonEmptyX = x

    # Add line to result
    if lastNonEmptyX >= 0:
      result.add(lineBuffer)

  # Reset style at the end
  if lastStyle != defaultStyle():
    result.add(resetSequence())

# Common terminal control templates
# These work with both Terminal and AsyncTerminal types

template writeAndFlush*(data: string) =
  ## Write data to stdout and flush
  stdout.write(data)
  stdout.flushFile()

template enableAlternateScreenImpl*(terminal: typed) =
  ## Common logic for enabling alternate screen
  if not terminal.alternateScreen:
    writeAndFlush(AlternateScreenEnter)
    terminal.alternateScreen = true

template disableAlternateScreenImpl*(terminal: typed) =
  ## Common logic for disabling alternate screen
  if terminal.alternateScreen:
    writeAndFlush(AlternateScreenExit)
    terminal.alternateScreen = false

template enableMouseImpl*(terminal: typed) =
  ## Common logic for enabling mouse
  if not terminal.mouseEnabled:
    writeAndFlush(enableMouseMode(MouseSGR))
    terminal.mouseEnabled = true

template disableMouseImpl*(terminal: typed) =
  ## Common logic for disabling mouse
  if terminal.mouseEnabled:
    writeAndFlush(disableMouseMode(MouseSGR))
    terminal.mouseEnabled = false

# Bracketed paste mode templates
template enableBracketedPasteImpl*(terminal: typed) =
  ## Common logic for enabling bracketed paste mode
  if not terminal.bracketedPasteEnabled:
    writeAndFlush(BracketedPasteEnable)
    terminal.bracketedPasteEnabled = true

template disableBracketedPasteImpl*(terminal: typed) =
  ## Common logic for disabling bracketed paste mode
  if terminal.bracketedPasteEnabled:
    writeAndFlush(BracketedPasteDisable)
    terminal.bracketedPasteEnabled = false

# Focus events templates
template enableFocusEventsImpl*(terminal: typed) =
  ## Common logic for enabling focus events
  if not terminal.focusEventsEnabled:
    writeAndFlush(FocusEventsEnable)
    terminal.focusEventsEnabled = true

template disableFocusEventsImpl*(terminal: typed) =
  ## Common logic for disabling focus events
  if terminal.focusEventsEnabled:
    writeAndFlush(FocusEventsDisable)
    terminal.focusEventsEnabled = false

# Mouse Input Processing

proc enableMouseMode*(mode: MouseMode): string =
  ## Generate sequence to enable mouse mode
  if mode == MouseOff:
    return ""

  result = ""
  # Enable all modes up to the requested one
  for m in MouseX10 .. mode:
    result.add(MouseSequences[m][0])

proc disableMouseMode*(mode: MouseMode): string =
  ## Generate sequence to disable mouse mode
  if mode == MouseOff:
    return ""

  result = ""
  # Disable in reverse order
  for i in countdown(ord(mode), ord(MouseX10)):
    let m = MouseMode(i)
    result.add(MouseSequences[m][1])

proc parseMouseEvent*(data: string): tuple[x: int, y: int, button: int, success: bool] =
  ## Parse mouse event from terminal input
  ## Returns (x, y, button, success)

  # SGR format: \e[<button>;<x>;<y>M or \e[<button>;<x>;<y>m
  if data.len > 3 and data[0 .. 2] == "\e[<":
    try:
      var parts: seq[string] = @[]
      var current = ""

      for i in 3 ..< data.len:
        if data[i] in {';', 'M', 'm'}:
          parts.add(current)
          current = ""
          if data[i] in {'M', 'm'}:
            break
        else:
          current.add(data[i])

      if parts.len >= 3:
        let button = parseInt(parts[0])
        let x = parseInt(parts[1]) - 1 # Convert from 1-based to 0-based
        let y = parseInt(parts[2]) - 1
        return (x, y, button, true)
    except ValueError:
      discard

  return (0, 0, 0, false)

# Performance Metrics

type RenderMetrics* = object ## Metrics for rendering performance analysis
  cellsChanged*: int
  commandsGenerated*: int
  outputSize*: int
  optimizationRatio*: float

proc calculateRenderMetrics*(
    oldBuffer, newBuffer: Buffer, batch: RenderBatch
): RenderMetrics =
  ## Calculate rendering performance metrics
  let changes = oldBuffer.diff(newBuffer)

  result = RenderMetrics(
    cellsChanged: changes.len,
    commandsGenerated: batch.commands.len,
    outputSize: batch.estimatedSize,
    optimizationRatio:
      if changes.len > 0:
        batch.commands.len.float / changes.len.float
      else:
        1.0,
  )

# Utility Functions

proc isTerminalInteractive*(): bool =
  ## Check if we're running in an interactive terminal
  isatty(STDIN_FILENO) == 1 and isatty(STDOUT_FILENO) == 1

# Cursor-aware rendering functions

proc buildOutputWithCursor*(
    oldBuffer, newBuffer: Buffer,
    cursorX, cursorY: int,
    cursorVisible: bool,
    cursorStyle: CursorStyle = CursorStyle.Default,
    lastCursorStyle: var CursorStyle,
    force: bool = false,
): string =
  ## Build output string with cursor positioning included
  ## This prevents cursor flickering by including cursor commands in the same output
  # First, build the buffer diff output
  if force or oldBuffer.area != newBuffer.area:
    # Use full render for different sizes
    for y in 0 ..< newBuffer.area.height:
      for x in 0 ..< newBuffer.area.width:
        let cell = newBuffer[x, y]
        # Render if cell has non-default symbol, foreground, or background
        if cell.symbol != " " or cell.style.fg.kind != Default or
            cell.style.bg.kind != Default:
          result.add(makeCursorPositionSeq(x, y))
          let styleSeq = cell.style.toAnsiSequence()
          if styleSeq.len > 0:
            result.add(styleSeq)
          result.add(cell.symbol)
          if styleSeq.len > 0:
            result.add(resetSequence())
  else:
    # Use differential rendering
    result.add(buildDifferentialOutput(oldBuffer, newBuffer))

  # Then append cursor commands to the same output string
  if cursorVisible and cursorX >= 0 and cursorY >= 0:
    # Only apply cursor style if it has changed to avoid interrupting blinking
    if cursorStyle != lastCursorStyle:
      result.add(getCursorStyleSeq(cursorStyle))
      lastCursorStyle = cursorStyle
    result.add(ShowCursorSeq)
    result.add(makeCursorPositionSeq(cursorX, cursorY))
  else:
    result.add(HideCursorSeq)

proc supportsAnsi*(): bool =
  ## Check if terminal supports ANSI escape sequences
  # Check TERM environment variable
  let term = getEnv("TERM", "")

  # Common terminals that don't support ANSI
  const unsupportedTerms = ["dumb", "cons25", "emacs"]

  if term in unsupportedTerms:
    return false

  # Most modern terminals support ANSI
  return term.len > 0 and isTerminalInteractive()

proc getTerminalCapabilities*(): set[MouseMode] =
  ## Detect supported mouse modes
  result = {}

  let term = getEnv("TERM", "")

  # Modern terminals generally support all modes
  if "xterm" in term or "screen" in term or "tmux" in term:
    result = {MouseX10, MouseButton, MouseMotion, MouseAll, MouseSGR}
  elif term.len > 0:
    # Conservative: assume basic support
    result = {MouseX10, MouseButton}

# Common terminal state query templates
# These work with both Terminal and AsyncTerminal types

template isRawMode*(terminal: typed): bool =
  ## Check if terminal is in raw mode
  terminal.rawMode

template isAlternateScreen*(terminal: typed): bool =
  ## Check if alternate screen is active
  terminal.alternateScreen

template isMouseEnabled*(terminal: typed): bool =
  ## Check if mouse reporting is enabled
  terminal.mouseEnabled

template getSize*(terminal: typed): Size =
  ## Get current terminal size
  terminal.size

template getArea*(terminal: typed): Rect =
  ## Get terminal area as a Rect
  rect(0, 0, terminal.size.width, terminal.size.height)

# Suspend/Resume templates

template isSuspended*(terminal: typed): bool =
  ## Check if terminal is currently suspended
  terminal.suspendState.isSuspended

template saveSuspendState*(terminal: typed) =
  ## Save current terminal state for suspend
  terminal.suspendState.suspendedRawMode = terminal.rawMode
  terminal.suspendState.suspendedAlternateScreen = terminal.alternateScreen
  terminal.suspendState.suspendedMouseEnabled = terminal.mouseEnabled
  terminal.suspendState.suspendedBracketedPaste = terminal.bracketedPasteEnabled
  terminal.suspendState.suspendedFocusEvents = terminal.focusEventsEnabled

template restoreSuspendedFeatures*(terminal: typed) =
  ## Restore terminal features from suspend state
  if terminal.suspendState.suspendedAlternateScreen:
    terminal.enableAlternateScreen()
  if terminal.suspendState.suspendedRawMode:
    terminal.enableRawMode()
  if terminal.suspendState.suspendedMouseEnabled:
    terminal.enableMouse()
  if terminal.suspendState.suspendedBracketedPaste:
    terminal.enableBracketedPaste()
  if terminal.suspendState.suspendedFocusEvents:
    terminal.enableFocusEvents()

template clearLastBufferForResume*(terminal: typed) =
  ## Clear lastBuffer to force full redraw after resume
  terminal.lastBuffer = newBuffer(0, 0)
  terminal.suspendState.isSuspended = false
