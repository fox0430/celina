## Layout System Demo
##
## This example demonstrates Celina's constraint-based layout system.
## It shows various layout types: fixed, percentage, ratio, min/max, and fill constraints.

import std/[strformat]
import ../src/celina
import ../src/core/layout

type
  LayoutDemo = object
    current_demo: int
    demos: seq[LayoutDemoItem]

  LayoutDemoItem = object
    name: string
    description: string
    layout: Layout

proc createDemos(): seq[LayoutDemoItem] =
  @[
    LayoutDemoItem(
      name: "Fixed Lengths",
      description: "Fixed width columns: 20, 30, 15 cells",
      layout: horizontal(@[length(20), length(30), length(15)]),
    ),
    LayoutDemoItem(
      name: "Percentage Split",
      description: "Percentage columns: 30%, 50%, 20%",
      layout: horizontal(@[percentage(30), percentage(50), percentage(20)]),
    ),
    LayoutDemoItem(
      name: "Ratio Layout",
      description: "Ratio columns: 1:2:1 proportions",
      layout: horizontal(@[ratio(1, 4), ratio(2, 4), ratio(1, 4)]),
    ),
    LayoutDemoItem(
      name: "Fill Constraints",
      description: "Fill with priorities: equal, double, equal",
      layout: horizontal(@[fill(1), fill(2), fill(1)]),
    ),
    LayoutDemoItem(
      name: "Mixed Constraints",
      description: "Fixed 15, fill, percentage 25%, fill",
      layout: horizontal(@[length(15), fill(), percentage(25), fill()]),
    ),
    LayoutDemoItem(
      name: "Min/Max Constraints",
      description: "Min 10, fill, max 20, fill",
      layout: horizontal(@[min(10), fill(), max(20), fill()]),
    ),
    LayoutDemoItem(
      name: "Vertical Layout",
      description: "Vertical: header(3), content(fill), footer(2)",
      layout: vertical(@[length(3), fill(), length(2)]),
    ),
    LayoutDemoItem(
      name: "Nested Layout",
      description: "Complex nested layout example",
      layout: vertical(@[length(5), fill(), length(3)]),
    ),
    LayoutDemoItem(
      name: "With Margins",
      description: "Horizontal layout with 2-cell margins",
      layout: horizontal(@[fill(), fill(), fill()]).withMargin(2),
    ),
    LayoutDemoItem(
      name: "Even Split",
      description: "Even split into 4 parts",
      layout: evenSplit(4, Horizontal),
    ),
  ]

proc renderLayoutArea(
    buffer: var Buffer, area: Rect, index: int, total: int, constraint_info: string = ""
) =
  ## Render a single layout area with debug information
  if area.isEmpty():
    return

  # Choose color based on index
  let colors = [
    rgb(255, 100, 100), # Red
    rgb(100, 255, 100), # Green  
    rgb(100, 100, 255), # Blue
    rgb(255, 255, 100), # Yellow
    rgb(255, 100, 255), # Magenta
    rgb(100, 255, 255), # Cyan
    rgb(255, 150, 100), # Orange
    rgb(150, 255, 150), # Light Green
  ]
  let color = colors[index mod colors.len]

  # Fill area with background
  for y in area.y ..< (area.y + area.height):
    for x in area.x ..< (area.x + area.width):
      buffer.setString(x, y, " ", style(defaultColor(), color))

  # Add border
  if area.width >= 2 and area.height >= 2:
    # Top and bottom borders
    for x in area.x ..< (area.x + area.width):
      buffer.setString(x, area.y, "─", style(color(Color.White), color))
      buffer.setString(
        x, area.y + area.height - 1, "─", style(color(Color.White), color)
      )

    # Left and right borders  
    for y in area.y ..< (area.y + area.height):
      buffer.setString(area.x, y, "│", style(color(Color.White), color))
      buffer.setString(
        area.x + area.width - 1, y, "│", style(color(Color.White), color)
      )

    # Corners
    buffer.setString(area.x, area.y, "┌", style(color(Color.White), color))
    buffer.setString(
      area.x + area.width - 1, area.y, "┐", style(color(Color.White), color)
    )
    buffer.setString(
      area.x, area.y + area.height - 1, "└", style(color(Color.White), color)
    )
    buffer.setString(
      area.x + area.width - 1,
      area.y + area.height - 1,
      "┘",
      style(color(Color.White), color),
    )

  # Add area info
  if area.width >= 8 and area.height >= 3:
    let info = &"Area {index + 1}"
    let size_info = &"{area.width}×{area.height}"

    let info_x = area.x + (area.width - info.len) div 2
    let size_x = area.x + (area.width - size_info.len) div 2

    if info_x >= area.x and info_x + info.len <= area.x + area.width:
      buffer.setString(
        info_x, area.y + 1, info, style(color(Color.Black), color, modifiers = {Bold})
      )

    if size_x >= area.x and size_x + size_info.len <= area.x + area.width and
        area.height >= 4:
      buffer.setString(size_x, area.y + 2, size_info, style(color(Color.Black), color))

    # Add constraint info if provided and there's space
    if constraint_info.len > 0 and area.height >= 5:
      let const_x = area.x + (area.width - constraint_info.len) div 2
      if const_x >= area.x and const_x + constraint_info.len <= area.x + area.width:
        buffer.setString(
          const_x, area.y + 3, constraint_info, style(color(Color.Black), color)
        )

