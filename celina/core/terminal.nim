## Terminal interface
##
## This module provides terminal control and rendering capabilities
## using ANSI escape sequences for POSIX systems (Linux, macOS, etc.).
##
## **Important**: This module exports global cursor functions like `showCursor()`,
## `hideCursor()`, and `setCursorStyle()`. These write directly to the terminal
## and do **not** integrate with the `App`/`Renderer` cursor state.
##
## When using `App`, control the cursor via the app instance instead:
## ```nim
## app.onRender proc(buffer: var Buffer) =
##   app.showCursorAt(x, y)      # Correct - uses renderer state
##   app.setCursorStyle(Bar)     # Correct
##   # showCursor()              # Wrong - bypasses renderer
## ```

import std/[termios, posix]

import geometry, colors, buffer, errors, terminal_common, screen_state
from output_stream import
  StreamReset, swAll, swPartial, srAbort, srOsc8, srSgr, srSyncEnd, outcomeOf,
  sendPendingReset, markPartialWrite, writeStream, setPendingReset
from events import clearPendingByte, clearInputClosed, setStdinNonBlockingPinned

export errors.TerminalError

type Terminal* = ref object ## Terminal interface for screen management
  size*: Size
  alternateScreen*: bool
  rawMode*: bool
  mouseEnabled*: bool
  bracketedPasteEnabled*: bool
  focusEventsEnabled*: bool
  syncOutputEnabled*: bool
  screen: ScreenState ## what the screen shows; see screen_state.nim
  rawModeEnabled: bool # Track raw mode state internally
  originalTermios: Termios # Store original terminal settings per instance
  originalStdinFlags: cint # Saved stdin descriptor flags (for O_NONBLOCK restore)
  stdinFlagsSaved: bool # Whether originalStdinFlags holds a captured value
  suspendState: SuspendState

proc lastBuffer*(terminal: Terminal): var Buffer {.inline.} =
  ## The frame the terminal shows while the screen is known. Writable, as in
  ## v0.13.0: assigning it, or a buffer of another size to force a redraw,
  ## still compiles.
  terminal.screen.lastBuffer

proc `lastBuffer=`*(terminal: Terminal, buffer: Buffer) {.inline.} =
  ## Assignment half of `lastBuffer`. Needed separately because a `var` return
  ## alone is not an assignment target on Nim 2.0.x.
  terminal.screen.lastBuffer = buffer

proc invalidate*(terminal: Terminal) =
  ## Mark the screen unknown, so the next frame is a full render. Call it
  ## after writing to the screen behind celina's back: the free
  ## `clearScreen()`, `clearLine` and `renderCell`, or another program taking
  ## the terminal (`suspend` does it for you).
  terminal.screen.invalidate()

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

