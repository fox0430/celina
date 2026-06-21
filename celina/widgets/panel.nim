## Panel widget for Celina CLI library
##
## A `Panel` is a rectangular surface that can draw a border on any subset of
## its four sides, show a title on the top edge, apply inner padding, and
## optionally fill its background and host a single child widget. It is the
## general-purpose framing primitive — the widget analogue of the window
## border in `core/windows` — inspired by Ratatui's `Block`.
##
## Use `inner` to obtain the content rectangle (inside the borders and
## padding) when you want to render your own content rather than handing a
## child widget to the panel.
##
## ### Usage Example:
## ```nim
## # Framed box with a centered title
## let p = newPanel()
##   .withBorders({bsTop, bsBottom, bsLeft, bsRight})
##   .withBorderKind(bkRounded)
##   .withTitle("Status", taCenter)
##
## p.render(area, buf)
##
## # Render custom content inside the frame
## let content = p.inner(area)
## buf.setString(content.x, content.y, "Hello", defaultStyle())
## ```

import base

import ../core/[geometry, buffer, colors, borders]

export borders.BorderKind, borders.BorderChars, borders.getBorderChars

type
  BorderSide* = enum
    ## A single edge of a `Panel`. Combine sides in a `set[BorderSide]` to
    ## select which edges are drawn (e.g. `{bsTop, bsLeft}`).
    bsTop
    bsRight
    bsBottom
    bsLeft

  TitleAlignment* = enum
    ## Horizontal placement of the title along the top edge.
    taLeft
    taCenter
    taRight

  Padding* = object ## Inner spacing between the border and the content area.
    top*, right*, bottom*, left*: int

  Panel* = ref object of Widget
    ## Framing widget: border, title, padding, fill, and an optional child.
    borders*: set[BorderSide] ## Which edges draw a border line.
    borderKind*: BorderKind ## Glyph set used for the border lines.
    borderStyle*: Style ## Style applied to the border glyphs.
    title*: string ## Title text drawn on the top edge (empty for none).
    titleAlignment*: TitleAlignment ## Horizontal placement of the title.
    titleStyle*: Style ## Style applied to the title text.
    style*: Style ## Fill style for the panel's interior (background).
    padding*: Padding ## Inner spacing between border and content.
    child*: Widget ## Optional child rendered into the content area.

# Construction helpers

proc padding*(all: int): Padding {.inline.} =
  ## Uniform padding on all four sides.
  Padding(top: all, right: all, bottom: all, left: all)

proc padding*(horizontal, vertical: int): Padding {.inline.} =
  ## Symmetric padding: `horizontal` on left/right, `vertical` on top/bottom.
  Padding(top: vertical, right: horizontal, bottom: vertical, left: horizontal)

proc padding*(top, right, bottom, left: int): Padding {.inline.} =
  ## Per-side padding.
  Padding(top: top, right: right, bottom: bottom, left: left)

const allBorders* = {bsTop, bsRight, bsBottom, bsLeft}
  ## Convenience set selecting every edge.

proc newPanel*(
    borders: set[BorderSide] = allBorders,
    borderKind: BorderKind = bkSingle,
    borderStyle: Style = defaultStyle(),
    title: string = "",
    titleAlignment: TitleAlignment = taLeft,
    titleStyle: Style = defaultStyle(),
    style: Style = defaultStyle(),
    padding: Padding = Padding(),
    child: Widget = nil,
): Panel =
  ## Create a new `Panel`. By default it draws a single-line border on all
  ## sides with no title, no padding, and no fill.
  Panel(
    borders: borders,
    borderKind: borderKind,
    borderStyle: borderStyle,
    title: title,
    titleAlignment: titleAlignment,
    titleStyle: titleStyle,
    style: style,
    padding: padding,
    child: child,
  )

# Builders (return a copy, leaving the original untouched)

proc withBorders*(p: Panel, borders: set[BorderSide]): Panel =
  ## Copy with a different set of drawn edges.
  result = copyWidget(p)
  result.borders = borders

proc withBorderKind*(p: Panel, kind: BorderKind): Panel =
  ## Copy with a different border glyph set.
  result = copyWidget(p)
  result.borderKind = kind

proc withBorderStyle*(p: Panel, style: Style): Panel =
  ## Copy with a different border style.
  result = copyWidget(p)
  result.borderStyle = style

proc withTitle*(p: Panel, title: string): Panel =
  ## Copy with different title text, leaving the existing alignment intact.
  result = copyWidget(p)
  result.title = title

proc withTitle*(p: Panel, title: string, alignment: TitleAlignment): Panel =
  ## Copy with a different title and alignment.
  result = copyWidget(p)
  result.title = title
  result.titleAlignment = alignment

proc withTitleAlignment*(p: Panel, alignment: TitleAlignment): Panel =
  ## Copy with a different title alignment, leaving the title text intact.
  result = copyWidget(p)
  result.titleAlignment = alignment

proc withTitleStyle*(p: Panel, style: Style): Panel =
  ## Copy with a different title style.
  result = copyWidget(p)
  result.titleStyle = style

proc withStyle*(p: Panel, style: Style): Panel =
  ## Copy with a different interior fill style.
  result = copyWidget(p)
  result.style = style

proc withPadding*(p: Panel, padding: Padding): Panel =
  ## Copy with different inner padding.
  result = copyWidget(p)
  result.padding = padding

proc withChild*(p: Panel, child: Widget): Panel =
  ## Copy hosting a different child widget.
  result = copyWidget(p)
  result.child = child

# Geometry

