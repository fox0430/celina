## Scrollbar widget for Celina CLI library
##
## A `Scrollbar` draws a single-line scroll indicator (track + draggable
## thumb, with optional begin/end arrow caps) along one edge of an area. It is
## the standalone, reusable counterpart to the scrollbar logic previously
## embedded in `list`/`table`, and is designed to be composed next to any
## scrollable content — inspired by Ratatui's `Scrollbar`.
##
## The widget is purely a *view* over three numbers:
## - `contentLength`  — total number of items/lines in the content
## - `viewportLength` — how many of them are visible at once
## - `position`       — index of the first visible item (the scroll offset)
##
## The thumb size and position are derived from those three values, so the
## owner only has to keep `position` in sync with whatever it is scrolling.
## Mouse wheel and track clicks are handled out of the box and reported via
## `onChange`.
##
## ### Usage Example:
## ```nim
## # A vertical scrollbar on the right edge tracking a 100-line document
## # of which 20 lines are visible, currently scrolled to line 10.
## let sb = newScrollbar(sbVerticalRight)
##   .withContentLength(100)
##   .withViewportLength(20)
##   .withPosition(10)
##
## sb.render(area, buf)
##
## # React to user-driven scrolling
## sb.onChange = proc(pos: int) =
##   doc.scrollOffset = pos
## ```

import base

import ../core/[geometry, buffer, colors]

type
  ScrollbarOrientation* = enum
    ## Which edge the bar is drawn on and which axis it scrolls.
    sbVerticalRight ## Vertical bar on the right edge (most common).
    sbVerticalLeft ## Vertical bar on the left edge.
    sbHorizontalBottom ## Horizontal bar on the bottom edge.
    sbHorizontalTop ## Horizontal bar on the top edge.

  Scrollbar* = ref object of Widget
    ## A single-line scroll indicator. See the module docs for the data model.
    orientation*: ScrollbarOrientation ## Edge/axis the bar is drawn on.
    contentLength*: int ## Total number of items in the scrollable content.
    viewportLength*: int ## Number of items visible at once.
    position*: int ## Index of the first visible item (scroll offset).
    thumbSymbol*: string ## Glyph for the thumb. Empty = orientation default (`█`).
    trackSymbol*: string
      ## Glyph for the track. Empty = orientation default (`│`/`─`).
    beginSymbol*: string ## Cap glyph at the start of the bar. Empty = none.
    endSymbol*: string ## Cap glyph at the end of the bar. Empty = none.
    thumbStyle*: Style ## Style applied to the thumb glyph(s).
    trackStyle*: Style ## Style applied to the track glyph(s).
    beginStyle*: Style ## Style applied to the begin cap.
    endStyle*: Style ## Style applied to the end cap.
    onChange*: proc(position: int) {.closure.}
      ## Called with the new `position` whenever a wheel/click moves the bar.

# Defaults shared by the constructor and the renderer.

const
  defaultThumbStyle* = style(White, BrightBlack)
  defaultTrackStyle* = style(BrightBlack)

proc isVertical*(orientation: ScrollbarOrientation): bool {.inline.} =
  ## True for the two vertical orientations.
  orientation in {sbVerticalRight, sbVerticalLeft}

proc isVertical*(sb: Scrollbar): bool {.inline.} =
  sb.orientation.isVertical

# Construction

proc newScrollbar*(
    orientation: ScrollbarOrientation = sbVerticalRight,
    contentLength: int = 0,
    viewportLength: int = 0,
    position: int = 0,
    thumbSymbol: string = "",
    trackSymbol: string = "",
    beginSymbol: string = "",
    endSymbol: string = "",
    thumbStyle: Style = defaultThumbStyle,
    trackStyle: Style = defaultTrackStyle,
    beginStyle: Style = defaultTrackStyle,
    endStyle: Style = defaultTrackStyle,
    onChange: proc(position: int) {.closure.} = nil,
): Scrollbar =
  ## Create a new `Scrollbar`. Empty thumb/track symbols fall back to the
  ## orientation-appropriate defaults at render time; empty begin/end symbols
  ## draw no cap.
  Scrollbar(
    orientation: orientation,
    contentLength: contentLength,
    viewportLength: viewportLength,
    position: position,
    thumbSymbol: thumbSymbol,
    trackSymbol: trackSymbol,
    beginSymbol: beginSymbol,
    endSymbol: endSymbol,
    thumbStyle: thumbStyle,
    trackStyle: trackStyle,
    beginStyle: beginStyle,
    endStyle: endStyle,
    onChange: onChange,
  )

proc scrollbar*(
    orientation: ScrollbarOrientation = sbVerticalRight,
    contentLength: int = 0,
    viewportLength: int = 0,
    position: int = 0,
): Scrollbar =
  ## Short constructor covering the common case (orientation + state).
  newScrollbar(
    orientation = orientation,
    contentLength = contentLength,
    viewportLength = viewportLength,
    position = position,
  )

