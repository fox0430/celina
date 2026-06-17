## Async Terminal I/O interface
##
## This module provides asynchronous terminal control and rendering capabilities
## using either Chronos or std/asyncdispatch for non-blocking I/O operations.
##
## **Important**: This module exports global cursor functions like `showCursorAsync()`,
## `hideCursorAsync()`, and `setCursorStyleAsync()`. These write directly to the terminal
## and do **not** integrate with the `AsyncApp`/`AsyncRenderer` cursor state.
##
## When using `AsyncApp`, control the cursor via the app instance instead:
## ```nim
## app.onRenderAsync proc(buffer: var Buffer) =
##   app.showCursorAt(x, y)      # Correct - uses renderer state
##   app.setCursorStyle(Bar)     # Correct
##   # await showCursorAsync()   # Wrong - bypasses renderer
## ```

import std/[termios, posix]

import async_backend, async_buffer
import ../core/[geometry, colors, buffer, terminal_common, errors]
from async_io import
  AsyncInputReader, clearPendingByteAsync, tryWriteAsync, writeOrRaiseAsync,
  tryWriteBlocking, writeOrRaiseBlocking

type
  AsyncTerminal* = ref object ## Async terminal interface for screen management
    size*: Size
    alternateScreen*: bool
    rawMode*: bool
    mouseEnabled*: bool
    bracketedPasteEnabled*: bool
    focusEventsEnabled*: bool
    syncOutputEnabled*: bool
    lastBuffer*: Buffer
    stdinFd*: AsyncFD
    stdoutFd*: AsyncFD
    rawModeEnabled: bool # Track raw mode state internally
    originalTermios: Termios # Store original terminal settings per instance
    suspendState: SuspendState

  AsyncTerminalError* = object of CatchableError

proc getTerminalSizeAsync*(): Size {.inline.} =
  ## Get current terminal size
  return getTerminalSizeWithFallback(80, 24)

proc updateSize*(terminal: AsyncTerminal) {.inline.} =
  ## Update terminal size from current terminal
  terminal.size = getTerminalSizeAsync()

proc newAsyncTerminal*(): AsyncTerminal =
  ## Create a new AsyncTerminal instance
  ## Uses default size if unable to get actual terminal size
  result = AsyncTerminal(
    size: size(80, 24), # Default size
    alternateScreen: false,
    rawMode: false,
    mouseEnabled: false,
    rawModeEnabled: false,
  )

  # Initialize async file descriptors
  result.stdinFd = STDIN_FILENO.AsyncFD
  result.stdoutFd = STDOUT_FILENO.AsyncFD

  # AsyncFD registration is handled automatically by Chronos
  # No manual registration needed

  updateSize(result)

  # Initialize lastBuffer to avoid initial full redraw
  result.lastBuffer = newBuffer(rect(0, 0, result.size.width, result.size.height))

proc enableRawMode*(terminal: AsyncTerminal, reader: AsyncInputReader = nil) =
  ## Enable raw mode for direct key input
  ## Best effort - logs errors in debug mode but doesn't raise
  ##
  ## When `reader` is non-nil, drops any UTF-8 resync byte buffered before
  ## the mode transition so it cannot leak across modes as a phantom
  ## keypress.
  ##
  ## **If you own an `AsyncInputReader` you MUST pass it**, otherwise a
  ## resync byte stashed in the previous mode will surface as a phantom
  ## keypress after the toggle. The `nil` default exists only for
  ## standalone terminal users who manage no reader at all.
  if terminal.rawModeEnabled:
    return # Already enabled

  if tcgetattr(STDIN_FILENO, addr terminal.originalTermios) == -1:
    when defined(celinaDebug):
      stderr.writeLine("Warning: Failed to get terminal attributes")
    return

  var raw = terminal.originalTermios
  applyTerminalConfig(raw, getRawModeConfig())

  if tcsetattr(STDIN_FILENO, TCSAFLUSH, addr raw) == -1:
    when defined(celinaDebug):
      stderr.writeLine("Warning: Failed to set raw mode")
    return

  terminal.rawMode = true
  terminal.rawModeEnabled = true
  if not reader.isNil:
    reader.clearPendingByteAsync()

proc disableRawMode*(terminal: AsyncTerminal, reader: AsyncInputReader = nil) =
  ## Disable raw mode, restoring original terminal settings
  ## Best effort - doesn't raise on error to ensure cleanup
  ##
  ## When `reader` is non-nil, drops any UTF-8 resync byte buffered before
  ## the mode transition. Same ownership rule as `enableRawMode`: callers
  ## that hold a reader MUST pass it to avoid a phantom keypress after
  ## the toggle.
  if not terminal.rawModeEnabled:
    return # Not enabled

  if tcsetattr(STDIN_FILENO, TCSAFLUSH, addr terminal.originalTermios) == -1:
    when defined(celinaDebug):
      stderr.writeLine("Warning: Failed to restore terminal settings")
  terminal.rawMode = false
  terminal.rawModeEnabled = false
  if not reader.isNil:
    reader.clearPendingByteAsync()