proc getSize*(terminal: Terminal): Size =
  ## Get current terminal size
  terminal.size

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
  ##
  ## **Threading**: must be paired with `disableRawMode` on the *same thread*.
  ## Event readers consult a thread-local pin flag (`stdinNonBlockingPinned`)
  ## to skip per-tick fcntl probes. Calling `disableRawMode` from a different
  ## thread would clear the global stdin O_NONBLOCK state without clearing
  ## the pin flag on the enabling thread, causing subsequent `pollKey`/
  ## `readKeyInput` calls there to issue blocking reads against a
  ## now-blocking stdin and hang.
  if terminal.rawModeEnabled:
    return # Already enabled

  try:
    checkSystemCallVoid(
      tcgetattr(STDIN_FILENO, addr terminal.originalTermios),
      "Failed to get terminal attributes",
    )

    var raw = terminal.originalTermios
    applyTerminalConfig(raw, getRawModeConfig())

    checkSystemCallVoid(
      tcsetattr(STDIN_FILENO, TCSAFLUSH, addr raw), "Failed to set raw mode"
    )
    # Capture stdin descriptor flags once and ensure O_NONBLOCK holds for the
    # lifetime of raw mode. Per-call toggling in readKeyInput is a TOCTOU race
    # against any other code that touches stdin flags, and burns up to 3
    # fcntl(2) calls per tick. Setting the pin flag here lets event readers
    # short-circuit to zero fcntl calls per tick on the in-App fast path.
    # `pollKey` delegates to `readKeyInput`, so the same fast path covers it.
    #
    # The pin flag means "event readers may assume stdin is non-blocking for
    # the duration of raw mode" — it does not necessarily mean *this* call
    # was the one that set O_NONBLOCK. If stdin was already non-blocking when
    # we entered (e.g. the host application set it for its own reasons), we
    # adopt that state and still raise the pin so readers benefit; the
    # original flags are restored verbatim on disableRawMode either way.
    let curFlags = fcntl(STDIN_FILENO, F_GETFL)
    if curFlags != -1:
      terminal.originalStdinFlags = curFlags
      terminal.stdinFlagsSaved = true
      if (curFlags and O_NONBLOCK) == 0:
        if fcntl(STDIN_FILENO, F_SETFL, curFlags or O_NONBLOCK) == -1:
          when defined(celinaDebug):
            stderr.writeLine(
              "Warning: failed to pin stdin O_NONBLOCK (errno=" & $errno & ")"
            )
        else:
          # We promoted stdin to non-blocking; raise the pin so readers skip
          # their per-tick fcntl probe.
          setStdinNonBlockingPinned(true)
      else:
        # stdin was already non-blocking before raw mode; adopt that state
        # and raise the pin so readers skip their per-tick fcntl probe. The
        # original flags are still saved and will be restored verbatim, so
        # this is non-destructive even though we did not change anything.
        setStdinNonBlockingPinned(true)
    else:
      when defined(celinaDebug):
        stderr.writeLine(
          "Warning: failed to read stdin flags for raw-mode pin (errno=" & $errno &
            "); event readers will fall back to per-tick fcntl toggling"
        )
    terminal.rawMode = true
    terminal.rawModeEnabled = true
    # Drop any UTF-8 resync byte buffered before mode transition so it
    # cannot leak across modes as a phantom keypress.
    clearPendingByte()
    # Raw mode took, so stdin is a live terminal; an earlier end is stale.
    clearInputClosed()
  except CatchableError as e:
    raise newTerminalError("Failed to enable raw mode: " & e.msg)

proc disableRawMode*(terminal: Terminal) =
  ## Disable raw mode, restoring original terminal settings
  ## Best effort - doesn't raise on error to ensure cleanup
  ##
  ## **Threading**: must be called on the same thread that invoked
  ## `enableRawMode`. The pin flag cleared here is thread-local, so a
  ## cross-thread disable would leave a stale `true` on the enabling thread
  ## while the underlying stdin O_NONBLOCK state has already been restored.
  if not terminal.rawModeEnabled:
    return # Not enabled

  # Best effort restoration - log but don't raise
  if tcsetattr(STDIN_FILENO, TCSAFLUSH, addr terminal.originalTermios) == -1:
    when defined(celinaDebug):
      stderr.writeLine("Warning: Failed to restore terminal settings")
  # Restore stdin descriptor flags captured in enableRawMode. Best effort;
  # callers see disableRawMode as infallible. The pin flag is cleared only
  # when we actually set one; if enableRawMode never captured flags (F_GETFL
  # failed), the pin was never set in the first place.
  if terminal.stdinFlagsSaved:
    if fcntl(STDIN_FILENO, F_SETFL, terminal.originalStdinFlags) == -1:
      when defined(celinaDebug):
        stderr.writeLine(
          "Warning: failed to restore stdin flags after raw mode (errno=" & $errno & ")"
        )
    terminal.stdinFlagsSaved = false
    setStdinNonBlockingPinned(false)
  terminal.rawMode = false
  terminal.rawModeEnabled = false
  clearPendingByte()

proc c_fflush(f: File): cint {.importc: "fflush", header: "<stdio.h>".}
  ## `flushFile` discards the result, so a failed flush would go unnoticed.

proc c_clearerr(f: File) {.importc: "clearerr", header: "<stdio.h>".}

# Safe write helper that handles EAGAIN
proc writeWithRetry(data: string, onPartial: set[StreamReset] = {}): int =
  ## Write with EAGAIN/EINTR retry. Returns bytes written; short count = gave up.
  ##
  ## Order: pending reset, C stdio flush, then `data` via `writeStream`. A failed
  ## flush is followed by a reset too. Gives up after `WriteMaxBlockedWaits`
  ## no-progress waits, so a wedged tty cannot hang the caller.

  if data.len == 0:
    # Early return for empty data
    return 0

  if not sendPendingReset():
    return 0

  if c_fflush(stdout) != 0:
    # stdio does not say how much went out; the reset is harmless if nothing did.
    when defined(celinaDebug):
      stderr.writeLine("Warning: writeWithRetry flush failed")
    # The failure is handled here, so the app's next `stdout.write` must not
    # raise on the error flag it left set.
    c_clearerr(stdout)
    markPartialWrite({})

  writeStream(data, onPartial)

