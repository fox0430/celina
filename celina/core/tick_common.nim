## Tick Common Module
## ==================
##
## Shared logic and constants for application tick processing.
## Used by both sync (App) and async (AsyncApp) implementations
## to eliminate code duplication in event loop handling.
##
## Overview
## --------
##
## The tick loop is the heart of the application, responsible for:
## 1. Detecting and handling terminal resize events
## 2. Polling and processing input events efficiently
## 3. Controlling frame rate for consistent rendering
##
## CPU Efficiency
## --------------
##
## The key to low CPU usage is the dynamic timeout for event polling.
## Instead of polling rapidly, we calculate exactly when the next
## render should occur and use that as the timeout. This means:
##
## * The process sleeps (blocked in select()) until an event arrives
## * OR until it's time to render the next frame
## * At 60 FPS with no input, the loop runs only 60 times/second
## * CPU usage during idle is minimal (<1%)
##
## FPS Control
## -----------
##
## The `shouldRender()` check ensures rendering occurs at the target
## FPS rate. Combined with the dynamic timeout, this provides both
## responsive event handling and efficient CPU usage.

const maxEventsPerTick* = 5
  ## Maximum events processed per tick to ensure smooth rendering.
  ## Processing too many events in one tick can cause visible frame drops.

type
  TickResult* = enum
    ## Result of processing a tick iteration
    trContinue ## Continue running the application
    trQuit ## Application should quit
    trError ## An error occurred

  ResizeState* = object ## State for tracking resize events across ticks
    lastCounter*: int

proc initResizeState*(initialCounter: int): ResizeState =
  ## Initialize resize state with the current counter value
  ResizeState(lastCounter: initialCounter)

proc checkResize*(state: var ResizeState, currentCounter: int): bool =
  ## Check if a resize occurred since last check.
  ## Updates the state and returns true if resize detected.
  ##
  ## This approach supports multiple App instances without race conditions
  ## by using counter-based detection rather than signal flags.
  if currentCounter != state.lastCounter:
    state.lastCounter = currentCounter
    return true
  return false

proc clampTimeout*(timeout: int, minTimeout: int = 0): int {.inline.} =
  ## Clamp timeout to a minimum value.
  ## Useful for async implementations that need minimum 1ms timeout
  ## to avoid busy waiting.
  if timeout > minTimeout: timeout else: minTimeout

proc calculatePollTimeout*(
    remainingFrameTime, applicationTimeout, elapsedSinceLastEvent: int
): int {.inline.} =
  ## Calculate the poll timeout integrating application timeout with FPS timing.
  ##
  ## When applicationTimeout is active (> 0), the poll sleeps for the shorter of:
  ## - Time until next frame render (remainingFrameTime)
  ## - Time until application timeout fires (applicationTimeout - elapsed)
  ##
  ## This ensures the event loop wakes up precisely when either the next
  ## render is due or the timeout has elapsed.
  if applicationTimeout > 0:
    let remainingUntilTimeout = max(applicationTimeout - elapsedSinceLastEvent, 0)
    min(remainingFrameTime, remainingUntilTimeout)
  else:
    remainingFrameTime

proc isTimeoutReached*(
    applicationTimeout, elapsedSinceLastEvent: int
): bool {.inline.} =
  ## Check if the application timeout has been reached.
  ##
  ## Returns true when applicationTimeout is active and enough idle time
  ## has passed since the last event.
  applicationTimeout > 0 and elapsedSinceLastEvent >= applicationTimeout
