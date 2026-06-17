## Common terminal algorithms and utilities
##
## This module contains shared algorithms and data structures used by both
## synchronous (terminal.nim) and asynchronous (async_terminal.nim) implementations.

import std/[strformat, termios, posix, strutils, os]
import geometry, colors, buffer

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

  CursorState* = object ## Cursor state management for terminal applications
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
    suspendedSyncOutput*: bool

  WriteOutcome* = enum
    woProgress ## `write` returned n > 0; `n` bytes were written, keep going
    woInterrupted ## interrupted by a signal (EINTR); retry
    woWouldBlock ## fd not ready (EAGAIN/EWOULDBLOCK); back off and retry
    woHardError ## unrecoverable error, or a 0-byte write; give up

  WriteWaitOutcome* = enum
    wwWritable ## fd reports POLLOUT; a retried `write` should make progress
    wwNotReady ## not writable within the timeout (or poll itself was interrupted)
    wwError ## fd reports POLLERR/POLLHUP/POLLNVAL; treat as a hard error

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

  # Synchronized Output sequences (DEC private mode 2026)
  # Prevents flickering by buffering output until mode is disabled
  # Supported by: Kitty, WezTerm, foot, Contour, mintty, etc.
  SyncOutputEnable* = "\e[?2026h"
  SyncOutputDisable* = "\e[?2026l"

  # OSC 8 Hyperlink sequences
  # Format: \e]8;params;uri\e\\ (or \x07 as terminator)
  # Supported by: iTerm2, Kitty, WezTerm, VTE-based (GNOME Terminal, etc.), Windows Terminal
  Osc8Start* = "\e]8;;"
  Osc8End* = "\e\\"
  Osc8Reset* = "\e]8;;\e\\" # Reset hyperlink (no URL)

  # OSC Window Title sequences
  # OSC 0: Set window title and icon name
  # OSC 1: Set icon name only
  # OSC 2: Set window title only
  # Supported by: Almost all terminal emulators
  OscWindowTitleStart* = "\e]0;"
  OscIconNameStart* = "\e]1;"
  OscTitleOnlyStart* = "\e]2;"
  OscTerminator* = "\a" # BEL character as terminator (widely supported)

  WriteBlockedWaitMs* = 2
    ## How long one blocked-write wait pauses for stdout to drain: the `poll(2)`
    ## timeout in the sync path, and the cooperative `sleepMs` backoff in the
    ## async path. Small so a terminal that drains quickly is serviced with low
    ## latency; the sync `poll` returns as soon as the fd is writable regardless.
  WriteMaxBlockedWaits* = 1000
    ## Maximum number of *consecutive* waits that make no forward progress before
    ## a write gives up, so a permanently wedged fd cannot hang the caller. The
    ## counter resets to zero on every byte written, so a slow-but-draining
    ## terminal handling a large buffer never trips it — only a genuinely stuck
    ## fd does, after roughly `WriteMaxBlockedWaits * WriteBlockedWaitMs` (~2s)
    ## of zero progress. This bounds both an EAGAIN stall and a pathological
    ## EINTR storm with the same budget.

proc makeWindowTitleSeq*(title: string): string {.inline.} =
  ## Generate OSC sequence to set window title and icon name
  ## Format: \e]0;title\a
  OscWindowTitleStart & title & OscTerminator

proc makeIconNameSeq*(name: string): string {.inline.} =
  ## Generate OSC sequence to set icon name only
  ## Format: \e]1;name\a
  OscIconNameStart & name & OscTerminator

proc makeTitleOnlySeq*(title: string): string {.inline.} =
  ## Generate OSC sequence to set window title only (not icon name)
  ## Format: \e]2;title\a
  OscTitleOnlyStart & title & OscTerminator

proc makeHyperlinkStartSeq*(url: string): string {.inline.} =
  ## Generate OSC 8 hyperlink start sequence
  ## Format: \e]8;;URL\e\\
  Osc8Start & url & Osc8End