# Alternate screen control
proc enableAlternateScreen*(terminal: AsyncTerminal) =
  ## Switch to alternate screen buffer.
  ## Raises IOError if the sequence cannot be written in full.
  if not terminal.alternateScreen:
    writeOrRaiseBlocking(AlternateScreenEnter)
    terminal.alternateScreen = true

proc disableAlternateScreen*(terminal: AsyncTerminal) =
  ## Switch back to main screen buffer.
  ## Best effort - doesn't raise on error to ensure cleanup can complete.
  if terminal.alternateScreen:
    tryWriteBlocking(AlternateScreenExit)
    terminal.alternateScreen = false

# Mouse control
proc enableMouse*(terminal: AsyncTerminal) =
  ## Enable mouse reporting.
  ## Best effort - doesn't raise on error.
  if not terminal.mouseEnabled:
    tryWriteBlocking(enableMouseMode(MouseSGR))
    terminal.mouseEnabled = true

proc disableMouse*(terminal: AsyncTerminal) =
  ## Disable mouse reporting.
  ## Best effort - doesn't raise on error to ensure cleanup can complete.
  if terminal.mouseEnabled:
    tryWriteBlocking(disableMouseMode(MouseSGR))
    terminal.mouseEnabled = false

# Bracketed paste control
proc enableBracketedPaste*(terminal: AsyncTerminal) =
  ## Enable bracketed paste mode for paste detection.
  ## Best effort - doesn't raise on error.
  if not terminal.bracketedPasteEnabled:
    tryWriteBlocking(BracketedPasteEnable)
    terminal.bracketedPasteEnabled = true

proc disableBracketedPaste*(terminal: AsyncTerminal) =
  ## Disable bracketed paste mode.
  ## Best effort - doesn't raise on error to ensure cleanup can complete.
  if terminal.bracketedPasteEnabled:
    tryWriteBlocking(BracketedPasteDisable)
    terminal.bracketedPasteEnabled = false

# Focus events control
proc enableFocusEvents*(terminal: AsyncTerminal) =
  ## Enable focus event reporting (terminal sends ESC[I/O on focus change).
  ## Best effort - doesn't raise on error.
  if not terminal.focusEventsEnabled:
    tryWriteBlocking(FocusEventsEnable)
    terminal.focusEventsEnabled = true

proc disableFocusEvents*(terminal: AsyncTerminal) =
  ## Disable focus event reporting.
  ## Best effort - doesn't raise on error to ensure cleanup can complete.
  if terminal.focusEventsEnabled:
    tryWriteBlocking(FocusEventsDisable)
    terminal.focusEventsEnabled = false

# Synchronized output control
proc enableSyncOutput*(terminal: AsyncTerminal) =
  ## Enable synchronized output mode (DEC private mode 2026).
  ## Terminal buffers output until mode is disabled, preventing flickering.
  ## Best effort - doesn't raise on error.
  if not terminal.syncOutputEnabled:
    tryWriteBlocking(SyncOutputEnable)
    terminal.syncOutputEnabled = true

proc disableSyncOutput*(terminal: AsyncTerminal) =
  ## Disable synchronized output mode, flushing buffered output.
  ## Best effort - doesn't raise on error to ensure cleanup can complete.
  if terminal.syncOutputEnabled:
    tryWriteBlocking(SyncOutputDisable)
    terminal.syncOutputEnabled = false

# Asynchronous mode toggles.
#
# These are the async twins of the synchronous mode toggles above. They use
# `tryWriteAsync` / `writeOrRaiseAsync` so a flow-controlled tty yields the
# event loop instead of blocking in `pollWritable`. The synchronous versions
# are retained for the synchronous `cleanup` fallback and for the shared
# `restoreSuspendedFeatures` template used by the sync terminal.
proc enableAlternateScreenAsync*(terminal: AsyncTerminal) {.async.} =
  ## Switch to alternate screen buffer asynchronously.
  ## Raises IOError if the sequence cannot be written in full.
  if not terminal.alternateScreen:
    await writeOrRaiseAsync(AlternateScreenEnter)
    terminal.alternateScreen = true

proc disableAlternateScreenAsync*(terminal: AsyncTerminal) {.async.} =
  ## Switch back to main screen buffer asynchronously.
  ## Best effort - doesn't raise on error to ensure cleanup can complete.
  if terminal.alternateScreen:
    await tryWriteAsync(AlternateScreenExit)
    terminal.alternateScreen = false

