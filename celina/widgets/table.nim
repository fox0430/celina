## Table widget
##
## This module provides table widgets for displaying structured data in rows
## and columns, with support for headers, selection, scrolling, and styling.

import std/[sequtils, options, strutils, unicode]

import base
import ../core/[geometry, buffer, colors, events, borders]

export
  borders.BorderKind, borders.BorderChars, borders.getBorderChars,
  borders.defaultBorderChars

{.push warning[Deprecated]: off.}
export
  borders.BorderStyle, borders.NoBorder, borders.DoubleBorder, borders.RoundedBorder,
  borders.SimpleBorder
{.pop.}

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

  TableStyle* = object ## Style aggregate for table colors
    header*: Style ## Header row style
    normalRow*: Style ## Normal data row style
    selectedRow*: Style ## Selected row style
    highlightedRow*: Style ## Highlighted (focused navigation) row style
    border*: Style ## Border glyph style

  TableCallbacks* = object ## Callback aggregate for table events
    onSelect*: proc(index: int)
    onMultiSelect*: proc(indices: seq[int])
    onHighlight*: proc(index: int)

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
    borderStyle*: BorderKind
    columnSpacing*: int # Space between columns
    showScrollbar*: bool
    # Styling
    headerStyle*: Style
    normalRowStyle*: Style
    selectedRowStyle*: Style
    highlightedRowStyle*: Style
    borderColor*: Style
    # Event handlers
    onSelect*: proc(index: int)
    onMultiSelect*: proc(indices: seq[int])
    onHighlight*: proc(index: int)

# Legacy `BorderStyle` type and `NoBorder`/`SimpleBorder`/etc. value aliases
# now live in `core/borders` and are re-exported above. Centralising them
# avoids ambiguous-identifier errors when both `widgets/input` and
# `widgets/table` are imported in the same module.

proc borderStyleOptions*(widget: Table): Style {.deprecated: "Use `borderColor`".} =
  ## Deprecated accessor – use `borderColor` instead.
  widget.borderColor

proc `borderStyleOptions=`*(
    widget: Table, val: Style
) {.deprecated: "Use `borderColor=`".} =
  ## Deprecated setter – use `borderColor=` instead.
  widget.borderColor = val

proc defaultTableStyle*(): TableStyle =
  ## Default style aggregate matching the historical per-field defaults.
  TableStyle(
    header: style(White, BrightBlack),
    normalRow: defaultStyle(),
    selectedRow: style(Black, White),
    highlightedRow: style(White, BrightBlack),
    border: style(BrightBlack),
  )

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
    border: BorderKind = bkSimple,
    columnSpacing: int = 1,
    showScrollbar: bool = true,
    style: TableStyle = defaultTableStyle(),
    callbacks: TableCallbacks = TableCallbacks(),
): Table =
  ## Create a new Table widget using `TableStyle` and `TableCallbacks` aggregates.
  Table(
    columns: columns,
    rows: rows,
    selectionMode: selectionMode,
    selectedIndices: @[],
    highlightedIndex: if rows.len > 0: 0 else: -1,
    scrollOffset: 0,
    visibleRowCount: 0,
    showHeader: showHeader,
    borderStyle: border,
    columnSpacing: columnSpacing,
    showScrollbar: showScrollbar,
    headerStyle: style.header,
    normalRowStyle: style.normalRow,
    selectedRowStyle: style.selectedRow,
    highlightedRowStyle: style.highlightedRow,
    borderColor: style.border,
    onSelect: callbacks.onSelect,
    onMultiSelect: callbacks.onMultiSelect,
    onHighlight: callbacks.onHighlight,
  )

