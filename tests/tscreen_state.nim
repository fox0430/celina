# Test suite for the screen_state module

import std/[unittest, strutils]

import
  ../celina/core/
    [buffer, colors, geometry, terminal_common, output_stream, screen_state]

proc knownScreen(width, height: int): ScreenState =
  ## A screen state whose last frame went out in full: `lastBuffer` is blank at
  ## the size and the screen is known. The transitions are the only way to reach
  ## a known screen, so the tests build it the way a terminal does.
  result.lastBuffer = newBuffer(width, height)
  let blank = newBuffer(width, height)
  result.finish(result.planFrame(blank, noCursor, false), blank, swAll)

suite "Screen state: planning":
  test "a known screen of the same size plans a diff":
    var state = knownScreen(4, 2)
    var frame = newBuffer(4, 2)
    frame[1, 0] = cell("x")

    let plan = state.planFrame(frame, noCursor, false)
    check plan.kind == pkFrame
    check plan.bytes == buildDifferentialOutput(state.lastBuffer, frame)

  test "an unknown screen plans a full render":
    var state = knownScreen(4, 2)
    var frame = newBuffer(4, 2)
    frame[1, 0] = cell("x")
    state.invalidate()

    check state.planFrame(frame, noCursor, false).bytes == buildFullRenderOutput(frame)
    # `lastBuffer` is kept; `known` alone makes the next frame a full render.
    check state.lastBuffer.area == rect(0, 0, 4, 2)

  test "a size change plans a full render":
    var state = knownScreen(4, 2)
    let frame = newBuffer(6, 3)

    check state.planFrame(frame, noCursor, false).bytes == buildFullRenderOutput(frame)

  test "the wrap only applies when asked, and a wrapped frame needs the block ended":
    var state = knownScreen(4, 2)
    var frame = newBuffer(4, 2)
    frame[1, 0] = cell("x")

    let unwrapped = state.planFrame(frame, noCursor, false)
    check unwrapped.bytes == buildDifferentialOutput(newBuffer(4, 2), frame)
    check srSyncEnd notin unwrapped.onPartial
    check unwrapped.onPartial == {srOsc8, srSgr}

    let wrapped = state.planFrame(frame, noCursor, true)
    check wrapped.bytes ==
      wrapWithSyncOutput(buildDifferentialOutput(newBuffer(4, 2), frame))
    check wrapped.onPartial == {srOsc8, srSgr, srSyncEnd}

    # A full render is wrapped the same way.
    state.invalidate()
    let full = state.planFrame(frame, noCursor, true)
    check full.bytes == wrapWithSyncOutput(buildFullRenderOutput(frame))

  test "an empty frame plans no bytes":
    var state = knownScreen(4, 2)
    let plan = state.planFrame(newBuffer(4, 2), noCursor, true)
    check plan.bytes == ""
    # Nothing goes out, so the reset set is never used.
    check plan.onPartial == {srOsc8, srSgr}

  test "a cursor request appends its commands inside the wrap":
    var state = knownScreen(4, 2)
    let request = CursorRequest(
      enabled: true,
      x: 2,
      y: 1,
      visible: true,
      style: SteadyBar,
      lastStyle: CursorStyle.Default,
    )
    let plan = state.planFrame(newBuffer(4, 2), request, true)

    let (expected, style) = buildOutputWithCursor(
      state.lastBuffer, newBuffer(4, 2), 2, 1, true, SteadyBar, CursorStyle.Default
    )
    check plan.bytes == wrapWithSyncOutput(expected)
    check plan.appliedStyle(swAll) == style
    check plan.appliedStyle(swPartial) == CursorStyle.Default
    # The cursor commands are inside the wrap, not after it.
    check SyncOutputDisable notin plan.bytes[0 ..< expected.len]

  test "a hidden or out-of-range cursor hides the cursor instead":
    var state = knownScreen(4, 2)
    let hidden = state.planFrame(
      newBuffer(4, 2),
      CursorRequest(enabled: true, x: 2, y: 1, visible: false, lastStyle: Default),
      false,
    )
    check hidden.bytes.endsWith(HideCursorSeq)

  test "a clear plans a bare reset-and-clear at the cleared size":
    var state = knownScreen(4, 2)
    let plan = state.planClear(size(6, 3))
    check plan.kind == pkClear
    check plan.bytes == ResetAndClearScreenSeq
    # A partial clear leaves nothing open the next write must undo.
    check plan.onPartial == {}