proc enableMouseAsync*(terminal: AsyncTerminal) {.async.} =
  ## Enable mouse reporting asynchronously.
  ## Best effort - doesn't raise on error.
  if not terminal.mouseEnabled:
    await tryWriteAsync(enableMouseMode(MouseSGR))
    terminal.mouseEnabled = true

proc disableMouseAsync*(terminal: AsyncTerminal) {.async.} =
  ## Disable mouse reporting asynchronously.
  ## Best effort - doesn't raise on error to ensure cleanup can complete.
  if terminal.mouseEnabled:
    await tryWriteAsync(disableMouseMode(MouseSGR))
    terminal.mouseEnabled = false

proc enableBracketedPasteAsync*(terminal: AsyncTerminal) {.async.} =
  ## Enable bracketed paste mode asynchronously.
  ## Best effort - doesn't raise on error.
  if not terminal.bracketedPasteEnabled:
    await tryWriteAsync(BracketedPasteEnable)
    terminal.bracketedPasteEnabled = true

proc disableBracketedPasteAsync*(terminal: AsyncTerminal) {.async.} =
  ## Disable bracketed paste mode asynchronously.
  ## Best effort - doesn't raise on error to ensure cleanup can complete.
  if terminal.bracketedPasteEnabled:
    await tryWriteAsync(BracketedPasteDisable)
    terminal.bracketedPasteEnabled = false

proc enableFocusEventsAsync*(terminal: AsyncTerminal) {.async.} =
  ## Enable focus event reporting asynchronously.
  ## Best effort - doesn't raise on error.
  if not terminal.focusEventsEnabled:
    await tryWriteAsync(FocusEventsEnable)
    terminal.focusEventsEnabled = true

proc disableFocusEventsAsync*(terminal: AsyncTerminal) {.async.} =
  ## Disable focus event reporting asynchronously.
  ## Best effort - doesn't raise on error to ensure cleanup can complete.
  if terminal.focusEventsEnabled:
    await tryWriteAsync(FocusEventsDisable)
    terminal.focusEventsEnabled = false

proc enableSyncOutputAsync*(terminal: AsyncTerminal) {.async.} =
  ## Enable synchronized output mode asynchronously.
  ## Best effort - doesn't raise on error.
  if not terminal.syncOutputEnabled:
    await tryWriteAsync(SyncOutputEnable)
    terminal.syncOutputEnabled = true

proc disableSyncOutputAsync*(terminal: AsyncTerminal) {.async.} =
  ## Disable synchronized output mode asynchronously.
  ## Best effort - doesn't raise on error to ensure cleanup can complete.
  if terminal.syncOutputEnabled:
    await tryWriteAsync(SyncOutputDisable)
    terminal.syncOutputEnabled = false

# Window title control
#
# Each ends with a cooperative `await sleepMs(0)`: `tryWriteAsync` only suspends
# when the write blocks, so on the normal fast-write path it returns without
# yielding; the trailing yield keeps a tight loop of these calls from monopolizing
# the event loop (restores the pre-robust-write-path behavior).
proc setWindowTitleAsync*(title: string) {.async.} =
  ## Set the terminal window title and icon name
  ## Supported by almost all terminal emulators
  await tryWriteAsync(makeWindowTitleSeq(title))
  await sleepMs(0)

proc setIconNameAsync*(name: string) {.async.} =
  ## Set the terminal icon name only
  await tryWriteAsync(makeIconNameSeq(name))
  await sleepMs(0)

proc setTitleOnlyAsync*(title: string) {.async.} =
  ## Set the terminal window title only (not icon name)
  await tryWriteAsync(makeTitleOnlySeq(title))
  await sleepMs(0)

# Async cursor control.
#
# These route through async_io's `tryWriteAsync`/`writeOrRaiseAsync` (the async
# twins of the sync `tryWrite`/`writeOrRaise`) so a truncated control sequence
# on a wedged tty is surfaced instead of silently swallowed by a discarded
# `stdout.flushFile()`. Cursor control is non-critical, so it is best-effort.
#
# Each ends with a cooperative `await sleepMs(0)`: `tryWriteAsync` only suspends
# when the write blocks, so on the normal fast-write path it returns without
# yielding; the trailing yield keeps a tight loop of these calls from monopolizing
# the event loop.
proc hideCursorAsync*() {.async.} =
  ## Hide the cursor asynchronously
  await tryWriteAsync(HideCursorSeq)
  await sleepMs(0)

proc showCursorAsync*() {.async.} =
  ## Show the cursor asynchronously
  await tryWriteAsync(ShowCursorSeq)
  await sleepMs(0)

proc setCursorPositionAsync*(x, y: int) {.async.} =
  ## Set cursor position asynchronously (0-based coordinates; converted to 1-based ANSI coordinates internally)
  await tryWriteAsync(makeCursorPositionSeq(x, y))
  await sleepMs(0)

