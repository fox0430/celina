## Button widget
##
## This module provides interactive button widgets with click handling,
## styling, and focus support.

import std/[strutils, unicode]

import base
import ../core/[geometry, buffer, colors, events]

type
  ButtonState* = enum
    ## Button visual states
    Normal ## Default state
    Hovered ## Mouse is over the button
    Pressed ## Button is being pressed
    Focused ## Button has keyboard focus
    Disabled ## Button is disabled

  Button* = ref object of Widget ## Interactive button widget
    text*: string
    normalStyle*: Style
    hoveredStyle*: Style
    pressedStyle*: Style
    focusedStyle*: Style
    disabledStyle*: Style
    state*: ButtonState
    enabled*: bool
    minWidth*: int
    padding*: int
    # Event handlers
    onClick*: proc() # Callback for button clicks
    onMouseEnter*: proc() # Callback when mouse enters button
    onMouseLeave*: proc() # Callback when mouse leaves button
    onFocus*: proc() # Callback when button receives focus
    onBlur*: proc() # Callback when button loses focus
    onKeyPress*: proc(key: KeyEvent): bool # Callback for key press events

# Button widget constructors
proc newButton*(
    text: string,
    normalStyle: Style = style(White, Blue),
    hoveredStyle: Style = style(White, Cyan),
    pressedStyle: Style = style(Black, White),
    focusedStyle: Style = style(Yellow, Blue),
    disabledStyle: Style = style(BrightBlack, Reset),
    minWidth: int = 0,
    padding: int = 1,
    onClick: proc() = nil,
    onMouseEnter: proc() = nil,
    onMouseLeave: proc() = nil,
    onFocus: proc() = nil,
    onBlur: proc() = nil,
    onKeyPress: proc(key: KeyEvent): bool = nil,
): Button =
  ## Create a new Button widget
  Button(
    text: text,
    normalStyle: normalStyle,
    hoveredStyle: hoveredStyle,
    pressedStyle: pressedStyle,
    focusedStyle: focusedStyle,
    disabledStyle: disabledStyle,
    state: Normal,
    enabled: true,
    minWidth: minWidth,
    padding: padding,
    onClick: onClick,
    onMouseEnter: onMouseEnter,
    onMouseLeave: onMouseLeave,
    onFocus: onFocus,
    onBlur: onBlur,
    onKeyPress: onKeyPress,
  )

proc button*(
    text: string,
    normalStyle: Style = style(White, Blue),
    hoveredStyle: Style = style(White, Cyan),
    pressedStyle: Style = style(Black, White),
    focusedStyle: Style = style(Yellow, Blue),
    disabledStyle: Style = style(BrightBlack, Reset),
    minWidth: int = 0,
    padding: int = 1,
    onClick: proc() = nil,
    onMouseEnter: proc() = nil,
    onMouseLeave: proc() = nil,
    onFocus: proc() = nil,
    onBlur: proc() = nil,
    onKeyPress: proc(key: KeyEvent): bool = nil,
): Button =
  ## Convenience constructor for Button widget
  newButton(
    text, normalStyle, hoveredStyle, pressedStyle, focusedStyle, disabledStyle,
    minWidth, padding, onClick, onMouseEnter, onMouseLeave, onFocus, onBlur, onKeyPress,
  )

# Button state management
proc setState*(widget: Button, newState: ButtonState) =
  ## Set the button state and trigger appropriate events
  if not widget.enabled and newState != Disabled:
    return # Can't change state when disabled

  let oldState = widget.state

  if widget.enabled:
    widget.state = newState
  else:
    widget.state = Disabled

  # Trigger state change events
  if oldState != newState:
    case newState
    of Hovered:
      if widget.onMouseEnter != nil:
        widget.onMouseEnter()
    of Focused:
      if widget.onFocus != nil:
        widget.onFocus()
    of Normal:
      if oldState == Hovered and widget.onMouseLeave != nil:
        widget.onMouseLeave()
      elif oldState == Focused and widget.onBlur != nil:
        widget.onBlur()
    else:
      discard

proc setEnabled*(widget: Button, enabled: bool) =
  ## Enable or disable the button
  widget.enabled = enabled
  if not enabled:
    widget.state = Disabled
  else:
    widget.state = Normal

proc isEnabled*(widget: Button): bool =
  ## Check if the button is enabled
  widget.enabled

# Button event handling
proc handleClick*(widget: Button) =
  ## Handle button click
  if widget.enabled and widget.onClick != nil:
    widget.onClick()

proc handleKeyEvent*(widget: Button, event: KeyEvent): bool =
  ## Handle keyboard input for the button
  ## Returns true if the event was handled
  if not widget.enabled:
    return false

  # First try custom key handler
  if widget.onKeyPress != nil:
    if widget.onKeyPress(event):
      return true

  # Default key handling
  case event.code
  of Enter, Space:
    widget.setState(Pressed)
    widget.handleClick()
    widget.setState(if widget.state == Focused: Focused else: Normal)
    return true
  else:
    return false

