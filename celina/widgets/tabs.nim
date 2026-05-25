## Tab widget for Celina CLI library
##
## This module provides a tabbed interface widget that allows switching between
## multiple content panels.

import std/[strutils, sequtils]

import base, text

import ../core/[geometry, buffer, colors]

type
  TabPosition* = enum
    ## Position of the tab bar
    Top
    Bottom

  TabStyle* = object ## Styling for tabs
    activeStyle*: Style
    inactiveStyle*: Style
    borderStyle*: Style
    dividerChar*: string

  Tab* = object ## Individual tab data
    title*: string
    content*: Widget

  Tabs* = ref object of Widget
    ## Tab widget that displays multiple tabs with switchable content
    tabs*: seq[Tab]
    activeIndex*: int
    position*: TabPosition
    tabStyle*: TabStyle
    showBorder*: bool

# Default tab styles
proc defaultTabStyle*(): TabStyle =
  ## Create default tab styling
  TabStyle(
    activeStyle: style(White, Blue),
    inactiveStyle: style(BrightBlack),
    borderStyle: style(BrightBlack),
    dividerChar: "│",
  )

# Tab widget constructors
proc newTabs*(
    tabs: seq[Tab] = @[],
    activeIndex: int = 0,
    position: TabPosition = Top,
    tabStyle: TabStyle = defaultTabStyle(),
    showBorder: bool = true,
): Tabs =
  ## Create a new Tabs widget
  Tabs(
    tabs: tabs,
    activeIndex: max(0, min(activeIndex, tabs.len - 1)),
    position: position,
    tabStyle: tabStyle,
    showBorder: showBorder,
  )

proc tabs*(
    tabs: seq[Tab],
    activeIndex: int = 0,
    position: TabPosition = Top,
    tabStyle: TabStyle = defaultTabStyle(),
    showBorder: bool = true,
): Tabs =
  ## Convenience constructor for Tabs widget
  newTabs(tabs, activeIndex, position, tabStyle, showBorder)

proc tab*(title: string, content: Widget): Tab =
  ## Create a single tab
  Tab(title: title, content: content)

# Tab management methods
proc addTab*(widget: Tabs, title: string, content: Widget) =
  ## Add a new tab
  widget.tabs.add(Tab(title: title, content: content))

proc removeTab*(widget: Tabs, index: int) =
  ## Remove a tab at the given index
  if index >= 0 and index < widget.tabs.len:
    widget.tabs.delete(index)
    # Adjust active index if necessary
    if widget.tabs.len == 0:
      widget.activeIndex = 0
    elif index <= widget.activeIndex:
      # If we removed a tab before or at the active tab, adjust the index
      if widget.activeIndex > 0:
        widget.activeIndex -= 1
      # If we removed the last tab and active was pointing to it
      if widget.activeIndex >= widget.tabs.len:
        widget.activeIndex = widget.tabs.len - 1

proc setActiveTab*(widget: Tabs, index: int) =
  ## Set the active tab
  if index >= 0 and index < widget.tabs.len:
    widget.activeIndex = index

proc nextTab*(widget: Tabs) =
  ## Switch to the next tab (with wrapping)
  if widget.tabs.len > 0:
    widget.activeIndex = (widget.activeIndex + 1) mod widget.tabs.len

proc prevTab*(widget: Tabs) =
  ## Switch to the previous tab (with wrapping)
  if widget.tabs.len > 0:
    widget.activeIndex = (widget.activeIndex - 1 + widget.tabs.len) mod widget.tabs.len

# Helper functions for rendering
proc calculateTabWidths(titles: seq[string], availableWidth: int): seq[int] =
  ## Calculate the width for each tab
  if titles.len == 0 or availableWidth <= 0:
    return @[]

  let totalDividers = max(0, titles.len - 1)
  let minTabWidth = max(1, 3) # Minimum space for "..." but at least 1
  var widths = newSeq[int](titles.len)

  # Handle extreme cases
  if availableWidth < totalDividers + titles.len:
    # Not enough space even for minimum widths
    for i in 0 ..< titles.len:
      widths[i] = 1
    return widths

  # Calculate natural widths (title + padding)
  var naturalWidths = newSeq[int](titles.len)
  var totalNaturalWidth = 0

  for i, title in titles:
    # Add padding, ensure minimum
    naturalWidths[i] = max(minTabWidth, title.displayWidth + 2)
    totalNaturalWidth += naturalWidths[i]

  totalNaturalWidth += totalDividers # Account for dividers

  if totalNaturalWidth <= availableWidth:
    # All tabs fit naturally
    widths = naturalWidths
  else:
    # Need to shrink tabs
    let availableForTabs = availableWidth - totalDividers
    let evenWidth = availableForTabs div titles.len

    if evenWidth >= minTabWidth:
      # Distribute evenly
      for i in 0 ..< titles.len:
        widths[i] = evenWidth
      # Distribute remainder
      let remainder = availableForTabs mod titles.len
      for i in 0 ..< remainder:
        widths[i] += 1
    else:
      # Not enough space, use minimum widths
      for i in 0 ..< titles.len:
        widths[i] = minTabWidth

  # Final bounds check
  for i in 0 ..< widths.len:
    widths[i] = max(1, widths[i])

  widths