proc newTable*(
    columns: seq[Column],
    rows: seq[TableRow],
    selectionMode: SelectionMode,
    showHeader: bool,
    borderStyle: BorderKind,
    columnSpacing: int,
    showScrollbar: bool,
    headerStyle: Style,
    normalRowStyle: Style = defaultStyle(),
    selectedRowStyle: Style = style(Black, White),
    highlightedRowStyle: Style = style(White, BrightBlack),
    borderStyleOptions: Style = style(BrightBlack),
    onSelect: proc(index: int) = nil,
    onMultiSelect: proc(indices: seq[int]) = nil,
    onHighlight: proc(index: int) = nil,
): Table {.deprecated: "Use newTable with TableStyle/TableCallbacks aggregate".} =
  ## Deprecated: legacy form taking individual style and callback parameters.
  ##
  ## The required positional `headerStyle` disambiguates this overload from
  ## the aggregate-based one.
  newTable(
    columns = columns,
    rows = rows,
    selectionMode = selectionMode,
    showHeader = showHeader,
    border = borderStyle,
    columnSpacing = columnSpacing,
    showScrollbar = showScrollbar,
    style = TableStyle(
      header: headerStyle,
      normalRow: normalRowStyle,
      selectedRow: selectedRowStyle,
      highlightedRow: highlightedRowStyle,
      border: borderStyleOptions,
    ),
    callbacks = TableCallbacks(
      onSelect: onSelect, onMultiSelect: onMultiSelect, onHighlight: onHighlight
    ),
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
    if widget.rows.len == 0:
      widget.highlightedIndex = -1
    else:
      if index < widget.highlightedIndex:
        dec widget.highlightedIndex
      if widget.highlightedIndex >= widget.rows.len:
        widget.highlightedIndex = widget.rows.len - 1

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
proc handleKeyEvent*(widget: Table, event: KeyEvent): EventResult =
  ## Handle keyboard input for the table with vim-like navigation.
  ## Returns `erConsume` when the table reacted to the event, `erContinue`
  ## otherwise.
  if widget.rows.len == 0:
    return erContinue

  case event.code
  of ArrowUp:
    widget.highlightPrevious()
    return erConsume
  of ArrowDown:
    widget.highlightNext()
    return erConsume
  of ArrowLeft, ArrowRight:
    # Reserved for future horizontal scrolling — propagate for now.
    return erContinue
  of Home:
    widget.highlightFirst()
    return erConsume
  of End:
    widget.highlightLast()
    return erConsume
  of PageUp:
    widget.fullPageUp()
    return erConsume
  of PageDown:
    widget.fullPageDown()
    return erConsume
  of Enter, Space:
    if widget.highlightedIndex >= 0 and widget.selectionMode != None:
      if event.code == Space and widget.selectionMode == Multiple:
        widget.toggleSelection(widget.highlightedIndex)
      else:
        widget.selectRow(widget.highlightedIndex)
      return erConsume
  of Char:
    case event.char
    # Vim-like navigation
    of "j": # Down
      widget.highlightNext()
      return erConsume
    of "k": # Up
      widget.highlightPrevious()
      return erConsume
    of "g": # Go to first (gg in vim, but single g for simplicity)
      widget.highlightFirst()
      return erConsume
    of "G": # Go to last
      widget.highlightLast()
      return erConsume
    of "h", "l":
      # Reserved for future horizontal scrolling — propagate for now.
      return erContinue
    # Vim-like scrolling
    of "u": # Half page up (Ctrl-U in vim)
      widget.pageUp()
      return erConsume
    of "d": # Half page down (Ctrl-D in vim)
      widget.pageDown()
      return erConsume
    of "b": # Full page up (Ctrl-B in vim)
      widget.fullPageUp()
      return erConsume
    of "f": # Full page down (Ctrl-F in vim)
      widget.fullPageDown()
      return erConsume
    # Selection
    of " ": # Space for selection
      if widget.highlightedIndex >= 0 and widget.selectionMode != None:
        if widget.selectionMode == Multiple:
          widget.toggleSelection(widget.highlightedIndex)
        else:
          widget.selectRow(widget.highlightedIndex)
        return erConsume
    of "v": # Visual mode toggle (for multiple selection)
      if widget.highlightedIndex >= 0 and widget.selectionMode == Multiple:
        widget.toggleSelection(widget.highlightedIndex)
        return erConsume
    else:
      return erContinue
  of Escape:
    # Clear selection on Escape
    if widget.selectedIndices.len > 0:
      widget.clearSelection()
      return erConsume
    return erContinue
  else:
    return erContinue

# Generated: Table currently only handles key events.
defineKeyDispatch(Table)

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
    if widget.borderStyle == bkNone:
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
      result[i] = col.title.displayWidth

  # If total fixed width exceeds available content width, scale down proportionally.
  # Fixed columns collapse like flex columns when the area is too narrow; the
  # final guard below guarantees the total never exceeds contentWidth.
  if totalFixedWidth > contentWidth and totalFixedWidth > 0:
    let scaleFactor = contentWidth.float / totalFixedWidth.float
    for i, col in widget.columns:
      if col.width.isSome:
        result[i] = int(result[i].float * scaleFactor)

  # Footprint of the fixed columns after any scaling above.
  var fixedWidth = 0
  for i, col in widget.columns:
    if col.width.isSome:
      fixedWidth += result[i]

  # Calculate minimum widths for flex columns based on content
  for colIndex in flexColumns:
    for row in widget.rows:
      if colIndex < row.cells.len:
        result[colIndex] = max(result[colIndex], row.cells[colIndex].displayWidth)

  # Fit the flexible columns into the width left over after the fixed columns.
  if flexColumns.len > 0:
    let flexBudget = max(0, contentWidth - fixedWidth)
    let flexContentWidth = flexColumns.mapIt(result[it]).foldl(a + b, 0)
    if flexContentWidth > flexBudget:
      # Content is wider than the space available: scale the flex columns down
      # proportionally so the table stays inside its area instead of growing to
      # fit the content and overrunning the widget bounds. Columns that no
      # longer fit collapse to zero and are dropped from the render.
      if flexContentWidth > 0:
        let scaleFactor = flexBudget.float / flexContentWidth.float
        for colIndex in flexColumns:
          result[colIndex] = max(0, int(result[colIndex].float * scaleFactor))
    else:
      # Spare room: distribute it evenly among the flex columns.
      let additionalWidth = (flexBudget - flexContentWidth) div flexColumns.len
      for colIndex in flexColumns:
        result[colIndex] += additionalWidth

  # Final guard: rounding and the per-column minimum on fixed columns can still
  # leave the total over the content width. Trim the widest column (dropping it
  # entirely if need be) until the row fits, so the computed widths never imply
  # a table wider than its area no matter how wide the cell content is.
  var usedWidth = result.foldl(a + b, 0)
  while usedWidth > contentWidth:
    var widest = -1
    for i in 0 ..< result.len:
      if result[i] > 0 and (widest == -1 or result[i] > result[widest]):
        widest = i
    if widest == -1:
      break # every column already collapsed to zero
    result[widest].dec
    usedWidth.dec

proc calculateTotalLineWidth*(
    columnWidths: seq[int], columnSpacing: int, hasBorders: bool
): int =
  ## Calculate the total width needed for a table line including borders and spacing
  let visibleColumns = columnWidths.filterIt(it > 0)
  result = visibleColumns.foldl(a + b, 0)
  if visibleColumns.len > 1:
    result += (visibleColumns.len - 1) * columnSpacing
  if hasBorders:
    # Left border + one separator between each pair of visible columns + right
    # border. With no visible columns the line is still the two outer borders
    # (matching the degenerate `topLeft & topRight` the border rows emit), so
    # the minimum is 2 — never 1, which would make the empty-row width math
    # below go negative.
    if visibleColumns.len == 0:
      result += 2
    else:
      result += visibleColumns.len + 1

proc formatCell*(content: string, width: int, alignment: ColumnAlignment): string =
  ## Format a cell's content within the given width
  if content.displayWidth > width:
    if width <= 3:
      return "...".truncateToWidth(width)
    let truncated = content.truncateToWidth(width - 3) & "..."
    # truncateToWidth may leave us short when a wide char gets dropped
    return truncated & " ".repeat(max(0, width - truncated.displayWidth))

  let padding = width - content.displayWidth
  case alignment
  of AlignLeft:
    content & " ".repeat(padding)
  of AlignRight:
    " ".repeat(padding) & content
  of AlignCenter:
    let leftPad = padding div 2
    let rightPad = padding - leftPad
    " ".repeat(leftPad) & content & " ".repeat(rightPad)

proc hasVisibleColumnAfter(columnWidths: seq[int], index: int): bool =
  ## True when some column after `index` is still visible (width > 0). The last
  ## *visible* column gets no trailing spacing/separator even when later columns
  ## exist but have collapsed to zero width. Keying the separators off this
  ## (rather than the raw index) keeps the rendered line width in step with
  ## `calculateTotalLineWidth`, which counts separators per visible column — so
  ## the scrollbar lands on the real right border and no dangling separator is
  ## drawn before it.
  for j in index + 1 ..< columnWidths.len:
    if columnWidths[j] > 0:
      return true
  false

proc drawClipped(b: var Buffer, x, y: int, area: Rect, text: string, style: Style) =
  ## Write `text` on row `y`, clipped to `area`. A row outside the vertical span
  ## `[area.y, area.bottom)` is dropped whole; within a row, runes outside the
  ## column range `[area.x, area.right)` — and any wide rune straddling an edge —
  ## are dropped. This keeps the table strictly inside the area it was handed:
  ## border glyphs, rounding, a collapsed scrollbar position, or a line that
  ## doesn't fit the remaining height can no longer spill past any edge and
  ## corrupt the neighbouring widgets that share the screen buffer.
  let leftEdge = area.x
  let rightEdge = area.right
  if text.len == 0 or leftEdge >= rightEdge or x >= rightEdge:
    return
  if y < area.y or y >= area.bottom:
    return
  var col = x
  var drawX = -1
  var visible = ""
  for r in text.runes:
    let w = runeWidth(r)
    if col >= rightEdge or col + w > rightEdge:
      break # this (possibly wide) rune would spill past the right edge
    if col >= leftEdge:
      if drawX < 0:
        drawX = col
      visible.add($r)
    # runes left of (or straddling) leftEdge are dropped
    col += w
  if drawX >= 0 and visible.len > 0:
    b.setString(drawX, y, visible, style)

# Table widget methods
method render*(widget: Table, area: Rect, buf: var Buffer) =
  ## Render the table widget
  if area.isEmpty or widget.columns.len == 0:
    return

  # All table drawing goes through `emit`, which clips every write to `area`
  # (both axes) so nothing can ever spill past the rectangle the table was given.
  template emit(ex, ey: int, text: string, st: Style) =
    drawClipped(buf, ex, ey, area, text, st)

  let columnWidths = widget.calculateColumnWidths(area.width)
  let borderChars = getBorderChars(widget.borderStyle)

  # Calculate actual table width
  let hasBorders = widget.borderStyle != bkNone
  let actualTableWidth =
    calculateTotalLineWidth(columnWidths, widget.columnSpacing, hasBorders)

  var currentY = area.y

  # Render top border
  if widget.borderStyle != bkNone:
    var borderLine = borderChars.topLeft
    for i, width in columnWidths:
      if width > 0:
        borderLine.add(borderChars.horizontal.repeat(width))
        if hasVisibleColumnAfter(columnWidths, i):
          borderLine.add(borderChars.horizontal.repeat(widget.columnSpacing))
          borderLine.add(borderChars.topT)
    borderLine.add(borderChars.topRight)
    emit(area.x, currentY, borderLine, widget.borderColor)
    currentY += 1

  # Render header if enabled
  if widget.showHeader and currentY < area.y + area.height:
    let hasBorders = widget.borderStyle != bkNone
    var currentX = area.x

    # Render left border
    if hasBorders:
      emit(currentX, currentY, borderChars.vertical, widget.borderColor)
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
        emit(currentX, currentY, cellContent, cellStyle)
        currentX += columnWidths[i]

        # Render column spacing and separator
        if hasVisibleColumnAfter(columnWidths, i):
          emit(currentX, currentY, " ".repeat(widget.columnSpacing), widget.headerStyle)
          currentX += widget.columnSpacing
          if hasBorders:
            emit(currentX, currentY, borderChars.vertical, widget.borderColor)
            currentX += 1

    # Render right border
    if hasBorders:
      emit(currentX, currentY, borderChars.vertical, widget.borderColor)

    currentY += 1

    # Header separator
    if widget.borderStyle != bkNone:
      var separatorLine = borderChars.leftT
      for i, width in columnWidths:
        if width > 0:
          separatorLine.add(borderChars.horizontal.repeat(width))
          if hasVisibleColumnAfter(columnWidths, i):
            separatorLine.add(borderChars.horizontal.repeat(widget.columnSpacing))
            separatorLine.add(borderChars.cross)
      separatorLine.add(borderChars.rightT)
      emit(area.x, currentY, separatorLine, widget.borderColor)
      currentY += 1

  # Calculate visible row area
  let availableRows =
    area.y + area.height - currentY - (if widget.borderStyle != bkNone: 1 else: 0)
  widget.visibleRowCount = max(0, availableRows)

  # Ensure scroll offset is valid
  let maxScroll = max(0, widget.rows.len - widget.visibleRowCount)
  widget.scrollOffset = min(widget.scrollOffset, maxScroll)

  # Calculate scrollbar position if needed
  let needsScrollbar = widget.showScrollbar and widget.rows.len > widget.visibleRowCount
  # Position scrollbar inside the right border of the actual table
  let scrollbarX =
    area.x + actualTableWidth - (if widget.borderStyle != bkNone: 2 else: 1)
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
      let hasBorders = widget.borderStyle != bkNone
      let expectedWidth =
        calculateTotalLineWidth(columnWidths, widget.columnSpacing, hasBorders)

      if hasBorders:
        emptyLine =
          borderChars.vertical & " ".repeat(max(0, expectedWidth - 2)) &
          borderChars.vertical
      else:
        emptyLine = " ".repeat(expectedWidth)

      emit(area.x, currentY, emptyLine, widget.normalRowStyle)

      # Render scrollbar for empty row (inside the border)
      if needsScrollbar:
        let relativeY = i
        if relativeY >= scrollbarPos and relativeY < scrollbarPos + scrollbarThumbSize:
          emit(scrollbarX, currentY, "█", style(BrightBlack))
        else:
          emit(scrollbarX, currentY, "│", style(BrightBlack))

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

    let hasBorders = widget.borderStyle != bkNone
    var currentX = area.x

    # Render left border
    if hasBorders:
      emit(currentX, currentY, borderChars.vertical, widget.borderColor)
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
        emit(currentX, currentY, cellContent, cellStyle)
        currentX += columnWidths[colIndex]

        # Render column spacing and separator
        if hasVisibleColumnAfter(columnWidths, colIndex):
          emit(currentX, currentY, " ".repeat(widget.columnSpacing), cellStyle)
          currentX += widget.columnSpacing
          if hasBorders:
            emit(currentX, currentY, borderChars.vertical, widget.borderColor)
            currentX += 1

    # Render scrollbar for data rows (before right border so it appears inside)
    if needsScrollbar:
      let relativeY = i
      if relativeY >= scrollbarPos and relativeY < scrollbarPos + scrollbarThumbSize:
        emit(scrollbarX, currentY, "█", style(BrightBlack))
      else:
        emit(scrollbarX, currentY, "│", style(BrightBlack))

    # Render right border
    if hasBorders:
      emit(currentX, currentY, borderChars.vertical, widget.borderColor)

    currentY += 1

  # Render bottom border
  if widget.borderStyle != bkNone and currentY < area.y + area.height:
    var borderLine = borderChars.bottomLeft
    for i, width in columnWidths:
      if width > 0:
        borderLine.add(borderChars.horizontal.repeat(width))
        if hasVisibleColumnAfter(columnWidths, i):
          borderLine.add(borderChars.horizontal.repeat(widget.columnSpacing))
          borderLine.add(borderChars.bottomT)
    borderLine.add(borderChars.bottomRight)
    emit(area.x, currentY, borderLine, widget.borderColor)

method getMinSize*(widget: Table): Size =
  ## Get minimum size for table widget
  if widget.columns.len == 0:
    return size(0, 0)

  # Minimum width: at least 3 characters per column plus spacing and borders
  let minWidth =
    widget.columns.len * 3 + (widget.columns.len - 1) * widget.columnSpacing +
    (if widget.borderStyle != bkNone: 2 else: 0) + (if widget.showScrollbar: 1 else: 0)

  # Minimum height: header + at least one row + borders
  let minHeight =
    (if widget.showHeader: 1 else: 0) + 1 +
    (if widget.borderStyle != bkNone: 2 + (if widget.showHeader: 1 else: 0)
    else: 0)

  size(minWidth, minHeight)

method getPreferredSize*(widget: Table, available: Size): Size =
  ## Get preferred size for table widget
  # Use all available space
  available

method canFocus*(widget: Table): bool =
  ## Tables can receive focus when they have selectable rows
  widget.selectionMode != None and widget.rows.anyIt(it.selectable)
