import std/[options, tables]
import ../../src/core/events
import types

type
  ModeHandler* = ref object
    handleKey*: proc(state: EditorState, key: KeyEvent): ModeTransition
    enter*: proc(state: EditorState)
    exit*: proc(state: EditorState)
    getName*: proc(): string

  ModeTransition* = object
    newMode*: Option[EditorMode]
    handled*: bool

proc transition*(
    handled: bool, newMode: Option[EditorMode] = none(EditorMode)
): ModeTransition =
  ModeTransition(handled: handled, newMode: newMode)

proc createNormalMode*(): ModeHandler =
  result = ModeHandler()

  result.handleKey = proc(state: EditorState, key: KeyEvent): ModeTransition =
    case key.code
    of KeyCode.Char:
      case key.char
      of 'i':
        return transition(true, some(EditorMode.Insert))
      of 'I':
        state.command = "^"
        return transition(true, some(EditorMode.Insert))
      of 'a':
        state.command = "l"
        return transition(true, some(EditorMode.Insert))
      of 'A':
        state.command = "$"
        return transition(true, some(EditorMode.Insert))
      of 'o':
        state.command = "o"
        return transition(true, some(EditorMode.Insert))
      of 'O':
        state.command = "O"
        return transition(true, some(EditorMode.Insert))
      of 'v':
        return transition(true, some(EditorMode.Visual))
      of 'V':
        return transition(true, some(EditorMode.VisualLine))
      of ':':
        state.command = ":"
        return transition(true, some(EditorMode.Command))
      of '/':
        state.command = "/"
        return transition(true, some(EditorMode.Search))
      of 'h':
        state.lastMotion = some(Motion.Left)
        return transition(true)
      of 'j':
        state.lastMotion = some(Motion.Down)
        return transition(true)
      of 'k':
        state.lastMotion = some(Motion.Up)
        return transition(true)
      of 'l':
        state.lastMotion = some(Motion.Right)
        return transition(true)
      of 'w':
        state.lastMotion = some(Motion.WordForward)
        return transition(true)
      of 'b':
        state.lastMotion = some(Motion.WordBackward)
        return transition(true)
      of '0':
        if state.repeatCount == 0:
          state.lastMotion = some(Motion.LineStart)
          return transition(true)
        else:
          state.repeatCount = state.repeatCount * 10
          return transition(true)
      of '$':
        state.lastMotion = some(Motion.LineEnd)
        return transition(true)
      of 'g':
        if state.command == "g":
          state.lastMotion = some(Motion.FileStart)
          state.command = ""
          return transition(true)
        else:
          state.command = "g"
          return transition(true)
      of 'G':
        state.lastMotion = some(Motion.FileEnd)
        return transition(true)
      of 'x':
        state.command = "x"
        return transition(true)
      of 'd':
        if state.command == "d":
          state.command = "dd"
          return transition(true)
        else:
          state.command = "d"
          return transition(true)
      of 'y':
        if state.command == "y":
          state.command = "yy"
          return transition(true)
        else:
          state.command = "y"
          return transition(true)
      of 'p':
        state.command = "p"
        return transition(true)
      of 'P':
        state.command = "P"
        return transition(true)
      of 'u':
        state.command = "u"
        return transition(true)
      of 'r':
        if KeyModifier.Ctrl in key.modifiers:
          state.command = "redo"
          return transition(true)
        else:
          state.command = "r"
          return transition(true)
      of '1' .. '9':
        state.repeatCount = state.repeatCount * 10 + (ord(key.char) - ord('0'))
        return transition(true)
      else:
        return transition(false)
    of KeyCode.Escape:
      state.command = ""
      state.repeatCount = 0
      return transition(true)
    of KeyCode.Enter:
      state.lastMotion = some(Motion.Down)
      state.cursor.column = 0
      return transition(true)
    else:
      return transition(false)

  result.enter = proc(state: EditorState) =
    state.command = ""
    state.repeatCount = 0

  result.exit = proc(state: EditorState) =
    discard

  result.getName = proc(): string =
    "NORMAL"

