## Async I/O implementation
##
## This module provides non-blocking I/O for terminal input/output
## that works with both Chronos and std/asyncdispatch.

import std/[options, posix, selectors, deques]

import async_backend
# The write loops live in core/output_stream.nim (which owns the shared
# EINTR/EAGAIN/short-write policy in terminal_common and the pending reset);
# this module only serializes them through the stdout lock.
from ../core/output_stream import writeStream, writeStreamLocked
from ../core/terminal_common import ReadOutcome, classifyReadResult

type
  AsyncIOError* = object of CatchableError

  ## Non-blocking input reader using selectors
  AsyncInputReader* = ref object
    selector: Selector[int]
    stdinFd: int
    buffer: string
    pendingByte: Option[byte]
      ## One-byte pushback slot for a UTF-8 resync byte (Unicode §3.9). Set
      ## by `readKeyAsync` after an `assembleUtf8Char` failure; consumed by
      ## `readCharNonBlocking` before checking `buffer` or stdin.
    usePolling: bool # Use polling instead of selector for raw mode
    selectorRegistered: bool # Track if selector registration succeeded
    closed: bool
      ## Set once a read finds stdin gone (`roClosed`); the fd is not polled or
      ## read after that.
    closeReported: bool ## Whether the one `InputClosed` event has gone out.

proc newAsyncInputReader*(): AsyncInputReader =
  ## Create a new async input reader
  result = AsyncInputReader()
  result.selector = newSelector[int]()
  result.stdinFd = STDIN_FILENO
  result.buffer = ""
  result.pendingByte = none(byte)
  result.usePolling = false
  result.selectorRegistered = false

  # Try to register stdin for reading - fall back to polling if it fails
  try:
    result.selector.registerHandle(result.stdinFd, {Read}, 0)
    result.selectorRegistered = true
  except Exception:
    result.usePolling = true
    result.selectorRegistered = false

proc isLive*(reader: AsyncInputReader): bool =
  ## Whether `reader` can still observe input. False for a nil reader or one
  ## that has been through `closeAsyncInputReader` (which nils `selector`).
  ## A polling-mode reader stays usable via direct `poll()`, so it is live as
  ## long as the object exists.
  not reader.isNil and (reader.usePolling or reader.selector != nil)

proc closeAsyncInputReader*(reader: AsyncInputReader) =
  ## Close the async input reader. Safe to call on a nil reader and safe
  ## to call repeatedly: after the first call `reader.selector` is set to
  ## nil so a second call cannot double-close the underlying fd.
  if reader.isNil:
    return
  if reader.selector != nil:
    if reader.selectorRegistered:
      try:
        reader.selector.unregister(reader.stdinFd)
      except Exception:
        discard
      reader.selectorRegistered = false

    try:
      reader.selector.close()
    except Exception:
      discard
    reader.selector = nil

# Non-blocking I/O Operations

proc hasDataAvailable*(reader: AsyncInputReader, timeoutMs: int = 0): bool =
  ## Check if data is available for reading (non-blocking)
  if reader.closed:
    # Nothing will arrive; wait out the timeout as an idle fd would.
    discard posix.poll(nil, 0, timeoutMs.cint)
    return false
  if reader.usePolling:
    # Polling mode: use direct POSIX poll() for raw terminal mode
    try:
      var pollfd: Tpollfd
      pollfd.fd = reader.stdinFd.cint
      pollfd.events = POLLIN.cshort
      pollfd.revents = 0

      let r = posix.poll(addr pollfd, 1, timeoutMs.cint)
      # Hang-up and error bits count too, so the read that follows sees the end
      # instead of the poll returning at once without data.
      let readable = POLLIN.int or POLLHUP.int or POLLERR.int or POLLNVAL.int
      return r > 0 and (pollfd.revents.int and readable) != 0
    except Exception:
      return false
  else:
    # Selector mode: original implementation
    if reader.selector == nil:
      return false
    try:
      let events = reader.selector.select(timeoutMs)
      return events.len > 0
    except OSError:
      return false

