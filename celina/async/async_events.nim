## Async event handling
##
## This module provides asynchronous event handling for keyboard input,
## mouse events, and other terminal events using either Chronos or std/asyncdispatch.

import std/[monotimes, options, strutils, times]

import async_backend, async_io
import
  ../core/[
    events, mouse_logic, utf8_utils, key_logic, escape_sequence_logic, terminal,
    geometry,
  ]

const
  ByteWaitSliceMs = 2
  EscapeWaitMs = 20 ## How long a lone ESC waits to be a sequence start.

type
  AsyncEventError* = object of CatchableError

  AsyncEventStream* = ref object
    reader: AsyncInputReader
    running*: bool
    eventCallback*: proc(event: Event): Future[bool] {.async.}
    lastWidth: int ## Track last seen terminal width
    lastHeight: int ## Track last seen terminal height

# Async mouse event parsing (using shared logic from mouse_logic module)

proc toEvent(data: mouse_logic.MouseEventData): Event =
  ## Convert MouseEventData to Event
  Event(
    kind: EventKind.Mouse,
    mouse: MouseEvent(
      kind: data.kind,
      button: data.button,
      x: data.x,
      y: data.y,
      modifiers: data.modifiers,
    ),
  )

proc readNextByteAsync(reader: AsyncInputReader): Future[Option[char]] {.async.} =
  ## Read the next byte of a sequence or character, waiting for one split off by
  ## the link (slow SSH/tmux). Sleeps in slices, so the wait does not hold the
  ## event loop and a signal cannot end it early.
  let deadline = getMonoTime() + initDuration(milliseconds = SequenceByteWaitMs)
  while true:
    result = reader.readCharNonBlocking()
    if result.isSome or reader.isClosed or getMonoTime() >= deadline:
      return
    await sleepMs(ByteWaitSliceMs)

proc readNextByte(
    reader: AsyncInputReader, waitMs: int = SequenceByteWaitMs
): Option[char] =
  ## Blocking `readNextByteAsync`, waiting up to `waitMs`.
  let deadline = getMonoTime() + initDuration(milliseconds = waitMs)
  while true:
    result = reader.readCharNonBlocking()
    if result.isSome or reader.isClosed:
      return
    let left = ceilMs(deadline - getMonoTime())
    if left <= 0:
      return
    discard reader.hasDataAvailable(left)

# The mouse and paste readers are templates over `nextByte`, an `Option[char]`
# expression evaluated once per byte, so the async and the blocking reader share
# them: the async one passes an `await` expression.

template mouseX10From(nextByte: untyped): Event =
  ## X10 mouse format after `ESC [ M`: button byte, then x and y bytes.
  block:
    var data: array[3, char]
    var complete = true
    for i in 0 .. 2:
      let next = nextByte
      if next.isNone:
        complete = false
        break
      data[i] = next.get
    if complete:
      parseMouseDataX10(data).toEvent()
    else:
      Event(kind: Unknown)

proc sgrMouseEvent(params: string, isRelease: bool): Event =
  ## The event of SGR mouse parameters `button;x;y`.
  let parts = params.split(';')
  if parts.len >= 3:
    try:
      let buttonCode = parseInt(parts[0])
      let x = parseInt(parts[1]) - 1 # SGR uses 1-based coordinates
      let y = parseInt(parts[2]) - 1
      return parseMouseDataSGR(buttonCode, x, y, isRelease).toEvent()
    except ValueError:
      return Event(kind: Unknown)
  Event(kind: Unknown)

template mouseSGRFrom(nextByte: untyped): Event =
  ## SGR mouse format after `ESC [ <`: `button;x;y` then M (press) or m
  ## (release).
  block:
    var params: string
    var ch: char
    var readCount = 0
    var complete = true
    while readCount < MaxSGRMouseReadBytes:
      let next = nextByte
      if next.isNone:
        complete = false
        break
      ch = next.get
      readCount.inc()
      if ch == 'M' or ch == 'm':
        break
      params.add(ch)
    # A terminator found on the MaxSGRMouseReadBytes-th byte is still valid; a
    # loop that ran out leaves a non-terminator byte in `ch`.
    if complete and (ch == 'M' or ch == 'm'):
      sgrMouseEvent(params, ch == 'm')
    else:
      Event(kind: Unknown)

template pasteFrom(nextByte: untyped): string =
  ## Bracketed paste content up to the end sequence ESC[201~, without it.
  block:
    var text = ""
    var state = PesNone
    var pending = ""
    while true:
      let next = nextByte
      if next.isNone:
        text.add(pending)
        break
      if stepPasteEnd(state, pending, next.get, text):
        break
    text