proc truncateTitle(title: string, width: int): string =
  ## Truncate a title to fit within the given width
  if title.displayWidth <= width:
    return title

  if width <= 3:
    return "...".truncateToWidth(width)

  title.truncateToWidth(width - 3) & "..."

proc renderTabBar(widget: Tabs, area: Rect, buf: var Buffer): int =
  ## Render the tab bar and return the height used
  if widget == nil or widget.tabs.len == 0 or area.isEmpty or area.width <= 0 or
      area.height <= 0:
    return 0

  let titles = widget.tabs.mapIt(it.title)
  let widths = calculateTabWidths(titles, area.width)

  # Safety check for widths array
  if widths.len != titles.len:
    return 0

  var x = area.x
  let y =
    if widget.position == Top:
      area.y
    else:
      area.y + area.height - 1

  # Bounds check for y coordinate
  if y < 0 or y >= buf.area.height:
    return 0

  for i, tab in widget.tabs:
    if x >= area.x + area.width or i >= widths.len:
      break # No more space or invalid index

    let width = max(1, widths[i]) # Ensure positive width
    let availablePadding = max(0, width - 2) # Available space for title after padding
    let truncated = truncateTitle(tab.title, availablePadding)
    let rawPadded =
      if width >= 3:
        " " & truncated & " ".repeat(max(0, width - truncated.displayWidth - 2)) & " "
      elif width == 2:
        " " & (if truncated.len > 0: truncated.truncateToWidth(1)
        else: " ")
      else:
        if truncated.len > 0:
          truncated.truncateToWidth(1)
        else:
          " "
    # Fill any remaining width when a wide character was dropped during truncation
    let padded = rawPadded & " ".repeat(max(0, width - rawPadded.displayWidth))

    let style =
      if i == widget.activeIndex:
        widget.tabStyle.activeStyle
      else:
        widget.tabStyle.inactiveStyle

    # Bounds check before writing
    let finalString =
      if padded.len > 0:
        padded.truncateToWidth(width)
      else:
        " "
    if x >= 0 and y >= 0 and x < buf.area.width and y < buf.area.height and
        finalString.len > 0:
      buf.setString(x, y, finalString, style)

    x += width

    # Draw divider with bounds checking
    if i < widget.tabs.len - 1 and x >= 0 and y >= 0 and x < area.x + area.width and
        x < buf.area.width and y < buf.area.height and
        widget.tabStyle.dividerChar.len > 0:
      buf.setString(x, y, widget.tabStyle.dividerChar, widget.tabStyle.borderStyle)
      x += 1

  return 1

