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

proc copyWidget*[T: Widget](widget: T): T =
  ## Return a copy of the ref widget `widget`. Use this at the start of
  ## builder procs to ensure no fields are accidentally dropped when only a
  ## few fields need to change.
  ##
  ## Notes:
  ## - This copies the object the ref points to. Value fields (and
  ##   strings/seqs) are copied, but any nested `ref` fields (e.g. callbacks)
  ##   are shared with the original, not deep-copied.
  ## - The copy is created with the *static* type `T`, so calling this through
  ##   a base-typed parameter does not preserve a more-derived subtype.
  new(result)
  result[] = widget[]

template defineKeyMouseDispatch*(WidgetT: untyped) =
  ## Generate the standard `handleEvent` that forwards `EventKind.Key` to
  ## `handleKeyEvent(event.key)` and `EventKind.Mouse` to
  ## `handleMouseEvent(event.mouse, area)`. All other event kinds return
  ## `erContinue`. Use this for widgets that consume both key and mouse
  ## input via the existing per-kind handlers (e.g. `Button`, `List`).
  ##
  ## Widgets with custom dispatch (e.g. forwarding to child widgets) must
  ## override `handleEvent` themselves and not invoke this template.

  method handleEvent*(widget: WidgetT, event: Event, area: Rect): EventResult =
    case event.kind
    of EventKind.Key:
      widget.handleKeyEvent(event.key)
    of EventKind.Mouse:
      widget.handleMouseEvent(event.mouse, area)
    else:
      erContinue

template defineKeyDispatch*(WidgetT: untyped) =
  ## Generate the standard `handleEvent` that forwards `EventKind.Key` to
  ## `handleKeyEvent(event.key)` only. Other event kinds (mouse, paste,
  ## focus, resize) return `erContinue`. Use this for widgets that consume
  ## only key input (e.g. `Input`, `Table`).

  method handleEvent*(widget: WidgetT, event: Event, area: Rect): EventResult =
    case event.kind
    of EventKind.Key:
      widget.handleKeyEvent(event.key)
    else:
      erContinue
