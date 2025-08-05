## Lazy Loading Text Buffer for Very Large Files
##
## This module implements a lazy loading strategy for files that are too large
## to load entirely into memory. It loads only the portions of the file that
## are currently visible or likely to be accessed soon.

import std/[options, streams, os, strutils, deques, tables, times, unicode]
import types, unicode_utils

const
  LAZY_THRESHOLD = 50 * 1024 * 1024  # 50MB - use lazy loading for larger files
  CHUNK_SIZE = 64 * 1024             # 64KB per chunk
  MAX_CHUNKS_IN_MEMORY = 256         # Maximum chunks to keep in memory (16MB)
  PREFETCH_CHUNKS = 8                # Number of chunks to prefetch ahead/behind

type
  ChunkId* = int
  
  FileChunk* = ref object
    id*: ChunkId
    startPos*: int64        # Start position in file
    endPos*: int64          # End position in file
    data*: string           # Actual chunk data
    lines*: seq[string]     # Lines in this chunk
    lineOffsets*: seq[int]  # Byte offsets of lines within chunk
    lastAccess*: DateTime   # For LRU eviction
    dirty*: bool            # Modified since last save
    loading*: bool          # Currently being loaded
  
  ChunkCache* = ref object
    chunks*: Table[ChunkId, FileChunk]
    lruQueue*: Deque[ChunkId]
    maxChunks*: int
  
  LazyTextBuffer* = ref object
    filePath*: string
    fileSize*: int64
    modified*: bool
    readOnly*: bool
    lineEnding*: LineEnding
    encoding*: string
    
    # File stream for random access
    fileStream*: FileStream
    
    # Chunk management
    chunkCache*: ChunkCache
    totalChunks*: int
    chunkSize*: int
    
    # Line index for fast line access
    lineIndex*: seq[tuple[chunkId: ChunkId, lineInChunk: int]]
    totalLines*: int
    indexBuilt*: bool
    
    # Current viewport for prefetching
    viewportStart*: int
    viewportEnd*: int
    
    # Background loading
    pendingLoads*: Deque[ChunkId]

proc newChunkCache*(maxChunks: int = MAX_CHUNKS_IN_MEMORY): ChunkCache =
  ChunkCache(
    chunks: initTable[ChunkId, FileChunk](),
    lruQueue: initDeque[ChunkId](),
    maxChunks: maxChunks
  )

proc newLazyTextBuffer*(filePath: string): LazyTextBuffer =
  let fileInfo = getFileInfo(filePath)
  let fileSize = fileInfo.size
  let totalChunks = int((fileSize + CHUNK_SIZE - 1) div CHUNK_SIZE)
  
  result = LazyTextBuffer(
    filePath: filePath,
    fileSize: fileSize,
    modified: false,
    readOnly: false,
    lineEnding: LF,
    encoding: "UTF-8",
    fileStream: newFileStream(filePath, fmRead),
    chunkCache: newChunkCache(),
    totalChunks: totalChunks,
    chunkSize: CHUNK_SIZE,
    lineIndex: @[],
    totalLines: 0,
    indexBuilt: false,
    viewportStart: 0,
    viewportEnd: 0,
    pendingLoads: initDeque[ChunkId]()
  )

proc shouldUseLazyLoading*(filePath: string): bool =
  try:
    let fileInfo = getFileInfo(filePath)
    fileInfo.size > LAZY_THRESHOLD
  except OSError:
    false

proc updateLRU(cache: ChunkCache, chunkId: ChunkId) =
  # Remove from current position
  var newQueue = initDeque[ChunkId]()
  for id in cache.lruQueue:
    if id != chunkId:
      newQueue.addLast(id)
  cache.lruQueue = newQueue
  
  # Add to front (most recently used)
  cache.lruQueue.addFirst(chunkId)

proc evictLRUChunk(cache: ChunkCache) =
  if cache.lruQueue.len > 0:
    let oldestId = cache.lruQueue.popLast()
    if oldestId in cache.chunks:
      let chunk = cache.chunks[oldestId]
      if chunk.dirty:
        # TODO: Write dirty chunk back to file
        discard
      cache.chunks.del(oldestId)

