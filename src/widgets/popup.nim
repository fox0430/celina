## Popup and tooltip widgets for Celina TUI library
##
## This module provides popup windows and tooltips that can be displayed
## over other content. Popups are activated via keyboard navigation.

import ../core/[geometry, buffer, colors]
import base
import std/sequtils

type
  PopupPosition* = enum
    ## Position of popup relative to anchor point
    Above
    Below
    Left
    Right
    Center

  PopupStyle* = object ## Styling options for popups
    border*: bool
    borderStyle*: Style
    background*: Style
    shadow*: bool
    shadowStyle*: Style

  PopupState* = object ## State for popup management
    visible*: bool
    anchorX*: int
    anchorY*: int
    position*: PopupPosition
    content*: seq[string]
    title*: string

  Popup* = ref object of StatefulWidget[PopupState] ## A popup window widget
    style*: PopupStyle
    minWidth*: int
    maxWidth*: int
    autoClose*: bool

  TooltipState* = object ## State for tooltip management
    visible*: bool
    text*: string
    anchorX*: int
    anchorY*: int

  Tooltip* = ref object of StatefulWidget[TooltipState] ## A simple tooltip widget
    style*: Style
    background*: Style

# Default styles
proc defaultPopupStyle*(): PopupStyle =
  ## Create default popup styling
  PopupStyle(
    border: true,
    borderStyle: style(Color.White, modifiers = {Bold}),
    background: style(Color.White, Color.Black),
    shadow: true,
    shadowStyle: style(Color.BrightBlack, Color.BrightBlack),
  )

proc defaultTooltipStyle*(): Style =
  ## Create default tooltip text styling
  style(Color.Black, Color.Yellow)

# Popup creation functions
proc newPopup*(
    content: seq[string] = @[],
    title: string = "",
    popupStyle: PopupStyle = defaultPopupStyle(),
    minWidth: int = 10,
    maxWidth: int = 50,
    autoClose: bool = true,
): Popup =
  ## Create a new popup widget
  let initialState = PopupState(
    visible: false,
    anchorX: 0,
    anchorY: 0,
    position: Below,
    content: content,
    title: title,
  )

  result = Popup()
  result.state = initialState
  result.style = popupStyle
  result.minWidth = minWidth
  result.maxWidth = maxWidth
  result.autoClose = autoClose

proc newTooltip*(
    text: string = "",
    textStyle: Style = defaultTooltipStyle(),
    bgStyle: Style = style(Color.Black, Color.Yellow),
): Tooltip =
  ## Create a new tooltip widget
  let initialState = TooltipState(visible: false, text: text, anchorX: 0, anchorY: 0)

  result = Tooltip()
  result.state = initialState
  result.style = textStyle
  result.background = bgStyle

# Popup control methods
proc show*(popup: Popup, anchorX, anchorY: int, position: PopupPosition = Below) =
  ## Show popup at specified anchor position
  popup.state.visible = true
  popup.state.anchorX = anchorX
  popup.state.anchorY = anchorY
  popup.state.position = position

proc hide*(popup: Popup) =
  ## Hide the popup
  popup.state.visible = false

proc isVisible*(popup: Popup): bool =
  ## Check if popup is currently visible
  popup.state.visible

proc setContent*(popup: Popup, content: seq[string], title: string = "") =
  ## Update popup content
  popup.state.content = content
  if title != "":
    popup.state.title = title

proc addLine*(popup: Popup, line: string) =
  ## Add a line to popup content
  popup.state.content.add(line)

proc clearContent*(popup: Popup) =
  ## Clear popup content
  popup.state.content = @[]
  popup.state.title = ""

# Tooltip control methods
proc show*(tooltip: Tooltip, anchorX, anchorY: int, text: string) =
  ## Show tooltip at specified position
  tooltip.state.visible = true
  tooltip.state.anchorX = anchorX
  tooltip.state.anchorY = anchorY
  tooltip.state.text = text

proc hide*(tooltip: Tooltip) =
  ## Hide the tooltip
  tooltip.state.visible = false

proc isVisible*(tooltip: Tooltip): bool =
  ## Check if tooltip is currently visible
  tooltip.state.visible

# Popup positioning logic
proc calculatePopupRect*(popup: Popup, bufferArea: Rect): Rect =
  ## Calculate the rectangle for popup placement
  let state = popup.state

  # Calculate content dimensions
  let titleLines = if state.title.len > 0: 1 else: 0
  let contentWidth = max(
    popup.minWidth,
    min(
      popup.maxWidth,
      max(
        state.title.len,
        if state.content.len > 0:
          state.content.mapIt(it.len).max()
        else:
          0,
      ),
    ),
  )
  let contentHeight = titleLines + state.content.len

  # Add border padding
  let totalWidth =
    if popup.style.border:
      contentWidth + 2
    else:
      contentWidth
  let totalHeight =
    if popup.style.border:
      contentHeight + 2
    else:
      contentHeight

  # Calculate position based on anchor and position preference
  var x, y: int

  case state.position
  of Above:
    x = state.anchorX - totalWidth div 2
    y = state.anchorY - totalHeight
  of Below:
    x = state.anchorX - totalWidth div 2
    y = state.anchorY + 1
  of Left:
    x = state.anchorX - totalWidth
    y = state.anchorY - totalHeight div 2
  of Right:
    x = state.anchorX + 1
    y = state.anchorY - totalHeight div 2
  of Center:
    x = bufferArea.width div 2 - totalWidth div 2
    y = bufferArea.height div 2 - totalHeight div 2

  # Constrain to buffer bounds
  x = max(0, min(x, bufferArea.width - totalWidth))
  y = max(0, min(y, bufferArea.height - totalHeight))

  rect(x, y, totalWidth, totalHeight)

