## Input widget
##
## This module provides text input widgets with cursor support,
## selection, and keyboard navigation.

import std/[strutils, unicode]

import base
import ../core/[geometry, buffer, colors, events]

type
  InputState* = object
    text*: string # The input text
    cursor*: int # Cursor position (in runes)
    selection*: tuple[start, stop: int] # Selection range (in runes)
    offset*: int # Horizontal scroll offset for long text
    focused*: bool # Whether the input has focus

  BorderStyle* = enum
    ## Border style options
    NoBorder
    SingleBorder
    DoubleBorder
    RoundedBorder

  Input* = ref object of Widget ## Text input widget
    state*: InputState
    placeholder*: string
    normalStyle*: Style
    focusedStyle*: Style
    placeholderStyle*: Style
    cursorStyle*: Style
    selectionStyle*: Style
    borderStyle*: BorderStyle
    borderNormalStyle*: Style
    borderFocusedStyle*: Style
    maxLength*: int # Maximum input length (0 = unlimited)
    readOnly*: bool # Read-only mode
    password*: bool # Password mode (show asterisks)
    # Event handlers
    onTextChanged*: proc(text: string) # Called when text changes
    onEnter*: proc(text: string) # Called on Enter key
    onFocus*: proc() # Called when input gains focus
    onBlur*: proc() # Called when input loses focus
    onKeyPress*: proc(key: KeyEvent): bool # Custom key handler

# Display width utility
proc displayWidth(s: string): int =
  ## Calculate the display width of a string considering wide characters
  for r in s.runes:
    result += runeWidth(r)

# Border drawing utilities
proc getBorderChars(
    borderStyle: BorderStyle
): tuple[topLeft, topRight, bottomLeft, bottomRight, horizontal, vertical: string] =
  ## Get border characters for the specified style
  case borderStyle
  of NoBorder:
    ("", "", "", "", "", "")
  of SingleBorder:
    ("┌", "┐", "└", "┘", "─", "│")
  of DoubleBorder:
    ("╔", "╗", "╚", "╝", "═", "║")
  of RoundedBorder:
    ("╭", "╮", "╰", "╯", "─", "│")

# Input widget constructors
proc newInput*(
    placeholder: string = "",
    normalStyle: Style = style(White, Reset),
    focusedStyle: Style = style(White, Blue),
    placeholderStyle: Style = style(BrightBlack, Reset),
    cursorStyle: Style = style(Black, White),
    selectionStyle: Style = style(White, BrightBlue),
    borderStyle: BorderStyle = NoBorder,
    borderNormalStyle: Style = style(BrightBlack, Reset),
    borderFocusedStyle: Style = style(Blue, Reset),
    maxLength: int = 0,
    readOnly: bool = false,
    password: bool = false,
    onTextChanged: proc(text: string) = nil,
    onEnter: proc(text: string) = nil,
    onFocus: proc() = nil,
    onBlur: proc() = nil,
    onKeyPress: proc(key: KeyEvent): bool = nil,
): Input =
  ## Create a new Input widget
  Input(
    state: InputState(text: "", cursor: 0, selection: (0, 0), offset: 0, focused: false),
    placeholder: placeholder,
    normalStyle: normalStyle,
    focusedStyle: focusedStyle,
    placeholderStyle: placeholderStyle,
    cursorStyle: cursorStyle,
    selectionStyle: selectionStyle,
    borderStyle: borderStyle,
    borderNormalStyle: borderNormalStyle,
    borderFocusedStyle: borderFocusedStyle,
    maxLength: maxLength,
    readOnly: readOnly,
    password: password,
    onTextChanged: onTextChanged,
    onEnter: onEnter,
    onFocus: onFocus,
    onBlur: onBlur,
    onKeyPress: onKeyPress,
  )

proc input*(
    placeholder: string = "",
    normalStyle: Style = style(White, Reset),
    focusedStyle: Style = style(White, Blue),
    placeholderStyle: Style = style(BrightBlack, Reset),
    cursorStyle: Style = style(Black, White),
    selectionStyle: Style = style(White, BrightBlue),
    borderStyle: BorderStyle = NoBorder,
    borderNormalStyle: Style = style(BrightBlack, Reset),
    borderFocusedStyle: Style = style(Blue, Reset),
    maxLength: int = 0,
    readOnly: bool = false,
    password: bool = false,
    onTextChanged: proc(text: string) = nil,
    onEnter: proc(text: string) = nil,
    onFocus: proc() = nil,
    onBlur: proc() = nil,
    onKeyPress: proc(key: KeyEvent): bool = nil,
): Input =
  ## Convenience constructor for Input widget
  newInput(
    placeholder, normalStyle, focusedStyle, placeholderStyle, cursorStyle,
    selectionStyle, borderStyle, borderNormalStyle, borderFocusedStyle, maxLength,
    readOnly, password, onTextChanged, onEnter, onFocus, onBlur, onKeyPress,
  )

