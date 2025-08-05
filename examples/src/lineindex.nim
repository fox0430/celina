## Line Index for fast line-based operations
##
## Maintains an index of line start positions to enable O(log n) line access
## instead of O(n) scanning. Updates incrementally as text is modified.

import std/[algorithm]

proc lowerBound*[T](a: openArray[T], key: T): int =
  ## Find the first index where key could be inserted to keep array sorted
  var low = 0
  var high = a.len
  while low < high:
    let mid = (low + high) div 2
    if a[mid] < key:
      low = mid + 1
    else:
      high = mid
  low

type
  LineIndex* = ref object
    lineStarts*: seq[int]  # Character positions where each line starts
    totalLength*: int      # Total text length
    dirty*: bool          # Whether index needs rebuilding

proc newLineIndex*(): LineIndex =
  LineIndex(
    lineStarts: @[0],  # Line 0 always starts at position 0
    totalLength: 0,
    dirty: false
  )

proc rebuildFrom*(index: LineIndex, text: string) =
  ## Rebuild index from complete text
  index.lineStarts = @[0]
  index.totalLength = text.len
  
  for i, ch in text:
    if ch == '\n':
      index.lineStarts.add(i + 1)
  
  index.dirty = false

proc newLineIndex*(text: string): LineIndex =
  result = newLineIndex()
  rebuildFrom(result, text)

proc clear*(index: LineIndex) =
  index.lineStarts = @[0]
  index.totalLength = 0
  index.dirty = false

proc lineCount*(index: LineIndex): int =
  ## Get number of lines
  index.lineStarts.len


proc getLineStart*(index: LineIndex, lineNum: int): int =
  ## Get character position where line starts (0-based)
  if lineNum < 0:
    return 0
  elif lineNum >= index.lineStarts.len:
    return index.totalLength
  else:
    return index.lineStarts[lineNum]

proc getLineEnd*(index: LineIndex, lineNum: int): int =
  ## Get character position where line ends (exclusive, points to newline or EOF)
  if lineNum < 0:
    return 0
  elif lineNum + 1 >= index.lineStarts.len:
    return index.totalLength
  else:
    return index.lineStarts[lineNum + 1] - 1  # -1 to exclude the newline

proc getLineLength*(index: LineIndex, lineNum: int): int =
  ## Get length of line (excluding newline)
  let start = index.getLineStart(lineNum)
  let endPos = index.getLineEnd(lineNum)
  max(0, endPos - start)

proc findLineAt*(index: LineIndex, position: int): int =
  ## Find which line contains the given character position
  if position < 0:
    return 0
  elif position >= index.totalLength:
    return max(0, index.lineStarts.len - 1)
  
  # Binary search for the line
  let searchResult = index.lineStarts.lowerBound(position + 1)
  max(0, searchResult - 1)

proc insertText*(index: LineIndex, position: int, text: string) =
  ## Update index after text insertion
  if text.len == 0:
    return
  
  let lineNum = index.findLineAt(position)
  let insertLen = text.len
  
  # Count newlines in inserted text
  var newlinePositions: seq[int] = @[]
  for i, ch in text:
    if ch == '\n':
      newlinePositions.add(position + i + 1)
  
  # Update total length
  index.totalLength += insertLen
  
  # Update existing line starts (shift positions after insertion point)
  for i in (lineNum + 1)..<index.lineStarts.len:
    index.lineStarts[i] += insertLen
  
  # Insert new line starts
  if newlinePositions.len > 0:
    let insertPoint = lineNum + 1
    for i, newlinePos in newlinePositions:
      index.lineStarts.insert(newlinePos, insertPoint + i)

