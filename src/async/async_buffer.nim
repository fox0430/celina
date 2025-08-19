## Async-safe Buffer implementation
##
## This module provides memory-safe Buffer types that can be used
## in async closures without violating Nim's memory safety requirements.

import std/atomics

import chronos

import ../core/[buffer, geometry, colors]

# Re-export core buffer types for convenience
export buffer, geometry, colors

type
  ## Thread-safe reference to a Buffer for async operations
  AsyncBuffer* = ref object
    buffer: Buffer
    lock: Atomic[bool] # Simple spinlock for thread safety

  ## Shared buffer pool for efficient memory management
  AsyncBufferPool* = ref object
    buffers: seq[AsyncBuffer]
    maxSize: int

# ============================================================================
# AsyncBuffer Creation and Management
# ============================================================================

proc newAsyncBuffer*(area: Rect): AsyncBuffer =
  ## Create a new async-safe buffer with the specified area
  result = AsyncBuffer()
  result.buffer = newBuffer(area)
  result.lock.store(false)

proc newAsyncBuffer*(width, height: int): AsyncBuffer {.inline.} =
  ## Create a new async-safe buffer with specified dimensions
  newAsyncBuffer(rect(0, 0, width, height))

proc clone*(asyncBuffer: AsyncBuffer): AsyncBuffer =
  ## Create a deep copy of an async buffer
  result = AsyncBuffer()
  result.buffer = asyncBuffer.buffer # Buffer is copied by value
  result.lock.store(false)

# ============================================================================
# Thread-Safe Access Methods
# ============================================================================

template withBuffer*(asyncBuffer: AsyncBuffer, operation: untyped): untyped =
  ## Thread-safe template for accessing the internal buffer
  ## Uses a simple spinlock to ensure exclusive access
  while asyncBuffer.lock.exchange(true):
    # Spin wait - in practice, this should be very brief
    discard

  try:
    # Allow access to 'buffer' variable within the template
    template buffer(): untyped =
      asyncBuffer.buffer

    operation
  finally:
    asyncBuffer.lock.store(false)

proc getArea*(asyncBuffer: AsyncBuffer): Rect =
  ## Get buffer area (thread-safe)
  asyncBuffer.withBuffer:
    result = buffer.area

proc getSize*(asyncBuffer: AsyncBuffer): Size =
  ## Get buffer size (thread-safe)
  asyncBuffer.withBuffer:
    result = size(buffer.area.width, buffer.area.height)

# ============================================================================
# Async-Safe Buffer Operations
# ============================================================================

proc clearAsync*(asyncBuffer: AsyncBuffer, cell: Cell = cell()) {.async.} =
  ## Clear buffer asynchronously
  asyncBuffer.withBuffer:
    buffer.clear(cell)

  # Yield to allow other async operations
  await sleepAsync(0.milliseconds)

proc setStringAsync*(
    asyncBuffer: AsyncBuffer, x, y: int, text: string, style: Style = defaultStyle()
) {.async.} =
  ## Set string asynchronously
  asyncBuffer.withBuffer:
    buffer.setString(x, y, text, style)

  # Yield to allow other async operations
  await sleepAsync(0.milliseconds)

proc setStringAsync*(
    asyncBuffer: AsyncBuffer, pos: Position, text: string, style: Style = defaultStyle()
) {.async.} =
  ## Set string at position asynchronously
  await asyncBuffer.setStringAsync(pos.x, pos.y, text, style)

proc setCellAsync*(asyncBuffer: AsyncBuffer, x, y: int, cell: Cell) {.async.} =
  ## Set cell asynchronously
  asyncBuffer.withBuffer:
    buffer[x, y] = cell

  await sleepAsync(0.milliseconds)

proc setCellAsync*(asyncBuffer: AsyncBuffer, pos: Position, cell: Cell) {.async.} =
  ## Set cell at position asynchronously
  await asyncBuffer.setCellAsync(pos.x, pos.y, cell)

proc fillAsync*(asyncBuffer: AsyncBuffer, area: Rect, fillCell: Cell) {.async.} =
  ## Fill area asynchronously
  asyncBuffer.withBuffer:
    buffer.fill(area, fillCell)

  await sleepAsync(0.milliseconds)

proc resizeAsync*(asyncBuffer: AsyncBuffer, newArea: Rect) {.async.} =
  ## Resize buffer asynchronously
  asyncBuffer.withBuffer:
    buffer.resize(newArea)

  await sleepAsync(0.milliseconds)