# Input state management
proc setText*(widget: Input, text: string) =
  ## Set the input text
  let newText =
    if widget.maxLength > 0:
      text.runeSubStr(0, widget.maxLength)
    else:
      text
  let textLen = newText.runeLen

  widget.state.text = newText
  widget.state.cursor = min(widget.state.cursor, textLen)
  widget.state.selection = (0, 0) # Clear selection

  if widget.onTextChanged != nil:
    widget.onTextChanged(widget.state.text)

proc getText*(widget: Input): string =
  ## Get the current input text
  widget.state.text

proc setCursor*(widget: Input, pos: int) =
  ## Set cursor position (in runes)
  let textLen = widget.state.text.runeLen
  widget.state.cursor = max(0, min(pos, textLen))
  widget.state.selection = (0, 0) # Clear selection

proc getCursor*(widget: Input): int =
  ## Get cursor position
  widget.state.cursor

proc setFocus*(widget: Input, focused: bool) =
  ## Set focus state
  if widget.state.focused != focused:
    widget.state.focused = focused
    if focused and widget.onFocus != nil:
      widget.onFocus()
    elif not focused and widget.onBlur != nil:
      widget.onBlur()

proc hasFocus*(widget: Input): bool =
  ## Check if input has focus
  widget.state.focused

proc hasSelection*(widget: Input): bool =
  ## Check if there's a text selection
  widget.state.selection.start != widget.state.selection.stop

proc getSelection*(widget: Input): tuple[start, stop: int] =
  ## Get selection range (normalized)
  let selection = widget.state.selection
  if selection.start <= selection.stop:
    selection
  else:
    (selection.stop, selection.start)

proc clearSelection*(widget: Input) =
  ## Clear text selection
  widget.state.selection = (0, 0)

# Text manipulation utilities
proc insertText*(widget: Input, text: string, pos: int = -1) =
  ## Insert text at position (or at cursor if pos = -1)
  if widget.readOnly:
    return

  let insertPos = if pos >= 0: pos else: widget.state.cursor
  let currentLen = widget.state.text.runeLen
  let actualPos = max(0, min(insertPos, currentLen))

  # Calculate how much we can insert
  let availableSpace =
    if widget.maxLength > 0:
      max(0, widget.maxLength - currentLen)
    else:
      text.runeLen

  if availableSpace <= 0:
    return

  let textToInsert =
    if text.runeLen > availableSpace:
      text.runeSubStr(0, availableSpace)
    else:
      text

  # Insert text
  let beforeText =
    if actualPos > 0:
      widget.state.text.runeSubStr(0, actualPos)
    else:
      ""
  let afterText =
    if actualPos < currentLen:
      widget.state.text.runeSubStr(actualPos)
    else:
      ""

  widget.state.text = beforeText & textToInsert & afterText
  widget.state.cursor = actualPos + textToInsert.runeLen
  widget.state.selection = (0, 0)

  if widget.onTextChanged != nil:
    widget.onTextChanged(widget.state.text)

proc deleteText*(widget: Input, start: int, length: int) =
  ## Delete text range
  if widget.readOnly:
    return

  let textLen = widget.state.text.runeLen
  let actualStart = max(0, min(start, textLen))
  let actualEnd = max(actualStart, min(start + length, textLen))

  if actualStart >= actualEnd:
    return

  let beforeText =
    if actualStart > 0:
      widget.state.text.runeSubStr(0, actualStart)
    else:
      ""
  let afterText =
    if actualEnd < textLen:
      widget.state.text.runeSubStr(actualEnd)
    else:
      ""

  widget.state.text = beforeText & afterText
  widget.state.cursor = min(widget.state.cursor, actualStart)
  widget.state.selection = (0, 0)

  if widget.onTextChanged != nil:
    widget.onTextChanged(widget.state.text)

