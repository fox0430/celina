## Input widget
##
## This module provides text input widgets with cursor support,
## selection, and keyboard navigation.

import std/unicode

import base
import ../core/[geometry, buffer, colors, events, borders]

export
  borders.BorderKind, borders.BorderChars, borders.getBorderChars,
  borders.defaultBorderChars

{.push warning[Deprecated]: off.}
export
  borders.BorderStyle, borders.NoBorder, borders.SingleBorder, borders.DoubleBorder,
  borders.RoundedBorder
{.pop.}

type
  ## Text editing APIs (cursor, selection, insert, delete, scroll offset)
  ## operate in rune units, not display width — `runeLen` calls below are
  ## intentional. Display width is only consulted by `calculateVisibleRange`
  ## and the renderer, where layout requires column math.
  InputState* = object
    text*: string # The input text
    cursor*: int # Cursor position (in runes)
    selection*: tuple[start, stop: int] # Selection range (in runes)
    offset*: int # Horizontal scroll offset for long text (in runes)
    focused*: bool # Whether the input has focus

  InputStyle* = object ## Style aggregate for input widget colors
    normal*: Style ## Content style when not focused
    focused*: Style ## Content style when focused
    placeholder*: Style ## Placeholder text style
    cursor*: Style ## Cursor cell style
    selection*: Style ## Selection highlight style
    borderNormal*: Style ## Border style when not focused
    borderFocused*: Style ## Border style when focused

  InputCallbacks* = object ## Callback aggregate for input events
    onTextChanged*: proc(text: string) ## Called when text changes
    onEnter*: proc(text: string) ## Called on Enter key
    onFocus*: proc() ## Called when input gains focus
    onBlur*: proc() ## Called when input loses focus
    onKeyPress*: proc(key: KeyEvent): EventResult
      ## Custom key handler (return erConsume to suppress default handling)

  Input* = ref object of Widget ## Text input widget
    state*: InputState
    placeholder*: string
    normalStyle*: Style
    focusedStyle*: Style
    placeholderStyle*: Style
    cursorStyle*: Style
    selectionStyle*: Style
    borderStyle*: BorderKind
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
    onKeyPress*: proc(key: KeyEvent): EventResult # Custom key handler

# The legacy `BorderStyle` type and `NoBorder`/`SingleBorder`/etc. value
# aliases now live in `core/borders` and are re-exported above so importing
# both `widgets/input` and `widgets/table` does not produce ambiguous-
# identifier errors.

proc defaultInputStyle*(): InputStyle =
  ## Default style aggregate matching the historical per-field defaults.
  InputStyle(
    normal: style(White, Reset),
    focused: style(White, Blue),
    placeholder: style(BrightBlack, Reset),
    cursor: style(Black, White),
    selection: style(White, BrightBlue),
    borderNormal: style(BrightBlack, Reset),
    borderFocused: style(Blue, Reset),
  )

# Input widget constructors
proc newInput*(
    placeholder: string = "",
    style: InputStyle = defaultInputStyle(),
    border: BorderKind = bkNone,
    maxLength: int = 0,
    readOnly: bool = false,
    password: bool = false,
    callbacks: InputCallbacks = InputCallbacks(),
): Input =
  ## Create a new Input widget using `InputStyle` and `InputCallbacks` aggregates.
  Input(
    state: InputState(text: "", cursor: 0, selection: (0, 0), offset: 0, focused: false),
    placeholder: placeholder,
    normalStyle: style.normal,
    focusedStyle: style.focused,
    placeholderStyle: style.placeholder,
    cursorStyle: style.cursor,
    selectionStyle: style.selection,
    borderStyle: border,
    borderNormalStyle: style.borderNormal,
    borderFocusedStyle: style.borderFocused,
    maxLength: maxLength,
    readOnly: readOnly,
    password: password,
    onTextChanged: callbacks.onTextChanged,
    onEnter: callbacks.onEnter,
    onFocus: callbacks.onFocus,
    onBlur: callbacks.onBlur,
    onKeyPress: callbacks.onKeyPress,
  )

