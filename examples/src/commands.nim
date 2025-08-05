import std/[options, strutils, tables, unicode]
import types, buffer, undo

type CommandExecutor* = ref object
  buffer*: buffer.TextBuffer
  state*: EditorState
  viewport*: ViewPort
  undoManager*: UndoManager

proc newCommandExecutor*(
    buffer: buffer.TextBuffer, state: EditorState, viewport: ViewPort
): CommandExecutor =
  CommandExecutor(
    buffer: buffer, state: state, viewport: viewport, undoManager: newUndoManager()
  )

proc clampCursor*(exec: CommandExecutor) =
  let lineCount = exec.buffer.lineCount()
  if exec.state.cursor.line >= lineCount:
    exec.state.cursor.line = max(0, lineCount - 1)
  elif exec.state.cursor.line < 0:
    exec.state.cursor.line = 0

  let lineLength = exec.buffer.getLineLength(exec.state.cursor.line)
  if exec.state.cursor.column >= lineLength:
    exec.state.cursor.column = max(0, lineLength - 1)
  elif exec.state.cursor.column < 0:
    exec.state.cursor.column = 0

proc updateViewport*(exec: CommandExecutor) =
  let scrollOffset = 5

  if exec.state.cursor.line < exec.viewport.topLine + scrollOffset:
    exec.viewport.topLine = max(0, exec.state.cursor.line - scrollOffset)
  elif exec.state.cursor.line >=
      exec.viewport.topLine + exec.viewport.height - scrollOffset:
    exec.viewport.topLine =
      max(0, exec.state.cursor.line - exec.viewport.height + scrollOffset + 1)

  if exec.state.cursor.column < exec.viewport.leftColumn:
    exec.viewport.leftColumn = exec.state.cursor.column
  elif exec.state.cursor.column >= exec.viewport.leftColumn + exec.viewport.width:
    exec.viewport.leftColumn = exec.state.cursor.column - exec.viewport.width + 1