proc deleteSelection*(widget: Input) =
  ## Delete selected text
  if not widget.hasSelection():
    return

  let selection = widget.getSelection()
  let length = selection.stop - selection.start
  widget.deleteText(selection.start, length)
  widget.state.cursor = selection.start

proc selectAll*(widget: Input) =
  ## Select all text
  let textLen = widget.state.text.runeLen
  widget.state.selection = (0, textLen)
  widget.state.cursor = textLen

# Input event handling
proc handleKeyEvent*(widget: Input, event: KeyEvent): bool =
  ## Handle keyboard input for the input widget
  ## Returns true if the event was handled
  if not widget.state.focused:
    return false

  # First try custom key handler
  if widget.onKeyPress != nil:
    if widget.onKeyPress(event):
      return true

  # Handle common key combinations
  if Ctrl in event.modifiers:
    case event.code
    of Char:
      case event.char
      of "a", "A": # Ctrl+A - Select all
        widget.selectAll()
        return true
      of "c", "C": # Ctrl+C - Copy (handled externally)
        return false
      of "v", "V": # Ctrl+V - Paste (handled externally)
        return false
      of "x", "X": # Ctrl+X - Cut (handled externally)
        return false
      else:
        return false
    else:
      return false

  # Handle regular key events
  case event.code
  of Char:
    if not widget.readOnly and event.char.len > 0 and event.char[0].ord >= 32:
      # Printable characters
      if widget.hasSelection():
        widget.deleteSelection()
      widget.insertText(event.char)
      return true
    else:
      return false # Non-printable character
  of Enter:
    if widget.onEnter != nil:
      widget.onEnter(widget.state.text)
      return true
  of Backspace:
    if not widget.readOnly:
      if widget.hasSelection():
        widget.deleteSelection()
      elif widget.state.cursor > 0:
        widget.deleteText(widget.state.cursor - 1, 1)
      return true
  of Delete:
    if not widget.readOnly:
      if widget.hasSelection():
        widget.deleteSelection()
      else:
        widget.deleteText(widget.state.cursor, 1)
      return true
  of ArrowLeft:
    if Shift in event.modifiers:
      # Extend selection
      if not widget.hasSelection():
        widget.state.selection.start = widget.state.cursor
      widget.state.cursor = max(0, widget.state.cursor - 1)
      widget.state.selection.stop = widget.state.cursor
    else:
      widget.clearSelection()
      widget.state.cursor = max(0, widget.state.cursor - 1)
    return true
  of ArrowRight:
    let textLen = widget.state.text.runeLen
    if Shift in event.modifiers:
      # Extend selection
      if not widget.hasSelection():
        widget.state.selection.start = widget.state.cursor
      widget.state.cursor = min(textLen, widget.state.cursor + 1)
      widget.state.selection.stop = widget.state.cursor
    else:
      widget.clearSelection()
      widget.state.cursor = min(textLen, widget.state.cursor + 1)
    return true
  of Home:
    if Shift in event.modifiers:
      if not widget.hasSelection():
        widget.state.selection.start = widget.state.cursor
      widget.state.cursor = 0
      widget.state.selection.stop = widget.state.cursor
    else:
      widget.clearSelection()
      widget.state.cursor = 0
    return true
  of End:
    let textLen = widget.state.text.runeLen
    if Shift in event.modifiers:
      if not widget.hasSelection():
        widget.state.selection.start = widget.state.cursor
      widget.state.cursor = textLen
      widget.state.selection.stop = widget.state.cursor
    else:
      widget.clearSelection()
      widget.state.cursor = textLen
    return true
  else:
    return false