proc tryWrite(data: string) =
  ## Try to write data, ignoring transient errors
  ## For cursor control sequences, we prefer to silently skip on EAGAIN
  ## rather than crashing, since they're often non-critical
  discard writeWithRetry(data)

proc writeOrRaise(data: string) =
  ## Write data with EAGAIN/EINTR retry, raising IOError on failure
  ## Use for critical paths where callers expect errors to be reported
  ## (e.g. setup sequences, screen clears, low-level render APIs)
  if writeWithRetry(data) != data.len:
    raise newException(IOError, "Terminal write failed (" & $data.len & " bytes)")

# Alternate screen control
proc enableAlternateScreen*(terminal: Terminal) =
  ## Switch to alternate screen buffer
  ## Raises IOError if unable to write to terminal
  if not terminal.alternateScreen:
    writeOrRaise(AlternateScreenEnter)
    terminal.alternateScreen = true

proc disableAlternateScreen*(terminal: Terminal) =
  ## Switch back to main screen buffer
  ## Best effort - doesn't raise on error to ensure cleanup
  if terminal.alternateScreen:
    tryWrite(AlternateScreenExit)
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

# Bracketed paste mode control
proc enableBracketedPaste*(terminal: Terminal) =
  ## Enable bracketed paste mode for paste detection
  if not terminal.bracketedPasteEnabled:
    tryWrite(BracketedPasteEnable)
    terminal.bracketedPasteEnabled = true

proc disableBracketedPaste*(terminal: Terminal) =
  ## Disable bracketed paste mode
  if terminal.bracketedPasteEnabled:
    tryWrite(BracketedPasteDisable)
    terminal.bracketedPasteEnabled = false

# Focus events control
proc enableFocusEvents*(terminal: Terminal) =
  ## Enable focus event reporting (terminal sends ESC[I/O on focus change)
  if not terminal.focusEventsEnabled:
    tryWrite(FocusEventsEnable)
    terminal.focusEventsEnabled = true

proc disableFocusEvents*(terminal: Terminal) =
  ## Disable focus event reporting
  if terminal.focusEventsEnabled:
    tryWrite(FocusEventsDisable)
    terminal.focusEventsEnabled = false

# Synchronized output control
proc enableSyncOutput*(terminal: Terminal) =
  ## Enable synchronized output mode (DEC private mode 2026)
  ## Terminal buffers output until mode is disabled, preventing flickering
  ## Supported by: Kitty, WezTerm, foot, Contour, mintty, etc.
  if not terminal.syncOutputEnabled:
    tryWrite(SyncOutputEnable)
    terminal.syncOutputEnabled = true

proc disableSyncOutput*(terminal: Terminal) =
  ## Disable synchronized output mode, flushing buffered output
  if terminal.syncOutputEnabled:
    tryWrite(SyncOutputDisable)
    terminal.syncOutputEnabled = false

# Window title control
proc setWindowTitle*(title: string) =
  ## Set the terminal window title and icon name
  ## Supported by almost all terminal emulators
  tryWrite(makeWindowTitleSeq(title))

proc setIconName*(name: string) =
  ## Set the terminal icon name only
  tryWrite(makeIconNameSeq(name))

proc setTitleOnly*(title: string) =
  ## Set the terminal window title only (not icon name)
  tryWrite(makeTitleOnlySeq(title))

# Cursor control
proc hideCursor*() =
  ## Hide the cursor
  tryWrite(HideCursorSeq)

proc showCursor*() =
  ## Show the cursor
  tryWrite(ShowCursorSeq)

proc setCursorPosition*(x, y: int) =
  ## Set cursor position (0-based coordinates; converted to 1-based ANSI coordinates internally)
  tryWrite(makeCursorPositionSeq(x, y))

