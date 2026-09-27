# Test suite for output_stream module

import std/unittest

import ../celina/core/[terminal_common, output_stream]
import ./stdout_capture

const resetAll = AbortPartialSeq & Osc8Reset & "\e[0m" & SyncOutputDisable
  ## Every reset, in the order the stream sends them.

suite "Output stream":
  teardown:
    # A failed check must not leave a reset pending for the next test.
    clearPendingReset()

  test "a write that stops partway is followed by the abort":
    when defined(linux):
      var n = -1
      let output = captureCutStdout(
        4,
        proc() =
          n = writeStream("\e[12;34H", {})
          discard writeStream("x", {}),
      )
      check n == 4
      # The abort goes out before the next write, so "x" is not swallowed
      # by the half-sent CSI.
      check output == "\e[12" & AbortPartialSeq & "x"
      check not resetPending()
    else:
      skip()

  test "a write that sent nothing is neither a partial nor a reset":
    var n = -1
    withFailingStdout(
      proc() =
        n = writeStream("abc", {srOsc8, srSgr})
    )
    check n == 0
    # Nothing was emitted, so what the screen shows did not change either.
    check outcomeOf(n, 3) == swNone
    check not resetPending()

  test "a full write sends no reset":
    var outcome = swNone
    let output = captureStdout(
      proc() =
        outcome = outcomeOf(writeStream("abc", {srOsc8, srSgr}), 3)
    )
    check output == "abc"
    check outcome == swAll
    check not resetPending()

  test "a write that stops partway marks the resets its bytes could leave open":
    when defined(linux):
      # A frame: an OSC 8 link, SGR attributes and (when celina wrapped it) a
      # synchronized output block are all open by the time the write stops.
      var
        n = -1
        outcome = swNone
        pendingAfterCut = false
      discard captureCutStdout(
        4,
        proc() =
          n = writeStream("\e[12;34H", {srOsc8, srSgr, srSyncEnd})
          outcome = outcomeOf(n, 8)
          pendingAfterCut = resetPending(),
        failedWrites = 2,
      )
      check n == 4
      check outcome == swPartial
      check pendingAfterCut

      let output = captureStdout(
        proc() =
          discard writeStream("x", {})
      )
      check output == resetAll & "x"
      check not resetPending()
    else:
      skip()

  test "a write with an empty reset set marks the abort alone":
    when defined(linux):
      discard captureCutStdout(
        4,
        proc() =
          discard writeStream("\e[12;34H", {}),
        failedWrites = 2,
      )
      let output = captureStdout(
        proc() =
          discard writeStream("x", {})
      )
      check output == AbortPartialSeq & "x"
    else:
      skip()

  test "a reset that does not go out after a cut write goes first in the next write":
    when defined(linux):
      var
        n = -1
        m = -1
        pendingAfterCut = false
      let output = captureCutStdout(
        4,
        proc() =
          n = writeStream("\e[12;34H", {srOsc8, srSgr})
          pendingAfterCut = resetPending()
          m = writeStream("x", {}),
        failedWrites = 2,
      )
      check n == 4
      check pendingAfterCut
      check m == 1
      check output == "\e[12" & AbortPartialSeq & Osc8Reset & "\e[0m" & "x"
      check not resetPending()
    else:
      skip()

  test "markPartialWrite clears the reset once it goes out":
    let output = captureStdout(
      proc() =
        markPartialWrite({})
    )
    check output == AbortPartialSeq
    check not resetPending()

  test "markPartialWrite keeps the reset pending when it cannot go out":
    withFailingStdout(
      proc() =
        markPartialWrite({})
    )
    check resetPending()

    let output = captureStdout(
      proc() =
        discard writeStream("x", {})
    )
    check output == AbortPartialSeq & "x"
    check not resetPending()

  test "markPartialWrite widens a reset that is already pending":
    when defined(linux):
      # `resume` marks a reset without taking the stdout lock, so one can be
      # pending when a write stops partway: the OSC 8 link and the block celina
      # wrapped that `resume` found open are still open, and the cut write's own
      # SGR reset must not drop them.
      var pendingAfterCut = false
      discard captureCutStdout(
        4,
        proc() =
          setPendingReset({srOsc8, srSyncEnd})
          markPartialWrite({srSgr})
          pendingAfterCut = resetPending(),
        failedWrites = 1,
      )
      check pendingAfterCut

      let output = captureStdout(
        proc() =
          discard writeStream("x", {})
      )
      check output == resetAll & "x"
      check not resetPending()
    else:
      skip()

  test "nothing is written while the pending reset cannot go out":
    var
      n = -1
      sent = true
    withFailingStdout(
      proc() =
        markPartialWrite({})
        n = writeStream("x", {})
        sent = sendPendingReset()
    )
    check n == 0
    check not sent
    check resetPending()

    var m = -1
    let output = captureStdout(
      proc() =
        m = writeStream("y", {})
    )
    check m == 1
    check output == AbortPartialSeq & "y"

  test "an empty write keeps a pending reset and writes nothing":
    withFailingStdout(
      proc() =
        markPartialWrite({})
    )
    var n = -1
    let output = captureStdout(
      proc() =
        n = writeStream("", {srOsc8})
    )
    check n == 0
    check output == ""
    check resetPending()

  test "setPendingReset makes the next write send the reset first":
    setPendingReset({srAbort, srOsc8, srSyncEnd})
    let output = captureStdout(
      proc() =
        discard writeStream("x", {})
    )
    check output == AbortPartialSeq & Osc8Reset & SyncOutputDisable & "x"
    check not resetPending()

  test "sendPendingReset writes nothing when no reset is pending":
    var sent = false
    let output = captureStdout(
      proc() =
        sent = sendPendingReset()
    )
    check sent
    check output == ""
