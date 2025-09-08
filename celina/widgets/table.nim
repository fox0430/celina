## Table widget
##
## This module provides table widgets for displaying structured data in rows
## and columns, with support for headers, selection, scrolling, and styling.

import std/[sequtils, options, strutils, unicode]

import base
import ../core/[geometry, buffer, colors, events]

type
  ColumnAlignment* = enum
    ## Column text alignment options
    AlignLeft
    AlignCenter
    AlignRight

  Column* = object ## Table column definition
    title*: string
    width*: Option[int] # Fixed width or auto-size
    alignment*: ColumnAlignment
    style*: Option[Style]

  TableRow* = object ## Table row data
    cells*: seq[string]
    style*: Option[Style] # Optional row-level styling
    selectable*: bool

  SelectionMode* = enum
    ## Table selection behavior
    None # No selection support
    Single # Single row selection
    Multiple # Multiple row selection

  BorderStyle* = enum
    ## Table border drawing style
    NoBorder
    SimpleBorder # Basic ASCII borders: |-+
    RoundedBorder # Unicode rounded borders
    DoubleBorder # Unicode double-line borders

  Table* = ref object of Widget ## Table widget for structured data
    columns*: seq[Column]
    rows*: seq[TableRow]
    # Selection and navigation
    selectionMode*: SelectionMode
    selectedIndices*: seq[int]
    highlightedIndex*: int # Currently highlighted row
    scrollOffset*: int # First visible row index
    visibleRowCount*: int # Number of data rows visible
    # Display options
    showHeader*: bool
    borderStyle*: BorderStyle
    columnSpacing*: int # Space between columns
    showScrollbar*: bool
    # Styling
    headerStyle*: Style
    normalRowStyle*: Style
    selectedRowStyle*: Style
    highlightedRowStyle*: Style
    borderStyleOptions*: Style
    # Event handlers
    onSelect*: proc(index: int)
    onMultiSelect*: proc(indices: seq[int])
    onHighlight*: proc(index: int)

# Column constructors
proc newColumn*(
    title: string,
    width: Option[int] = none(int),
    alignment: ColumnAlignment = AlignLeft,
    style: Option[Style] = none(Style),
): Column =
  ## Create a new table column
  Column(title: title, width: width, alignment: alignment, style: style)

proc column*(title: string): Column =
  ## Convenience constructor for simple column
  newColumn(title)

proc column*(title: string, width: int): Column =
  ## Create column with fixed width
  newColumn(title, some(width))

proc column*(title: string, alignment: ColumnAlignment): Column =
  ## Create column with specific alignment
  newColumn(title, alignment = alignment)

# Row constructors
proc newTableRow*(
    cells: seq[string], style: Option[Style] = none(Style), selectable: bool = true
): TableRow =
  ## Create a new table row
  TableRow(cells: cells, style: style, selectable: selectable)

proc tableRow*(cells: seq[string]): TableRow =
  ## Convenience constructor for simple row
  newTableRow(cells)

proc tableRow*(cells: seq[string], style: Style): TableRow =
  ## Create styled row
  newTableRow(cells, some(style))

# Table widget constructors
proc newTable*(
    columns: seq[Column] = @[],
    rows: seq[TableRow] = @[],
    selectionMode: SelectionMode = Single,
    showHeader: bool = true,
    borderStyle: BorderStyle = SimpleBorder,
    columnSpacing: int = 1,
    showScrollbar: bool = true,
    headerStyle: Style = style(White, BrightBlack),
    normalRowStyle: Style = defaultStyle(),
    selectedRowStyle: Style = style(Black, White),
    highlightedRowStyle: Style = style(White, BrightBlack),
    borderStyleOptions: Style = style(BrightBlack),
    onSelect: proc(index: int) = nil,
    onMultiSelect: proc(indices: seq[int]) = nil,
    onHighlight: proc(index: int) = nil,
): Table =
  ## Create a new Table widget
  Table(
    columns: columns,
    rows: rows,
    selectionMode: selectionMode,
    selectedIndices: @[],
    highlightedIndex: if rows.len > 0: 0 else: -1,
    scrollOffset: 0,
    visibleRowCount: 0,
    showHeader: showHeader,
    borderStyle: borderStyle,
    columnSpacing: columnSpacing,
    showScrollbar: showScrollbar,
    headerStyle: headerStyle,
    normalRowStyle: normalRowStyle,
    selectedRowStyle: selectedRowStyle,
    highlightedRowStyle: highlightedRowStyle,
    borderStyleOptions: borderStyleOptions,
    onSelect: onSelect,
    onMultiSelect: onMultiSelect,
    onHighlight: onHighlight,
  )

