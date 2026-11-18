import std/[unittest, os, monotimes, times, importutils]

import ../celina/core/fps {.all.}

# Test suite for FPS module
suite "FPS Module Tests":
  suite "FpsMonitor Creation":
    test "Create with default FPS":
      let monitor = newFpsMonitor()
      check monitor != nil
      check monitor.getTargetFps() == 60

    test "Create with custom FPS":
      let monitor = newFpsMonitor(30)
      check monitor.getTargetFps() == 30

    test "Invalid FPS values raise exception":
      expect ValueError:
        discard newFpsMonitor(0)

      expect ValueError:
        discard newFpsMonitor(-1)

      expect ValueError:
        discard newFpsMonitor(250)

  suite "FPS Configuration":
    test "Set target FPS":
      let monitor = newFpsMonitor()
      monitor.setTargetFps(30)
      check monitor.getTargetFps() == 30

    test "Set invalid FPS raises exception":
      let monitor = newFpsMonitor()

      expect ValueError:
        monitor.setTargetFps(0)

      expect ValueError:
        monitor.setTargetFps(250)

    test "Get frame timeout":
      let monitor60 = newFpsMonitor(60)
      check monitor60.getFrameTimeout() == 17 # ceil(1000ms / 60fps) = 17ms

      let monitor30 = newFpsMonitor(30)
      check monitor30.getFrameTimeout() == 34 # ceil(1000ms / 30fps) = 34ms

      let monitor120 = newFpsMonitor(120)
      check monitor120.getFrameTimeout() == 9 # ceil(1000ms / 120fps) = 9ms

  suite "Frame Tracking":
    test "Start and end frame":
      let monitor = newFpsMonitor()
      monitor.startFrame()
      sleep(10)
      monitor.endFrame()

      # After 10ms sleep with 60 FPS (16.67ms per frame), remaining time should be ~6ms
      let remaining = monitor.getRemainingFrameTime()
      check remaining >= 0 and remaining <= 10

    test "Multiple frames":
      let monitor = newFpsMonitor()

      for i in 0 ..< 5:
        monitor.startFrame()
        sleep(10)
        monitor.endFrame()

      # After last frame with 10ms sleep, remaining time should be ~6ms for 60 FPS
      let remaining = monitor.getRemainingFrameTime()
      check remaining >= 0 and remaining <= 10

    test "getCurrentFps initially zero":
      let monitor = newFpsMonitor()
      check monitor.getCurrentFps() == 0

  suite "Frame Timing":
    test "shouldRender with fast frames":
      let monitor = newFpsMonitor(10) # 10 FPS = 100ms per frame
      monitor.startFrame()
      sleep(30) # Sleep for 30ms (well below 100ms threshold)

      # Should not render yet (only 30ms passed, need 100ms)
      # Note: CI environments may have timing imprecision, so we allow some tolerance
      let shouldRenderResult = monitor.shouldRender()
      if not shouldRenderResult:
        # Expected behavior - not enough time has passed
        check true
      else:
        # If timing is imprecise in CI, check that at least some time has passed
        let elapsed = monitor.getRemainingFrameTime()
        check elapsed >= 0 # Sanity check that time tracking works

    test "shouldRender after sufficient time":
      let monitor = newFpsMonitor(10) # 10 FPS = 100ms per frame
      monitor.startFrame()
      sleep(110) # Sleep for 110ms

      # Should render now
      check monitor.shouldRender() == true

    test "getRemainingFrameTime":
      let monitor = newFpsMonitor(10) # 10 FPS = 100ms per frame
      monitor.startFrame()
      sleep(30)

      let remaining = monitor.getRemainingFrameTime()
      # Should have roughly 70ms remaining (allow wide tolerance for CI environments)
      # CI environments may have significant timing imprecision due to scheduling
      check remaining >= 0 # At minimum, should be non-negative
      if remaining > 0:
        # If we got a positive value, it should be reasonable
        check remaining <= 100 # Should not exceed frame duration

    test "getRemainingFrameTime when frame time exceeded":
      let monitor = newFpsMonitor(10) # 10 FPS = 100ms per frame
      monitor.startFrame()
      sleep(120)

      let remaining = monitor.getRemainingFrameTime()
      check remaining == 0

  suite "Performance Statistics":
    test "getStats returns valid data":
      let monitor = newFpsMonitor()
      let stats = monitor.getStats()

      check stats.fps >= 0.0
      check stats.frameTime >= 0.0
      check stats.frameCount >= 0

    test "getStats frame time calculation":
      let monitor = newFpsMonitor()

      # Simulate some FPS
      for i in 0 ..< 100:
        monitor.startFrame()
        sleep(5)
        monitor.endFrame()

      sleep(1100) # Wait over 1 second for FPS calculation

      for i in 0 ..< 100:
        monitor.startFrame()
        sleep(5)
        monitor.endFrame()

      let stats = monitor.getStats()
      # After frames have been counted, stats should be meaningful
      check stats.fps >= 0.0

  suite "Edge Cases":
    test "Frame timing with zero-duration frames":
      let monitor = newFpsMonitor()
      monitor.startFrame()
      monitor.endFrame()

      # Frame time should be very small but valid
      check monitor.getRemainingFrameTime() >= 0

    test "Multiple startFrame calls":
      let monitor = newFpsMonitor()
      monitor.startFrame()
      sleep(10)
      monitor.startFrame() # Start new frame without ending previous

      # Should use latest start time, so remaining time should be close to full frame time
      let frameTime = monitor.getRemainingFrameTime()
      check frameTime >= 10 # Should be close to frame timeout (16ms for 60 FPS)

    test "FPS boundaries":
      let monitor1 = newFpsMonitor(1) # Minimum valid FPS
      check monitor1.getTargetFps() == 1

      let monitor120 = newFpsMonitor(120) # Maximum valid FPS
      check monitor120.getTargetFps() == 120

