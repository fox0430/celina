# Tests for async_terminal module

import std/[unittest, strutils, posix, importutils, oserrors]

import ../celina/async/[async_backend, async_buffer]
import ../celina/core/[geometry, colors, buffer, errors]

import ../celina/async/async_terminal {.all.}
import ../celina/async/async_io {.all.}
import ./stdout_capture
import ../celina/core/terminal_common
from ../celina/core/output_stream import
  clearPendingReset, resetPending, setPendingReset, srAbort, srOsc8, srSgr, srSyncEnd

privateAccess(AsyncTerminal)

# Test helpers
proc createTestBuffer(width, height: int, fillChar: string = " "): Buffer =
  result = newBuffer(rect(0, 0, width, height))
  for y in 0 ..< height:
    for x in 0 ..< width:
      result[x, y] = cell(fillChar, defaultStyle())

# Helper to create terminal without fd registration for testing
proc createTestTerminal(): AsyncTerminal =
  result = AsyncTerminal(
    size: size(80, 24), alternateScreen: false, rawMode: false, mouseEnabled: false
  )
  # Initialize lastBuffer without fd registration
  result.lastBuffer = newBuffer(rect(0, 0, result.size.width, result.size.height))

proc knownScreenTerminal(width, height: int): AsyncTerminal =
  ## A terminal whose screen is known at the given size: `clearScreenAsync`
  ## records a blank screen, so the next frame is a diff against it. Its own
  ## output is captured, so a test's capture starts clean.
  let terminal = createTestTerminal()
  terminal.size = size(width, height)
  discard captureStdout(
    proc() =
      waitFor terminal.clearScreenAsync()
  )
  terminal

suite "AsyncTerminal Basic Operations":
  test "newAsyncTerminal creates terminal with default state":
    # Test the structure without fd registration
    let terminal = createTestTerminal()
    check:
      terminal.size.width == 80 # Test terminal default
      terminal.size.height == 24 # Test terminal default
      not terminal.alternateScreen
      not terminal.rawMode
      not terminal.mouseEnabled
      terminal.lastBuffer.area.width > 0

  test "updateSize gets terminal dimensions":
    let terminal = createTestTerminal()
    try:
      terminal.updateSize()
      # Size should change to actual terminal size
      check terminal.size.width > 0
      check terminal.size.height > 0
    except TerminalError:
      # CI environments may not have a real terminal
      skip()

  test "getTerminalSizeAsync returns valid size":
    let size = getTerminalSizeAsync()
    check:
      size.width > 0
      size.height > 0
      # Should be at least minimum reasonable terminal size (or fallback)
      size.width >= 10
      size.height >= 5

suite "AsyncTerminal State Management":
  test "alternate screen state tracking":
    let terminal = createTestTerminal()
    check not terminal.isAlternateScreen()

    terminal.enableAlternateScreen()
    check terminal.isAlternateScreen()

    terminal.disableAlternateScreen()
    check not terminal.isAlternateScreen()

  test "mouse enabled state tracking":
    let terminal = createTestTerminal()
    check not terminal.isMouseEnabled()

    terminal.enableMouse()
    check terminal.isMouseEnabled()

    terminal.disableMouse()
    check not terminal.isMouseEnabled()

  test "getSize and getArea consistency":
    let terminal = createTestTerminal()
    let size = terminal.getSize()
    let area = terminal.getArea()

    check:
      area.x == 0
      area.y == 0
      area.width == size.width
      area.height == size.height

# Terminal display affecting tests removed to prevent interference

suite "AsyncTerminal Rendering":
  test "buffer operations without async terminal":
    # Test basic buffer operations without real terminal
    let terminal = createTestTerminal()
    let buffer = createTestBuffer(10, 5, "T")

    # Test buffer state management
    terminal.lastBuffer = buffer
    check terminal.lastBuffer.area == buffer.area

    # Test with AsyncBuffer
    let asyncBuffer = newAsyncBuffer(rect(0, 0, 8, 4))
    try:
      waitFor(asyncBuffer.setCellAsync(0, 0, cell("A")))
      waitFor(asyncBuffer.setCellAsync(1, 1, cell("B")))

      # Verify cells were set
      check asyncBuffer.getCell(0, 0).symbol == "A"
      check asyncBuffer.getCell(1, 1).symbol == "B"
    except CatchableError:
      check false

suite "AsyncTerminal Buffer Management":
  test "buffer state management":
    let terminal = createTestTerminal()

    # Test basic buffer management
    let buffer1 = createTestBuffer(5, 3, "1")
    terminal.lastBuffer = buffer1
    check terminal.lastBuffer.area == buffer1.area

    # Test buffer modification
    var buffer2 = createTestBuffer(5, 3, "1")
    buffer2[0, 0] = cell("2", defaultStyle())
    buffer2[2, 1] = cell("3", defaultStyle())

    terminal.lastBuffer = buffer2
    check terminal.lastBuffer[0, 0].symbol == "2"
    check terminal.lastBuffer[2, 1].symbol == "3"

  test "buffer area management":
    let terminal = createTestTerminal()

    # Test size change handling
    let buffer1 = createTestBuffer(5, 3)
    terminal.lastBuffer = buffer1

    let buffer2 = createTestBuffer(7, 4)
    terminal.lastBuffer = buffer2
    check terminal.lastBuffer.area == buffer2.area

suite "AsyncTerminal Basic Error Handling":
  test "terminal creation":
    let terminal = createTestTerminal()
    check terminal != nil
    check terminal.size.width == 80
    check terminal.size.height == 24

  test "AsyncTerminalError type exists":
    # Test that AsyncTerminalError is properly defined
    let err = AsyncTerminalError(msg: "Test error")
    check err.msg == "Test error"

  test "Terminal operations with invalid buffer sizes":
    let terminal = createTestTerminal()

    # Terminal should handle empty buffer gracefully
    let emptyBuffer = newBuffer(0, 0)
    terminal.lastBuffer = emptyBuffer
    check terminal.lastBuffer.area.isEmpty()
    check terminal.lastBuffer.area.width == 0
    check terminal.lastBuffer.area.height == 0

  test "Terminal operations with oversized buffers":
    let terminal = createTestTerminal()

    # Terminal should handle buffers larger than screen
    let largeBuffer = newBuffer(terminal.size.width * 2, terminal.size.height * 2)
    terminal.lastBuffer = largeBuffer
    check largeBuffer.area.width > terminal.size.width
    check largeBuffer.area.height > terminal.size.height
    check largeBuffer.area.width == terminal.size.width * 2

suite "AsyncTerminal ANSI Escape Sequences":
  test "Position creation for cursor control":
    # Test position creation which would be used for cursor control
    let pos1 = pos(10, 20)
    let pos2 = pos(5, 15)

    check pos1.x == 10
    check pos1.y == 20
    check pos2.x == 5
    check pos2.y == 15

  test "Terminal coordinates":
    # Test coordinate handling
    let terminal = createTestTerminal()
    let area = terminal.getArea()

    check area.x == 0
    check area.y == 0
    check area.width > 0
    check area.height > 0

