## Error handling module
##
## This module provides error handling:
## - Standard exception inheritance from CatchableError
## - Simple, focused error types
## - Minimal overhead and complexity

import std/[strformat, os]

type
  TerminalError* = object of CatchableError
    ## Terminal operation failures (ANSI codes, raw mode, etc.)

  BufferError* = object of IndexDefect ## Buffer access or manipulation errors

  LayoutError* = object of ValueError ## Layout constraint resolution errors

  RenderError* = object of CatchableError ## Rendering pipeline errors

  EventError* = object of CatchableError ## Event handling errors

# Standard exception types that we'll use directly:
# - IOError (for file I/O)
# - OSError (for system calls)
# - ValueError (for validation)
# - IndexDefect (for bounds checking)
# - KeyError (for lookups)
# - ResourceExhaustedError (for memory/resources)

# Simple error constructor functions
proc newTerminalError*(msg: string): ref TerminalError =
  ## Create a terminal error
  new(result)
  result.msg = msg

proc newBufferError*(msg: string): ref BufferError =
  ## Create a buffer error
  new(result)
  result.msg = msg

proc newLayoutError*(msg: string): ref LayoutError =
  ## Create a layout error
  new(result)
  result.msg = msg

proc newRenderError*(msg: string): ref RenderError =
  ## Create a render error
  new(result)
  result.msg = msg

proc newEventError*(msg: string): ref EventError =
  ## Create an event error
  new(result)
  result.msg = msg

# Error context utilities (optional, lightweight)
proc withContext*(msg: string, context: string): string =
  ## Add context to an error message
  if context.len > 0:
    context & ": " & msg
  else:
    msg

# System call error checking (using standard OSError)
template checkSystemCall*(call: untyped, errorMsg: string): untyped =
  ## Check system call return value and raise OSError on failure
  let res = call
  if res == -1:
    raiseOSError(OSErrorCode(errno), errorMsg)
  res

template checkSystemCallVoid*(call: untyped, errorMsg: string): untyped =
  ## Check system call return value for void functions
  if call == -1:
    raiseOSError(OSErrorCode(errno), errorMsg)

template tryIO*(body: untyped): untyped =
  ## Simple I/O wrapper that re-raises as IOError if needed
  try:
    body
  except IOError:
    raise # Already the right type
  except OSError as e:
    raise newException(IOError, "I/O operation failed: " & e.msg)
  except CatchableError as e:
    raise newException(IOError, "Unexpected I/O error: " & e.msg)

template ensure*(condition: bool, errorMsg: string): untyped =
  ## Ensure condition is true or raise ValueError
  if not condition:
    raise newException(ValueError, errorMsg)

template ensureNotNil*[T](value: T, errorMsg: string): T =
  ## Ensure value is not nil and return it
  if value.isNil:
    raise newException(ValueError, errorMsg & " (value is nil)")
  value

# Resource management helpers
template withResource*(resource: untyped, cleanup: untyped, body: untyped): untyped =
  ## Execute body with resource, ensuring cleanup on error
  try:
    body
  finally:
    cleanup

template withErrorContext*(context: string, body: untyped): untyped =
  ## Add context to any errors raised in body
  try:
    body
  except TerminalError as e:
    raise newTerminalError(withContext(e.msg, context))
  except BufferError as e:
    raise newBufferError(withContext(e.msg, context))
  except LayoutError as e:
    raise newLayoutError(withContext(e.msg, context))
  except RenderError as e:
    raise newRenderError(withContext(e.msg, context))
  except EventError as e:
    raise newEventError(withContext(e.msg, context))
  except CatchableError as e:
    # For other exceptions, just re-raise with modified message
    raise newException(ValueError, withContext(e.msg, context))

# Simple error recovery helpers
proc tryRecover*[T](operation: proc(): T, fallback: T): T =
  ## Try an operation and return fallback on error
  try:
    return operation()
  except CatchableError:
    return fallback

# Debug helpers
when defined(celinaDebug):
  template debugLog*(msg: string) =
    stderr.writeLine("[DEBUG] ", msg)

else:
  template debugLog*(msg: string) =
    discard
