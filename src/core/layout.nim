#core/layout.nim# Constraint-based layout system for Celina CLI library
##
## This module provides a flexible constraint-based layout system similar to
## Ratatui's layout capabilities, allowing for responsive UI design.

import std/[math, strformat]
import geometry

type
  Direction* = enum
    ## Layout direction for arranging elements
    Horizontal ## Arrange elements side by side (left to right)
    Vertical ## Arrange elements top to bottom

  ConstraintKind* = enum
    ## Types of constraints for layout calculation
    Length ## Fixed length in terminal cells
    Percentage ## Percentage of available space (0-100)
    Ratio ## Ratio of available space (numerator, denominator)
    Min ## Minimum size constraint
    Max ## Maximum size constraint
    Fill ## Fill remaining space after other constraints

  Constraint* = object ## A layout constraint defining how space should be allocated
    case kind*: ConstraintKind
    of Length:
      length*: int
    of Percentage:
      percentage*: int ## 0-100
    of Ratio:
      numerator*: int
      denominator*: int
    of Min:
      min*: int
    of Max:
      max*: int
    of Fill:
      priority*: int ## Higher priority gets more space (default: 1)

  Layout* = object ## Layout configuration for arranging widgets
    direction*: Direction
    constraints*: seq[Constraint]
    margin*: int
    horizontal_margin*: int
    vertical_margin*: int

  LayoutSolver* = object ## Internal solver for constraint resolution
    available_space: int
    results: seq[int]

# Constraint constructors
proc length*(value: int): Constraint {.inline.} =
  ## Create a fixed length constraint
  Constraint(kind: Length, length: max(0, value))

proc percentage*(value: int): Constraint {.inline.} =
  ## Create a percentage constraint (0-100)
  Constraint(kind: Percentage, percentage: clamp(value, 0, 100))

proc ratio*(numerator, denominator: int): Constraint =
  ## Create a ratio constraint
  ## Uses 1:1 ratio if denominator is invalid
  let safeDenominator = if denominator <= 0: 1 else: denominator
  Constraint(kind: Ratio, numerator: max(0, numerator), denominator: safeDenominator)

proc min*(value: int): Constraint {.inline.} =
  ## Create a minimum size constraint
  Constraint(kind: Min, min: max(0, value))

proc max*(value: int): Constraint {.inline.} =
  ## Create a maximum size constraint
  Constraint(kind: Max, max: max(0, value))

proc fill*(priority: int = 1): Constraint {.inline.} =
  ## Create a fill constraint with optional priority
  Constraint(kind: Fill, priority: max(1, priority))

# Layout constructor
proc layout*(
    direction: Direction = Vertical, constraints: seq[Constraint] = @[], margin: int = 0
): Layout {.inline.} =
  ## Create a new Layout
  Layout(
    direction: direction,
    constraints: constraints,
    margin: margin,
    horizontal_margin: margin,
    vertical_margin: margin,
  )

proc withMargin*(layout: Layout, margin: int): Layout {.inline.} =
  ## Create a layout with uniform margin
  Layout(
    direction: layout.direction,
    constraints: layout.constraints,
    margin: margin,
    horizontal_margin: margin,
    vertical_margin: margin,
  )

proc withMargins*(layout: Layout, horizontal, vertical: int): Layout {.inline.} =
  ## Create a layout with different horizontal and vertical margins
  Layout(
    direction: layout.direction,
    constraints: layout.constraints,
    margin: 0,
    horizontal_margin: horizontal,
    vertical_margin: vertical,
  )

# Constraint solver implementation
proc initSolver(available_space: int, constraint_count: int): LayoutSolver {.inline.} =
  ## Initialize a new layout solver
  LayoutSolver(available_space: available_space, results: newSeq[int](constraint_count))