suite "AsyncTerminal Control Sequence Writes":
  # These exercise the control writes that now route through async_io's
  # writeOrRaiseAsync/tryWriteAsync instead of a discarded stdout.flushFile().
  # On a writable fd the full sequence is flushed, so none of them must raise;
  # a short count would raise (critical clears) or be logged under
  # -d:celinaDebug (best-effort cursor control).
  test "clearScreenAsync completes a full write without raising":
    waitFor clearScreenAsync()

  test "line clears complete without raising":
    waitFor clearLineAsync()
    waitFor clearToEndOfLineAsync()
    waitFor clearToStartOfLineAsync()

  test "cursor show/hide/position/move complete without raising":
    waitFor hideCursorAsync()
    waitFor showCursorAsync()
    waitFor setCursorPositionAsync(0, 0)
    waitFor setCursorPositionAsync(pos(0, 0))
    waitFor moveCursorAsync(0, 0)

  test "showCursorAtAsync emits position and show in one sequence":
    waitFor showCursorAtAsync(0, 0)
    waitFor showCursorAtAsync(pos(0, 0))

  test "renderCellAsync writes a styled cell without raising":
    # renderCellAsync now concatenates cursor+style+symbol+reset into one
    # tryWriteAsync; a full write on a writable fd must not raise.
    let styledCell = cell("X", style(Color.Red, Color.Blue, {Bold}))
    waitFor renderCellAsync(styledCell, 0, 0)

  test "renderCellAsync writes an unstyled cell without raising":
    waitFor renderCellAsync(cell("Y"), 0, 0)

  test "window title procs complete without raising":
    # These route through best-effort tryWriteAsync; a full write must not raise.
    waitFor setWindowTitleAsync("celina-test")
    waitFor setIconNameAsync("celina")
    waitFor setTitleOnlyAsync("celina-test")

suite "AsyncTerminal.clearScreenAsync":
  test "resets SGR, clears, and records a blank screen at the current size":
    let terminal = createTestTerminal()
    terminal.size = size(10, 3)
    terminal.lastBuffer = newBuffer(4, 2)
    terminal.lastBuffer[0, 0] = cell("x")

    let output = captureStdout(
      proc() =
        waitFor terminal.clearScreenAsync()
    )

    check output == ResetAndClearScreenSeq
    check terminal.lastBuffer == newBuffer(10, 3)

  test "the next draw writes only the cells that are not blank":
    let terminal = createTestTerminal()
    terminal.size = size(10, 3)
    var frame = newBuffer(10, 3)
    frame[2, 1] = cell("x")

    let output = captureStdout(
      proc() =
        waitFor terminal.clearScreenAsync()
        waitFor terminal.drawAsync(frame)
    )

    check output ==
      ResetAndClearScreenSeq &
      wrapWithSyncOutput(buildDifferentialOutput(newBuffer(10, 3), frame))

  test "a clear that sent nothing raises and keeps the screen known":
    let terminal = knownScreenTerminal(10, 3)
    var frame = newBuffer(10, 3)
    frame[2, 1] = cell("x")

    var raised = false
    withFailingStdout(
      proc() =
        try:
          waitFor terminal.clearScreenAsync()
        except IOError:
          raised = true
    )
    check raised

    let output = captureStdout(
      proc() =
        waitFor terminal.drawAsync(frame)
    )

    # The clear emitted nothing, so the screen still shows `lastBuffer` and the
    # next frame is a diff against it.
    check output == wrapWithSyncOutput(buildDifferentialOutput(newBuffer(10, 3), frame))