proc setCursorPositionAsync*(pos: Position) {.async.} =
  ## Set cursor position asynchronously
  await tryWriteAsync(makeCursorPositionSeq(pos))
  await sleepMs(0)

proc showCursorAtAsync*(x, y: int) {.async.} =
  ## Set cursor position and show it asynchronously
  await tryWriteAsync(makeCursorPositionSeq(x, y) & ShowCursorSeq)
  await sleepMs(0)

proc showCursorAtAsync*(pos: Position) {.async.} =
  ## Set cursor position and show it asynchronously
  await tryWriteAsync(makeCursorPositionSeq(pos) & ShowCursorSeq)
  await sleepMs(0)

proc saveCursorAsync*() {.async.} =
  ## Save current cursor position asynchronously
  await tryWriteAsync(SaveCursorSeq)
  await sleepMs(0)

proc restoreCursorAsync*() {.async.} =
  ## Restore previously saved cursor position asynchronously
  await tryWriteAsync(RestoreCursorSeq)
  await sleepMs(0)

proc moveCursorUpAsync*(steps: int = 1) {.async.} =
  ## Move cursor up by specified steps asynchronously
  await tryWriteAsync(makeCursorMoveSeq(CursorUpSeq, steps))
  await sleepMs(0)

proc moveCursorDownAsync*(steps: int = 1) {.async.} =
  ## Move cursor down by specified steps asynchronously
  await tryWriteAsync(makeCursorMoveSeq(CursorDownSeq, steps))
  await sleepMs(0)

proc moveCursorLeftAsync*(steps: int = 1) {.async.} =
  ## Move cursor left by specified steps asynchronously
  await tryWriteAsync(makeCursorMoveSeq(CursorLeftSeq, steps))
  await sleepMs(0)

proc moveCursorRightAsync*(steps: int = 1) {.async.} =
  ## Move cursor right by specified steps asynchronously
  await tryWriteAsync(makeCursorMoveSeq(CursorRightSeq, steps))
  await sleepMs(0)

proc moveCursorAsync*(dx, dy: int) {.async.} =
  ## Move cursor relatively by dx, dy asynchronously.
  ## The vertical and horizontal moves are concatenated into a single
  ## `tryWriteAsync` (one `posix.write`, one trailing yield) rather than
  ## delegating to the per-axis movers, which would emit two writes and yield
  ## the event loop twice for a diagonal move.
  var moveSeq = ""
  if dy < 0:
    moveSeq.add(makeCursorMoveSeq(CursorUpSeq, -dy))
  elif dy > 0:
    moveSeq.add(makeCursorMoveSeq(CursorDownSeq, dy))

  if dx < 0:
    moveSeq.add(makeCursorMoveSeq(CursorLeftSeq, -dx))
  elif dx > 0:
    moveSeq.add(makeCursorMoveSeq(CursorRightSeq, dx))

  if moveSeq.len > 0:
    await tryWriteAsync(moveSeq)
    await sleepMs(0)

proc setCursorStyleAsync*(style: CursorStyle) {.async.} =
  ## Set cursor appearance style asynchronously
  await tryWriteAsync(getCursorStyleSeq(style))
  await sleepMs(0)

# Async screen control.
#
# A truncated screen/line clear leaves the terminal in a corrupt state, so the
# full-screen and full-line clears are critical (`writeOrRaiseAsync`, matching
# the sync `clearScreen`/`clearLine`); the partial-line clear is best-effort
# (matching the sync `clearToStartOfLine` = tryWrite).
#
# Each ends with a cooperative `await sleepMs(0)`: the write helpers only suspend
# when the write blocks, so the trailing yield restores the event-loop fairness
# the pre-robust-write-path versions had on the normal fast-write path.
proc clearScreenAsync*() {.async.} =
  ## Clear the entire screen asynchronously.
  ## Does not move the cursor (matches the synchronous `clearScreen`).
  await writeOrRaiseAsync(ClearScreenSeq)
  await sleepMs(0)

proc clearLineAsync*() {.async.} =
  ## Clear the current line asynchronously
  await writeOrRaiseAsync(ClearLineSeq)
  await sleepMs(0)

proc clearToEndOfLineAsync*() {.async.} =
  ## Clear from cursor to end of line asynchronously
  await writeOrRaiseAsync(ClearToEndOfLineSeq)
  await sleepMs(0)

proc clearToStartOfLineAsync*() {.async.} =
  ## Clear from start of line to cursor asynchronously
  await tryWriteAsync(ClearToStartOfLineSeq)
  await sleepMs(0)

