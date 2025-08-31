## List widget
##
## This module provides list widgets for displaying and interacting with
## collections of items, with support for selection, scrolling, and styling.

import std/[sequtils, options, strutils, unicode]

import base
import ../core/[geometry, buffer, colors, events]

type
  ListState* = enum
    ## List visual states
    Normal
    Focused
    Disabled

  SelectionMode* = enum
    ## List selection behavior
    None # No selection support
    Single # Single item selection
    Multiple # Multiple item selection

  ListItem* = object ## Individual list item with optional custom style
    text*: string
    style*: Option[Style]
    selectable*: bool

  List* = ref object of Widget ## List widget for displaying items
    items*: seq[ListItem]
    state*: ListState
    selectionMode*: SelectionMode
    selectedIndices*: seq[int]
    highlightedIndex*: int # Currently highlighted item (keyboard navigation)
    scrollOffset*: int # First visible item index
    visibleCount*: int # Number of items visible at once
    # Styling
    normalStyle*: Style
    selectedStyle*: Style
    highlightedStyle*: Style
    disabledStyle*: Style
    bulletPrefix*: string # Optional prefix for items (e.g., "• ", "- ")
    showScrollbar*: bool
    # Event handlers
    onSelect*: proc(index: int) # Single selection callback
    onMultiSelect*: proc(indices: seq[int]) # Multiple selection callback
    onHighlight*: proc(index: int) # Highlight change callback

# List item constructors
proc newListItem*(
    text: string, style: Option[Style] = none(Style), selectable: bool = true
): ListItem =
  ## Create a new list item
  ListItem(text: text, style: style, selectable: selectable)

proc listItem*(text: string): ListItem =
  ## Convenience constructor for simple list item
  newListItem(text)

proc listItem*(text: string, style: Style): ListItem =
  ## Create a styled list item
  newListItem(text, some(style))

# List widget constructors
proc newList*(
    items: seq[ListItem] = @[],
    selectionMode: SelectionMode = Single,
    normalStyle: Style = defaultStyle(),
    selectedStyle: Style = style(Black, White),
    highlightedStyle: Style = style(White, BrightBlack),
    disabledStyle: Style = style(BrightBlack, Reset),
    bulletPrefix: string = "",
    showScrollbar: bool = true,
    onSelect: proc(index: int) = nil,
    onMultiSelect: proc(indices: seq[int]) = nil,
    onHighlight: proc(index: int) = nil,
): List =
  ## Create a new List widget
  List(
    items: items,
    state: Normal,
    selectionMode: selectionMode,
    selectedIndices: @[],
    highlightedIndex: if items.len > 0: 0 else: -1,
    scrollOffset: 0,
    visibleCount: 0,
    normalStyle: normalStyle,
    selectedStyle: selectedStyle,
    highlightedStyle: highlightedStyle,
    disabledStyle: disabledStyle,
    bulletPrefix: bulletPrefix,
    showScrollbar: showScrollbar,
    onSelect: onSelect,
    onMultiSelect: onMultiSelect,
    onHighlight: onHighlight,
  )

proc list*(items: seq[string], selectionMode: SelectionMode = Single): List =
  ## Convenience constructor for List widget from strings
  let listItems = items.mapIt(listItem(it))
  newList(listItems, selectionMode)

# List state management
proc setState*(widget: List, newState: ListState) =
  ## Set the list state
  widget.state = newState

proc setEnabled*(widget: List, enabled: bool) =
  ## Enable or disable the list
  widget.state = if enabled: Normal else: Disabled

proc isEnabled*(widget: List): bool =
  ## Check if the list is enabled
  widget.state != Disabled

# Item management
proc addItem*(widget: List, item: ListItem) =
  ## Add an item to the list
  widget.items.add(item)
  if widget.highlightedIndex < 0 and item.selectable:
    widget.highlightedIndex = widget.items.len - 1

proc addItem*(widget: List, text: string) =
  ## Add a simple text item to the list
  widget.addItem(listItem(text))

proc removeItem*(widget: List, index: int) =
  ## Remove an item from the list
  if index >= 0 and index < widget.items.len:
    widget.items.delete(index)
    # Adjust selection and highlight indices
    widget.selectedIndices = widget.selectedIndices.filterIt(it != index).mapIt(
        if it > index:
          it - 1
        else:
          it
      )
    if widget.highlightedIndex >= widget.items.len:
      widget.highlightedIndex = max(0, widget.items.len - 1)

