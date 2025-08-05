## Simplified efficient text buffer implementation
##
## This module provides a TextBuffer interface that automatically
## chooses between GapBuffer and Rope based on file size.

import std/[options, strutils, os, unicode]
import types, gapbuffer, rope, lazybuffer, unicode_utils

type
  BufferBackend* = enum
    GapBufferBackend    # Best for small to medium files
    RopeBackend        # Best for large files  
    LazyBufferBackend   # Best for very large files (lazy loading)

  EfficientTextBuffer* = ref object
    backend*: BufferBackend
    filePath*: Option[string]
    modified*: bool
    readOnly*: bool
    lineEnding*: LineEnding
    encoding*: string
    
    # Backend storage
    case backendKind*: BufferBackend
    of GapBufferBackend:
      gapBuffer*: GapBuffer
    of RopeBackend:
      rope*: Rope
    of LazyBufferBackend:
      lazyBuffer*: LazyTextBuffer

const
  ROPE_THRESHOLD = 1024 * 1024         # 1MB - use Rope for larger files
  LAZY_THRESHOLD = 50 * 1024 * 1024    # 50MB - use Lazy for very large files

proc chooseBackend(size: int): BufferBackend =
  if size > LAZY_THRESHOLD:
    LazyBufferBackend
  elif size > ROPE_THRESHOLD:
    RopeBackend
  else:
    GapBufferBackend

proc chooseBackendForFile(filePath: string): BufferBackend =
  if lazybuffer.shouldUseLazyLoading(filePath):
    LazyBufferBackend
  else:
    try:
      let fileInfo = getFileInfo(filePath)
      chooseBackend(int(fileInfo.size))
    except OSError:
      GapBufferBackend

proc newEfficientTextBuffer*(content: string = "", filePath: Option[string] = none(string)): EfficientTextBuffer =
  let backend = chooseBackend(content.len)
  
  case backend
  of GapBufferBackend:
    result = EfficientTextBuffer(
      backendKind: GapBufferBackend,
      backend: backend,
      filePath: filePath,
      modified: false,
      readOnly: false,
      lineEnding: LF,
      encoding: "UTF-8",
      gapBuffer: newGapBuffer(content)
    )
  
  of RopeBackend:
    result = EfficientTextBuffer(
      backendKind: RopeBackend,
      backend: backend,
      filePath: filePath,
      modified: false,
      readOnly: false,
      lineEnding: LF,
      encoding: "UTF-8",
      rope: newRope(content)
    )
  
  of LazyBufferBackend:
    # Lazy buffer needs a file path
    if filePath.isSome:
      result = EfficientTextBuffer(
        backendKind: LazyBufferBackend,
        backend: backend,
        filePath: filePath,
        modified: false,
        readOnly: false,
        lineEnding: LF,
        encoding: "UTF-8",
        lazyBuffer: newLazyTextBuffer(filePath.get())
      )
    else:
      # Fallback to Rope if no file path
      result = EfficientTextBuffer(
        backendKind: RopeBackend,
        backend: RopeBackend,
        filePath: filePath,
        modified: false,
        readOnly: false,
        lineEnding: LF,
        encoding: "UTF-8",
        rope: newRope(content)
      )

# Core text operations
proc getText*(buffer: EfficientTextBuffer): string =
  case buffer.backendKind
  of GapBufferBackend:
    $buffer.gapBuffer
  of RopeBackend:
    $buffer.rope
  of LazyBufferBackend:
    # For lazy buffers, getting full text is expensive - not recommended
    var result = ""
    for i in 0..<buffer.lazyBuffer.lineCount():
      if i > 0:
        result.add('\n')
      result.add(buffer.lazyBuffer.getLine(i))
    result

proc length*(buffer: EfficientTextBuffer): int =
  case buffer.backendKind
  of GapBufferBackend:
    buffer.gapBuffer.len
  of RopeBackend:
    buffer.rope.length
  of LazyBufferBackend:
    # For lazy buffers, length calculation is expensive
    int(buffer.lazyBuffer.fileSize)

proc charAt*(buffer: EfficientTextBuffer, position: int): char =
  case buffer.backendKind
  of GapBufferBackend:
    buffer.gapBuffer.charAt(position)
  of RopeBackend:
    buffer.rope.charAt(position)
  of LazyBufferBackend:
    # For lazy buffers, random character access is not efficient
    # Convert position to line/column and use line-based access
    var currentPos = 0
    for lineIdx in 0..<buffer.lazyBuffer.lineCount():
      let line = buffer.lazyBuffer.getLine(lineIdx)
      if currentPos + line.len > position:
        return line[position - currentPos]
      currentPos += line.len + 1  # +1 for newline
    '\0'

