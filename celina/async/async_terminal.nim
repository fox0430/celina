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
import ../core/[geometry, colors, buffer, terminal_common, errors, screen_state]
from async_io import
  AsyncInputReader, clearPendingByteAsync, tryWriteAsync, writeOrRaiseAsync,
  writeStdoutAsync, tryWriteBlocking, writeOrRaiseBlocking, withStdoutLock
from ../core/output_stream import
  swAll, swPartial, srAbort, srOsc8, srSgr, srSyncEnd, outcomeOf, setPendingReset,
  writeStreamLocked

type
  AsyncTerminal* = ref object ## Async terminal interface for screen management
    size*: Size
    alternateScreen*: bool
    rawMode*: bool
    mouseEnabled*: bool
    bracketedPasteEnabled*: bool
    focusEventsEnabled*: bool
    syncOutputEnabled*: bool
    screen: ScreenState ## what the screen shows; see screen_state.nim
    stdinFd*: AsyncFD
    stdoutFd*: AsyncFD
    rawModeEnabled: bool # Track raw mode state internally
    originalTermios: Termios # Store original terminal settings per instance
    suspendState: SuspendState

  AsyncTerminalError* = object of CatchableError

proc lastBuffer*(terminal: AsyncTerminal): var Buffer {.inline.} =
  ## The frame the terminal shows while the screen is known. Writable, as in
  ## v0.13.0: assigning it, or a buffer of another size to force a redraw,
  ## still compiles.
  terminal.screen.lastBuffer

proc `lastBuffer=`*(terminal: AsyncTerminal, buffer: Buffer) {.inline.} =
  ## Assignment half of `lastBuffer`. Needed separately because a `var` return
  ## alone is not an assignment target on Nim 2.0.x.
  terminal.screen.lastBuffer = buffer

proc invalidate*(terminal: AsyncTerminal) =
  ## Mark the screen unknown, so the next frame is a full render. Call it
  ## after writing to the screen behind celina's back: the free
  ## `clearScreenAsync()`, `clearLineAsync` and `renderCellAsync`, or another
  ## program taking the terminal (`suspendAsync` does it for you).
  terminal.screen.invalidate()

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

  # A blank `lastBuffer` at the current size. The screen starts out unknown,
  # so the first frame renders in full unless `setupAsync`'s clear made it known
  # (it records a blank screen, which is what a diff then needs).
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

# Asynchronous mode toggles. Async twins of the sync toggles above;
# the sync versions remain for the `cleanup` fallback and `restoreSuspendedFeatures`.
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
# Trailing `await sleepMs(0)` keeps tight loops from monopolizing the event loop.
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

# Async cursor control. Best-effort via `tryWriteAsync`/`writeOrRaiseAsync`.
# Trailing `await sleepMs(0)` keeps tight loops from monopolizing the event loop.
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

# Async screen control. Full clears are critical (`writeOrRaiseAsync`);
# partial-line clear is best-effort (mirrors the sync split).
proc clearScreenAsync*() {.async.} =
  ## Clear the entire screen asynchronously.
  ## Does not move the cursor (matches the synchronous `clearScreen`).
  ##
  ## Does not update an `AsyncTerminal`'s `lastBuffer`, so a later draw diffs
  ## against content that is gone. Use `terminal.clearScreenAsync()` when
  ## drawing, or `terminal.invalidate()` when the next frame must not be a diff.
  await writeOrRaiseAsync(ClearScreenSeq)
  await sleepMs(0)

proc clearScreenAsync*(terminal: AsyncTerminal) {.async.} =
  ## Clear the entire screen asynchronously and record it as blank, so the
  ## next draw writes only the cells that are not blank. Resets SGR first, and
  ## the output stream sends the reset of a cut write first. Does not move the
  ## cursor (matches the synchronous `Terminal.clearScreen`).
  ##
  ## Raises IOError if the clear cannot be written in full. A clear that sent
  ## nothing keeps the screen known; a partial one leaves it unknown, so the
  ## next draw is a full render. A cancel propagates and has the same effect.
  withStdoutLock:
    var plan = terminal.screen.planClear(terminal.size)
    var outcome = swPartial # a cancel mid-write counts as partial
    try:
      let written = await writeStreamLocked(plan.bytes, plan.onPartial)
      outcome = outcomeOf(written, plan.bytes.len)
    finally:
      terminal.screen.finishClear(plan, outcome)
    if outcome != swAll:
      raise
        newException(IOError, "Terminal write failed (" & $plan.bytes.len & " bytes)")
  # Yield, as the other write helpers do: a clear that neither blocks nor finds
  # the lock held would otherwise never suspend.
  await sleepMs(0)

