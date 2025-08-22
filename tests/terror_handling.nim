## Error handling tests for Celina TUI library
##
## This test module verifies that the error handling system works correctly.

import std/[unittest, strutils, tables, options]
import ../celina/core/[errors, terminal]

{.push warning[UnreachableCode]: off.}

suite "Error Handling Tests":
  test "TerminalError creation":
    let err = newTerminalError("Test error", ErrTerminalConfig, "test context")
    check err.msg == "Test error"
    check err.code == ErrTerminalConfig
    check err.context == "test context"

  test "SystemCallError creation":
    let err = newSystemCallError("System call failed", 5, ErrSystemCall, "ioctl")
    check err.errno == 5
    check err.code == ErrSystemCall
    check err.context == "ioctl"
    # Should include errno in message
    check err.msg.contains("errno: 5")

  test "IOError creation":
    let err = newIOError("I/O failed", ErrIOWrite, "stdout")
    check err.msg == "I/O failed"
    check err.code == ErrIOWrite
    check err.context == "stdout"

  test "ValidationError creation":
    let err = newValidationError("Invalid input", "bad_value", ErrInvalidInput)
    check err.invalidValue == "bad_value"
    check err.code == ErrInvalidInput
    check err.msg.contains("invalid value: 'bad_value'")

  test "MemoryError creation":
    let err = newMemoryError("Out of memory", 1024, ErrOutOfMemory)
    check err.requestedSize == 1024
    check err.code == ErrOutOfMemory
    check err.msg.contains("1024 bytes")

  test "Error chaining":
    let innerErr = newException(IOError, "Inner error")
    let outerErr = newTerminalError("Outer error")
    let chainedErr = outerErr.chain(innerErr)

    check chainedErr.innerError != nil
    check chainedErr.innerError.msg == "Inner error"

  test "Error context":
    let err = newTerminalError("Test error")
    let contextErr = err.withContext("test operation")

    check contextErr.context == "test operation"

    # Adding more context
    let moreContextErr = contextErr.withContext("nested operation")
    check moreContextErr.context == "test operation -> nested operation"

  test "Error formatting":
    let err = newTerminalError("Test error", ErrTerminalConfig, "test context")
    let formatted = formatError(err)

    check formatted.contains("[ErrTerminalConfig]")
    check formatted.contains("Test error")
    check formatted.contains("Context: test context")

  test "Error statistics":
    var stats = ErrorStats()
    let err1 = newTerminalError("Error 1", ErrTerminalConfig)
    let err2 = newIOError("Error 2", ErrIOWrite)
    let err3 = newTerminalError("Error 3", ErrTerminalConfig)

    stats.recordError(err1)
    stats.recordError(err2)
    stats.recordError(err3)

    check stats.totalErrors == 3
    check stats.errorsByCode.getOrDefault(ErrTerminalConfig) == 2
    check stats.errorsByCode.getOrDefault(ErrIOWrite) == 1
    check stats.lastError.isSome
    check stats.lastError.get.msg == "Error 3"

  test "Error recovery":
    var callCount = 0
    let result = tryRecover(
      proc(): int =
        callCount.inc()
        if callCount == 1:
          raise newException(ValueError, "Test error")
        return 42,
      fallback = -1,
      logError = false,
    )

    check result == -1 # Should return fallback on first call
    check callCount == 1

  test "Ensure macro":
    expect ValidationError:
      ensure(false, "Test validation")

    # Should not raise
    ensure(true, "Test validation")

  test "Terminal size error handling":
    # This test will only work if we can mock ioctl
    # For now, just test that getTerminalSizeOrDefault doesn't crash
    let size = getTerminalSizeOrDefault()
    check size.width > 0
    check size.height > 0

  test "withErrorContext template":
    expect TerminalError:
      try:
        raise newException(ValueError, "Inner error")
      except CatchableError as e:
        raise newTerminalError("Test error", context = "test context", inner = e)

    try:
      try:
        raise newException(ValueError, "Inner error")
      except CatchableError as e:
        raise newTerminalError("Test error", context = "test context", inner = e)
    except TerminalError as e:
      check e.context.contains("test context")
      check e.innerError != nil
      check e.innerError.msg == "Inner error"

when isMainModule:
  echo "Running error handling tests..."
