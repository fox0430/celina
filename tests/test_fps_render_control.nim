## Test to verify shouldRender() works correctly with lastRenderTime
import std/[unittest, os, times]
import ../celina/core/fps

suite "FPS Render Control Tests":
  test "shouldRender respects lastRenderTime across multiple checks":
    # Test that shouldRender() uses lastRenderTime for timing control
    let monitor = newFpsMonitor(60) # 60 FPS = ~16.67ms per frame

    # First render should be allowed immediately (just initialized)
    check monitor.shouldRender() == true

    # Simulate rendering
    monitor.startFrame()
    monitor.endFrame()

    # Immediately after render, should NOT render again
    check monitor.shouldRender() == false

    # Wait a bit but not enough
    sleep(5)
    check monitor.shouldRender() == false

    # Wait enough time total
    sleep(12) # Total ~17ms
    check monitor.shouldRender() == true

  test "Multiple shouldRender checks without startFrame":
    let monitor = newFpsMonitor(10) # 10 FPS = 100ms per frame

    # First check should be true (just initialized)
    check monitor.shouldRender() == true

    # Start frame to update lastRenderTime
    monitor.startFrame()
    monitor.endFrame()

    # Multiple checks in rapid succession should all be false
    check monitor.shouldRender() == false
    sleep(20)
    check monitor.shouldRender() == false
    sleep(20)
    check monitor.shouldRender() == false

    # After enough time, should be true
    sleep(70) # Total ~110ms
    check monitor.shouldRender() == true

  test "startFrame updates lastRenderTime":
    let monitor = newFpsMonitor(30) # 30 FPS = ~33.33ms per frame

    # Initial render
    check monitor.shouldRender() == true
    monitor.startFrame()
    let renderTime1 = epochTime()
    monitor.endFrame()

    # Should not render immediately
    check monitor.shouldRender() == false

    # Wait and render again
    sleep(40)
    check monitor.shouldRender() == true
    monitor.startFrame()
    let renderTime2 = epochTime()
    monitor.endFrame()

    # Check that renders were spaced appropriately
    let spacing = (renderTime2 - renderTime1) * 1000.0
    check spacing >= 33.0 # Should be at least target frame time

  test "getRemainingFrameTime decreases over time":
    let monitor = newFpsMonitor(10) # 10 FPS = 100ms

    # Render to set lastRenderTime
    monitor.startFrame()
    monitor.endFrame()

    let remaining1 = monitor.getRemainingFrameTime()
    check remaining1 > 0
    check remaining1 <= 100

    sleep(30)
    let remaining2 = monitor.getRemainingFrameTime()
    check remaining2 < remaining1 # Should decrease

    sleep(80)
    let remaining3 = monitor.getRemainingFrameTime()
    check remaining3 == 0 # Should be zero after frame time elapsed

  test "Simulation of actual tick loop":
    # Simulate how app.nim uses the FPS monitor
    let monitor = newFpsMonitor(60)
    var renderCount = 0
    var skipCount = 0

    # Simulate 10 ticks over ~100ms
    for i in 0 ..< 10:
      # Simulate event processing (2ms)
      sleep(2)

      # Check if should render
      if monitor.shouldRender():
        monitor.startFrame()
        # Simulate rendering (1ms)
        sleep(1)
        monitor.endFrame()
        renderCount.inc()
      else:
        skipCount.inc()

      # Small sleep to simulate tick overhead
      sleep(7) # Total ~10ms per tick

    # At 60 FPS target (~16.67ms/frame), with 10ms ticks
    # We should get approximately 5-6 renders
    echo "Renders: ", renderCount, ", Skips: ", skipCount
    check renderCount >= 4
    check renderCount <= 7
    check skipCount > 0 # Should have some skips

  test "High frequency ticks don't cause excessive rendering":
    let monitor = newFpsMonitor(30) # 30 FPS = 33.33ms
    var renderCount = 0

    # Rapid ticks (100 ticks with 1ms each = 100ms total)
    for i in 0 ..< 100:
      if monitor.shouldRender():
        monitor.startFrame()
        monitor.endFrame()
        renderCount.inc()
      sleep(1)

    # Should only render ~3 times (100ms / 33.33ms ≈ 3)
    echo "High frequency test renders: ", renderCount
    check renderCount >= 2
    check renderCount <= 4