proc clearLineAsync*() {.async.} =
  ## Clear the current line asynchronously
  ##
  ## Does not update an `AsyncTerminal`'s `lastBuffer`: call
  ## `terminal.invalidate()` if the next draw must not be a diff against it.
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

# The frame protocol, in one place per backend: plan, write, record. Each public
# entry point is a wrapper that picks its options and maps the outcome (raise, or
# ignore and keep the previous cursor style).
#
# Planning, writing and recording happen under one hold of the stdout lock, so a
# frame is built against the screen state the previous writer left: a writer that
# failed partway makes the frame that waited behind it a full render, and two
# concurrent draws cannot leave a diff built against a `lastBuffer` that another
# task has since replaced. There is no `except` here, so a chronos cancel
# propagates to the caller; the screen state still records the partial write.

proc presentFrame(
    terminal: AsyncTerminal,
    buffer: Buffer,
    cursor: CursorRequest,
    force: bool,
    wrap: bool,
): Future[Presented] {.async.} =
  ## Plan, write and record one frame of `buffer`, whose content the caller
  ## keeps (copy semantics). `force` marks the screen unknown first, so the
  ## frame is a full render. A building error happens before any byte goes out,
  ## so no write is recorded; the one state change it can leave behind is the
  ## `force` invalidate, which runs before the plan.
  var
    outcome = swPartial # a cancel mid-write counts as a partial write
    style = cursor.lastStyle
  withStdoutLock:
    if force:
      terminal.screen.invalidate()
    var plan = terminal.screen.planFrame(buffer, cursor, wrap)
    try:
      let written = await writeStreamLocked(plan.bytes, plan.onPartial)
      outcome = outcomeOf(written, plan.bytes.len)
    finally:
      # No `await` in here: a `finally` that suspends cannot be nested in
      # `withStdoutLock`'s own.
      terminal.screen.finish(plan, buffer, outcome)
    style = plan.appliedStyle(outcome)
  Presented(outcome: outcome, style: style)

proc presentFrameAdopt(
    terminal: AsyncTerminal,
    asyncBuffer: async_buffer.AsyncBuffer,
    cursor: CursorRequest,
    force: bool,
    wrap: bool,
): Future[Presented] {.async.} =
  ## `presentFrame` for the live grid of a renderer-owned `AsyncBuffer`, which
  ## the caller re-fills every frame. The frame is adopted into `lastBuffer`
  ## before the write (a `swap` in the steady state) and handed back to
  ## `asyncBuffer` on failure, so a task that mutates the grid during a
  ## flow-controlled write cannot desync `lastBuffer` from the bytes that went
  ## out. A staged write that sent nothing is handed back too, but counts as a
  ## failure for the screen state: the grid was in play during the write, so
  ## the next frame is a full render.
  var
    outcome = swPartial # a cancel mid-write counts as a partial write
    style = cursor.lastStyle
  withStdoutLock:
    asyncBuffer.withBuffer:
      if force:
        terminal.screen.invalidate()
      var plan = terminal.screen.planFrame(buffer, cursor, wrap)
      terminal.screen.stage(plan, buffer)
      try:
        let written = await writeStreamLocked(plan.bytes, plan.onPartial)
        outcome = outcomeOf(written, plan.bytes.len)
      finally:
        terminal.screen.finishAdopt(plan, buffer, outcome)
      style = plan.appliedStyle(outcome)
  Presented(outcome: outcome, style: style)

proc renderAsync*(terminal: AsyncTerminal, buffer: Buffer) {.async.} =
  ## Render a buffer to the terminal asynchronously using differential updates
  ## Output is automatically wrapped with synchronized output sequences (DEC mode 2026)
  ## to prevent flickering on supported terminals, unless the app enabled that
  ## mode itself.
  ##
  ## Low-level API: raises `TerminalError` if the frame cannot be written in full
  ## (a truncated frame on a wedged tty), matching the sync `render`. A partial
  ## or cancelled write leaves the screen unknown, so the next frame renders in
  ## full; one that sent nothing keeps it known. The high-level `AsyncApp` render
  ## path goes through `drawWithCursorAdoptAsync`, which ignores the failure and
  ## retries instead of propagating.
  let presented =
    await terminal.presentFrame(buffer, noCursor, false, not terminal.syncOutputEnabled)
  if presented.outcome != swAll:
    raise newTerminalError("Failed to render buffer: terminal write truncated")

