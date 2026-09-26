# Test suite for output_stream module

import std/unittest

import ../celina/core/[terminal_common, output_stream]
import ./stdout_capture

suite "Output stream":
  teardown:
    # A failed check must not leave an abort pending for the next test.
    clearPendingAbort()

  test "a write that stops partway is followed by the abort":
    when defined(linux):
      var n = 0
      let output = captureCutStdout(
        4,
        proc() =
          n = writeStream("\e[12;34H")
          discard writeStream("x"),
      )
      check n == 4
      # The abort goes out before the next write, so "x" is not swallowed
      # by the half-sent CSI.
      check output == "\e[12" & AbortPartialSeq & "x"
      check not abortPending()
    else:
      skip()

  test "a full write or a write that sent nothing adds no abort":
    let output = captureStdout(
      proc() =
        discard writeStream("abc")
    )
    check output == "abc"

    var n = -1
    withFailingStdout(
      proc() =
        n = writeStream("abc")
    )
    check n == 0
    check not abortPending()

  test "an abort that does not go out after a cut write goes first in the next write":
    when defined(linux):
      var
        n = 0
        m = 0
        pendingAfterCut = false
      let output = captureCutStdout(
        4,
        proc() =
          n = writeStream("\e[12;34H")
          pendingAfterCut = abortPending()
          m = writeStream("x"),
        failedWrites = 2,
      )
      check n == 4
      check pendingAfterCut
      check m == 1
      check output == "\e[12" & AbortPartialSeq & "x"
      check not abortPending()
    else:
      skip()

  test "abortPartialWrite clears the abort once it goes out":
    let output = captureStdout(
      proc() =
        abortPartialWrite()
    )
    check output == AbortPartialSeq
    check not abortPending()

  test "abortPartialWrite keeps the abort pending when it cannot go out":
    withFailingStdout(
      proc() =
        abortPartialWrite()
    )
    check abortPending()

    let output = captureStdout(
      proc() =
        discard writeStream("x")
    )
    check output == AbortPartialSeq & "x"
    check not abortPending()

  test "nothing is written while the pending abort cannot go out":
    var
      n = -1
      sent = true
    withFailingStdout(
      proc() =
        abortPartialWrite()
        n = writeStream("x")
        sent = sendPendingAbort()
    )
    check n == 0
    check not sent
    check abortPending()

    var m = 0
    let output = captureStdout(
      proc() =
        m = writeStream("y")
    )
    check m == 1
    check output == AbortPartialSeq & "y"

  test "an empty write keeps a pending abort":
    withFailingStdout(
      proc() =
        abortPartialWrite()
    )
    var n = -1
    let output = captureStdout(
      proc() =
        n = writeStream("")
    )
    check n == 0
    check output == ""
    check abortPending()

  test "setPendingAbort makes the next write send the abort first":
    setPendingAbort()
    let output = captureStdout(
      proc() =
        discard writeStream("x")
    )
    check output == AbortPartialSeq & "x"
    check not abortPending()

  test "sendPendingAbort writes nothing when no abort is pending":
    var sent = false
    let output = captureStdout(
      proc() =
        sent = sendPendingAbort()
    )
    check sent
    check output == ""