# Calculate visible range and cursor position for rendering
proc calculateVisibleRange(
    widget: Input, width: int
): tuple[offset: int, visibleStart: int, visibleEnd: int, cursorX: int] =
  ## Calculate which part of the text is visible and where the cursor should be drawn
  ## This now works with display widths instead of rune counts
  let textLen = widget.state.text.runeLen
  let cursor = widget.state.cursor

  if textLen == 0 or width <= 0:
    return (0, 0, 0, 0)

  # Calculate display width from start to cursor position
  var cursorDisplayWidth = 0
  var runeIndex = 0
  for r in widget.state.text.runes:
    if runeIndex >= cursor:
      break
    cursorDisplayWidth += runeWidth(r)
    runeIndex += 1

  # Ensure cursor is visible - adjust offset based on display width
  var offset = widget.state.offset

  # Calculate display width from offset to current view
  var offsetDisplayWidth = 0
  runeIndex = 0
  for r in widget.state.text.runes:
    if runeIndex >= offset:
      break
    offsetDisplayWidth += runeWidth(r)
    runeIndex += 1

  # If cursor is beyond the right edge, scroll right
  let cursorRelativeWidth = cursorDisplayWidth - offsetDisplayWidth
  if cursorRelativeWidth >= width:
    # Scroll right until cursor is visible
    offsetDisplayWidth = cursorDisplayWidth - width + 1
    offset = 0
    var accWidth = 0
    for r in widget.state.text.runes:
      if accWidth >= offsetDisplayWidth:
        break
      accWidth += runeWidth(r)
      offset += 1

  # If cursor is beyond the left edge, scroll left
  if cursor < offset:
    offset = cursor

  # Constrain offset to valid range
  offset = max(0, min(offset, textLen))

  # Calculate visible range based on display width
  let visibleStart = offset
  var visibleEnd = offset
  var accumulatedWidth = 0
  runeIndex = 0
  for r in widget.state.text.runes:
    if runeIndex < offset:
      runeIndex += 1
      continue
    let charWidth = runeWidth(r)
    if accumulatedWidth + charWidth > width:
      break
    accumulatedWidth += charWidth
    visibleEnd += 1
    runeIndex += 1

  # Calculate cursor X position in display width
  var cursorX = 0
  runeIndex = 0
  for r in widget.state.text.runes:
    if runeIndex >= offset and runeIndex < cursor:
      cursorX += runeWidth(r)
    elif runeIndex >= cursor:
      break
    runeIndex += 1

  # Ensure cursor position is within bounds
  let clampedCursorX =
    if width > 0:
      max(0, min(cursorX, width - 1))
    else:
      0

  widget.state.offset = offset
  return (offset, visibleStart, visibleEnd, clampedCursorX)

proc getDisplayText(widget: Input): string =
  ## Get the text to display (with password masking if enabled)
  if widget.password and widget.state.text.len > 0:
    "*".repeat(widget.state.text.runeLen)
  else:
    widget.state.text

# Input widget methods
method render*(widget: Input, area: Rect, buf: var Buffer) =
  ## Render the input widget
  if area.isEmpty:
    return

  # Determine content area (inside border if any)
  var contentArea = area
  if widget.borderStyle != NoBorder:
    # Adjust content area for border
    if area.width <= 2 or area.height <= 2:
      return # Too small for border
    contentArea = rect(area.x + 1, area.y + 1, area.width - 2, area.height - 2)

    # Draw border
    let borderStyle =
      if widget.state.focused: widget.borderFocusedStyle else: widget.borderNormalStyle
    let (topLeft, topRight, bottomLeft, bottomRight, horizontal, vertical) =
      getBorderChars(widget.borderStyle)

    # Draw corners
    if topLeft.len > 0:
      buf.setString(area.x, area.y, topLeft, borderStyle)
    if topRight.len > 0:
      buf.setString(area.x + area.width - 1, area.y, topRight, borderStyle)
    if bottomLeft.len > 0:
      buf.setString(area.x, area.y + area.height - 1, bottomLeft, borderStyle)
    if bottomRight.len > 0:
      buf.setString(
        area.x + area.width - 1, area.y + area.height - 1, bottomRight, borderStyle
      )

    # Draw horizontal lines
    for x in 1 ..< (area.width - 1):
      if horizontal.len > 0:
        buf.setString(area.x + x, area.y, horizontal, borderStyle)
        buf.setString(area.x + x, area.y + area.height - 1, horizontal, borderStyle)

    # Draw vertical lines
    for y in 1 ..< (area.height - 1):
      if vertical.len > 0:
        buf.setString(area.x, area.y + y, vertical, borderStyle)
        buf.setString(area.x + area.width - 1, area.y + y, vertical, borderStyle)

  let displayText = widget.getDisplayText()
  let currentStyle =
    if widget.state.focused: widget.focusedStyle else: widget.normalStyle

  # Calculate visible text range using content area
  let (_, visStart, visEnd, _) = widget.calculateVisibleRange(contentArea.width)

  if displayText.len == 0:
    # Show placeholder text - clear with placeholder style background
    let backgroundStyle = Style(
      fg: widget.placeholderStyle.fg, bg: widget.placeholderStyle.bg, modifiers: {}
    )

    # Clear the content area with placeholder background
    for x in 0 ..< contentArea.width:
      buf.setString(contentArea.x + x, contentArea.y, " ", backgroundStyle)

    if widget.placeholder.len > 0:
      let placeholderText = widget.placeholder.runeSubStr(
        0, min(widget.placeholder.runeLen, contentArea.width)
      )
      buf.setString(
        contentArea.x, contentArea.y, placeholderText, widget.placeholderStyle
      )
  else:
    # Clear the content area with input background for text display
    for x in 0 ..< contentArea.width:
      buf.setString(contentArea.x + x, contentArea.y, " ", currentStyle)

    # Render visible text
    # Render character by character to handle selection
    var x = 0
    for i in visStart ..< visEnd:
      if x >= contentArea.width:
        break

      let char = displayText.runeSubStr(i, 1)
      let charWidth = char.displayWidth()

      # Check if we have enough space for this character
      if x + charWidth > contentArea.width:
        break

      let charStyle =
        if widget.hasSelection():
          let selection = widget.getSelection()
          if i >= selection.start and i < selection.stop:
            widget.selectionStyle
          else:
            currentStyle
        else:
          currentStyle

      buf.setString(contentArea.x + x, contentArea.y, char, charStyle)
      x += charWidth

  # Note: Cursor rendering is handled by the application level
  # The cursor position should be calculated and set by the app

