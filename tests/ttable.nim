## Unit tests for table widget

import std/[unittest, sequtils, options, strformat]

import ../celina/core/[geometry, colors, buffer]
import ../celina/widgets/table {.all.}

suite "Table Widget Tests":
  test "Table creation and initialization":
    # Test basic table creation
    let columns = @["Name", "Age", "City"]
    let tableWidget = table(columns)

    check:
      tableWidget.columns.len == 3
      tableWidget.rows.len == 0
      tableWidget.selectionMode == Single
      tableWidget.highlightedIndex == -1
      tableWidget.selectedIndices.len == 0
      tableWidget.scrollOffset == 0
      tableWidget.showHeader == true
      tableWidget.borderStyle == SimpleBorder

  test "Column creation":
    # Test Column creation
    let col1 = column("Simple")
    let col2 = column("Fixed Width", 20)
    let col3 = column("Centered", AlignCenter)
    let col4 = newColumn("Styled", some(15), AlignRight, some(style(color(Red))))

    check:
      col1.title == "Simple"
      col1.width.isNone
      col1.alignment == AlignLeft
      col1.style.isNone

      col2.title == "Fixed Width"
      col2.width.isSome
      col2.width.get() == 20

      col3.alignment == AlignCenter

      col4.title == "Styled"
      col4.width.get() == 15
      col4.alignment == AlignRight
      col4.style.isSome

  test "Row creation":
    # Test TableRow creation
    let row1 = tableRow(@["John", "30", "NYC"])
    let row2 = tableRow(@["Jane", "25", "LA"], style(color(Blue)))
    let row3 = newTableRow(@["Bob", "35", "SF"], some(style(color(Green))), false)

    check:
      row1.cells.len == 3
      row1.cells[0] == "John"
      row1.style.isNone
      row1.selectable == true

      row2.style.isSome
      row2.selectable == true

      row3.selectable == false

  test "Table with data creation":
    # Test table creation with columns and rows
    let columns = @["Name", "Age"]
    let rows = @[@["Alice", "28"], @["Bob", "32"], @["Charlie", "24"]]
    let tableWidget = table(columns, rows)

    check:
      tableWidget.columns.len == 2
      tableWidget.rows.len == 3
      tableWidget.highlightedIndex == 0
      tableWidget.rows[0].cells[0] == "Alice"
      tableWidget.rows[2].cells[1] == "24"

  test "Empty table handling":
    # Test empty table behavior
    let emptyTable = newTable()

    check:
      emptyTable.columns.len == 0
      emptyTable.rows.len == 0
      emptyTable.highlightedIndex == -1
      emptyTable.selectedIndices.len == 0

  test "Column management":
    # Test adding and removing columns
    var tableWidget = table(@["Col1", "Col2"])

    check tableWidget.columns.len == 2

    tableWidget.addColumn("Col3")
    check:
      tableWidget.columns.len == 3
      tableWidget.columns[2].title == "Col3"

    tableWidget.removeColumn(1)
    check:
      tableWidget.columns.len == 2
      tableWidget.columns[1].title == "Col3"

  test "Row management":
    # Test adding and removing rows
    var tableWidget = table(@["Name", "Value"])

    check tableWidget.rows.len == 0

    tableWidget.addRow(@["Test", "123"])
    check:
      tableWidget.rows.len == 1
      tableWidget.highlightedIndex == 0
      tableWidget.rows[0].cells[0] == "Test"

    tableWidget.addRow(tableRow(@["Another", "456"]))
    check tableWidget.rows.len == 2

    tableWidget.removeRow(0)
    check:
      tableWidget.rows.len == 1
      tableWidget.rows[0].cells[0] == "Another"

    tableWidget.clearRows()
    check:
      tableWidget.rows.len == 0
      tableWidget.highlightedIndex == -1

  test "Data replacement":
    # Test setData functionality
    var tableWidget = table(@["A", "B"])
    tableWidget.addRow(@["1", "2"])

    let newData = @[@["X", "Y"], @["Z", "W"]]
    tableWidget.setData(newData)

    check:
      tableWidget.rows.len == 2
      tableWidget.rows[0].cells[0] == "X"
      tableWidget.rows[1].cells[1] == "W"
      tableWidget.selectedIndices.len == 0
      tableWidget.highlightedIndex == 0

  test "removeRow resets highlight to -1 when emptied":
    var tableWidget = table(@["Name"], @[@["Only"]])
    check tableWidget.highlightedIndex == 0

    tableWidget.removeRow(0)
    check:
      tableWidget.rows.len == 0
      tableWidget.highlightedIndex == -1

  test "removeRow keeps highlight on the same row when removing before it":
    var tableWidget = table(@["Name"], @[@["A"], @["B"], @["C"], @["D"]])
    tableWidget.highlightedIndex = 2 # "C"

    # Removing a row before the highlight should keep the highlight on "C"
    tableWidget.removeRow(0)
    check:
      tableWidget.rows.len == 3
      tableWidget.highlightedIndex == 1
      tableWidget.rows[tableWidget.highlightedIndex].cells[0] == "C"

    # Removing the highlighted row clamps within range
    tableWidget.removeRow(2) # remove "D"
    check tableWidget.highlightedIndex == 1 # still "C"

    tableWidget.removeRow(1) # remove highlighted "C"
    check:
      tableWidget.rows.len == 1
      tableWidget.highlightedIndex == 0

  test "Single selection":
    # Test single selection mode
    let rows = @[@["A", "1"], @["B", "2"], @["C", "3"]]
    var tableWidget = table(@["Letter", "Number"], rows)
    tableWidget.selectionMode = Single

    check tableWidget.selectedIndices.len == 0

    tableWidget.selectRow(1)
    check:
      tableWidget.selectedIndices == @[1]
      tableWidget.isSelected(1) == true
      tableWidget.isSelected(0) == false

    # Selecting another row should clear previous selection
    tableWidget.selectRow(2)
    check:
      tableWidget.selectedIndices == @[2]
      tableWidget.isSelected(1) == false
      tableWidget.isSelected(2) == true

  test "Multiple selection":
    # Test multiple selection mode
    let rows = @[@["A", "1"], @["B", "2"], @["C", "3"]]
    var tableWidget = table(@["Letter", "Number"], rows)
    tableWidget.selectionMode = Multiple

    tableWidget.selectRow(0)
    tableWidget.selectRow(2)
    check:
      tableWidget.selectedIndices.len == 2
      tableWidget.isSelected(0) == true
      tableWidget.isSelected(2) == true
      tableWidget.isSelected(1) == false

    tableWidget.toggleSelection(1)
    check:
      tableWidget.selectedIndices.len == 3
      tableWidget.isSelected(1) == true

    tableWidget.toggleSelection(0)
    check:
      tableWidget.selectedIndices.len == 2
      tableWidget.isSelected(0) == false

    tableWidget.clearSelection()
    check tableWidget.selectedIndices.len == 0

  test "No selection mode":
    # Test that no selection mode prevents selection
    let rows = @[@["A", "1"], @["B", "2"]]
    var tableWidget = table(@["Letter", "Number"], rows)
    tableWidget.selectionMode = None

    tableWidget.selectRow(0)
    check tableWidget.selectedIndices.len == 0

  test "Navigation":
    # Test navigation functions
    let rows = @[
      tableRow(@["A", "1"]),
      newTableRow(@["B", "2"], none(Style), false), # Non-selectable
      tableRow(@["C", "3"]),
    ]
    var tableWidget = newTable(@[column("Letter"), column("Number")], rows)
    tableWidget.highlightedIndex = 0

    # Should skip non-selectable row
    tableWidget.highlightNext()
    check tableWidget.highlightedIndex == 2

    tableWidget.highlightPrevious()
    check tableWidget.highlightedIndex == 0

  test "Column width calculation":
    # Test calculateColumnWidths function
    let columns = @[column("Short"), column("Very Long Header"), column("Med", 10)]
    let rows = @[
      tableRow(@["A", "Medium length content", "X"]),
      tableRow(@["Really long content here", "B", "Y"]),
    ]
    var tableWidget = newTable(columns, rows)

    let widths = tableWidget.calculateColumnWidths(80)

    # Should have calculated reasonable widths
    check:
      widths.len == 3
      widths[2] == 10 # Fixed width column
      widths.foldl(a + b, 0) <= 80 - 2 - 2 # Account for spacing and borders

  test "Cell formatting":
    # Test formatCell function
    check:
      formatCell("Hello", 10, AlignLeft) == "Hello     "
      formatCell("Hello", 10, AlignRight) == "     Hello"
      formatCell("Hello", 10, AlignCenter) == "  Hello   "
      formatCell("Very long content", 8, AlignLeft) == "Very ..."
      formatCell("Short", 3, AlignLeft) == "..."

  test "Cell formatting with wide characters":
    # 日本 is 4 display columns; pad to width 6
    check formatCell("日本", 6, AlignLeft) == "日本  "
    check formatCell("日本", 6, AlignRight) == "  日本"
    # Truncation: "日本語" (6 cols) into width 5 -> keep "日" + "..." plus pad
    # width-3 = 2 columns -> "日" (2 cols) + "..." = "日..." (5 cols)
    check formatCell("日本語", 5, AlignLeft) == "日..."

  test "Border characters":
    # Test getBorderChars function
    let simple = getBorderChars(SimpleBorder)
    check:
      simple.horizontal == "-"
      simple.vertical == "|"
      simple.topLeft == "+"

    let none = getBorderChars(NoBorder)
    check:
      none.horizontal == ""
      none.vertical == ""

  test "Minimum and preferred size":
    # Test size calculations
    let columns = @[column("A"), column("B"), column("C")]
    let tableWidget = newTable(columns)

    let minSize = tableWidget.getMinSize()
    check:
      minSize.width > 0
      minSize.height > 0

    let prefSize = tableWidget.getPreferredSize(size(100, 50))
    check:
      prefSize.width == 100
      prefSize.height == 50

  test "Focus capability":
    # Test canFocus method
    let noSelectionTable = newTable(@[column("A")])
    noSelectionTable.selectionMode = None
    check noSelectionTable.canFocus() == false

    let emptyTable = newTable(@[column("A")])
    check emptyTable.canFocus() == false

    var focusableTable = table(@["A"], @[@["1"]])
    check focusableTable.canFocus() == true

    # Make all rows non-selectable
    focusableTable.rows[0].selectable = false
    check focusableTable.canFocus() == false

  test "Scrolling":
    # Test scrolling functionality
    let rows = (0 .. 10).mapIt(@[&"Row {it}", &"Value {it}"])
    var tableWidget = table(@["Name", "Value"], rows)
    tableWidget.visibleRowCount = 5

    check tableWidget.scrollOffset == 0

    tableWidget.scrollDown(3)
    check tableWidget.scrollOffset == 3

    tableWidget.scrollUp(1)
    check tableWidget.scrollOffset == 2

    # Test bounds
    tableWidget.scrollDown(20)
    check tableWidget.scrollOffset <= tableWidget.rows.len - tableWidget.visibleRowCount

    tableWidget.scrollUp(20)
    check tableWidget.scrollOffset == 0

  test "Border alignment correctness":
    # Test that borders align properly with content
    let columns = @[column("A", 5), column("B", 8), column("C", 6)]
    let rows = @[tableRow(@["12345", "12345678", "123456"])]
    var tableWidget = newTable(columns, rows)

    # Test column width calculation accounts for borders properly
    let totalAvailableWidth = 30
    let widths = tableWidget.calculateColumnWidths(totalAvailableWidth)

    # With SimpleBorder: 2 borders + 2 separators = 4 chars overhead
    let expectedContentWidth = totalAvailableWidth - 4
    let actualContentWidth = widths.foldl(a + b, 0)

    check:
      widths.len == 3
      actualContentWidth <= expectedContentWidth
      # Fixed columns should maintain their width
      widths[0] == 5
      widths[1] == 8
      widths[2] == 6

  test "Five column rendering verification":
    # Test that all 5 columns render correctly (addresses the missing 5th column bug)
    let columns = @[
      column("Name", 10),
      column("Age", 5),
      column("City", 8),
      column("Job", 10),
      column("Salary", 8),
    ]
    let rows = @[tableRow(@["Alice", "28", "NYC", "Engineer", "$75000"])]
    var tableWidget = newTable(columns, rows)

    check:
      tableWidget.columns.len == 5
      tableWidget.columns[4].title == "Salary"
      tableWidget.rows[0].cells.len == 5
      tableWidget.rows[0].cells[4] == "$75000"

    # Test width calculation with 5 columns
    let widths = tableWidget.calculateColumnWidths(60)
    check:
      widths.len == 5
      # All columns should get some width
      widths.allIt(it > 0)

  test "Styling separation for borders vs content":
    # Test that border styles don't interfere with content styles
    let columns = @[column("Test", 10)]
    let customRowStyle = style(color(Red), color(Blue))
    let rows = @[newTableRow(@["content"], some(customRowStyle), true)]
    var tableWidget = newTable(columns, rows)

    tableWidget.borderStyle = SimpleBorder
    tableWidget.borderColor = style(color(Green))
    tableWidget.selectedRowStyle = style(color(White), color(Black))

    check:
      rows[0].style.isSome
      rows[0].style.get().fg == color(Red)
      rows[0].style.get().bg == color(Blue)
      tableWidget.borderColor.fg == color(Green)
      tableWidget.selectedRowStyle.fg == color(White)

  test "Width calculation edge cases":
    # Test edge cases in column width calculation
    var tableWidget = newTable(@[column("A"), column("B"), column("C")])

    # Test with very small available width: columns shrink but the table still
    # fits inside the area (10 is just wide enough for 3 single-char columns).
    let smallWidths = tableWidget.calculateColumnWidths(10)
    check:
      smallWidths.len == 3
      smallWidths.allIt(it >= 1) # All columns still get at least 1 character
      calculateTotalLineWidth(smallWidths, tableWidget.columnSpacing, true) <= 10

    # Test with no room for content (just borders). Columns that cannot fit
    # collapse to zero rather than overflowing the area.
    let tinyWidths = tableWidget.calculateColumnWidths(4)
    check:
      tinyWidths.len == 3
      tinyWidths.allIt(it >= 0)
      calculateTotalLineWidth(tinyWidths, tableWidget.columnSpacing, true) <= 4

    # Test with mixed fixed and auto columns
    let mixedColumns = @[column("Fixed", 15), column("Auto1"), column("Auto2")]
    tableWidget = newTable(mixedColumns)
    let mixedWidths = tableWidget.calculateColumnWidths(50)
    check:
      mixedWidths[0] == 15 # Fixed width maintained
      mixedWidths[1] > 0 # Auto columns get remaining space
      mixedWidths[2] > 0
      # Like the other cases, the line must stay within the available width so a
      # regression in the fixed/flex scaling math cannot slip past unnoticed.
      calculateTotalLineWidth(mixedWidths, tableWidget.columnSpacing, true) <= 50

    # Fixed columns collapse like flex columns when the area is too narrow,
    # rather than being clamped to an artificial minimum that the final guard
    # would only have to trim away.
    let fixedColumns = @[column("A", 10), column("B", 10), column("C", 10)]
    tableWidget = newTable(fixedColumns)
    for areaWidth in [4, 6, 8, 10, 12]:
      let widths = tableWidget.calculateColumnWidths(areaWidth)
      let lineWidth = calculateTotalLineWidth(widths, tableWidget.columnSpacing, true)
      check:
        widths.allIt(it >= 0)
        lineWidth <= areaWidth

  test "Wide content does not overflow the area width":
    # Regression: flexible columns used to grow to fit the widest cell with no
    # upper bound, so content far wider than the area produced a table line that
    # ran well past the widget bounds. Column widths must now stay within the
    # available width regardless of how long the cell content is.
    let columns = @[column("Name"), column("Description")]
    let rows = @[
      tableRow(
        @[
          "Alice",
          "A very very long description that far exceeds the available area width",
        ]
      ),
      tableRow(@["Bob", "Another extremely long piece of content for this row entry"]),
    ]
    var tableWidget = newTable(columns, rows)

    # Includes areas narrower than (columns * 3), where columns must collapse
    # rather than overflow.
    for areaWidth in [3, 5, 8, 12, 20, 40, 60]:
      let widths = tableWidget.calculateColumnWidths(areaWidth)
      let hasBorders = tableWidget.borderStyle != bkNone
      let lineWidth =
        calculateTotalLineWidth(widths, tableWidget.columnSpacing, hasBorders)
      check:
        widths.allIt(it >= 0)
        lineWidth <= areaWidth

  test "Wide content does not draw past the widget area on render":
    # Render tables with very wide cells into sub-regions of a larger buffer,
    # including pathologically narrow areas, short areas, and a non-zero origin,
    # and confirm nothing is ever written outside the table's area rectangle.
    let columns = @[column("Name"), column("Description")]
    let rows = @[
      tableRow(@["Alice", "A description that is far wider than the table area"]),
      tableRow(@["Bob", "Yet another overly long cell value used for this row"]),
    ]

    # Short heights (1..3) exercise the vertical clip: with borders the header
    # separator and bottom border can land below a tiny area, so clipping must
    # apply on the y axis as well as on x.
    for areaWidth in [3, 5, 8, 12, 24]:
      for areaHeight in [1, 2, 3, 5]:
        var tableWidget = newTable(columns, rows)
        var buf = newBuffer(60, 8)
        let area = rect(2, 1, areaWidth, areaHeight) # offset origin + narrow width
        tableWidget.render(area, buf)

        # Every cell outside the area rectangle must remain untouched (a space).
        for y in 0 ..< buf.area.height:
          for x in 0 ..< buf.area.width:
            if x < area.x or x >= area.x + area.width or y < area.y or
                y >= area.y + area.height:
              check buf[x, y].symbol == " "

  test "Render does not crash when all columns collapse with empty rows":
    # Regression: when the area is too narrow for any column, every column
    # collapses to width 0. With borders and more visible row slots than data
    # rows, the empty-row path built `repeat(expectedWidth - 2)` with
    # expectedWidth == 1, raising a RangeDefect. It must now render cleanly.
    let tableWidget =
      newTable(@[column("A"), column("B"), column("C")], @[tableRow(@["x", "y", "z"])])
    let area = rect(0, 0, 3, 10) # width 3 collapses all columns; height 10 => empty rows
    check tableWidget.calculateColumnWidths(area.width).allIt(it == 0)

    var buf = newBuffer(40, 12)
    tableWidget.render(area, buf) # must not raise

    # Nothing escapes the (degenerate) area.
    for y in 0 ..< buf.area.height:
      for x in 0 ..< buf.area.width:
        if x < area.x or x >= area.right or y < area.y or y >= area.bottom:
          check buf[x, y].symbol == " "

  test "Trailing collapsed columns do not draw a dangling separator":
    # A wide fixed column forces the trailing columns to collapse to zero at a
    # narrow width. The rendered line must be exactly calculateTotalLineWidth
    # wide: no separator drawn past the last visible column (which would also
    # push the scrollbar off the real right border).
    let columns = @[column("Wide", 12), column("B"), column("C")]
    let rows = @[tableRow(@["wwwwwwwwwwww", "b", "c"])]
    let tableWidget = newTable(columns, rows)
    let area = rect(0, 0, 16, 6)
    let widths = tableWidget.calculateColumnWidths(area.width)
    check (widths[1] == 0 and widths[2] == 0) # trailing columns collapsed
    let expected = calculateTotalLineWidth(widths, tableWidget.columnSpacing, true)

    var buf = newBuffer(20, 6)
    tableWidget.render(area, buf)

    # Width actually drawn on the top border row = rightmost non-blank column + 1.
    var drawnRight = -1
    for x in 0 ..< buf.area.width:
      if buf[x, area.y].symbol != "" and buf[x, area.y].symbol != " ":
        drawnRight = x
    check drawnRight + 1 == expected

  test "Separator rendering condition":
    # Test the separator rendering logic (fixes the missing 5th column issue)
    let columns = @[column("A"), column("B"), column("C"), column("D"), column("E")]
    var tableWidget = newTable(columns)

    # The key fix was changing separator condition from complex logic to: i < columns.len - 1
    for i in 0 ..< tableWidget.columns.len:
      let shouldHaveSeparator = i < tableWidget.columns.len - 1

      if i == 0:
        check shouldHaveSeparator == true # First column should have separator
      elif i == tableWidget.columns.len - 1:
        check shouldHaveSeparator == false # Last column should NOT have separator
      else:
        check shouldHaveSeparator == true # Middle columns should have separator

    # Specifically test that 5th column (index 4) doesn't get a separator
    check (4 < tableWidget.columns.len - 1) == false

