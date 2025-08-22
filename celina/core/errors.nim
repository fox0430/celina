## Error handling types and utilities
##
## This module provides a unified error handling system with:
## - Hierarchical exception types
## - Error codes for categorization
## - Utility functions for error management
## - Error context and chaining support

import std/[options, tables, strformat, os, posix]

type
  ErrorCode* = enum
    ## Error code categories for classification
    ErrNone
    # I/O related errors
    ErrIO
    ErrIORead
    ErrIOWrite
    ErrIOTimeout # Terminal operation errors
    ErrTerminal
    ErrTerminalConfig
    ErrTerminalRender
    ErrTerminalSize # System call errors
    ErrSystem
    ErrSystemCall
    ErrPermission
    ErrResourceUnavailable # Memory related errors
    ErrMemory
    ErrOutOfMemory
    ErrBufferOverflow # Input validation errors
    ErrInvalidInput
    ErrInvalidUnicode
    ErrInvalidColor
    ErrOutOfBounds # Async operation errors
    ErrAsync
    ErrAsyncTimeout
    ErrAsyncCancelled

  CelinaError* = ref object of CatchableError ## Base error type for all Celina errors
    code*: ErrorCode
    context*: string
    innerError*: ref CatchableError

  # Specific error types inheriting from CelinaError
  TerminalError* = ref object of CelinaError ## Errors related to terminal operations

  CelinaIOError* = ref object of CelinaError ## Errors related to I/O operations

  SystemCallError* = ref object of CelinaError
    ## Errors from system calls with errno information
    errno*: cint

  MemoryError* = ref object of CelinaError ## Memory allocation and buffer errors
    requestedSize*: int

  ValidationError* = ref object of CelinaError ## Input validation errors
    invalidValue*: string

  AsyncError* = ref object of CelinaError ## Errors in async operations

  ErrorStats* = object ## Error statistics tracking (optional, for debugging)
    totalErrors*: int
    errorsByCode*: Table[ErrorCode, int]
    lastError*: Option[CelinaError]

var globalErrorStats* = ErrorStats()

# Error constructors
proc newTerminalError*(
    msg: string, code = ErrTerminal, context = "", inner: ref CatchableError = nil
): TerminalError =
  ## Create a new terminal error
  result = TerminalError(msg: msg, code: code, context: context)
  result.innerError = inner

proc newIOError*(
    msg: string, code = ErrIO, context = "", inner: ref CatchableError = nil
): CelinaIOError =
  ## Create a new I/O error
  result = CelinaIOError(msg: msg, code: code, context: context)
  result.innerError = inner

proc newSystemCallError*(
    msg: string, errno: cint, code = ErrSystemCall, context = ""
): SystemCallError =
  ## Create a new system call error with errno
  let errnoStr = $errno
  let osError = osErrorMsg(OSErrorCode(errno))
  result = SystemCallError(
    msg: msg & " (errno: " & errnoStr & " - " & osError & ")",
    code: code,
    context: context,
    errno: errno,
  )

proc newMemoryError*(
    msg: string, size: int, code = ErrMemory, context = ""
): MemoryError =
  ## Create a new memory error
  result = MemoryError(
    msg: msg & " (requested: " & $size & " bytes)",
    code: code,
    context: context,
    requestedSize: size,
  )

proc newValidationError*(
    msg: string, invalidValue: string, code = ErrInvalidInput, context = ""
): ValidationError =
  ## Create a new validation error
  result = ValidationError(
    msg: msg & " (invalid value: '" & invalidValue & "')",
    code: code,
    context: context,
    invalidValue: invalidValue,
  )

proc newAsyncError*(
    msg: string, code = ErrAsync, context = "", inner: ref CatchableError = nil
): AsyncError =
  ## Create a new async error
  result = AsyncError(msg: msg, code: code, context: context)
  result.innerError = inner

# Error chaining utilities
proc withContext*(err: CelinaError, context: string): CelinaError =
  ## Add context to an existing error
  err.context =
    if err.context.len > 0:
      err.context & " -> " & context
    else:
      context
  err

proc chain*(outer: CelinaError, inner: ref CatchableError): CelinaError =
  ## Chain errors together
  outer.innerError = inner
  outer

# Error formatting
proc formatError*(err: CelinaError): string =
  ## Format error for display
  result = &"[{err.code}] {err.msg}"
  if err.context.len > 0:
    result.add(&"\n  Context: {err.context}")
  if not err.innerError.isNil:
    result.add(&"\n  Caused by: {err.innerError.msg}")

proc `$`*(err: CelinaError): string =
  ## String representation of error
  formatError(err)