proc renderBorder(widget: Tabs, area: Rect, tabBarY: int, buf: var Buffer) =
  ## Render the border around the content area
  if not widget.showBorder or area.isEmpty or area.width < 2 or area.height < 2:
    return

  let contentTop =
    if widget.position == Top:
      area.y + 1
    else:
      area.y
  let contentBottom =
    if widget.position == Top:
      area.y + area.height - 1
    else:
      area.y + area.height - 2

  # Bounds validation
  if contentTop < 0 or contentBottom >= buf.area.height or contentTop >= contentBottom:
    return
  if area.x < 0 or area.x + area.width > buf.area.width:
    return

  # Top border
  if widget.position == Bottom or contentTop != tabBarY:
    if contentTop >= 0 and contentTop < buf.area.height:
      for x in max(0, area.x) ..< min(buf.area.width, area.x + area.width):
        buf.setString(x, contentTop, "─", widget.tabStyle.borderStyle)

  # Bottom border
  if widget.position == Top or contentBottom != tabBarY:
    if contentBottom >= 0 and contentBottom < buf.area.height:
      for x in max(0, area.x) ..< min(buf.area.width, area.x + area.width):
        buf.setString(x, contentBottom, "─", widget.tabStyle.borderStyle)

  # Left border
  if area.x >= 0 and area.x < buf.area.width:
    for y in max(0, contentTop + 1) ..< min(buf.area.height, contentBottom):
      buf.setString(area.x, y, "│", widget.tabStyle.borderStyle)

  # Right border
  let rightX = area.x + area.width - 1
  if rightX >= 0 and rightX < buf.area.width:
    for y in max(0, contentTop + 1) ..< min(buf.area.height, contentBottom):
      buf.setString(rightX, y, "│", widget.tabStyle.borderStyle)

  # Corners with bounds checking
  if area.x >= 0 and area.x < buf.area.width and contentTop >= 0 and
      contentTop < buf.area.height:
    buf.setString(area.x, contentTop, "┌", widget.tabStyle.borderStyle)
  if rightX >= 0 and rightX < buf.area.width and contentTop >= 0 and
      contentTop < buf.area.height:
    buf.setString(rightX, contentTop, "┐", widget.tabStyle.borderStyle)
  if area.x >= 0 and area.x < buf.area.width and contentBottom >= 0 and
      contentBottom < buf.area.height:
    buf.setString(area.x, contentBottom, "└", widget.tabStyle.borderStyle)
  if rightX >= 0 and rightX < buf.area.width and contentBottom >= 0 and
      contentBottom < buf.area.height:
    buf.setString(rightX, contentBottom, "┘", widget.tabStyle.borderStyle)

  # Connect tab bar to border (for active tab)
  # Note: We keep the border intact for a cleaner look
  # The active tab is distinguished by its background color only

proc computeContentArea(widget: Tabs, area: Rect, tabBarHeight: int): Rect =
  ## Shared layout: shrink `area` by `tabBarHeight` on the bar side and,
  ## when `showBorder` is enabled and the remaining height has room, by
  ## one cell on each border edge.
  if area.isEmpty or widget.tabs.len == 0:
    return Rect(x: area.x, y: area.y, width: 0, height: 0)

  var content = area
  if widget.position == Top:
    content.y += tabBarHeight
    content.height = max(0, content.height - tabBarHeight)
  else:
    content.height = max(0, content.height - tabBarHeight)

  if widget.showBorder and content.height > 2:
    content.x += 1
    content.y += 1
    content.width = max(0, content.width - 2)
    content.height = max(0, content.height - 2)

  content

# Tab widget methods
method render*(widget: Tabs, area: Rect, buf: var Buffer) =
  ## Render the tabs widget
  if area.isEmpty or widget.tabs.len == 0:
    return

  # Render tab bar
  let tabBarHeight = renderTabBar(widget, area, buf)

  # Compute content area (pre-border) to decide if borders fit
  let preBorderContent =
    if widget.position == Top:
      Rect(
        x: area.x,
        y: area.y + tabBarHeight,
        width: area.width,
        height: max(0, area.height - tabBarHeight),
      )
    else:
      Rect(
        x: area.x,
        y: area.y,
        width: area.width,
        height: max(0, area.height - tabBarHeight),
      )

  # Render border if enabled
  if widget.showBorder and preBorderContent.height > 2:
    renderBorder(
      widget,
      area,
      if widget.position == Top:
        area.y
      else:
        area.y + area.height - 1,
      buf,
    )

  let contentArea = widget.computeContentArea(area, tabBarHeight)

  # Render active tab content
  if widget.activeIndex < widget.tabs.len and not contentArea.isEmpty:
    let activeTab = widget.tabs[widget.activeIndex]
    if activeTab.content != nil:
      activeTab.content.render(contentArea, buf)

method getMinSize*(widget: Tabs): Size =
  ## Get minimum size for tabs widget
  var minWidth = 10 # Minimum for tab bar
  var minHeight = 1 # Tab bar height

  if widget.showBorder:
    minHeight += 2 # Top and bottom borders
    minWidth = max(minWidth, 4) # Left and right borders

  # Consider content minimum sizes
  for tab in widget.tabs:
    if tab.content != nil:
      let contentMin = tab.content.getMinSize()
      minWidth = max(minWidth, contentMin.width + (if widget.showBorder: 2 else: 0))
      minHeight =
        max(minHeight, contentMin.height + 1 + (if widget.showBorder: 2 else: 0))

  size(minWidth, minHeight)

method getPreferredSize*(widget: Tabs, available: Size): Size =
  ## Get preferred size for tabs widget
  available # Use all available space by default

method canFocus*(widget: Tabs): bool =
  ## Tabs widget can receive focus for keyboard navigation
  true

func tabBarHeight*(widget: Tabs): int =
  ## Height of the tab bar row (1 when tabs exist, 0 otherwise).
  if widget.tabs.len > 0: 1 else: 0