proc main() =
  var state = LayoutDemo(current_demo: 0, demos: createDemos())

  quickRun(
    eventHandler = proc(event: Event): bool =
      case event.kind
      of EventKind.Key:
        case event.key.code
        of KeyCode.Char:
          case event.key.char
          of 'q':
            return false
          of 'n', ' ':
            state.current_demo = (state.current_demo + 1) mod state.demos.len
          of 'p':
            state.current_demo =
              (state.current_demo - 1 + state.demos.len) mod state.demos.len
          of '1' .. '9':
            let index = ord(event.key.char) - ord('1')
            if index < state.demos.len:
              state.current_demo = index
          of '0':
            if state.demos.len >= 10:
              state.current_demo = 9
          else:
            discard
        of KeyCode.Escape:
          return false
        of KeyCode.ArrowRight:
          state.current_demo = (state.current_demo + 1) mod state.demos.len
        of KeyCode.ArrowLeft:
          state.current_demo =
            (state.current_demo - 1 + state.demos.len) mod state.demos.len
        else:
          discard
      else:
        discard
      return true,
    renderHandler = proc(buffer: var Buffer) =
      buffer.clear()

      let area = buffer.area
      let demo = state.demos[state.current_demo]

      # Title
      let title = "Constraint-Based Layout Demo"
      buffer.setString(
        area.width div 2 - title.len div 2,
        1,
        title,
        style(Color.Cyan, modifiers = {Bold, Underline}),
      )

      # Current demo info
      let demo_info = &"Demo {state.current_demo + 1}/{state.demos.len}: {demo.name}"
      buffer.setString(
        area.width div 2 - demo_info.len div 2,
        3,
        demo_info,
        style(Color.Yellow, modifiers = {Bold}),
      )

      # Description
      buffer.setString(
        area.width div 2 - demo.description.len div 2,
        4,
        demo.description,
        style(Color.White),
      )

      # Layout demonstration area
      let layout_area = rect(5, 7, area.width - 10, area.height - 15)

      # Handle nested layout demo specially
      if state.current_demo == 7: # Nested layout demo
        let outer_areas = demo.layout.split(layout_area)
        if outer_areas.len >= 3:
          # Render header
          renderLayoutArea(buffer, outer_areas[0], 0, 3, "Header")

          # Split middle area horizontally
          let middle_layout = horizontal(@[percentage(30), fill(), percentage(25)])
          let middle_areas = middle_layout.split(outer_areas[1])

          for i, sub_area in middle_areas:
            let labels = ["Sidebar", "Content", "Panel"]
            let label =
              if i < labels.len:
                labels[i]
              else:
                &"Area {i+1}"
            renderLayoutArea(buffer, sub_area, i + 1, middle_areas.len + 2, label)

          # Render footer
          renderLayoutArea(
            buffer, outer_areas[2], middle_areas.len + 1, middle_areas.len + 2, "Footer"
          )
      else:
        # Regular layout demo
        let areas = demo.layout.split(layout_area)

        for i, layout_area in areas:
          # Generate constraint info for display
          let constraint =
            if i < demo.layout.constraints.len:
              $demo.layout.constraints[i]
            else:
              ""
          renderLayoutArea(buffer, layout_area, i, areas.len, constraint)

      # Layout details
      let details_y = area.height - 7
      buffer.setString(
        2, details_y, "Layout Details:", style(Color.Green, modifiers = {Bold})
      )

      let direction_info = &"Direction: {demo.layout.direction}"
      buffer.setString(2, details_y + 1, direction_info, style(Color.BrightBlack))

      let constraint_info = &"Constraints: {demo.layout.constraints}"
      if constraint_info.len <= area.width - 4:
        buffer.setString(2, details_y + 2, constraint_info, style(Color.BrightBlack))
      else:
        buffer.setString(
          2, details_y + 2, "Constraints: (see areas above)", style(Color.BrightBlack)
        )

      # Controls
      let controls = [
        "Controls:", "←/→ or n/p - Navigate demos", "1-9,0 - Jump to demo",
        "q/ESC - Quit",
      ]

      for i, control in controls:
        let color = if i == 0: Color.Yellow else: Color.BrightBlack
        let modifiers =
          if i == 0:
            {Bold}
          else:
            {}
        buffer.setString(
          2, area.height - 4 + i, control, style(color, modifiers = modifiers)
        ),
  )

when isMainModule:
  echo "Starting Layout Demo..."
  echo "This demonstrates the constraint-based layout system"
  echo "Use ←/→ or n/p to navigate between demos"
  main()