proc solveConstraints(solver: var LayoutSolver, constraints: seq[Constraint]) =
  ## Solve all constraints and fill the results array
  if constraints.len == 0:
    return

  # Initialize all results to 0
  for i in 0 ..< solver.results.len:
    solver.results[i] = 0

  var remaining_space = solver.available_space
  var unsolved_indices: seq[int] = @[]

  # Phase 1: Solve fixed constraints (Length, Percentage, Ratio)
  for i, constraint in constraints:
    case constraint.kind
    of Length:
      solver.results[i] = min(constraint.length, remaining_space)
      remaining_space -= solver.results[i]
    of Percentage:
      let size = (solver.available_space * constraint.percentage) div 100
      solver.results[i] = min(size, remaining_space)
      remaining_space -= solver.results[i]
    of Ratio:
      let size =
        (solver.available_space * constraint.numerator) div constraint.denominator
      solver.results[i] = min(size, remaining_space)
      remaining_space -= solver.results[i]
    else:
      unsolved_indices.add(i)

  # Phase 2: Apply Min constraints
  var solved_min_indices: seq[int] = @[]
  for i in unsolved_indices:
    let constraint = constraints[i]
    if constraint.kind == Min:
      let needed = constraint.min
      if needed <= remaining_space:
        solver.results[i] = needed
        remaining_space -= needed
        solved_min_indices.add(i)

  # Remove solved min constraints from unsolved list
  for solved in solved_min_indices:
    let idx = unsolved_indices.find(solved)
    if idx >= 0:
      unsolved_indices.delete(idx)

  # Phase 3: Distribute remaining space to Fill constraints
  var fill_indices: seq[int] = @[]
  var total_priority = 0

  for i in unsolved_indices:
    if constraints[i].kind == Fill:
      fill_indices.add(i)
      total_priority += constraints[i].priority

  if fill_indices.len > 0 and remaining_space > 0:
    var allocated_total = 0
    for i in fill_indices:
      let priority = constraints[i].priority
      let allocated = (remaining_space * priority) div total_priority
      solver.results[i] = allocated
      allocated_total += allocated

    # Distribute any remaining space due to integer division
    var leftover = remaining_space - allocated_total
    for i in fill_indices:
      if leftover > 0:
        solver.results[i] += 1
        leftover -= 1

  # Phase 4: Apply Max constraints as post-processing
  for i, constraint in constraints:
    if constraint.kind == Max:
      if solver.results[i] > constraint.max:
        let excess = solver.results[i] - constraint.max
        solver.results[i] = constraint.max
        remaining_space += excess

proc split*(layout: Layout, area: Rect): seq[Rect] =
  ## Split an area according to the layout constraints
  if layout.constraints.len == 0:
    return @[area]

  # Apply margins to get the working area
  let working_area = area.shrink(layout.horizontal_margin, layout.vertical_margin)

  # Determine available space based on direction
  let available_space =
    case layout.direction
    of Horizontal: working_area.width
    of Vertical: working_area.height

  # Solve constraints
  var solver = initSolver(available_space, layout.constraints.len)
  solver.solveConstraints(layout.constraints)

  # Create result rectangles
  var results: seq[Rect] = @[]
  var current_pos =
    case layout.direction
    of Horizontal: working_area.x
    of Vertical: working_area.y

  for i, size in solver.results:
    let rect =
      case layout.direction
      of Horizontal:
        rect(current_pos, working_area.y, size, working_area.height)
      of Vertical:
        rect(working_area.x, current_pos, working_area.width, size)

    results.add(rect)
    current_pos += size

  return results

# Convenience functions for common layout patterns
proc horizontal*(constraints: seq[Constraint], margin: int = 0): Layout {.inline.} =
  ## Create a horizontal layout
  layout(Horizontal, constraints, margin)

proc vertical*(constraints: seq[Constraint], margin: int = 0): Layout {.inline.} =
  ## Create a vertical layout
  layout(Vertical, constraints, margin)

proc evenSplit*(count: int, direction: Direction = Vertical): Layout {.inline.} =
  ## Create a layout that splits space evenly
  var constraints: seq[Constraint] = @[]
  for i in 0 ..< count:
    constraints.add(fill())
  layout(direction, constraints)

proc twoColumn*(left_width: int): Layout {.inline.} =
  ## Create a two-column layout with fixed left width
  horizontal(@[length(left_width), fill()])

proc twoColumnPercent*(left_percent: int): Layout {.inline.} =
  ## Create a two-column layout with percentage-based left width
  horizontal(@[percentage(left_percent), percentage(100 - left_percent)])

proc threeRow*(header_height, footer_height: int): Layout {.inline.} =
  ## Create a three-row layout (header, content, footer)
  vertical(@[length(header_height), fill(), length(footer_height)])

# String representation for debugging
proc `$`*(constraint: Constraint): string =
  case constraint.kind
  of Length:
    &"Length({constraint.length})"
  of Percentage:
    &"Percentage({constraint.percentage}%)"
  of Ratio:
    &"Ratio({constraint.numerator}/{constraint.denominator})"
  of Min:
    &"Min({constraint.min})"
  of Max:
    &"Max({constraint.max})"
  of Fill:
    &"Fill(priority={constraint.priority})"

proc `$`*(layout: Layout): string =
  let dir = if layout.direction == Horizontal: "Horizontal" else: "Vertical"
  let constraints_str = $layout.constraints
  &"Layout({dir}, {constraints_str}, margin={layout.margin})"
