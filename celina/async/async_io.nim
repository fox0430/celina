## Async I/O implementation
##
## This module provides non-blocking I/O for terminal input/output
## that works with both Chronos and std/asyncdispatch.

import std/[options, posix, selectors]

import async_backend

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

var globalInputReader {.threadvar.}: AsyncInputReader

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

proc closeAsyncInputReader*(reader: AsyncInputReader) =
  ## Close the async input reader
  if reader.selector != nil:
    if reader.selectorRegistered:
      try:
        reader.selector.unregister(reader.stdinFd)
      except Exception:
        discard

    try:
      reader.selector.close()
    except Exception:
      discard

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

proc initAsyncIO*() {.raises: [].} =
  ## Initialize async I/O system
  try:
    if globalInputReader.isNil:
      globalInputReader = newAsyncInputReader()
  except Exception:
    discard

proc cleanupAsyncIO*() =
  ## Cleanup async I/O system
  if not globalInputReader.isNil:
    globalInputReader.closeAsyncInputReader()
    globalInputReader = nil

proc hasInputAsync*(timeoutMs: int = 1): Future[bool] {.async.} =
  ## Check if input is available asynchronously
  if globalInputReader.isNil:
    initAsyncIO()

  # Double-check that initialization succeeded
  if globalInputReader.isNil:
    return false

  # timeoutMs already provided as parameter

  # Yield to other async tasks first
  await sleepMs(0)

  # Check for buffered data - ensure globalInputReader is not nil
  if not globalInputReader.isNil and globalInputReader.buffer.len > 0:
    return true

  # Check for new data - ensure globalInputReader is not nil
  if not globalInputReader.isNil:
    return globalInputReader.hasDataAvailable(timeoutMs)
  else:
    return false

proc readCharAsync*(): Future[char] {.async.} =
  ## Read a character asynchronously
  if globalInputReader.isNil:
    initAsyncIO()

  # Double-check that initialization succeeded
  if globalInputReader.isNil:
    return '\0'

  # Yield to other async tasks
  await sleepMs(0)

  # Try to read from buffer or stdin - ensure globalInputReader is not nil
  if not globalInputReader.isNil:
    result = globalInputReader.readCharNonBlocking()
  else:
    result = '\0'

proc peekCharAsync*(): Future[char] {.async.} =
  ## Peek at next character without consuming it
  if globalInputReader.isNil:
    initAsyncIO()

  # Double-check that initialization succeeded
  if globalInputReader.isNil:
    return '\0'

  await sleepMs(0)

  # Ensure globalInputReader is not nil before accessing
  if not globalInputReader.isNil:
    if globalInputReader.buffer.len > 0:
      return globalInputReader.buffer[0]

    if globalInputReader.hasDataAvailable(0):
      let newData = globalInputReader.readNonBlocking()
      if newData.len > 0:
        globalInputReader.buffer.add(newData)
        if globalInputReader.buffer.len > 0:
          return globalInputReader.buffer[0]

  return '\0'

proc readStdinAsync*(timeoutMs: int = 10): Future[string] {.async.} =
  ## Read available stdin data asynchronously
  if globalInputReader.isNil:
    initAsyncIO()

  # Double-check that initialization succeeded
  if globalInputReader.isNil:
    return ""

  # timeoutMs already provided as parameter
  await sleepMs(0)

  # Ensure globalInputReader is not nil before accessing
  if not globalInputReader.isNil and globalInputReader.hasDataAvailable(timeoutMs):
    return globalInputReader.readNonBlocking()
  else:
    return ""

# Async Output Functions

proc writeStdoutAsync*(data: string): Future[int] {.async.} =
  ## Write data to stdout asynchronously
  await sleepMs(0) # Yield to other tasks

  try:
    result = posix.write(STDOUT_FILENO.cint, cstring(data), data.len.cint).int
  except CatchableError:
    result = 0

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

proc clearInputBuffer*() =
  ## Clear the input buffer
  if not globalInputReader.isNil:
    globalInputReader.buffer = ""
    globalInputReader.pendingByte = none(byte)

proc setPendingByteAsync*(b: byte) =
  ## Stash a byte to be re-injected as the first byte of the next event
  ## (Unicode §3.9 resync). Called from `readKeyAsync` after a UTF-8
  ## assembly produces a leftover byte. A no-op if the global reader
  ## hasn't been initialised.
  if not globalInputReader.isNil:
    globalInputReader.pendingByte = some(b)

proc clearPendingByteAsync*() =
  ## Drop any byte waiting to be re-injected. Call from raw-mode toggles
  ## to prevent stale bytes from leaking across mode transitions.
  if not globalInputReader.isNil:
    globalInputReader.pendingByte = none(byte)

proc getInputBufferStats*(): tuple[size: int, available: bool] =
  ## Get input buffer statistics
  if globalInputReader.isNil:
    return (0, false)
  return (globalInputReader.buffer.len, globalInputReader.hasDataAvailable(0))

# Testing and Validation

proc testAsyncIO*(): Future[bool] {.async.} =
  ## Test async I/O functionality
  try:
    initAsyncIO()

    # Test output
    discard await writeStdoutAsync("Testing async I/O...\n")
    await flushStdoutAsync()

    # Test input availability check
    discard await hasInputAsync(10)

    return true
  except CatchableError:
    return false

# Backwards Compatibility Functions

# Export the same interface as async_io.nim for drop-in replacement
export hasInputAsync, readCharAsync, peekCharAsync, readStdinAsync
export writeStdoutAsync, flushStdoutAsync, clearScreenAsync, moveCursorAsync
export hideCursorAsync, showCursorAsync, clearInputBuffer, testAsyncIO