# Line-based helper functions
proc lineToPosition*(buffer: EfficientTextBuffer, pos: CursorPosition): int =
  ## Convert line/column position to character position
  var currentLine = 0
  var lineStart = 0
  
  for i in 0..<buffer.length():
    if currentLine == pos.line:
      return lineStart + pos.column
    if buffer.charAt(i) == '\n':
      inc currentLine
      lineStart = i + 1
  
  if currentLine == pos.line:
    lineStart + pos.column
  else:
    buffer.length()

proc positionToLine*(buffer: EfficientTextBuffer, position: int): CursorPosition =
  ## Convert character position to line/column position
  var currentLine = 0
  var lineStart = 0
  
  for i in 0..<min(position, buffer.length()):
    if buffer.charAt(i) == '\n':
      inc currentLine
      lineStart = i + 1
  
  CursorPosition(line: currentLine, column: position - lineStart)

# Editing operations
proc insertText*(buffer: EfficientTextBuffer, pos: CursorPosition, text: string) =
  if text.len == 0:
    return
  
  case buffer.backendKind
  of GapBufferBackend:
    let position = buffer.lineToPosition(pos)
    buffer.gapBuffer.insert(position, text)
  of RopeBackend:
    let position = buffer.lineToPosition(pos)
    buffer.rope = buffer.rope.insert(position, text)
  of LazyBufferBackend:
    buffer.lazyBuffer.insertText(pos, text)
  
  buffer.modified = true

# Line-based operations  
proc lineCount*(buffer: EfficientTextBuffer): int =
  case buffer.backendKind
  of GapBufferBackend:
    buffer.gapBuffer.lineCount()
  of RopeBackend:
    buffer.rope.lineCount()
  of LazyBufferBackend:
    buffer.lazyBuffer.lineCount()

proc getLine*(buffer: EfficientTextBuffer, lineIndex: int): string =
  case buffer.backendKind
  of GapBufferBackend:
    buffer.gapBuffer.getLine(lineIndex)
  of RopeBackend:
    buffer.rope.getLine(lineIndex)
  of LazyBufferBackend:
    buffer.lazyBuffer.getLine(lineIndex)

proc getLineLength*(buffer: EfficientTextBuffer, lineIndex: int): int =
  let line = buffer.getLine(lineIndex)
  line.len

proc deleteChar*(buffer: EfficientTextBuffer, pos: CursorPosition) =
  # Unicode-aware character deletion
  case buffer.backendKind
  of GapBufferBackend, RopeBackend:
    # For GapBuffer and Rope, use line-based approach to handle Unicode properly
    if pos.line >= 0 and pos.line < buffer.lineCount():
      let line = buffer.getLine(pos.line)
      if pos.column >= 0 and pos.column < line.charLen():
        # Use Unicode utilities for safe character deletion
        let newLine = line.deleteCharAt(pos.column)
        
        # Replace the entire line
        case buffer.backendKind
        of GapBufferBackend:
          # Delete old line and insert new one
          buffer.gapBuffer.deleteLine(pos.line)
          buffer.gapBuffer.insertLine(pos.line, newLine)
        of RopeBackend:
          # For rope, find line positions and replace
          let lineStart = buffer.rope.findLineStart(pos.line)
          let nextLineStart = if pos.line + 1 < buffer.lineCount():
                                buffer.rope.findLineStart(pos.line + 1)
                              else:
                                buffer.rope.length
          let lineLength = nextLineStart - lineStart
          buffer.rope = buffer.rope.delete(lineStart, lineLength)
          buffer.rope = buffer.rope.insert(lineStart, newLine & (if pos.line + 1 < buffer.lineCount(): "\n" else: ""))
        else: discard
  of LazyBufferBackend:
    buffer.lazyBuffer.deleteChar(pos)
  
  buffer.modified = true

proc insertLine*(buffer: EfficientTextBuffer, lineIndex: int, content: string = "") =
  case buffer.backendKind
  of GapBufferBackend:
    buffer.gapBuffer.insertLine(lineIndex, content)
  of RopeBackend:
    let position = buffer.rope.findLineStart(lineIndex)
    buffer.rope = buffer.rope.insert(position, content & "\n")
  of LazyBufferBackend:
    # For lazy buffer, insert at beginning of line
    let pos = CursorPosition(line: lineIndex, column: 0)
    buffer.lazyBuffer.insertText(pos, content & "\n")
  
  buffer.modified = true