proc newInput*(
    placeholder: string,
    normalStyle: Style,
    focusedStyle: Style = style(White, Blue),
    placeholderStyle: Style = style(BrightBlack, Reset),
    cursorStyle: Style = style(Black, White),
    selectionStyle: Style = style(White, BrightBlue),
    borderStyle: BorderKind = bkNone,
    borderNormalStyle: Style = style(BrightBlack, Reset),
    borderFocusedStyle: Style = style(Blue, Reset),
    maxLength: int = 0,
    readOnly: bool = false,
    password: bool = false,
    onTextChanged: proc(text: string) = nil,
    onEnter: proc(text: string) = nil,
    onFocus: proc() = nil,
    onBlur: proc() = nil,
    onKeyPress: proc(key: KeyEvent): EventResult = nil,
): Input {.deprecated: "Use newInput with InputStyle/InputCallbacks aggregate".} =
  ## Deprecated: legacy form taking individual style and callback parameters.
  ##
  ## The required positional `normalStyle` disambiguates this overload from
  ## the aggregate-based one.
  newInput(
    placeholder = placeholder,
    style = InputStyle(
      normal: normalStyle,
      focused: focusedStyle,
      placeholder: placeholderStyle,
      cursor: cursorStyle,
      selection: selectionStyle,
      borderNormal: borderNormalStyle,
      borderFocused: borderFocusedStyle,
    ),
    border = borderStyle,
    maxLength = maxLength,
    readOnly = readOnly,
    password = password,
    callbacks = InputCallbacks(
      onTextChanged: onTextChanged,
      onEnter: onEnter,
      onFocus: onFocus,
      onBlur: onBlur,
      onKeyPress: onKeyPress,
    ),
  )

proc input*(
    placeholder: string = "",
    style: InputStyle = defaultInputStyle(),
    border: BorderKind = bkNone,
    maxLength: int = 0,
    readOnly: bool = false,
    password: bool = false,
    callbacks: InputCallbacks = InputCallbacks(),
): Input =
  ## Convenience constructor for Input widget (aggregate form).
  newInput(placeholder, style, border, maxLength, readOnly, password, callbacks)

