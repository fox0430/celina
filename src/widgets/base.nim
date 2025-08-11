## Base widget system for Celina CLI library
##
## This module defines the fundamental widget traits and base classes
## for building UI components.

import ../core/[geometry, buffer]

type
  Widget* = ref object of RootObj ## Base widget type - all widgets inherit from this

  StatefulWidget*[T] = ref object of Widget ## Widget with internal state
    state*: T

# Core widget rendering method
method render*(widget: Widget, area: Rect, buf: var Buffer) {.base.} =
  ## Render the widget into the given buffer area
  ## Default implementation does nothing
  discard

proc renderStateful*[T](widget: StatefulWidget[T], area: Rect, buf: var Buffer) =
  ## Render a stateful widget
  ## Default implementation does nothing
  discard

# Widget utility methods
method getMinSize*(widget: Widget): Size {.base.} =
  ## Get the minimum size required by this widget
  ## Default: no minimum size constraint
  size(0, 0)

method getPreferredSize*(widget: Widget, available: Size): Size {.base.} =
  ## Get the preferred size for the given available space
  ## Default: use all available space
  available

method canFocus*(widget: Widget): bool {.base.} =
  ## Check if this widget can receive focus
  ## Default: widgets cannot receive focus
  false

# Widget creation utilities
proc newWidget*(): Widget =
  ## Create a new base widget
  Widget()

proc newStatefulWidget*[T](initialState: T): StatefulWidget[T] =
  ## Create a new stateful widget with initial state
  StatefulWidget[T](state: initialState)

# Widget composition utilities
proc renderWidget*(widget: Widget, area: Rect, buf: var Buffer) =
  ## Convenience function to render any widget
  widget.render(area, buf)

proc renderWidgetAt*(widget: Widget, x, y, width, height: int, buf: var Buffer) =
  ## Render widget at specific coordinates
  let area = rect(x, y, width, height)
  widget.render(area, buf)

# Widget measurement utilities
proc measureWidget*(widget: Widget, available: Size): Size =
  ## Measure how much space a widget wants
  let minSize = widget.getMinSize()
  let preferredSize = widget.getPreferredSize(available)

  size(
    max(minSize.width, min(preferredSize.width, available.width)),
    max(minSize.height, min(preferredSize.height, available.height)),
  )

proc constrainSize*(requested: Size, available: Size, minimum: Size): Size =
  ## Constrain a size within bounds
  size(
    max(minimum.width, min(requested.width, available.width)),
    max(minimum.height, min(requested.height, available.height)),
  )

# Widget state management for StatefulWidget
proc getState*[T](widget: StatefulWidget[T]): T =
  ## Get the current state of a stateful widget
  widget.state

proc setState*[T](widget: StatefulWidget[T], newState: T) =
  ## Set the state of a stateful widget
  widget.state = newState

proc updateState*[T](widget: StatefulWidget[T], updateFn: proc(state: T): T) =
  ## Update the state using a function
  widget.state = updateFn(widget.state)