# Builders (return a copy, leaving the original untouched)

proc withOrientation*(sb: Scrollbar, orientation: ScrollbarOrientation): Scrollbar =
  ## Copy on a different edge/axis.
  result = copyWidget(sb)
  result.orientation = orientation

proc withContentLength*(sb: Scrollbar, length: int): Scrollbar =
  ## Copy with a different total content length.
  result = copyWidget(sb)
  result.contentLength = length

proc withViewportLength*(sb: Scrollbar, length: int): Scrollbar =
  ## Copy with a different visible (viewport) length.
  result = copyWidget(sb)
  result.viewportLength = length

proc withPosition*(sb: Scrollbar, position: int): Scrollbar =
  ## Copy scrolled to a different position.
  result = copyWidget(sb)
  result.position = position

proc withState*(
    sb: Scrollbar, contentLength, viewportLength, position: int
): Scrollbar =
  ## Copy with all three state numbers set at once.
  result = copyWidget(sb)
  result.contentLength = contentLength
  result.viewportLength = viewportLength
  result.position = position

proc withSymbols*(
    sb: Scrollbar, thumb = "", track = "", `begin` = "", `end` = ""
): Scrollbar =
  ## Copy with custom glyphs. Empty arguments leave the existing value in
  ## place rather than clearing it.
  result = copyWidget(sb)
  if thumb.len > 0:
    result.thumbSymbol = thumb
  if track.len > 0:
    result.trackSymbol = track
  if `begin`.len > 0:
    result.beginSymbol = `begin`
  if `end`.len > 0:
    result.endSymbol = `end`

proc withThumbStyle*(sb: Scrollbar, style: Style): Scrollbar =
  ## Copy with a different thumb style.
  result = copyWidget(sb)
  result.thumbStyle = style

proc withTrackStyle*(sb: Scrollbar, style: Style): Scrollbar =
  ## Copy with a different track style.
  result = copyWidget(sb)
  result.trackStyle = style

# State helpers

proc maxPosition*(sb: Scrollbar): int {.inline.} =
  ## Largest valid `position`: `contentLength - viewportLength`, clamped at 0
  ## (0 when the content already fits in the viewport).
  max(0, sb.contentLength - sb.viewportLength)

proc isScrollable*(sb: Scrollbar): bool {.inline.} =
  ## True when there is more content than fits in the viewport.
  sb.contentLength > sb.viewportLength and sb.viewportLength > 0

proc clampPosition*(sb: Scrollbar) =
  ## Force `position` back into the valid `0 .. maxPosition` range.
  sb.position = clamp(sb.position, 0, sb.maxPosition)

proc setPosition*(sb: Scrollbar, position: int) =
  ## Set `position` (clamped) and fire `onChange` only on a real change.
  let newPos = clamp(position, 0, sb.maxPosition)
  if newPos != sb.position:
    sb.position = newPos
    if sb.onChange != nil:
      sb.onChange(newPos)

proc scrollBy*(sb: Scrollbar, delta: int) =
  ## Move `position` by `delta` items (clamped), firing `onChange` on change.
  sb.setPosition(sb.position + delta)

# Rendering

proc resolveSymbols(sb: Scrollbar, vertical: bool): tuple[thumb, track: string] =
  ## Pick the glyphs to draw, applying orientation defaults for empty fields.
  result.thumb = if sb.thumbSymbol.len > 0: sb.thumbSymbol else: "█"
  result.track =
    if sb.trackSymbol.len > 0:
      sb.trackSymbol
    elif vertical:
      "│"
    else:
      "─"

proc thumbMetrics*(sb: Scrollbar, trackLen: int): tuple[size, pos: int] =
  ## Compute the thumb size and offset (in cells) for a track of `trackLen`
  ## cells. When the content fits the viewport the thumb fills the whole
  ## track. Exposed for testing.
  if trackLen <= 0:
    return (0, 0)
  let content = max(sb.contentLength, 0)
  let viewport = max(sb.viewportLength, 0)
  if content <= viewport or content <= 0:
    return (trackLen, 0)

  let size = clamp(max(1, (viewport * trackLen) div content), 1, trackLen)
  let maxPos = content - viewport
  let pos = clamp(sb.position, 0, maxPos)
  var thumbPos =
    if maxPos > 0:
      (pos * (trackLen - size)) div maxPos
    else:
      0
  thumbPos = clamp(thumbPos, 0, trackLen - size)
  (size, thumbPos)