proc makeCursorPositionSeq*(x, y: int): string {.inline.} =
  ## Generate ANSI sequence for cursor positioning.
  ## Takes 0-based coordinates and emits a 1-based CSI sequence.
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
  ## Supports OSC 8 hyperlinks - hyperlink state is tracked per cell

  if oldBuffer.area != newBuffer.area:
    # Different sizes, use simple approach
    let changes = calculateSimpleDiff(oldBuffer, newBuffer)
    var currentHyperlink = ""
    var currentStyle = defaultStyle() # SGR style currently active in the terminal

    for change in changes:
      # Shadow cell (right half of a wide char): the lead covers it — skip.
      if change.cell.isShadow:
        continue

      result.add(makeCursorPositionSeq(change.pos.x, change.pos.y))

      # Handle hyperlink state change
      if change.cell.hyperlink != currentHyperlink:
        if currentHyperlink.len > 0:
          result.add(Osc8Reset)
        if change.cell.hyperlink.len > 0:
          result.add(makeHyperlinkStartSeq(change.cell.hyperlink))
        currentHyperlink = change.cell.hyperlink

      # Emit a style sequence only when the style differs from the one already
      # active; runs of same-styled cells then share a single SGR sequence.
      if change.cell.style != currentStyle:
        if currentStyle != defaultStyle():
          result.add(resetSequence())
        if change.cell.style != defaultStyle():
          result.add(change.cell.style.toAnsiSequence())
        currentStyle = change.cell.style

      result.add(change.cell.symbol)

    # Close any open hyperlink and reset any lingering style at the end
    if currentHyperlink.len > 0:
      result.add(Osc8Reset)
    if currentStyle != defaultStyle():
      result.add(resetSequence())
    return result

  var lastCursorPos = (-1, -1) # Track cursor position to minimize cursor moves
  var currentHyperlink = "" # Track current hyperlink state
  var currentStyle = defaultStyle() # SGR style currently active in the terminal

  # Cell-by-cell scan; runs of identical style share a single SGR sequence
  for y in 0 ..< newBuffer.area.height:
    for x in 0 ..< newBuffer.area.width:
      let oldCell = oldBuffer[x, y]
      let newCell = newBuffer[x, y]

      if oldCell != newCell:
        # Shadow cell (right half of a wide char): the lead already advanced
        # the cursor across this column. Emit nothing, but keep lastCursorPos
        # in step so the next cell still positions correctly.
        if newCell.isShadow:
          lastCursorPos = (x + 1, y)
          continue

        # Only move cursor if we're not at the right position
        if lastCursorPos != (x, y):
          result.add(makeCursorPositionSeq(x, y))
          lastCursorPos = (x, y)

        # Handle hyperlink state change
        if newCell.hyperlink != currentHyperlink:
          if currentHyperlink.len > 0:
            result.add(Osc8Reset)
          if newCell.hyperlink.len > 0:
            result.add(makeHyperlinkStartSeq(newCell.hyperlink))
          currentHyperlink = newCell.hyperlink

        # Emit a style sequence only when the style changes. Adjacent changed
        # cells with the same style reuse the active SGR; carrying the style
        # across cursor jumps over unchanged cells is also correct, since SGR
        # only affects glyphs as they are written.
        if newCell.style != currentStyle:
          if currentStyle != defaultStyle():
            result.add(resetSequence())
          if newCell.style != defaultStyle():
            result.add(newCell.style.toAnsiSequence())
          currentStyle = newCell.style

        result.add(newCell.symbol)

        # Update cursor position (we wrote one character)
        lastCursorPos = (x + 1, y)

  # Close any open hyperlink and reset any lingering style at the end
  if currentHyperlink.len > 0:
    result.add(Osc8Reset)
  if currentStyle != defaultStyle():
    result.add(resetSequence())

proc buildFullRenderOutput*(buffer: Buffer): string =
  ## Build output string for full buffer render
  ## Supports OSC 8 hyperlinks
  result = newStringOfCap(buffer.area.width * buffer.area.height * 10)

  # Clear screen first
  result.add(ClearScreenSeq)

  var lastStyle = defaultStyle()
  var lastHyperlink = ""
  var lastNonEmptyX = -1

  for y in 0 ..< buffer.area.height:
    var lineHasContent = false
    var lineBuffer = ""
    lastNonEmptyX = -1

    # Check if line has any content
    for x in 0 ..< buffer.area.width:
      let cell = buffer[x, y]
      if not cell.isEmpty or cell.style != defaultStyle() or cell.hyperlink.len > 0:
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

      # Shadow cell (right half of a wide character): emit nothing — the wide
      # glyph already advanced the cursor two columns. A space here would shift
      # the rest of the line right. (Blanks hold " ", so they skip this.)
      if cell.isShadow:
        continue

      # Update hyperlink if changed
      if cell.hyperlink != lastHyperlink:
        if lastHyperlink.len > 0:
          lineBuffer.add(Osc8Reset)
        if cell.hyperlink.len > 0:
          lineBuffer.add(makeHyperlinkStartSeq(cell.hyperlink))
        lastHyperlink = cell.hyperlink

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

  # Close any open hyperlink at the end
  if lastHyperlink.len > 0:
    result.add(Osc8Reset)

  # Reset style at the end
  if lastStyle != defaultStyle():
    result.add(resetSequence())

