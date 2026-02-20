## Tests for tick_common module

import std/unittest

import ../celina/core/tick_common

suite "clampTimeout":
  test "returns timeout when above minimum":
    check clampTimeout(10, 1) == 10
    check clampTimeout(100, 1) == 100

  test "returns minTimeout when timeout is at or below minimum":
    check clampTimeout(0, 1) == 1
    check clampTimeout(1, 1) == 1
    check clampTimeout(-5, 1) == 1

  test "default minTimeout is 0":
    check clampTimeout(5) == 5
    check clampTimeout(0) == 0
    check clampTimeout(-1) == 0

suite "ResizeState":
  test "initResizeState sets initial counter":
    var state = initResizeState(42)
    check state.lastCounter == 42

  test "checkResize returns true when counter changes":
    var state = initResizeState(0)
    check state.checkResize(1) == true
    check state.lastCounter == 1

  test "checkResize returns false when counter unchanged":
    var state = initResizeState(5)
    check state.checkResize(5) == false

  test "checkResize detects multiple resizes":
    var state = initResizeState(0)
    check state.checkResize(1) == true
    check state.checkResize(1) == false
    check state.checkResize(2) == true
    check state.checkResize(2) == false

suite "calculatePollTimeout":
  test "no application timeout returns remainingFrameTime":
    check calculatePollTimeout(16, 0, 0) == 16
    check calculatePollTimeout(100, 0, 500) == 100

  test "application timeout larger than frame time returns frame time":
    # 500ms timeout, 0ms elapsed, 16ms frame time → min(16, 500) = 16
    check calculatePollTimeout(16, 500, 0) == 16

  test "remaining timeout smaller than frame time returns remaining timeout":
    # 500ms timeout, 490ms elapsed → 10ms remaining, frame time 16ms → 10
    check calculatePollTimeout(16, 500, 490) == 10

  test "timeout already reached returns 0":
    # 500ms timeout, 500ms elapsed → 0ms remaining
    check calculatePollTimeout(16, 500, 500) == 0
    # 500ms timeout, 600ms elapsed → still 0 (clamped by max)
    check calculatePollTimeout(16, 500, 600) == 0

  test "both values equal returns that value":
    check calculatePollTimeout(100, 200, 100) == 100

  test "frame time is 0":
    check calculatePollTimeout(0, 500, 0) == 0

  test "negative application timeout treated as disabled":
    # applicationTimeout <= 0 takes the else branch
    check calculatePollTimeout(16, -1, 100) == 16

suite "isTimeoutReached":
  test "returns false when timeout is disabled":
    check isTimeoutReached(0, 1000) == false

  test "returns false when elapsed is less than timeout":
    check isTimeoutReached(500, 200) == false
    check isTimeoutReached(500, 499) == false

  test "returns true when elapsed equals timeout":
    check isTimeoutReached(500, 500) == true

  test "returns true when elapsed exceeds timeout":
    check isTimeoutReached(500, 600) == true
    check isTimeoutReached(100, 5000) == true

  test "returns false when timeout is negative":
    check isTimeoutReached(-1, 100) == false