proc handleMouseEvent*(widget: Button, event: MouseEvent, area: Rect): bool =
  ## Handle mouse input for the button
  ## Returns true if the event was handled
  if not widget.enabled:
    return false

  # Check if mouse is within button bounds
  let mouseInBounds =
    event.x >= area.x and event.x < area.x + area.width and event.y >= area.y and
    event.y < area.y + area.height

  if mouseInBounds:
    case event.kind
    of Press:
      if event.button == Left:
        widget.setState(Pressed)
        return true
    of Release:
      if event.button == Left and widget.state == Pressed:
        widget.setState(Hovered)
        widget.handleClick()
        return true
    of Move:
      if widget.state != Pressed:
        widget.setState(Hovered)
      return true
    else:
      discard
  else:
    # Mouse left the button area
    if widget.state == Hovered:
      widget.setState(Normal)

  return false

# Button styling utilities
proc getCurrentStyle*(widget: Button): Style =
  ## Get the current style based on button state
  case widget.state
  of Normal: widget.normalStyle
  of Hovered: widget.hoveredStyle
  of Pressed: widget.pressedStyle
  of Focused: widget.focusedStyle
  of Disabled: widget.disabledStyle

proc getButtonText*(widget: Button): string =
  ## Get the formatted button text with padding
  if widget.padding > 0:
    " ".repeat(widget.padding) & widget.text & " ".repeat(widget.padding)
  else:
    widget.text

# Button widget methods
method render*(widget: Button, area: Rect, buf: var Buffer) =
  ## Render the button widget
  if area.isEmpty:
    return

  let buttonText = widget.getButtonText()
  let currentStyle = widget.getCurrentStyle()
  let textWidth = buttonText.runeLen

  # Calculate actual button dimensions
  let actualButtonWidth = max(textWidth, widget.minWidth)
  let buttonWidth = min(area.width, actualButtonWidth)

  # Calculate button position (centered within the area)
  let buttonStartX = area.x + max(0, (area.width - buttonWidth) div 2)
  let buttonStartY = area.y + max(0, (area.height - 1) div 2)

  # Render the area in one pass - no clearing then redrawing
  for y in 0 ..< area.height:
    for x in 0 ..< area.width:
      let cellX = area.x + x
      let cellY = area.y + y

      # Determine if this cell is inside the button area
      let isInsideButton =
        x >= (buttonStartX - area.x) and x < (buttonStartX - area.x + buttonWidth)

      if isInsideButton:
        buf.setString(cellX, cellY, " ", currentStyle)
      else:
        buf.setString(cellX, cellY, " ", defaultStyle())

  # Calculate text position (centered within button)
  let textStartX = buttonStartX + max(0, (buttonWidth - textWidth) div 2)
  let textStartY = buttonStartY

  # Render the text if it fits
  if textStartY < area.y + area.height and textStartX < area.x + area.width:
    let visibleText =
      if textStartX + textWidth > area.x + area.width:
        buttonText.runeSubStr(0, area.x + area.width - textStartX)
      else:
        buttonText

    buf.setString(textStartX, textStartY, visibleText, currentStyle)

method getMinSize*(widget: Button): Size =
  ## Get minimum size for button widget
  let buttonText = widget.getButtonText()
  let textWidth = max(buttonText.runeLen, widget.minWidth)
  size(textWidth, 1)

method getPreferredSize*(widget: Button, available: Size): Size =
  ## Get preferred size for button widget
  let minSize = widget.getMinSize()
  size(
    max(minSize.width, min(available.width, minSize.width + 2)),
    max(minSize.height, min(available.height, 3)),
  )

method canFocus*(widget: Button): bool =
  ## Buttons can receive focus when enabled
  widget.enabled

# Button widget builders and modifiers
proc withText*(widget: Button, text: string): Button =
  ## Create a copy with different text
  Button(
    text: text,
    normalStyle: widget.normalStyle,
    hoveredStyle: widget.hoveredStyle,
    pressedStyle: widget.pressedStyle,
    focusedStyle: widget.focusedStyle,
    disabledStyle: widget.disabledStyle,
    state: widget.state,
    enabled: widget.enabled,
    minWidth: widget.minWidth,
    padding: widget.padding,
    onClick: widget.onClick,
  )

proc withStyles*(
    widget: Button,
    normal: Style = defaultStyle(),
    hovered: Style = defaultStyle(),
    pressed: Style = defaultStyle(),
    focused: Style = defaultStyle(),
    disabled: Style = defaultStyle(),
): Button =
  ## Create a copy with different styles
  Button(
    text: widget.text,
    normalStyle: if normal == defaultStyle(): widget.normalStyle else: normal,
    hoveredStyle: if hovered == defaultStyle(): widget.hoveredStyle else: hovered,
    pressedStyle: if pressed == defaultStyle(): widget.pressedStyle else: pressed,
    focusedStyle: if focused == defaultStyle(): widget.focusedStyle else: focused,
    disabledStyle: if disabled == defaultStyle(): widget.disabledStyle else: disabled,
    state: widget.state,
    enabled: widget.enabled,
    minWidth: widget.minWidth,
    padding: widget.padding,
    onClick: widget.onClick,
  )