# Async buffer rendering
proc renderCellAsync*(cell: Cell, x, y: int) {.async.} =
  ## Render a single cell at the specified position asynchronously.
  ## Best-effort (matching the sync `renderCell`): a transient tty hiccup is
  ## logged under `-d:celinaDebug` rather than raising. The cursor move, style,
  ## symbol and reset are concatenated into one `tryWriteAsync` so the cell is
  ## emitted atomically (one `posix.write`) instead of four separately-awaited
  ## fragments that another task's output could interleave with.
  ##
  ## Ends with a cooperative `await sleepMs(0)` so a tight loop of cell renders
  ## does not monopolize the event loop (restores the yield that the previous
  ## `setCursorPositionAsync`-based implementation provided).
  let styleSeq = cell.style.toAnsiSequence()

  var output = makeCursorPositionSeq(x, y)
  if styleSeq.len > 0:
    output.add(styleSeq)
  output.add(cell.symbol)
  if styleSeq.len > 0:
    output.add(resetSequence())

  await tryWriteAsync(output)
  await sleepMs(0)

proc renderAsync*(terminal: AsyncTerminal, buffer: Buffer) {.async.} =
  ## Render a buffer to the terminal asynchronously using differential updates
  ## Output is automatically wrapped with synchronized output sequences (DEC mode 2026)
  ## to prevent flickering on supported terminals.
  ##
  ## Low-level API: raises `TerminalError` if the frame cannot be written in full
  ## (a truncated frame on a wedged tty), matching the sync `render`. On failure
  ## `lastBuffer` is left unchanged so the next frame redraws the same diff. The
  ## high-level `AsyncApp` render path goes through `drawWithCursorAdoptAsync`,
  ## which catches this and retries instead of propagating.
  let rawOutput = buildDifferentialOutput(terminal.lastBuffer, buffer)

  if rawOutput.len > 0:
    # Skip wrapping if sync output is already enabled to avoid double-wrapping
    let output =
      if terminal.syncOutputEnabled:
        rawOutput
      else:
        wrapWithSyncOutput(rawOutput)
    try:
      await writeOrRaiseAsync(output)
    except IOError as e:
      raise newTerminalError("Failed to render buffer: " & e.msg)

  # Update last buffer and clear dirty region for next frame
  terminal.lastBuffer = buffer
  terminal.lastBuffer.clearDirty()

proc renderFullAsync*(terminal: AsyncTerminal, buffer: Buffer) {.async.} =
  ## Force a full async render of the buffer
  ## Output is automatically wrapped with synchronized output sequences (DEC mode 2026)
  ## to prevent flickering on supported terminals.
  ##
  ## Low-level API: raises `TerminalError` if the frame cannot be written in full,
  ## matching the sync `renderFull`. On failure `lastBuffer` is left unchanged so
  ## the next frame redraws.
  let rawOutput = buildFullRenderOutput(buffer)
  # Skip wrapping if sync output is already enabled to avoid double-wrapping
  let output =
    if terminal.syncOutputEnabled:
      rawOutput
    else:
      wrapWithSyncOutput(rawOutput)

  try:
    await writeOrRaiseAsync(output)
  except IOError as e:
    raise newTerminalError("Failed to render buffer: " & e.msg)

  # Update last buffer and clear dirty region
  terminal.lastBuffer = buffer
  terminal.lastBuffer.clearDirty()

# Terminal setup and cleanup
proc cleanupAsync*(terminal: AsyncTerminal, reader: AsyncInputReader = nil) {.async.}

proc setupAsync*(terminal: AsyncTerminal, reader: AsyncInputReader = nil) {.async.} =
  ## Setup terminal for CLI mode asynchronously.
  ##
  ## Best-effort atomicity: if a step fails after an earlier one already took
  ## effect, the applied steps are rolled back via `cleanupAsync` before the
  ## error propagates. This keeps the shell from being stranded in the
  ## alternate screen or raw mode after a failed setup.
  try:
    await terminal.enableAlternateScreenAsync()
    terminal.enableRawMode(reader)
    await clearScreenAsync()
    terminal.updateSize()
  except CatchableError as e:
    # `cleanupAsync` is infallible, but guard it defensively so a cleanup
    # failure can never mask the original setup error.
    try:
      await terminal.cleanupAsync(reader)
    except CatchableError:
      discard
    raise e

proc setupWithHiddenCursorAsync*(
    terminal: AsyncTerminal, reader: AsyncInputReader = nil
) {.async.} =
  ## Setup terminal for CLI mode with cursor hidden asynchronously
  await terminal.setupAsync(reader)
  await hideCursorAsync()

proc setupWithMouseAsync*(
    terminal: AsyncTerminal, reader: AsyncInputReader = nil
) {.async.} =
  ## Setup terminal for CLI mode with mouse support asynchronously
  await terminal.setupAsync(reader)
  await terminal.enableMouseAsync()