proc readNonBlocking*(reader: AsyncInputReader): string =
  ## Read available data non-blocking. Marks the reader closed when the read
  ## finds stdin gone.
  if reader.closed:
    return ""
  try:
    var buffer: array[256, char]
    let bytesRead = posix.read(reader.stdinFd.cint, addr buffer[0], buffer.len.cint)

    case classifyReadResult(bytesRead, reader.stdinFd.cint)
    of roData:
      result = newString(bytesRead)
      copyMem(addr result[0], addr buffer[0], bytesRead)
    of roNoData:
      result = ""
    of roClosed:
      reader.closed = true
      result = ""
  except CatchableError:
    result = ""

proc isClosed*(reader: AsyncInputReader): bool =
  ## Whether stdin has ended for `reader` (see `EventKind.InputClosed`). Once
  ## true it stays true.
  not reader.isNil and reader.closed

proc takeCloseNotice*(reader: AsyncInputReader): bool =
  ## True exactly once after stdin closes; the caller then emits the one
  ## `InputClosed` event.
  if reader.isNil or not reader.closed or reader.closeReported:
    return false
  reader.closeReported = true
  true

proc readCharNonBlocking*(reader: AsyncInputReader): char =
  ## Read a single character non-blocking
  # Highest priority: a byte pushed back from a previous UTF-8 assembly
  # failure (Unicode §3.9 resync). Consume it before the regular buffer or
  # any stdin read so it becomes the first byte of the next event.
  if reader.pendingByte.isSome:
    let b = reader.pendingByte.get
    reader.pendingByte = none(byte)
    return char(b)

  if reader.buffer.len > 0:
    result = reader.buffer[0]
    reader.buffer = reader.buffer[1 ..^ 1]
    return

  if reader.hasDataAvailable(0):
    let newData = reader.readNonBlocking()
    if newData.len > 0:
      reader.buffer.add(newData)
      if reader.buffer.len > 0:
        result = reader.buffer[0]
        reader.buffer = reader.buffer[1 ..^ 1]
        return

  result = '\0'

# Async Wrapper Functions

proc hasInputAsync*(
    reader: AsyncInputReader, timeoutMs: int = 1
): Future[bool] {.async.} =
  ## Check if input is available asynchronously
  if reader.isNil:
    return false

  # Yield to other async tasks first
  await sleepMs(0)

  if reader.pendingByte.isSome:
    # A stashed UTF-8 resync byte (Unicode §3.9) is a real keystroke that the
    # next readCharNonBlocking will emit; it lives only in pendingByte and never
    # reaches the fd, so hasDataAvailable can't see it. Report it as available so
    # it isn't stranded until fresh fd input arrives.
    return true

  if reader.buffer.len > 0:
    return true

  if reader.closed:
    if not reader.closeReported:
      # The close itself is pending; `readKeyAsync` turns it into an event.
      return true
    # Wait out the timeout rather than return at once, or a poll loop such as
    # `tickAsync` would spin.
    await sleepMs(timeoutMs)
    return false

  return reader.hasDataAvailable(timeoutMs)

proc readCharAsync*(reader: AsyncInputReader): Future[char] {.async.} =
  ## Read a character asynchronously
  if reader.isNil:
    return '\0'

  # Yield to other async tasks
  await sleepMs(0)

  result = reader.readCharNonBlocking()