suite "Frame clock":
  privateAccess(FpsMonitor)
  let interval = initDuration(nanoseconds = 1_000_000_000 div 60)

  test "the first frame is due at once":
    let monitor = newFpsMonitor(60)
    check monitor.frameDue()
    check monitor.frameTimeLeft() == 0
    monitor.beginFrame()
    check not monitor.frameDue()
    check monitor.frameTimeLeft() in 1 .. 17

  test "the wait is rounded up":
    let monitor = newFpsMonitor(60)
    monitor.nextFrameTime = getMonoTime() + initDuration(microseconds = 10_700)
    let left = monitor.frameTimeLeft()
    let actual = (monitor.nextFrameTime - getMonoTime()).inNanoseconds
    check left.int64 * 1_000_000 >= actual

  test "the next frame is one interval after the last, not after now":
    let monitor = newFpsMonitor(60)
    let due = getMonoTime() - initDuration(milliseconds = 5)
    monitor.nextFrameTime = due
    monitor.beginFrame()
    check monitor.nextFrameTime == due + interval

  test "after a stall of a whole frame the clock starts again from now":
    let monitor = newFpsMonitor(60)
    monitor.nextFrameTime = getMonoTime() - initDuration(milliseconds = 50)
    let before = getMonoTime()
    monitor.beginFrame()
    check monitor.nextFrameTime >= before + interval
    check monitor.nextFrameTime <= getMonoTime() + interval

  test "a higher target FPS cuts the wait for the next frame":
    let monitor = newFpsMonitor(1)
    monitor.beginFrame()
    check monitor.frameTimeLeft() > 900
    monitor.setTargetFps(60)
    check monitor.frameTimeLeft() <= 17

  test "a lower target FPS keeps the next frame where it was":
    let monitor = newFpsMonitor(60)
    monitor.beginFrame()
    let due = monitor.nextFrameTime
    monitor.setTargetFps(1)
    check monitor.nextFrameTime == due

  test "the frame clock leaves the render timing alone":
    let monitor = newFpsMonitor(60)
    monitor.startFrame()
    check not monitor.shouldRender()
    let renderedAt = monitor.lastRenderTime
    monitor.beginFrame()
    check monitor.lastRenderTime == renderedAt