proc table*(columns: seq[string]): Table =
  ## Convenience constructor from column titles
  let cols = columns.mapIt(column(it))
  newTable(cols)

proc table*(columns: seq[string], rows: seq[seq[string]]): Table =
  ## Convenience constructor from column titles and row data
  let cols = columns.mapIt(column(it))
  let tableRows = rows.mapIt(tableRow(it))
  newTable(cols, tableRows)

# Column management
proc addColumn*(widget: Table, col: Column) =
  ## Add a column to the table
  widget.columns.add(col)

proc addColumn*(widget: Table, title: string, width: Option[int] = none(int)) =
  ## Add a simple column to the table
  widget.addColumn(newColumn(title, width))

proc removeColumn*(widget: Table, index: int) =
  ## Remove a column from the table
  if index >= 0 and index < widget.columns.len:
    widget.columns.delete(index)
    # Remove corresponding cells from all rows
    for row in widget.rows.mitems:
      if index < row.cells.len:
        row.cells.delete(index)

# Row management
proc addRow*(widget: Table, row: TableRow) =
  ## Add a row to the table
  widget.rows.add(row)
  if widget.highlightedIndex < 0 and row.selectable:
    widget.highlightedIndex = widget.rows.len - 1

proc addRow*(widget: Table, cells: seq[string]) =
  ## Add a simple row to the table
  widget.addRow(tableRow(cells))

proc removeRow*(widget: Table, index: int) =
  ## Remove a row from the table
  if index >= 0 and index < widget.rows.len:
    widget.rows.delete(index)
    # Adjust selection and highlight indices
    widget.selectedIndices = widget.selectedIndices.filterIt(it != index).mapIt(
        if it > index:
          it - 1
        else:
          it
      )
    if widget.highlightedIndex >= widget.rows.len:
      widget.highlightedIndex = max(0, widget.rows.len - 1)

proc clearRows*(widget: Table) =
  ## Clear all rows from the table
  widget.rows = @[]
  widget.selectedIndices = @[]
  widget.highlightedIndex = -1
  widget.scrollOffset = 0

proc setData*(widget: Table, rows: seq[seq[string]]) =
  ## Replace all row data
  widget.rows = rows.mapIt(tableRow(it))
  widget.selectedIndices = @[]
  widget.highlightedIndex = if rows.len > 0: 0 else: -1
  widget.scrollOffset = 0

# Selection management
proc selectRow*(widget: Table, index: int) =
  ## Select a row (respecting selection mode)
  if index < 0 or index >= widget.rows.len or not widget.rows[index].selectable:
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

proc deselectRow*(widget: Table, index: int) =
  ## Deselect a row (for multiple selection mode)
  if widget.selectionMode == Multiple:
    widget.selectedIndices = widget.selectedIndices.filterIt(it != index)
    if widget.onMultiSelect != nil:
      widget.onMultiSelect(widget.selectedIndices)

proc toggleSelection*(widget: Table, index: int) =
  ## Toggle selection of a row
  if index < 0 or index >= widget.rows.len or not widget.rows[index].selectable:
    return

  if index in widget.selectedIndices:
    widget.deselectRow(index)
  else:
    widget.selectRow(index)

proc clearSelection*(widget: Table) =
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

proc isSelected*(widget: Table, index: int): bool =
  ## Check if a row is selected
  index in widget.selectedIndices

