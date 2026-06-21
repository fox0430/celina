## Async I/O implementation
##
## This module provides non-blocking I/O for terminal input/output
## that works with both Chronos and std/asyncdispatch.

import std/[options, posix, selectors, deques]

import async_backend
from ../core/terminal_common import
  WriteOutcome, classifyWriteResult, WriteWaitOutcome, pollWritable, WriteBlockedWaitMs,
  WriteMaxBlockedWaits, writeAllBlocking

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
  if reader.usePolling:
    # Polling mode: use direct POSIX poll() for raw terminal mode
    try:
      var pollfd: Tpollfd
      pollfd.fd = reader.stdinFd.cint
      pollfd.events = POLLIN.cshort
      pollfd.revents = 0

      let r = posix.poll(addr pollfd, 1, timeoutMs.cint)
      return r > 0 and (pollfd.revents.int and POLLIN.int) != 0
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
  ## Read available data non-blocking
  try:
    var buffer: array[256, char]
    let bytesRead = posix.read(reader.stdinFd.cint, addr buffer[0], buffer.len.cint)

    if bytesRead > 0:
      result = newString(bytesRead)
      copyMem(addr result[0], addr buffer[0], bytesRead)
    else:
      result = ""
  except CatchableError:
    result = ""

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
  ## Read available stdin data asynchronously
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

  if reader.hasDataAvailable(timeoutMs):
    return prefix & reader.readNonBlocking()
  else:
    return prefix

# Async Output Functions

# Serialization for concurrent stdout writes.
#
# `writeStdoutAsync` yields the event loop (`await sleepMs`) between `write(2)`
# attempts so it can drain a flow-controlled tty without blocking. That yield is
# also a window in which a *second* task could start its own write and interleave
# bytes, splicing two escape sequences together and corrupting terminal state.
# To prevent that, every `writeStdoutAsync` call holds this single cooperative
# lock for its whole duration, so one sequence is fully flushed before the next
# one begins. (The synchronous `writeStdoutBlocking` family and `flushStdoutAsync`
# do not take this lock — they are for the cleanup/signal path and must not run
# concurrently with a live async writer.)
#
# It is a plain bool + FIFO waiter queue, not chronos' `AsyncLock`: std/asyncdispatch
# ships no async lock, and chronos' lock has a stricter ownership contract (a
# separate `acquired` flag, plus a hand-off whose returned future only completes a
# loop turn later) that does not match the direct synchronous hand-off used here. A
# hand-rolled FIFO is the one implementation that serves both backends with the
# same semantics. The loop is single-threaded and cooperative, so the bool
# test-and-set in `tryAcquireStdoutLockImmediate` crosses no `await` and cannot race
# another task; release hands the lock straight to the next waiter (the bool stays
# set) to avoid both a spin-wait and a barge-ahead by a task acquiring in the gap.
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

