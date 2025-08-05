import std/[options, strutils, tables, unicode]
import ../../src/core/[geometry, colors, buffer as celinabuffer, events]
import ../../src/widgets/base
import types, buffer, efficientbuffer, modes, commands, memmonitor

type EditorWidget* = ref object of Widget
  textBuffer*: buffer.TextBuffer
  state*: EditorState
  config*: EditorConfig
  viewport*: ViewPort
  modeHandlers*: Table[EditorMode, ModeHandler]
  executor*: CommandExecutor
  statusMessage*: string

proc newEditorWidget*(config: EditorConfig = defaultEditorConfig()): EditorWidget =
  let textBuffer = buffer.newTextBuffer()
  let state = newEditorState()
  let viewport = ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24)
  let executor = newCommandExecutor(textBuffer, state, viewport)

  result = EditorWidget(
    textBuffer: textBuffer,
    state: state,
    config: config,
    viewport: viewport,
    modeHandlers: createModeHandlers(),
    executor: executor,
    statusMessage: "",
  )
  
  # Register buffer for memory monitoring
  monitorBuffer(textBuffer)

proc loadFile*(editor: EditorWidget, path: string): bool =
  result = efficientbuffer.load(editor.textBuffer, path)
  if result:
    editor.state.cursor = CursorPosition(line: 0, column: 0)
    editor.viewport.topLine = 0
    editor.viewport.leftColumn = 0

proc renderLineNumbers(
    editor: EditorWidget, buffer: var celinabuffer.Buffer, area: Rect
): int =
  if not editor.config.showLineNumbers:
    return 0

  let lineCount = efficientbuffer.lineCount(editor.textBuffer)
  let maxLineNumWidth = len($lineCount) + 1

  let lineNumStyle =
    Style(fg: ColorValue(kind: Indexed, indexed: Color.BrightBlack), modifiers: {})

  let currentLineStyle = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.Yellow),
    modifiers: {StyleModifier.Bold},
  )

  for y in 0 ..< min(area.height - 1, lineCount - editor.viewport.topLine):
    let lineNum = editor.viewport.topLine + y
    let lineNumStr = align($(lineNum + 1), maxLineNumWidth - 1) & " "

    let style =
      if lineNum == editor.state.cursor.line: currentLineStyle else: lineNumStyle

    buffer.setString(area.x, area.y + y, lineNumStr, style)

  return maxLineNumWidth

proc renderTextContent(
    editor: EditorWidget, buffer: var celinabuffer.Buffer, area: Rect
) =
  let lineCount = efficientbuffer.lineCount(editor.textBuffer)
  let visibleLines = min(area.height, lineCount - editor.viewport.topLine)

  let normalStyle = Style.default()
  let cursorLineStyle = Style(
    bg:
      if editor.config.cursorLine:
        ColorValue(kind: Indexed, indexed: Color.Black)
      else:
        ColorValue(kind: Default)
  )

  for y in 0 ..< visibleLines:
    let lineIndex = editor.viewport.topLine + y
    let line = efficientbuffer.getLine(editor.textBuffer, lineIndex)

    let displayLine =
      if editor.viewport.leftColumn < line.len:
        line[editor.viewport.leftColumn ..^ 1]
      else:
        ""

    let style =
      if lineIndex == editor.state.cursor.line and editor.config.cursorLine:
        cursorLineStyle
      else:
        normalStyle

    for x in 0 ..< area.width:
      if x < displayLine.len:
        buffer[area.x + x, area.y + y] = cell($displayLine[x], style)
      else:
        buffer[area.x + x, area.y + y] = cell(" ", style)

  for y in visibleLines ..< area.height:
    let tildeStyle =
      Style(fg: ColorValue(kind: Indexed, indexed: Color.Blue), modifiers: {})
    buffer.setString(area.x, area.y + y, "~", tildeStyle)

proc renderCursor(
    editor: EditorWidget,
    buffer: var celinabuffer.Buffer,
    area: Rect,
    lineNumOffset: int,
) =
  let cursorScreenY = editor.state.cursor.line - editor.viewport.topLine
  let cursorScreenX =
    editor.state.cursor.column - editor.viewport.leftColumn + lineNumOffset

  if cursorScreenY >= 0 and cursorScreenY < area.height and
      cursorScreenX >= lineNumOffset and cursorScreenX < area.width + lineNumOffset:
    let cursorStyle =
      case editor.state.mode
      of Normal, Command, Search:
        Style(
          bg: ColorValue(kind: Indexed, indexed: Color.White),
          fg: ColorValue(kind: Indexed, indexed: Color.Black),
          modifiers: {},
        )
      of Insert:
        Style(
          bg: ColorValue(kind: Indexed, indexed: Color.Green),
          fg: ColorValue(kind: Indexed, indexed: Color.Black),
          modifiers: {},
        )
      of Visual, VisualLine, VisualBlock:
        Style(
          bg: ColorValue(kind: Indexed, indexed: Color.Blue),
          fg: ColorValue(kind: Indexed, indexed: Color.White),
          modifiers: {},
        )
      of Replace:
        Style(
          bg: ColorValue(kind: Indexed, indexed: Color.Red),
          fg: ColorValue(kind: Indexed, indexed: Color.White),
          modifiers: {},
        )

    let cellAtCursor =
      buffer[area.x + cursorScreenX - lineNumOffset, area.y + cursorScreenY]
    let cursorCell = cell(cellAtCursor.symbol, cursorStyle)
    buffer[area.x + cursorScreenX - lineNumOffset, area.y + cursorScreenY] = cursorCell