proc getCursorPosition*(widget: Input, area: Rect): tuple[x, y: int, visible: bool] =
  ## Get the screen cursor position for this input widget
  ## Returns the absolute screen coordinates and visibility
  if not widget.state.focused:
    return (-1, -1, false)

  # Determine content area (inside border if any)
  var contentArea = area
  if widget.borderStyle != NoBorder:
    if area.width <= 2 or area.height <= 2:
      return (-1, -1, false) # Too small for border
    contentArea = rect(area.x + 1, area.y + 1, area.width - 2, area.height - 2)

  let (_, _, _, cursorX) = widget.calculateVisibleRange(contentArea.width)

  if cursorX >= 0 and cursorX < contentArea.width:
    return (contentArea.x + cursorX, contentArea.y, true)
  else:
    return (-1, -1, false)

method getMinSize*(widget: Input): Size =
  ## Get minimum size for input widget
  if widget.borderStyle != NoBorder:
    size(3, 3) # Border needs at least 3x3
  else:
    size(1, 1)

method getPreferredSize*(widget: Input, available: Size): Size =
  ## Get preferred size for input widget
  if widget.borderStyle != NoBorder:
    size(available.width, 3) # Border needs height of 3
  else:
    size(available.width, 1)

method canFocus*(widget: Input): bool =
  ## Input widgets can receive focus
  not widget.readOnly

# Input widget builders and modifiers
proc withText*(widget: Input, text: string): Input =
  ## Create a copy with different text
  result = Input(
    state: widget.state,
    placeholder: widget.placeholder,
    normalStyle: widget.normalStyle,
    focusedStyle: widget.focusedStyle,
    placeholderStyle: widget.placeholderStyle,
    cursorStyle: widget.cursorStyle,
    selectionStyle: widget.selectionStyle,
    maxLength: widget.maxLength,
    readOnly: widget.readOnly,
    password: widget.password,
    onTextChanged: widget.onTextChanged,
    onEnter: widget.onEnter,
    onFocus: widget.onFocus,
    onBlur: widget.onBlur,
    onKeyPress: widget.onKeyPress,
  )
  result.setText(text)

proc withPlaceholder*(widget: Input, placeholder: string): Input =
  ## Create a copy with different placeholder
  Input(
    state: widget.state,
    placeholder: placeholder,
    normalStyle: widget.normalStyle,
    focusedStyle: widget.focusedStyle,
    placeholderStyle: widget.placeholderStyle,
    cursorStyle: widget.cursorStyle,
    selectionStyle: widget.selectionStyle,
    maxLength: widget.maxLength,
    readOnly: widget.readOnly,
    password: widget.password,
    onTextChanged: widget.onTextChanged,
    onEnter: widget.onEnter,
    onFocus: widget.onFocus,
    onBlur: widget.onBlur,
    onKeyPress: widget.onKeyPress,
  )