proc writeStdoutAsync*(data: string): Future[int] {.async.} =
  ## Write data to stdout asynchronously.
  ##
  ## Loops until every byte is written so a short `write(2)` can't leave a
  ## multi-byte escape sequence half-emitted (which corrupts terminal state).
  ## On EAGAIN it asks `pollWritable` whether stdout has drained or gone away
  ## (POLLHUP/POLLERR) and yields cooperatively via `await sleepMs` between
  ## attempts, so it neither busy-spins nor blocks the event loop. It gives up
  ## only after `WriteMaxBlockedWaits` consecutive attempts make no progress
  ## (≈2s on a wedged tty) or on a hard error, so ordinary flow control never
  ## truncates output. Returns the number of bytes written: `data.len` on
  ## success, or a short count if it gives up before the data is fully flushed.
  ##
  ## This is the async twin of `writeWithRetry` in core/terminal.nim; the two
  ## share the same EINTR/EAGAIN/short-write contract and retry policy (the
  ## constants in terminal_common) but differ in how they wait — this one yields
  ## via `await sleepMs`, the sync version blocks in `pollWritable` — so keep
  ## their policy in sync when changing either.
  ##
  ## The return value is a raw byte count (the async twin of `write(2)`); a short
  ## count means output was truncated. Callers that must not emit a half-written
  ## control sequence go through `writeOrRaiseAsync` (raises `IOError` on a short
  ## count) instead of discarding it; `tryWriteAsync` is the best-effort variant
  ## for non-critical control. These mirror the sync `writeOrRaise`/`tryWrite`
  ## split in core/terminal.nim, and `async_terminal` routes all its control and
  ## frame output through them so a truncated escape sequence can never be
  ## silently swallowed on the live render path.
  ##
  ## Concurrency: the whole write is serialized through `acquireStdoutLock` /
  ## `releaseStdoutLock`, so two tasks writing at once can never interleave their
  ## bytes and splice one escape sequence into another. Each caller's data is
  ## flushed in full (or to its short-count give-up point) before the next
  ## queued writer starts, and writes proceed in call order (FIFO). Only
  ## `writeStdoutAsync` writers are serialized; the synchronous
  ## `writeStdoutBlocking` family and `flushStdoutAsync` bypass the lock.
  ##
  ## A chronos `CancelledError` propagates out of this proc (so a `cancelAndWait`
  ## shutdown can interrupt a write that is parked on a flow-controlled tty); the
  ## lock is still released on the way out. Every *other* error is swallowed and
  ## reported as a short count, as before.
  ##
  ## Head-of-line cost: the lock is held for the whole write, including the
  ## `WriteMaxBlockedWaits` back-off budget (~2s) on a wedged tty, so one stuck
  ## writer stalls every other queued writer for up to that budget. This is
  ## deliberate — releasing mid-write would let another task's bytes splice into a
  ## half-emitted escape sequence, the exact corruption this serialization
  ## prevents — and the per-write give-up budget bounds the worst-case stall.

  # An empty write does nothing, so skip the lock entirely rather than acquire
  # (and possibly park behind an in-flight writer) just to emit zero bytes.
  if data.len == 0:
    return 0

  var
    total = 0
    blockedWaits = 0
    held = false
  let fd = STDOUT_FILENO.cint

  # Hold the lock for the entire write, including every `await` inside the loop,
  # so no other task can emit between our `write(2)` attempts. Acquire inside the
  # `try` and set `held` only once it has actually granted, so the `finally`
  # releases iff this call owns the lock: a writer cancelled while still parked in
  # the wait queue (CancelledError raised at `await waitForStdoutLock()`) never
  # releases a lock it never held — its queued waiter is skipped by the next
  # `releaseStdoutLock`. `unsafeAddr data[total]` is only evaluated once
  # `total < data.len`, so it is never taken on an empty string.
  try:
    # Fast path: take a free lock with no Future allocation; only park (allocating
    # a waiter) when another writer already holds it.
    if not tryAcquireStdoutLockImmediate():
      await waitForStdoutLock()
    held = true

    while total < data.len:
      let n = posix.write(fd, unsafeAddr data[total], data.len - total).int

      case classifyWriteResult(n)
      of woProgress:
        total += n
        blockedWaits = 0
      of woInterrupted:
        # Interrupted before writing anything. Yield before retrying so a signal
        # storm (e.g. SIGWINCH during a resize drag) can't starve the event
        # loop, and count it so a relentless storm can't loop forever.
        inc blockedWaits
        if blockedWaits >= WriteMaxBlockedWaits:
          when defined(celinaDebug):
            stderr.writeLine(
              "Warning: writeStdoutAsync gave up after " & $WriteMaxBlockedWaits &
                " interrupted writes (" & $total & "/" & $data.len & " bytes)"
            )
          break
        await sleepMs(0)
      of woWouldBlock:
        # Non-blocking stdout not ready (its open file description shares stdin's
        # O_NONBLOCK when fd 0/1 point at the same tty). Wait for it to drain
        # instead of dropping data mid-escape-sequence: probe whether the fd has
        # become writable or gone away, then yield. Give up only after
        # WriteMaxBlockedWaits consecutive no-progress waits (steady drainage
        # resets the counter via woProgress), so a flow-controlled terminal
        # never truncates output yet a permanently wedged fd can't hang forever.
        inc blockedWaits
        if blockedWaits >= WriteMaxBlockedWaits:
          when defined(celinaDebug):
            stderr.writeLine(
              "Warning: writeStdoutAsync gave up after " & $WriteMaxBlockedWaits &
                " blocked writes (" & $total & "/" & $data.len & " bytes)"
            )
          break
        case pollWritable(fd, 0) # non-blocking probe; never blocks the event loop
        of wwError:
          # stdout went away (POLLHUP/POLLERR); stop and report bytes sent.
          when defined(celinaDebug):
            stderr.writeLine(
              "Warning: writeStdoutAsync stdout error (" & $total & "/" & $data.len &
                " bytes)"
            )
          break
        of wwWritable:
          # Writable again: yield once and retry promptly.
          await sleepMs(0)
        of wwNotReady:
          # Still full: back off cooperatively before re-probing the fd.
          await sleepMs(WriteBlockedWaitMs)
      of woHardError:
        # Hard error, or a 0-byte write we can't make progress on. Stop and
        # report how much actually made it out.
        when defined(celinaDebug):
          stderr.writeLine(
            "Warning: writeStdoutAsync hard error (" & $total & "/" & $data.len &
              " bytes)"
          )
        break
  except CancelledError as e:
    # Let chronos cancellation propagate (the `finally` still releases the lock)
    # so `cancelAndWait`-based shutdown can tear the write down, instead of the
    # catch-all below silently swallowing it and finishing the future as a normal
    # short count. asyncdispatch never raises this type, so this is a no-op there.
    raise e
  except CatchableError:
    # Preserve the old contract of never raising on ordinary I/O errors: report
    # however many bytes already made it out.
    discard
  finally:
    if held:
      releaseStdoutLock()

  result = total

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
  ## Blocking write of `data` to stdout via the shared `writeAllBlocking` loop in
  ## terminal_common (the same loop the sync `writeWithRetry` uses). Instead of
  ## yielding, it blocks in `pollWritable` while stdout is non-writable. Uses
  ## `STDOUT_FILENO` directly so it never goes through the stdio buffer or mixes
  ## ordering with `stdout.write`/`stdout.flushFile`. Returns bytes written (a
  ## short count means it gave up on a wedged tty); never raises.
  ##
  ## Intended for mode toggles in `AsyncTerminal` that must stay callable from
  ## both async procs and the synchronous `cleanup` fallback used by crash
  ## handlers/signal hooks.
  writeAllBlocking(STDOUT_FILENO.cint, data)

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
    reader.pendingByte.isSome or reader.buffer.len > 0 or reader.hasDataAvailable(0)
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
