## Async I/O implementation
##
## This module provides non-blocking I/O for terminal input/output
## that works with both Chronos and std/asyncdispatch.

import std/[options, posix, selectors]

import async_backend
from ../core/terminal_common import
  WriteOutcome, classifyWriteResult, WriteWaitOutcome, pollWritable, WriteBlockedWaitMs,
  WriteMaxBlockedWaits

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
  ## TODO: Multiple concurrent calls can interleave bytes on stdout and corrupt
  ## terminal state. Serialize all async stdout writes through a single queue or
  ## lock so escape sequences from different tasks never mix.
  ##
  ## TODO: Callers currently ignore the short-count return value when the loop
  ## gives up. Consider surfacing partial-write failures via a result type,
  ## exception, or debug log so the application knows output was truncated.

  var
    total = 0
    blockedWaits = 0
  let fd = STDOUT_FILENO.cint

  # An empty `data` never enters the loop, so `result` stays 0; no special case
  # needed. `unsafeAddr data[total]` is only evaluated once `total < data.len`,
  # so it is never taken on an empty string.
  try:
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
          break
        case pollWritable(fd, 0) # non-blocking probe; never blocks the event loop
        of wwError:
          # stdout went away (POLLHUP/POLLERR); stop and report bytes sent.
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
        break
  except CatchableError:
    # Preserve the old contract of never raising out of this proc: report
    # however many bytes already made it out.
    discard

  result = total

proc flushStdoutAsync*(): Future[void] {.async.} =
  ## Flush stdout asynchronously
  await sleepMs(0)
  stdout.flushFile()

# Terminal Control (Async)

proc writeEscapeAsync*(sequence: string): Future[void] {.async.} =
  ## Write ANSI escape sequence asynchronously
  discard await writeStdoutAsync("\e" & sequence)

proc clearScreenAsync*(): Future[void] {.async.} =
  ## Clear screen asynchronously
  await writeEscapeAsync("[2J[H")

proc moveCursorAsync*(x, y: int): Future[void] {.async.} =
  ## Move cursor to position asynchronously
  await writeEscapeAsync("[" & $(y + 1) & ";" & $(x + 1) & "H")

proc hideCursorAsync*(): Future[void] {.async.} =
  ## Hide cursor asynchronously
  await writeEscapeAsync("[?25l")

proc showCursorAsync*(): Future[void] {.async.} =
  ## Show cursor asynchronously
  await writeEscapeAsync("[?25h")

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