# Low-level write retry policy and classification
# Shared by the sync (`writeWithRetry` in terminal.nim), the blocking async-mode
# (`writeStdoutBlocking` in async/async_io.nim) and the async (`writeStdoutAsync`,
# same file) write loops so the EINTR/EAGAIN/short-write decision and the give-up
# thresholds live in one place. The two *blocking* loops now share their whole
# body via `writeAllBlocking` below; only the async loop stays separate because it
# must `await sleepMs` (after a non-blocking `pollWritable` probe) instead of
# blocking in `pollWritable`.

proc classifyWriteResult*(n: int): WriteOutcome =
  ## Classify the raw return value of a single `write(2)` call into a retry
  ## decision. `errno` must still reflect that `write` call (call this with no
  ## intervening syscall). A 0-byte write of a non-empty buffer is treated as a
  ## hard error since `write` makes no progress and never legitimately returns 0
  ## for a non-zero request.
  if n > 0:
    woProgress
  elif n < 0 and errno == EINTR:
    woInterrupted
  elif n < 0 and (errno == EAGAIN or errno == EWOULDBLOCK):
    woWouldBlock
  else:
    woHardError

proc pollWritable*(fd: cint, timeoutMs: int): WriteWaitOutcome =
  ## Wait up to `timeoutMs` milliseconds (0 = non-blocking probe) for `fd` to
  ## accept output. Used by both write loops when `write` reports EAGAIN: instead
  ## of sleeping blind, they ask the kernel whether the fd has drained, and learn
  ## when the fd has gone away (POLLHUP/POLLERR) so a flow-controlled write is not
  ## confused with a dead terminal. A `poll` interrupted by a signal, or that
  ## merely times out, is reported as `wwNotReady` so the caller backs off and
  ## retries (its own blocked-wait counter bounds how long that can continue).
  var pfd: Tpollfd
  pfd.fd = fd
  pfd.events = POLLOUT
  pfd.revents = 0

  let r = posix.poll(addr pfd, 1, timeoutMs.cint)
  if r <= 0:
    # r < 0: poll failed/was interrupted; r == 0: timed out, still not writable.
    return wwNotReady
  if (pfd.revents.int and (POLLERR.int or POLLHUP.int or POLLNVAL.int)) != 0:
    # Error bits win over POLLOUT: the fd is gone, writing again would fail.
    return wwError
  if (pfd.revents.int and POLLOUT.int) != 0:
    return wwWritable
  wwNotReady

proc writeAllBlocking*(fd: cint, data: string): int =
  ## The single shared blocking write loop: loops on `posix.write(fd, ...)` until
  ## every byte of `data` is written or it gives up after `WriteMaxBlockedWaits`
  ## consecutive no-progress waits, blocking in `pollWritable` (not yielding)
  ## while the fd is non-writable. Returns the number of bytes actually written
  ## (`data.len` on success, a short count on give-up). Never raises — a short
  ## count is the signal that output was truncated.
  ##
  ## `writeStdoutBlocking` (async/async_io.nim) and the sync `writeWithRetry`
  ## (terminal.nim) both delegate here; the async `writeStdoutAsync` stays
  ## separate because it must `await` rather than block. Uses the shared
  ## `classifyWriteResult`/`WriteMaxBlockedWaits` policy above.
  if data.len == 0:
    return 0

  var
    total = 0
    blockedWaits = 0
  try:
    while total < data.len:
      let n = posix.write(fd, unsafeAddr data[total], data.len - total).int

      case classifyWriteResult(n)
      of woProgress:
        total += n
        blockedWaits = 0
      of woInterrupted:
        # Interrupted before any byte moved. Retry, but count it so a relentless
        # signal storm cannot spin forever.
        inc blockedWaits
        if blockedWaits >= WriteMaxBlockedWaits:
          when defined(celinaDebug):
            stderr.writeLine("Warning: writeAllBlocking gave up after repeated EINTR")
          break
      of woWouldBlock:
        # fd's kernel buffer is full. Block in pollWritable until it drains
        # instead of dropping data mid-escape-sequence; give up only after
        # WriteMaxBlockedWaits consecutive no-progress waits.
        inc blockedWaits
        if blockedWaits >= WriteMaxBlockedWaits:
          when defined(celinaDebug):
            stderr.writeLine("Warning: writeAllBlocking gave up after repeated EAGAIN")
          break
        case pollWritable(fd, WriteBlockedWaitMs)
        of wwError:
          # fd went away (POLLHUP/POLLERR); stop and report bytes sent.
          when defined(celinaDebug):
            stderr.writeLine("Warning: writeAllBlocking: fd reported POLLERR/POLLHUP")
          break
        of wwWritable:
          # Writable again: retry promptly.
          continue
        of wwNotReady:
          # The blocking poll already consumed the back-off budget; loop back and
          # let the blocked-waits counter decide whether to give up.
          continue
      of woHardError:
        # Hard error, or a 0-byte write we can't make progress on; stop and
        # report how much actually made it out.
        when defined(celinaDebug):
          stderr.writeLine("Warning: writeAllBlocking failed with error: " & $errno)
        break
  except CatchableError:
    # Never raise out of the loop: report however many bytes already made it out.
    discard

  result = total

