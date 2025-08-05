import std/[deques, options, strutils]
import types
import buffer

type
  UndoManager* = ref object
    undoStack: Deque[EditOperation]
    redoStack: Deque[EditOperation]
    maxUndoLevels: int
    groupDepth: int
    currentGroup: seq[EditOperation]

  EditOperation* = object
    kind*: EditOperationKind
    position*: CursorPosition
    text*: string
    endPosition*: Option[CursorPosition]

  EditOperationKind* = enum
    OpInsert
    OpDelete
    OpReplace

proc newUndoManager*(maxLevels: int = 100): UndoManager =
  UndoManager(
    undoStack: initDeque[EditOperation](),
    redoStack: initDeque[EditOperation](),
    maxUndoLevels: maxLevels,
    groupDepth: 0,
    currentGroup: @[],
  )

proc beginGroup*(um: UndoManager) =
  inc um.groupDepth

proc endGroup*(um: UndoManager) =
  if um.groupDepth > 0:
    dec um.groupDepth
    if um.groupDepth == 0 and um.currentGroup.len > 0:
      # Merge group operations into a single compound operation
      for op in um.currentGroup:
        um.undoStack.addLast(op)
      um.currentGroup = @[]

proc addOperation*(um: UndoManager, op: EditOperation) =
  if um.groupDepth > 0:
    um.currentGroup.add(op)
  else:
    um.undoStack.addLast(op)
    um.redoStack.clear()

    # Limit undo stack size
    while um.undoStack.len > um.maxUndoLevels:
      discard um.undoStack.popFirst()

proc recordInsert*(um: UndoManager, pos: CursorPosition, text: string) =
  um.addOperation(
    EditOperation(
      kind: OpInsert, position: pos, text: text, endPosition: none(CursorPosition)
    )
  )

proc recordDelete*(
    um: UndoManager,
    pos: CursorPosition,
    text: string,
    endPos: Option[CursorPosition] = none(CursorPosition),
) =
  um.addOperation(
    EditOperation(kind: OpDelete, position: pos, text: text, endPosition: endPos)
  )

proc recordReplace*(
    um: UndoManager, pos: CursorPosition, oldText: string, newText: string
) =
  um.addOperation(
    EditOperation(
      kind: OpReplace,
      position: pos,
      text: oldText & "\0" & newText, # Separator for old and new text
      endPosition: none(CursorPosition),
    )
  )

proc applyUndo*(buffer: buffer.TextBuffer, op: EditOperation): CursorPosition =
  case op.kind
  of OpInsert:
    # Undo insert by deleting
    var deleteCount = op.text.len
    var pos = op.position
    for _ in 0 ..< deleteCount:
      buffer.deleteChar(pos)
    result = op.position
  of OpDelete:
    # Undo delete by inserting
    buffer.insertText(op.position, op.text)
    result = op.position
  of OpReplace:
    let parts = op.text.split('\0')
    if parts.len == 2:
      # Delete new text
      var pos = op.position
      for _ in 0 ..< parts[1].len:
        buffer.deleteChar(pos)
      # Insert old text
      buffer.insertText(op.position, parts[0])
    result = op.position

proc applyRedo*(buffer: buffer.TextBuffer, op: EditOperation): CursorPosition =
  case op.kind
  of OpInsert:
    # Redo insert
    buffer.insertText(op.position, op.text)
    result =
      CursorPosition(line: op.position.line, column: op.position.column + op.text.len)
  of OpDelete:
    # Redo delete
    var pos = op.position
    for _ in 0 ..< op.text.len:
      buffer.deleteChar(pos)
    result = op.position
  of OpReplace:
    let parts = op.text.split('\0')
    if parts.len == 2:
      # Delete old text
      var pos = op.position
      for _ in 0 ..< parts[0].len:
        buffer.deleteChar(pos)
      # Insert new text
      buffer.insertText(op.position, parts[1])
    result = op.position

proc undo*(um: UndoManager, buffer: buffer.TextBuffer): Option[CursorPosition] =
  if um.undoStack.len > 0:
    let op = um.undoStack.popLast()
    um.redoStack.addLast(op)
    result = some(applyUndo(buffer, op))
  else:
    result = none(CursorPosition)

proc redo*(um: UndoManager, buffer: buffer.TextBuffer): Option[CursorPosition] =
  if um.redoStack.len > 0:
    let op = um.redoStack.popLast()
    um.undoStack.addLast(op)
    result = some(applyRedo(buffer, op))
  else:
    result = none(CursorPosition)

proc canUndo*(um: UndoManager): bool =
  um.undoStack.len > 0

proc canRedo*(um: UndoManager): bool =
  um.redoStack.len > 0

proc clear*(um: UndoManager) =
  um.undoStack.clear()
  um.redoStack.clear()
  um.currentGroup = @[]
  um.groupDepth = 0