proc setupWithPasteAsync*(
    terminal: AsyncTerminal, reader: AsyncInputReader = nil
) {.async.} =
  ## Setup terminal for CLI mode with bracketed paste support asynchronously
  await terminal.setupAsync(reader)
  await terminal.enableBracketedPasteAsync()

proc setupWithMouseAndPasteAsync*(
    terminal: AsyncTerminal, reader: AsyncInputReader = nil
) {.async.} =
  ## Setup terminal for CLI mode with mouse and bracketed paste support asynchronously
  await terminal.setupAsync(reader)
  await terminal.enableMouseAsync()
  await terminal.enableBracketedPasteAsync()

proc runDisableSequence(terminal: AsyncTerminal, reader: AsyncInputReader = nil) =
  ## LIFO disable sequence shared by the sync `cleanup`.
  ##
  ## Each step is guarded individually so one failure cannot skip the rest. The
  ## current disable procs are all best-effort and do not raise, but the guard is
  ## kept defensively so a future change to a disable step (or an unexpected
  ## exception from a system call) cannot abort the rest of cleanup.
  template guard(body: untyped) =
    try:
      body
    except CatchableError:
      discard

  guard:
    terminal.disableSyncOutput()
  guard:
    terminal.disableFocusEvents()
  guard:
    terminal.disableBracketedPaste()
  guard:
    terminal.disableMouse()
  guard:
    terminal.disableRawMode(reader)
  guard:
    terminal.disableAlternateScreen()

proc runDisableSequenceAsync(
    terminal: AsyncTerminal, reader: AsyncInputReader = nil
) {.async.} =
  ## LIFO disable sequence for `cleanupAsync`.
  ##
  ## Mirrors `runDisableSequence` but uses async writes so the event loop is not
  ## blocked while waiting for a flow-controlled terminal to drain. Each step is
  ## guarded for the same defensive reason as the sync variant: a failure in one
  ## disable step must not skip the rest of cleanup.
  template guard(body: untyped) =
    try:
      body
    except CatchableError:
      discard

  guard:
    await terminal.disableSyncOutputAsync()
  guard:
    await terminal.disableFocusEventsAsync()
  guard:
    await terminal.disableBracketedPasteAsync()
  guard:
    await terminal.disableMouseAsync()
  guard:
    terminal.disableRawMode(reader)
  guard:
    await terminal.disableAlternateScreenAsync()

proc cleanup*(terminal: AsyncTerminal, reader: AsyncInputReader = nil) =
  ## Synchronous cleanup variant for crash handlers and signal hooks.
  ##
  ## Mirrors `cleanupAsync` but uses blocking writes so it can be invoked when
  ## the async event loop is unavailable. Uses the sync `runDisableSequence`.
  ## `tryWriteBlocking` is best-effort and never raises, so no `try/except` is
  ## needed around the cursor restore.
  tryWriteBlocking(ShowCursorSeq)
  runDisableSequence(terminal, reader)

proc cleanupAsync*(terminal: AsyncTerminal, reader: AsyncInputReader = nil) {.async.} =
  ## Cleanup and restore terminal asynchronously.
  ##
  ## Disable order is the reverse of `setupAsync` (LIFO): raw mode is
  ## restored before leaving the alternate screen so the final `tcsetattr`
  ## runs while the program-mode screen is still active. Mirrors the sync
  ## `terminal.cleanup()` policy — app-level wrappers should delegate here.
  ##
  ## This proc is best-effort and never raises: every step is guarded so a
  ## single failure cannot skip later cleanup steps, matching the infallible
  ## contract of the synchronous `cleanup`.
  try:
    await showCursorAsync()
    await runDisableSequenceAsync(terminal, reader)
  except CatchableError:
    discard

  # AsyncFD cleanup is handled automatically by Chronos
  # No manual unregistration needed

proc isSuspended*(terminal: AsyncTerminal): bool {.inline.} =
  ## Check if terminal is currently suspended
  terminal.suspendState.isSuspended

proc suspendAsync*(terminal: AsyncTerminal, reader: AsyncInputReader = nil) {.async.} =
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
  await showCursorAsync()
  await terminal.disableSyncOutputAsync()
  await terminal.disableFocusEventsAsync()
  await terminal.disableBracketedPasteAsync()
  await terminal.disableMouseAsync()
  terminal.disableRawMode(reader)
  await terminal.disableAlternateScreenAsync()

  terminal.suspendState.isSuspended = true

