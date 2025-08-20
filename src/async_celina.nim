## Async Celina CLI Library
## =========================
##
## A powerful async Terminal User Interface library for Nim using Chronos,
## inspired by Ratatui. Provides high-performance, non-blocking components
## for building interactive terminal applications.
##
## Basic Async Usage:
## ```nim
## import pkg/chronos
## import pkg/async_celina
##
## proc main() {.async.} =
##   await quickRunAsync(
##     eventHandler = proc(event: Event): Future[bool] {.async.} =
##       case event.kind
##       of EventKind.Key:
##         if event.key.code == KeyCode.Char and event.key.char == 'q':
##           return false
##       else: discard
##       return true,
##
##     renderHandler = proc(buffer: var Buffer): Future[void] {.async.} =
##       buffer.clear()
##       buffer.setString(10, 5, "Hello Async World!", defaultStyle())
##   )
##
## when isMainModule:
##   waitFor main()
## ```

import std/[options, unicode, times]

import pkg/chronos

import async/[async_app, async_terminal, async_events, async_io]

export async_app, async_terminal, async_events, async_io

export options, unicode

export chronos

export
  AsyncApp, AsyncAppConfig, AsyncTerminal, AsyncEventStream, AsyncAppError,
  AsyncTerminalError, AsyncEventError

type AsyncPerfMonitor* = ref object
  frameCount: int
  eventCount: int
  startTime: float
  lastUpdate: float

# ============================================================================
# Core Async Celina API
# ============================================================================

# Re-export quickRunAsync from async_app for convenience
export quickRunAsync

# ============================================================================
# Utility Functions
# ============================================================================

proc asyncToSync*[T](asyncProc: Future[T]): T =
  ## Convert async procedure to synchronous (blocks until complete)
  return waitFor asyncProc

# ============================================================================
# Performance Monitoring
# ============================================================================

proc newAsyncPerfMonitor*(): AsyncPerfMonitor =
  let now = epochTime()
  result =
    AsyncPerfMonitor(frameCount: 0, eventCount: 0, startTime: now, lastUpdate: now)

proc recordFrame*(monitor: AsyncPerfMonitor) =
  monitor.frameCount.inc()
  monitor.lastUpdate = epochTime()

proc recordEvent*(monitor: AsyncPerfMonitor) =
  monitor.eventCount.inc()

proc getFPS*(monitor: AsyncPerfMonitor): float =
  let elapsed = epochTime() - monitor.startTime
  if elapsed > 0:
    return monitor.frameCount.float / elapsed
  else:
    return 0.0

proc getEventRate*(monitor: AsyncPerfMonitor): float =
  let elapsed = epochTime() - monitor.startTime
  if elapsed > 0:
    return monitor.eventCount.float / elapsed
  else:
    return 0.0