proc createInsertMode*(): ModeHandler =
  result = ModeHandler()

  result.handleKey = proc(state: EditorState, key: KeyEvent): ModeTransition =
    case key.code
    of KeyCode.Escape:
      return transition(true, some(EditorMode.Normal))
    of KeyCode.Char:
      state.command = "insert:" & $key.char
      return transition(true)
    of KeyCode.Enter:
      state.command = "insert:newline"
      return transition(true)
    of KeyCode.Backspace:
      state.command = "backspace"
      return transition(true)
    of KeyCode.Tab:
      state.command = "insert:tab"
      return transition(true)
    else:
      return transition(false)

  result.enter = proc(state: EditorState) =
    state.command = ""

  result.exit = proc(state: EditorState) =
    if state.cursor.column > 0:
      state.cursor.column -= 1

  result.getName = proc(): string =
    "INSERT"

proc createCommandMode*(): ModeHandler =
  result = ModeHandler()

  result.handleKey = proc(state: EditorState, key: KeyEvent): ModeTransition =
    case key.code
    of KeyCode.Escape:
      state.command = ""
      return transition(true, some(EditorMode.Normal))
    of KeyCode.Enter:
      let cmd = state.command[1 ..^ 1]
      state.command = "execute:" & cmd
      return transition(true, some(EditorMode.Normal))
    of KeyCode.Char:
      state.command &= $key.char
      return transition(true)
    of KeyCode.Backspace:
      if state.command.len > 1:
        state.command = state.command[0 ..^ 2]
        return transition(true)
      else:
        return transition(true, some(EditorMode.Normal))
    else:
      return transition(false)

  result.enter = proc(state: EditorState) =
    state.command = ":"

  result.exit = proc(state: EditorState) =
    discard

  result.getName = proc(): string =
    "COMMAND"

proc createVisualMode*(): ModeHandler =
  result = ModeHandler()

  result.handleKey = proc(state: EditorState, key: KeyEvent): ModeTransition =
    case key.code
    of KeyCode.Escape:
      state.selection = none(Selection)
      return transition(true, some(EditorMode.Normal))
    of KeyCode.Char:
      case key.char
      of 'h', 'j', 'k', 'l', 'w', 'b', '0', '$':
        let normalHandler = createNormalMode()
        let trans = normalHandler.handleKey(state, key)
        return transition(trans.handled)
      of 'd', 'x':
        state.command = "delete"
        return transition(true, some(EditorMode.Normal))
      of 'y':
        state.command = "yank"
        return transition(true, some(EditorMode.Normal))
      of 'c':
        state.command = "change"
        return transition(true, some(EditorMode.Insert))
      else:
        return transition(false)
    else:
      return transition(false)

  result.enter = proc(state: EditorState) =
    state.selection = some(Selection(start: state.cursor, finish: state.cursor))

  result.exit = proc(state: EditorState) =
    discard

  result.getName = proc(): string =
    "VISUAL"

proc createSearchMode*(): ModeHandler =
  result = ModeHandler()

  result.handleKey = proc(state: EditorState, key: KeyEvent): ModeTransition =
    case key.code
    of KeyCode.Escape:
      state.command = ""
      state.searchPattern = ""
      return transition(true, some(EditorMode.Normal))
    of KeyCode.Enter:
      state.searchPattern = state.command[1 ..^ 1]
      state.command = "search"
      return transition(true, some(EditorMode.Normal))
    of KeyCode.Char:
      state.command &= $key.char
      return transition(true)
    of KeyCode.Backspace:
      if state.command.len > 1:
        state.command = state.command[0 ..^ 2]
        return transition(true)
      else:
        return transition(true, some(EditorMode.Normal))
    else:
      return transition(false)

  result.enter = proc(state: EditorState) =
    state.command = "/"

  result.exit = proc(state: EditorState) =
    discard

  result.getName = proc(): string =
    "SEARCH"

proc createModeHandlers*(): Table[EditorMode, ModeHandler] =
  result = initTable[EditorMode, ModeHandler]()
  result[EditorMode.Normal] = createNormalMode()
  result[EditorMode.Insert] = createInsertMode()
  result[EditorMode.Command] = createCommandMode()
  result[EditorMode.Visual] = createVisualMode()
  result[EditorMode.Search] = createSearchMode()