# Navigation
proc highlightNext*(widget: Table) =
  ## Move highlight to next selectable row
  if widget.rows.len == 0:
    return

  var newIndex = widget.highlightedIndex + 1
  while newIndex < widget.rows.len:
    if widget.rows[newIndex].selectable:
      widget.highlightedIndex = newIndex
      # Scroll if needed
      if newIndex >= widget.scrollOffset + widget.visibleRowCount:
        widget.scrollOffset = newIndex - widget.visibleRowCount + 1
      if widget.onHighlight != nil:
        widget.onHighlight(newIndex)
      break
    newIndex.inc()

proc highlightPrevious*(widget: Table) =
  ## Move highlight to previous selectable row
  if widget.rows.len == 0:
    return

  var newIndex = widget.highlightedIndex - 1
  while newIndex >= 0:
    if widget.rows[newIndex].selectable:
      widget.highlightedIndex = newIndex
      # Scroll if needed
      if newIndex < widget.scrollOffset:
        widget.scrollOffset = newIndex
      if widget.onHighlight != nil:
        widget.onHighlight(newIndex)
      break
    newIndex.dec()

proc scrollUp*(widget: Table, lines: int = 1) =
  ## Scroll the table up
  widget.scrollOffset = max(0, widget.scrollOffset - lines)

proc scrollDown*(widget: Table, lines: int = 1) =
  ## Scroll the table down
  let maxScroll = max(0, widget.rows.len - widget.visibleRowCount)
  widget.scrollOffset = min(maxScroll, widget.scrollOffset + lines)

proc highlightFirst*(widget: Table) =
  ## Move highlight to first selectable row (vim: gg)
  for i in 0 ..< widget.rows.len:
    if widget.rows[i].selectable:
      widget.highlightedIndex = i
      widget.scrollOffset = 0
      if widget.onHighlight != nil:
        widget.onHighlight(i)
      break

proc highlightLast*(widget: Table) =
  ## Move highlight to last selectable row (vim: G)
  for i in countdown(widget.rows.len - 1, 0):
    if widget.rows[i].selectable:
      widget.highlightedIndex = i
      if widget.visibleRowCount > 0:
        widget.scrollOffset = max(0, i - widget.visibleRowCount + 1)
      if widget.onHighlight != nil:
        widget.onHighlight(i)
      break

proc pageUp*(widget: Table) =
  ## Scroll up by one page (vim: Ctrl-U)
  if widget.visibleRowCount > 0:
    let scrollAmount = widget.visibleRowCount div 2
    widget.scrollUp(scrollAmount)
    # Try to move highlight up as well
    let targetIndex = max(0, widget.highlightedIndex - scrollAmount)
    for i in countdown(targetIndex, 0):
      if i < widget.rows.len and widget.rows[i].selectable:
        widget.highlightedIndex = i
        if widget.onHighlight != nil:
          widget.onHighlight(i)
        break

proc pageDown*(widget: Table) =
  ## Scroll down by one page (vim: Ctrl-D)
  if widget.visibleRowCount > 0:
    let scrollAmount = widget.visibleRowCount div 2
    widget.scrollDown(scrollAmount)
    # Try to move highlight down as well
    let targetIndex = min(widget.rows.len - 1, widget.highlightedIndex + scrollAmount)
    for i in targetIndex ..< widget.rows.len:
      if widget.rows[i].selectable:
        widget.highlightedIndex = i
        if widget.onHighlight != nil:
          widget.onHighlight(i)
        break

proc fullPageUp*(widget: Table) =
  ## Scroll up by full page (vim: Ctrl-B)
  if widget.visibleRowCount > 0:
    widget.scrollUp(widget.visibleRowCount)
    # Move highlight to first visible row
    for i in widget.scrollOffset ..<
        min(widget.scrollOffset + widget.visibleRowCount, widget.rows.len):
      if widget.rows[i].selectable:
        widget.highlightedIndex = i
        if widget.onHighlight != nil:
          widget.onHighlight(i)
        break