proc setCursorPosition*(pos: Position) =
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
  ##
  ## Does not update a `Terminal`'s `lastBuffer`, so a later `draw` diffs
  ## against content that is gone. Use `terminal.clearScreen()` when drawing,
  ## or `terminal.invalidate()` when the next frame must not be a diff.
  writeOrRaise(ClearScreenSeq)

proc clearScreen*(terminal: Terminal) =
  ## Clear the entire screen and record it as blank, so the next `draw` writes
  ## only the cells that are not blank. Resets SGR first, and the output stream
  ## sends the reset of a cut write first. Does not move the cursor.
  ##
  ## Raises IOError if the clear cannot be written in full. A clear that sent
  ## nothing keeps the screen known; a partial one leaves it unknown, so the
  ## next `draw` is a full render.
  var plan = terminal.screen.planClear(terminal.size)
  let outcome = outcomeOf(writeWithRetry(plan.bytes, plan.onPartial), plan.bytes.len)
  terminal.screen.finishClear(plan, outcome)
  if outcome != swAll:
    raise newException(IOError, "Terminal write failed (" & $plan.bytes.len & " bytes)")

proc clearLine*() =
  ## Clear the current line
  ## Raises IOError if unable to write to terminal
  ##
  ## Does not update a `Terminal`'s `lastBuffer`: call `terminal.invalidate()`
  ## if the next `draw` must not be a diff against it.
  writeOrRaise(ClearLineSeq)

proc clearToEndOfLine*() =
  ## Clear from cursor to end of line
  ## Raises IOError if unable to write to terminal
  writeOrRaise(ClearToEndOfLineSeq)

proc clearToStartOfLine*() =
  ## Clear from start of line to cursor
  tryWrite(ClearToStartOfLineSeq)

# Buffer rendering
proc renderCell*(cell: Cell, x, y: int) =
  ## Render a single cell at the specified position
  ##
  ## Writes to the screen outside the screen model, so a `Terminal` diffs
  ## against a `lastBuffer` this changed. Call `terminal.invalidate()` when
  ## drawing to such a terminal afterwards.
  setCursorPosition(x, y)

  let styleSeq = cell.style.toAnsiSequence()
  if styleSeq.len > 0:
    tryWrite(styleSeq)

  tryWrite(sanitizeCellSymbol(cell.symbol))

  if styleSeq.len > 0:
    tryWrite(resetSequence())

# The frame protocol, in one place per backend: plan, write, record. Each
# public entry point is a wrapper that picks its options and maps the outcome
# (raise, or ignore and keep the previous cursor style).

template presentFrame(
    terminal: Terminal,
    buffer: untyped,
    cursor: CursorRequest,
    force: bool,
    wrap: bool,
    adopt: static bool,
): Presented =
  ## Plan, write and record one frame of `buffer`, and report the outcome and
  ## the cursor style the terminal now shows. `force` marks the screen unknown
  ## first, so the frame is a full render; `adopt` is the zero-copy variant
  ## whose caller re-fills `buffer` every frame. A failed write comes back as
  ## the outcome. The write blocks, so an adopt frame is not staged: it is
  ## adopted after a write that went out in full.
  block:
    if force:
      terminal.screen.invalidate()
    let plan = terminal.screen.planFrame(buffer, cursor, wrap)
    # `writeWithRetry` flushes the C stdio buffer first, so a frame cannot
    # overtake a `stdout.write` that preceded it.
    let outcome = outcomeOf(writeWithRetry(plan.bytes, plan.onPartial), plan.bytes.len)
    when adopt:
      terminal.screen.finishAdopt(plan, buffer, outcome)
    else:
      terminal.screen.finish(plan, buffer, outcome)
    Presented(outcome: outcome, style: plan.appliedStyle(outcome))

proc render*(terminal: Terminal, buffer: Buffer) =
  ## Low-level differential render; raises on truncation. Prefer `draw` for
  ## app loops. Full render while unknown; not wrapped in synchronized output.
  let presented = terminal.presentFrame(buffer, noCursor, false, false, false)
  if presented.outcome != swAll:
    raise newTerminalError("Failed to render buffer: terminal write truncated")

proc renderFull*(terminal: Terminal, buffer: Buffer) =
  ## Low-level forced full render; raises on truncation. Not wrapped in
  ## synchronized output, as in `render`.
  let presented = terminal.presentFrame(buffer, noCursor, true, false, false)
  if presented.outcome != swAll:
    raise newTerminalError("Failed to render full buffer: terminal write truncated")