proc restoreSuspendedFeaturesAsync(terminal: AsyncTerminal) {.async.} =
  ## Restore terminal features from suspend state asynchronously.
  ## Async twin of the shared `restoreSuspendedFeatures` template.
  if terminal.suspendState.suspendedAlternateScreen:
    await terminal.enableAlternateScreenAsync()
  if terminal.suspendState.suspendedRawMode:
    terminal.enableRawMode()
  if terminal.suspendState.suspendedMouseEnabled:
    await terminal.enableMouseAsync()
  if terminal.suspendState.suspendedBracketedPaste:
    await terminal.enableBracketedPasteAsync()
  if terminal.suspendState.suspendedFocusEvents:
    await terminal.enableFocusEventsAsync()
  if terminal.suspendState.suspendedSyncOutput:
    await terminal.enableSyncOutputAsync()

proc resumeAsync*(terminal: AsyncTerminal, reader: AsyncInputReader = nil) {.async.} =
  ## Resume terminal after suspend, restoring program mode
  ##
  ## Restores terminal state that was saved by `suspendAsync()`.
  ## After resume, call `drawAsync(buffer, force = true)` to redraw the screen.
  ##
  ## When `reader` is non-nil, drops any UTF-8 resync byte that may have
  ## accumulated during suspend, mirroring the `enableRawMode(reader)`
  ## contract so the pending-byte invariant survives the round trip.
  if not terminal.isSuspended:
    return # Not suspended

  # Restore saved state. `restoreSuspendedFeaturesAsync` is the async twin of
  # the shared `restoreSuspendedFeatures` template; it cannot thread the reader
  # through its internal `enableRawMode()` call — that call clears no pending
  # byte. We compensate by clearing explicitly here; if the template ever starts
  # forwarding a reader, this fallback becomes a harmless double-clear.
  await restoreSuspendedFeaturesAsync(terminal)
  if not reader.isNil:
    reader.clearPendingByteAsync()
  await hideCursorAsync()

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
  ## Draw an AsyncBuffer to the terminal asynchronously.
  ## Passes the live grid by reference (no per-frame snapshot copy); the
  ## underlying `drawAsync(Buffer)` keeps copy semantics for `lastBuffer`.
  asyncBuffer.withBuffer:
    await terminal.drawAsync(buffer, force)

proc buildCursorFrame(
    terminal: AsyncTerminal,
    buffer: Buffer,
    cursorX, cursorY: int,
    cursorVisible: bool,
    cursorStyle: CursorStyle,
    lastCursorStyle: CursorStyle,
    force: bool,
): tuple[output: string, style: CursorStyle] =
  ## Build the cursor-positioned frame bytes from `terminal.lastBuffer` and
  ## `buffer`. Synchronous on purpose: it lets the caller commit `lastBuffer`
  ## without an `await` ever sitting between reading the live grid and adopting
  ## it, which preserves the async_buffer single-coroutine invariant ("async
  ## procs do not await between buffer access and yield points"). `output` is the
  ## wrapped, ready-to-write sequence ("" when the frame has no changes); `style`
  ## is the new cursor style. `buffer` is read-only (hidden reference, no copy).
  let (rawOutput, newLastCursorStyle) = buildOutputWithCursor(
    terminal.lastBuffer, buffer, cursorX, cursorY, cursorVisible, cursorStyle,
    lastCursorStyle, force,
  )
  result.style = newLastCursorStyle
  if rawOutput.len == 0:
    result.output = ""
  elif terminal.syncOutputEnabled:
    # Skip wrapping if sync output is already enabled to avoid double-wrapping
    result.output = rawOutput
  else:
    # Wrap with synchronized output to prevent flickering
    result.output = wrapWithSyncOutput(rawOutput)

proc drawWithCursorAsync*(
    terminal: AsyncTerminal,
    buffer: Buffer,
    cursorX, cursorY: int,
    cursorVisible: bool,
    cursorStyle: CursorStyle = CursorStyle.Default,
    lastCursorStyle: CursorStyle,
    force: bool = false,
): Future[CursorStyle] {.async.} =
  ## Draw a buffer with cursor positioning in a single write operation.
  ## This prevents cursor flickering by including cursor commands in the same output
  ##
  ## Output is automatically wrapped with synchronized output sequences (DEC mode 2026)
  ## to prevent flickering on supported terminals.
  ##
  ## The buffer's contents are preserved across the call (copy semantics). For a
  ## zero-copy renderer-owned hot path, use `drawWithCursorAdoptAsync`.
  ##
  ## A truncated frame on a wedged tty (the `IOError` from `writeOrRaiseAsync`) is
  ## swallowed so a transient hiccup never crashes the async render loop (mirrors
  ## the sync `Terminal.drawWithCursor`); on failure `lastBuffer` is left
  ## unchanged so the next frame retries the same diff.
  ##
  ## Returns the updated lastCursorStyle value on success, or the original
  ## `lastCursorStyle` on failure. Caller is responsible for tracking this state
  ## (e.g., via CursorManager.updateLastStyle()).
  let (output, style) = terminal.buildCursorFrame(
    buffer, cursorX, cursorY, cursorVisible, cursorStyle, lastCursorStyle, force
  )
  var ok = true
  if output.len > 0:
    try:
      await writeOrRaiseAsync(output)
    except CatchableError as e:
      when defined(celinaDebug):
        stderr.writeLine("Warning: drawWithCursorAsync() failed: " & e.msg)
      else:
        discard e # Avoid "declared but not used" warning
      ok = false
  if ok:
    terminal.lastBuffer = buffer
    terminal.lastBuffer.clearDirty()
    return style
  # Write failed: the terminal state is unchanged, so keep lastCursorStyle.
  return lastCursorStyle

