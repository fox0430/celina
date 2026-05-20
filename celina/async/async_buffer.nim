## Async-safe Buffer implementation
##
## This module provides Buffer types for async closures. Both supported
## async backends (asyncdispatch and chronos) are single-threaded
## cooperative runtimes, so no locking is required — the buffer is only
## ever touched by one coroutine at a time, and async procs below do not
## await between buffer access and yield points.

import std/unicode

import async_backend

import ../core/[buffer, geometry, colors]

export buffer, geometry, colors

type AsyncBufferMetrics* = object ## Performance monitoring
  activeBuffers*: int
  totalCreated*: int
  poolHits*: int

var globalAsyncBufferMetrics* {.threadvar.}: AsyncBufferMetrics

# Metrics and tracking functions (defined early for use in other functions)

proc trackAsyncBufferCreation*() =
  globalAsyncBufferMetrics.totalCreated.inc()
  globalAsyncBufferMetrics.activeBuffers.inc()

proc trackAsyncBufferDestroy*() =
  globalAsyncBufferMetrics.activeBuffers.dec()

proc getAsyncBufferMetrics*(): AsyncBufferMetrics =
  globalAsyncBufferMetrics

type
  AsyncBuffer* = ref object ## Reference to a Buffer for async operations
    buffer: Buffer

  AsyncBufferPool* = ref object ## Shared buffer pool for efficient memory management
    buffers: seq[AsyncBuffer]
    maxSize: int

# Forward declarations
proc destroyAsync*(asyncBuffer: AsyncBuffer)

# AsyncBuffer Creation and Management

proc newAsyncBuffer*(area: Rect): AsyncBuffer =
  ## Create a new async-safe buffer with the specified area
  result = AsyncBuffer()
  result.buffer = newBuffer(area)

proc newAsyncBuffer*(width, height: int): AsyncBuffer {.inline.} =
  ## Create a new async-safe buffer with specified dimensions
  newAsyncBuffer(rect(0, 0, width, height))

proc clone*(asyncBuffer: AsyncBuffer): AsyncBuffer =
  ## Create a deep copy of an async buffer
  result = AsyncBuffer()
  result.buffer = asyncBuffer.buffer # Buffer is copied by value

# Internal Buffer Access Templates

template withBuffer*(asyncBuffer: AsyncBuffer, operation: untyped): untyped =
  ## Template for accessing the internal buffer
  block:
    template buffer(): untyped =
      asyncBuffer.buffer

    operation

template withBufferAsync*(asyncBuffer: AsyncBuffer, operation: untyped): untyped =
  ## Template for accessing the internal buffer in async context
  block:
    template buffer(): untyped =
      asyncBuffer.buffer

    operation

proc getArea*(asyncBuffer: AsyncBuffer): Rect =
  ## Get buffer area
  asyncBuffer.buffer.area

proc getSize*(asyncBuffer: AsyncBuffer): Size =
  ## Get buffer size
  size(asyncBuffer.buffer.area.width, asyncBuffer.buffer.area.height)

# Async-Safe Buffer Operations

proc clearAsync*(asyncBuffer: AsyncBuffer, cell: Cell = cell()) {.async.} =
  ## Clear buffer asynchronously
  asyncBuffer.buffer.clear(cell)

  # Yield to allow other async operations
  await sleepMs(0)

proc setStringAsync*(
    asyncBuffer: AsyncBuffer,
    x, y: int,
    text: string,
    style: Style = defaultStyle(),
    hyperlink: string = "",
) {.async.} =
  ## Set string asynchronously
  asyncBuffer.buffer.setString(x, y, text, style, hyperlink)

  # Yield to allow other async operations
  await sleepMs(0)

proc setStringAsync*(
    asyncBuffer: AsyncBuffer,
    pos: Position,
    text: string,
    style: Style = defaultStyle(),
    hyperlink: string = "",
) {.async.} =
  ## Set string at position asynchronously
  await asyncBuffer.setStringAsync(pos.x, pos.y, text, style, hyperlink)