# Terminal setup and cleanup

proc cleanup*(terminal: Terminal) =
  ## Cleanup terminal, restoring original settings.
  ## Best effort - each step is guarded individually so a single failure
  ## does not block later cleanup steps.
  ##
  ## Disable order is the reverse of `setup` (LIFO): raw mode is restored
  ## before leaving the alternate screen so that the final `tcsetattr` runs
  ## while the program-mode screen is still active. Callers that need a
  ## different order should not reorder these lines piecemeal — the policy
  ## lives here so app-level wrappers can delegate to it. A mode added here
  ## belongs in `EmergencyResetSeq` too.
  ##
  ## The first write sends the reset a cut frame needs (OSC 8, SGR, the
  ## synchronized output block), so nothing has to be prepended here.
  template guard(body: untyped) =
    try:
      body
    except CatchableError:
      discard

  guard:
    showCursor()
  guard:
    terminal.disableSyncOutput()
  guard:
    terminal.disableFocusEvents()
  guard:
    terminal.disableBracketedPaste()
  guard:
    terminal.disableMouse()
  guard:
    terminal.disableRawMode()
  guard:
    terminal.disableAlternateScreen()

proc emergencyRestore*(terminal: Terminal) =
  ## Restore the terminal from a signal handler or crash hook, where a frame
  ## may have been cut off mid-write.
  ##
  ## Unlike `cleanup`, ignores the per-mode flags and writes
  ## `EmergencyResetSeq` (or `EmergencyResetAltScreenSeq`) straight to the fd
  ## without flushing stdio, which is not async-signal-safe. Then restores
  ## raw mode. Never raises.
  ##
  ## The screen is marked unknown: the terminal no longer shows `lastBuffer`, so
  ## a caller that keeps drawing after this must redraw in full. The output
  ## stream's pending reset is left alone, since this path is not async-signal-safe
  ## enough to add a write.
  terminal.screen.invalidate()
  discard writeAllBlocking(
    cint(STDOUT_FILENO),
    if terminal.alternateScreen: EmergencyResetAltScreenSeq else: EmergencyResetSeq,
  )
  terminal.syncOutputEnabled = false
  terminal.focusEventsEnabled = false
  terminal.bracketedPasteEnabled = false
  terminal.mouseEnabled = false
  terminal.alternateScreen = false
  # disableRawMode can raise from its celinaDebug stderr warnings.
  try:
    terminal.disableRawMode()
  except CatchableError:
    discard

proc setup*(terminal: Terminal) =
  ## Setup terminal for CLI mode.
  ##
  ## Best-effort atomicity: if a step fails after an earlier one already took
  ## effect (e.g. `enableRawMode` raises ENOTTY on a non-TTY once the
  ## alternate screen has been entered), the applied steps are rolled back via
  ## `cleanup` before the error propagates. This keeps the shell from being
  ## stranded in the alternate screen or raw mode after a failed setup.
  try:
    terminal.enableAlternateScreen()
    terminal.enableRawMode()
    # Size first: the clear records a blank screen at the current size.
    terminal.updateSize()
    terminal.clearScreen()
  except CatchableError:
    terminal.cleanup()
    raise

proc setupWithHiddenCursor*(terminal: Terminal) =
  ## Setup terminal for CLI mode with cursor hidden (backward compatibility)
  terminal.setup()
  hideCursor()

proc setupWithMouse*(terminal: Terminal) =
  ## Setup terminal for CLI mode with mouse support
  ## Raises TerminalError if setup fails. Any partially-applied terminal
  ## state is rolled back via `cleanup` before the error propagates.
  try:
    terminal.setup()
    terminal.enableMouse()
  except CatchableError as e:
    terminal.cleanup()
    raise newTerminalError("Failed to setup terminal with mouse: " & e.msg)

proc setupWithPaste*(terminal: Terminal) =
  ## Setup terminal for CLI mode with bracketed paste support
  ## Raises TerminalError if setup fails. Any partially-applied terminal
  ## state is rolled back via `cleanup` before the error propagates.
  try:
    terminal.setup()
    terminal.enableBracketedPaste()
  except CatchableError as e:
    terminal.cleanup()
    raise newTerminalError("Failed to setup terminal with paste: " & e.msg)

