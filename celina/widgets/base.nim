## Base widget system for Celina CLI library
##
## This module defines the fundamental widget traits and base classes
## for building UI components.

import ../core/[geometry, buffer]

type Widget* = ref object of RootObj ## Base widget type - all widgets inherit from this

method render*(widget: Widget, area: Rect, buf: var Buffer) {.base.} =
  ## Render the widget into the given buffer area
  ## Default implementation does nothing
  discard

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