proc setRunesAsync*(
    asyncBuffer: AsyncBuffer,
    x, y: int,
    runes: seq[Rune],
    style: Style = defaultStyle(),
    hyperlink: string = "",
) {.async.} =
  ## Set a sequence of runes starting at the given coordinates asynchronously
  asyncBuffer.buffer.setRunes(x, y, runes, style, hyperlink)

  await sleepMs(0)

proc setRunesAsync*(
    asyncBuffer: AsyncBuffer,
    pos: Position,
    runes: seq[Rune],
    style: Style = defaultStyle(),
    hyperlink: string = "",
) {.async.} =
  ## Set a sequence of runes starting at the given position asynchronously
  await asyncBuffer.setRunesAsync(pos.x, pos.y, runes, style, hyperlink)

proc setCellAsync*(asyncBuffer: AsyncBuffer, x, y: int, cell: Cell) {.async.} =
  ## Set cell asynchronously
  asyncBuffer.buffer[x, y] = cell

  await sleepMs(0)

proc setCellAsync*(asyncBuffer: AsyncBuffer, pos: Position, cell: Cell) {.async.} =
  ## Set cell at position asynchronously
  await asyncBuffer.setCellAsync(pos.x, pos.y, cell)

proc fillAsync*(asyncBuffer: AsyncBuffer, area: Rect, fillCell: Cell) {.async.} =
  ## Fill area asynchronously
  asyncBuffer.buffer.fill(area, fillCell)

  await sleepMs(0)

proc resizeAsync*(asyncBuffer: AsyncBuffer, newArea: Rect) {.async.} =
  ## Resize buffer asynchronously
  asyncBuffer.buffer.resize(newArea)

  await sleepMs(0)

# Synchronous Access

proc getCell*(asyncBuffer: AsyncBuffer, x, y: int): Cell =
  ## Get cell
  asyncBuffer.buffer[x, y]

proc getCell*(asyncBuffer: AsyncBuffer, pos: Position): Cell =
  ## Get cell at position
  asyncBuffer.getCell(pos.x, pos.y)

proc setString*(
    asyncBuffer: AsyncBuffer,
    x, y: int,
    text: string,
    style: Style = defaultStyle(),
    hyperlink: string = "",
) =
  ## Set string
  asyncBuffer.buffer.setString(x, y, text, style, hyperlink)

proc setString*(
    asyncBuffer: AsyncBuffer,
    pos: Position,
    text: string,
    style: Style = defaultStyle(),
    hyperlink: string = "",
) =
  ## Set string at position
  asyncBuffer.setString(pos.x, pos.y, text, style, hyperlink)

proc setRunes*(
    asyncBuffer: AsyncBuffer,
    x, y: int,
    runes: seq[Rune],
    style: Style = defaultStyle(),
    hyperlink: string = "",
) =
  ## Set a sequence of runes starting at the given coordinates
  asyncBuffer.buffer.setRunes(x, y, runes, style, hyperlink)

proc setRunes*(
    asyncBuffer: AsyncBuffer,
    pos: Position,
    runes: seq[Rune],
    style: Style = defaultStyle(),
    hyperlink: string = "",
) =
  ## Set a sequence of runes starting at the given position
  asyncBuffer.setRunes(pos.x, pos.y, runes, style, hyperlink)

proc clear*(asyncBuffer: AsyncBuffer, cell: Cell = cell()) =
  ## Clear buffer
  asyncBuffer.buffer.clear(cell)

# Dirty Region Management (Optimization Integration)

proc clearDirty*(asyncBuffer: AsyncBuffer) =
  ## Clear the dirty region after rendering
  ## This should be called after the buffer has been successfully rendered
  ## to reset the dirty tracking for the next frame
  asyncBuffer.buffer.clearDirty()

proc clearDirtyAsync*(asyncBuffer: AsyncBuffer) {.async.} =
  ## Clear the dirty region asynchronously
  asyncBuffer.buffer.clearDirty()

  await sleepMs(0)

proc isDirty*(asyncBuffer: AsyncBuffer): bool =
  ## Check if the buffer has any dirty regions
  asyncBuffer.buffer.isDirty

proc getDirtyRegionSize*(asyncBuffer: AsyncBuffer): int =
  ## Get the size of the dirty region
  ## Returns 0 if no changes have been made
  asyncBuffer.buffer.getDirtyRegionSize()

