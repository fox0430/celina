## Async-safe Buffer implementation
##
## This module provides memory-safe Buffer types that can be used
## in async closures without violating Nim's memory safety requirements.

import std/[locks, strformat]

import async_backend

import ../core/[buffer, geometry, colors, resources]

export buffer, geometry, colors

type AsyncBufferMetrics* = object ## Performance monitoring
  activeBuffers*: int
  totalCreated*: int
  poolHits*: int
  avgLockWaitTime*: float

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
  AsyncBuffer* = ref object ## Thread-safe reference to a Buffer for async operations
    buffer: Buffer
    lock: Lock # Proper lock instead of spinlock
    resourceId: ResourceId

  AsyncBufferPool* = ref object ## Shared buffer pool for efficient memory management
    buffers: seq[AsyncBuffer]
    maxSize: int
    poolLock: Lock

# Forward declarations
proc destroyAsync*(asyncBuffer: AsyncBuffer)

# AsyncBuffer Creation and Management

proc newAsyncBuffer*(area: Rect): AsyncBuffer =
  ## Create a new async-safe buffer with the specified area
  result = AsyncBuffer()
  result.buffer = newBuffer(area)
  initLock(result.lock)

  # Register with resource manager
  let rm = getGlobalResourceManager()
  let asyncBuf = result # Capture specific reference
  result.resourceId = rm.registerResource(
    RsBuffer,
    &"AsyncBuffer({area.width}x{area.height})",
    proc() =
      try:
        deinitLock(asyncBuf.lock)
      except:
        discard,
  )

proc newAsyncBuffer*(width, height: int): AsyncBuffer {.inline.} =
  ## Create a new async-safe buffer with specified dimensions
  newAsyncBuffer(rect(0, 0, width, height))

proc newAsyncBufferNoRM*(area: Rect): AsyncBuffer =
  ## Create a new async-safe buffer without resource manager registration
  ## Used in async contexts to avoid GC safety issues
  result = AsyncBuffer()
  result.buffer = newBuffer(area)
  initLock(result.lock)
  result.resourceId = ResourceId(0) # No resource tracking

proc newAsyncBufferNoRM*(width, height: int): AsyncBuffer {.inline.} =
  ## Create a new async-safe buffer with specified dimensions without resource manager
  newAsyncBufferNoRM(rect(0, 0, width, height))

proc clone*(asyncBuffer: AsyncBuffer): AsyncBuffer =
  ## Create a deep copy of an async buffer
  result = AsyncBuffer()
  withLock(asyncBuffer.lock):
    result.buffer = asyncBuffer.buffer # Buffer is copied by value
  initLock(result.lock)

  # Register the cloned buffer
  let rm = getGlobalResourceManager()
  let clonedBuf = result # Capture specific reference
  result.resourceId = rm.registerResource(
    RsBuffer,
    &"AsyncBuffer-Clone({result.buffer.area.width}x{result.buffer.area.height})",
    proc() =
      try:
        deinitLock(clonedBuf.lock)
      except:
        discard,
  )

# Thread-Safe Access Methods

template withBuffer*(asyncBuffer: AsyncBuffer, operation: untyped): untyped =
  ## Thread-safe template for accessing the internal buffer
  ## Uses proper locks instead of spinlock for better performance
  withLock(asyncBuffer.lock):
    # Allow access to 'buffer' variable within the template
    template buffer(): untyped =
      asyncBuffer.buffer

    # Update resource access time
    let rm = getGlobalResourceManager()
    rm.touchResource(asyncBuffer.resourceId)

    operation

template withBufferAsync*(asyncBuffer: AsyncBuffer, operation: untyped): untyped =
  ## Thread-safe template for accessing the internal buffer in async context
  ## Skips resource tracking to avoid GC safety issues
  withLock(asyncBuffer.lock):
    # Allow access to 'buffer' variable within the template
    template buffer(): untyped =
      asyncBuffer.buffer

    operation