proc parseMouseEventX10(reader: AsyncInputReader): Future[Event] {.async.} =
  ## Parse X10 mouse format: ESC[Mbxy
  return mouseX10From(await reader.readNextByteAsync())

proc parseMouseEventSGR(reader: AsyncInputReader): Future[Event] {.async.} =
  ## Parse SGR mouse format: ESC[<button;x;y;M/m
  return mouseSGRFrom(await reader.readNextByteAsync())

proc readMouseX10(reader: AsyncInputReader): Event =
  ## Blocking `parseMouseEventX10`.
  mouseX10From(reader.readNextByte())

proc readMouseSGR(reader: AsyncInputReader): Event =
  ## Blocking `parseMouseEventSGR`.
  mouseSGRFrom(reader.readNextByte())

template utf8From(firstByte: byte, nextByte: untyped): Utf8AssemblyResult =
  ## `assembleUtf8Char` over `nextByte`, without its closure: a closure would
  ## make every caller of the blocking reader raise `Exception`.
  block:
    let lead = firstByte
    let byteLen = utf8ByteLength(lead)
    var assembly = Utf8AssemblyResult(text: "", leftover: none(byte))
    if byteLen == 1:
      assembly.text = $char(lead)
    elif byteLen > 1:
      let (secondLo, secondHi) = utf8SecondByteRange(lead)
      var continuationBytes: seq[byte]
      for i in 1 ..< byteLen:
        let next = nextByte
        if next.isNone:
          # Truncated: nothing to push back.
          assembly.text = Utf8ReplacementChar
          break
        let b = next.get.byte
        # The second byte must also stay inside the lead-byte range (no
        # overlongs or surrogates); a rejected byte starts the next event.
        if not isUtf8ContinuationByte(b) or (i == 1 and (b < secondLo or b > secondHi)):
          assembly = Utf8AssemblyResult(text: Utf8ReplacementChar, leftover: some(b))
          break
        continuationBytes.add(b)
      if assembly.text.len == 0:
        assembly.text = buildUtf8String(lead, continuationBytes)
    assembly

proc readUtf8CharAsync(
    reader: AsyncInputReader, firstByte: byte
): Future[Utf8AssemblyResult] {.async.} =
  return utf8From(firstByte, await reader.readNextByteAsync())

proc readUtf8Char(reader: AsyncInputReader, firstByte: byte): Utf8AssemblyResult =
  ## Blocking `readUtf8CharAsync`.
  utf8From(firstByte, reader.readNextByte())

# Async escape sequence parsing
# Uses the shared `parseEscapeSequenceUnified` template from core/events.
# Each reader expression is `await`-wrapped so the template's repeated use
# of the parameter becomes a fresh async byte read at each occurrence.

proc readByteTupleAsync(
    reader: AsyncInputReader
): Future[tuple[success: bool, ch: char]] {.async.} =
  ## Async adapter that exposes readNextByteAsync() with the same shape the
  ## unified routing template expects.
  let next = await reader.readNextByteAsync()
  return (success: next.isSome, ch: next.get('\0'))

proc readDrainByteAsync(
    reader: AsyncInputReader
): Future[tuple[success: bool, ch: char]] {.async.} =
  ## The template's `drainByte`: only a byte that is already there.
  let next = await reader.readCharAsync()
  return (success: next.isSome, ch: next.get('\0'))

proc readByteTuple(reader: AsyncInputReader): tuple[success: bool, ch: char] =
  ## Blocking `readByteTupleAsync`.
  let next = reader.readNextByte()
  (success: next.isSome, ch: next.get('\0'))

proc readDrainByte(reader: AsyncInputReader): tuple[success: bool, ch: char] =
  ## Blocking `readDrainByteAsync`.
  let next = reader.readCharNonBlocking()
  (success: next.isSome, ch: next.get('\0'))

proc readPasteByteAsync(reader: AsyncInputReader): Future[Option[char]] {.async.} =
  ## The next byte of paste content, waiting up to `PasteByteWaitMs`.
  if not (await reader.hasInputAsync(PasteByteWaitMs)):
    return none(char)
  return await reader.readCharAsync()

proc readPasteContentAsync(reader: AsyncInputReader): Future[string] {.async.} =
  ## Read all content until paste end sequence ESC[201~ (async mode).
  return pasteFrom(await reader.readPasteByteAsync())

