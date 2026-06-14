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

suite "AsyncIO Buffer Operations":
  test "clearBuffer is safe":
    let reader = newAsyncInputReader()
    reader.clearBuffer()
    reader.closeAsyncInputReader()

  test "bufferStats returns valid data":
    let reader = newAsyncInputReader()
    let stats = reader.bufferStats()
    check stats.size >= 0
    reader.closeAsyncInputReader()

  test "clearBuffer with nil reader is a no-op":
    var reader: AsyncInputReader = nil
    reader.clearBuffer()

  test "bufferStats with nil reader returns defaults":
    var reader: AsyncInputReader = nil
    let stats = reader.bufferStats()
    check(stats.size == 0)
    check(stats.available == false)

  test "bufferStats reports a stashed pending byte as available":
    let reader = newAsyncInputReader()
    # A stashed resync byte never reaches the fd, so `available` must consult
    # pendingByte to stay consistent with hasInputAsync.
    try:
      reader.setPendingByteAsync('Z'.byte)
      check reader.bufferStats().available
    finally:
      reader.closeAsyncInputReader()

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
  test "hasInputAsync with nil reader returns false":
    var reader: AsyncInputReader = nil
    let hasInput = waitFor reader.hasInputAsync(0)
    check hasInput == false

  test "readCharAsync returns valid char":
    let reader = newAsyncInputReader()
    let ch = waitFor reader.readCharAsync()
    check ch.ord >= 0
    reader.closeAsyncInputReader()

  test "hasInputAsync reports a stashed pending byte":
    let reader = newAsyncInputReader()
    # try/finally so a failed check still closes the reader; otherwise the
    # leaked selector/STDIN registration could cascade into later tests.
    try:
      # A UTF-8 resync byte (Unicode §3.9) lives only in pendingByte, never on
      # the fd, so hasDataAvailable can't see it. hasInputAsync must still
      # report it.
      reader.setPendingByteAsync('Z'.byte)
      check waitFor reader.hasInputAsync(0)
      # And it is exactly what the next read hands back, not stranded.
      check reader.readCharNonBlocking() == 'Z'
    finally:
      reader.closeAsyncInputReader()

  test "readStdinAsync with timeout":
    let reader = newAsyncInputReader()
    let data = waitFor reader.readStdinAsync(1)
    check data.len >= 0
    reader.closeAsyncInputReader()

  test "readStdinAsync drains a stashed pending byte":
    let reader = newAsyncInputReader()
    # hasInputAsync/bufferStats report a stashed byte as available, so
    # readStdinAsync must be able to consume it; otherwise a
    # hasInputAsync()/readStdinAsync() loop spins on the invisible byte.
    try:
      reader.setPendingByteAsync('Z'.byte)
      let data = waitFor reader.readStdinAsync(0)
      check data.len >= 1
      check data[0] == 'Z' # stashed byte is drained first, before any fd data
    finally:
      reader.closeAsyncInputReader()

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