proc renderFullAsync*(terminal: AsyncTerminal, buffer: Buffer) {.async.} =
  ## Force a full async render of the buffer
  ## Output is automatically wrapped with synchronized output sequences (DEC mode 2026)
  ## to prevent flickering on supported terminals, unless the app enabled that
  ## mode itself.
  ##
  ## Low-level API: raises `TerminalError` if the frame cannot be written in full,
  ## matching the sync `renderFull`. A partial or cancelled write leaves the
  ## screen unknown.
  let presented =
    await terminal.presentFrame(buffer, noCursor, true, not terminal.syncOutputEnabled)
  if presented.outcome != swAll:
    raise newTerminalError("Failed to render full buffer: terminal write truncated")

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
    # Size first: the clear records a blank screen at the current size.
    terminal.updateSize()
    await terminal.clearScreenAsync()
  except CatchableError as e:
    # Report the setup error, not a cancel from cleanup.
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
  ## LIFO disable sequence shared by the sync `cleanup`. A mode added here
  ## belongs in `EmergencyResetSeq` too.
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

proc cleanup*(terminal: AsyncTerminal, reader: AsyncInputReader = nil) =
  ## Synchronous cleanup variant for a crash hook or an unhandled-exception
  ## hook, where the event loop is unavailable.
  ##
  ## Mirrors `cleanupAsync` but uses blocking writes. Uses the sync
  ## `runDisableSequence`. `tryWriteBlocking` is best-effort and never raises,
  ## so no `try/except` is needed around the cursor restore. The first write
  ## sends the reset a cut frame needs, so nothing has to be prepended here.
  ##
  ## A signal handler must use `emergencyRestore` instead: it writes straight to
  ## the fd, which a signal handler needs. See `Terminal.emergencyRestore`.
  tryWriteBlocking(ShowCursorSeq)
  runDisableSequence(terminal, reader)

proc clearModeFlags(terminal: AsyncTerminal) =
  ## Mark the modes `EmergencyResetSeq` turns off as disabled.
  terminal.syncOutputEnabled = false
  terminal.focusEventsEnabled = false
  terminal.bracketedPasteEnabled = false
  terminal.mouseEnabled = false

proc disableRawModeQuietly(terminal: AsyncTerminal, reader: AsyncInputReader) =
  # disableRawMode can raise from its celinaDebug stderr warnings.
  try:
    terminal.disableRawMode(reader)
  except CatchableError:
    discard

proc emergencyRestore*(terminal: AsyncTerminal, reader: AsyncInputReader = nil) =
  ## Restore the terminal from a signal handler or crash hook, where a frame
  ## may have been cut off mid-write. See `Terminal.emergencyRestore`.
  ## Keeps the LIFO order: the modes go off first, then raw mode, then the
  ## alternate screen. A mode flag is cleared only once its disable went out
  ## in full, so a later cleanup retries a failed one. The screen is marked
  ## unknown, so a caller that keeps drawing after this redraws in full. Never
  ## raises.
  terminal.screen.invalidate()
  let fd = cint(STDOUT_FILENO)
  if writeAllBlocking(fd, EmergencyResetSeq) == EmergencyResetSeq.len:
    terminal.clearModeFlags()
  terminal.disableRawModeQuietly(reader)
  if terminal.alternateScreen:
    if writeAllBlocking(fd, EmergencyAltScreenTail) == EmergencyAltScreenTail.len:
      terminal.alternateScreen = false

when hasChronos:
  proc emergencyRestoreAsync(
      terminal: AsyncTerminal, reader: AsyncInputReader
  ) {.async.} =
    ## `emergencyRestore` through the async stdout lock, for a cancelled
    ## `cleanupAsync`. Like the blocking twin it marks the screen unknown, so a
    ## caller that keeps drawing after this redraws in full — it matters most
    ## here, where the alternate screen is left. Never raises.
    terminal.screen.invalidate()
    try:
      if (await writeStdoutAsync(EmergencyResetSeq)) == EmergencyResetSeq.len:
        terminal.clearModeFlags()
    except CatchableError:
      discard
    terminal.disableRawModeQuietly(reader)
    # Rechecked: a blocking fallback in `cleanupAsync` may have left it already.
    if terminal.alternateScreen:
      try:
        if (await writeStdoutAsync(EmergencyAltScreenTail)) == EmergencyAltScreenTail.len:
          terminal.alternateScreen = false
      except CatchableError:
        discard

