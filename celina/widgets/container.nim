## Container widget — a base for widgets that hold and dispatch to children.
##
## `Container` provides a generic shell for composite widgets: it owns a
## `seq[Widget]` of children and a `focusedIndex`, and forwards `handleEvent`
## to the currently focused child. Concrete containers (e.g. `Tabs`,
## vertical/horizontal layouts) typically inherit from `Container` and add
## their own `render` plus a layout-aware override of `handleEvent` when
## mouse hit-testing requires it.
##
## The default `handleEvent` is layout-naive: it passes the container's full
## `area` to the focused child. That is correct for single-active-child
## containers (only one child is visible/interactive at a time) and good
## enough as a fallback for multi-child layouts that don't care about
## precise mouse routing.

import base

import ../core/geometry

type Container* = ref object of Widget
  ## Generic container holding child widgets and a focus index.
  ##
  ## - `children` is the ordered list of child widgets.
  ## - `focusedIndex` is the index of the child currently receiving events.
  ##   `-1` means no child is focused (events are not forwarded).
  children*: seq[Widget]
  focusedIndex*: int

proc newContainer*(children: seq[Widget] = @[], focusedIndex: int = -1): Container =
  ## Construct a new `Container`. `focusedIndex` is clamped to the valid
  ## range, or set to `-1` when `children` is empty. When the resolved
  ## index is valid, the corresponding child is notified via
  ## `setFocus(true)` so widget focus state stays in sync with the
  ## container.
  let idx =
    if children.len == 0:
      -1
    else:
      max(-1, min(focusedIndex, children.len - 1))
  result = Container(children: children, focusedIndex: idx)
  if idx >= 0:
    children[idx].setFocus(true)

proc focusedChild*(c: Container): Widget =
  ## Return the currently focused child, or `nil` if none.
  if c.focusedIndex < 0 or c.focusedIndex >= c.children.len:
    return nil
  c.children[c.focusedIndex]

proc setFocusedIndex*(c: Container, index: int) =
  ## Move focus to the child at `index`. Out-of-range values clear focus
  ## (the resolved index becomes `-1`). If the resolved index equals the
  ## current `focusedIndex` this is a no-op — `setFocus` is not re-issued
  ## on the same child. Otherwise calls `setFocus(false)` on the previous
  ## child and `setFocus(true)` on the new one.
  let newIndex = if index < 0 or index >= c.children.len: -1 else: index
  if newIndex == c.focusedIndex:
    return
  let prev = c.focusedChild()
  if prev != nil:
    prev.setFocus(false)
  c.focusedIndex = newIndex
  let next = c.focusedChild()
  if next != nil:
    next.setFocus(true)

proc focusNext*(c: Container): bool =
  ## Move focus to the next focusable child. Wraps around at the end.
  ## Returns `true` when focus moved, `false` when there is no focusable
  ## child (including the empty-container case).
  if c.children.len == 0:
    return false
  let start = c.focusedIndex
  var i =
    if start < 0:
      0
    else:
      (start + 1) mod c.children.len
  for _ in 0 ..< c.children.len:
    if c.children[i].canFocus():
      c.setFocusedIndex(i)
      return true
    i = (i + 1) mod c.children.len
  false

proc focusPrev*(c: Container): bool =
  ## Move focus to the previous focusable child. Wraps around at the start.
  if c.children.len == 0:
    return false
  let start = c.focusedIndex
  let n = c.children.len
  var i =
    if start < 0:
      n - 1
    else:
      (start - 1 + n) mod n
  for _ in 0 ..< n:
    if c.children[i].canFocus():
      c.setFocusedIndex(i)
      return true
    i = (i - 1 + n) mod n
  false

proc addChild*(c: Container, child: Widget) =
  ## Append a child. Does not change `focusedIndex` — if you want the
  ## first appended child to receive focus, call `setFocusedIndex(0)`
  ## afterwards, or pass the seq through `newContainer(focusedIndex = …)`.
  ## Keeping this proc focus-neutral lets callers build the children list
  ## first and decide focus separately (e.g. after a layout pass).
  c.children.add(child)

method canFocus*(c: Container): bool =
  ## A container can focus if at least one child can.
  for child in c.children:
    if child.canFocus():
      return true
  false

method handleEvent*(c: Container, event: Event, area: Rect): EventResult =
  ## Forward the event to the focused child, passing the container's full
  ## area. Returns `erContinue` when no child is focused or the focused
  ## child does not consume the event.
  let child = c.focusedChild()
  if child == nil:
    return erContinue
  child.handleEvent(event, area)

method setFocus*(c: Container, focused: bool) =
  ## Propagate focus to a child.
  ##
  ## - `focused = true`: if a child is already selected, notify it. If no
  ##   child is selected (`focusedIndex == -1`), pick the first focusable
  ##   child via `focusNext()` so receiving focus actually lands somewhere
  ##   interactive — otherwise the container would silently swallow focus.
  ## - `focused = false`: notify the currently focused child but preserve
  ##   `focusedIndex` so focus can be restored on re-entry.
  if focused and c.focusedChild() == nil:
    discard c.focusNext()
    return
  let child = c.focusedChild()
  if child != nil:
    child.setFocus(focused)

method isFocused*(c: Container): bool =
  let child = c.focusedChild()
  child != nil and child.isFocused()