# Common error checking patterns
template checkSystemCall*(call: untyped, errorMsg: string): untyped =
  ## Check system call return value and raise on error
  ## Usage: checkSystemCall(ioctl(...), "Failed to get terminal size")
  let res = call
  if res == -1:
    raise newSystemCallError(errorMsg, errno)
  res

template checkSystemCallVoid*(call: untyped, errorMsg: string): untyped =
  ## Check system call return value for void functions
  if call == -1:
    raise newSystemCallError(errorMsg, errno)

template tryIO*(body: untyped): untyped =
  ## Wrap I/O operations with error handling
  try:
    body
  except CelinaIOError as e:
    raise newIOError("I/O operation failed", inner = e)
  except OSError as e:
    raise newIOError("OS I/O error: " & e.msg, inner = e)
  except CatchableError as e:
    raise newIOError("Unexpected I/O error: " & e.msg, inner = e)

template ensure*(
    condition: bool, errorMsg: string, errorCode = ErrInvalidInput
): untyped =
  ## Ensure condition is true or raise error
  if not condition:
    raise newValidationError(errorMsg, "condition failed", errorCode)

template ensureNotNil*[T](value: T, errorMsg: string): T =
  ## Ensure value is not nil and return it
  if value.isNil:
    raise newValidationError(errorMsg, "nil value")
  value

# Resource management helpers
template withResource*(resource: untyped, cleanup: untyped, body: untyped): untyped =
  ## Execute body with resource, ensuring cleanup on error
  ## Usage:
  ##   withResource(file, file.close()):
  ##     file.write("data")
  try:
    body
  finally:
    cleanup

template withNonBlocking*(body: untyped): untyped =
  ## Execute body with stdin in non-blocking mode, restore on exit
  let flags = checkSystemCall(fcntl(STDIN_FILENO, F_GETFL), "Failed to get stdin flags")
  checkSystemCallVoid(
    fcntl(STDIN_FILENO, F_SETFL, flags or O_NONBLOCK), "Failed to set non-blocking mode"
  )
  try:
    body
  finally:
    # Best effort restore
    discard fcntl(STDIN_FILENO, F_SETFL, flags)

template withErrorContext*(context: string, body: untyped): untyped =
  ## Add context to any errors raised in body
  try:
    body
  except CelinaError as e:
    e.context =
      if e.context.len > 0:
        context & " -> " & e.context
      else:
        context
    raise e
  except CatchableError as e:
    raise newTerminalError(e.msg, context = context, inner = e)

# Error recovery helpers
proc tryRecover*[T](operation: proc(): T, fallback: T, logError = true): T =
  ## Try an operation and return fallback on error
  try:
    return operation()
  except CatchableError as e:
    when defined(celinaDebug):
      if logError:
        stderr.writeLine("Error recovered: ", e.msg)
    else:
      discard e
    return fallback

proc retryOperation*[T](operation: proc(): T, maxAttempts = 3, delayMs = 100): T =
  ## Retry an operation with exponential backoff
  var lastError: ref CatchableError
  for attempt in 1 .. maxAttempts:
    try:
      return operation()
    except CatchableError as e:
      lastError = e
      if attempt < maxAttempts:
        sleep(delayMs * attempt)

  # All attempts failed
  raise newTerminalError(
    &"Operation failed after {maxAttempts} attempts", inner = lastError
  )

proc recordError*(stats: var ErrorStats, error: CelinaError) =
  ## Record error in statistics
  stats.totalErrors.inc
  stats.errorsByCode.mgetOrPut(error.code, 0).inc
  stats.lastError = some(error)

proc clearErrorStats*(stats: var ErrorStats) =
  ## Clear error statistics
  stats.totalErrors = 0
  stats.errorsByCode.clear()
  stats.lastError = none(CelinaError)

proc getErrorReport*(stats: ErrorStats): string =
  ## Generate error report from statistics
  result = &"Total errors: {stats.totalErrors}\n"
  for code, count in stats.errorsByCode:
    result.add(&"  {code}: {count}\n")
  if stats.lastError.isSome:
    result.add(&"Last error: {stats.lastError.get.formatError()}\n")

# Debug helpers
when defined(celinaDebug):
  template debugAssert*(cond: bool, msg = "") =
    ## Debug-only assertion
    if not cond:
      let info = instantiationInfo()
      raise newException(
        AssertionDefect,
        &"Debug assertion failed at {info.filename}:{info.line} - {msg}",
      )

  template logError*(e: CelinaError) =
    ## Log error to stderr in debug mode
    stderr.writeLine("[ERROR] ", formatError(e))

else:
  template debugAssert*(cond: bool, msg = "") =
    discard

  template logError*(e: CelinaError) =
    discard