proc readStdinAsync*(
    reader: AsyncInputReader, timeoutMs: int = 10
): Future[string] {.async.} =
  ## Read available stdin data asynchronously. Once stdin ends, `isClosed`
  ## turns true and `readKeyAsync` no longer reports `InputClosed`.
  if reader.isNil:
    return ""

  await sleepMs(0)

  # Drain the stashed resync byte and any buffered data first, in the same
  # priority order as readCharNonBlocking. hasInputAsync/bufferStats report both
  # as available even though they never reach the fd, so a
  # hasInputAsync()/readStdinAsync() loop would otherwise spin forever on input
  # this proc could not consume.
  var prefix = ""
  if reader.pendingByte.isSome:
    prefix.add(char(reader.pendingByte.get))
    reader.pendingByte = none(byte)
  if reader.buffer.len > 0:
    prefix.add(reader.buffer)
    reader.buffer = ""

  let data =
    if reader.hasDataAvailable(timeoutMs):
      prefix & reader.readNonBlocking()
    else:
      prefix
  # The end shows through `isClosed`; take the notice so hasInputAsync stops
  # reporting it, or that loop would spin on the close.
  discard reader.takeCloseNotice()
  return data

# Async Output Functions

# Serialization for concurrent stdout writes. `writeStdoutAsync` yields
# between `write(2)` attempts, opening a window for interleaved writes that
# would splice escape sequences. Holders keep this cooperative lock for the
# whole unit of output (a single write, or a frame via `withStdoutLock`),
# so one sequence flushes fully before the next begins. `writeStdoutBlocking`
# and `flushStdoutAsync` bypass it for the cleanup/signal path.
#
# Plain bool + FIFO queue (no AsyncLock): serves both backends with the same
# semantics. Single-threaded cooperative loop, so the bool test-and-set crosses
# no `await` and cannot race; release hands off directly to avoid barging.
var
  stdoutWriteLocked = false
  stdoutWriteWaiters = initDeque[Future[void]]()

# These touch the module-global lock state, which chronos' async macro flags as
# non-GC-safe; the single-threaded loop makes it safe in fact, and the `{.gcsafe.}`
# blocks assert that so the helpers stay callable from the gcsafe `writeStdoutAsync`.
# Splitting the fast path (a plain bool test-and-set, no allocation) from the parked
# path (which allocates a waiter Future) keeps the common uncontended write
# allocation-free; neither helper has an `await` of its own, so the test-and-set
# stays a single uninterrupted step.

proc tryAcquireStdoutLockImmediate(): bool =
  ## Take the lock without suspending when it is free. Returns true if this call
  ## now holds it (no Future allocated); false if another writer holds it, in which
  ## case the caller must `await waitForStdoutLock()`. The bool test-and-set crosses
  ## no `await`, so it cannot race another task on a single-threaded event loop.
  {.gcsafe.}:
    if stdoutWriteLocked:
      return false
    stdoutWriteLocked = true
    return true

proc waitForStdoutLock(): Future[void] =
  ## Park behind the current holder; the returned future completes once an earlier
  ## writer hands the lock over in FIFO order. Only called when the lock is held, so
  ## it allocates exactly one waiter — the contended path, not the common one.
  result = newFuture[void]("waitForStdoutLock")
  {.gcsafe.}:
    stdoutWriteWaiters.addLast(result)

proc releaseStdoutLock() =
  ## Release the stdout lock. If a writer is waiting, hand the lock straight to the
  ## next one in FIFO order (keeping `stdoutWriteLocked` set) so no other task can
  ## barge in during the gap and so no one spin-waits. Skips any waiter whose future
  ## is already finished (e.g. a write cancelled while parked, whose waiter lingers
  ## in the queue until it is drained here) to avoid double-completing it. Only when
  ## the queue holds no live waiter is the lock actually cleared.
  {.gcsafe.}:
    while stdoutWriteWaiters.len > 0:
      let waiter = stdoutWriteWaiters.popFirst()
      if not waiter.finished:
        waiter.complete()
        return
    stdoutWriteLocked = false

template withStdoutLock*(body: untyped) =
  ## Hold the stdout lock across `body`, which must cover the whole unit of
  ## output (plan + write + record for a frame; `writeStreamLocked` for a
  ## single write). Not reentrant: `body` must not call a lock-taking write.
  ##
  ## Cancel-safe: the lock releases only once actually granted, so a cancel
  ## while parked never releases an unheld lock.
  block:
    var stdoutLockHeld = false
    try:
      # Fast path: take a free lock with no Future allocation; only park
      # (allocating a waiter) when another writer already holds it.
      if not tryAcquireStdoutLockImmediate():
        await waitForStdoutLock()
      stdoutLockHeld = true
      body
    finally:
      if stdoutLockHeld:
        releaseStdoutLock()