proc getArea*(asyncBuffer: AsyncBuffer): Rect =
  ## Get buffer area (thread-safe)
  asyncBuffer.withBuffer:
    result = buffer.area

proc getSize*(asyncBuffer: AsyncBuffer): Size =
  ## Get buffer size (thread-safe)
  asyncBuffer.withBuffer:
    result = size(buffer.area.width, buffer.area.height)

# Async-Safe Buffer Operations

proc clearAsync*(asyncBuffer: AsyncBuffer, cell: Cell = cell()) {.async.} =
  ## Clear buffer asynchronously
  asyncBuffer.withBufferAsync:
    buffer.clear(cell)

  # Yield to allow other async operations
  await sleepMs(0)

proc setStringAsync*(
    asyncBuffer: AsyncBuffer, x, y: int, text: string, style: Style = defaultStyle()
) {.async.} =
  ## Set string asynchronously
  asyncBuffer.withBufferAsync:
    buffer.setString(x, y, text, style)

  # Yield to allow other async operations
  await sleepMs(0)

proc setStringAsync*(
    asyncBuffer: AsyncBuffer, pos: Position, text: string, style: Style = defaultStyle()
) {.async.} =
  ## Set string at position asynchronously
  await asyncBuffer.setStringAsync(pos.x, pos.y, text, style)

proc setCellAsync*(asyncBuffer: AsyncBuffer, x, y: int, cell: Cell) {.async.} =
  ## Set cell asynchronously
  asyncBuffer.withBufferAsync:
    buffer[x, y] = cell

  await sleepMs(0)

proc setCellAsync*(asyncBuffer: AsyncBuffer, pos: Position, cell: Cell) {.async.} =
  ## Set cell at position asynchronously
  await asyncBuffer.setCellAsync(pos.x, pos.y, cell)

proc fillAsync*(asyncBuffer: AsyncBuffer, area: Rect, fillCell: Cell) {.async.} =
  ## Fill area asynchronously
  asyncBuffer.withBufferAsync:
    buffer.fill(area, fillCell)

  await sleepMs(0)

proc resizeAsync*(asyncBuffer: AsyncBuffer, newArea: Rect) {.async.} =
  ## Resize buffer asynchronously
  asyncBuffer.withBufferAsync:
    buffer.resize(newArea)

  await sleepMs(0)

# Synchronous Access (when needed)

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

# Dirty Region Management (Optimization Integration)

proc clearDirty*(asyncBuffer: AsyncBuffer) =
  ## Clear the dirty region after rendering (thread-safe)
  ## This should be called after the buffer has been successfully rendered
  ## to reset the dirty tracking for the next frame
  asyncBuffer.withBuffer:
    buffer.clearDirty()

proc clearDirtyAsync*(asyncBuffer: AsyncBuffer) {.async.} =
  ## Clear the dirty region asynchronously
  asyncBuffer.withBufferAsync:
    buffer.clearDirty()

  await sleepMs(0)

proc isDirty*(asyncBuffer: AsyncBuffer): bool =
  ## Check if the buffer has any dirty regions (thread-safe)
  asyncBuffer.withBuffer:
    result = buffer.dirty.isDirty

proc getDirtyRegionSize*(asyncBuffer: AsyncBuffer): int =
  ## Get the size of the dirty region (thread-safe)
  ## Returns 0 if no changes have been made
  asyncBuffer.withBuffer:
    result = buffer.getDirtyRegionSize()

# Buffer Conversion and Integration

proc toBuffer*(asyncBuffer: AsyncBuffer): Buffer =
  ## Convert AsyncBuffer to regular Buffer (creates copy)
  asyncBuffer.withBuffer:
    result = buffer

proc toBufferAsync*(asyncBuffer: AsyncBuffer): Buffer =
  ## Convert AsyncBuffer to regular Buffer (creates copy) - async-safe version
  asyncBuffer.withBufferAsync:
    result = buffer

