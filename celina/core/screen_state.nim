## Screen state: what the terminal shows, and the one frame protocol
##
## While `known`, `lastBuffer` is on screen and the next frame may be a diff;
## unknown (cut write, `suspend`, `invalidate`) forces a full render. A write
## that sent nothing keeps the screen known.
##
## Present paths plan one frame, write it, record the outcome. Copy paths use
## `finish`; adopt paths `stage` before the write and `finishAdopt` after:
##
## ```nim
## if force: screen.invalidate()
## var plan = screen.planFrame(buffer, cursor, wrap)
## when adopt:
##   screen.stage(plan, buffer)
## let outcome = outcomeOf(writeStream(plan.bytes, plan.onPartial), plan.bytes.len)
## when adopt:
##   screen.finishAdopt(plan, buffer, outcome)
## else:
##   screen.finish(plan, buffer, outcome)
## ```
##
## `planFrame` decides full-vs-diff, appends cursor commands, wraps in sync
## output and names the partial-write reset. `stage`/`finishAdopt` keep
## `lastBuffer` to frames actually shown. Writes live in output_stream.nim.
##
## Pure: no I/O, shared by both backends and driven directly by tests.

import buffer, geometry, terminal_common, output_stream

type
  ScreenState* = object
    lastBuffer: Buffer ## the frame the screen showed, while `known`
    known: bool
    epoch: int ## bumped by every change to unknown

  CursorRequest* = object
    enabled*: bool ## false for the paths that leave the cursor alone
    x*, y*: int
    visible*: bool
    style*, lastStyle*: CursorStyle

  PlanKind* = enum
    pkFrame ## a frame: a full render or a diff against `lastBuffer`
    pkClear ## a full-screen clear; `lastBuffer` becomes blank

  FramePlan* = object
    bytes*: string ## ready to write; "" = nothing to write
    onPartial*: set[StreamReset] ## what a partial write of these bytes needs undone
    kind*: PlanKind
    epoch: int ## `ScreenState.epoch` when the plan was made
    newStyle, lastStyle: CursorStyle
    clearedSize: Size ## pkClear: the size of the blank `lastBuffer`
    staged: bool ## pkFrame: `lastBuffer` already holds the frame

  Presented* = object ## What a present path reports back
    outcome*: StreamWrite ## how much of the frame went out
    style*: CursorStyle ## the cursor style the terminal now shows

const noCursor* = CursorRequest()
  ## The request of a path that leaves the cursor alone (`draw`, the low-level
  ## `render`): no cursor commands, and the tracked style does not change.

proc lastBuffer*(s: var ScreenState): var Buffer {.inline.} =
  ## The frame the terminal shows while the screen is known. Writable, as in
  ## v0.13.0: assigning it or mutating a cell still compiles, and assigning a
  ## buffer of another size makes the next frame a full render.
  s.lastBuffer

proc `lastBuffer=`*(s: var ScreenState, buffer: Buffer) {.inline.} =
  ## Assignment half of `lastBuffer`. Needed separately because a `var` return
  ## alone is not an assignment target on Nim 2.0.x.
  s.lastBuffer = buffer

proc known*(s: ScreenState): bool {.inline.} =
  ## Whether `lastBuffer` is what the screen shows.
  s.known

proc invalidate*(s: var ScreenState) =
  ## Mark unknown so the next frame is a full render. For off-model writes
  ## (free `clearScreen`, `renderCell`, another program) and forced frames.
  s.known = false
  inc s.epoch

proc planFrame*(
    s: ScreenState, buffer: Buffer, cursor: CursorRequest, wrap: bool
): FramePlan =
  ## Plan the next frame: full render while unknown or after resize, else diff.
  ## `wrap` adds DEC 2026 sync output (and `srSyncEnd` to `onPartial`); pass
  ## false when unwrapped or app-managed. Cursor commands go inside the wrap.
  result.epoch = s.epoch
  result.lastStyle = cursor.lastStyle
  if not s.known or needsFullRender(s.lastBuffer, buffer, false):
    result.bytes = buildFullRenderOutput(buffer)
  else:
    result.bytes = buildDifferentialOutput(s.lastBuffer, buffer)
  if cursor.enabled:
    result.newStyle = appendCursorCommands(
      result.bytes, cursor.x, cursor.y, cursor.visible, cursor.style, cursor.lastStyle
    )
  else:
    result.newStyle = cursor.lastStyle
  if wrap and result.bytes.len > 0:
    result.bytes = wrapWithSyncOutput(result.bytes)
    result.onPartial = {srOsc8, srSgr, srSyncEnd}
  else:
    result.onPartial = {srOsc8, srSgr}

