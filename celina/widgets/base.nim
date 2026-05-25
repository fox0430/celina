## Base widget system for Celina CLI library
##
## This module defines the fundamental widget traits and base classes
## for building UI components.

import ../core/[geometry, buffer, events]

# Re-export the event surface so widget consumers (and Widget subclasses
# overriding `handleEvent`) get `Event`, `EventKind`, `EventResult`, plus
# `KeyEvent`/`KeyCode`/`MouseEvent`/`MouseEventKind`/`KeyModifier` without
# needing to import `core/events` separately.
export events

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

method handleEvent*(widget: Widget, event: Event, area: Rect): EventResult {.base.} =
  ## Dispatch a unified `Event` to the widget.
  ##
  ## Concrete widgets override this to consume key/mouse/paste/etc.; the
  ## default implementation returns `erContinue` so events propagate upward
  ## (to the window/global handler) when a widget does not care.
  ##
  ## `area` is the rect the widget was last rendered into and is required
  ## for mouse hit-testing. Widgets that only react to keys may ignore it.
  erContinue

method setFocus*(widget: Widget, focused: bool) {.base.} =
  ## Set this widget's focus state. Default implementation is a no-op so
  ## focusable widgets can override without forcing every widget to track
  ## focus.
  discard

method isFocused*(widget: Widget): bool {.base.} =
  ## Query this widget's focus state. Default implementation returns false.
  false