proc setupWithMouseAndPaste*(terminal: Terminal) =
  ## Setup terminal for CLI mode with mouse and bracketed paste support
  ## Raises TerminalError if setup fails. Any partially-applied terminal
  ## state is rolled back via `cleanup` before the error propagates.
  try:
    terminal.setup()
    terminal.enableMouse()
    terminal.enableBracketedPaste()
  except CatchableError as e:
    terminal.cleanup()
    raise newTerminalError("Failed to setup terminal with mouse and paste: " & e.msg)

proc isSuspended*(terminal: Terminal): bool =
  ## Check if terminal is currently suspended
  terminal.suspendState.isSuspended

proc suspend*(terminal: Terminal) =
  ## Suspend terminal to return to shell mode temporarily
  ##
  ## Saves current terminal state and restores normal shell mode.
  ## Use `resume()` to return to program mode.
  ##
  ## Example:
  ## ```nim
  ## terminal.suspend()
  ## discard execShellCmd("ls ./")
  ## terminal.resume()
  ## ```
  if terminal.isSuspended:
    return # Already suspended

  # Another program gets the terminal, so whatever it does with it is not
  # `lastBuffer`.
  terminal.screen.invalidate()

  # Save current state (using rawModeEnabled for internal tracking)
  terminal.suspendState.suspendedRawMode = terminal.rawModeEnabled
  terminal.suspendState.suspendedAlternateScreen = terminal.alternateScreen
  terminal.suspendState.suspendedMouseEnabled = terminal.mouseEnabled
  terminal.suspendState.suspendedBracketedPaste = terminal.bracketedPasteEnabled
  terminal.suspendState.suspendedFocusEvents = terminal.focusEventsEnabled
  terminal.suspendState.suspendedSyncOutput = terminal.syncOutputEnabled

  # Return to shell mode. A mode added here belongs in `EmergencyResetSeq` too.
  # The first write sends the reset a cut frame needs, so nothing is prepended.
  try:
    showCursor()
  except CatchableError:
    discard
  terminal.disableSyncOutput()
  terminal.disableFocusEvents()
  terminal.disableBracketedPaste()
  terminal.disableMouse()
  terminal.disableRawMode()
  terminal.disableAlternateScreen()

  terminal.suspendState.isSuspended = true

proc resume*(terminal: Terminal) =
  ## Resume terminal after suspend, restoring program mode
  ##
  ## Restores terminal state that was saved by `suspend()`. The screen is
  ## marked unknown here, so the next `draw` is a full redraw; no `force`
  ## needed.
  if not terminal.isSuspended:
    return # Not suspended

  # Another program had the terminal, so whatever it showed is not
  # `lastBuffer`. Marked again rather than only in `suspend`: a frame drawn
  # while the terminal was handed over would otherwise put the screen back to
  # known, and the epoch bump also stops a frame in flight across this point
  # from claiming the screen.
  terminal.screen.invalidate()

  # Another program had the terminal and may have left a sequence or an OSC 8
  # link open, may have left attributes set, or may have left a synchronized
  # output block celina wrapped open, so the first write after this resets all
  # of that. The SGR reset is what a hand back without a frame in between needs:
  # nothing else restores the attributes, and the next frame is not guaranteed.
  setPendingReset({srAbort, srOsc8, srSgr, srSyncEnd})

  # Restore saved state
  restoreSuspendedFeatures(terminal)
  hideCursor()

  terminal.suspendState.isSuspended = false

# High-level rendering interface
#
# Every draw path is a wrapper around `presentFrame`: it picks the options
# (cursor handling, force, the DEC 2026 wrap, copy vs adopt) and maps the
# outcome. A failed write is ignored here, so a transient terminal hiccup never
# crashes the render loop; the screen state records it, so the next frame is a
# full render.

