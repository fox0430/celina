## List Widget Demo
##
## Demonstrates various list widget features including:
## - Single and multiple selection modes
## - Keyboard and mouse navigation
## - Scrolling for long lists
## - Custom styling and bullets

import std/[strformat, sequtils, strutils]

import pkg/celina
import pkg/celina/widgets/list

proc main() =
  var selectedItem = -1
  var multipleSelection: seq[int] = @[]
  var listMode = 0 # 0: single select, 1: multi select, 2: no selection

  # Create items for the list
  let items = (1 .. 30).mapIt(fmt"Item {it}")

  # Create the list widget with single selection mode initially
  var listWidget = selectList(
    items,
    onSelect = proc(index: int) =
      selectedItem = index,
  )

  # Configure the list
  listWidget.setState(Focused)

  let config = AppConfig(
    title: "List Widget Demo",
    alternateScreen: true,
    mouseCapture: true,
    rawMode: true,
    targetFps: 30,
  )

  var app = newApp(config)

  app.onEvent proc(event: Event): bool =
    case event.kind
    of EventKind.Key:
      case event.key.code
      of KeyCode.Escape, KeyCode.Char:
        if event.key.code == Escape or (
          event.key.code == Char and event.key.char == "q"
        ):
          return false
        elif event.key.code == Char:
          case event.key.char
          of "1":
            # Switch to single selection mode
            listMode = 0
            listWidget = selectList(
              items,
              onSelect = proc(index: int) =
                selectedItem = index,
            )
            listWidget.setState(Focused)
          of "2":
            # Switch to multiple selection mode
            listMode = 1
            listWidget = checkList(
              items,
              onMultiSelect = proc(indices: seq[int]) =
                multipleSelection = indices,
            )
            listWidget.setState(Focused)
          of "3":
            # Switch to no selection mode with bullets
            listMode = 2
            listWidget = bulletList(items, "→ ")
            listWidget.setState(Focused)
          of "c":
            # Clear selection
            listWidget.clearSelection()
            selectedItem = -1
            multipleSelection = @[]
          else:
            # Pass other keys to the list widget
            discard listWidget.handleKeyEvent(event.key)
      else:
        # Pass navigation keys to the list widget
        discard listWidget.handleKeyEvent(event.key)
    of EventKind.Mouse:
      # Pass mouse events to the list widget
      # We use hardcoded area calculation here to match render
      let listWidth = 50
      let listHeight = 20
      let listX = 15 # Approximate center for 80-column terminal
      let listY = 4
      let listArea = rect(listX, listY, listWidth, listHeight)
      discard listWidget.handleMouseEvent(event.mouse, listArea)
    else:
      discard

    return true

  app.onRender proc(buffer: var Buffer) =
    buffer.clear()
    let area = buffer.area

    # Draw title
    let title = "List Widget Demo"
    let titleX = (area.width - title.len) div 2
    buffer.setString(titleX, 0, title, bold())

    # Draw instructions
    let instructions = [
      "Navigation: ↑/↓ or j/k | Select: Enter/Space | Scroll: Mouse wheel",
      "Modes: [1] Single Select | [2] Multi Select | [3] No Selection",
      "Commands: [c] Clear Selection | [q] Quit",
    ]

    for i, instruction in instructions:
      let instrX = (area.width - instruction.len) div 2
      buffer.setString(instrX, 1 + i, instruction, style(BrightBlack))

    # Calculate list area (centered)
    let listWidth = min(50, area.width - 4)
    let listHeight = min(20, area.height - 8)
    let listX = (area.width - listWidth) div 2
    let listY = 4
    let listArea = rect(listX, listY, listWidth, listHeight)

    # Draw border around list
    for y in 0 ..< listHeight + 2:
      for x in 0 ..< listWidth + 2:
        let cellX = listX - 1 + x
        let cellY = listY - 1 + y

        if y == 0:
          if x == 0:
            buffer.setString(cellX, cellY, "┌", style(BrightBlack))
          elif x == listWidth + 1:
            buffer.setString(cellX, cellY, "┐", style(BrightBlack))
          else:
            buffer.setString(cellX, cellY, "─", style(BrightBlack))
        elif y == listHeight + 1:
          if x == 0:
            buffer.setString(cellX, cellY, "└", style(BrightBlack))
          elif x == listWidth + 1:
            buffer.setString(cellX, cellY, "┘", style(BrightBlack))
          else:
            buffer.setString(cellX, cellY, "─", style(BrightBlack))
        else:
          if x == 0 or x == listWidth + 1:
            buffer.setString(cellX, cellY, "│", style(BrightBlack))

    # Render the list widget
    listWidget.render(listArea, buffer)

    # Show selection status at the bottom
    let statusY = listY + listHeight + 3
    var statusText = ""
    var statusColor = style(Yellow)

    case listMode
    of 0:
      if selectedItem >= 0:
        statusText = fmt"Selected: {items[selectedItem]}"
      else:
        statusText = "No selection"
    of 1:
      if multipleSelection.len > 0:
        let selectedItems = multipleSelection.mapIt(items[it]).join(", ")
        statusText = fmt"Selected {multipleSelection.len} items: {selectedItems}"
        # Truncate if too long
        let maxWidth = area.width - 4
        if statusText.len > maxWidth:
          statusText = statusText[0 ..< maxWidth - 3] & "..."
      else:
        statusText = "No items selected"
    else:
      statusText = "Display mode - no selection"
      statusColor = style(BrightBlack)

    let statusX = (area.width - statusText.len) div 2
    buffer.setString(statusX, statusY, statusText, statusColor)

  app.run()

when isMainModule:
  main()
