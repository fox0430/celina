# Test suite for async_io module
#
import std/[unittest, posix]

import ../celina/async/async_backend
import ../celina/async/async_io {.all.}
import ../celina/core/terminal_common

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
    # Reports the full byte count, not a partial single-write result.
    let bytesWritten = waitFor writeStdoutAsync(".")
    check(bytesWritten == 1)

  test "writeStdoutAsync writes a multi-byte payload in full":
    # The loop must complete a short write rather than returning one write()'s
    # partial count, so the whole length comes back.
    let payload = "abcdefghij"
    let bytesWritten = waitFor writeStdoutAsync(payload)
    check(bytesWritten == payload.len)

  test "writeStdoutAsync with empty string":
    let bytesWritten = waitFor writeStdoutAsync("")
    check(bytesWritten == 0)

  test "flushStdoutAsync completes":
    waitFor flushStdoutAsync()

  test "writeOrRaiseAsync completes a full write without raising":
    # writeOrRaiseAsync raises IOError only on a short count; a fully flushed
    # sequence (the normal case on a writable fd) must return cleanly.
    waitFor writeOrRaiseAsync("\e[0m")

  test "writeOrRaiseAsync with empty data is a no-op":
    # An empty write reports 0 of 0 bytes, so the short-count guard must not
    # misfire and raise on it.
    waitFor writeOrRaiseAsync("")

  test "tryWriteAsync completes a full write without raising":
    # tryWriteAsync is best-effort: a full write must not raise, and a truncated
    # one would only be logged under -d:celinaDebug.
    waitFor tryWriteAsync("\e[0m")

  test "tryWriteAsync with empty data is a no-op":
    waitFor tryWriteAsync("")

suite "Blocking Output Functions":
  test "writeStdoutBlocking writes data":
    let bytesWritten = writeStdoutBlocking(".")
    check(bytesWritten == 1)

  test "writeStdoutBlocking writes a multi-byte payload in full":
    let payload = "abcdefghij"
    let bytesWritten = writeStdoutBlocking(payload)
    check(bytesWritten == payload.len)

  test "writeStdoutBlocking with empty string":
    let bytesWritten = writeStdoutBlocking("")
    check(bytesWritten == 0)

  test "writeOrRaiseBlocking completes a full write without raising":
    writeOrRaiseBlocking("\e[0m")

  test "writeOrRaiseBlocking with empty data is a no-op":
    writeOrRaiseBlocking("")

  test "tryWriteBlocking completes a full write without raising":
    tryWriteBlocking("\e[0m")

  test "tryWriteBlocking with empty data is a no-op":
    tryWriteBlocking("")

suite "Shared Blocking Write Loop":
  # writeAllBlocking is the loop that writeStdoutBlocking (and the sync
  # writeWithRetry) delegate to. These cover both the full-write path and the
  # give-up/short-count path that drives the raise in writeOrRaise*.
  test "writeAllBlocking writes a full payload":
    check writeAllBlocking(STDOUT_FILENO.cint, "abc") == 3

  test "writeAllBlocking with empty data is a no-op":
    check writeAllBlocking(STDOUT_FILENO.cint, "") == 0

  test "writeAllBlocking reports a short count on an unwritable fd":
    # A read-only fd makes posix.write fail with EBADF -> woHardError -> give up,
    # so the loop returns a short count. This is the condition writeOrRaiseAsync/
    # writeOrRaiseBlocking turn into an IOError, exercised without wedging real
    # stdout (which would block for the full ~2s retry budget).
    let roFd = posix.open("/dev/null", O_RDONLY)
    check roFd >= 0
    let n = writeAllBlocking(roFd.cint, "abc")
    discard posix.close(roFd)
    check n == 0

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