proc cleanupStepsAsync(terminal: AsyncTerminal, reader: AsyncInputReader) {.async.} =
  ## The ordered steps of `cleanupAsync`. Each is guarded so a failure cannot
  ## skip the rest; only `CancelledError` propagates.
  template step(body: untyped) =
    try:
      body
    except CancelledError as e:
      raise e
    except CatchableError:
      discard

  step:
    await showCursorAsync()
  step:
    await terminal.disableSyncOutputAsync()
  step:
    await terminal.disableFocusEventsAsync()
  step:
    await terminal.disableBracketedPasteAsync()
  step:
    await terminal.disableMouseAsync()
  step:
    terminal.disableRawMode(reader)
  step:
    await terminal.disableAlternateScreenAsync()

proc cleanupAsync*(terminal: AsyncTerminal, reader: AsyncInputReader = nil) {.async.} =
  ## Cleanup and restore terminal asynchronously.
  ##
  ## Disable order is the reverse of `setupAsync` (LIFO): raw mode is
  ## restored before leaving the alternate screen so the final `tcsetattr`
  ## runs while the program-mode screen is still active. Mirrors the sync
  ## `terminal.cleanup()` policy — app-level wrappers should delegate here.
  ## A mode added here belongs in `EmergencyResetSeq` too. The first write
  ## sends the reset a cut frame needs, so nothing has to be prepended here.
  ##
  ## Raises only on cancellation. A chronos cancel replaces the remaining
  ## steps with the emergency reset, then re-raises. A second cancel during
  ## that reset falls back to a blocking write (up to ~2s, bypassing the
  ## stdout lock), since the caller may exit before a background reset runs.
  when hasChronos:
    try:
      await cleanupStepsAsync(terminal, reader)
    except CancelledError as e:
      let restore = terminal.emergencyRestoreAsync(reader)
      try:
        await restore.join()
      except CancelledError:
        restore.cancelSoon()
        terminal.emergencyRestore(reader)
      raise e
  else:
    await cleanupStepsAsync(terminal, reader)

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

  # Another program gets the terminal, so whatever it does with it is not
  # `lastBuffer`.
  terminal.screen.invalidate()

  # Save current state
  saveSuspendState(terminal)

  # Return to shell mode. A mode added here belongs in `EmergencyResetSeq` too.
  # The first write sends the reset a cut frame needs, so nothing is prepended.
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
  ## Restores terminal state that was saved by `suspendAsync()`. The screen is
  ## marked unknown here, so the next `drawAsync` is a full redraw; no `force`
  ## needed.
  ##
  ## When `reader` is non-nil, drops any UTF-8 resync byte that may have
  ## accumulated during suspend, mirroring the `enableRawMode(reader)`
  ## contract so the pending-byte invariant survives the round trip.
  if not terminal.isSuspended:
    return # Not suspended

  # Another program had the terminal, so whatever it showed is not
  # `lastBuffer`. Marked again rather than only in `suspendAsync`: a frame
  # drawn while the terminal was handed over would otherwise put the screen
  # back to known, and the epoch bump also stops a frame in flight across this
  # point from claiming the screen.
  terminal.screen.invalidate()

  # Another program had the terminal and may have left a sequence or an OSC 8
  # link open, may have left attributes set, or may have left a synchronized
  # output block celina wrapped open, so the first write after this resets all
  # of that. The SGR reset is what a hand back without a frame in between needs:
  # nothing else restores the attributes, and the next frame is not guaranteed.
  setPendingReset({srAbort, srOsc8, srSgr, srSyncEnd})

  # Restore saved state. `restoreSuspendedFeaturesAsync` is the async twin of
  # the shared `restoreSuspendedFeatures` template; it cannot thread the reader
  # through its internal `enableRawMode()` call — that call clears no pending
  # byte. We compensate by clearing explicitly here; if the template ever starts
  # forwarding a reader, this fallback becomes a harmless double-clear.
  await restoreSuspendedFeaturesAsync(terminal)
  if not reader.isNil:
    reader.clearPendingByteAsync()
  await hideCursorAsync()

  terminal.suspendState.isSuspended = false

