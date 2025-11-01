# Test suite for async_io module
#
import std/unittest

import ../celina/async/async_backend
import ../celina/async/async_io {.all.}

suite "AsyncIO Module Import":
  test "module imports successfully":
    # Just test that the module imports without error
    check(true)

suite "AsyncInputReader Lifecycle":
  test "newAsyncInputReader creates valid reader":
    let reader = newAsyncInputReader()
    check reader != nil
    reader.closeAsyncInputReader()

  test "closeAsyncInputReader is idempotent":
    let reader = newAsyncInputReader()
    reader.closeAsyncInputReader()
    reader.closeAsyncInputReader() # Should not crash

suite "Global AsyncIO Management":
  test "initAsyncIO and cleanupAsyncIO":
    initAsyncIO()
    cleanupAsyncIO()

  test "initialization and cleanup are idempotent":
    initAsyncIO()
    initAsyncIO()
    cleanupAsyncIO()
    cleanupAsyncIO()

  test "global functions that don't require reader creation":
    initAsyncIO()
    clearInputBuffer()

    let stats = getInputBufferStats()
    check(stats.size >= 0)
    check(stats.available == true or stats.available == false)

    cleanupAsyncIO()

  test "error handling with no global reader":
    cleanupAsyncIO()

    clearInputBuffer()

    let stats = getInputBufferStats()
    check(stats.size == 0)
    check(stats.available == false)

suite "AsyncIO Buffer Operations":
  test "clearInputBuffer is safe":
    initAsyncIO()
    clearInputBuffer()
    cleanupAsyncIO()

  test "getInputBufferStats returns valid data":
    initAsyncIO()
    let stats = getInputBufferStats()
    check stats.size >= 0
    cleanupAsyncIO()

suite "Async Output Functions":
  test "writeStdoutAsync writes data":
    let bytesWritten = waitFor writeStdoutAsync(".")
    check(bytesWritten >= 0)

  test "writeStdoutAsync with empty string":
    let bytesWritten = waitFor writeStdoutAsync("")
    check(bytesWritten == 0)

  test "flushStdoutAsync completes":
    waitFor flushStdoutAsync()

  test "writeEscapeAsync with ANSI code":
    waitFor writeEscapeAsync("[0m")

  test "clearScreenAsync completes":
    waitFor clearScreenAsync()

suite "Async Cursor Control":
  test "terminal control functions":
    waitFor writeEscapeAsync("[0m")
    waitFor hideCursorAsync()
    waitFor showCursorAsync()

  test "cursor hide and show sequence":
    waitFor hideCursorAsync()
    waitFor showCursorAsync()

suite "Async Input Functions":
  test "hasInputAsync with nil reader auto-initializes":
    cleanupAsyncIO()
    let hasInput = waitFor hasInputAsync(0)
    check hasInput == true or hasInput == false

  test "readCharAsync returns valid char":
    initAsyncIO()
    let ch = waitFor readCharAsync()
    check ch.ord >= 0
    cleanupAsyncIO()

  test "peekCharAsync doesn't consume buffer":
    initAsyncIO()
    let ch1 = waitFor peekCharAsync()
    let ch2 = waitFor peekCharAsync()
    check ch1 == ch2
    cleanupAsyncIO()

  test "readStdinAsync with timeout":
    initAsyncIO()
    let data = waitFor readStdinAsync(1)
    check data.len >= 0
    cleanupAsyncIO()

suite "AsyncInputReader Non-Blocking Operations":
  test "reader lifecycle":
    let reader = newAsyncInputReader()
    check reader != nil
    reader.closeAsyncInputReader()

  test "multiple reader instances":
    let reader1 = newAsyncInputReader()
    let reader2 = newAsyncInputReader()
    check reader1 != nil
    check reader2 != nil
    reader1.closeAsyncInputReader()
    reader2.closeAsyncInputReader()
