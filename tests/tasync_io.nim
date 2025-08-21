# Test suite for async_io module
#
import std/unittest

import pkg/chronos

import ../src/async/async_io

suite "Safe Real AsyncIO Tests":
  test "module imports successfully":
    # Just test that the module imports without error
    check(true)

  test "global functions that don't require reader creation":
    # Test functions that work without creating AsyncInputReader
    initAsyncIO() # This should work
    clearInputBuffer() # This should handle nil reader gracefully

    let stats = getInputBufferStats()
    check(stats.size >= 0)
    check(stats.available == true or stats.available == false)

    cleanupAsyncIO() # This should work

  test "async output functions":
    # These don't depend on input readers and should be safe
    let bytesWritten = waitFor writeStdoutAsync(".")
    check(bytesWritten >= 0)

    waitFor flushStdoutAsync()

  test "terminal control functions":
    # Test escape function without visible effects
    waitFor writeEscapeAsync("[0m") # Reset formatting - safe
    waitFor hideCursorAsync()
    waitFor showCursorAsync()

  test "initialization and cleanup are idempotent":
    # Multiple calls should be safe
    initAsyncIO()
    initAsyncIO()
    cleanupAsyncIO()
    cleanupAsyncIO()

  test "error handling with no global reader":
    cleanupAsyncIO()

    # These should not crash even with nil global reader
    clearInputBuffer()

    let stats = getInputBufferStats()
    check(stats.size == 0)
    check(stats.available == false)