proc readPasteContent(reader: AsyncInputReader): string =
  ## Blocking `readPasteContentAsync`.
  pasteFrom(reader.readNextByte(PasteByteWaitMs))

proc leadByteEvent(ch: char): Option[Event] =
  ## The event the first byte of an event makes on its own: Ctrl+C (`Quit`), a
  ## Ctrl combination, or Enter, Tab, Space or Backspace.
  if ch == '\x03':
    return some(Event(kind: Quit))
  let ctrlLetterResult = mapCtrlLetterKey(ch)
  if ctrlLetterResult.isCtrlKey:
    return some(Event(kind: Key, key: ctrlLetterResult.keyEvent))
  let ctrlNumberResult = mapCtrlNumberKey(ch)
  if ctrlNumberResult.isCtrlKey:
    return some(Event(kind: Key, key: ctrlNumberResult.keyEvent))
  let basicKey = mapBasicKey(ch)
  if basicKey.code in {Enter, Tab, Space, Backspace}:
    return some(Event(kind: Key, key: basicKey))

proc charEvent(reader: AsyncInputReader, assembly: Utf8AssemblyResult): Event =
  ## The key of an assembled UTF-8 character. A resync byte (Unicode §3.9) is
  ## stashed as the first byte of the next event; an invalid start byte reads
  ## as U+FFFD (KeyEvent.char invariant).
  if assembly.leftover.isSome:
    reader.setPendingByteAsync(assembly.leftover.get)
  let text = if assembly.text.len > 0: assembly.text else: Utf8ReplacementChar
  Event(kind: Key, key: KeyEvent(code: Char, char: text))

# Async key reading with escape sequence support
proc readKeyAsync*(reader: AsyncInputReader): Future[Event] {.async.} =
  ## Read a key event asynchronously using non-blocking I/O. While the close
  ## notice is pending this returns `Event(kind: InputClosed)`; once it is spent
  ## (or `readStdinAsync` took it) a closed reader reports `Unknown`, so a
  ## caller loop should watch `isClosed`.
  try:
    let next = await reader.readCharAsync()

    if next.isNone:
      if reader.takeCloseNotice():
        return Event(kind: InputClosed)
      return Event(kind: Unknown)

    let ch = next.get
    let lead = leadByteEvent(ch)
    if lead.isSome:
      return lead.get

    # Handle escape sequences via the unified routing template.
    # The post-ESC wait distinguishes standalone ESC from a sequence start; if
    # no follow-up byte arrives, return a bare ESC.
    if ch == '\x1b':
      let hasMoreData = await reader.hasInputAsync(EscapeWaitMs)
      if not hasMoreData:
        return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))
      return parseEscapeSequenceUnified(
        await reader.readByteTupleAsync(),
        await reader.readPasteContentAsync(),
        await reader.parseMouseEventX10(),
        await reader.parseMouseEventSGR(),
        reader.unreadInput,
        await reader.readDrainByteAsync(),
      )

    # Handle regular UTF-8 characters
    return reader.charEvent(await reader.readUtf8CharAsync(ch.byte))
  except CancelledError as e:
    # Must precede `except CatchableError` so chronos cancellation propagates
    # to the caller instead of being wrapped into AsyncEventError.
    raise e
  except CatchableError as e:
    raise newException(AsyncEventError, "Async key reading failed: " & e.msg)

# Non-blocking async event reading
proc pollKeyAsync*(reader: AsyncInputReader): Future[Option[Event]] {.async.} =
  ## Poll for a key event asynchronously (non-blocking). The close notice
  ## surfaces as `some(Event(kind: InputClosed))`; a closed reader polls as
  ## `none` once it is spent.
  try:
    # Check if input is available first
    let hasInput = await reader.hasInputAsync(1)
    if not hasInput:
      return none(Event)

    # Input is available, read the event
    let event = await reader.readKeyAsync()
    if event.kind != Unknown:
      return some(event)
    else:
      return none(Event)
  except CancelledError as e:
    # Must precede `except CatchableError` so chronos cancellation propagates
    # to the caller instead of being wrapped into AsyncEventError.
    raise e
  except CatchableError as e:
    raise newException(AsyncEventError, "Async key polling failed: " & e.msg)