proc executeMotion*(exec: CommandExecutor, motion: Motion, count: int = 1) =
  let repeatCount = if count == 0: 1 else: count

  case motion
  of Motion.Left:
    let line = exec.buffer.getLine(exec.state.cursor.line)
    var newCol = exec.state.cursor.column
    for _ in 0 ..< repeatCount:
      if newCol > 0:
        # Find the start of the previous character
        newCol -= 1
        while newCol > 0 and ord(line[newCol]) >= 0x80 and ord(line[newCol]) < 0xC0:
          newCol -= 1
      else:
        break
    exec.state.cursor.column = max(0, newCol)
  of Motion.Right:
    let line = exec.buffer.getLine(exec.state.cursor.line)
    var newCol = exec.state.cursor.column
    for _ in 0 ..< repeatCount:
      if newCol < line.len:
        let rune = line.runeAt(newCol)
        newCol += rune.size
      else:
        break
    exec.state.cursor.column = min(line.len - 1, newCol)
  of Motion.Up:
    exec.state.cursor.line = max(0, exec.state.cursor.line - repeatCount)
  of Motion.Down:
    let lineCount = exec.buffer.lineCount()
    exec.state.cursor.line = min(lineCount - 1, exec.state.cursor.line + repeatCount)
  of Motion.LineStart:
    exec.state.cursor.column = 0
  of Motion.LineEnd:
    let lineLength = exec.buffer.getLineLength(exec.state.cursor.line)
    exec.state.cursor.column = max(0, lineLength - 1)
  of Motion.WordForward:
    for _ in 0 ..< repeatCount:
      let line = exec.buffer.getLine(exec.state.cursor.line)
      var col = exec.state.cursor.column

      while col < line.len and line[col].isAlphaNumeric():
        col += 1
      while col < line.len and not line[col].isAlphaNumeric():
        col += 1

      if col >= line.len and exec.state.cursor.line < exec.buffer.lineCount() - 1:
        exec.state.cursor.line += 1
        exec.state.cursor.column = 0
      else:
        exec.state.cursor.column = min(col, line.len - 1)
  of Motion.WordBackward:
    for _ in 0 ..< repeatCount:
      let line = exec.buffer.getLine(exec.state.cursor.line)
      var col = exec.state.cursor.column

      if col > 0:
        col -= 1
        while col > 0 and not line[col].isAlphaNumeric():
          col -= 1
        while col > 0 and line[col - 1].isAlphaNumeric():
          col -= 1
        exec.state.cursor.column = col
      elif exec.state.cursor.line > 0:
        exec.state.cursor.line -= 1
        let prevLineLength = exec.buffer.getLineLength(exec.state.cursor.line)
        exec.state.cursor.column = max(0, prevLineLength - 1)
  of Motion.FileStart:
    exec.state.cursor.line = 0
    exec.state.cursor.column = 0
  of Motion.FileEnd:
    exec.state.cursor.line = max(0, exec.buffer.lineCount() - 1)
    exec.state.cursor.column = 0
  of Motion.PageDown:
    let pageSize = exec.viewport.height - 2
    exec.state.cursor.line =
      min(exec.buffer.lineCount() - 1, exec.state.cursor.line + pageSize)
    exec.viewport.topLine = min(
      exec.buffer.lineCount() - exec.viewport.height, exec.viewport.topLine + pageSize
    )
  of Motion.PageUp:
    let pageSize = exec.viewport.height - 2
    exec.state.cursor.line = max(0, exec.state.cursor.line - pageSize)
    exec.viewport.topLine = max(0, exec.viewport.topLine - pageSize)
  of Motion.HalfPageDown:
    let halfPageSize = exec.viewport.height div 2
    exec.state.cursor.line =
      min(exec.buffer.lineCount() - 1, exec.state.cursor.line + halfPageSize)
    exec.viewport.topLine = min(
      exec.buffer.lineCount() - exec.viewport.height,
      exec.viewport.topLine + halfPageSize,
    )
  of Motion.HalfPageUp:
    let halfPageSize = exec.viewport.height div 2
    exec.state.cursor.line = max(0, exec.state.cursor.line - halfPageSize)
    exec.viewport.topLine = max(0, exec.viewport.topLine - halfPageSize)

  exec.clampCursor()
  exec.updateViewport()

proc executeInsert*(exec: CommandExecutor, text: string) =
  if text == "newline":
    exec.undoManager.recordInsert(exec.state.cursor, "\n")
    exec.buffer.splitLine(exec.state.cursor)
    exec.state.cursor.line += 1
    exec.state.cursor.column = 0
  elif text == "tab":
    let tabText = "    "
    exec.undoManager.recordInsert(exec.state.cursor, tabText)
    exec.buffer.insertText(exec.state.cursor, tabText)
    exec.state.cursor.column += 4
  else:
    exec.undoManager.recordInsert(exec.state.cursor, text)
    exec.buffer.insertText(exec.state.cursor, text)
    exec.state.cursor.column += text.runeLen

  exec.updateViewport()

proc executeDelete*(exec: CommandExecutor) =
  if exec.state.selection.isSome:
    let sel = exec.state.selection.get()
    let startLine = min(sel.start.line, sel.finish.line)
    let endLine = max(sel.start.line, sel.finish.line)
    let startCol =
      if sel.start.line < sel.finish.line:
        sel.start.column
      else:
        min(sel.start.column, sel.finish.column)
    let endCol =
      if sel.start.line < sel.finish.line:
        sel.finish.column
      else:
        max(sel.start.column, sel.finish.column)

    var yankedText = ""
    for line in startLine .. endLine:
      if line == startLine and line == endLine:
        let lineText = exec.buffer.getLine(line)
        yankedText &= lineText[startCol .. endCol]
      elif line == startLine:
        let lineText = exec.buffer.getLine(line)
        yankedText &= lineText[startCol ..^ 1] & "\n"
      elif line == endLine:
        let lineText = exec.buffer.getLine(line)
        yankedText &= lineText[0 .. endCol]
      else:
        yankedText &= exec.buffer.getLine(line) & "\n"

    exec.state.registers[exec.state.yankRegister] = yankedText

    for line in countdown(endLine, startLine):
      exec.buffer.deleteLine(line)

    exec.state.cursor.line = startLine
    exec.state.cursor.column = 0
    exec.state.selection = none(Selection)
  else:
    exec.buffer.deleteChar(exec.state.cursor)

  exec.clampCursor()
  exec.updateViewport()