proc clearItems*(widget: List) =
  ## Clear all items from the list
  widget.items = @[]
  widget.selectedIndices = @[]
  widget.highlightedIndex = -1
  widget.scrollOffset = 0

proc setItems*(widget: List, items: seq[ListItem]) =
  ## Replace all items in the list
  widget.items = items
  widget.selectedIndices = @[]
  widget.highlightedIndex = if items.len > 0: 0 else: -1
  widget.scrollOffset = 0

proc setItems*(widget: List, items: seq[string]) =
  ## Replace all items with simple text items
  widget.setItems(items.mapIt(listItem(it)))

# Selection management
proc selectItem*(widget: List, index: int) =
  ## Select an item (respecting selection mode)
  if index < 0 or index >= widget.items.len or not widget.items[index].selectable:
    return

  case widget.selectionMode
  of None:
    return
  of Single:
    widget.selectedIndices = @[index]
    if widget.onSelect != nil:
      widget.onSelect(index)
  of Multiple:
    if index notin widget.selectedIndices:
      widget.selectedIndices.add(index)
    if widget.onMultiSelect != nil:
      widget.onMultiSelect(widget.selectedIndices)

proc deselectItem*(widget: List, index: int) =
  ## Deselect an item (for multiple selection mode)
  if widget.selectionMode == Multiple:
    widget.selectedIndices = widget.selectedIndices.filterIt(it != index)
    if widget.onMultiSelect != nil:
      widget.onMultiSelect(widget.selectedIndices)

proc toggleSelection*(widget: List, index: int) =
  ## Toggle selection of an item
  if index < 0 or index >= widget.items.len or not widget.items[index].selectable:
    return

  if index in widget.selectedIndices:
    widget.deselectItem(index)
  else:
    widget.selectItem(index)

proc clearSelection*(widget: List) =
  ## Clear all selections
  widget.selectedIndices = @[]
  case widget.selectionMode
  of Multiple:
    if widget.onMultiSelect != nil:
      widget.onMultiSelect(@[])
  of Single:
    if widget.onSelect != nil:
      widget.onSelect(-1)
  else:
    discard

proc isSelected*(widget: List, index: int): bool =
  ## Check if an item is selected
  index in widget.selectedIndices

# Navigation
proc highlightNext*(widget: List) =
  ## Move highlight to next selectable item
  if widget.items.len == 0:
    return

  var newIndex = widget.highlightedIndex + 1
  while newIndex < widget.items.len:
    if widget.items[newIndex].selectable:
      widget.highlightedIndex = newIndex
      # Scroll if needed
      if newIndex >= widget.scrollOffset + widget.visibleCount:
        widget.scrollOffset = newIndex - widget.visibleCount + 1
      if widget.onHighlight != nil:
        widget.onHighlight(newIndex)
      break
    newIndex.inc()

proc highlightPrevious*(widget: List) =
  ## Move highlight to previous selectable item
  if widget.items.len == 0:
    return

  var newIndex = widget.highlightedIndex - 1
  while newIndex >= 0:
    if widget.items[newIndex].selectable:
      widget.highlightedIndex = newIndex
      # Scroll if needed
      if newIndex < widget.scrollOffset:
        widget.scrollOffset = newIndex
      if widget.onHighlight != nil:
        widget.onHighlight(newIndex)
      break
    newIndex.dec()

proc highlightFirst*(widget: List) =
  ## Move highlight to first selectable item
  for i in 0 ..< widget.items.len:
    if widget.items[i].selectable:
      widget.highlightedIndex = i
      widget.scrollOffset = 0
      if widget.onHighlight != nil:
        widget.onHighlight(i)
      break

proc highlightLast*(widget: List) =
  ## Move highlight to last selectable item
  for i in countdown(widget.items.len - 1, 0):
    if widget.items[i].selectable:
      widget.highlightedIndex = i
      if widget.visibleCount > 0:
        widget.scrollOffset = max(0, i - widget.visibleCount + 1)
      if widget.onHighlight != nil:
        widget.onHighlight(i)
      break

