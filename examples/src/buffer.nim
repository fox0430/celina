## Efficient Text Buffer with automatic backend selection
## 
## This module provides a high-level TextBuffer interface that automatically
## chooses the most appropriate backend (GapBuffer, Rope, or Hybrid) based on
## file size and usage patterns for optimal memory efficiency.

import std/[options, strutils]
import types, efficientbuffer

# Re-export efficient buffer types
export efficientbuffer.EfficientTextBuffer
export efficientbuffer.BufferBackend

# Type alias for backward compatibility
type TextBuffer* = EfficientTextBuffer

# Constructor function for backward compatibility
proc newTextBuffer*(filePath: Option[string] = none(string)): TextBuffer =
  newEfficientTextBuffer("", filePath)

# Wrapper functions to maintain the original interface
proc lineCount*(buffer: TextBuffer): int =
  efficientbuffer.lineCount(buffer)

proc getLine*(buffer: TextBuffer, lineIndex: int): string =
  efficientbuffer.getLine(buffer, lineIndex)

proc getLineLength*(buffer: TextBuffer, lineIndex: int): int =
  efficientbuffer.getLineLength(buffer, lineIndex)

proc insertChar*(buffer: TextBuffer, pos: CursorPosition, ch: char) =
  efficientbuffer.insertText(buffer, pos, $ch)

proc insertText*(buffer: TextBuffer, pos: CursorPosition, text: string) =
  efficientbuffer.insertText(buffer, pos, text)

proc deleteChar*(buffer: TextBuffer, pos: CursorPosition) =
  efficientbuffer.deleteChar(buffer, pos)

proc deleteLine*(buffer: TextBuffer, lineIndex: int) =
  efficientbuffer.deleteLine(buffer, lineIndex)

proc insertLine*(buffer: TextBuffer, lineIndex: int, content: string = "") =
  efficientbuffer.insertLine(buffer, lineIndex, content)

proc splitLine*(buffer: TextBuffer, pos: CursorPosition) =
  efficientbuffer.splitLine(buffer, pos)

proc getText*(buffer: TextBuffer): string =
  efficientbuffer.getText(buffer)

proc setText*(buffer: TextBuffer, text: string) =
  # Replace entire content by recreating buffer
  let newBackend = if text.len > 1024 * 1024: RopeBackend 
                   else: GapBufferBackend
  
  let newBuffer = newEfficientTextBuffer(text, buffer.filePath)
  buffer[] = newBuffer[]
  buffer.modified = true

proc save*(buffer: TextBuffer, path: string): bool =
  efficientbuffer.save(buffer, path)

proc load*(buffer: TextBuffer, path: string): bool =
  efficientbuffer.load(buffer, path)

# Additional performance monitoring functions
proc getBackendInfo*(buffer: TextBuffer): string =
  let stats = buffer.getPerformanceStats()
  "Backend: " & stats.backend & 
  ", Memory: " & $(stats.memoryUsage div 1024) & " KB" &
  ", Length: " & $stats.length

proc estimateMemoryUsage*(buffer: TextBuffer): int =
  efficientbuffer.estimateMemoryUsage(buffer)

# Legacy Piece Table types for compatibility (but not used)
type
  PieceActionKind* = enum
    PieceInsert
    PieceDelete  
    PieceReplace

  PieceTableAction* = object
    case kind*: PieceActionKind
    of PieceInsert:
      insertIndex*: int
      insertedPieces*: seq[string]  # Simplified
    of PieceDelete:
      deleteIndex*: int
      deletedPieces*: seq[string]   # Simplified
    of PieceReplace:
      replaceIndex*: int
      replacedPieces*: seq[string]  # Simplified
      newPieces*: seq[string]       # Simplified

  PieceTable* = ref object
    # Legacy structure - not actually used but kept for compatibility
    original*: string
    added*: string

# Legacy functions that do nothing but maintain compatibility
proc newPieceTable*(content: string = ""): PieceTable =
  PieceTable(original: content, added: "")

proc getText*(pt: PieceTable): string =
  pt.original

proc insert*(pt: PieceTable, offset: int, text: string) =
  discard

proc delete*(pt: PieceTable, offset: int, length: int) =
  discard

proc undo*(pt: PieceTable): bool =
  false

proc redo*(pt: PieceTable): bool =
  false