proc writeStdoutAsync*(data: string): Future[int] {.async.} =
  ## Async stdout write, serialized through the stdout lock. Loop is
  ## `writeStreamLocked`; this proc only adds the lock. Yields between
  ## `write(2)` attempts, gives up after `WriteMaxBlockedWaits` no-progress
  ## waits (~2s) or a hard error.
  ##
  ## Returns bytes written (`data.len` on success). Use `writeOrRaiseAsync`
  ## for critical sequences, `tryWriteAsync` for best-effort ones. Frame paths
  ## use `withStdoutLock` + `writeStreamLocked` directly to see the outcome.
  ##
  ## `CancelledError` propagates (lock still released, cut reset still marked);
  ## other errors become a short count. The lock is held for the whole write,
  ## so one wedged writer stalls the queue up to the give-up budget — required
  ## to avoid splicing half-emitted escape sequences.
  #
  # An empty write does nothing, so skip the lock entirely rather than acquire
  # (and possibly park behind an in-flight writer) just to emit zero bytes.
  if data.len == 0:
    return 0

  var written = 0
  withStdoutLock:
    written = await writeStreamLocked(data, {})
  written

proc flushStdoutAsync*(): Future[void] {.async.} =
  ## Flush the C stdio buffer (`stdout.flushFile`) asynchronously.
  ##
  ## Note: the async terminal control/render path writes via `posix.write`
  ## (`writeStdoutAsync`) directly, bypassing the stdio buffer, so it does not
  ## need this. Retained for callers that emit via buffered `stdout.write` and
  ## want it flushed — but do not interleave buffered `stdout.write` with the
  ## `posix.write` control path, or the two byte streams can reach the tty out
  ## of order.
  await sleepMs(0)
  stdout.flushFile()

# Terminal Control (Async)

# Shared short-count checks for the async/blocking write wrappers below. Splitting
# the best-effort (log) and critical (raise) cases keeps the best-effort wrappers
# free of an `IOError` effect in non-debug builds, so they stay callable from
# `{.raises: [].}` contexts (signal handlers).
proc warnShortWrite(n, expected: int, what: string) =
  ## Best-effort: log a truncated write under `-d:celinaDebug`, never raise on it.
  if n != expected:
    when defined(celinaDebug):
      stderr.writeLine(
        "Warning: " & what & " truncated (" & $n & "/" & $expected & " bytes)"
      )

proc raiseIfShortWrite(n, expected: int) =
  ## Critical: raise `IOError` if the write was truncated. A half-written control
  ## sequence corrupts terminal state, so a short count is surfaced rather than
  ## silently swallowed.
  if n != expected:
    raise newException(
      IOError, "Terminal write truncated (" & $n & "/" & $expected & " bytes)"
    )

proc tryWriteAsync*(data: string): Future[void] {.async.} =
  ## Best-effort async write for non-critical control sequences (cursor
  ## show/hide/move, titles, partial-line clears). A truncated write is logged
  ## under `-d:celinaDebug` and otherwise ignored, so a transient tty hiccup
  ## degrades gracefully instead of crashing the caller. The async twin of the
  ## sync `tryWrite` in core/terminal.nim. Pass the full sequence — the constants
  ## in terminal_common already include the leading ESC.
  let n = await writeStdoutAsync(data)
  warnShortWrite(n, data.len, "async terminal write")