suite "AsyncTerminal unknown screen state":
  # A write that stops partway leaves the screen unknown, so the next frame is a
  # full render. A write that sent nothing changes nothing: the screen keeps
  # whatever it was, so a known screen stays known and its next frame is the
  # same diff again. `withFailingStdout` (EBADF, zero bytes) covers the second
  # case, `captureCutStdout` the first.

  teardown:
    # A failed check or a resume must not leave a reset pending for the next
    # test.
    clearPendingReset()

  # A frame celina wrapped needs its synchronized output block ended too.
  const frameReset = AbortPartialSeq & Osc8Reset & "\e[0m" & SyncOutputDisable

  test "a known screen diffs, and invalidate makes the next draw full":
    let terminal = knownScreenTerminal(10, 3)
    var frame = newBuffer(10, 3)
    frame[2, 1] = cell("x")

    let diff = captureStdout(
      proc() =
        waitFor terminal.drawAsync(frame)
    )
    check diff == wrapWithSyncOutput(buildDifferentialOutput(newBuffer(10, 3), frame))

    terminal.invalidate()
    let drawn = captureStdout(
      proc() =
        waitFor terminal.drawAsync(frame)
    )
    check drawn == wrapWithSyncOutput(buildFullRenderOutput(frame))
    # `lastBuffer` is kept; the state alone makes the next frame a full render.
    check terminal.lastBuffer.area == rect(0, 0, 10, 3)

  test "a write that sent nothing keeps the screen known":
    let terminal = knownScreenTerminal(10, 3)
    var frame = newBuffer(10, 3)
    frame[2, 1] = cell("x")
    var raised = false
    withFailingStdout(
      proc() =
        try:
          waitFor terminal.drawAsync(frame)
        except TerminalError:
          raised = true
    )
    check raised

    var next = frame
    next[3, 1] = cell("y")
    let output = captureStdout(
      proc() =
        waitFor terminal.drawAsync(next)
    )
    # Not a full repaint: nothing was emitted, so the screen still shows
    # `lastBuffer` and the next frame is a diff against it.
    check output == wrapWithSyncOutput(buildDifferentialOutput(newBuffer(10, 3), next))

  test "an adopt draw that sent nothing leaves the next draw full":
    let terminal = knownScreenTerminal(10, 3)
    var frame = newBuffer(10, 3)
    frame[2, 1] = cell("x")
    let asyncBuffer = newAsyncBuffer(10, 3)
    asyncBuffer.updateFromBuffer(frame)
    var style = CursorStyle.Default
    withFailingStdout(
      proc() =
        style = waitFor terminal.drawWithCursorAdoptAsync(
          asyncBuffer, 1, 1, true, SteadyBar, lastCursorStyle = style
        )
    )
    check style == CursorStyle.Default

    let output = captureStdout(
      proc() =
        discard waitFor terminal.drawWithCursorAdoptAsync(
          asyncBuffer, 1, 1, true, SteadyBar, lastCursorStyle = style
        )
    )
    let (expected, _) = buildOutputWithCursor(
      newBuffer(10, 3),
      frame,
      1,
      1,
      true,
      SteadyBar,
      lastCursorStyle = style,
      force = true,
    )
    # The grid was in the caller's hands while the failed write ran, so the
    # screen is unknown and this frame is a full render.
    check output == wrapWithSyncOutput(expected)

  test "a failed drawWithCursorAsync keeps the screen known":
    let terminal = knownScreenTerminal(10, 3)
    var frame = newBuffer(10, 3)
    frame[2, 1] = cell("x")

    var style = CursorStyle.Default
    withFailingStdout(
      proc() =
        style = waitFor terminal.drawWithCursorAsync(
          frame, 1, 1, true, SteadyBar, lastCursorStyle = style
        )
    )
    check style == CursorStyle.Default

    let output = captureStdout(
      proc() =
        discard waitFor terminal.drawWithCursorAsync(
          frame, 1, 1, true, SteadyBar, lastCursorStyle = style
        )
    )
    let (expected, _) = buildOutputWithCursor(
      newBuffer(10, 3),
      frame,
      1,
      1,
      true,
      SteadyBar,
      lastCursorStyle = CursorStyle.Default,
    )
    check output == wrapWithSyncOutput(expected)

  test "a draw cut off partway is reset at once and the next draw is full":
    when defined(linux):
      let terminal = knownScreenTerminal(10, 3)
      var frame = newBuffer(10, 3)
      frame[2, 1] = cell("x")
      var next = frame
      next[3, 1] = cell("y")
      # `drawAsync` raises on a truncated frame (it does not swallow it), so the
      # cut first draw is caught; the second one is the point of the test.
      let cutDraw = proc() =
        try:
          waitFor terminal.drawAsync(frame)
        except TerminalError:
          discard
        waitFor terminal.drawAsync(next)
      let output = captureCutStdout(4, cutDraw)

      let cutFrame =
        wrapWithSyncOutput(buildDifferentialOutput(newBuffer(10, 3), frame))
      check output ==
        cutFrame[0 ..< 4] & frameReset & wrapWithSyncOutput(buildFullRenderOutput(next))
    else:
      skip()

  test "a clear after a cut write is reset first and makes the screen known":
    when defined(linux):
      let terminal = knownScreenTerminal(10, 3)
      var frame = newBuffer(10, 3)
      frame[2, 1] = cell("x")
      let cutDraw = proc() =
        try:
          waitFor terminal.drawAsync(frame)
        except TerminalError:
          discard
      discard captureCutStdout(4, cutDraw, failedWrites = 2)

      let output = captureStdout(
        proc() =
          waitFor terminal.clearScreenAsync()
          waitFor terminal.drawAsync(frame)
      )
      check output ==
        frameReset & ResetAndClearScreenSeq &
        wrapWithSyncOutput(buildDifferentialOutput(newBuffer(10, 3), frame))
    else:
      skip()

  test "a clear cut off partway leaves the next draw full":
    when defined(linux):
      let terminal = knownScreenTerminal(10, 3)
      var raised = false
      discard captureCutStdout(
        4,
        proc() =
          try:
            waitFor terminal.clearScreenAsync()
          except IOError:
            raised = true,
      )
      check raised

      var frame = newBuffer(10, 3)
      frame[2, 1] = cell("x")
      let output = captureStdout(
        proc() =
          waitFor terminal.drawAsync(frame)
      )
      # The clear stopped partway, so the screen is unknown: full render.
      check output == wrapWithSyncOutput(buildFullRenderOutput(frame))
    else:
      skip()

  test "a renderAsync that sent nothing keeps the screen known":
    let terminal = knownScreenTerminal(10, 3)
    var frame = newBuffer(10, 3)
    frame[2, 1] = cell("x")

    var raised = false
    withFailingStdout(
      proc() =
        try:
          waitFor terminal.renderAsync(frame)
        except TerminalError:
          raised = true
    )
    check raised

    let output = captureStdout(
      proc() =
        waitFor terminal.renderAsync(frame)
    )
    check output == wrapWithSyncOutput(buildDifferentialOutput(newBuffer(10, 3), frame))

  test "a renderAsync cut off partway makes the next render full":
    when defined(linux):
      let terminal = knownScreenTerminal(10, 3)
      var frame = newBuffer(10, 3)
      frame[2, 1] = cell("x")

      var raised = false
      let cutProc = proc() =
        try:
          waitFor terminal.renderAsync(frame)
        except TerminalError:
          raised = true
      discard captureCutStdout(4, cutProc)
      check raised

      # A diff against the old `lastBuffer` would be wrong: render in full.
      let output = captureStdout(
        proc() =
          waitFor terminal.renderAsync(frame)
      )
      check output == wrapWithSyncOutput(buildFullRenderOutput(frame))
    else:
      skip()

  test "renderAsync renders in full after a resize":
    let terminal = knownScreenTerminal(10, 3)
    var frame = newBuffer(20, 5)
    frame[2, 1] = cell("x")

    let output = captureStdout(
      proc() =
        waitFor terminal.renderAsync(frame)
    )
    check output == wrapWithSyncOutput(buildFullRenderOutput(frame))

  test "resumeAsync sends the reset before its first write":
    let terminal = knownScreenTerminal(10, 3)
    discard captureStdout(
      proc() =
        waitFor terminal.suspendAsync()
    )
    # Another program had the terminal and may have left a sequence, an OSC 8
    # link, attributes set, or a block celina wrapped open.
    let resumed = captureStdout(
      proc() =
        waitFor terminal.resumeAsync()
    )
    check resumed ==
      AbortPartialSeq & Osc8Reset & "\e[0m" & SyncOutputDisable & HideCursorSeq
    check not resetPending()

  test "a hand back after resumeAsync resets the attributes left behind":
    # `suspendAsync`, `resumeAsync` and `cleanup` write no frame, so nothing
    # else restores the attributes another program left set: without the SGR
    # reset the shell inherits them. The next frame would start with one, but a
    # hand back is not guaranteed to be followed by a frame.
    let terminal = knownScreenTerminal(10, 3)
    let handedBack = captureStdout(
      proc() =
        waitFor terminal.suspendAsync()
        waitFor terminal.resumeAsync()
        waitFor terminal.cleanupAsync()
    )
    check "\e[0m" in handedBack
    check handedBack.endsWith(ShowCursorSeq)

  test "the first draw after resumeAsync is a full render":
    let terminal = knownScreenTerminal(10, 3)
    var frame = newBuffer(10, 3)
    frame[2, 1] = cell("x")
    discard captureStdout(
      proc() =
        waitFor terminal.suspendAsync()
        waitFor terminal.resumeAsync()
    )

    let output = captureStdout(
      proc() =
        waitFor terminal.drawAsync(frame)
    )
    check output == wrapWithSyncOutput(buildFullRenderOutput(frame))

  test "cleanup, cleanupAsync and suspendAsync send the reset of a cut write first":
    when defined(linux):
      let terminal = knownScreenTerminal(10, 3)
      let known = captureStdout(
        proc() =
          waitFor terminal.cleanupAsync()
      )
      check known == ShowCursorSeq

      var frame = newBuffer(10, 3)
      frame[2, 1] = cell("x")
      let cutDraw = proc() =
        try:
          waitFor terminal.drawAsync(frame)
        except TerminalError:
          discard

      discard captureCutStdout(4, cutDraw, failedWrites = 2)
      let cleanedAsync = captureStdout(
        proc() =
          waitFor terminal.cleanupAsync()
      )
      check cleanedAsync == frameReset & ShowCursorSeq

      discard captureCutStdout(4, cutDraw, failedWrites = 2)
      let cleaned = captureStdout(
        proc() =
          terminal.cleanup()
      )
      check cleaned == frameReset & ShowCursorSeq

      discard captureCutStdout(4, cutDraw, failedWrites = 2)
      let suspended = captureStdout(
        proc() =
          waitFor terminal.suspendAsync()
      )
      check suspended == frameReset & ShowCursorSeq
    else:
      skip()

  # `F_SETPIPE_SZ` is a Linux extension, so the pipe can only be shrunk here.
  when defined(linux) and hasChronos:
    var F_SETPIPE_SZ {.importc: "F_SETPIPE_SZ", header: "<fcntl.h>".}: cint

    # A chronos cancel must reach the caller (a `cancelAndWait` shutdown depends
    # on it) and count as a partial write: the frame may have gone out in part.
    # The body is an `async` proc because a chronos cancel has to be awaited to
    # observe; the test itself only `waitFor`s the result.
    proc cancelDuringFrameDraw(
        terminal: AsyncTerminal, frame: Buffer
    ): Future[tuple[cancelled: bool, style: CursorStyle, note: string]] {.async.} =
      var fds: array[2, cint]
      if pipe(fds) != 0:
        return (cancelled: false, style: CursorStyle.Default, note: "pipe failed")
      # A small pipe buffer, so even a modest frame parks on EAGAIN instead of
      # waiting for the 64 KiB default to fill. `F_SETPIPE_SZ` returns the new
      # size, so only -1 is a failure. The caller pins the frame to be larger
      # than what is asked for here; if the shrink does not take (a sandbox that
      # forbids it, a pipe-user-pages limit) the whole frame would fit the
      # default buffer and the write would never park, so say so instead of
      # letting that read as a lost cancel.
      let shrunk = fcntl(fds[1], F_SETPIPE_SZ, 4096)
      if shrunk < 0:
        let why = osErrorMsg(osLastError()) # before any other call touches errno
        discard close(fds[0])
        discard close(fds[1])
        return (
          cancelled: false,
          style: CursorStyle.Default,
          note: "cannot shrink the pipe buffer: " & why,
        )
      for fd in fds:
        discard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) or O_NONBLOCK)
      stdout.flushFile()
      let saved = dup(STDOUT_FILENO)
      if saved < 0:
        discard close(fds[0])
        discard close(fds[1])
        return (cancelled: false, style: CursorStyle.Default, note: "dup failed")

      var
        cancelled = false
        style = CursorStyle.Default
        note = ""
      try:
        discard dup2(fds[1], STDOUT_FILENO)
        let fut = terminal.drawWithCursorAsync(
          frame, 0, 0, true, CursorStyle.Default, lastCursorStyle = style
        )
        # The pipe holds 4096 bytes and the frame is larger than that (the
        # caller checks the margin), so once bytes are observable on the read
        # end the writer is parked mid-write: wait for that instead of assuming a
        # fixed sleep gets the cancel there. The probe never blocks (timeout 0);
        # the `await` yields to the writer.
        var started = false
        for _ in 0 ..< 500: # up to ~5 s
          var pfd: Tpollfd
          pfd.fd = fds[0]
          pfd.events = POLLIN
          pfd.revents = 0
          if posix.poll(addr pfd, 1, 0) > 0:
            started = true
            break
          await sleepMs(10)
        if not started:
          note = "frame write did not start within the wait bound"
        else:
          fut.cancelSoon()
          try:
            # Awaiting the future itself is what observes the error: `join` and
            # `cancelAndWait` swallow it, which is the bug this test pins down.
            let applied: CursorStyle = await fut
            style = applied
            # It returned without raising, so the write finished on its own —
            # went out in full, or gave up on a short count. Either way the
            # cancel was not observed, and saying so keeps a failure from
            # arriving with no reason at all.
            note = "frame write finished without a cancel"
          except CancelledError:
            cancelled = true
          except CatchableError as e:
            # The frame failed on its own before the cancel landed; keep the
            # reason so a failure can be told apart from a lost cancel.
            note = "frame failed on its own: " & e.msg
        # Drain the pipe so the write end is empty again before it is closed.
        var buf = newString(65536)
        while posix.read(fds[0], addr buf[0], buf.len) > 0:
          discard
      finally:
        discard dup2(saved, STDOUT_FILENO)
        discard close(saved)
        discard close(fds[0])
        discard close(fds[1])
      (cancelled: cancelled, style: style, note: note)

    test "a cancel during a frame write is not swallowed":
      let terminal = knownScreenTerminal(10, 3)
      # A frame larger than the pipe buffer the helper asks for (styled cells in
      # every position, ~6.4 KiB against its 4 KiB), so the write parks on EAGAIN
      # and the cancel lands in the middle of it. The margin is what makes the
      # cancel reachable at all, and it is only ~1.6x, so pin it: a frame that
      # shrank below the buffer would be written in full and the test would
      # report a lost cancel instead of the real cause.
      var frame = newBuffer(100, 60)
      for y in 0 ..< 60:
        for x in 0 ..< 100:
          frame[x, y] = cell($((x + y) mod 10), style(Color.Red, modifiers = {Bold}))
      check buildFullRenderOutput(frame).len > 4096

      let (cancelled, style, note) = waitFor cancelDuringFrameDraw(terminal, frame)

      check note == ""
      check cancelled
      # The tracked cursor style is unchanged.
      check style == CursorStyle.Default
      # The cancel counts as a partial write: the first write after it carries
      # its resets, and the screen is unknown. A frame of the screen's own size
      # proves the unknown part — the size difference of the cancelled frame
      # would force a full render on its own.
      var small = newBuffer(10, 3)
      small[1, 1] = cell("z")
      let (expected, _) = buildOutputWithCursor(
        newBuffer(10, 3),
        small,
        0,
        0,
        true,
        CursorStyle.Default,
        lastCursorStyle = style,
        force = true,
      )
      let output = captureStdout(
        proc() =
          discard waitFor terminal.drawWithCursorAsync(
            small, 0, 0, true, CursorStyle.Default, lastCursorStyle = style
          )
      )
      check (AbortPartialSeq & Osc8Reset & "\e[0m") in output
      check output.endsWith(wrapWithSyncOutput(expected))
  else:
    test "a cancel during a frame write is not swallowed":
      skip()

  test "a frame that waited for the lock is planned after the writer ahead of it":
    let terminal = knownScreenTerminal(10, 3)
    var frame = newBuffer(10, 3)
    frame[3, 1] = cell("y")

    # Hold the lock so the frame below parks on it, then leave behind what a
    # write that stopped partway leaves: the screen unknown and its reset
    # pending. The frame is planned only once the lock is handed over, so it
    # is a full render behind that reset, not a diff against the screen as it
    # was when the frame was called. The lock and the planning under it are
    # shared by both async backends, so this runs on both.
    doAssert tryAcquireStdoutLockImmediate()
    let parked = terminal.drawAsync(frame)
    # What a wrapped frame that stopped partway leaves behind: the abort and
    # the resets of what it had opened.
    setPendingReset({srAbort, srOsc8, srSgr, srSyncEnd})
    terminal.invalidate()
    try:
      let output = captureStdout(
        proc() =
          releaseStdoutLock()
          waitFor parked
      )
      check output == frameReset & wrapWithSyncOutput(buildFullRenderOutput(frame))
      check not resetPending()
    finally:
      # The lock must not stay held for the rest of the suite: the frame
      # releases it on its own way out, so this only matters when the body
      # above never ran or never got that far.
      releaseStdoutLock()