proc draw*(terminal: Terminal, buffer: Buffer, force: bool = false) =
  ## Draw a buffer to the terminal (high-level API)
  ##
  ## This is the recommended high-level rendering function for main application loops.
  ## Unlike `render()` and `renderFull()`, this function silently ignores I/O errors
  ## to prevent crashes from transient terminal issues. A write that stopped partway
  ## leaves the screen unknown, so the next frame is a full render; one that sent
  ## nothing leaves it known, and the next frame is the same diff again.
  ##
  ## Output is automatically wrapped with synchronized output sequences (DEC mode 2026)
  ## to prevent flickering on supported terminals, unless the app enabled that mode
  ## itself and owns the block.
  ##
  ## The buffer's contents are preserved across the call (copy semantics), so it
  ## is safe to keep and incrementally update the same buffer between frames.
  ## Renderer-owned hot paths that fully re-fill the buffer each frame can use
  ## the zero-copy `drawAdopt` instead.
  ##
  ## Parameters:
  ## - buffer: The buffer to render to the terminal
  ## - force: If true, marks the screen unknown first, so this frame is a full
  ##   redraw regardless of changes
  ##
  ## Note: For rendering with cursor positioning, use `drawWithCursor()` instead.
  ## For low-level rendering with explicit error handling, use `render()` or `renderFull()`.
  let presented = terminal.presentFrame(
    buffer, noCursor, force, not terminal.syncOutputEnabled, false
  )
  when defined(celinaDebug):
    if presented.outcome == swPartial:
      stderr.writeLine("Warning: draw() left the screen unknown")
  else:
    discard presented # Avoid "declared but not used" warning

proc drawAdopt*(terminal: Terminal, buffer: var Buffer, force: bool = false) =
  ## Zero-copy variant of `draw` for renderer-owned buffers.
  ##
  ## Instead of copying, the rendered content is swapped into `lastBuffer` and
  ## the previous frame's storage is handed back in `buffer` (recycled). The
  ## caller MUST fully re-fill `buffer` before the next frame or it will render
  ## stale content; `Renderer.render` guarantees this via `renderer.clear()`.
  ## On the first frame and after a resize the content is copied instead. A
  ## write that did not go out in full adopts nothing, so the caller keeps the
  ## grid it rendered. Prefer the copy-preserving `draw` unless you own the
  ## buffer and clear it every frame.
  discard
    terminal.presentFrame(buffer, noCursor, force, not terminal.syncOutputEnabled, true)

proc drawWithCursor*(
    terminal: Terminal,
    buffer: Buffer,
    cursorX, cursorY: int,
    cursorVisible: bool,
    cursorStyle: CursorStyle = CursorStyle.Default,
    lastCursorStyle: CursorStyle,
    force: bool = false,
): CursorStyle =
  ## Draw buffer with cursor positioning in single write operation
  ## This prevents cursor flickering by including cursor commands in the same output
  ##
  ## Output is automatically wrapped with synchronized output sequences (DEC mode 2026)
  ## to prevent flickering on supported terminals.
  ##
  ## Returns the updated lastCursorStyle value on success, or the original
  ## `lastCursorStyle` on failure (the frame may have stopped before its DECSCUSR,
  ## so the next frame sends it again). Caller is responsible for tracking this state.
  ##
  ## The buffer's contents are preserved across the call (copy semantics). For a
  ## zero-copy renderer-owned hot path, use `drawWithCursorAdopt` instead.
  ##
  ## Note: This procedure silently ignores I/O errors to prevent crashes from transient
  ## terminal issues. A write that stopped partway leaves the screen unknown, so the next
  ## frame is a full render; one that sent nothing leaves it known, and the next frame
  ## is the same diff again.
  let presented = terminal.presentFrame(
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
    false,
  )
  when defined(celinaDebug):
    if presented.outcome == swPartial:
      stderr.writeLine("Warning: drawWithCursor() left the screen unknown")
  presented.style

proc drawWithCursorAdopt*(
    terminal: Terminal,
    buffer: var Buffer,
    cursorX, cursorY: int,
    cursorVisible: bool,
    cursorStyle: CursorStyle = CursorStyle.Default,
    lastCursorStyle: CursorStyle,
    force: bool = false,
): CursorStyle =
  ## Zero-copy variant of `drawWithCursor` for renderer-owned buffers.
  ##
  ## As with `drawAdopt`, the rendered content is swapped into `lastBuffer` and
  ## the previous frame's storage is recycled back into `buffer`, so the caller
  ## MUST fully re-fill `buffer` each frame. Used by `Renderer.render`. A
  ## write that did not go out in full adopts nothing, as with `drawAdopt`.
  ##
  ## Returns the updated lastCursorStyle value on success, or the original
  ## `lastCursorStyle` on failure.
  terminal.presentFrame(
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
    true,
  ).style

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