proc hasBorder*(p: Panel, side: BorderSide): bool {.inline.} =
  ## True when an edge is actually drawn on `side`: the side is selected in
  ## `borders` *and* the glyph set is not `bkNone`. Both the layout helpers
  ## (`inner`/`getMinSize`) and the painters (`drawBorder`/`drawTitle`)
  ## consult this single predicate, so the space reserved for the frame and
  ## the frame that is actually drawn can never disagree.
  side in p.borders and p.borderKind != bkNone

proc insets(p: Panel): tuple[top, right, bottom, left: int] =
  ## Per-side space the frame reserves: one cell for each drawn border edge
  ## plus that side's (non-negative) padding. Single source of truth shared
  ## by `inner` and `getMinSize`.
  (
    top: (if p.hasBorder(bsTop): 1 else: 0) + max(0, p.padding.top),
    right: (if p.hasBorder(bsRight): 1 else: 0) + max(0, p.padding.right),
    bottom: (if p.hasBorder(bsBottom): 1 else: 0) + max(0, p.padding.bottom),
    left: (if p.hasBorder(bsLeft): 1 else: 0) + max(0, p.padding.left),
  )

proc inner*(p: Panel, area: Rect): Rect =
  ## Compute the content rectangle inside the border lines and padding.
  ##
  ## Each drawn edge consumes one cell; padding is then applied on top. A
  ## `bkNone` border reserves no space (see `hasBorder`). The result is
  ## clamped to a non-negative size and never extends past `area`.
  let ins = p.insets()
  rect(
    area.x + ins.left,
    area.y + ins.top,
    max(0, area.width - ins.left - ins.right),
    max(0, area.height - ins.top - ins.bottom),
  )

# Rendering

proc drawTitle(p: Panel, area: Rect, buf: var Buffer) =
  ## Draw the title along the top edge, truncating by display width so a
  ## multibyte or wide-character title is never split mid-rune and never
  ## overflows past the corners.
  # The title lives on the top border line, so it is drawn only when a top
  # edge is actually painted (a `bkNone` panel has no edge to host it).
  if p.title.len == 0 or not p.hasBorder(bsTop):
    return

  # Available column span between the (possible) corner glyphs.
  let
    leftBound = area.x + (if p.hasBorder(bsLeft): 1 else: 0)
    rightBound = area.right - (if p.hasBorder(bsRight): 1 else: 0)
    available = rightBound - leftBound
  if available <= 0:
    return

  # The general branch already covers `available == 1`: `truncateToWidth(0)`
  # returns "" and the ellipsis (width 1) fills the lone column.
  let displayTitle =
    if p.title.displayWidth <= available:
      p.title
    else:
      p.title.truncateToWidth(available - 1) & "…"

  let titleWidth = displayTitle.displayWidth
  let startX =
    case p.titleAlignment
    of taLeft:
      leftBound
    of taCenter:
      leftBound + (available - titleWidth) div 2
    of taRight:
      rightBound - titleWidth

  buf.setString(startX, area.y, displayTitle, p.titleStyle)

proc drawBorder(p: Panel, area: Rect, buf: var Buffer) =
  ## Draw the selected border edges and corners into `area` via the shared
  ## `borders.drawBox` painter, so the panel frame and the window frame
  ## (`core/windows`) are guaranteed to draw identically. `hasBorder` already
  ## folds `bkNone` into each side, so an all-`bkNone` panel passes four
  ## `false` flags and nothing is drawn.
  buf.drawBox(
    area,
    getBorderChars(p.borderKind),
    top = p.hasBorder(bsTop),
    right = p.hasBorder(bsRight),
    bottom = p.hasBorder(bsBottom),
    left = p.hasBorder(bsLeft),
    style = p.borderStyle,
  )

method render*(p: Panel, area: Rect, buf: var Buffer) =
  ## Render the panel: optional interior fill, border, title, then child.
  if area.isEmpty:
    return

  # Fill the interior background when a non-default style is requested.
  # `fill` clips to the buffer and writes one pre-built blank cell per
  # position, avoiding the per-cell UTF-8 re-parse a `setString(" ")` loop
  # would incur.
  if p.style != defaultStyle():
    buf.fill(area, cell(" ", p.style))

  p.drawBorder(area, buf)
  p.drawTitle(area, buf)

  if p.child != nil:
    let content = p.inner(area)
    if not content.isEmpty:
      p.child.render(content, buf)

method getMinSize*(p: Panel): Size =
  ## Minimum size: the border thickness plus padding plus the child's
  ## minimum, so the content area can satisfy the child.
  let ins = p.insets()
  let childMin =
    if p.child != nil:
      p.child.getMinSize()
    else:
      size(0, 0)
  size(ins.left + ins.right + childMin.width, ins.top + ins.bottom + childMin.height)

# Child interaction — forward the Widget contract to the hosted child so a
# framed interactive widget (Button/Input/List/…) stays reachable. Mirrors
# `widgets/container.nim`, but for the single `child`, and hit-tests mouse
# events against the content rect the child was actually rendered into.

method handleEvent*(p: Panel, event: Event, area: Rect): EventResult =
  ## Forward the event to the child, hit-tested against `inner(area)` so a
  ## mouse position lines up with where the child was drawn. Returns
  ## `erContinue` when there is no child (or the child ignores the event).
  if p.child != nil:
    p.child.handleEvent(event, p.inner(area))
  else:
    erContinue

method canFocus*(p: Panel): bool =
  ## A panel is focusable exactly when its child is.
  p.child != nil and p.child.canFocus()

method setFocus*(p: Panel, focused: bool) =
  ## Propagate focus to the child.
  if p.child != nil:
    p.child.setFocus(focused)

method isFocused*(p: Panel): bool =
  ## A panel is focused when its child is.
  p.child != nil and p.child.isFocused()