proc scrollUp*(widget: List, lines: int = 1) =
  ## Scroll the list up
  widget.scrollOffset = max(0, widget.scrollOffset - lines)

proc scrollDown*(widget: List, lines: int = 1) =
  ## Scroll the list down
  let maxScroll = max(0, widget.items.len - widget.visibleCount)
  widget.scrollOffset = min(maxScroll, widget.scrollOffset + lines)

proc pageUp*(widget: List) =
  ## Scroll up by one page
  if widget.visibleCount > 0:
    widget.scrollUp(widget.visibleCount)

proc pageDown*(widget: List) =
  ## Scroll down by one page
  if widget.visibleCount > 0:
    widget.scrollDown(widget.visibleCount)

# Event handling
proc handleKeyEvent*(widget: List, event: KeyEvent): bool =
  ## Handle keyboard input for the list
  ## Returns true if the event was handled
  if not widget.isEnabled():
    return false

  case event.code
  of ArrowUp:
    widget.highlightPrevious()
    return true
  of ArrowDown:
    widget.highlightNext()
    return true
  of Char:
    case event.char
    of 'k':
      widget.highlightPrevious()
      return true
    of 'j':
      widget.highlightNext()
      return true
    else:
      discard
  of Home:
    widget.highlightFirst()
    return true
  of End:
    widget.highlightLast()
    return true
  of PageUp:
    widget.pageUp()
    return true
  of PageDown:
    widget.pageDown()
    return true
  of Enter, Space:
    if widget.selectionMode != None and widget.highlightedIndex >= 0:
      if widget.selectionMode == Multiple and event.code == Space:
        widget.toggleSelection(widget.highlightedIndex)
      else:
        widget.selectItem(widget.highlightedIndex)
      return true
  else:
    discard

  return false

proc handleMouseEvent*(widget: List, event: MouseEvent, area: Rect): bool =
  ## Handle mouse input for the list
  ## Returns true if the event was handled
  if not widget.isEnabled():
    return false

  # Check if mouse is within list bounds for scrolling
  let inBounds =
    event.x >= area.x and event.x < area.x + area.width and event.y >= area.y and
    event.y < area.y + area.height

  # Handle wheel events (work even outside bounds for better UX)
  if event.kind == Press:
    if event.button == WheelUp:
      widget.scrollUp()
      return true
    elif event.button == WheelDown:
      widget.scrollDown()
      return true

  # Other events require mouse to be in bounds
  if not inBounds:
    return false

  let itemIndex = widget.scrollOffset + (event.y - area.y)

  if itemIndex >= 0 and itemIndex < widget.items.len and
      widget.items[itemIndex].selectable:
    case event.kind
    of Press:
      if event.button == Left:
        widget.highlightedIndex = itemIndex
        if widget.onHighlight != nil:
          widget.onHighlight(itemIndex)
        return true
    of Release:
      if event.button == Left:
        if widget.selectionMode != None:
          if widget.selectionMode == Multiple and event.modifiers.contains(Ctrl):
            widget.toggleSelection(itemIndex)
          else:
            widget.selectItem(itemIndex)
        return true
    else:
      discard

  return false

# Rendering utilities
proc getItemStyle*(widget: List, index: int): Style =
  ## Get the style for a specific item
  if widget.state == Disabled:
    return widget.disabledStyle

  # Custom item style takes precedence
  if widget.items[index].style.isSome:
    return widget.items[index].style.get()

  # Then selection/highlight styles
  let isSelected = index in widget.selectedIndices
  let isHighlighted = index == widget.highlightedIndex and widget.state == Focused

  if isSelected and isHighlighted:
    # Combine styles - use selected background with highlighted foreground
    return style(
      widget.highlightedStyle.fg, widget.selectedStyle.bg,
      widget.selectedStyle.modifiers,
    )
  elif isSelected:
    return widget.selectedStyle
  elif isHighlighted:
    return widget.highlightedStyle
  else:
    return widget.normalStyle

