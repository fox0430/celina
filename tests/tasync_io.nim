# Test suite for async_io module
#
import std/[unittest, posix, deques]

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

suite "Stdout Write Serialization":
  # writeStdoutAsync yields the event loop mid-write, so concurrent writers must
  # be serialized through tryAcquireStdoutLockImmediate/waitForStdoutLock/
  # releaseStdoutLock or their bytes interleave and corrupt escape sequences.
  # These exercise the lock directly via the {.all.} import.

  teardown:
    # Defensive isolation: these tests assert against module-global lock state, so
    # a failed assertion mid-test must not leak stdoutWriteLocked/waiters into the
    # next test and cascade spurious failures. Each test still opens with
    # `check not stdoutWriteLocked` to prove it actually started clean.
    while stdoutWriteWaiters.len > 0:
      discard stdoutWriteWaiters.popFirst()
    stdoutWriteLocked = false

  test "tryAcquireStdoutLockImmediate grants immediately when the lock is free":
    check not stdoutWriteLocked
    check tryAcquireStdoutLockImmediate() # free -> granted, no Future allocated
    check stdoutWriteLocked
    releaseStdoutLock()
    check not stdoutWriteLocked

  test "contended acquires park and are handed off in FIFO order":
    check not stdoutWriteLocked
    check tryAcquireStdoutLockImmediate() # free -> immediate, holds the lock
    let f2 = waitForStdoutLock() # held -> parked
    let f3 = waitForStdoutLock() # held -> parked behind f2
    check not f2.finished
    check not f3.finished
    check stdoutWriteWaiters.len == 2

    releaseStdoutLock() # hands the lock to f2, stays held
    check f2.finished
    check not f3.finished
    check stdoutWriteLocked

    releaseStdoutLock() # hands the lock to f3
    check f3.finished
    check stdoutWriteLocked

    releaseStdoutLock() # no waiter left -> lock clears
    check not stdoutWriteLocked
    check stdoutWriteWaiters.len == 0

  test "release skips an already-finished (cancelled) waiter":
    check not stdoutWriteLocked
    check tryAcquireStdoutLockImmediate() # immediate, holds the lock
    let dead = waitForStdoutLock() # parked
    let live = waitForStdoutLock() # parked behind it
    # A waiter that finished out from under the queue (here via complete(); a real
    # chronos cancellation is covered by the dedicated test below). Release must
    # skip it via the `not waiter.finished` guard and hand off to the next live one.
    dead.complete()
    check stdoutWriteWaiters.len == 2

    releaseStdoutLock() # skips `dead`, hands to `live`
    check live.finished
    check stdoutWriteLocked

    releaseStdoutLock()
    check not stdoutWriteLocked
    check stdoutWriteWaiters.len == 0

  test "writes contending for a held lock queue and each flush in full (FIFO)":
    # Hold the lock first so the writes below cannot grab it synchronously and
    # must actually park. Otherwise each small write completes in one shot before
    # the next is even launched, so nothing ever contends and the test would pass
    # even if the lock were a no-op.
    check not stdoutWriteLocked
    check tryAcquireStdoutLockImmediate()
    check stdoutWriteLocked
    let payloads = @["aa", "bbb", "cccc"]
    var futs: seq[Future[int]]
    for p in payloads:
      futs.add writeStdoutAsync(p)
    # All three are now genuinely queued behind the held lock.
    check stdoutWriteWaiters.len == payloads.len
    for f in futs:
      check not f.finished
    # Release; the queued writers drain in FIFO order, each flushing in full.
    releaseStdoutLock()
    for i in 0 ..< futs.len:
      check (waitFor futs[i]) == payloads[i].len
    check not stdoutWriteLocked
    check stdoutWriteWaiters.len == 0

  when hasChronos:
    test "a writeStdoutAsync cancelled while parked is skipped, never wedging the lock":
      # Real chronos cancellation (asyncdispatch has none): a parked writer whose
      # CancelledError fires at `await waitForStdoutLock()` must NOT release a lock
      # it never held, and the next release must skip its cancelled waiter and
      # clear the lock rather than deadlock on it.
      check not stdoutWriteLocked
      check tryAcquireStdoutLockImmediate() # the test holds the lock
      let parked = writeStdoutAsync("zz") # parks behind us
      check stdoutWriteWaiters.len == 1
      check not parked.finished

      waitFor parked.cancelAndWait()
      check parked.cancelled()
      check stdoutWriteLocked # we still hold it; the cancelled writer didn't touch it
      check stdoutWriteWaiters.len == 1 # cancelled waiter lingers until release

      releaseStdoutLock() # must skip the cancelled waiter and clear the lock
      check not stdoutWriteLocked
      check stdoutWriteWaiters.len == 0

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