proc writeOrRaiseAsync*(data: string): Future[void] {.async.} =
  ## Async write for critical control sequences (screen clears, frame output),
  ## raising `IOError` if the data cannot be flushed in full. A half-written
  ## control sequence corrupts terminal state, so a short count is surfaced
  ## rather than silently swallowed (the bug this fixes) — the async twin of the
  ## sync `writeOrRaise` in core/terminal.nim. Pass the full sequence — the
  ## constants in terminal_common already include the leading ESC.
  let n = await writeStdoutAsync(data)
  raiseIfShortWrite(n, data.len)

# Synchronous Blocking Output Functions

proc writeStdoutBlocking*(data: string): int =
  ## Blocking write of `data` to stdout via the shared `writeStream` in
  ## core/output_stream.nim (the same path the sync `writeWithRetry` uses,
  ## pending resets included). Instead of yielding, it blocks in
  ## `pollWritable` while stdout is non-writable. Uses `STDOUT_FILENO`
  ## directly so it never goes through the stdio buffer or mixes ordering with
  ## `stdout.write`/`stdout.flushFile`. Returns bytes written (a short count
  ## means it gave up on a wedged tty, or a pending reset kept it from trying at
  ## all); never raises.
  ##
  ## Intended for mode toggles in `AsyncTerminal` that must stay callable from
  ## both async procs and the synchronous `cleanup` fallback used by crash
  ## handlers/signal hooks.
  writeStream(data, {})

proc tryWriteBlocking*(data: string) =
  ## Best-effort synchronous write for mode toggles and other non-critical
  ## control sequences. A truncated write is logged under `-d:celinaDebug` and
  ## otherwise ignored. The blocking twin of `tryWriteAsync`.
  warnShortWrite(writeStdoutBlocking(data), data.len, "blocking terminal write")

proc writeOrRaiseBlocking*(data: string) =
  ## Synchronous write for critical mode toggles, raising `IOError` if the data
  ## cannot be flushed in full. The blocking twin of `writeOrRaiseAsync`.
  raiseIfShortWrite(writeStdoutBlocking(data), data.len)

# Buffer Management

proc clearBuffer*(reader: AsyncInputReader) =
  ## Clear the input buffer
  if not reader.isNil:
    reader.buffer = ""
    reader.pendingByte = none(byte)

proc setPendingByteAsync*(reader: AsyncInputReader, b: byte) =
  ## Stash a byte to be re-injected as the first byte of the next event
  ## (Unicode §3.9 resync). Called from `readKeyAsync` after a UTF-8
  ## assembly produces a leftover byte. A no-op if `reader` is nil.
  if not reader.isNil:
    reader.pendingByte = some(b)

proc clearPendingByteAsync*(reader: AsyncInputReader) =
  ## Drop any byte waiting to be re-injected. Call from raw-mode toggles
  ## to prevent stale bytes from leaking across mode transitions.
  if not reader.isNil:
    reader.pendingByte = none(byte)

proc bufferStats*(reader: AsyncInputReader): tuple[size: int, available: bool] =
  ## Get input buffer statistics
  if reader.isNil:
    return (0, false)

  # `available` mirrors hasInputAsync exactly: a stashed pendingByte and buffered
  # data are both readable input even though they never reached the fd, so gating
  # reads on `available` must see them or the byte/buffer is stranded (the bug
  # this fixes).
  let available =
    reader.pendingByte.isSome or reader.buffer.len > 0 or
    (reader.closed and not reader.closeReported) or reader.hasDataAvailable(0)
  return (reader.buffer.len, available)

# Testing and Validation

proc testAsyncIO*(): Future[bool] {.async.} =
  ## Test async I/O functionality. Creates a temporary reader to exercise
  ## the I/O path; callers that need a persistent reader should manage one
  ## themselves via `newAsyncInputReader`.
  try:
    let reader = newAsyncInputReader()
    defer:
      reader.closeAsyncInputReader()

    # Test output
    discard await writeStdoutAsync("Testing async I/O...\n")
    await flushStdoutAsync()

    # Test input availability check
    discard await reader.hasInputAsync(10)

    return true
  except CatchableError:
    return false