suite "AsyncTerminal POSIX Platform Support":
  test "Terminal size detection works on POSIX systems":
    let size = getTerminalSizeAsync()

    # Should work on POSIX platforms (Linux, macOS, etc.)
    # In CI environments, this might be fallback size
    check size.width > 0
    check size.height > 0
    check size.width >= 10 # Reasonable minimum
    check size.height >= 5

    # Common fallback values
    if size.width == 80 and size.height == 24:
      # Likely using fallback values, which is acceptable
      discard
    else:
      # Using actual terminal dimensions
      check size.width >= 20
      check size.height >= 5

  test "Raw mode state tracking on POSIX":
    let terminal = createTestTerminal()

    # Test initial state
    check not terminal.isRawMode()

  test "Alternate screen state tracking on POSIX":
    let terminal = createTestTerminal()

    # Test initial state
    check not terminal.isAlternateScreen()

suite "AsyncTerminal Differential Rendering":
  test "Terminal tracks last buffer for diffs":
    let terminal = createTestTerminal()
    let buffer1 = newBuffer(10, 5)
    let buffer2 = newBuffer(10, 5)

    # Terminal should track last buffer for differential rendering
    terminal.lastBuffer = buffer1
    check terminal.lastBuffer.area.width == 10
    check terminal.lastBuffer.area.height == 5

    # Change to different buffer
    terminal.lastBuffer = buffer2
    check terminal.lastBuffer.area == buffer2.area

  test "Buffer size changes trigger full redraw":
    let terminal = createTestTerminal()
    let buffer1 = newBuffer(10, 5)
    let buffer2 = newBuffer(15, 8) # Different size

    # Terminal should detect buffer size changes
    terminal.lastBuffer = buffer1
    check terminal.lastBuffer.area == buffer1.area

    terminal.lastBuffer = buffer2
    check terminal.lastBuffer.area != buffer1.area
    check terminal.lastBuffer.area == buffer2.area

  test "Terminal render with same-size buffers":
    let terminal = createTestTerminal()
    var buffer1 = newBuffer(10, 5)
    var buffer2 = newBuffer(10, 5)

    # Terminal should handle same-size buffer transitions
    terminal.lastBuffer = buffer1
    check terminal.lastBuffer.area == buffer1.area

    terminal.lastBuffer = buffer2
    check terminal.lastBuffer.area == buffer2.area
    check terminal.lastBuffer.area == buffer1.area # Same size

    # Same size, different content
    buffer1[1, 1] = cell("A")
    buffer2[1, 1] = cell("B")
    buffer2[2, 2] = cell("C")

    # Should detect differences
    let changes = buffer1.diff(buffer2)
    check changes.len > 0