proc fullPageDown*(widget: Table) =
  ## Scroll down by full page (vim: Ctrl-F)
  if widget.visibleRowCount > 0:
    widget.scrollDown(widget.visibleRowCount)
    # Move highlight to first visible row
    for i in widget.scrollOffset ..<
        min(widget.scrollOffset + widget.visibleRowCount, widget.rows.len):
      if widget.rows[i].selectable:
        widget.highlightedIndex = i
        if widget.onHighlight != nil:
          widget.onHighlight(i)
        break

# Event handling for vim-like navigation
proc handleKeyEvent*(widget: Table, event: KeyEvent): bool =
  ## Handle keyboard input for the table with vim-like navigation
  ## Returns true if the event was handled
  if widget.rows.len == 0:
    return false

  case event.code
  of ArrowUp:
    widget.highlightPrevious()
    return true
  of ArrowDown:
    widget.highlightNext()
    return true
  of ArrowLeft, ArrowRight:
    # Could be used for horizontal scrolling in future
    return false
  of Home:
    widget.highlightFirst()
    return true
  of End:
    widget.highlightLast()
    return true
  of PageUp:
    widget.fullPageUp()
    return true
  of PageDown:
    widget.fullPageDown()
    return true
  of Enter, Space:
    if widget.highlightedIndex >= 0 and widget.selectionMode != None:
      if event.code == Space and widget.selectionMode == Multiple:
        widget.toggleSelection(widget.highlightedIndex)
      else:
        widget.selectRow(widget.highlightedIndex)
      return true
  of Char:
    case event.char
    # Vim-like navigation
    of 'j': # Down
      widget.highlightNext()
      return true
    of 'k': # Up
      widget.highlightPrevious()
      return true
    of 'g': # Go to first (gg in vim, but single g for simplicity)
      widget.highlightFirst()
      return true
    of 'G': # Go to last
      widget.highlightLast()
      return true
    of 'h': # Left (could be used for horizontal scrolling)
      return false
    of 'l': # Right (could be used for horizontal scrolling)
      return false
    # Vim-like scrolling
    of 'u': # Half page up (Ctrl-U in vim)
      widget.pageUp()
      return true
    of 'd': # Half page down (Ctrl-D in vim)
      widget.pageDown()
      return true
    of 'b': # Full page up (Ctrl-B in vim)
      widget.fullPageUp()
      return true
    of 'f': # Full page down (Ctrl-F in vim)
      widget.fullPageDown()
      return true
    # Selection
    of ' ': # Space for selection
      if widget.highlightedIndex >= 0 and widget.selectionMode != None:
        if widget.selectionMode == Multiple:
          widget.toggleSelection(widget.highlightedIndex)
        else:
          widget.selectRow(widget.highlightedIndex)
        return true
    of 'v': # Visual mode toggle (for multiple selection)
      if widget.highlightedIndex >= 0 and widget.selectionMode == Multiple:
        widget.toggleSelection(widget.highlightedIndex)
        return true
    else:
      return false
  of Escape:
    # Clear selection on Escape
    if widget.selectedIndices.len > 0:
      widget.clearSelection()
      return true
    return false
  else:
    return false

# Utility functions for table layout
proc calculateColumnWidths*(widget: Table, availableWidth: int): seq[int] =
  ## Calculate actual column widths based on content and constraints
  result = newSeq[int](widget.columns.len)

  if widget.columns.len == 0:
    return

  var totalFixedWidth = 0
  var flexColumns: seq[int] = @[]

  # Calculate space needed for borders and spacing
  let verticalBorders =
    if widget.borderStyle == NoBorder:
      0
    else:
      widget.columns.len + 1
  let totalSpacing = (widget.columns.len - 1) * widget.columnSpacing + verticalBorders
  let contentWidth = max(0, availableWidth - totalSpacing)

  # First pass: handle fixed-width columns
  for i, col in widget.columns:
    if col.width.isSome:
      result[i] = col.width.get()
      totalFixedWidth += result[i]
    else:
      flexColumns.add(i)
      # Start with minimum width based on header
      result[i] = col.title.runeLen

  # If total fixed width exceeds available content width, scale down proportionally
  if totalFixedWidth > contentWidth and totalFixedWidth > 0:
    let scaleFactor = contentWidth.float / totalFixedWidth.float
    for i, col in widget.columns:
      if col.width.isSome:
        result[i] = max(3, int(result[i].float * scaleFactor))
          # Minimum 3 chars per column

  # Calculate minimum widths for flex columns based on content
  for colIndex in flexColumns:
    for row in widget.rows:
      if colIndex < row.cells.len:
        result[colIndex] = max(result[colIndex], row.cells[colIndex].runeLen)

  # Distribute remaining width among flex columns
  let remainingWidth =
    contentWidth - totalFixedWidth - flexColumns.mapIt(result[it]).foldl(a + b, 0)
  if remainingWidth > 0 and flexColumns.len > 0:
    let additionalWidth = remainingWidth div flexColumns.len
    for colIndex in flexColumns:
      result[colIndex] += additionalWidth

