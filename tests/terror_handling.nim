## Error handling tests
##
## This test module verifies that the error handling system works correctly.

import std/[unittest, os]
import ../celina/core/[errors, terminal]

{.push warning[UnreachableCode]: off.}

suite "Error Handling Tests":
  test "TerminalError creation":
    let err = newTerminalError("Test error")
    check err.msg == "Test error"
    check err is ref TerminalError

  test "BufferError creation":
    let err = newBufferError("Buffer overflow")
    check err.msg == "Buffer overflow"
    check err is ref BufferError

  test "LayoutError creation":
    let err = newLayoutError("Layout constraint failed")
    check err.msg == "Layout constraint failed"
    check err is ref LayoutError

  test "RenderError creation":
    let err = newRenderError("Render operation failed")
    check err.msg == "Render operation failed"
    check err is ref RenderError

  test "EventError creation":
    let err = newEventError("Event handling failed")
    check err.msg == "Event handling failed"
    check err is ref EventError

  test "OSError handling":
    # Test that we properly handle OS errors (standard Nim approach)
    expect(OSError):
      raiseOSError(OSErrorCode(5), "System call failed")

  test "IOError handling":
    # Test standard IOError handling
    expect(IOError):
      raise newException(IOError, "I/O operation failed")

  test "ValueError handling":
    # Test standard ValueError handling
    expect(ValueError):
      raise newException(ValueError, "Invalid input value")

  test "ResourceExhaustedError handling":
    # Test standard resource exhaustion handling
    expect(ResourceExhaustedError):
      raise newException(ResourceExhaustedError, "Out of memory")

  test "Error context utility":
    # Test simple error context addition
    let baseMsg = "Operation failed"
    let contextMsg = withContext(baseMsg, "terminal setup")
    check contextMsg == "terminal setup: Operation failed"

    # Test empty context
    let noContextMsg = withContext(baseMsg, "")
    check noContextMsg == "Operation failed"

  test "withErrorContext template":
    # Test error context wrapping
    expect(TerminalError):
      withErrorContext("terminal initialization"):
        raise newTerminalError("Hardware failure")

  test "ensure template":
    # Test validation helper
    expect(ValueError):
      ensure(false, "Condition must be true")

    # Should not raise when condition is true
    ensure(true, "This should not raise")

  test "ensureNotNil template":
    # Test nil checking helper with ref types
    let validRef = new(int)
    validRef[] = 42
    let result = ensureNotNil(validRef, "Reference must not be nil")
    check result[] == 42

    # Test nil case
    expect(ValueError):
      let nilRef: ref int = nil
      discard ensureNotNil(nilRef, "Should fail for nil reference")

  test "tryRecover utility":
    # Test error recovery
    var attempts = 0
    let result = tryRecover(
      proc(): int =
        attempts.inc()
        if attempts == 1:
          raise newException(ValueError, "First attempt fails")
        return 42,
      fallback = -1,
    )

    check result == -1 # Should return fallback on error
    check attempts == 1

  test "tryIO template":
    # Test I/O error handling wrapper
    expect(IOError):
      tryIO:
        raise newException(OSError, "System I/O error")

  test "withResource template":
    # Test resource management
    var cleanupCalled = false

    withResource("test resource", (cleanupCalled = true)):
      check cleanupCalled == false # Should not be called yet

    check cleanupCalled == true # Should be called after block

{.pop.}