proc renderScrollbar*(widget: List, area: Rect, buf: var Buffer) =
  ## Render a scrollbar on the right edge
  if not widget.showScrollbar or widget.items.len <= widget.visibleCount:
    return

  let scrollbarX = area.x + area.width - 1
  let totalItems = widget.items.len
  let scrollbarHeight = area.height

  # Calculate thumb size and position
  let thumbSize = max(1, (widget.visibleCount * scrollbarHeight) div totalItems)
  let thumbPos =
    if totalItems > widget.visibleCount:
      (widget.scrollOffset * (scrollbarHeight - thumbSize)) div
        (totalItems - widget.visibleCount)
    else:
      0

  # Draw scrollbar track and thumb
  for y in 0 ..< scrollbarHeight:
    let isThumb = y >= thumbPos and y < thumbPos + thumbSize
    let char = if isThumb: "█" else: "│"
    let style =
      if isThumb:
        style(White, BrightBlack)
      else:
        style(BrightBlack)
    buf.setString(scrollbarX, area.y + y, char, style)

# List widget methods
method render*(widget: List, area: Rect, buf: var Buffer) =
  ## Render the list widget
  if area.isEmpty:
    return

  # Update visible count
  widget.visibleCount = area.height

  # Ensure scroll offset is valid
  let maxScroll = max(0, widget.items.len - widget.visibleCount)
  widget.scrollOffset = min(widget.scrollOffset, maxScroll)

  # Calculate content area (accounting for scrollbar)
  let contentWidth =
    if widget.showScrollbar and widget.items.len > widget.visibleCount:
      area.width - 1
    else:
      area.width

  # Render visible items
  for i in 0 ..< widget.visibleCount:
    let itemIndex = widget.scrollOffset + i
    if itemIndex >= widget.items.len:
      # Clear remaining lines
      buf.setString(area.x, area.y + i, " ".repeat(contentWidth), widget.normalStyle)
      continue

    let item = widget.items[itemIndex]
    let itemStyle = widget.getItemStyle(itemIndex)

    # Prepare item text with optional bullet
    var itemText = widget.bulletPrefix & item.text

    # Truncate or pad to fit width
    if itemText.runeLen > contentWidth:
      itemText = itemText.runeSubStr(0, contentWidth - 3) & "..."
    else:
      itemText = itemText & " ".repeat(contentWidth - itemText.runeLen)

    buf.setString(area.x, area.y + i, itemText, itemStyle)

  # Render scrollbar if needed
  widget.renderScrollbar(area, buf)

method getMinSize*(widget: List): Size =
  ## Get minimum size for list widget
  # Minimum: show at least one item
  let minWidth =
    if widget.bulletPrefix.len > 0:
      widget.bulletPrefix.runeLen + 10
    else:
      10
  size(minWidth, 1)

method getPreferredSize*(widget: List, available: Size): Size =
  ## Get preferred size for list widget
  # Prefer to show all items if possible, otherwise use available space
  let preferredHeight = min(widget.items.len, available.height)
  let maxItemWidth =
    widget.items.mapIt(widget.bulletPrefix.runeLen + it.text.runeLen).max()
  let preferredWidth =
    min(maxItemWidth + (if widget.showScrollbar: 1 else: 0), available.width)
  size(preferredWidth, preferredHeight)

method canFocus*(widget: List): bool =
  ## Lists can receive focus when enabled and have selectable items
  widget.isEnabled() and widget.items.anyIt(it.selectable)

# List widget builders and modifiers
proc withItems*(widget: List, items: seq[ListItem]): List =
  ## Create a copy with different items
  result = List(
    items: items,
    state: widget.state,
    selectionMode: widget.selectionMode,
    selectedIndices: @[],
    highlightedIndex: if items.len > 0: 0 else: -1,
    scrollOffset: 0,
    visibleCount: widget.visibleCount,
    normalStyle: widget.normalStyle,
    selectedStyle: widget.selectedStyle,
    highlightedStyle: widget.highlightedStyle,
    disabledStyle: widget.disabledStyle,
    bulletPrefix: widget.bulletPrefix,
    showScrollbar: widget.showScrollbar,
    onSelect: widget.onSelect,
    onMultiSelect: widget.onMultiSelect,
    onHighlight: widget.onHighlight,
  )

