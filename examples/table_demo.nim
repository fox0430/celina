## Table Widget Demo
##
## This example demonstrates advanced features of the Table widget including:
## - Custom column widths and alignment
## - table.Multiple selection mode
## - Custom styling
## - Different border styles
## - Scrolling with large datasets

import pkg/celina
import pkg/celina/Widgets/table

import std/[strformat, random, options, sequtils, strutils]

proc generateLargeDataset(): seq[seq[string]] =
  ## Generate a large dataset for demonstration
  randomize()
  result = @[]

  let firstNames =
    @[
      "Alice", "Bob", "Charlie", "Diana", "Eve", "Frank", "Grace", "Henry", "Ivy",
      "Jack", "Kate", "Liam", "Mia", "Noah", "Olivia", "Paul",
    ]
  let lastNames =
    @[
      "Smith", "Johnson", "Brown", "Wilson", "Davis", "Miller", "Lee", "Taylor",
      "Anderson", "Thomas", "Jackson", "White", "Harris", "Martin", "Thompson",
    ]
  let cities =
    @[
      "New York", "Los Angeles", "Chicago", "Houston", "Phoenix", "Philadelphia",
      "San Antonio", "San Diego", "Dallas", "San Jose", "Austin", "Jacksonville",
    ]
  let jobs =
    @[
      "Engineer", "Designer", "Developer", "Manager", "Analyst", "Consultant",
      "Director", "Specialist", "Coordinator", "Administrator", "Supervisor",
    ]

  for i in 0 ..< 50:
    let firstName = sample(firstNames)
    let lastName = sample(lastNames)
    let age = rand(22 .. 65)
    let city = sample(cities)
    let job = sample(jobs)
    let salary = rand(40000 .. 150000)

    result.add(@[&"{firstName} {lastName}", $age, city, job, &"${salary}"])

proc main() =
  # Create columns with custom properties
  let columns =
    @[
      newColumn("Name", some(25), AlignLeft),
      newColumn("Age", some(8), AlignCenter),
      newColumn("City", some(15), AlignLeft),
      newColumn("Job Title", some(18), AlignLeft),
      newColumn("Salary", some(12), AlignRight),
    ]

  # Generate sample data
  let data = generateLargeDataset()

  # Create the table widget with custom styling
  var tableWidget = newTable(
    columns = columns,
    rows = data.mapIt(tableRow(it)),
    selectionMode = table.Multiple,
    showHeader = true,
    borderStyle = table.RoundedBorder,
    columnSpacing = 1,
    showScrollbar = true,
    headerStyle = style(BrightWhite, Blue),
    normalRowStyle = defaultStyle(),
    selectedRowStyle = style(Black, BrightGreen),
    highlightedRowStyle = style(BrightWhite, BrightBlack),
    borderStyleOptions = style(BrightBlue),
  )

  # Variables for UI state
  var showHelp = true
  var currentBorderStyle = table.RoundedBorder
  var currentSelectionMode = table.Multiple

  # Configure the app
  var config = AppConfig(
    title: "Advanced Table Example",
    alternateScreen: true,
    mouseCapture: false,
    rawMode: true,
    windowMode: false,
    targetFps: 60,
  )

  var app = newApp(config)

  # Event handler
  app.onEvent do(event: Event) -> bool:
    case event.kind
    of EventKind.Key:
      # Handle application-specific keys first
      case event.key.code
      of KeyCode.Char:
        case event.key.char
        of "q":
          return false
        of "?": # Show/hide help with '?'
          showHelp = not showHelp
          return true
        of "B": # Capital B to cycle border styles (to avoid conflict with vim 'b')
          # Cycle through border styles
          currentBorderStyle =
            case currentBorderStyle
            of table.NoBorder: table.SimpleBorder
            of table.SimpleBorder: table.RoundedBorder
            of table.RoundedBorder: table.DoubleBorder
            of table.DoubleBorder: table.NoBorder
          tableWidget.borderStyle = currentBorderStyle
          return true
        of "M":
          # Capital M to cycle selection modes (to avoid conflict with vim movements)
          # Cycle through selection modes
          currentSelectionMode =
            case currentSelectionMode
            of table.None: table.Single
            of table.Single: table.Multiple
            of table.Multiple: table.None
          tableWidget.selectionMode = currentSelectionMode
          tableWidget.clearSelection()
          return true
        of "C": # Capital C to clear selection
          tableWidget.clearSelection()
          return true
        else:
          discard
      of KeyCode.Escape:
        return false
      else:
        discard

      # Let the table handle vim-like navigation and other keys
      if tableWidget.handleKeyEvent(event.key):
        return true
    else:
      discard
    return true

  # Render handler
  app.onRender do(buffer: var Buffer):
    buffer.clear()
    let area = buffer.area

    # Title and instructions
    buffer.setString(2, 0, "Advanced Table Example", style(BrightWhite, Blue))

    var currentY = 2

    if showHelp:
      let helpText =
        @[
          "Vim Navigation: j/k (↑↓) | g/G (first/last) | u/d (half page) | b/f (full page)",
          "Selection: Space/v (toggle) | Enter (select) | Esc (clear)",
          "Commands: '?' Help | 'B' Border | 'M' Mode | 'C' Clear | 'q' Quit",
        ]
      for line in helpText:
        buffer.setString(2, currentY, line, style(Yellow))
        currentY += 1
      currentY += 1

    # Status line
    let borderStyleName =
      case currentBorderStyle
      of table.NoBorder: "table.None"
      of table.SimpleBorder: "Simple"
      of table.RoundedBorder: "Rounded"
      of table.DoubleBorder: "Double"
    let selectionModeName =
      case currentSelectionMode
      of table.None: "table.None"
      of table.Single: "table.Single"
      of table.Multiple: "table.Multiple"

    let statusLine =
      &"Border: {borderStyleName} | Selection: {selectionModeName} | " &
      &"Rows: {tableWidget.rows.len} | Selected: {tableWidget.selectedIndices.len}"
    buffer.setString(2, currentY, statusLine, style(Cyan))
    currentY += 2

    # Calculate table area
    let statusAreaHeight = if showHelp: 8 else: 4
    let tableArea = rect(2, currentY, area.width - 4, area.height - statusAreaHeight)
    tableWidget.render(tableArea, buffer)

    # Show selection details at the bottom
    if tableWidget.selectedIndices.len > 0:
      let bottomY = area.height - 2
      if tableWidget.selectedIndices.len == 1:
        let selectedIndex = tableWidget.selectedIndices[0]
        let selectedRow = tableWidget.rows[selectedIndex]
        let info = "Selected: " & selectedRow.cells.join(" | ")
        let truncatedInfo =
          if info.len > area.width - 4:
            info[0 ..< (area.width - 7)] & "..."
          else:
            info
        buffer.setString(2, bottomY, truncatedInfo, style(Green))
      else:
        let info =
          &"table.Multiple selection: {tableWidget.selectedIndices.len} rows selected"
        buffer.setString(2, bottomY, info, style(Green))

  # Run the application
  app.run()

when isMainModule:
  main()