proc withMaxLength*(widget: Input, maxLength: int): Input =
  ## Create a copy with different max length
  Input(
    state: widget.state,
    placeholder: widget.placeholder,
    normalStyle: widget.normalStyle,
    focusedStyle: widget.focusedStyle,
    placeholderStyle: widget.placeholderStyle,
    cursorStyle: widget.cursorStyle,
    selectionStyle: widget.selectionStyle,
    maxLength: maxLength,
    readOnly: widget.readOnly,
    password: widget.password,
    onTextChanged: widget.onTextChanged,
    onEnter: widget.onEnter,
    onFocus: widget.onFocus,
    onBlur: widget.onBlur,
    onKeyPress: widget.onKeyPress,
  )

proc withStyles*(
    widget: Input,
    normal: Style = defaultStyle(),
    focused: Style = defaultStyle(),
    placeholder: Style = defaultStyle(),
    cursor: Style = defaultStyle(),
    selection: Style = defaultStyle(),
): Input =
  ## Create a copy with different styles
  Input(
    state: widget.state,
    placeholder: widget.placeholder,
    normalStyle: if normal == defaultStyle(): widget.normalStyle else: normal,
    focusedStyle: if focused == defaultStyle(): widget.focusedStyle else: focused,
    placeholderStyle:
      if placeholder == defaultStyle(): widget.placeholderStyle else: placeholder,
    cursorStyle: if cursor == defaultStyle(): widget.cursorStyle else: cursor,
    selectionStyle:
      if selection == defaultStyle(): widget.selectionStyle else: selection,
    maxLength: widget.maxLength,
    readOnly: widget.readOnly,
    password: widget.password,
    onTextChanged: widget.onTextChanged,
    onEnter: widget.onEnter,
    onFocus: widget.onFocus,
    onBlur: widget.onBlur,
    onKeyPress: widget.onKeyPress,
  )

proc withEventHandlers*(
    widget: Input,
    onTextChanged: proc(text: string) = nil,
    onEnter: proc(text: string) = nil,
    onFocus: proc() = nil,
    onBlur: proc() = nil,
    onKeyPress: proc(key: KeyEvent): bool = nil,
): Input =
  ## Create a copy with different event handlers
  Input(
    state: widget.state,
    placeholder: widget.placeholder,
    normalStyle: widget.normalStyle,
    focusedStyle: widget.focusedStyle,
    placeholderStyle: widget.placeholderStyle,
    cursorStyle: widget.cursorStyle,
    selectionStyle: widget.selectionStyle,
    maxLength: widget.maxLength,
    readOnly: widget.readOnly,
    password: widget.password,
    onTextChanged: if onTextChanged != nil: onTextChanged else: widget.onTextChanged,
    onEnter: if onEnter != nil: onEnter else: widget.onEnter,
    onFocus: if onFocus != nil: onFocus else: widget.onFocus,
    onBlur: if onBlur != nil: onBlur else: widget.onBlur,
    onKeyPress: if onKeyPress != nil: onKeyPress else: widget.onKeyPress,
  )

# Convenience constructors for common input types
proc passwordInput*(
    placeholder: string = "Password",
    maxLength: int = 0,
    onEnter: proc(text: string) = nil,
    onFocus: proc() = nil,
    onBlur: proc() = nil,
    onTextChanged: proc(text: string) = nil,
): Input =
  ## Create a password input widget
  newInput(
    placeholder = placeholder,
    normalStyle = style(White, Reset),
    focusedStyle = style(White, Blue),
    maxLength = maxLength,
    password = true,
    onEnter = onEnter,
    onFocus = onFocus,
    onBlur = onBlur,
    onTextChanged = onTextChanged,
  )

proc searchInput*(
    placeholder: string = "Search...",
    onTextChanged: proc(text: string) = nil,
    onEnter: proc(text: string) = nil,
    onFocus: proc() = nil,
    onBlur: proc() = nil,
): Input =
  ## Create a search input widget
  newInput(
    placeholder = placeholder,
    normalStyle = style(White, Reset),
    focusedStyle = style(White, BrightBlue),
    placeholderStyle = style(BrightBlack, Reset),
    onTextChanged = onTextChanged,
    onEnter = onEnter,
    onFocus = onFocus,
    onBlur = onBlur,
  )

proc readOnlyInput*(
    text: string, normalStyle: Style = style(BrightBlack, Reset)
): Input =
  ## Create a read-only input widget
  result =
    newInput(normalStyle = normalStyle, focusedStyle = normalStyle, readOnly = true)
  result.setText(text)