suite "AsyncTerminal Integration Tests":
  test "Terminal with styled content":
    let terminal = createTestTerminal()
    var buffer = newBuffer(terminal.size.width, terminal.size.height)

    # Add styled content
    let styledCell = cell("X", style(Color.Red, Color.Blue, {Bold, Italic}))
    buffer[5, 5] = styledCell

    # Should handle styled cells
    check buffer[5, 5].style.fg.indexed == Color.Red
    check buffer[5, 5].style.bg.indexed == Color.Blue
    check Bold in buffer[5, 5].style.modifiers

  test "Terminal with unicode content":
    let terminal = createTestTerminal()
    var buffer = newBuffer(20, 10)

    # Add unicode characters - wide chars go through setCell so shadow cells
    # are placed correctly.
    buffer[0, 0] = cell("α")
    buffer[1, 0] = cell("β")
    buffer.setCell(2, 0, "🚀", 2)
    buffer.setCell(4, 0, "🌟", 2)

    # Terminal should handle unicode content in lastBuffer
    terminal.lastBuffer = buffer
    check terminal.lastBuffer[0, 0].symbol == "α"
    check terminal.lastBuffer[2, 0].symbol == "🚀"

  test "Terminal buffer operations":
    let terminal = createTestTerminal()
    var buffer = newBuffer(terminal.getArea())

    # Fill buffer with pattern
    for y in 0 ..< buffer.area.height:
      for x in 0 ..< buffer.area.width:
        if (x + y) mod 2 == 0:
          buffer[x, y] = cell("#")
        else:
          buffer[x, y] = cell(".")

    # Terminal should work with its own area-sized buffer
    terminal.lastBuffer = buffer
    check terminal.lastBuffer.area == terminal.getArea()
    check terminal.lastBuffer[0, 0].symbol == "#"
    check terminal.lastBuffer[1, 0].symbol == "."
    check terminal.lastBuffer[0, 1].symbol == "."
    check terminal.lastBuffer[1, 1].symbol == "#"