proc withPadding*(widget: Button, padding: int): Button =
  ## Create a copy with different padding
  Button(
    text: widget.text,
    normalStyle: widget.normalStyle,
    hoveredStyle: widget.hoveredStyle,
    pressedStyle: widget.pressedStyle,
    focusedStyle: widget.focusedStyle,
    disabledStyle: widget.disabledStyle,
    state: widget.state,
    enabled: widget.enabled,
    minWidth: widget.minWidth,
    padding: padding,
    onClick: widget.onClick,
  )

proc withMinWidth*(widget: Button, minWidth: int): Button =
  ## Create a copy with different minimum width
  Button(
    text: widget.text,
    normalStyle: widget.normalStyle,
    hoveredStyle: widget.hoveredStyle,
    pressedStyle: widget.pressedStyle,
    focusedStyle: widget.focusedStyle,
    disabledStyle: widget.disabledStyle,
    state: widget.state,
    enabled: widget.enabled,
    minWidth: minWidth,
    padding: widget.padding,
    onClick: widget.onClick,
  )

proc withOnClick*(widget: Button, onClick: proc()): Button =
  ## Create a copy with different click handler
  Button(
    text: widget.text,
    normalStyle: widget.normalStyle,
    hoveredStyle: widget.hoveredStyle,
    pressedStyle: widget.pressedStyle,
    focusedStyle: widget.focusedStyle,
    disabledStyle: widget.disabledStyle,
    state: widget.state,
    enabled: widget.enabled,
    minWidth: widget.minWidth,
    padding: widget.padding,
    onClick: onClick,
    onMouseEnter: widget.onMouseEnter,
    onMouseLeave: widget.onMouseLeave,
    onFocus: widget.onFocus,
    onBlur: widget.onBlur,
    onKeyPress: widget.onKeyPress,
  )

proc withEventHandlers*(
    widget: Button,
    onClick: proc() = nil,
    onMouseEnter: proc() = nil,
    onMouseLeave: proc() = nil,
    onFocus: proc() = nil,
    onBlur: proc() = nil,
    onKeyPress: proc(key: KeyEvent): bool = nil,
): Button =
  ## Create a copy with different event handlers
  Button(
    text: widget.text,
    normalStyle: widget.normalStyle,
    hoveredStyle: widget.hoveredStyle,
    pressedStyle: widget.pressedStyle,
    focusedStyle: widget.focusedStyle,
    disabledStyle: widget.disabledStyle,
    state: widget.state,
    enabled: widget.enabled,
    minWidth: widget.minWidth,
    padding: widget.padding,
    onClick: if onClick != nil: onClick else: widget.onClick,
    onMouseEnter: if onMouseEnter != nil: onMouseEnter else: widget.onMouseEnter,
    onMouseLeave: if onMouseLeave != nil: onMouseLeave else: widget.onMouseLeave,
    onFocus: if onFocus != nil: onFocus else: widget.onFocus,
    onBlur: if onBlur != nil: onBlur else: widget.onBlur,
    onKeyPress: if onKeyPress != nil: onKeyPress else: widget.onKeyPress,
  )

# Convenience constructors for common button types
proc primaryButton*(text: string, onClick: proc() = nil): Button =
  ## Create a primary (prominent) button
  newButton(
    text,
    normalStyle = style(White, Blue),
    hoveredStyle = style(White, Cyan),
    pressedStyle = style(Blue, White),
    focusedStyle = style(Yellow, Blue),
    onClick = onClick,
  )

proc secondaryButton*(text: string, onClick: proc() = nil): Button =
  ## Create a secondary button
  newButton(
    text,
    normalStyle = style(White, BrightBlack),
    hoveredStyle = style(White, White),
    pressedStyle = style(BrightBlack, White),
    focusedStyle = style(Yellow, BrightBlack),
    onClick = onClick,
  )

proc dangerButton*(text: string, onClick: proc() = nil): Button =
  ## Create a danger (destructive action) button
  newButton(
    text,
    normalStyle = style(White, Red),
    hoveredStyle = style(White, Magenta),
    pressedStyle = style(Red, White),
    focusedStyle = style(Yellow, Red),
    onClick = onClick,
  )

proc successButton*(text: string, onClick: proc() = nil): Button =
  ## Create a success button
  newButton(
    text,
    normalStyle = style(White, Green),
    hoveredStyle = style(White, BrightGreen), # Changed from Cyan to avoid conflict
    pressedStyle = style(Green, White),
    focusedStyle = style(Yellow, Green),
    onClick = onClick,
  )