proc renderSelection(
    editor: EditorWidget,
    buffer: var celinabuffer.Buffer,
    area: Rect,
    lineNumOffset: int,
) =
  if editor.state.selection.isNone:
    return

  let sel = editor.state.selection.get()
  let selectionStyle = Style(
    bg: ColorValue(kind: Indexed, indexed: Color.Blue),
    fg: ColorValue(kind: Indexed, indexed: Color.White),
    modifiers: {},
  )

  let startLine = min(sel.start.line, sel.finish.line)
  let endLine = max(sel.start.line, sel.finish.line)
  let startCol =
    if sel.start.line < sel.finish.line:
      sel.start.column
    elif sel.start.line > sel.finish.line:
      sel.finish.column
    else:
      min(sel.start.column, sel.finish.column)
  let endCol =
    if sel.start.line > sel.finish.line:
      sel.start.column
    elif sel.start.line < sel.finish.line:
      sel.finish.column
    else:
      max(sel.start.column, sel.finish.column)

  for line in startLine .. endLine:
    let screenY = line - editor.viewport.topLine
    if screenY >= 0 and screenY < area.height:
      let lineText = efficientbuffer.getLine(editor.textBuffer, line)
      let lineStartCol = if line == startLine: startCol else: 0
      let lineEndCol =
        if line == endLine:
          endCol
        else:
          lineText.len - 1

      for col in lineStartCol .. lineEndCol:
        let screenX = col - editor.viewport.leftColumn + lineNumOffset
        if screenX >= lineNumOffset and screenX < area.width + lineNumOffset and
            col < lineText.len:
          let cellAtPos = buffer[area.x + screenX - lineNumOffset, area.y + screenY]
          buffer[area.x + screenX - lineNumOffset, area.y + screenY] =
            cell(cellAtPos.symbol, selectionStyle)

proc renderStatusLine(
    editor: EditorWidget, buffer: var celinabuffer.Buffer, area: Rect
) =
  if not editor.config.showStatusLine:
    return

  let statusY = area.y + area.height - 1

  let modeStr = editor.modeHandlers[editor.state.mode].getName()
  let posStr = $(editor.state.cursor.line + 1) & "," & $(editor.state.cursor.column + 1)
  let fileStr =
    if editor.textBuffer.filePath.isSome:
      editor.textBuffer.filePath.get() & (
        if editor.textBuffer.modified: " [+]" else: ""
      )
    else:
      "[No Name]" & (if editor.textBuffer.modified: " [+]" else: "")

  let leftStatus = " " & modeStr & " | " & fileStr
  let rightStatus = posStr & " "

  let statusStyle = Style(
    bg: ColorValue(kind: Indexed, indexed: Color.BrightBlack),
    fg: ColorValue(kind: Indexed, indexed: Color.White),
    modifiers: {},
  )

  for x in 0 ..< area.width:
    buffer[area.x + x, statusY] = cell(" ", statusStyle)

  buffer.setString(area.x, statusY, leftStatus, statusStyle)
  buffer.setString(
    area.x + area.width - rightStatus.len, statusY, rightStatus, statusStyle
  )

  if editor.state.mode == EditorMode.Command or editor.state.mode == EditorMode.Search:
    let commandY = statusY
    let commandStyle = Style.default()
    for x in 0 ..< area.width:
      buffer[area.x + x, commandY] = cell(" ", commandStyle)
    buffer.setString(area.x, commandY, editor.state.command, commandStyle)

  if editor.statusMessage.len > 0:
    let messageY = statusY
    let messageStyle = Style.default()
    buffer.setString(area.x, messageY, editor.statusMessage, messageStyle)

method render*(editor: EditorWidget, area: Rect, buffer: var celinabuffer.Buffer) =
  editor.viewport.width = area.width
  editor.viewport.height =
    if editor.config.showStatusLine:
      area.height - 1
    else:
      area.height

  # Update viewport for lazy loading
  let endLine = editor.viewport.topLine + editor.viewport.height
  efficientbuffer.setViewport(editor.textBuffer, editor.viewport.topLine, endLine)
  
  # Process any pending loads for lazy buffers
  efficientbuffer.processPendingLoads(editor.textBuffer)

  let lineNumOffset = editor.renderLineNumbers(buffer, area)

  let textArea = Rect(
    x: area.x + lineNumOffset,
    y: area.y,
    width: area.width - lineNumOffset,
    height:
      if editor.config.showStatusLine:
        area.height - 1
      else:
        area.height,
  )

  editor.renderTextContent(buffer, textArea)
  editor.renderSelection(buffer, textArea, lineNumOffset)
  editor.renderCursor(buffer, textArea, lineNumOffset)
  editor.renderStatusLine(buffer, area)

method handleEvent*(editor: EditorWidget, event: Event): bool =
  if event.kind != EventKind.Key:
    return false

  let key = event.key

  if editor.state.mode in editor.modeHandlers:
    let handler = editor.modeHandlers[editor.state.mode]
    let transition = handler.handleKey(editor.state, key)

    if transition.handled:
      if transition.newMode.isSome:
        let oldMode = editor.state.mode
        let newMode = transition.newMode.get()

        if oldMode in editor.modeHandlers:
          editor.modeHandlers[oldMode].exit(editor.state)

        editor.state.mode = newMode

        if newMode in editor.modeHandlers:
          editor.modeHandlers[newMode].enter(editor.state)

      editor.executor.processCommand(editor.state.command)

      return true

  return false

method getMinSize*(editor: EditorWidget): Size =
  Size(width: 20, height: 5)

proc getMaxSize*(editor: EditorWidget): Size =
  Size(width: int.high, height: int.high)