proc ensureCacheSpace(cache: ChunkCache) =
  while cache.chunks.len >= cache.maxChunks:
    cache.evictLRUChunk()

proc chunkIdForPosition(buffer: LazyTextBuffer, pos: int64): ChunkId =
  int(pos div buffer.chunkSize)

proc loadChunk*(buffer: LazyTextBuffer, chunkId: ChunkId): FileChunk =
  # Check if already in cache
  if chunkId in buffer.chunkCache.chunks:
    let chunk = buffer.chunkCache.chunks[chunkId]
    chunk.lastAccess = now()
    buffer.chunkCache.updateLRU(chunkId)
    return chunk
  
  # Ensure cache has space
  buffer.chunkCache.ensureCacheSpace()
  
  # Load chunk from file
  let startPos = int64(chunkId * buffer.chunkSize)
  let endPos = min(startPos + buffer.chunkSize, buffer.fileSize)
  
  buffer.fileStream.setPosition(startPos)
  let data = buffer.fileStream.readStr(int(endPos - startPos))
  
  # Split into lines and build line offsets
  var lines: seq[string] = @[]
  var lineOffsets: seq[int] = @[]
  var currentLine = ""
  var byteOffset = 0
  
  for i, ch in data:
    if ch == '\n':
      lines.add(currentLine)
      lineOffsets.add(byteOffset)
      currentLine = ""
      byteOffset = i + 1
    elif ch != '\r':  # Skip CR in CRLF
      currentLine.add(ch)
  
  # Add final line if it doesn't end with newline
  if currentLine.len > 0 or data.len == 0:
    lines.add(currentLine)
    lineOffsets.add(byteOffset)
  
  # Create chunk
  result = FileChunk(
    id: chunkId,
    startPos: startPos,
    endPos: endPos,
    data: data,
    lines: lines,
    lineOffsets: lineOffsets,
    lastAccess: now(),
    dirty: false,
    loading: false
  )
  
  # Add to cache
  buffer.chunkCache.chunks[chunkId] = result
  buffer.chunkCache.updateLRU(chunkId)

proc buildLineIndex*(buffer: LazyTextBuffer) =
  if buffer.indexBuilt:
    return
  
  buffer.lineIndex = @[]
  buffer.totalLines = 0
  
  # Build index by loading chunks sequentially and counting lines
  for chunkId in 0..<buffer.totalChunks:
    let chunk = buffer.loadChunk(chunkId)
    for lineInChunk in 0..<chunk.lines.len:
      buffer.lineIndex.add((chunkId: chunkId, lineInChunk: lineInChunk))
      inc buffer.totalLines
  
  buffer.indexBuilt = true

proc lineCount*(buffer: LazyTextBuffer): int =
  if not buffer.indexBuilt:
    buffer.buildLineIndex()
  buffer.totalLines

proc getLine*(buffer: LazyTextBuffer, lineIndex: int): string =
  if not buffer.indexBuilt:
    buffer.buildLineIndex()
  
  if lineIndex < 0 or lineIndex >= buffer.totalLines:
    return ""
  
  let lineInfo = buffer.lineIndex[lineIndex]
  let chunk = buffer.loadChunk(lineInfo.chunkId)
  
  if lineInfo.lineInChunk < chunk.lines.len:
    chunk.lines[lineInfo.lineInChunk]
  else:
    ""

proc getLineLength*(buffer: LazyTextBuffer, lineIndex: int): int =
  buffer.getLine(lineIndex).len

proc setViewport*(buffer: LazyTextBuffer, startLine, endLine: int) =
  buffer.viewportStart = startLine
  buffer.viewportEnd = endLine
  
  # Prefetch chunks for viewport
  if buffer.indexBuilt and startLine < buffer.totalLines:
    let startChunk = if startLine >= 0 and startLine < buffer.lineIndex.len:
                      buffer.lineIndex[startLine].chunkId
                     else: 0
    let endChunk = if endLine >= 0 and endLine < buffer.lineIndex.len:
                    buffer.lineIndex[min(endLine, buffer.lineIndex.len - 1)].chunkId
                   else: buffer.totalChunks - 1
    
    # Queue prefetch requests
    for chunkId in max(0, startChunk - PREFETCH_CHUNKS)..min(buffer.totalChunks - 1, endChunk + PREFETCH_CHUNKS):
      if chunkId notin buffer.chunkCache.chunks and chunkId notin buffer.pendingLoads:
        buffer.pendingLoads.addLast(chunkId)