proc deleteLine*(buffer: EfficientTextBuffer, lineIndex: int) =
  case buffer.backendKind
  of GapBufferBackend:
    buffer.gapBuffer.deleteLine(lineIndex)
  of RopeBackend:
    let lineStart = buffer.rope.findLineStart(lineIndex)
    let nextLineStart = buffer.rope.findLineStart(lineIndex + 1)
    let deleteLength = if nextLineStart > lineStart: nextLineStart - lineStart else: buffer.rope.length - lineStart
    buffer.rope = buffer.rope.delete(lineStart, deleteLength)
  of LazyBufferBackend:
    # For lazy buffer, delete entire line
    let line = buffer.lazyBuffer.getLine(lineIndex)
    let startPos = CursorPosition(line: lineIndex, column: 0)
    # Delete all characters in the line plus newline
    for i in 0..<(line.len + 1):
      buffer.lazyBuffer.deleteChar(startPos)
  
  buffer.modified = true

proc splitLine*(buffer: EfficientTextBuffer, pos: CursorPosition) =
  buffer.insertText(pos, "\n")

# File operations  
proc load*(buffer: EfficientTextBuffer, path: string): bool =
  try:
    # Choose appropriate backend based on file size
    let newBackend = chooseBackendForFile(path)
    
    # Reinitialize with new backend if needed
    if buffer.backendKind != newBackend:
      case newBackend
      of LazyBufferBackend:
        # For lazy loading, create new lazy buffer
        let newBuffer = EfficientTextBuffer(
          backendKind: LazyBufferBackend,
          backend: newBackend,
          filePath: some(path),
          modified: false,
          readOnly: false,
          lineEnding: LF,
          encoding: "UTF-8",
          lazyBuffer: newLazyTextBuffer(path)
        )
        buffer[] = newBuffer[]
      else:
        # For other backends, read content first
        let content = readFile(path)
        let newBuffer = newEfficientTextBuffer(content, some(path))
        buffer[] = newBuffer[]
    else:
      case buffer.backendKind
      of GapBufferBackend:
        let content = readFile(path)
        buffer.gapBuffer = newGapBuffer(content)
      of RopeBackend:
        let content = readFile(path)
        buffer.rope = newRope(content)
      of LazyBufferBackend:
        # Close old lazy buffer and create new one
        if buffer.lazyBuffer != nil:
          buffer.lazyBuffer.close()
        buffer.lazyBuffer = newLazyTextBuffer(path)
    
    buffer.filePath = some(path)
    buffer.modified = false
    
    # Detect line ending (only for non-lazy buffers)
    if buffer.backendKind != LazyBufferBackend:
      let content = readFile(path)
      if content.contains("\r\n"):
        buffer.lineEnding = CRLF
      elif content.contains("\r"):
        buffer.lineEnding = CR
      else:
        buffer.lineEnding = LF
    else:
      buffer.lineEnding = LF  # Default for lazy buffers
    
    return true
  except IOError:
    return false

proc save*(buffer: EfficientTextBuffer, path: string): bool =
  try:
    case buffer.backendKind
    of LazyBufferBackend:
      # For lazy buffers, use specialized save method
      if buffer.lazyBuffer.save():
        buffer.modified = false
        buffer.filePath = some(path)
        return true
      else:
        return false
    else:
      # For other buffers, get full content and write
      let content = buffer.getText()
      writeFile(path, content)
      buffer.modified = false
      buffer.filePath = some(path)
      return true
  except IOError:
    return false

# Memory usage monitoring
proc estimateMemoryUsage*(buffer: EfficientTextBuffer): int =
  result = sizeof(EfficientTextBuffer[])
  
  case buffer.backendKind
  of GapBufferBackend:
    result += buffer.gapBuffer.estimateMemoryUsage()
  of RopeBackend:
    result += buffer.rope.estimateMemoryUsage()
  of LazyBufferBackend:
    result += buffer.lazyBuffer.estimateMemoryUsage()

proc getPerformanceStats*(buffer: EfficientTextBuffer): tuple[backend: string, memoryUsage: int, length: int] =
  let backendName = case buffer.backendKind
    of GapBufferBackend: "GapBuffer"
    of RopeBackend: "Rope"
    of LazyBufferBackend: "LazyBuffer"
  
  (
    backend: backendName,
    memoryUsage: buffer.estimateMemoryUsage(),
    length: buffer.length()
  )

# Viewport management for lazy buffers
proc setViewport*(buffer: EfficientTextBuffer, startLine, endLine: int) =
  case buffer.backendKind
  of LazyBufferBackend:
    buffer.lazyBuffer.setViewport(startLine, endLine)
  else:
    discard  # Other backends don't need viewport management

proc processPendingLoads*(buffer: EfficientTextBuffer, maxLoads: int = 2) =
  case buffer.backendKind
  of LazyBufferBackend:
    buffer.lazyBuffer.processPendingLoads(maxLoads)
  else:
    discard  # Other backends don't have pending loads