proc drawWithCursorAdoptAsync*(
    terminal: AsyncTerminal,
    asyncBuffer: async_buffer.AsyncBuffer,
    cursorX, cursorY: int,
    cursorVisible: bool,
    cursorStyle: CursorStyle = CursorStyle.Default,
    lastCursorStyle: CursorStyle,
    force: bool = false,
): Future[CursorStyle] {.async.} =
  ## Zero-copy variant of `drawWithCursorAsync` for renderer-owned AsyncBuffers.
  ##
  ## The freshly rendered grid is swapped into the terminal's `lastBuffer` and
  ## the previous frame's storage is recycled back into `asyncBuffer` (no
  ## per-frame snapshot copy). The caller must therefore fully re-fill
  ## `asyncBuffer` each frame — `AsyncApp.renderAsync` does this via
  ## `renderer.clear()`. The buffer is passed as a `ref` (an `AsyncBuffer`)
  ## rather than `var Buffer` because `{.async.}` procs cannot capture `var`
  ## parameters.
  ##
  ## The frame bytes are built synchronously and `lastBuffer` is committed
  ## *before* the write, so no `await` sits between reading the live grid and
  ## adopting it: a concurrent task that mutates `asyncBuffer` during a
  ## flow-controlled write can no longer desync `lastBuffer` from the bytes
  ## actually emitted. On the steady-state path (areas match) the commit is a
  ## zero-copy swap rolled back if the write fails; on the first frame / right
  ## after a resize (areas differ) `adoptLastBufferImpl` copies anyway, so the
  ## plain write-then-adopt order is kept (the caller forces a full redraw next
  ## frame, which masks the rare write-failure window there).
  ##
  ## Returns the updated lastCursorStyle value on success, or the original
  ## `lastCursorStyle` on failure.
  asyncBuffer.withBuffer:
    # `buffer` aliases `asyncBuffer.buffer` (the live grid).
    let (output, style) = terminal.buildCursorFrame(
      buffer, cursorX, cursorY, cursorVisible, cursorStyle, lastCursorStyle, force
    )
    result = style

    if output.len == 0:
      # No changes: adopt (recycle storage) without writing.
      terminal.adoptLastBufferImpl(buffer)
      return

    if terminal.lastBuffer.area == buffer.area:
      # Steady state: commit by swap BEFORE the write. `buffer` then aliases the
      # recycled previous frame, so a concurrent mutation during the write lands
      # there (the caller re-fills it next frame) and cannot corrupt `lastBuffer`.
      swap(terminal.lastBuffer, buffer)
      terminal.lastBuffer.clearDirty()
      try:
        await writeOrRaiseAsync(output)
      except CatchableError as e:
        # Roll the swap back so a failed frame leaves `lastBuffer` as the frame
        # still on screen and the next frame retries the same diff.
        swap(terminal.lastBuffer, buffer)
        terminal.lastBuffer.clearDirty()
        # The terminal never received the new DECSCUSR sequence, so the tracked
        # cursor style must stay unchanged too.
        result = lastCursorStyle
        when defined(celinaDebug):
          stderr.writeLine("Warning: drawWithCursorAdoptAsync() failed: " & e.msg)
        else:
          discard e # Avoid "declared but not used" warning
    else:
      # First frame / post-resize: areas differ, so the adopt copies anyway (no
      # zero-copy to protect) and the caller forces a full redraw next frame.
      try:
        await writeOrRaiseAsync(output)
        terminal.adoptLastBufferImpl(buffer)
      except CatchableError as e:
        # Keep lastBuffer unchanged so the next frame can retry the diff.
        # The cursor style was never applied either.
        result = lastCursorStyle
        when defined(celinaDebug):
          stderr.writeLine("Warning: drawWithCursorAdoptAsync() failed: " & e.msg)
        else:
          discard e # Avoid "declared but not used" warning

# Terminal state queries
# Note: getSize and getArea need explicit proc definitions to avoid conflicts
# with async_buffer.getSize in async_app.nim.

proc getSize*(terminal: AsyncTerminal): Size {.inline.} =
  ## Get current terminal size
  terminal.size

proc getArea*(terminal: AsyncTerminal): Rect {.inline.} =
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