method render*(sb: Scrollbar, area: Rect, buf: var Buffer) =
  ## Render the scrollbar along its edge of `area`. A vertical bar occupies
  ## one column (the left or right edge); a horizontal bar one row (the top or
  ## bottom edge). The rest of `area` is left untouched, so the same rect can
  ## be shared with the content it scrolls.
  if area.isEmpty:
    return

  let vertical = sb.isVertical
  let barLen = if vertical: area.height else: area.width
  if barLen <= 0:
    return

  # Fixed coordinate of the bar's line on the chosen edge.
  let col =
    if sb.orientation == sbVerticalRight:
      area.x + area.width - 1
    else:
      area.x
  let row =
    if sb.orientation == sbHorizontalBottom:
      area.y + area.height - 1
    else:
      area.y

  # Paint a single glyph at offset `i` along the bar's axis.
  template paint(i: int, s: string, st: Style) =
    if vertical:
      buf.setString(col, area.y + i, s, st)
    else:
      buf.setString(area.x + i, row, s, st)

  let (thumbCh, trackCh) = sb.resolveSymbols(vertical)

  # Begin/end caps consume the first/last cell of the bar when present.
  var trackStart = 0
  var trackEnd = barLen # exclusive
  if sb.beginSymbol.len > 0:
    paint(0, sb.beginSymbol, sb.beginStyle)
    trackStart = 1
  if sb.endSymbol.len > 0 and barLen - 1 >= trackStart:
    paint(barLen - 1, sb.endSymbol, sb.endStyle)
    trackEnd = barLen - 1

  let trackLen = trackEnd - trackStart
  if trackLen <= 0:
    return

  let (thumbSize, thumbPos) = sb.thumbMetrics(trackLen)
  for i in 0 ..< trackLen:
    let isThumb = i >= thumbPos and i < thumbPos + thumbSize
    if isThumb:
      paint(trackStart + i, thumbCh, sb.thumbStyle)
    else:
      paint(trackStart + i, trackCh, sb.trackStyle)

method getMinSize*(sb: Scrollbar): Size =
  ## A scrollbar needs one cell across its short axis and at least one along
  ## its long axis — a single cell either way, regardless of orientation.
  size(1, 1)

method getPreferredSize*(sb: Scrollbar, available: Size): Size =
  ## Span the available length along the bar's axis, one cell across.
  if sb.isVertical:
    size(1, max(1, available.height))
  else:
    size(max(1, available.width), 1)

# Mouse interaction

proc positionForOffset(sb: Scrollbar, offset, trackLen: int): int =
  ## Map a cell offset within the track (0 ..< trackLen) to a content
  ## position, so clicking near the top scrolls to the top and clicking near
  ## the bottom scrolls to the end.
  let maxPos = sb.maxPosition
  if maxPos <= 0 or trackLen <= 1:
    return 0
  clamp((offset * maxPos) div (trackLen - 1), 0, maxPos)

proc handleMouseEvent*(sb: Scrollbar, event: MouseEvent, area: Rect): EventResult =
  ## Wheel scrolls by one item; a left click on the bar jumps the thumb to
  ## that point. Both route through `setPosition`, so `onChange` fires on any
  ## real movement. Returns `erConsume` when the event moved (or could move)
  ## the bar, `erContinue` otherwise.
  if not sb.isScrollable or area.isEmpty:
    return erContinue

  if event.kind == Press:
    case event.button
    of WheelUp:
      sb.scrollBy(-1)
      return erConsume
    of WheelDown:
      sb.scrollBy(1)
      return erConsume
    of Left:
      let vertical = sb.isVertical
      # Hit-test against the single line the bar occupies.
      let onBar =
        if vertical:
          let col =
            if sb.orientation == sbVerticalRight:
              area.x + area.width - 1
            else:
              area.x
          event.x == col and event.y >= area.y and event.y < area.y + area.height
        else:
          let row =
            if sb.orientation == sbHorizontalBottom:
              area.y + area.height - 1
            else:
              area.y
          event.y == row and event.x >= area.x and event.x < area.x + area.width
      if not onBar:
        return erContinue

      let barLen = if vertical: area.height else: area.width
      var trackStart = 0
      var trackEnd = barLen
      if sb.beginSymbol.len > 0:
        trackStart = 1
      if sb.endSymbol.len > 0 and barLen - 1 >= trackStart:
        trackEnd = barLen - 1
      let trackLen = trackEnd - trackStart
      if trackLen <= 0:
        return erContinue

      let raw =
        if vertical:
          event.y - area.y
        else:
          event.x - area.x
      let offset = clamp(raw - trackStart, 0, trackLen - 1)
      sb.setPosition(sb.positionForOffset(offset, trackLen))
      return erConsume
    else:
      discard

  erContinue

method handleEvent*(sb: Scrollbar, event: Event, area: Rect): EventResult =
  ## Forward only mouse events; keys are left for the owning widget.
  case event.kind
  of EventKind.Mouse:
    sb.handleMouseEvent(event.mouse, area)
  else:
    erContinue