proc input*(
    placeholder: string,
    normalStyle: Style,
    focusedStyle: Style = style(White, Blue),
    placeholderStyle: Style = style(BrightBlack, Reset),
    cursorStyle: Style = style(Black, White),
    selectionStyle: Style = style(White, BrightBlue),
    borderStyle: BorderKind = bkNone,
    borderNormalStyle: Style = style(BrightBlack, Reset),
    borderFocusedStyle: Style = style(Blue, Reset),
    maxLength: int = 0,
    readOnly: bool = false,
    password: bool = false,
    onTextChanged: proc(text: string) = nil,
    onEnter: proc(text: string) = nil,
    onFocus: proc() = nil,
    onBlur: proc() = nil,
    onKeyPress: proc(key: KeyEvent): EventResult = nil,
): Input {.deprecated: "Use input with InputStyle/InputCallbacks aggregate".} =
  ## Deprecated: legacy convenience form taking individual style parameters.
  newInput(
    placeholder = placeholder,
    style = InputStyle(
      normal: normalStyle,
      focused: focusedStyle,
      placeholder: placeholderStyle,
      cursor: cursorStyle,
      selection: selectionStyle,
      borderNormal: borderNormalStyle,
      borderFocused: borderFocusedStyle,
    ),
    border = borderStyle,
    maxLength = maxLength,
    readOnly = readOnly,
    password = password,
    callbacks = InputCallbacks(
      onTextChanged: onTextChanged,
      onEnter: onEnter,
      onFocus: onFocus,
      onBlur: onBlur,
      onKeyPress: onKeyPress,
    ),
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

method setFocus*(widget: Input, focused: bool) =
  ## Set focus state. Fires `onFocus`/`onBlur` callbacks on transition.
  if widget.state.focused != focused:
    widget.state.focused = focused
    if focused and widget.onFocus != nil:
      widget.onFocus()
    elif not focused and widget.onBlur != nil:
      widget.onBlur()

method isFocused*(widget: Input): bool =
  widget.state.focused

proc hasFocus*(widget: Input): bool {.inline.} =
  ## Backwards-compatible alias for `isFocused`.
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
proc handleKeyEvent*(widget: Input, event: KeyEvent): EventResult =
  ## Handle keyboard input for the input widget.
  ## Returns `erConsume` when the widget handled the key, `erContinue`
  ## otherwise so the global handler can still see it.
  if not widget.state.focused:
    return erContinue

  # First try custom key handler
  if widget.onKeyPress != nil:
    let r = widget.onKeyPress(event)
    if r != erContinue:
      return r

  # Handle common key combinations
  if Ctrl in event.modifiers:
    case event.code
    of Char:
      case event.char
      of "a", "A": # Ctrl+A - Select all
        widget.selectAll()
        return erConsume
      of "c", "C", "v", "V", "x", "X":
        # Defer clipboard handling to the application layer.
        return erContinue
      else:
        return erContinue
    else:
      return erContinue

  # Handle regular key events
  case event.code
  of Char:
    if not widget.readOnly and event.char.len > 0 and event.char[0].ord >= 32:
      # Printable characters
      if widget.hasSelection():
        widget.deleteSelection()
      widget.insertText(event.char)
      return erConsume
    else:
      # Non-printable character — let the app decide what to do with it.
      return erContinue
  of Enter:
    if widget.onEnter != nil:
      widget.onEnter(widget.state.text)
      return erConsume
  of Backspace:
    if not widget.readOnly:
      if widget.hasSelection():
        widget.deleteSelection()
      elif widget.state.cursor > 0:
        widget.deleteText(widget.state.cursor - 1, 1)
      return erConsume
  of Delete:
    if not widget.readOnly:
      if widget.hasSelection():
        widget.deleteSelection()
      else:
        widget.deleteText(widget.state.cursor, 1)
      return erConsume
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
    return erConsume
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
    return erConsume
  of Home:
    if Shift in event.modifiers:
      if not widget.hasSelection():
        widget.state.selection.start = widget.state.cursor
      widget.state.cursor = 0
      widget.state.selection.stop = widget.state.cursor
    else:
      widget.clearSelection()
      widget.state.cursor = 0
    return erConsume
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
    return erConsume
  else:
    return erContinue

# Generated: Input only consumes key events; other kinds propagate.
defineKeyDispatch(Input)

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
  ## Get the text to display (with password masking if enabled).
  ##
  ## Mask each rune with a character of the same display width so the masked
  ## string has the same rune count *and* column width as the original. This
  ## keeps it aligned with `calculateVisibleRange`, which indexes by rune over
  ## the original text but accumulates columns by `runeWidth`.
  if widget.password and widget.state.text.len > 0:
    for r in widget.state.text.runes:
      if runeWidth(r) >= 2:
        result.add("＊") # FULLWIDTH ASTERISK (2 cols)
      else:
        result.add('*') # narrow asterisk (1 col)
  else:
    result = widget.state.text

# Input widget methods
method render*(widget: Input, area: Rect, buf: var Buffer) =
  ## Render the input widget
  if area.isEmpty:
    return

  # Determine content area (inside border if any)
  var contentArea = area
  if widget.borderStyle != bkNone:
    # Adjust content area for border
    if area.width <= 2 or area.height <= 2:
      return # Too small for border
    contentArea = rect(area.x + 1, area.y + 1, area.width - 2, area.height - 2)

    # Draw border
    let borderStyle =
      if widget.state.focused: widget.borderFocusedStyle else: widget.borderNormalStyle
    let bc = getBorderChars(widget.borderStyle)

    # Draw corners
    if bc.topLeft.len > 0:
      buf.setString(area.x, area.y, bc.topLeft, borderStyle)
    if bc.topRight.len > 0:
      buf.setString(area.x + area.width - 1, area.y, bc.topRight, borderStyle)
    if bc.bottomLeft.len > 0:
      buf.setString(area.x, area.y + area.height - 1, bc.bottomLeft, borderStyle)
    if bc.bottomRight.len > 0:
      buf.setString(
        area.x + area.width - 1, area.y + area.height - 1, bc.bottomRight, borderStyle
      )

    # Draw horizontal lines
    for x in 1 ..< (area.width - 1):
      if bc.horizontal.len > 0:
        buf.setString(area.x + x, area.y, bc.horizontal, borderStyle)
        buf.setString(area.x + x, area.y + area.height - 1, bc.horizontal, borderStyle)

    # Draw vertical lines
    for y in 1 ..< (area.height - 1):
      if bc.vertical.len > 0:
        buf.setString(area.x, area.y + y, bc.vertical, borderStyle)
        buf.setString(area.x + area.width - 1, area.y + y, bc.vertical, borderStyle)

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
      let placeholderText = widget.placeholder.truncateToWidth(contentArea.width)
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
  if widget.borderStyle != bkNone:
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
  if widget.borderStyle != bkNone:
    size(3, 3) # Border needs at least 3x3
  else:
    size(1, 1)

method getPreferredSize*(widget: Input, available: Size): Size =
  ## Get preferred size for input widget
  if widget.borderStyle != bkNone:
    size(available.width, 3) # Border needs height of 3
  else:
    size(available.width, 1)

method canFocus*(widget: Input): bool =
  ## Input widgets can receive focus
  not widget.readOnly

# Input widget builders and modifiers
proc withText*(widget: Input, text: string): Input =
  ## Create a copy with different text
  result = copyWidget(widget)
  result.setText(text)

proc withPlaceholder*(widget: Input, placeholder: string): Input =
  ## Create a copy with different placeholder
  result = copyWidget(widget)
  result.placeholder = placeholder

proc withMaxLength*(widget: Input, maxLength: int): Input =
  ## Create a copy with different max length
  result = copyWidget(widget)
  result.maxLength = maxLength

proc withStyles*(
    widget: Input,
    normal: Style = defaultStyle(),
    focused: Style = defaultStyle(),
    placeholder: Style = defaultStyle(),
    cursor: Style = defaultStyle(),
    selection: Style = defaultStyle(),
): Input =
  ## Create a copy with different styles
  result = copyWidget(widget)
  if normal != defaultStyle():
    result.normalStyle = normal
  if focused != defaultStyle():
    result.focusedStyle = focused
  if placeholder != defaultStyle():
    result.placeholderStyle = placeholder
  if cursor != defaultStyle():
    result.cursorStyle = cursor
  if selection != defaultStyle():
    result.selectionStyle = selection

proc withEventHandlers*(
    widget: Input,
    onTextChanged: proc(text: string) = nil,
    onEnter: proc(text: string) = nil,
    onFocus: proc() = nil,
    onBlur: proc() = nil,
    onKeyPress: proc(key: KeyEvent): EventResult = nil,
): Input =
  ## Create a copy with different event handlers
  result = copyWidget(widget)
  if onTextChanged != nil:
    result.onTextChanged = onTextChanged
  if onEnter != nil:
    result.onEnter = onEnter
  if onFocus != nil:
    result.onFocus = onFocus
  if onBlur != nil:
    result.onBlur = onBlur
  if onKeyPress != nil:
    result.onKeyPress = onKeyPress

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
    maxLength = maxLength,
    password = true,
    callbacks = InputCallbacks(
      onEnter: onEnter, onFocus: onFocus, onBlur: onBlur, onTextChanged: onTextChanged
    ),
  )

proc searchInput*(
    placeholder: string = "Search...",
    onTextChanged: proc(text: string) = nil,
    onEnter: proc(text: string) = nil,
    onFocus: proc() = nil,
    onBlur: proc() = nil,
): Input =
  ## Create a search input widget
  var styleSet = defaultInputStyle()
  styleSet.focused = style(White, BrightBlue)
  newInput(
    placeholder = placeholder,
    style = styleSet,
    callbacks = InputCallbacks(
      onTextChanged: onTextChanged, onEnter: onEnter, onFocus: onFocus, onBlur: onBlur
    ),
  )

proc readOnlyInput*(
    text: string, normalStyle: Style = style(BrightBlack, Reset)
): Input =
  ## Create a read-only input widget
  var styleSet = defaultInputStyle()
  styleSet.normal = normalStyle
  styleSet.focused = normalStyle
  result = newInput(style = styleSet, readOnly = true)
  result.setText(text)
