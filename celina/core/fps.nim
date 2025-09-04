## FPS Monitoring Module
## ====================
##
## Provides frame rate monitoring and performance tracking for terminal applications.
## Supports both synchronous and asynchronous operation modes.

import std/times

type
  FpsMonitor* = ref object ## Frame rate monitoring and control
    targetFps*: int ## Target FPS for rendering
    frameCounter: int ## Frame counter for FPS calculation
    lastFpsTime: float ## Last time FPS was calculated
    currentFps: float ## Current calculated FPS
    frameStartTime: float ## Start time of current frame

  PerfStats* = object ## Performance statistics
    fps*: float ## Current frames per second
    frameTime*: float ## Average frame time in milliseconds
    frameCount*: int ## Total frames rendered
    eventCount*: int ## Total events processed
    eventRate*: float ## Events per second

proc newFpsMonitor*(targetFps: int = 60): FpsMonitor =
  ## Create a new FPS monitor with specified target FPS
  if targetFps < 1 or targetFps > 120:
    raise newException(ValueError, "FPS must be between 1 and 120")

  result = FpsMonitor(
    targetFps: targetFps,
    frameCounter: 0,
    lastFpsTime: epochTime(),
    currentFps: 0.0,
    frameStartTime: epochTime(),
  )

proc setTargetFps*(monitor: FpsMonitor, fps: int) =
  ## Set the target FPS
  if fps < 1 or fps > 120:
    raise newException(ValueError, "FPS must be between 1 and 120")
  monitor.targetFps = fps

proc getTargetFps*(monitor: FpsMonitor): int =
  ## Get the current target FPS
  monitor.targetFps

proc getFrameTimeout*(monitor: FpsMonitor): int =
  ## Get the timeout in milliseconds for achieving target FPS
  1000 div monitor.targetFps

proc startFrame*(monitor: FpsMonitor) =
  ## Mark the start of a new frame
  monitor.frameStartTime = epochTime()

proc endFrame*(monitor: FpsMonitor) =
  ## Mark the end of current frame and update counters
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

proc getFrameTime*(monitor: FpsMonitor): float =
  ## Get the time elapsed since frame start in milliseconds
  (epochTime() - monitor.frameStartTime) * 1000.0

proc shouldRender*(monitor: FpsMonitor): bool =
  ## Check if enough time has passed to render next frame
  let targetFrameTime = 1.0 / monitor.targetFps.float
  let elapsed = epochTime() - monitor.frameStartTime
  elapsed >= targetFrameTime

proc getRemainingFrameTime*(monitor: FpsMonitor): int =
  ## Get remaining time in current frame (milliseconds)
  let targetFrameTime = 1.0 / monitor.targetFps.float
  let elapsed = epochTime() - monitor.frameStartTime
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
  result.eventCount = 0 # This would need to be tracked separately
  result.eventRate = 0.0 # This would need to be tracked separately

# Async-specific performance monitoring
type AsyncPerfMonitor* = ref object
  frameCount*: int
  eventCount*: int
  startTime*: float
  lastUpdate*: float

proc newAsyncPerfMonitor*(): AsyncPerfMonitor =
  ## Create a new async performance monitor
  let now = epochTime()
  result =
    AsyncPerfMonitor(frameCount: 0, eventCount: 0, startTime: now, lastUpdate: now)

proc recordFrame*(monitor: AsyncPerfMonitor) =
  ## Record a frame render in async mode
  monitor.frameCount.inc()
  monitor.lastUpdate = epochTime()

proc recordEvent*(monitor: AsyncPerfMonitor) =
  ## Record an event in async mode
  monitor.eventCount.inc()

proc getFPS*(monitor: AsyncPerfMonitor): float =
  ## Get FPS for async monitor
  let elapsed = epochTime() - monitor.startTime
  if elapsed > 0:
    return monitor.frameCount.float / elapsed
  else:
    return 0.0

proc getEventRate*(monitor: AsyncPerfMonitor): float =
  ## Get event rate for async monitor
  let elapsed = epochTime() - monitor.startTime
  if elapsed > 0:
    return monitor.eventCount.float / elapsed
  else:
    return 0.0