suite "Screen state: recording the outcome":
  test "swAll adopts the frame and keeps the screen known":
    var state = knownScreen(4, 2)
    var frame = newBuffer(4, 2)
    frame[1, 0] = cell("x")
    var plan = state.planFrame(frame, noCursor, false)

    state.stage(plan, frame)
    state.finishAdopt(plan, frame, swAll)

    check state.known
    check state.lastBuffer[1, 0].symbol == "x"

  test "swNone keeps the screen known and lastBuffer unchanged":
    var state = knownScreen(4, 2)
    var frame = newBuffer(4, 2)
    frame[1, 0] = cell("x")
    var plan = state.planFrame(frame, noCursor, false)

    state.stage(plan, frame)
    state.finishAdopt(plan, frame, swNone)

    # A write that sent nothing left the screen exactly as it was, so the next
    # frame is the same diff again, not a full repaint.
    check state.known
    check state.lastBuffer[1, 0].symbol == " "
    check state.planFrame(frame, noCursor, false).bytes ==
      buildDifferentialOutput(newBuffer(4, 2), frame)

  test "swPartial rolls the adopt back and marks the screen unknown":
    var state = knownScreen(4, 2)
    var frame = newBuffer(4, 2)
    frame[1, 0] = cell("x")
    var plan = state.planFrame(frame, noCursor, false)

    state.stage(plan, frame)
    state.finishAdopt(plan, frame, swPartial)

    check not state.known
    # The caller keeps the grid it rendered; `lastBuffer` holds only frames the
    # screen showed.
    check state.lastBuffer[1, 0].symbol == " "
    check frame[1, 0].symbol == "x"

  test "the copy variant commits the caller's buffer":
    var state = knownScreen(4, 2)
    var frame = newBuffer(4, 2)
    frame[1, 0] = cell("x")

    state.finish(state.planFrame(frame, noCursor, false), frame, swAll)
    check state.known
    check state.lastBuffer[1, 0].symbol == "x"

  test "the copy variant takes nothing for a write that sent nothing":
    # A copy is not staged, so there is nothing to roll back: `lastBuffer` keeps
    # the frame it already had, never the one that never went out.
    var state = knownScreen(4, 2)
    var shown = newBuffer(4, 2)
    shown[0, 0] = cell("a")
    state.finish(state.planFrame(shown, noCursor, false), shown, swAll)

    var unsent = newBuffer(4, 2)
    unsent[1, 0] = cell("b")
    state.invalidate()
    state.finish(state.planFrame(unsent, noCursor, false), unsent, swNone)

    check not state.known
    check state.lastBuffer[0, 0].symbol == "a"
    check state.lastBuffer[1, 0].symbol == " "

  test "the copy variant takes nothing for a partial write":
    var state = knownScreen(4, 2)
    var shown = newBuffer(4, 2)
    shown[0, 0] = cell("a")
    state.finish(state.planFrame(shown, noCursor, false), shown, swAll)

    var partial = newBuffer(4, 2)
    partial[1, 0] = cell("b")
    state.finish(state.planFrame(partial, noCursor, false), partial, swPartial)

    check not state.known
    check state.lastBuffer[0, 0].symbol == "a"
    check state.lastBuffer[1, 0].symbol == " "

  test "a clear that goes out in full records a blank screen":
    var state = knownScreen(4, 2)
    let plan = state.planClear(size(6, 3))
    state.finishClear(plan, swAll)

    check state.known
    check state.lastBuffer == newBuffer(6, 3)

  test "a clear that sends nothing leaves the screen as it was":
    var state = knownScreen(4, 2)
    state.invalidate()
    state.finishClear(state.planClear(size(6, 3)), swNone)

    check not state.known
    check state.lastBuffer.area == rect(0, 0, 4, 2)

  test "a partial write is recorded even when nothing was staged":
    var state = knownScreen(4, 2)
    state.finish(
      state.planFrame(newBuffer(4, 2), noCursor, false), newBuffer(4, 2), swPartial
    )
    check not state.known