proc deleteText*(index: LineIndex, position: int, length: int) =
  ## Update index after text deletion
  if length <= 0:
    return
  
  let startLine = index.findLineAt(position)
  let endLine = index.findLineAt(position + length - 1)
  let deleteLen = length
  
  # Count lines that will be completely removed
  var linesToRemove: seq[int] = @[]
  for lineNum in (startLine + 1)..endLine:
    if index.getLineStart(lineNum) < position + length:
      linesToRemove.add(lineNum)
  
  # Remove deleted lines (in reverse order to maintain indices)
  for i in countdown(linesToRemove.len - 1, 0):
    index.lineStarts.delete(linesToRemove[i])
  
  # Update total length
  index.totalLength -= deleteLen
  
  # Update remaining line starts (shift positions after deletion point)
  let remainingLineStart = startLine + 1
  for i in remainingLineStart..<index.lineStarts.len:
    index.lineStarts[i] -= deleteLen

proc replaceText*(index: LineIndex, position: int, deleteLength: int, insertText: string) =
  ## Update index after text replacement
  index.deleteText(position, deleteLength)
  index.insertText(position, insertText)

proc validate*(index: LineIndex, text: string): bool =
  ## Validate that index is consistent with actual text
  if index.totalLength != text.len:
    return false
  
  var expectedStarts: seq[int] = @[0]
  for i, ch in text:
    if ch == '\n':
      expectedStarts.add(i + 1)
  
  if index.lineStarts.len != expectedStarts.len:
    return false
  
  for i, start in index.lineStarts:
    if i < expectedStarts.len and start != expectedStarts[i]:
      return false
  
  return true

proc getStats*(index: LineIndex): tuple[lines: int, totalLength: int, indexSize: int] =
  ## Get statistics about the index
  (
    lines: index.lineStarts.len,
    totalLength: index.totalLength,
    indexSize: index.lineStarts.len * sizeof(int)
  )

# Advanced operations for large files
type
  ChunkedLineIndex* = ref object
    chunks*: seq[LineIndex]
    chunkStarts*: seq[int]  # Character positions where each chunk starts
    chunkSize*: int         # Target size for each chunk
    totalLength*: int

proc newChunkedLineIndex*(chunkSize: int = 64 * 1024): ChunkedLineIndex =
  ChunkedLineIndex(
    chunks: @[],
    chunkStarts: @[],
    chunkSize: chunkSize,
    totalLength: 0
  )

proc rebuildFromChunked*(index: ChunkedLineIndex, text: string) =
  ## Rebuild chunked index from complete text
  index.chunks = @[]
  index.chunkStarts = @[]
  index.totalLength = text.len
  
  var pos = 0
  while pos < text.len:
    let chunkEnd = min(pos + index.chunkSize, text.len)
    let chunkText = text[pos..<chunkEnd]
    
    let chunkIndex = newLineIndex(chunkText)
    index.chunks.add(chunkIndex)
    index.chunkStarts.add(pos)
    
    pos = chunkEnd

proc findChunkAt*(index: ChunkedLineIndex, position: int): int =
  ## Find which chunk contains the given position
  if position >= index.totalLength:
    return max(0, index.chunks.len - 1)
  
  let searchResult = index.chunkStarts.lowerBound(position + 1)
  max(0, searchResult - 1)

proc getLineAtChunked*(index: ChunkedLineIndex, position: int): int =
  ## Find line number for position using chunked index
  let chunkNum = index.findChunkAt(position)
  if chunkNum >= index.chunks.len:
    return 0
  
  let chunk = index.chunks[chunkNum]
  let chunkStart = index.chunkStarts[chunkNum]
  let relativePos = position - chunkStart
  let lineInChunk = chunk.findLineAt(relativePos)
  
  # Calculate total line number
  var totalLines = 0
  for i in 0..<chunkNum:
    totalLines += index.chunks[i].lineCount() - 1  # -1 because chunks overlap at boundaries
  
  totalLines + lineInChunk

# Memory usage estimation
proc estimateMemoryUsage*(index: LineIndex): int =
  sizeof(LineIndex[]) + index.lineStarts.len * sizeof(int)

proc estimateMemoryUsage*(index: ChunkedLineIndex): int =
  var total = sizeof(ChunkedLineIndex[])
  total += index.chunkStarts.len * sizeof(int)
  for chunk in index.chunks:
    total += chunk.estimateMemoryUsage()
  total