# ============================================================================
# Synchronous Access (when needed)
# ============================================================================

proc getCell*(asyncBuffer: AsyncBuffer, x, y: int): Cell =
  ## Get cell synchronously (thread-safe)
  asyncBuffer.withBuffer:
    result = buffer[x, y]

proc getCell*(asyncBuffer: AsyncBuffer, pos: Position): Cell =
  ## Get cell at position synchronously (thread-safe)
  asyncBuffer.getCell(pos.x, pos.y)

proc setString*(
    asyncBuffer: AsyncBuffer, x, y: int, text: string, style: Style = defaultStyle()
) =
  ## Set string synchronously (thread-safe)
  asyncBuffer.withBuffer:
    buffer.setString(x, y, text, style)

proc setString*(
    asyncBuffer: AsyncBuffer, pos: Position, text: string, style: Style = defaultStyle()
) =
  ## Set string at position synchronously (thread-safe)
  asyncBuffer.setString(pos.x, pos.y, text, style)

proc clear*(asyncBuffer: AsyncBuffer, cell: Cell = cell()) =
  ## Clear buffer synchronously (thread-safe)
  asyncBuffer.withBuffer:
    buffer.clear(cell)

# ============================================================================
# Buffer Conversion and Integration
# ============================================================================

proc toBuffer*(asyncBuffer: AsyncBuffer): Buffer =
  ## Convert AsyncBuffer to regular Buffer (creates copy)
  asyncBuffer.withBuffer:
    result = buffer

proc updateFromBuffer*(asyncBuffer: AsyncBuffer, sourceBuffer: Buffer) =
  ## Update AsyncBuffer from a regular Buffer
  asyncBuffer.withBuffer:
    buffer = sourceBuffer

proc mergeAsync*(
    dest: AsyncBuffer, src: AsyncBuffer, destPos: Position = pos(0, 0)
) {.async.} =
  ## Merge one AsyncBuffer into another asynchronously
  let srcBuffer = src.toBuffer()

  dest.withBuffer:
    buffer.merge(srcBuffer, destPos)

  await sleepAsync(0.milliseconds)

# ============================================================================
# AsyncBuffer Pool for Performance
# ============================================================================

proc newAsyncBufferPool*(maxSize: int = 10): AsyncBufferPool =
  ## Create a new async buffer pool for efficient memory management
  AsyncBufferPool(buffers: @[], maxSize: maxSize)

proc getBuffer*(pool: AsyncBufferPool, area: Rect): AsyncBuffer =
  ## Get a buffer from the pool or create new one
  if pool.buffers.len > 0:
    result = pool.buffers.pop()
    result.withBuffer:
      if buffer.area != area:
        buffer.resize(area)
      else:
        buffer.clear()
  else:
    result = newAsyncBuffer(area)

proc returnBuffer*(pool: AsyncBufferPool, asyncBuffer: AsyncBuffer) =
  ## Return a buffer to the pool
  if pool.buffers.len < pool.maxSize:
    asyncBuffer.clear()
    pool.buffers.add(asyncBuffer)

# ============================================================================
# Async-Safe Rendering Utilities  
# ============================================================================

proc toStringsAsync*(asyncBuffer: AsyncBuffer): Future[seq[string]] {.async.} =
  ## Convert buffer to strings asynchronously
  asyncBuffer.withBuffer:
    result = buffer.toStrings()

  await sleepAsync(0.milliseconds)

proc diffAsync*(
    old, new: AsyncBuffer
): Future[seq[tuple[pos: Position, cell: Cell]]] {.async.} =
  ## Calculate differences between two async buffers
  let oldBuffer = old.toBuffer()
  let newBuffer = new.toBuffer()

  result = diff(oldBuffer, newBuffer)
  await sleepAsync(0.milliseconds)

# ============================================================================
# Debugging and Utilities
# ============================================================================

proc `$`*(asyncBuffer: AsyncBuffer): string =
  ## String representation of AsyncBuffer
  asyncBuffer.withBuffer:
    result = "AsyncBuffer(" & $buffer.area & ")"

proc isLocked*(asyncBuffer: AsyncBuffer): bool =
  ## Check if buffer is currently locked
  asyncBuffer.lock.load()

proc stats*(asyncBuffer: AsyncBuffer): tuple[area: Rect, locked: bool] =
  ## Get buffer statistics
  (area: asyncBuffer.getArea(), locked: asyncBuffer.isLocked())