proc wrapWithSyncOutput*(output: string): string =
  ## Wrap output string with synchronized output sequences
  ## This prevents flickering by buffering terminal output
  if output.len == 0:
    return ""
  SyncOutputEnable & output & SyncOutputDisable

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
    lastCursorStyle: CursorStyle,
    force: bool = false,
): tuple[output: string, newLastCursorStyle: CursorStyle] =
  ## Build output string with cursor positioning included
  ## This prevents cursor flickering by including cursor commands in the same output
  ## Supports OSC 8 hyperlinks
  ##
  ## Returns a tuple with the output string and the updated cursor style.
  ## Caller is responsible for tracking the lastCursorStyle state.
  var output = ""
  var updatedLastCursorStyle = lastCursorStyle

  # First, build the buffer diff output
  if force or oldBuffer.area != newBuffer.area:
    # Use full render for different sizes
    var currentHyperlink = ""
    for y in 0 ..< newBuffer.area.height:
      for x in 0 ..< newBuffer.area.width:
        let cell = newBuffer[x, y]
        # Render if cell has non-default symbol, foreground, background, or hyperlink
        if cell.symbol != " " or cell.style.fg.kind != Default or
            cell.style.bg.kind != Default or cell.hyperlink.len > 0:
          output.add(makeCursorPositionSeq(x, y))

          # Handle hyperlink state change
          if cell.hyperlink != currentHyperlink:
            if currentHyperlink.len > 0:
              output.add(Osc8Reset)
            if cell.hyperlink.len > 0:
              output.add(makeHyperlinkStartSeq(cell.hyperlink))
            currentHyperlink = cell.hyperlink

          let styleSeq = cell.style.toAnsiSequence()
          if styleSeq.len > 0:
            output.add(styleSeq)
          output.add(cell.symbol)
          if styleSeq.len > 0:
            output.add(resetSequence())

    # Close any open hyperlink
    if currentHyperlink.len > 0:
      output.add(Osc8Reset)
  else:
    # Use differential rendering
    output.add(buildDifferentialOutput(oldBuffer, newBuffer))

  # Then append cursor commands to the same output string
  if cursorVisible and cursorX >= 0 and cursorY >= 0:
    # Only apply cursor style if it has changed to avoid interrupting blinking
    if cursorStyle != updatedLastCursorStyle:
      output.add(getCursorStyleSeq(cursorStyle))
      updatedLastCursorStyle = cursorStyle
    output.add(ShowCursorSeq)
    output.add(makeCursorPositionSeq(cursorX, cursorY))
  else:
    output.add(HideCursorSeq)

  result = (output: output, newLastCursorStyle: updatedLastCursorStyle)

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
  terminal.suspendState.suspendedSyncOutput = terminal.syncOutputEnabled

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
  if terminal.suspendState.suspendedSyncOutput:
    terminal.enableSyncOutput()

template clearLastBufferForResume*(terminal: typed) =
  ## Clear lastBuffer to force full redraw after resume
  terminal.lastBuffer = newBuffer(0, 0)
  terminal.suspendState.isSuspended = false

template adoptLastBufferImpl*(terminal: typed, buffer: var Buffer) =
  ## Adopt `buffer` as the new `lastBuffer` without the per-frame deep copy.
  ##
  ## In steady state both buffers cover the same area, so we `swap` (zero-copy):
  ## `lastBuffer` takes the freshly rendered content and the caller's `buffer`
  ## receives the previous frame's storage (recycling the allocation). This is
  ## only safe when the caller fully re-fills `buffer` before the next render,
  ## so it is reserved for renderer-owned buffers (the `*Adopt` draw variants);
  ## the public `draw`/`drawWithCursor` keep copy semantics and never call this.
  ##
  ## When the areas differ (first frame, after a resize) we fall back to a copy
  ## so the caller is never handed a wrong-sized buffer.
  ##
  ## Shared by the sync (`terminal.nim`) and async (`async_terminal.nim`)
  ## backends so the swap/copy contract lives in exactly one place.
  if terminal.lastBuffer.area == buffer.area:
    swap(terminal.lastBuffer, buffer)
  else:
    terminal.lastBuffer = buffer
  terminal.lastBuffer.clearDirty()