proc withSelectionMode*(widget: List, mode: SelectionMode): List =
  ## Create a copy with different selection mode
  result = List(
    items: widget.items,
    state: widget.state,
    selectionMode: mode,
    selectedIndices:
      if mode == Single and widget.selectedIndices.len > 0:
        @[widget.selectedIndices[0]]
      elif mode == None:
        @[]
      else:
        widget.selectedIndices,
    highlightedIndex: widget.highlightedIndex,
    scrollOffset: widget.scrollOffset,
    visibleCount: widget.visibleCount,
    normalStyle: widget.normalStyle,
    selectedStyle: widget.selectedStyle,
    highlightedStyle: widget.highlightedStyle,
    disabledStyle: widget.disabledStyle,
    bulletPrefix: widget.bulletPrefix,
    showScrollbar: widget.showScrollbar,
    onSelect: widget.onSelect,
    onMultiSelect: widget.onMultiSelect,
    onHighlight: widget.onHighlight,
  )

proc withStyles*(
    widget: List,
    normal: Style = defaultStyle(),
    selected: Style = defaultStyle(),
    highlighted: Style = defaultStyle(),
    disabled: Style = defaultStyle(),
): List =
  ## Create a copy with different styles
  result = List(
    items: widget.items,
    state: widget.state,
    selectionMode: widget.selectionMode,
    selectedIndices: widget.selectedIndices,
    highlightedIndex: widget.highlightedIndex,
    scrollOffset: widget.scrollOffset,
    visibleCount: widget.visibleCount,
    normalStyle: if normal == defaultStyle(): widget.normalStyle else: normal,
    selectedStyle: if selected == defaultStyle(): widget.selectedStyle else: selected,
    highlightedStyle:
      if highlighted == defaultStyle(): widget.highlightedStyle else: highlighted,
    disabledStyle: if disabled == defaultStyle(): widget.disabledStyle else: disabled,
    bulletPrefix: widget.bulletPrefix,
    showScrollbar: widget.showScrollbar,
    onSelect: widget.onSelect,
    onMultiSelect: widget.onMultiSelect,
    onHighlight: widget.onHighlight,
  )

proc withBulletPrefix*(widget: List, prefix: string): List =
  ## Create a copy with different bullet prefix
  result = List(
    items: widget.items,
    state: widget.state,
    selectionMode: widget.selectionMode,
    selectedIndices: widget.selectedIndices,
    highlightedIndex: widget.highlightedIndex,
    scrollOffset: widget.scrollOffset,
    visibleCount: widget.visibleCount,
    normalStyle: widget.normalStyle,
    selectedStyle: widget.selectedStyle,
    highlightedStyle: widget.highlightedStyle,
    disabledStyle: widget.disabledStyle,
    bulletPrefix: prefix,
    showScrollbar: widget.showScrollbar,
    onSelect: widget.onSelect,
    onMultiSelect: widget.onMultiSelect,
    onHighlight: widget.onHighlight,
  )

proc withScrollbar*(widget: List, show: bool): List =
  ## Create a copy with scrollbar visibility setting
  result = List(
    items: widget.items,
    state: widget.state,
    selectionMode: widget.selectionMode,
    selectedIndices: widget.selectedIndices,
    highlightedIndex: widget.highlightedIndex,
    scrollOffset: widget.scrollOffset,
    visibleCount: widget.visibleCount,
    normalStyle: widget.normalStyle,
    selectedStyle: widget.selectedStyle,
    highlightedStyle: widget.highlightedStyle,
    disabledStyle: widget.disabledStyle,
    bulletPrefix: widget.bulletPrefix,
    showScrollbar: show,
    onSelect: widget.onSelect,
    onMultiSelect: widget.onMultiSelect,
    onHighlight: widget.onHighlight,
  )

# Convenience constructors for common list types
proc simpleList*(items: seq[string]): List =
  ## Create a simple list with no selection
  list(items, None)

proc selectList*(items: seq[string], onSelect: proc(index: int) = nil): List =
  ## Create a single-selection list
  newList(items.mapIt(listItem(it)), Single, onSelect = onSelect)

proc checkList*(
    items: seq[string], onMultiSelect: proc(indices: seq[int]) = nil
): List =
  ## Create a multiple-selection checklist
  newList(
    items.mapIt(listItem(it)),
    Multiple,
    bulletPrefix = "[ ] ",
    onMultiSelect = onMultiSelect,
  )

proc bulletList*(items: seq[string], bullet: string = "• "): List =
  ## Create a bulleted list
  newList(items.mapIt(listItem(it)), None, bulletPrefix = bullet)