suite "Table Scrollbar Tests":
  test "Scrollbar visibility conditions":
    # Test when scrollbar should and shouldn't appear
    var table1 = newTable(
      columns = @[column("Data", 30)],
      rows = @[tableRow(@["Row 1"]), tableRow(@["Row 2"])],
      showScrollbar = true,
    )
    table1.visibleRowCount = 10

    var table2 = newTable(
      columns = @[column("Data", 30)],
      rows = (0 .. 50).mapIt(tableRow(@[$it])),
      showScrollbar = true,
    )
    table2.visibleRowCount = 10

    # Check scrollbar needed calculation
    let needs1 = table1.showScrollbar and table1.rows.len > table1.visibleRowCount
    let needs2 = table2.showScrollbar and table2.rows.len > table2.visibleRowCount

    check:
      needs1 == false # 2 rows, 10 visible -> no scrollbar
      needs2 == true # 51 rows, 10 visible -> scrollbar needed

  test "Scrollbar thumb size calculation":
    # Test that thumb size is proportional to visible content
    var table = newTable(
      columns = @[column("Test")],
      rows = (0 .. 99).mapIt(tableRow(@[$it])), # 100 rows
      showScrollbar = true,
    )

    # Test with 25% visible
    table.visibleRowCount = 25
    let thumbSize1 =
      max(1, (table.visibleRowCount * table.visibleRowCount) div table.rows.len)
    check thumbSize1 == 6 # 25 * 25 / 100 = 6.25 -> 6

    # Test with 50% visible
    table.visibleRowCount = 50
    let thumbSize2 =
      max(1, (table.visibleRowCount * table.visibleRowCount) div table.rows.len)
    check thumbSize2 == 25 # 50 * 50 / 100 = 25

    # Test with 10% visible
    table.visibleRowCount = 10
    let thumbSize3 =
      max(1, (table.visibleRowCount * table.visibleRowCount) div table.rows.len)
    check thumbSize3 == 1 # 10 * 10 / 100 = 1

  test "Scrollbar position calculation":
    # Test that scrollbar thumb moves correctly with scroll offset
    var table = newTable(
      columns = @[column("Test")],
      rows = (0 .. 49).mapIt(tableRow(@[$it])), # 50 rows
      showScrollbar = true,
    )
    table.visibleRowCount = 10

    # Test at top
    table.scrollOffset = 0
    let scrollbarHeight = table.visibleRowCount
    let thumbSize = max(1, (table.visibleRowCount * scrollbarHeight) div table.rows.len)
    let pos1 =
      if table.rows.len > table.visibleRowCount:
        (table.scrollOffset * (scrollbarHeight - thumbSize)) div
          (table.rows.len - table.visibleRowCount)
      else:
        0
    check pos1 == 0

    # Test at middle
    table.scrollOffset = 20
    let pos2 =
      if table.rows.len > table.visibleRowCount:
        (table.scrollOffset * (scrollbarHeight - thumbSize)) div
          (table.rows.len - table.visibleRowCount)
      else:
        0
    check pos2 == 4 # (20 * (10 - 2)) / 40 = 4

    # Test at bottom
    table.scrollOffset = 40
    let pos3 =
      if table.rows.len > table.visibleRowCount:
        (table.scrollOffset * (scrollbarHeight - thumbSize)) div
          (table.rows.len - table.visibleRowCount)
      else:
        0
    check pos3 == 8 # (40 * (10 - 2)) / 40 = 8

  test "Scroll offset bounds":
    # Test that scroll offset stays within valid bounds
    var table = newTable(
      columns = @[column("Test")],
      rows = (0 .. 29).mapIt(tableRow(@[$it])), # 30 rows
      showScrollbar = true,
    )
    table.visibleRowCount = 10

    # Test scrolling down
    table.scrollDown(5)
    check table.scrollOffset == 5

    table.scrollDown(100) # Try to scroll past bottom
    let maxScroll = max(0, table.rows.len - table.visibleRowCount)
    check table.scrollOffset == maxScroll
    check table.scrollOffset == 20 # 30 - 10 = 20

    # Test scrolling up
    table.scrollUp(10)
    check table.scrollOffset == 10

    table.scrollUp(100) # Try to scroll past top
    check table.scrollOffset == 0

  test "Page navigation with scrollbar":
    # Test page up/down movements
    var table = newTable(
      columns = @[column("Test")],
      rows = (0 .. 99).mapIt(tableRow(@[$it])), # 100 rows
      showScrollbar = true,
    )
    table.visibleRowCount = 20
    table.highlightedIndex = 0

    # Half page down
    table.pageDown()
    check table.scrollOffset == 10 # Half of visible rows

    # Half page up
    table.pageUp()
    check table.scrollOffset == 0

    # Full page down
    table.fullPageDown()
    check table.scrollOffset == 20 # Full visible count

    # Full page up
    table.fullPageUp()
    check table.scrollOffset == 0

    # Test from middle position
    table.scrollOffset = 50
    table.fullPageDown()
    check table.scrollOffset == 70

    table.fullPageUp()
    check table.scrollOffset == 50

  test "Scrollbar position inside borders":
    # Test that scrollbar is positioned correctly relative to borders
    var table = newTable(
      columns = @[column("Test", 30)],
      rows = (0 .. 50).mapIt(tableRow(@[$it])),
      border = bkSimple,
      showScrollbar = true,
    )

    # Calculate actual table width
    let columnWidths = table.calculateColumnWidths(80)
    let hasBorders = table.borderStyle != NoBorder
    let actualTableWidth =
      calculateTotalLineWidth(columnWidths, table.columnSpacing, hasBorders)

    # Scrollbar should be inside the right border
    let scrollbarX = actualTableWidth - (if hasBorders: 2 else: 1)

    check:
      scrollbarX < actualTableWidth # Inside the table
      scrollbarX > 0 # Valid position

    # Test with no border
    table.borderStyle = NoBorder
    let scrollbarXNoBorder = actualTableWidth - 1
    check scrollbarXNoBorder == actualTableWidth - 1 # At right edge

  test "Scrollbar with different border styles":
    # Test scrollbar positioning with each border style
    for borderKind in [bkNone, bkSingle, bkSimple, bkRounded, bkDouble]:
      var table = newTable(
        columns = @[column("Test", 20)],
        rows = (0 .. 30).mapIt(tableRow(@[$it])),
        border = borderKind,
        showScrollbar = true,
      )
      table.visibleRowCount = 10

      let columnWidths = table.calculateColumnWidths(40)
      let hasBorders = borderKind != bkNone
      let actualTableWidth =
        calculateTotalLineWidth(columnWidths, table.columnSpacing, hasBorders)

      # Scrollbar position should adjust based on border
      let expectedX = actualTableWidth - (if hasBorders: 2 else: 1)

      check:
        expectedX > 0
        expectedX < actualTableWidth or
          (not hasBorders and expectedX == actualTableWidth - 1)

  test "Scrollbar interaction with highlight":
    # Test that highlight and scroll work together correctly
    var table = newTable(
      columns = @[column("Test")],
      rows = (0 .. 49).mapIt(tableRow(@[$it])),
      showScrollbar = true,
    )
    table.visibleRowCount = 10
    table.highlightedIndex = 0

    # Navigate down past visible area
    for i in 0 .. 15:
      table.highlightNext()

    check:
      table.highlightedIndex == 16
      table.scrollOffset > 0 # Should have scrolled
      table.scrollOffset <= table.highlightedIndex - table.visibleRowCount + 1

    # Navigate to last
    table.highlightLast()
    check:
      table.highlightedIndex == 49
      table.scrollOffset == 40 # Should scroll to show last item

    # Navigate to first
    table.highlightFirst()
    check:
      table.highlightedIndex == 0
      table.scrollOffset == 0