proc calculateTotalLineWidth*(
    columnWidths: seq[int], columnSpacing: int, hasBorders: bool
): int =
  ## Calculate the total width needed for a table line including borders and spacing
  let visibleColumns = columnWidths.filterIt(it > 0)
  result = visibleColumns.foldl(a + b, 0)
  if visibleColumns.len > 1:
    result += (visibleColumns.len - 1) * columnSpacing
  if hasBorders:
    result += visibleColumns.len + 1 # Left border + vertical separators + right border

proc formatCell*(content: string, width: int, alignment: ColumnAlignment): string =
  ## Format a cell's content within the given width
  if content.runeLen > width:
    if width <= 3:
      return "...".runeSubStr(0, width)
    return content.runeSubStr(0, width - 3) & "..."

  let padding = width - content.runeLen
  case alignment
  of AlignLeft:
    content & " ".repeat(padding)
  of AlignRight:
    " ".repeat(padding) & content
  of AlignCenter:
    let leftPad = padding div 2
    let rightPad = padding - leftPad
    " ".repeat(leftPad) & content & " ".repeat(rightPad)

proc getBorderChars*(
    style: BorderStyle
): tuple[
  horizontal: string,
  vertical: string,
  topLeft: string,
  topRight: string,
  bottomLeft: string,
  bottomRight: string,
  cross: string,
  topT: string,
  bottomT: string,
  leftT: string,
  rightT: string,
] =
  ## Get border characters for the specified border style
  case style
  of NoBorder:
    ("", "", "", "", "", "", "", "", "", "", "")
  of SimpleBorder:
    ("-", "|", "+", "+", "+", "+", "+", "+", "+", "+", "+")
  of RoundedBorder:
    ("─", "│", "╭", "╮", "╰", "╯", "┼", "┬", "┴", "├", "┤")
  of DoubleBorder:
    ("═", "║", "╔", "╗", "╚", "╝", "╬", "╦", "╩", "╠", "╣")