proc updateFromBuffer*(asyncBuffer: AsyncBuffer, sourceBuffer: Buffer) =
  ## Update AsyncBuffer from a regular Buffer
  asyncBuffer.withBuffer:
    buffer = sourceBuffer

proc updateFromBufferAsync*(asyncBuffer: AsyncBuffer, sourceBuffer: Buffer) =
  ## Update AsyncBuffer from a regular Buffer - async-safe version
  asyncBuffer.withBufferAsync:
    buffer = sourceBuffer

proc mergeAsync*(
    dest: AsyncBuffer, src: AsyncBuffer, destPos: Position = pos(0, 0)
) {.async.} =
  ## Merge one AsyncBuffer into another asynchronously
  let srcBuffer = src.toBufferAsync()

  dest.withBufferAsync:
    buffer.merge(srcBuffer, destPos)

  await sleepMs(0)

# AsyncBuffer Pool for Performance

proc getBuffer*(pool: AsyncBufferPool, area: Rect): AsyncBuffer =
  ## Get a buffer from the pool or create new one
  withLock(pool.poolLock):
    if pool.buffers.len > 0:
      result = pool.buffers.pop()
      trackAsyncBufferCreation() # Count as reuse
      result.withBuffer:
        if buffer.area != area:
          buffer.resize(area)
        else:
          buffer.clear()
    else:
      result = newAsyncBuffer(area)
      trackAsyncBufferCreation()

proc returnBuffer*(pool: AsyncBufferPool, asyncBuffer: AsyncBuffer) =
  ## Return a buffer to the pool
  withLock(pool.poolLock):
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
  asyncBuffer.withBufferAsync:
    result = buffer.toStrings()

  await sleepMs(0)

proc diffAsync*(
    old, new: AsyncBuffer
): Future[seq[tuple[pos: Position, cell: Cell]]] {.async.} =
  ## Calculate differences between two async buffers
  let oldBuffer = old.toBufferAsync()
  let newBuffer = new.toBufferAsync()

  result = diff(oldBuffer, newBuffer)
  await sleepMs(0)

# Debugging and Utilities

proc `$`*(asyncBuffer: AsyncBuffer): string =
  ## String representation of AsyncBuffer
  asyncBuffer.withBuffer:
    result = "AsyncBuffer(" & $buffer.area & ")"

proc destroyAsync*(asyncBuffer: AsyncBuffer) =
  ## Properly destroy an async buffer and clean up resources
  try:
    let rm = getGlobalResourceManager()
    rm.unregisterResource(asyncBuffer.resourceId)
  except:
    discard # Skip resource cleanup if manager not available

  try:
    deinitLock(asyncBuffer.lock)
  except:
    discard # Best effort cleanup

proc stats*(asyncBuffer: AsyncBuffer): tuple[area: Rect, resourceId: ResourceId] =
  ## Get buffer statistics
  (area: asyncBuffer.getArea(), resourceId: asyncBuffer.resourceId)

# Resource Management Integration

proc newAsyncBufferPool*(maxSize: int = 10): AsyncBufferPool =
  ## Create a new async buffer pool for efficient memory management
  result = AsyncBufferPool(buffers: @[], maxSize: maxSize)
  initLock(result.poolLock)

proc destroyAsyncBufferPool*(pool: AsyncBufferPool) =
  ## Properly destroy a buffer pool
  withLock(pool.poolLock):
    for buffer in pool.buffers:
      buffer.destroyAsync()
    pool.buffers.setLen(0)

  try:
    deinitLock(pool.poolLock)
  except:
    discard

template withAsyncBuffer*(area: Rect, name: string, body: untyped): untyped =
  ## Template for automatic async buffer management
  let asyncBuffer {.inject.} = newAsyncBuffer(area)
  try:
    body
  finally:
    asyncBuffer.destroyAsync()