suite "Async Adopt Rendering":
  test "drawWithCursorAdoptAsync swaps AsyncBuffer when areas match":
    let terminal = createTestTerminal()
    terminal.lastBuffer = newBuffer(10, 5)
    terminal.lastBuffer[0, 0] = cell("OLD")

    let asyncBuffer = newAsyncBuffer(10, 5)
    asyncBuffer.withBuffer:
      buffer[0, 0] = cell("NEW")

    discard waitFor terminal.drawWithCursorAdoptAsync(
      asyncBuffer, 0, 0, false, CursorStyle.Default, CursorStyle.Default, force = true
    )

    check terminal.lastBuffer[0, 0].symbol == "NEW"
    asyncBuffer.withBuffer:
      check buffer[0, 0].symbol == "OLD"

  test "drawWithCursorAdoptAsync copies AsyncBuffer when areas differ":
    let terminal = createTestTerminal()
    terminal.lastBuffer = newBuffer(5, 5)
    terminal.lastBuffer[0, 0] = cell("OLD")

    let asyncBuffer = newAsyncBuffer(10, 5)
    asyncBuffer.withBuffer:
      buffer[0, 0] = cell("NEW")

    discard waitFor terminal.drawWithCursorAdoptAsync(
      asyncBuffer, 0, 0, false, CursorStyle.Default, CursorStyle.Default, force = true
    )

    check terminal.lastBuffer[0, 0].symbol == "NEW"
    asyncBuffer.withBuffer:
      check buffer[0, 0].symbol == "NEW"
      check buffer.area == terminal.lastBuffer.area

  test "drawWithCursorAdoptAsync recycles AsyncBuffer across frames":
    let terminal = createTestTerminal()
    let asyncBuffer = newAsyncBuffer(10, 5)

    for i in 0 ..< 3:
      asyncBuffer.withBuffer:
        buffer.clear()
        buffer[0, 0] = cell($i)
      discard waitFor terminal.drawWithCursorAdoptAsync(
        asyncBuffer, 0, 0, false, CursorStyle.Default, CursorStyle.Default, force = true
      )
      check terminal.lastBuffer[0, 0].symbol == $i

  test "drawWithCursorAdoptAsync keeps lastBuffer in sync with rendered diffs":
    # Regression for the commit-before-await reorder: `lastBuffer` is adopted from
    # the grid that produced the bytes (no await sits between reading the live
    # grid and the swap), so after every frame it must equal what was rendered and
    # the next frame's diff baseline stays correct. Uses force = false to exercise
    # the differential (swap) path, not a full redraw.
    let terminal = createTestTerminal()
    terminal.lastBuffer = newBuffer(10, 5) # match the AsyncBuffer area (swap path)
    let asyncBuffer = newAsyncBuffer(10, 5)

    for i in 0 ..< 4:
      asyncBuffer.withBuffer:
        buffer.clear()
        buffer[i, 0] = cell($i)
      discard waitFor terminal.drawWithCursorAdoptAsync(
        asyncBuffer,
        0,
        0,
        false,
        CursorStyle.Default,
        CursorStyle.Default,
        force = false,
      )
      check terminal.lastBuffer[i, 0].symbol == $i
      if i > 0:
        # The previous frame's cell must be gone from the adopted baseline.
        check terminal.lastBuffer[i - 1, 0].symbol != $(i - 1)

  test "drawWithCursorAdoptAsync rolls back lastBuffer when the write sends nothing":
    # On the steady-state swap path, `lastBuffer` is adopted before the write, so
    # a task that mutates the grid during a flow-controlled write cannot corrupt
    # it. If the frame does not go out in full, the swap is rolled back and the
    # caller keeps the grid it rendered.
    let terminal = createTestTerminal()
    terminal.lastBuffer = newBuffer(10, 5)
    terminal.lastBuffer[0, 0] = cell("OLD")

    let asyncBuffer = newAsyncBuffer(10, 5)
    asyncBuffer.withBuffer:
      buffer[0, 0] = cell("NEW")

    # Redirect stdout (fd 1) to a read-only fd so the underlying posix.write
    # fails with EBADF and the frame is never sent. Save and restore the
    # original fd so only this test is affected.
    let savedStdout = posix.dup(STDOUT_FILENO)
    let roFd = posix.open("/dev/null", O_RDONLY)
    require savedStdout >= 0
    require roFd >= 0

    var rolledBackStyle: CursorStyle
    try:
      discard posix.dup2(roFd, STDOUT_FILENO)
      rolledBackStyle = waitFor terminal.drawWithCursorAdoptAsync(
        asyncBuffer, 0, 0, false, CursorStyle.Default, CursorStyle.Default, force = true
      )
    finally:
      discard posix.dup2(savedStdout, STDOUT_FILENO)
      discard posix.close(savedStdout)
      discard posix.close(roFd)

    # lastBuffer must be rolled back to the pre-write state.
    check terminal.lastBuffer[0, 0].symbol == "OLD"
    # The cursor style was never applied either.
    check rolledBackStyle == CursorStyle.Default
    # The AsyncBuffer still owns the freshly rendered grid.
    asyncBuffer.withBuffer:
      check buffer[0, 0].symbol == "NEW"

    # Nothing was emitted, so only the forced invalidation makes the next frame
    # a full render, and no reset is owed.
    var expected: string
    asyncBuffer.withBuffer:
      expected = buildOutputWithCursor(
        terminal.lastBuffer,
        buffer,
        0,
        0,
        false,
        lastCursorStyle = CursorStyle.Default,
        force = true,
      ).output
    let output = captureStdout(
      proc() =
        discard waitFor terminal.drawWithCursorAdoptAsync(
          asyncBuffer, 0, 0, false, CursorStyle.Default, CursorStyle.Default
        )
    )
    check output == wrapWithSyncOutput(expected)

suite "AsyncTerminal Performance Considerations":
  test "Large buffer handling":
    let terminal = createTestTerminal()
    let hugeBuffer = newBuffer(200, 100) # Large buffer

    # Terminal should handle large buffers in lastBuffer
    terminal.lastBuffer = hugeBuffer
    check terminal.lastBuffer.area.width == 200
    check terminal.lastBuffer.area.height == 100
    check terminal.lastBuffer.area.area() == 20000

  test "Repeated rendering with minimal changes":
    let terminal = createTestTerminal()
    var buffer1 = newBuffer(50, 20)
    var buffer2 = newBuffer(50, 20)

    # Terminal should track buffer changes for efficient rendering
    terminal.lastBuffer = buffer1
    let originalArea = terminal.lastBuffer.area

    terminal.lastBuffer = buffer2
    check terminal.lastBuffer.area == originalArea # Same dimensions

    # Identical buffers should have no differences
    let noDiff = buffer1.diff(buffer2)
    check noDiff.len == 0

    # Small change should have minimal diff
    buffer2[10, 10] = cell("X")
    let smallDiff = buffer1.diff(buffer2)
    check smallDiff.len == 1

  test "Buffer memory efficiency":
    # Test that buffers don't use excessive memory
    let smallBuffer = newBuffer(1, 1)
    let mediumBuffer = newBuffer(80, 24)

    # Should create buffers efficiently
    check smallBuffer.area.area() == 1
    check mediumBuffer.area.area() == 1920