proc planClear*(s: ScreenState, size: Size): FramePlan =
  ## Plan a full-screen clear of a `size`-sized screen, recorded as blank at
  ## that size once it goes out. Not wrapped, and a partial write of it leaves
  ## nothing open that the next write has to undo.
  result.kind = pkClear
  result.bytes = ResetAndClearScreenSeq
  result.epoch = s.epoch
  result.clearedSize = size

proc stage*(s: var ScreenState, plan: var FramePlan, buffer: var Buffer) =
  ## Adopt `buffer` before the write so a concurrent mutation cannot desync
  ## `lastBuffer` from the bytes. Swaps on matching area (zero-copy steady
  ## state); otherwise `finish` copies. A failed write rolls back.
  if plan.kind == pkFrame and s.lastBuffer.area == buffer.area:
    swap(s.lastBuffer, buffer)
    s.lastBuffer.clearDirty()
    plan.staged = true

proc applyOutcome(s: var ScreenState, plan: FramePlan, outcome: StreamWrite) =
  ## The `known` and `epoch` half of `finish`, shared by every variant.
  if outcome == swPartial:
    # Some bytes went out: the screen shows a mix of two frames.
    s.known = false
    inc s.epoch
  elif outcome == swAll and s.epoch == plan.epoch:
    # The frame is on screen, unless something invalidated the screen while the
    # write was in flight: a concurrent `invalidate`, `suspend` or `resume`
    # does not take the stdout lock, and its unknown is the newer truth.
    s.known = true

proc finish*(
    s: var ScreenState, plan: FramePlan, buffer: Buffer, outcome: StreamWrite
) =
  ## Record a written frame whose content the caller keeps (`draw`,
  ## `drawWithCursor`, the low-level `render`): `lastBuffer` becomes `buffer`
  ## when the frame went out in full.
  if plan.kind == pkFrame and outcome == swAll:
    s.lastBuffer = buffer
    s.lastBuffer.clearDirty()
  s.applyOutcome(plan, outcome)

proc finishAdopt*(
    s: var ScreenState, plan: FramePlan, buffer: var Buffer, outcome: StreamWrite
) =
  ## Record a written frame the caller gave up (`drawAdopt`,
  ## `drawWithCursorAdopt`): a staged swap is kept when the frame went out in
  ## full and rolled back otherwise, so `lastBuffer` holds only frames the
  ## screen showed and the caller keeps the grid it rendered.
  if plan.kind == pkFrame:
    if plan.staged:
      if outcome != swAll:
        swap(s.lastBuffer, buffer)
        s.lastBuffer.clearDirty()
    elif outcome == swAll:
      # `stage` could not swap (first frame, after a resize): copy instead.
      s.lastBuffer = buffer
      s.lastBuffer.clearDirty()
  s.applyOutcome(plan, outcome)

proc finishClear*(s: var ScreenState, plan: FramePlan, outcome: StreamWrite) =
  ## Record a written clear: the screen shows a blank grid of the cleared size.
  if outcome == swAll:
    s.lastBuffer = newBuffer(plan.clearedSize.width, plan.clearedSize.height)
  s.applyOutcome(plan, outcome)

proc appliedStyle*(plan: FramePlan, outcome: StreamWrite): CursorStyle =
  ## The cursor style the terminal now shows: the one the plan sent when the
  ## frame went out in full, else the previous one, so the next frame sends its
  ## DECSCUSR again.
  if outcome == swAll: plan.newStyle else: plan.lastStyle