# High-level async rendering interface
#
# Every draw path is a wrapper around `presentFrame`/`presentFrameAdopt`: it
# picks the options (cursor handling, force, the DEC 2026 wrap, copy vs adopt)
# and maps the outcome. A failed write is ignored here, so a transient terminal
# hiccup never crashes the async render loop; the screen state records it, so
# the next frame is a full render.

proc drawAsync*(
    terminal: AsyncTerminal, buffer: Buffer, force: bool = false
): Future[void] {.async.} =
  ## Draw a buffer to the terminal asynchronously.
  ##
  ## Output is wrapped with synchronized output sequences (DEC mode 2026) unless
  ## the app enabled that mode itself.
  ##
  ## Raises `TerminalError` if the frame cannot be written in full, as
  ## `renderAsync` does (unlike `drawWithCursorAsync`, which ignores it).
  let presented =
    await terminal.presentFrame(buffer, noCursor, force, not terminal.syncOutputEnabled)
  if presented.outcome != swAll:
    raise newTerminalError("Failed to draw buffer: terminal write truncated")

proc drawAsync*(
    terminal: AsyncTerminal, asyncBuffer: async_buffer.AsyncBuffer, force: bool = false
): Future[void] {.async.} =
  ## Draw an AsyncBuffer to the terminal asynchronously.
  ## Passes the live grid by reference (no per-frame snapshot copy); the
  ## underlying `drawAsync(Buffer)` keeps copy semantics for `lastBuffer`.
  asyncBuffer.withBuffer:
    await terminal.drawAsync(buffer, force)

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
  ## A truncated frame on a wedged tty is ignored so a transient hiccup never
  ## crashes the async render loop (mirrors the sync `Terminal.drawWithCursor`);
  ## a write that stopped partway marks the screen unknown, so the next frame is
  ## a full render. One that sent nothing keeps the screen known, and the next
  ## frame is the same diff again.
  ##
  ## A chronos cancel is not a hiccup: it propagates, so a `cancelAndWait`
  ## shutdown sees it, and the screen state records the partial write.
  ##
  ## Returns the updated lastCursorStyle value on success, or the original
  ## `lastCursorStyle` on failure. Caller is responsible for tracking this state
  ## (e.g., via CursorManager.updateLastStyle()).
  let presented = await terminal.presentFrame(
    buffer,
    CursorRequest(
      enabled: true,
      x: cursorX,
      y: cursorY,
      visible: cursorVisible,
      style: cursorStyle,
      lastStyle: lastCursorStyle,
    ),
    force,
    not terminal.syncOutputEnabled,
  )
  when defined(celinaDebug):
    if presented.outcome == swPartial:
      stderr.writeLine("Warning: drawWithCursorAsync() left the screen unknown")
  presented.style

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
  ## The frame is adopted before the write and handed back on a partial or
  ## cancelled write, so a concurrent task that mutates `asyncBuffer` during a
  ## flow-controlled write can no longer desync `lastBuffer` from the bytes
  ## actually emitted. A write that stopped partway, was cancelled, or sent
  ## nothing marks the screen unknown, so the next frame is a full render (for
  ## a write that sent nothing, the grid was in play during the write).
  ##
  ## Returns the updated lastCursorStyle value on success, or the original
  ## `lastCursorStyle` on failure.
  let presented = await terminal.presentFrameAdopt(
    asyncBuffer,
    CursorRequest(
      enabled: true,
      x: cursorX,
      y: cursorY,
      visible: cursorVisible,
      style: cursorStyle,
      lastStyle: lastCursorStyle,
    ),
    force,
    not terminal.syncOutputEnabled,
  )
  when defined(celinaDebug):
    if presented.outcome == swPartial:
      stderr.writeLine("Warning: drawWithCursorAdoptAsync() left the screen unknown")
  presented.style

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
  ## Template for convenient async terminal usage with automatic cleanup.
  ##
  ## A cancel during cleanup is dropped if the body raised, so it cannot
  ## replace the body's error; otherwise it propagates, so code after this
  ## block does not keep running.
  await terminal.setupAsync()
  var bodyRaised = false
  try:
    body
  except CatchableError as e:
    bodyRaised = true
    raise e
  finally:
    if bodyRaised:
      try:
        await terminal.cleanupAsync()
      except CancelledError:
        discard
    else:
      await terminal.cleanupAsync()