proc processPendingLoads*(buffer: LazyTextBuffer, maxLoads: int = 2) =
  var loaded = 0
  while buffer.pendingLoads.len > 0 and loaded < maxLoads:
    let chunkId = buffer.pendingLoads.popFirst()
    if chunkId notin buffer.chunkCache.chunks:
      discard buffer.loadChunk(chunkId)
      inc loaded

proc insertText*(buffer: LazyTextBuffer, pos: CursorPosition, text: string) =
  # For large file lazy loading, editing is complex
  # This is a simplified implementation that marks chunks as dirty
  if not buffer.indexBuilt:
    buffer.buildLineIndex()
  
  if pos.line >= 0 and pos.line < buffer.totalLines:
    let lineInfo = buffer.lineIndex[pos.line]
    let chunk = buffer.loadChunk(lineInfo.chunkId)
    
    if lineInfo.lineInChunk < chunk.lines.len:
      let line = chunk.lines[lineInfo.lineInChunk]
      let col = min(pos.column, line.len)
      chunk.lines[lineInfo.lineInChunk] = line[0..<col] & text & line[col..^1]
      chunk.dirty = true
      buffer.modified = true

proc deleteChar*(buffer: LazyTextBuffer, pos: CursorPosition) =
  if not buffer.indexBuilt:
    buffer.buildLineIndex()
  
  if pos.line >= 0 and pos.line < buffer.totalLines:
    let lineInfo = buffer.lineIndex[pos.line]
    let chunk = buffer.loadChunk(lineInfo.chunkId)
    
    if lineInfo.lineInChunk < chunk.lines.len:
      let line = chunk.lines[lineInfo.lineInChunk]
      
      # Use Unicode utilities for safe character deletion
      if pos.column >= 0 and pos.column < line.charLen():
        let newLine = line.deleteCharAt(pos.column)
        chunk.lines[lineInfo.lineInChunk] = newLine
        chunk.dirty = true
        buffer.modified = true

proc save*(buffer: LazyTextBuffer): bool =
  # Save all dirty chunks back to file
  try:
    let tempPath = buffer.filePath & ".tmp"
    let outStream = newFileStream(tempPath, fmWrite)
    
    # Write all chunks in order
    for chunkId in 0..<buffer.totalChunks:
      if chunkId in buffer.chunkCache.chunks:
        let chunk = buffer.chunkCache.chunks[chunkId]
        if chunk.dirty:
          # Reconstruct chunk data from modified lines
          var newData = ""
          for i, line in chunk.lines:
            newData.add(line)
            if i < chunk.lines.len - 1:
              newData.add('\n')
          outStream.write(newData)
          chunk.dirty = false
        else:
          outStream.write(chunk.data)
      else:
        # Load and write unchanged chunk
        let chunk = buffer.loadChunk(chunkId)
        outStream.write(chunk.data)
    
    outStream.close()
    
    # Replace original file
    moveFile(tempPath, buffer.filePath)
    buffer.modified = false
    
    return true
  except IOError:
    return false

proc close*(buffer: LazyTextBuffer) =
  if buffer.fileStream != nil:
    buffer.fileStream.close()
    buffer.fileStream = nil

proc estimateMemoryUsage*(buffer: LazyTextBuffer): int =
  result = sizeof(LazyTextBuffer[])
  result += buffer.lineIndex.len * sizeof((ChunkId, int))
  
  for chunk in buffer.chunkCache.chunks.values:
    result += sizeof(FileChunk[])
    result += chunk.data.len
    result += chunk.lines.len * 32  # Estimate for string overhead