import std/[tables, options, deques]
import ../../src/core/events

type
  EditorMode* = enum
    Normal
    Insert
    Visual
    VisualLine
    VisualBlock
    Command
    Search
    Replace

  Motion* = enum
    Left
    Right
    Up
    Down
    WordForward
    WordBackward
    LineStart
    LineEnd
    FileStart
    FileEnd
    PageUp
    PageDown
    HalfPageUp
    HalfPageDown

  TextObject* = enum
    InnerWord
    AroundWord
    InnerParagraph
    AroundParagraph
    InnerQuote
    AroundQuote
    InnerParen
    AroundParen
    InnerBracket
    AroundBracket
    InnerBrace
    AroundBrace

  CommandType* = enum
    Write
    Quit
    WriteQuit
    ForceQuit
    Edit
    CommandSearch
    CommandReplace
    Set
    Help

  EditorCommand* = object
    kind*: CommandType
    args*: seq[string]

  CursorPosition* = object
    line*: int
    column*: int

  Selection* = object
    start*: CursorPosition
    finish*: CursorPosition

  EditorState* = ref object
    mode*: EditorMode
    cursor*: CursorPosition
    selection*: Option[Selection]
    command*: string
    searchPattern*: string
    lastMotion*: Option[Motion]
    repeatCount*: int
    registers*: Table[char, string]
    yankRegister*: char
    undoStack*: Deque[EditorAction]
    redoStack*: Deque[EditorAction]
    marks*: Table[char, CursorPosition]
    macroRecording*: Option[char]
    macroBuffer*: seq[Event]

  EditorActionKind* = enum
    Insert
    Delete
    Replace

  EditorAction* = object
    case kind*: EditorActionKind
    of Insert:
      insertPos*: CursorPosition
      text*: string
    of Delete:
      deleteStart*: CursorPosition
      deleteEnd*: CursorPosition
      deletedText*: string
    of Replace:
      replacePos*: CursorPosition
      oldText*: string
      newText*: string

  TextBuffer* = ref object
    lines*: seq[string]
    filePath*: Option[string]
    modified*: bool
    readOnly*: bool
    lineEnding*: LineEnding
    encoding*: string

  LineEnding* = enum
    LF
    CRLF
    CR

  EditorConfig* = object
    tabSize*: int
    expandTab*: bool
    showLineNumbers*: bool
    showStatusLine*: bool
    relativeLineNumbers*: bool
    cursorLine*: bool
    cursorColumn*: bool
    scrollOffset*: int
    wrapLines*: bool
    syntaxHighlight*: bool
    autoIndent*: bool
    showWhitespace*: bool

  ViewPort* = object
    topLine*: int
    leftColumn*: int
    width*: int
    height*: int

proc defaultEditorConfig*(): EditorConfig =
  EditorConfig(
    tabSize: 4,
    expandTab: true,
    showLineNumbers: true,
    showStatusLine: true,
    relativeLineNumbers: false,
    cursorLine: true,
    cursorColumn: false,
    scrollOffset: 5,
    wrapLines: false,
    syntaxHighlight: true,
    autoIndent: true,
    showWhitespace: false,
  )

proc newTextBuffer*(filePath: Option[string] = none(string)): TextBuffer =
  TextBuffer(
    lines: @[""],
    filePath: filePath,
    modified: false,
    readOnly: false,
    lineEnding: LF,
    encoding: "UTF-8",
  )

proc newEditorState*(): EditorState =
  EditorState(
    mode: Normal,
    cursor: CursorPosition(line: 0, column: 0),
    selection: none(Selection),
    command: "",
    searchPattern: "",
    lastMotion: none(Motion),
    repeatCount: 0,
    registers: initTable[char, string](),
    yankRegister: '"',
    undoStack: initDeque[EditorAction](),
    redoStack: initDeque[EditorAction](),
    marks: initTable[char, CursorPosition](),
    macroRecording: none(char),
    macroBuffer: @[],
  )