proc contentArea*(widget: Tabs, area: Rect): Rect =
  ## Compute the rect where the active tab's content is rendered. Shares
  ## its layout logic with `render` via `computeContentArea`, so event
  ## dispatch and hit testing stay in sync with what's drawn.
  widget.computeContentArea(area, widget.tabBarHeight())

proc tabBarRect*(widget: Tabs, area: Rect): Rect =
  ## The 1-row strip where tab headings are drawn. Empty rect when there
  ## are no tabs or the area is empty.
  if area.isEmpty or widget.tabs.len == 0:
    return rect(area.x, area.y, 0, 0)
  let y =
    if widget.position == Top:
      area.y
    else:
      area.y + area.height - 1
  rect(area.x, y, area.width, 1)

proc tabIndexAt*(widget: Tabs, area: Rect, x, y: int): int =
  ## Hit-test the tab bar: return the tab index at `(x, y)`, or `-1` if
  ## the point is outside the bar, on a divider, or beyond the last tab.
  ## Mirrors the layout produced by `renderTabBar`.
  let bar = widget.tabBarRect(area)
  if bar.width <= 0 or bar.height <= 0 or not bar.contains(x, y):
    return -1
  let titles = widget.tabs.mapIt(it.title)
  let widths = calculateTabWidths(titles, area.width)
  if widths.len != widget.tabs.len:
    return -1
  var cur = area.x
  for i, w in widths:
    if x >= cur and x < cur + w:
      return i
    cur += w
    # Divider cell between tabs is not part of any tab.
    if i < widget.tabs.len - 1:
      if x == cur:
        return -1
      cur += 1
  -1

method handleEvent*(widget: Tabs, event: Event, area: Rect): EventResult =
  ## Tabs event dispatch:
  ##
  ## 1. Tab / Shift+Tab cycles the active tab (consumed).
  ## 2. Left-button press on the tab bar selects that tab (consumed).
  ## 3. Other events are forwarded to the active tab's `content` widget,
  ##    with the computed content area so child mouse hit-testing works.
  if widget.tabs.len == 0:
    return erContinue

  if event.kind == EventKind.Key:
    let key = event.key
    case key.code
    of KeyCode.Tab:
      if Shift in key.modifiers:
        widget.prevTab()
      else:
        widget.nextTab()
      return erConsume
    of KeyCode.BackTab:
      widget.prevTab()
      return erConsume
    else:
      discard

  if event.kind == EventKind.Mouse:
    let m = event.mouse
    if m.kind == MouseEventKind.Press and m.button == MouseButton.Left:
      let idx = widget.tabIndexAt(area, m.x, m.y)
      if idx >= 0:
        widget.setActiveTab(idx)
        return erConsume

  if widget.activeIndex >= 0 and widget.activeIndex < widget.tabs.len:
    let active = widget.tabs[widget.activeIndex].content
    if active != nil:
      return active.handleEvent(event, widget.contentArea(area))

  erContinue

# Builder methods
proc withStyle*(widget: Tabs, tabStyle: TabStyle): Tabs =
  ## Create a copy with different styling
  Tabs(
    tabs: widget.tabs,
    activeIndex: widget.activeIndex,
    position: widget.position,
    tabStyle: tabStyle,
    showBorder: widget.showBorder,
  )

proc withPosition*(widget: Tabs, position: TabPosition): Tabs =
  ## Create a copy with different tab position
  Tabs(
    tabs: widget.tabs,
    activeIndex: widget.activeIndex,
    position: position,
    tabStyle: widget.tabStyle,
    showBorder: widget.showBorder,
  )

proc withBorder*(widget: Tabs, showBorder: bool): Tabs =
  ## Create a copy with border enabled/disabled
  Tabs(
    tabs: widget.tabs,
    activeIndex: widget.activeIndex,
    position: widget.position,
    tabStyle: widget.tabStyle,
    showBorder: showBorder,
  )

# Convenience constructors
proc simpleTabs*(titles: seq[string], contents: seq[Widget]): Tabs =
  ## Create tabs from title and content sequences
  var tabs = newSeq[Tab]()
  for i in 0 ..< min(titles.len, contents.len):
    tabs.add(Tab(title: titles[i], content: contents[i]))
  newTabs(tabs)

proc textTabs*(items: seq[(string, string)]): Tabs =
  ## Create tabs with text content
  var tabs = newSeq[Tab]()
  for (title, content) in items:
    let textWidget = Text(content: content, style: defaultStyle())
    tabs.add(Tab(title: title, content: textWidget))
  newTabs(tabs)