suite "AsyncTerminal Boundary Conditions":
  test "Minimum size terminal":
    # Test with very small terminal size
    var minBuffer = newBuffer(1, 1)
    check minBuffer.area.width == 1
    check minBuffer.area.height == 1

    minBuffer[0, 0] = cell("X")
    check minBuffer[0, 0].symbol == "X"

  test "Terminal position edge cases":
    # Test position values for cursor positioning
    let pos1 = pos(0, 0) # Top-left
    let pos2 = pos(-1, -1) # Negative
    let pos3 = pos(1000, 1000) # Large values

    check pos1.x == 0 and pos1.y == 0
    check pos2.x == -1 and pos2.y == -1
    check pos3.x == 1000 and pos3.y == 1000

  test "Buffer overflow protection":
    var buffer = newBuffer(5, 3)

    # Accessing out-of-bounds should be safe
    let outOfBounds = buffer[100, 100]
    check outOfBounds.symbol == " " # Should return empty cell

suite "AsyncTerminal Common Module Integration":
  test "Terminal uses common ANSI sequences":
    # Test that common sequences are accessible
    check AlternateScreenEnter == "\e[?1049h"
    check AlternateScreenExit == "\e[?1049l"
    check HideCursorSeq == "\e[?25l"
    check ShowCursorSeq == "\e[?25h"

  test "Terminal size detection integration":
    let (width, height, success) = getTerminalSizeFromSystem()
    let asyncSize = getTerminalSizeAsync()

    # Both should return reasonable values
    check asyncSize.width > 0
    check asyncSize.height > 0

    if success:
      # If system detection works, both should agree
      check asyncSize.width == width
      check asyncSize.height == height
    else:
      # Fallback should be used
      check asyncSize.width >= 10
      check asyncSize.height >= 5

  test "Mouse mode integration":
    let enableSeq = enableMouseMode(MouseSGR)
    let disableSeq = disableMouseMode(MouseSGR)

    check enableSeq.len > 0
    check disableSeq.len > 0
    check enableSeq != disableSeq

  test "Render batch integration":
    var buffer1 = newBuffer(5, 3)
    var buffer2 = newBuffer(5, 3)

    buffer2[1, 1] = cell("T", defaultStyle())
    buffer2[2, 2] = cell("E", defaultStyle())

    let output = buildDifferentialOutput(buffer1, buffer2)
    check output.len > 0
    check output.find("T") >= 0
    check output.find("E") >= 0

suite "AsyncTerminal Cursor Control":
  test "Cursor movement sequences are valid":
    # Test that cursor movement sequences are properly formatted
    let upSeq = makeCursorMoveSeq(CursorUpSeq, 3)
    let downSeq = makeCursorMoveSeq(CursorDownSeq, 5)
    let leftSeq = makeCursorMoveSeq(CursorLeftSeq, 2)
    let rightSeq = makeCursorMoveSeq(CursorRightSeq, 4)

    check upSeq.contains("3")
    check downSeq.contains("5")
    check leftSeq.contains("2")
    check rightSeq.contains("4")

    # Single step uses shorter sequence
    let singleUp = makeCursorMoveSeq(CursorUpSeq, 1)
    check singleUp == CursorUpSeq

  test "Save and restore cursor sequences":
    check SaveCursorSeq == "\e[s"
    check RestoreCursorSeq == "\e[u"

  test "Cursor style sequences are valid":
    check getCursorStyleSeq(CursorStyle.Default) == CursorStyleDefault
    check getCursorStyleSeq(CursorStyle.BlinkingBlock) == CursorStyleBlinkingBlock
    check getCursorStyleSeq(CursorStyle.SteadyBlock) == CursorStyleSteadyBlock
    check getCursorStyleSeq(CursorStyle.BlinkingUnderline) ==
      CursorStyleBlinkingUnderline
    check getCursorStyleSeq(CursorStyle.SteadyUnderline) == CursorStyleSteadyUnderline
    check getCursorStyleSeq(CursorStyle.BlinkingBar) == CursorStyleBlinkingBar
    check getCursorStyleSeq(CursorStyle.SteadyBar) == CursorStyleSteadyBar

suite "AsyncTerminal Line Clearing":
  test "Clear line sequences are valid":
    check ClearLineSeq == "\e[2K"
    check ClearToEndOfLineSeq == "\e[0K"
    check ClearToStartOfLineSeq == "\e[1K"

  test "Clear sequences are different":
    check ClearLineSeq != ClearToEndOfLineSeq
    check ClearLineSeq != ClearToStartOfLineSeq
    check ClearToEndOfLineSeq != ClearToStartOfLineSeq

suite "AsyncTerminal Setup Variants":
  test "setupWithHiddenCursorAsync exists":
    # Test that the proc exists and has correct signature
    let terminal = createTestTerminal()
    # We can't actually call it without a real terminal, but we can verify it compiles
    when compiles(terminal.setupWithHiddenCursorAsync()):
      check true
    else:
      check false

suite "AsyncTerminal Cleanup":
  # Note: rawMode is exercised separately because enableRawMode calls
  # tcsetattr() on the real terminal. The flags toggled below only
  # require stdout writes and are safe in tests.

  test "cleanup resets all toggleable flags":
    let terminal = createTestTerminal()

    terminal.enableAlternateScreen()
    terminal.enableMouse()
    terminal.enableBracketedPaste()
    terminal.enableFocusEvents()
    terminal.enableSyncOutput()

    check terminal.alternateScreen
    check terminal.mouseEnabled
    check terminal.bracketedPasteEnabled
    check terminal.focusEventsEnabled
    check terminal.syncOutputEnabled

    terminal.cleanup()

    check not terminal.alternateScreen
    check not terminal.mouseEnabled
    check not terminal.bracketedPasteEnabled
    check not terminal.focusEventsEnabled
    check not terminal.syncOutputEnabled

  test "cleanup is idempotent":
    let terminal = createTestTerminal()
    terminal.enableMouse()
    terminal.enableBracketedPaste()

    terminal.cleanup()
    check not terminal.mouseEnabled
    check not terminal.bracketedPasteEnabled

    terminal.cleanup()
    check not terminal.mouseEnabled
    check not terminal.bracketedPasteEnabled

  test "cleanup with partial state disables only enabled flags":
    let terminal = createTestTerminal()
    terminal.enableMouse()
    terminal.enableBracketedPaste()

    check terminal.mouseEnabled
    check terminal.bracketedPasteEnabled
    check not terminal.alternateScreen
    check not terminal.focusEventsEnabled
    check not terminal.syncOutputEnabled

    terminal.cleanup()

    check not terminal.mouseEnabled
    check not terminal.bracketedPasteEnabled
    check not terminal.alternateScreen
    check not terminal.focusEventsEnabled
    check not terminal.syncOutputEnabled

  test "cleanup on freshly created terminal is safe":
    let terminal = createTestTerminal()
    terminal.cleanup()
    check not terminal.alternateScreen
    check not terminal.mouseEnabled
    check not terminal.bracketedPasteEnabled
    check not terminal.focusEventsEnabled
    check not terminal.syncOutputEnabled

  test "cleanup disables flag enabled last (LIFO end of sequence)":
    # alternateScreen is the final disable step in cleanup's LIFO order,
    # so this guards against accidentally truncating the sequence.
    let terminal = createTestTerminal()
    terminal.enableAlternateScreen()
    check terminal.alternateScreen

    terminal.cleanup()
    check not terminal.alternateScreen