# Table widget methods
method render*(widget: Table, area: Rect, buf: var Buffer) =
  ## Render the table widget
  if area.isEmpty or widget.columns.len == 0:
    return

  let columnWidths = widget.calculateColumnWidths(area.width)
  let borderChars = getBorderChars(widget.borderStyle)

  # Calculate actual table width
  let hasBorders = widget.borderStyle != NoBorder
  let actualTableWidth =
    calculateTotalLineWidth(columnWidths, widget.columnSpacing, hasBorders)

  var currentY = area.y

  # Render top border
  if widget.borderStyle != NoBorder:
    var borderLine = borderChars.topLeft
    for i, width in columnWidths:
      if width > 0:
        borderLine.add(borderChars.horizontal.repeat(width))
        if i < columnWidths.len - 1:
          borderLine.add(borderChars.horizontal.repeat(widget.columnSpacing))
          borderLine.add(borderChars.topT)
    borderLine.add(borderChars.topRight)
    buf.setString(area.x, currentY, borderLine, widget.borderStyleOptions)
    currentY += 1

  # Render header if enabled
  if widget.showHeader and currentY < area.y + area.height:
    let hasBorders = widget.borderStyle != NoBorder
    var currentX = area.x

    # Render left border
    if hasBorders:
      buf.setString(currentX, currentY, borderChars.vertical, widget.borderStyleOptions)
      currentX += 1

    # Render each header cell with proper styling
    for i, col in widget.columns:
      if i < columnWidths.len and columnWidths[i] > 0:
        let cellContent = formatCell(col.title, columnWidths[i], col.alignment)
        let cellStyle =
          if col.style.isSome:
            col.style.get()
          else:
            widget.headerStyle
        buf.setString(currentX, currentY, cellContent, cellStyle)
        currentX += cellContent.len

        # Render column spacing and separator
        if i < widget.columns.len - 1:
          buf.setString(
            currentX, currentY, " ".repeat(widget.columnSpacing), widget.headerStyle
          )
          currentX += widget.columnSpacing
          if hasBorders:
            buf.setString(
              currentX, currentY, borderChars.vertical, widget.borderStyleOptions
            )
            currentX += 1

    # Render right border
    if hasBorders:
      buf.setString(currentX, currentY, borderChars.vertical, widget.borderStyleOptions)

    currentY += 1

    # Header separator
    if widget.borderStyle != NoBorder:
      var separatorLine = borderChars.leftT
      for i, width in columnWidths:
        if width > 0:
          separatorLine.add(borderChars.horizontal.repeat(width))
          if i < columnWidths.len - 1:
            separatorLine.add(borderChars.horizontal.repeat(widget.columnSpacing))
            separatorLine.add(borderChars.cross)
      separatorLine.add(borderChars.rightT)
      buf.setString(area.x, currentY, separatorLine, widget.borderStyleOptions)
      currentY += 1

  # Calculate visible row area
  let availableRows =
    area.y + area.height - currentY - (if widget.borderStyle != NoBorder: 1 else: 0)
  widget.visibleRowCount = max(0, availableRows)

  # Ensure scroll offset is valid
  let maxScroll = max(0, widget.rows.len - widget.visibleRowCount)
  widget.scrollOffset = min(widget.scrollOffset, maxScroll)

  # Calculate scrollbar position if needed
  let needsScrollbar = widget.showScrollbar and widget.rows.len > widget.visibleRowCount
  # Position scrollbar inside the right border of the actual table
  let scrollbarX =
    area.x + actualTableWidth - (if widget.borderStyle != NoBorder: 2 else: 1)
  var scrollbarHeight = 0
  var scrollbarPos = 0
  var scrollbarThumbSize = 0

  if needsScrollbar:
    # Calculate scrollbar metrics
    scrollbarHeight = widget.visibleRowCount
    scrollbarThumbSize =
      max(1, (widget.visibleRowCount * scrollbarHeight) div widget.rows.len)
    if widget.rows.len > widget.visibleRowCount:
      scrollbarPos =
        (widget.scrollOffset * (scrollbarHeight - scrollbarThumbSize)) div
        (widget.rows.len - widget.visibleRowCount)

  # Render visible rows
  for i in 0 ..< widget.visibleRowCount:
    if currentY >= area.y + area.height:
      break

    let rowIndex = widget.scrollOffset + i

    if rowIndex >= widget.rows.len:
      # Empty row
      var emptyLine = ""
      let hasBorders = widget.borderStyle != NoBorder
      let expectedWidth =
        calculateTotalLineWidth(columnWidths, widget.columnSpacing, hasBorders)

      if hasBorders:
        emptyLine =
          borderChars.vertical & " ".repeat(expectedWidth - 2) & borderChars.vertical
      else:
        emptyLine = " ".repeat(expectedWidth)

      buf.setString(area.x, currentY, emptyLine, widget.normalRowStyle)

      # Render scrollbar for empty row (inside the border)
      if needsScrollbar:
        let relativeY = i
        if relativeY >= scrollbarPos and relativeY < scrollbarPos + scrollbarThumbSize:
          buf.setString(scrollbarX, currentY, "█", style(BrightBlack))
        else:
          buf.setString(scrollbarX, currentY, "│", style(BrightBlack))

      currentY += 1
      continue

    let row = widget.rows[rowIndex]
    let isSelected = rowIndex in widget.selectedIndices
    let isHighlighted = rowIndex == widget.highlightedIndex

    # Determine row style
    let rowStyle =
      if row.style.isSome:
        row.style.get()
      elif isSelected and isHighlighted:
        # Combine styles
        style(
          widget.highlightedRowStyle.fg, widget.selectedRowStyle.bg,
          widget.selectedRowStyle.modifiers,
        )
      elif isSelected:
        widget.selectedRowStyle
      elif isHighlighted:
        widget.highlightedRowStyle
      else:
        widget.normalRowStyle

    let hasBorders = widget.borderStyle != NoBorder
    var currentX = area.x

    # Render left border
    if hasBorders:
      buf.setString(currentX, currentY, borderChars.vertical, widget.borderStyleOptions)
      currentX += 1

    # Render each data cell with proper styling
    for colIndex, col in widget.columns:
      if colIndex < columnWidths.len and columnWidths[colIndex] > 0:
        let cellContent =
          if colIndex < row.cells.len:
            formatCell(row.cells[colIndex], columnWidths[colIndex], col.alignment)
          else:
            " ".repeat(columnWidths[colIndex])

        # Apply row style only to cell content, not borders
        let cellStyle =
          if row.style.isSome:
            row.style.get()
          else:
            rowStyle
        buf.setString(currentX, currentY, cellContent, cellStyle)
        currentX += cellContent.len

        # Render column spacing and separator
        if colIndex < widget.columns.len - 1:
          buf.setString(currentX, currentY, " ".repeat(widget.columnSpacing), cellStyle)
          currentX += widget.columnSpacing
          if hasBorders:
            buf.setString(
              currentX, currentY, borderChars.vertical, widget.borderStyleOptions
            )
            currentX += 1

    # Render scrollbar for data rows (before right border so it appears inside)
    if needsScrollbar:
      let relativeY = i
      if relativeY >= scrollbarPos and relativeY < scrollbarPos + scrollbarThumbSize:
        buf.setString(scrollbarX, currentY, "█", style(BrightBlack))
      else:
        buf.setString(scrollbarX, currentY, "│", style(BrightBlack))

    # Render right border
    if hasBorders:
      buf.setString(currentX, currentY, borderChars.vertical, widget.borderStyleOptions)

    currentY += 1

  # Render bottom border
  if widget.borderStyle != NoBorder and currentY < area.y + area.height:
    var borderLine = borderChars.bottomLeft
    for i, width in columnWidths:
      if width > 0:
        borderLine.add(borderChars.horizontal.repeat(width))
        if i < columnWidths.len - 1:
          borderLine.add(borderChars.horizontal.repeat(widget.columnSpacing))
          borderLine.add(borderChars.bottomT)
    borderLine.add(borderChars.bottomRight)
    buf.setString(area.x, currentY, borderLine, widget.borderStyleOptions)

method getMinSize*(widget: Table): Size =
  ## Get minimum size for table widget
  if widget.columns.len == 0:
    return size(0, 0)

  # Minimum width: at least 3 characters per column plus spacing and borders
  let minWidth =
    widget.columns.len * 3 + (widget.columns.len - 1) * widget.columnSpacing +
    (if widget.borderStyle != NoBorder: 2 else: 0) + (
      if widget.showScrollbar: 1 else: 0
    )

  # Minimum height: header + at least one row + borders
  let minHeight =
    (if widget.showHeader: 1 else: 0) + 1 +
    (if widget.borderStyle != NoBorder: 2 + (if widget.showHeader: 1 else: 0)
    else: 0)

  size(minWidth, minHeight)

method getPreferredSize*(widget: Table, available: Size): Size =
  ## Get preferred size for table widget
  # Use all available space
  available

method canFocus*(widget: Table): bool =
  ## Tables can receive focus when they have selectable rows
  widget.selectionMode != None and widget.rows.anyIt(it.selectable)