# Buffer Conversion and Integration

proc toBuffer*(asyncBuffer: AsyncBuffer): Buffer =
  ## Convert AsyncBuffer to regular Buffer (creates copy)
  asyncBuffer.buffer

proc toBufferAsync*(asyncBuffer: AsyncBuffer): Buffer =
  ## Convert AsyncBuffer to regular Buffer (creates copy) - async-safe version
  asyncBuffer.buffer

proc updateFromBuffer*(asyncBuffer: AsyncBuffer, sourceBuffer: Buffer) =
  ## Update AsyncBuffer from a regular Buffer
  asyncBuffer.buffer = sourceBuffer

proc updateFromBufferAsync*(asyncBuffer: AsyncBuffer, sourceBuffer: Buffer) =
  ## Update AsyncBuffer from a regular Buffer - async-safe version
  asyncBuffer.buffer = sourceBuffer

proc mergeAsync*(
    dest: AsyncBuffer, src: AsyncBuffer, destPos: Position = pos(0, 0)
) {.async.} =
  ## Merge one AsyncBuffer into another asynchronously
  dest.buffer.merge(src.buffer, destPos)

  await sleepMs(0)

# AsyncBuffer Pool for Performance

proc getBuffer*(pool: AsyncBufferPool, area: Rect): AsyncBuffer =
  ## Get a buffer from the pool or create new one
  if pool.buffers.len > 0:
    result = pool.buffers.pop()
    trackAsyncBufferCreation() # Count as reuse
    if result.buffer.area != area:
      result.buffer.resize(area)
    else:
      result.buffer.clear()
  else:
    result = newAsyncBuffer(area)
    trackAsyncBufferCreation()

proc returnBuffer*(pool: AsyncBufferPool, asyncBuffer: AsyncBuffer) =
  ## Return a buffer to the pool
  if pool.buffers.len < pool.maxSize:
    asyncBuffer.clear() # AsyncBuffer has its own clear method
    pool.buffers.add(asyncBuffer)
  else:
    # Pool is full, destroy the buffer
    asyncBuffer.destroyAsync()
    trackAsyncBufferDestroy()

# Async-Safe Rendering Utilities

proc toStringsAsync*(asyncBuffer: AsyncBuffer): Future[seq[string]] {.async.} =
  ## Convert buffer to strings asynchronously
  result = asyncBuffer.buffer.toStrings()

  await sleepMs(0)

proc diffAsync*(
    old, new: AsyncBuffer
): Future[seq[tuple[pos: Position, cell: Cell]]] {.async.} =
  ## Calculate differences between two async buffers
  result = diff(old.buffer, new.buffer)
  await sleepMs(0)

# Debugging and Utilities

proc `$`*(asyncBuffer: AsyncBuffer): string =
  ## String representation of AsyncBuffer
  "AsyncBuffer(" & $asyncBuffer.buffer.area & ")"

proc destroyAsync*(asyncBuffer: AsyncBuffer) =
  ## Properly destroy an async buffer
  ## Kept as a no-op for API compatibility; AsyncBuffer holds no resources
  ## requiring explicit cleanup now that the lock has been removed.
  discard

proc stats*(asyncBuffer: AsyncBuffer): tuple[area: Rect] =
  ## Get buffer statistics
  (area: asyncBuffer.getArea())

# Resource Management Integration

proc newAsyncBufferPool*(maxSize: int = 10): AsyncBufferPool =
  ## Create a new async buffer pool for efficient memory management
  AsyncBufferPool(buffers: @[], maxSize: maxSize)

proc destroyAsyncBufferPool*(pool: AsyncBufferPool) =
  ## Properly destroy a buffer pool
  for buffer in pool.buffers:
    buffer.destroyAsync()
  pool.buffers.setLen(0)

template withAsyncBuffer*(area: Rect, name: string, body: untyped): untyped =
  ## Template for automatic async buffer management
  let asyncBuffer {.inject.} = newAsyncBuffer(area)
  try:
    body
  finally:
    asyncBuffer.destroyAsync()
