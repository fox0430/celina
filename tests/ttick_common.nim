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
  test "initResizeState sets initial size":
    var state = initResizeState(80, 24)
    check state.lastWidth == 80
    check state.lastHeight == 24

  test "checkResize returns true when size changes":
    var state = initResizeState(80, 24)
    check state.checkResize(100, 24) == true
    check state.lastWidth == 100
    check state.lastHeight == 24

  test "checkResize returns true when height changes":
    var state = initResizeState(80, 24)
    check state.checkResize(80, 30) == true
    check state.lastHeight == 30

  test "checkResize returns false when size unchanged":
    var state = initResizeState(80, 24)
    check state.checkResize(80, 24) == false

  test "checkResize detects multiple resizes":
    var state = initResizeState(80, 24)
    check state.checkResize(100, 30) == true
    check state.checkResize(100, 30) == false
    check state.checkResize(120, 40) == true
    check state.checkResize(120, 40) == false

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