proc executeDeleteLine*(exec: CommandExecutor, count: int = 1) =
  let repeatCount = if count == 0: 1 else: count
  let startLine = exec.state.cursor.line
  let endLine = min(startLine + repeatCount - 1, exec.buffer.lineCount() - 1)

  # Yank lines
  var yankedText = ""
  for line in startLine .. endLine:
    yankedText &= exec.buffer.getLine(line) & "\n"
  exec.state.registers[exec.state.yankRegister] = yankedText

  # Record undo
  exec.undoManager.recordDelete(
    CursorPosition(line: startLine, column: 0),
    yankedText,
    some(CursorPosition(line: endLine, column: exec.buffer.getLineLength(endLine))),
  )

  # Delete lines
  for _ in 0 ..< repeatCount:
    if exec.state.cursor.line < exec.buffer.lineCount():
      exec.buffer.deleteLine(exec.state.cursor.line)

  exec.clampCursor()
  exec.updateViewport()

proc executeYank*(exec: CommandExecutor) =
  if exec.state.selection.isSome:
    let sel = exec.state.selection.get()
    let startLine = min(sel.start.line, sel.finish.line)
    let endLine = max(sel.start.line, sel.finish.line)
    let startCol =
      if sel.start.line < sel.finish.line:
        sel.start.column
      else:
        min(sel.start.column, sel.finish.column)
    let endCol =
      if sel.start.line < sel.finish.line:
        sel.finish.column
      else:
        max(sel.start.column, sel.finish.column)

    var yankedText = ""
    for line in startLine .. endLine:
      if line == startLine and line == endLine:
        let lineText = exec.buffer.getLine(line)
        yankedText &= lineText[startCol .. endCol]
      elif line == startLine:
        let lineText = exec.buffer.getLine(line)
        yankedText &= lineText[startCol ..^ 1] & "\n"
      elif line == endLine:
        let lineText = exec.buffer.getLine(line)
        yankedText &= lineText[0 .. endCol]
      else:
        yankedText &= exec.buffer.getLine(line) & "\n"

    exec.state.registers[exec.state.yankRegister] = yankedText
    exec.state.selection = none(Selection)
  else:
    let yankedLine = exec.buffer.getLine(exec.state.cursor.line) & "\n"
    exec.state.registers[exec.state.yankRegister] = yankedLine

proc executePaste*(exec: CommandExecutor, after: bool = true) =
  if exec.state.yankRegister in exec.state.registers:
    let text = exec.state.registers[exec.state.yankRegister]

    if text.endsWith("\n"):
      if after:
        exec.buffer.insertLine(exec.state.cursor.line + 1, text[0 ..^ 2])
        exec.state.cursor.line += 1
      else:
        exec.buffer.insertLine(exec.state.cursor.line, text[0 ..^ 2])
      exec.state.cursor.column = 0
    else:
      if after and exec.buffer.getLineLength(exec.state.cursor.line) > 0:
        exec.state.cursor.column += 1
      exec.buffer.insertText(exec.state.cursor, text)
      if not after:
        exec.state.cursor.column += text.runeLen - 1

    exec.clampCursor()
    exec.updateViewport()