proc calculateTooltipRect(tooltip: Tooltip, bufferArea: Rect): Rect =
  ## Calculate the rectangle for tooltip placement
  let state = tooltip.state
  let width = state.text.len
  let height = 1

  # Position tooltip near anchor, but keep in bounds
  var x = state.anchorX
  var y = state.anchorY - 1 # Above anchor by default

  # Adjust if would go out of bounds
  if x + width > bufferArea.width:
    x = bufferArea.width - width
  if y < 0:
    y = state.anchorY + 1 # Below anchor instead

  x = max(0, x)
  y = max(0, min(y, bufferArea.height - 1))

  rect(x, y, width, height)

# Rendering methods
method render*(popup: Popup, area: Rect, buf: var Buffer) =
  ## Render the popup widget
  if not popup.state.visible:
    return

  let popupRect = popup.calculatePopupRect(area)

  # Draw shadow if enabled
  if popup.style.shadow and popupRect.x + popupRect.width + 1 < area.width and
      popupRect.y + popupRect.height + 1 < area.height:
    # Right shadow
    for y in popupRect.y + 1 .. popupRect.y + popupRect.height:
      if y < area.height:
        buf[popupRect.x + popupRect.width, y] = cell(" ", popup.style.shadowStyle)

    # Bottom shadow
    for x in popupRect.x + 1 .. popupRect.x + popupRect.width:
      if x < area.width:
        buf[x, popupRect.y + popupRect.height] = cell(" ", popup.style.shadowStyle)

  # Draw background
  for y in popupRect.y .. popupRect.y + popupRect.height - 1:
    for x in popupRect.x .. popupRect.x + popupRect.width - 1:
      if x < area.width and y < area.height:
        buf[x, y] = cell(" ", popup.style.background)

  # Draw border if enabled
  if popup.style.border:
    # Top and bottom borders
    for x in popupRect.x .. popupRect.x + popupRect.width - 1:
      if x < area.width:
        if popupRect.y < area.height:
          buf[x, popupRect.y] = cell("─", popup.style.borderStyle)
        if popupRect.y + popupRect.height - 1 < area.height:
          buf[x, popupRect.y + popupRect.height - 1] =
            cell("─", popup.style.borderStyle)

    # Left and right borders
    for y in popupRect.y .. popupRect.y + popupRect.height - 1:
      if y < area.height:
        if popupRect.x < area.width:
          buf[popupRect.x, y] = cell("│", popup.style.borderStyle)
        if popupRect.x + popupRect.width - 1 < area.width:
          buf[popupRect.x + popupRect.width - 1, y] =
            cell("│", popup.style.borderStyle)

    # Corners
    if popupRect.x < area.width and popupRect.y < area.height:
      buf[popupRect.x, popupRect.y] = cell("┌", popup.style.borderStyle)
    if popupRect.x + popupRect.width - 1 < area.width and popupRect.y < area.height:
      buf[popupRect.x + popupRect.width - 1, popupRect.y] =
        cell("┐", popup.style.borderStyle)
    if popupRect.x < area.width and popupRect.y + popupRect.height - 1 < area.height:
      buf[popupRect.x, popupRect.y + popupRect.height - 1] =
        cell("└", popup.style.borderStyle)
    if popupRect.x + popupRect.width - 1 < area.width and
        popupRect.y + popupRect.height - 1 < area.height:
      buf[popupRect.x + popupRect.width - 1, popupRect.y + popupRect.height - 1] =
        cell("┘", popup.style.borderStyle)

  # Draw content
  let contentX =
    if popup.style.border:
      popupRect.x + 1
    else:
      popupRect.x
  let contentY =
    if popup.style.border:
      popupRect.y + 1
    else:
      popupRect.y
  var currentY = contentY

  # Draw title if present
  if popup.state.title.len > 0 and currentY < area.height:
    buf.setString(
      contentX,
      currentY,
      popup.state.title,
      popup.style.background.withModifiers({Bold}),
    )
    inc currentY

  # Draw content lines
  for line in popup.state.content:
    if currentY < area.height:
      buf.setString(contentX, currentY, line, popup.style.background)
      inc currentY

method render*(tooltip: Tooltip, area: Rect, buf: var Buffer) =
  ## Render the tooltip widget
  if not tooltip.state.visible or tooltip.state.text.len == 0:
    return

  let tooltipRect = tooltip.calculateTooltipRect(area)

  # Draw tooltip background and text
  let combinedStyle =
    style(tooltip.style.fg, tooltip.background.bg, tooltip.style.modifiers)
  buf.setString(tooltipRect.x, tooltipRect.y, tooltip.state.text, combinedStyle)

# Widget size methods
method getMinSize*(popup: Popup): Size =
  ## Get minimum size for popup
  size(popup.minWidth, 3) # Minimum for border + one line content

method getPreferredSize*(popup: Popup, available: Size): Size =
  ## Get preferred size for popup
  let titleLines = if popup.state.title.len > 0: 1 else: 0
  let contentWidth =
    if popup.state.content.len > 0:
      popup.state.content.mapIt(it.len).max()
    else:
      popup.minWidth
  let contentHeight = titleLines + popup.state.content.len

  let width = max(popup.minWidth, min(popup.maxWidth, contentWidth))
  let height = contentHeight + (if popup.style.border: 2 else: 0)

  size(width, height)

method getMinSize*(tooltip: Tooltip): Size =
  ## Get minimum size for tooltip
  size(1, 1)

method getPreferredSize*(tooltip: Tooltip, available: Size): Size =
  ## Get preferred size for tooltip
  size(tooltip.state.text.len, 1)