suite "AsyncTerminal emergencyRestore":
  test "emergencyRestore resets all toggleable flags":
    let terminal = createTestTerminal()

    terminal.enableAlternateScreen()
    terminal.enableMouse()
    terminal.enableBracketedPaste()
    terminal.enableFocusEvents()
    terminal.enableSyncOutput()

    terminal.emergencyRestore()

    check not terminal.alternateScreen
    check not terminal.mouseEnabled
    check not terminal.bracketedPasteEnabled
    check not terminal.focusEventsEnabled
    check not terminal.syncOutputEnabled

  test "emergencyRestore on freshly created terminal is safe":
    let terminal = createTestTerminal()
    terminal.emergencyRestore()
    terminal.emergencyRestore()
    check not terminal.alternateScreen

  test "emergencyRestore leaves the mode flags set when the write fails":
    # A later cleanup must still see the modes a failed reset left enabled.
    let terminal = createTestTerminal()
    terminal.enableAlternateScreen()
    terminal.enableMouse()
    let savedStdout = posix.dup(STDOUT_FILENO)
    let roFd = posix.open("/dev/null", O_RDONLY)
    require savedStdout >= 0
    require roFd >= 0
    try:
      discard posix.dup2(roFd, STDOUT_FILENO)
      terminal.emergencyRestore()
    finally:
      discard posix.dup2(savedStdout, STDOUT_FILENO)
      discard posix.close(savedStdout)
      discard posix.close(roFd)

    check terminal.alternateScreen
    check terminal.mouseEnabled
    terminal.cleanup()

suite "AsyncTerminal cleanupAsync":
  test "cleanupAsync resets all toggleable flags":
    let terminal = createTestTerminal()

    terminal.enableAlternateScreen()
    terminal.enableMouse()
    terminal.enableBracketedPaste()
    terminal.enableFocusEvents()
    terminal.enableSyncOutput()

    waitFor terminal.cleanupAsync()

    check not terminal.alternateScreen
    check not terminal.mouseEnabled
    check not terminal.bracketedPasteEnabled
    check not terminal.focusEventsEnabled
    check not terminal.syncOutputEnabled

  test "cleanupAsync is idempotent":
    let terminal = createTestTerminal()
    terminal.enableMouse()

    waitFor terminal.cleanupAsync()
    check not terminal.mouseEnabled

    waitFor terminal.cleanupAsync()
    check not terminal.mouseEnabled

  when hasChronos:
    proc enableAllModes(terminal: AsyncTerminal) =
      terminal.enableAlternateScreen()
      terminal.enableMouse()
      terminal.enableBracketedPaste()
      terminal.enableFocusEvents()
      terminal.enableSyncOutput()

    proc checkAllModesOff(terminal: AsyncTerminal) =
      check not terminal.alternateScreen
      check not terminal.mouseEnabled
      check not terminal.bracketedPasteEnabled
      check not terminal.focusEventsEnabled
      check not terminal.syncOutputEnabled

    proc allModesOff(terminal: AsyncTerminal): bool =
      not (
        terminal.alternateScreen or terminal.mouseEnabled or
        terminal.bracketedPasteEnabled or terminal.focusEventsEnabled or
        terminal.syncOutputEnabled
      )

    proc cancelCleanupWhileParked(
        terminal: AsyncTerminal, cancels: int, restoredBeforeUnlock: var bool
    ): Future[void] =
      ## Start cleanupAsync behind a held stdout lock and request `cancels`
      ## cancels, letting each land before the next. The first cancel moves it
      ## to the emergency reset, still parked; a second one makes it restore
      ## with a blocking write and return while the lock is still held.
      doAssert tryAcquireStdoutLockImmediate()
      try:
        result = terminal.cleanupAsync()
        for _ in 1 .. cancels:
          result.cancelSoon()
          waitFor sleepAsync(1.milliseconds)
        doAssert result.finished == (cancels >= 2)
        restoredBeforeUnlock = terminal.allModesOff()
      finally:
        releaseStdoutLock()
      waitFor result.join()
      # Let a dropped background reset wind down; it must write nothing.
      waitFor sleepAsync(5.milliseconds)

    proc cancelCleanupWhileParked(
        cancels: int
    ): (AsyncTerminal, Future[void], string, bool) =
      ## Enable every mode, then run the cancelled cleanup with stdout captured.
      let terminal = createTestTerminal()
      var fut: Future[void]
      var restoredBeforeUnlock = false
      let output = captureStdout(
        proc() =
          terminal.enableAllModes()
          fut = terminal.cancelCleanupWhileParked(cancels, restoredBeforeUnlock)
      )
      (terminal, fut, output, restoredBeforeUnlock)

    test "cancelled cleanupAsync restores the terminal and re-raises":
      # The cancel lands on the cursor write. The remaining steps are replaced
      # by the emergency reset, and the cancel reaches the caller.
      let (terminal, fut, output, _) = cancelCleanupWhileParked(1)
      check fut.cancelled
      terminal.checkAllModesOff()
      check output.endsWith(EmergencyResetAltScreenSeq)
      check output.count(ShowCursorSeq) == 1

    test "a second cancel restores the terminal before returning":
      # The second cancel lands while the reset is parked. The caller may exit
      # right away, so cleanupAsync restores with a blocking write first, and
      # the dropped background reset must not write it again.
      let (terminal, fut, output, restoredBeforeUnlock) = cancelCleanupWhileParked(2)
      check restoredBeforeUnlock
      check fut.cancelled
      terminal.checkAllModesOff()
      check output.endsWith(EmergencyResetAltScreenSeq)
      check output.count(ShowCursorSeq) == 1

    test "a failed emergency reset leaves the mode flags set":
      # With stdout unwritable the reset cannot go out, so the flags must keep
      # saying the modes are on for a later cleanup to retry them.
      let terminal = createTestTerminal()
      discard captureStdout(
        proc() =
          terminal.enableAllModes()
      )
      let savedStdout = posix.dup(STDOUT_FILENO)
      let roFd = posix.open("/dev/null", O_RDONLY)
      require savedStdout >= 0
      require roFd >= 0
      var fut: Future[void]
      try:
        discard posix.dup2(roFd, STDOUT_FILENO)
        var restoredBeforeUnlock: bool
        fut = terminal.cancelCleanupWhileParked(1, restoredBeforeUnlock)
      finally:
        discard posix.dup2(savedStdout, STDOUT_FILENO)
        discard posix.close(savedStdout)
        discard posix.close(roFd)

      check fut.cancelled
      check terminal.alternateScreen
      check terminal.mouseEnabled
      check terminal.syncOutputEnabled