proc executeCommand*(
    exec: CommandExecutor, cmdStr: string
): tuple[success: bool, message: string] =
  let parts = cmdStr.strip().split(" ")
  if parts.len == 0:
    return (false, "")

  let cmd = parts[0]
  case cmd
  of "w", "write":
    if exec.buffer.filePath.isSome:
      if exec.buffer.save(exec.buffer.filePath.get()):
        return (true, "Written " & exec.buffer.filePath.get())
      else:
        return (false, "Error writing file")
    else:
      if parts.len > 1:
        let path = parts[1 ..^ 1].join(" ")
        if exec.buffer.save(path):
          return (true, "Written " & path)
        else:
          return (false, "Error writing file")
      else:
        return (false, "No file name")
  of "q", "quit":
    if exec.buffer.modified:
      return (false, "No write since last change (add ! to override)")
    else:
      return (true, "quit")
  of "q!", "quit!":
    return (true, "quit")
  of "wq", "x":
    if exec.buffer.filePath.isSome:
      if exec.buffer.save(exec.buffer.filePath.get()):
        return (true, "quit")
      else:
        return (false, "Error writing file")
    else:
      return (false, "No file name")
  of "e", "edit":
    if parts.len > 1:
      let path = parts[1 ..^ 1].join(" ")
      if exec.buffer.load(path):
        exec.state.cursor = CursorPosition(line: 0, column: 0)
        exec.viewport.topLine = 0
        exec.viewport.leftColumn = 0
        return (true, "Loaded " & path)
      else:
        return (false, "Error loading file")
    else:
      return (false, "Argument required")
  else:
    return (false, "Not an editor command: " & cmd)

proc processCommand*(exec: CommandExecutor, command: string) =
  if command.startsWith("insert:"):
    let text = command[7 ..^ 1]
    exec.executeInsert(text)
  elif command == "backspace":
    if exec.state.cursor.column > 0:
      exec.state.cursor.column -= 1
      exec.buffer.deleteChar(exec.state.cursor)
    elif exec.state.cursor.line > 0:
      exec.state.cursor.line -= 1
      let lineLength = exec.buffer.getLineLength(exec.state.cursor.line)
      exec.state.cursor.column = lineLength
      exec.buffer.deleteChar(exec.state.cursor)
    exec.updateViewport()
  elif command == "x":
    exec.executeDelete()
  elif command == "dd":
    exec.executeDeleteLine(exec.state.repeatCount)
  elif command == "yy":
    exec.executeYank()
  elif command == "p":
    exec.executePaste(after = true)
  elif command == "P":
    exec.executePaste(after = false)
  elif command == "u":
    let newPos = exec.undoManager.undo(exec.buffer)
    if newPos.isSome:
      exec.state.cursor = newPos.get()
      exec.clampCursor()
      exec.updateViewport()
  elif command == "redo":
    let newPos = exec.undoManager.redo(exec.buffer)
    if newPos.isSome:
      exec.state.cursor = newPos.get()
      exec.clampCursor()
      exec.updateViewport()
  elif command == "o":
    exec.buffer.insertLine(exec.state.cursor.line + 1, "")
    exec.state.cursor.line += 1
    exec.state.cursor.column = 0
    exec.updateViewport()
  elif command == "O":
    exec.buffer.insertLine(exec.state.cursor.line, "")
    exec.state.cursor.column = 0
    exec.updateViewport()
  elif command == "^":
    exec.executeMotion(Motion.LineStart)
    while exec.state.cursor.column < exec.buffer.getLineLength(exec.state.cursor.line) and
        exec.buffer.getLine(exec.state.cursor.line)[exec.state.cursor.column] == ' ':
      exec.state.cursor.column += 1
  elif command == "$":
    exec.executeMotion(Motion.LineEnd)
  elif command == "l" and exec.state.mode == EditorMode.Insert:
    exec.executeMotion(Motion.Right)
  elif command.startsWith("execute:"):
    let cmdStr = command[8 ..^ 1]
    let (_, message) = exec.executeCommand(cmdStr)
    if message == "quit":
      quit(0)
  elif exec.state.lastMotion.isSome:
    exec.executeMotion(exec.state.lastMotion.get(), exec.state.repeatCount)
    exec.state.repeatCount = 0
    exec.state.lastMotion = none(Motion)