proc readKey*(reader: AsyncInputReader): Event =
  ## Blocking `readKeyAsync`, for code that cannot await. Like `readKeyAsync`,
  ## it waits for the rest of a sequence split by the link, but not for the
  ## first byte: without input it returns `Unknown` at once (see `hasInput`).
  let next = reader.readCharNonBlocking()
  if next.isNone:
    if reader.takeCloseNotice():
      return Event(kind: InputClosed)
    return Event(kind: Unknown)

  let ch = next.get
  let lead = leadByteEvent(ch)
  if lead.isSome:
    return lead.get

  if ch == '\x1b':
    if not reader.hasInput(EscapeWaitMs):
      return Event(kind: Key, key: KeyEvent(code: Escape, char: "\x1b"))
    return parseEscapeSequenceUnified(
      reader.readByteTuple(),
      reader.readPasteContent(),
      reader.readMouseX10(),
      reader.readMouseSGR(),
      reader.unreadInput,
      reader.readDrainByte(),
    )

  reader.charEvent(reader.readUtf8Char(ch.byte))

# Event polling with timeout
proc pollEventsAsync*(
    reader: AsyncInputReader, timeoutMs: int
): Future[bool] {.async.} =
  ## Poll for available events asynchronously with a timeout
  ## Returns true if events are available, false if timeout occurred
  try:
    return await reader.hasInputAsync(timeoutMs)
  except CancelledError as e:
    # Must precede `except CatchableError` so chronos cancellation propagates
    # to the caller instead of being wrapped into AsyncEventError.
    raise e
  except CatchableError as e:
    raise newException(AsyncEventError, "Async event polling failed: " & e.msg)

# Advanced async event waiting
proc waitForKeyAsync*(reader: AsyncInputReader): Future[Event] {.async.} =
  ## Wait for a key press asynchronously (blocking until event). While stdin is
  ## closed, returns `Event(kind: InputClosed)` instead of waiting.
  while true:
    try:
      let event = await reader.readKeyAsync()
      if event.kind != Unknown:
        return event
      if reader.isClosed:
        discard reader.takeCloseNotice()
        return Event(kind: InputClosed)
    except CancelledError as e:
      # Must precede `except CatchableError` so chronos cancellation propagates
      # to the caller instead of being wrapped into AsyncEventError.
      raise e
    except CatchableError as e:
      raise newException(AsyncEventError, "Async key waiting failed: " & e.msg)

    # Small async sleep to prevent busy waiting
    await sleepMs(10)

proc waitForAnyKeyAsync*(reader: AsyncInputReader): Future[bool] {.async.} =
  ## Wait for any key press asynchronously. False on a quit request or once
  ## stdin has ended; use `waitForKeyAsync` to tell the two apart.
  let event = await reader.waitForKeyAsync()
  return event.kind notin {Quit, InputClosed}

# Multiple event source handling

# Async event stream
proc newAsyncEventStream*(
    reader: AsyncInputReader, callback: proc(event: Event): Future[bool] {.async.}
): AsyncEventStream =
  ## Create a new async event stream with callback.
  ##
  ## `reader` is borrowed, not owned: the caller is responsible for keeping
  ## it alive for as long as the stream may be polling (i.e. at least until
  ## `stream.running` is false) and for closing it afterwards via
  ## `closeAsyncInputReader`. Closing `reader` while the stream is still
  ## running will use-after-close the underlying selector fd.
  let termSize = getTerminalSizeOrDefault()
  return AsyncEventStream(
    reader: reader,
    running: false,
    eventCallback: callback,
    lastWidth: termSize.width,
    lastHeight: termSize.height,
  )

proc startAsync*(stream: AsyncEventStream) {.async.} =
  ## Start the async event stream
  stream.running = true

  while stream.running:
    try:
      # Check for events from multiple sources
      var event: Option[Event]

      # Check resize first (highest priority) by polling terminal size
      let currentSize = getTerminalSizeOrDefault()
      if currentSize.width != stream.lastWidth or currentSize.height != stream.lastHeight:
        stream.lastWidth = currentSize.width
        stream.lastHeight = currentSize.height
        event = some(Event(kind: Resize))
      else:
        # Check for keyboard events
        let keyEventOpt = await stream.reader.pollKeyAsync()
        if keyEventOpt.isSome():
          event = keyEventOpt
        else:
          # Small sleep to prevent busy waiting
          await sleepMs(16) # ~60 FPS
          continue

      if event.isSome() and stream.eventCallback != nil:
        let shouldContinue = await stream.eventCallback(event.get())
        if not shouldContinue:
          stream.running = false
    except CatchableError:
      # Any errors should stop the stream for now
      stream.running = false

proc stopAsync*(stream: AsyncEventStream) {.async.} =
  ## Stop the async event stream
  stream.running = false