suite "Screen state: adopt":
  test "staging swaps when the areas match and rolls back on failure":
    var state = knownScreen(4, 2)
    state.lastBuffer[0, 0] = cell("old")
    var frame = newBuffer(4, 2)
    frame[0, 0] = cell("new")
    var plan = state.planFrame(frame, noCursor, false)

    state.stage(plan, frame)
    check state.lastBuffer[0, 0].symbol == "new"
    check frame[0, 0].symbol == "old"

    state.finishAdopt(plan, frame, swPartial)
    check state.lastBuffer[0, 0].symbol == "old"
    check frame[0, 0].symbol == "new"

  test "staging copies when the areas differ, so the caller keeps its size":
    var state = knownScreen(4, 2)
    var frame = newBuffer(6, 3)
    var plan = state.planFrame(frame, noCursor, false)

    state.stage(plan, frame)
    check state.lastBuffer.area == rect(0, 0, 4, 2)
    check frame.area == rect(0, 0, 6, 3)

    state.finishAdopt(plan, frame, swAll)
    check state.lastBuffer.area == rect(0, 0, 6, 3)
    check frame.area == rect(0, 0, 6, 3)

  test "a staged frame is adopted clean":
    var state = knownScreen(4, 2)
    var frame = newBuffer(4, 2)
    frame[0, 0] = cell("new")
    frame.markDirty(0, 0)
    var plan = state.planFrame(frame, noCursor, false)

    state.stage(plan, frame)
    state.finishAdopt(plan, frame, swAll)
    check not state.lastBuffer.isDirty()

suite "Screen state: epoch":
  # The state can change without the stdout lock: a user `invalidate`, a
  # `suspend`, another task's `resume`. A frame that was planned before such a
  # change must not claim a known screen when it lands.

  test "invalidate marks the screen unknown and the next frame is a full render":
    var state = knownScreen(4, 2)
    var frame = newBuffer(4, 2)
    frame[1, 0] = cell("x")
    check state.planFrame(frame, noCursor, false).bytes ==
      buildDifferentialOutput(newBuffer(4, 2), frame)

    state.invalidate()
    check not state.known
    check state.planFrame(frame, noCursor, false).bytes == buildFullRenderOutput(frame)

  test "a copy frame that went out in full does not claim a known screen":
    var state = knownScreen(4, 2)
    var frame = newBuffer(4, 2)
    frame[1, 0] = cell("x")
    let plan = state.planFrame(frame, noCursor, false)

    state.invalidate() # e.g. `suspend` while the write was in flight
    state.finish(plan, frame, swAll)

    check not state.known
    # The frame did go out, so it is still the screen model.
    check state.lastBuffer == frame

  test "a staged frame that went out in full does not claim a known screen":
    var state = knownScreen(4, 2)
    var frame = newBuffer(4, 2)
    frame[1, 0] = cell("x")
    var plan = state.planFrame(frame, noCursor, false)

    state.stage(plan, frame)
    state.invalidate() # e.g. `suspend` while the write was in flight
    state.finishAdopt(plan, frame, swAll)

    check not state.known
    check state.lastBuffer[1, 0].symbol == "x"

  test "a clear that went out in full does not claim a known screen either":
    var state = knownScreen(4, 2)
    let plan = state.planClear(size(6, 3))

    state.invalidate()
    state.finishClear(plan, swAll)

    check not state.known
    check state.lastBuffer == newBuffer(6, 3)

  test "without an intervening change the screen stays known":
    var state = knownScreen(4, 2)
    let frame = newBuffer(4, 2)
    state.finish(state.planFrame(frame, noCursor, false), frame, swAll)
    check state.known

suite "Screen state: cursor style":
  test "a frame that went out in full applies the new cursor style":
    var state = knownScreen(4, 2)
    let plan = state.planFrame(
      newBuffer(4, 2),
      CursorRequest(
        enabled: true,
        x: 0,
        y: 0,
        visible: true,
        style: SteadyBar,
        lastStyle: CursorStyle.Default,
      ),
      false,
    )
    check plan.appliedStyle(swAll) == SteadyBar

  test "any other outcome keeps the previous style, so it is sent again":
    var state = knownScreen(4, 2)
    let plan = state.planFrame(
      newBuffer(4, 2),
      CursorRequest(
        enabled: true,
        x: 0,
        y: 0,
        visible: true,
        style: SteadyBar,
        lastStyle: CursorStyle.Default,
      ),
      false,
    )
    check plan.appliedStyle(swPartial) == CursorStyle.Default
    check plan.appliedStyle(swNone) == CursorStyle.Default

  test "an unchanged style is not sent":
    var state = knownScreen(4, 2)
    let plan = state.planFrame(
      newBuffer(4, 2),
      CursorRequest(
        enabled: true, x: 0, y: 0, visible: true, style: SteadyBar, lastStyle: SteadyBar
      ),
      false,
    )
    check getCursorStyleSeq(SteadyBar) notin plan.bytes
    check plan.appliedStyle(swAll) == SteadyBar

  test "a path without cursor handling leaves the style alone":
    var state = knownScreen(4, 2)
    let plan = state.planFrame(newBuffer(4, 2), noCursor, false)
    check plan.appliedStyle(swAll) == CursorStyle.Default
    check ShowCursorSeq notin plan.bytes
    check HideCursorSeq notin plan.bytes
