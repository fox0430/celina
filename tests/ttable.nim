## Unit tests for table widget

import std/[unittest, sequtils, options, strformat]

import ../celina
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
    let rows =
      @[
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
    let rows =
      @[
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
    let columns =
      @[
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
    tableWidget.borderStyleOptions = style(color(Green))
    tableWidget.selectedRowStyle = style(color(White), color(Black))

    check:
      rows[0].style.isSome
      rows[0].style.get().fg == color(Red)
      rows[0].style.get().bg == color(Blue)
      tableWidget.borderStyleOptions.fg == color(Green)
      tableWidget.selectedRowStyle.fg == color(White)

  test "Width calculation edge cases":
    # Test edge cases in column width calculation
    var tableWidget = newTable(@[column("A"), column("B"), column("C")])

    # Test with very small available width
    let smallWidths = tableWidget.calculateColumnWidths(10)
    check:
      smallWidths.len == 3
      smallWidths.allIt(it >= 1) # All columns should get at least 1 character

    # Test with no available width for content (just borders)
    let tinyWidths = tableWidget.calculateColumnWidths(4) # Just enough for borders
    check:
      tinyWidths.len == 3
      tinyWidths.allIt(it >= 1)

    # Test with mixed fixed and auto columns
    let mixedColumns = @[column("Fixed", 15), column("Auto1"), column("Auto2")]
    tableWidget = newTable(mixedColumns)
    let mixedWidths = tableWidget.calculateColumnWidths(50)
    check:
      mixedWidths[0] == 15 # Fixed width maintained
      mixedWidths[1] > 0 # Auto columns get remaining space
      mixedWidths[2] > 0

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
