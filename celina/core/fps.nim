## FPS Monitoring Module
## ====================
##
## Provides frame rate monitoring and performance tracking for terminal applications.
##
## Overview
## --------
##
## The FPS monitor controls rendering frequency to maintain a target frame rate while
## minimizing CPU usage. It uses a `lastRenderTime` tracking mechanism to ensure
## accurate frame spacing regardless of tick frequency.
##
## Key Features
## ------------
##
## * **Accurate FPS Control**: Maintains target FPS by tracking last render time
## * **CPU Efficiency**: Skips unnecessary renders when target FPS not reached
## * **Real-time Statistics**: Calculates actual FPS over rolling 1-second windows
## * **Frame Timing**: Provides frame time measurements and remaining time calculations
##
## Implementation Details
## ----------------------
##
## The monitor uses `lastRenderTime` to track when the last frame was rendered.
## This field is updated when `startFrame()` is called and is used for FPS control.
##
## The `shouldRender()` check compares elapsed time since `lastRenderTime` against
## the target frame interval (1.0 / targetFPS). This ensures consistent frame spacing
## even when the application tick rate is higher than the target FPS.
##
## For example, with 60 FPS target (~16.67ms interval):
##
## * If last render was 10ms ago: `shouldRender()` returns false
## * If last render was 20ms ago: `shouldRender()` returns true
##
## This approach prevents excessive rendering while allowing responsive event processing.

import std/times

type
  FpsMonitor* = ref object ## Frame rate monitoring and control
    targetFps*: int ## Target FPS for rendering
    frameCounter: int ## Frame counter for FPS calculation
    lastFpsTime: float ## Last time FPS was calculated
    currentFps: float ## Current calculated FPS
    lastRenderTime: float ## Last time a frame was rendered

  PerfStats* = object ## Performance statistics
    fps*: float ## Current frames per second
    frameTime*: float ## Average frame time in milliseconds
    frameCount*: int ## Total frames rendered

const DefaultTargetFps = 60

proc newFpsMonitor*(targetFps: int = DefaultTargetFps): FpsMonitor =
  ## Create a new FPS monitor with specified target FPS.
  ##
  ## The monitor is initialized to allow immediate rendering (lastRenderTime = 0.0).
  ##
  ## Parameters:
  ##   * `targetFps`: Target frames per second (1-240). Default is 60.
  ##
  ## Returns:
  ##   A new FpsMonitor instance ready to use.
  ##
  ## Raises:
  ##   ValueError if targetFps is outside the valid range (1-240).
  if targetFps < 1 or targetFps > 240:
    raise newException(ValueError, "FPS must be 1-240")

  let now = epochTime()
  result = FpsMonitor(
    targetFps: targetFps,
    frameCounter: 0,
    lastFpsTime: now,
    currentFps: 0.0,
    lastRenderTime: 0.0, # Initialize to 0 to allow first render immediately
  )

proc setTargetFps*(monitor: FpsMonitor, fps: int) =
  ## Set the target FPS
  if fps < 1 or fps > 240:
    raise newException(ValueError, "FPS must be 1-240")
  monitor.targetFps = fps

proc getTargetFps*(monitor: FpsMonitor): int =
  ## Get the current target FPS
  monitor.targetFps

proc getFrameTimeout*(monitor: FpsMonitor): int =
  ## Get the timeout in milliseconds for achieving target FPS
  1000 div monitor.targetFps

proc startFrame*(monitor: FpsMonitor) =
  ## Mark the start of a new frame and update last render time.
  ##
  ## This should be called immediately before rendering when `shouldRender()` returns true.
  ## It updates `lastRenderTime` for FPS control.
  ##
  ## Important:
  ##   * Only call this when you actually render a frame
  ##   * Do not call this every tick - use `shouldRender()` to check first
  ##   * Calling this updates the FPS control timing
  monitor.lastRenderTime = epochTime()

proc endFrame*(monitor: FpsMonitor) =
  ## Mark the end of current frame and update performance statistics.
  ##
  ## This increments the frame counter and updates the calculated FPS every second
  ## using a rolling window approach.
  ##
  ## Important:
  ##   * Call this after rendering is complete
  ##   * Must be paired with `startFrame()`
  ##   * Only call when actually rendering (after `shouldRender()` check)
  ##
  ## FPS Calculation:
  ##   FPS is calculated over a rolling 1-second window. The counter resets
  ##   after each calculation, so `currentFps` represents the average FPS
  ##   over the last second.
  monitor.frameCounter.inc()

  # Update FPS calculation every second
  let currentTime = epochTime()
  let elapsed = currentTime - monitor.lastFpsTime

  if elapsed >= 1.0:
    monitor.currentFps = monitor.frameCounter.float / elapsed
    monitor.lastFpsTime = currentTime
    monitor.frameCounter = 0

proc getCurrentFps*(monitor: FpsMonitor): float =
  ## Get the current calculated FPS
  monitor.currentFps

proc shouldRender*(monitor: FpsMonitor): bool =
  ## Check if enough time has passed since last render to maintain target FPS.
  ##
  ## This compares the elapsed time since `lastRenderTime` against the target
  ## frame interval (1.0 / targetFps). Returns true if rendering should occur.
  ##
  ## Key Behavior:
  ##   * Uses `lastRenderTime` for timing control
  ##   * Can be called multiple times without side effects
  ##   * Returns false if target FPS interval not reached
  ##   * Returns true immediately after initialization (lastRenderTime = 0.0)
  ##
  ## This allows for efficient CPU usage by skipping renders when called
  ## at high frequency (e.g., event-driven loops).
  ##
  ## Performance:
  ##   At 60 FPS target with 1000 Hz tick rate, this returns true only
  ##   60 times per second, preventing 940 unnecessary render calls.
  let targetFrameTime = 1.0 / monitor.targetFps.float
  let elapsed = epochTime() - monitor.lastRenderTime
  elapsed >= targetFrameTime

proc getRemainingFrameTime*(monitor: FpsMonitor): int =
  ## Get remaining time until next render should occur (milliseconds).
  ##
  ## This calculates how much time remains before `shouldRender()` will
  ## return true, based on the target FPS and time since last render.
  ##
  ## Returns:
  ##   Milliseconds remaining until next render (0 if should render now)
  ##
  ## Use Case:
  ##   Use this for sleep/timeout values in event loops to minimize CPU
  ##   usage while maintaining responsive rendering.
  ##
  ## Note:
  ##   Returns 0 if target frame time already exceeded, indicating
  ##   rendering should occur immediately.
  let targetFrameTime = 1.0 / monitor.targetFps.float
  let elapsed = epochTime() - monitor.lastRenderTime
  let remaining = targetFrameTime - elapsed
  if remaining > 0:
    result = int(remaining * 1000)
  else:
    result = 0

proc getStats*(monitor: FpsMonitor): PerfStats =
  ## Get comprehensive performance statistics
  result.fps = monitor.currentFps
  result.frameTime =
    if monitor.currentFps > 0:
      1000.0 / monitor.currentFps
    else:
      0.0
  result.frameCount = monitor.frameCounter
