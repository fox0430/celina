## Buffer system
##
## This module provides the core buffer abstraction for managing
## terminal screen content and efficient rendering.

import std/[strformat, unicode, sequtils, strutils]

import pkg/unicodedb/[widths, properties, segmentation]

import geometry, colors

type
  Cell* = object ## Represents a single character cell in the terminal
    symbol*: string # UTF-8 string to support Unicode
    style*: Style # Visual styling
    hyperlink*: string # OSC 8 hyperlink URL (empty = no link)

  RowDirty* = object
    ## Per-row dirty extents.
    ## When `isDirty` is true, the row has changes spanning columns
    ## `[minX..maxX]` inclusive. When false, `minX`/`maxX` are meaningless.
    isDirty*: bool
    minX*, maxX*: int

  DirtyRegion* = object
    ## Tracks changed cells as per-row dirty spans (one `(minX, maxX)` per
    ## row). Sparse vertical updates skip untouched rows during diff.
    ##
    ## Invariant (maintained by `newBuffer`/`resize`/`clone`): for the
    ## owning buffer, `rows.len == buffer.area.height`. `markDirty` and
    ## `markDirtyRect` rely on this and index `rows` directly after a
    ## bounds check against `area.height`.
    ##
    ## `anyDirty` mirrors "any `rows[*].isDirty` is true" so the common
    ## clean/dirty probe stays O(1). Set whenever a row is first marked,
    ## cleared by `clearDirty`.
    ##
    ## The legacy bounding-box accessors (`isDirty`/`minX`/`maxX`/`minY`/
    ## `maxY`) are exposed as computed procs further below. Use
    ## `boundingBox` when you need more than one of them at once.
    rows*: seq[RowDirty]
    anyDirty*: bool

  Buffer* = object ## 2D buffer representing terminal screen content
    area*: Rect # The area this buffer covers
    content: seq[seq[Cell]] # 2D grid of cells
    dirty: DirtyRegion # Per-row dirty tracker

const
  DefaultTabWidth* = 8
    ## Default tab-stop spacing for `\t` expansion in `setString` / `setRunes`.
    ## Override per call with the `tabWidth` parameter. Values <= 0 disable
    ## expansion — `\t` is then substituted with a single space, matching
    ## the fallback behavior for other C0 control characters.

  ZeroWidthCategories = ctgMn + ctgMe + ctgCf
    ## Unicode general categories whose code points advance the terminal
    ## cursor by zero columns: nonspacing marks (Mn — e.g. U+0301 COMBINING
    ## ACUTE ACCENT and the variation selectors U+FE00..U+FE0F), enclosing
    ## marks (Me), and format controls (Cf — e.g. U+200D ZERO WIDTH JOINER,
    ## U+200C ZWNJ, U+200B ZERO WIDTH SPACE).

  VS16 = 0xFE0F
    ## VARIATION SELECTOR-16: requests emoji presentation for the preceding
    ## base, promoting an otherwise narrow emoji to two columns.
  VS15 = 0xFE0E ## VARIATION SELECTOR-15: requests text presentation; never promotes.

  EmojiModifierFirst = 0x1F3FB
  EmojiModifierLast = 0x1F3FF
    ## EMOJI MODIFIER FITZPATRICK type 1-6 (skin tones). They only follow an
    ## Emoji_Modifier_Base, and the resulting modifier sequence takes emoji
    ## presentation — two columns — even when the base's default presentation is
    ## narrow (e.g. U+261D ☝). Like VS16, they fold as a zero-width mark but
    ## promote the whole cluster.

proc cell*(
    symbol: string = " ", style: Style = defaultStyle(), hyperlink: string = ""
): Cell {.inline.} =
  ## Create a new Cell
  Cell(symbol: symbol, style: style, hyperlink: hyperlink)

proc cell*(
    symbol: char, style: Style = defaultStyle(), hyperlink: string = ""
): Cell {.inline.} =
  ## Create a new Cell from a character
  Cell(symbol: $symbol, style: style, hyperlink: hyperlink)

proc cell*(
    symbol: Rune, style: Style = defaultStyle(), hyperlink: string = ""
): Cell {.inline.} =
  ## Create a new Cell from a Rune
  Cell(symbol: $symbol, style: style, hyperlink: hyperlink)

# Cell utilities
proc isEmpty*(cell: Cell): bool {.inline.} =
  ## Check if cell is truly empty (no content at all)
  cell.symbol.len == 0

proc isShadow*(cell: Cell): bool {.inline.} =
  ## True when this cell is a shadow (right half) of a wide character.
  ## Shadow cells carry an empty symbol; a blank cell holds " " instead.
  ## Alias of `isEmpty` — the predicates share an implementation because
  ## a shadow cell is, by definition, the only legitimate empty cell.
  cell.isEmpty

proc runeWidth*(r: Rune): int =
  ## Get the display width of a rune in terminal columns: 0 for combining
  ## marks and zero-width joiners/format controls, 2 for wide East Asian
  ## and emoji code points, 1 for everything else.
  ##
  ## Reporting 0 for these zero-width runes is essential to terminal
  ## correctness: they render merged onto the preceding base character
  ## without moving the cursor, so counting one as a column would shift
  ## every following glyph. `setRunes` folds them into the base cell and the
  ## differential renderer assumes one written cell == one cursor advance.
  let n = int(r)
  if n < 0x80:
    # Fast path: every ASCII code point occupies one column. C0 controls
    # are substituted with a space before reaching a cell; callers that
    # still pass one here expect width 1, matching historical behavior.
    return 1
  if n > 0x10FFFF:
    return 1
  if r.unicodeCategory in ZeroWidthCategories:
    return 0
  case r.unicodeWidth
  of UnicodeWidth.uwdtNarrow, UnicodeWidth.uwdtHalf, UnicodeWidth.uwdtAmbiguous,
      UnicodeWidth.uwdtNeutral:
    1
  else:
    2

template isC0Control(n: int): bool =
  ## C0 control character (0x00..0x1F) or DEL (0x7F). Writing these directly
  ## to a terminal moves the cursor or otherwise disrupts rendering, so they
  ## must never reach a cell's `symbol`.
  n < 0x20 or n == 0x7F

template isKeycapBase(r: Rune): bool =
  ## A base that U+20E3 COMBINING ENCLOSING KEYCAP can enclose into a two-column
  ## keycap glyph: an ASCII digit 0-9, '#', or '*'. After any other base, U+20E3
  ## is just an ordinary (one-column) combining mark, so it must not promote.
  int(r) == 0x23 or int(r) == 0x2A or int(r) in 0x30 .. 0x39

proc clusterAt(runes: openArray[Rune], start: int): tuple[next, width: int] =
  ## Segment one extended grapheme cluster starting at `start` (which must be a
  ## valid index). Return the exclusive end index and the cluster's terminal
  ## column width.
  ##
  ## Width is a property of the whole cluster, not of any single code point:
  ## a base whose default presentation is narrow becomes two columns when an
  ## emoji-presentation selector (VS16) or a ZWJ join makes it an emoji, and a
  ## ZWJ emoji sequence (e.g. a multi-person family) renders as a single
  ## two-column glyph regardless of how many emoji it joins. `runeWidth` stays
  ## the per-code-point primitive; this is where cluster rules live.
  let n = runes.len
  let lead = runes[start]
  var i = start + 1
  var w = runeWidth(lead)

  # A C0 control / DEL never combines with following marks (TR29 GB4/GB5): it is
  # its own cluster, so a trailing combining mark becomes the next cluster and
  # folds onto the previous base (e.g. a tab's expanded space) instead of being
  # swallowed here and silently dropped by the control branch of setRunes.
  if isC0Control(int(lead)):
    return (i, w)

  # Fast path for a lone rune: with nothing following it, no VS16/ZWJ/keycap
  # promotion and no regional-indicator pair can apply, so its width is exactly
  # `runeWidth(lead)`. This skips the `wordBreakProp` lookups for the dominant
  # single-rune-cell case, which matters because `width(cell)` runs `clusterAt`
  # inside the `[]=` write primitive (up to twice per cell written).
  if i >= n:
    return (i, w)

  let leadProp = wordBreakProp(lead)

  # Regional-indicator pair -> a single flag glyph, two columns. `i < n` is
  # already guaranteed by the lone-rune fast path above, so `runes[i]` is in
  # range here.
  if leadProp == sgwRegionalIndicator and wordBreakProp(runes[i]) == sgwRegionalIndicator:
    return (i + 1, 2)

  let isEmoji = leadProp == sgwExtendedPictographic
  var promote = false
    ## Set by VS16 or a ZWJ join: the cluster takes emoji presentation and
    ## therefore two columns even when the base alone is narrow.
  var keycap = false
    ## Set by U+20E3 COMBINING ENCLOSING KEYCAP: an emoji keycap sequence
    ## (e.g. "1️⃣" = digit + VS16 + U+20E3) renders in two columns even though
    ## the base digit is narrow and not itself pictographic.

  while i < n:
    let r = runes[i]
    let cp = int(r)
    # Variation selectors are themselves `sgwExtend` in TR29, so they must be
    # matched before the generic extend/format fold below.
    if cp == VS16:
      if isEmoji:
        promote = true
      inc i
      continue
    if cp == VS15:
      # Text-presentation selector: requests the non-emoji glyph (one column).
      # As the last presentation selector in the cluster it overrides a preceding
      # VS16, so clear `promote` -- e.g. base + VS16 + VS15 renders as text,
      # width 1, not the 2 a stale `promote` would report (which would advance the
      # differential renderer's cursor a column too far and leave a ghost cell).
      promote = false
      inc i
      continue
    if cp in EmojiModifierFirst .. EmojiModifierLast:
      # Emoji modifier (skin tone): folds as a zero-width mark but, like VS16,
      # promotes a narrow Emoji_Modifier_Base (a subset of ExtendedPictographic)
      # to its two-column emoji presentation. Guarded by `isEmoji` so a stray
      # modifier after a non-pictographic base does not over-count.
      if isEmoji:
        promote = true
      inc i
      continue
    if cp == 0x20E3:
      # COMBINING ENCLOSING KEYCAP: folds as a zero-width mark but promotes the
      # whole cluster to a two-column keycap glyph -- only over a valid keycap
      # base (digit / '#' / '*'). After any other base it is a stray combining
      # mark the terminal draws in one column, so promoting would over-count and
      # re-introduce the ghost-cell desync this segmentation exists to prevent.
      if isKeycapBase(lead):
        keycap = true
      inc i
      continue
    let p = wordBreakProp(r)
    if p == sgwZwj:
      # A ZWJ that joins another emoji collapses the whole sequence into one
      # two-column cluster; a dangling ZWJ just folds as a zero-width rune.
      #
      # TR29 GB11 only suppresses the break for `ExtPict Extend* ZWJ × ExtPict`,
      # i.e. when the cluster already *is* an emoji (`isEmoji`). A ZWJ after a
      # non-emoji base (e.g. "A" + ZWJ + emoji) does NOT join: the ZWJ folds
      # onto the base as a zero-width rune and the following emoji opens its own
      # cluster. Without the `isEmoji` guard the emoji would be swallowed here
      # and the cluster kept at the base's narrow width, under-counting the
      # column the terminal still draws and re-introducing the ghost-cell desync.
      if isEmoji and i + 1 < n and wordBreakProp(runes[i + 1]) == sgwExtendedPictographic:
        promote = true
        i += 2
        continue
      inc i
      continue
    if p == sgwExtend or p == sgwFormat:
      inc i
      continue
    break

  # `promote` is only ever set under an `isEmoji` guard (VS16 / ZWJ join above),
  # so it already implies emoji presentation; `keycap` promotes a valid keycap
  # base independently.
  if promote or keycap:
    w = 2
  (i, w)

iterator clusterMetrics*(runes: openArray[Rune]): tuple[leadIdx, width: int] =
  ## Segment `runes` into extended grapheme clusters, yielding each cluster's
  ## lead rune index and terminal column width *without* materializing the
  ## cluster text. Use this for measurement passes (total width, alignment,
  ## clipping math) where the cluster string is not needed — it avoids the
  ## per-cluster string allocation that `graphemeClusters` pays.
  var i = 0
  while i < runes.len:
    let (nxt, w) = clusterAt(runes, i)
    yield (i, w)
    i = nxt

iterator graphemeClusters*(
    runes: openArray[Rune]
): tuple[leadIdx: int, text: string, width: int] =
  ## Segment `runes` into extended grapheme clusters, yielding for each the lead
  ## rune's index, the full cluster text (lead plus folded/joined runes), and
  ## the cluster's terminal column width. Use this for cell layout so the lead
  ## cell carries the whole cluster and the cursor advances by `width`. When the
  ## text is not needed, prefer `clusterMetrics` to skip the string build.
  var i = 0
  while i < runes.len:
    let (nxt, w) = clusterAt(runes, i)
    var text = ""
    for j in i ..< nxt:
      text.add($runes[j])
    yield (i, text, w)
    i = nxt

proc clustersWidth*(runes: openArray[Rune]): int =
  ## Total terminal column width of `runes`, measured by grapheme cluster (so
  ## VS16-promoted and ZWJ emoji clusters count as two columns, not summed
  ## per code point). The width counterpart of `graphemeClusters`.
  for (_, w) in clusterMetrics(runes):
    result += w

proc runesWidth*(runes: seq[Rune]): int =
  ## Calculate total display width of a sequence of runes, by grapheme cluster.
  clustersWidth(runes)

proc displayWidth*(s: string): int =
  ## Calculate the display width of a UTF-8 string in terminal columns.
  ##
  ## Wide characters (CJK, emoji, etc.) count as 2 columns; narrow characters
  ## count as 1. Use this in place of `runeLen` whenever the result feeds into
  ## visual layout (truncation, padding, width reservation, preferred size).
  # Fast path: a pure-ASCII string has one column per byte (every ASCII code
  # point is width 1, including C0 controls, matching `runeWidth`), so there is
  # nothing to segment and no need to materialize a `seq[Rune]`. This covers the
  # dominant TUI case (plain-text labels) and the hot word-wrap loop, which
  # calls `displayWidth` once per word.
  for ch in s:
    if ch >= '\x80':
      return clustersWidth(s.toRunes)
  s.len

proc truncateToWidth*(s: string, maxWidth: int): string =
  ## Return the longest prefix of `s` whose display width does not exceed
  ## `maxWidth`. Grapheme clusters are kept whole and measured by cluster, so a
  ## wide cluster — a CJK character, or a VS16/ZWJ emoji that renders in two
  ## columns — is dropped rather than split or under-counted when it would not
  ## fit. The result's `displayWidth` therefore never exceeds `maxWidth`.
  if maxWidth <= 0:
    return ""
  # Fast path: a pure-ASCII string is one column per byte, so the longest fitting
  # prefix is just its first `maxWidth` bytes — no segmentation or `seq[Rune]`.
  var ascii = true
  for ch in s:
    if ch >= '\x80':
      ascii = false
      break
  if ascii:
    return s[0 ..< min(maxWidth, s.len)]
  # Measure with `clusterMetrics` (no per-cluster string build) to find the rune
  # index past the longest fitting prefix, then build the result once.
  let runes = s.toRunes
  var w = 0
  var endIdx = runes.len
  for (leadIdx, cw) in clusterMetrics(runes):
    if w + cw > maxWidth:
      endIdx = leadIdx
      break
    w += cw
  for j in 0 ..< endIdx:
    result.add($runes[j])

proc width*(cell: Cell): int =
  ## Get the display width of the cell's symbol.
  ##
  ## A cell holds exactly one grapheme cluster, so this is cluster-aware: a
  ## VS16-promoted or ZWJ emoji lead reports 2, matching `setRunes`/`setString`
  ## layout. `[]=` relies on this for wide-character shadow cleanup, so it must
  ## not regress to a per-code-point `runeWidth(runes[0])`.
  if cell.symbol.len == 0:
    return 0
  let runes = cell.symbol.toRunes
  if runes.len == 0:
    return 0
  return clusterAt(runes, 0).width

proc `==`*(a, b: Cell): bool =
  ## Compare two cells for equality
  a.symbol == b.symbol and a.style == b.style and a.hyperlink == b.hyperlink

proc `$`*(cell: Cell): string =
  ## String representation of Cell
  var parts: seq[string] = @[&"'{cell.symbol}'"]
  if cell.style != defaultStyle():
    parts.add($cell.style)
  if cell.hyperlink.len > 0:
    parts.add(&"hyperlink: \"{cell.hyperlink}\"")
  &"Cell({parts.join(\", \")})"

proc newBuffer*(area: Rect): Buffer =
  ## Create a new Buffer with the specified area
  Buffer(
    area: area,
    content: newSeqWith(area.height, newSeqWith(area.width, cell())),
    dirty: DirtyRegion(rows: newSeq[RowDirty](area.height)),
  )

proc newBuffer*(width, height: int): Buffer =
  ## Create a new Buffer with specified dimensions at origin
  newBuffer(rect(0, 0, width, height))

# Dirty region management
proc isDirty*(d: DirtyRegion): bool {.inline.} =
  ## True if any row has recorded changes. O(1).
  d.anyDirty

proc boundingBox*(d: DirtyRegion): tuple[isDirty: bool, minX, minY, maxX, maxY: int] =
  ## Single-pass walk that returns the full dirty bounding box.
  ## Prefer this over calling `minX`/`minY`/`maxX`/`maxY` individually
  ## when you need more than one coordinate. Returns zeros when clean —
  ## callers should gate on `isDirty` before treating values as meaningful.
  if not d.anyDirty:
    return (false, 0, 0, 0, 0)
  var first = true
  for y in 0 ..< d.rows.len:
    let row = d.rows[y]
    if not row.isDirty:
      continue
    if first:
      result = (true, row.minX, y, row.maxX, y)
      first = false
    else:
      if row.minX < result.minX:
        result.minX = row.minX
      if row.maxX > result.maxX:
        result.maxX = row.maxX
      result.maxY = y

proc minY*(d: DirtyRegion): int {.inline.} =
  ## Y of the topmost dirty row. Returns 0 when no row is dirty;
  ## callers should gate on `isDirty` before treating the value as
  ## meaningful (matches the pre-row-spans behaviour).
  d.boundingBox.minY

proc maxY*(d: DirtyRegion): int {.inline.} =
  ## Y of the bottommost dirty row. Returns 0 when no row is dirty.
  d.boundingBox.maxY

proc minX*(d: DirtyRegion): int {.inline.} =
  ## Minimum X across all dirty rows (bounding-box left edge).
  d.boundingBox.minX

proc maxX*(d: DirtyRegion): int {.inline.} =
  ## Maximum X across all dirty rows (bounding-box right edge).
  d.boundingBox.maxX

proc isRowDirty*(buffer: Buffer, y: int): bool {.inline.} =
  ## True when row `y` has any dirty cells.
  ## Out-of-range rows are treated as clean.
  y >= 0 and y < buffer.dirty.rows.len and buffer.dirty.rows[y].isDirty

proc markRowDirty(d: var DirtyRegion, y, lo, hi: int) {.inline.} =
  ## Extend row `y`'s dirty span to cover `[lo..hi]` and set `anyDirty`.
  ## Caller is responsible for ensuring `y` is in range.
  if not d.rows[y].isDirty:
    d.rows[y] = RowDirty(isDirty: true, minX: lo, maxX: hi)
    d.anyDirty = true
  else:
    if lo < d.rows[y].minX:
      d.rows[y].minX = lo
    if hi > d.rows[y].maxX:
      d.rows[y].maxX = hi

proc markDirty*(buffer: var Buffer, x, y: int) =
  ## Mark a specific cell as dirty. Extends the affected row's span.
  if x < 0 or x >= buffer.area.width or y < 0 or y >= buffer.area.height:
    return
  buffer.dirty.markRowDirty(y, x, x)

proc markDirtyRect*(buffer: var Buffer, rect: Rect) =
  ## Mark a rectangular area as dirty by extending each affected row's span.
  let clipped = buffer.area.intersection(rect)
  if clipped.isEmpty:
    return

  let localMinX = clipped.x - buffer.area.x
  let localMinY = clipped.y - buffer.area.y
  let localMaxX = clipped.right - 1 - buffer.area.x
  let localMaxY = clipped.bottom - 1 - buffer.area.y

  for y in localMinY .. localMaxY:
    buffer.dirty.markRowDirty(y, localMinX, localMaxX)

proc clearDirty*(buffer: var Buffer) =
  ## Clear the dirty region after rendering.
  ## Should be called after a buffer has been successfully rendered.
  ## Early-returns when already clean to keep the no-op frame O(1);
  ## otherwise resets only the rows actually marked dirty to keep the
  ## row seq's backing storage and avoid re-touching long stretches of
  ## already-clean rows on tall buffers with sparse updates.
  if not buffer.dirty.anyDirty:
    return
  for i in 0 ..< buffer.dirty.rows.len:
    if buffer.dirty.rows[i].isDirty:
      buffer.dirty.rows[i] = RowDirty()
  buffer.dirty.anyDirty = false

proc getDirtyRegionSize*(buffer: Buffer): int =
  ## Total dirty cell count across all dirty rows.
  ## With per-row tracking this is the exact dirty span sum rather than
  ## the bounding-box area, so sparse vertical updates yield much smaller
  ## values than the rectangular tracker did.
  if not buffer.dirty.anyDirty:
    return 0
  for row in buffer.dirty.rows:
    if row.isDirty:
      result += row.maxX - row.minX + 1

proc isDirty*(buffer: Buffer): bool {.inline.} =
  ## True when any cell has been recorded as changed. O(1).
  buffer.dirty.anyDirty

# Buffer access and manipulation
proc `[]`*(buffer: Buffer, x, y: int): Cell =
  ## Get cell at coordinates (relative to buffer area)
  if x >= 0 and x < buffer.area.width and y >= 0 and y < buffer.area.height:
    buffer.content[y][x]
  else:
    cell() # Return empty cell for out-of-bounds access

proc `[]`*(buffer: Buffer, pos: Position): Cell {.inline.} =
  ## Get cell at position
  buffer[pos.x, pos.y]

proc `[]=`*(buffer: var Buffer, x, y: int, newCell: Cell) =
  ## Set cell at coordinates.
  ##
  ## Maintains wide-character consistency:
  ## - If overwriting the shadow cell of a wide character at (x-1), the
  ##   orphaned lead at (x-1) is replaced with a space (preserving its
  ##   style; the hyperlink, if any, is dropped because the link anchor
  ##   is gone).
  ## - If the old cell at (x, y) was a wide-character lead, its shadow
  ##   at (x+1) is replaced with a space (preserving the lead's style).
  ##
  ## Writes with an empty symbol (shadow cells) skip the left-side
  ## cleanup so that sequential wide-character writes (lead followed by
  ## shadow) do not erase the lead just written.
  ##
  ## NOTE: This is a low-level single-cell write. When `newCell` is a
  ## wide character (width == 2) the matching shadow at (x+1) is NOT
  ## placed automatically — callers must write the shadow themselves or
  ## use `setCell` / `setString` which handle it. Likewise, writing a
  ## wide character at the rightmost column leaves the buffer in an
  ## inconsistent state (no room for a shadow); use `setCell`, which
  ## performs the right-edge check.
  if not (x >= 0 and x < buffer.area.width and y >= 0 and y < buffer.area.height):
    return

  let isShadowWrite = newCell.isShadow
  var minX = x
  var maxX = x

  if not isShadowWrite and x > 0:
    let leftCell = buffer.content[y][x - 1]
    if not leftCell.isShadow and leftCell.width == 2:
      buffer.content[y][x - 1] = cell(" ", leftCell.style)
      minX = x - 1

  let oldCell = buffer.content[y][x]
  if not oldCell.isShadow and oldCell.width == 2 and x + 1 < buffer.area.width:
    buffer.content[y][x + 1] = cell(" ", oldCell.style)
    maxX = x + 1

  buffer.content[y][x] = newCell

  # markDirty(min) then markDirty(max) expands the region to cover the
  # whole [minX..maxX] range; x always sits inside so we don't mark it
  # separately when there was a neighbour cleanup.
  buffer.markDirty(minX, y)
  if maxX != minX:
    buffer.markDirty(maxX, y)

proc `[]=`*(buffer: var Buffer, pos: Position, cell: Cell) {.inline.} =
  ## Set cell at position
  buffer[pos.x, pos.y] = cell

proc isValidPos*(buffer: Buffer, x, y: int): bool {.inline.} =
  ## Check if coordinates are within buffer bounds
  x >= 0 and x < buffer.area.width and y >= 0 and y < buffer.area.height

proc isValidPos*(buffer: Buffer, pos: Position): bool {.inline.} =
  ## Check if position is within buffer bounds
  buffer.isValidPos(pos.x, pos.y)

# Buffer operations
proc clear*(buffer: var Buffer, cell: Cell = cell()) =
  ## Clear the entire buffer with the given cell.
  ##
  ## Bypasses `[]=` (and its wide-character consistency check) because
  ## every cell is overwritten by `cell`, so there is no orphan to crush.
  for y in 0 ..< buffer.area.height:
    for x in 0 ..< buffer.area.width:
      buffer.content[y][x] = cell

  # Mark entire buffer as dirty
  buffer.markDirtyRect(buffer.area)

proc fill*(buffer: var Buffer, area: Rect, fillCell: Cell) =
  ## Fill a rectangular area with the given cell
  let clippedArea = buffer.area.intersection(area)

  for y in clippedArea.y ..< clippedArea.bottom:
    for x in clippedArea.x ..< clippedArea.right:
      let localX = x - buffer.area.x
      let localY = y - buffer.area.y
      if buffer.isValidPos(localX, localY):
        buffer[localX, localY] = fillCell

  # Mark filled area as dirty
  buffer.markDirtyRect(clippedArea)

proc foldClusterInto*(buffer: var Buffer, baseX, y: int, text: string) {.inline.} =
  ## Append a zero-width cluster's text onto an existing base cell at
  ## (baseX, y), keeping the grapheme cluster in a single cell. Direct symbol
  ## mutation bypasses the wide-char cleanup in `[]=` so the base's shadow cell
  ## (for a wide base) is preserved. A no-op when `baseX < 0` or out of range,
  ## so callers can pass a "no base yet" sentinel and have the text dropped —
  ## mirroring how a leading mark with nothing to attach to is dropped.
  if baseX >= 0 and buffer.isValidPos(baseX, y):
    buffer.content[y][baseX].symbol.add(text)
    buffer.markDirty(baseX, y)

proc setRunes*(
    buffer: var Buffer,
    x, y: int,
    runes: seq[Rune],
    style: Style = defaultStyle(),
    hyperlink: string = "",
    tabWidth: int = DefaultTabWidth,
) =
  ## Set a sequence of runes starting at the given coordinates.
  ## Handles Unicode characters and wide characters properly.
  ## If hyperlink is provided, the text becomes a clickable link (OSC 8).
  ##
  ## `\t` expands to spaces up to the next `tabWidth` boundary measured
  ## from the starting `x`, so consecutive tabs land on consistent stops.
  ## When `tabWidth <= 0`, tab expansion is disabled and `\t` is replaced
  ## with a single space. Other C0 control characters and DEL are always
  ## replaced with a single space — leaving them in a cell symbol would
  ## otherwise be re-emitted verbatim by the differential renderer and
  ## shift subsequent cursor positioning on the real terminal.
  if runes.len == 0:
    return
  if not buffer.isValidPos(x, y):
    return

  var currentX = x
  let startX = x
  var lastBaseX = -1
    ## Column of the most recently written base cell in this call. Trailing
    ## zero-width runes (combining marks, ZWJ, variation selectors) are
    ## folded into it. `-1` means no base cell yet, so a zero-width rune
    ## leading the run has nothing to attach to and is dropped.

  # Iterate by grapheme cluster, not per rune, so VS16-promoted and ZWJ emoji
  # clusters occupy a single (possibly wide) cell whose width matches how the
  # terminal renders them. `text` carries the whole cluster; the C0/tab
  # branches key off the lead rune and ignore it.
  for (leadIdx, text, width) in graphemeClusters(runes):
    let n = int(runes[leadIdx])
    if n == 0x09 and tabWidth > 0:
      # Tab: expand to spaces up to next tab stop relative to startX.
      # Bail out early once we've hit the right edge so that a run of
      # tabs past the buffer width doesn't spin through their strides
      # writing nothing.
      if currentX >= buffer.area.width:
        break
      let stride = tabWidth - ((currentX - startX) mod tabWidth)
      for _ in 0 ..< stride:
        if currentX >= buffer.area.width:
          break
        if buffer.isValidPos(currentX, y):
          buffer[currentX, y] = cell(" ", style, hyperlink)
          lastBaseX = currentX
        currentX.inc
      continue
    if isC0Control(n):
      # Other C0 controls / DEL (and `\t` when tabWidth <= 0):
      # substitute single space.
      if currentX >= buffer.area.width:
        break
      if buffer.isValidPos(currentX, y):
        buffer[currentX, y] = cell(" ", style, hyperlink)
        lastBaseX = currentX
      currentX.inc
      continue

    if width == 0:
      # Zero-width cluster (a leading/orphan combining mark, joiner, or
      # variation selector with no base of its own): fold it into the last
      # base cell so the cluster stays in one cell and the cursor still
      # advances one column per visible glyph. With nothing to attach to
      # (`lastBaseX < 0`) it drops. See `foldClusterInto`.
      buffer.foldClusterInto(lastBaseX, y, text)
      continue

    if currentX + width > buffer.area.width:
      break

    if buffer.isValidPos(currentX, y):
      buffer[currentX, y] = cell(text, style, hyperlink)
      # For wide characters, mark the next cell as occupied (empty)
      # Also inherit the hyperlink for proper link region handling
      if width == 2 and buffer.isValidPos(currentX + 1, y):
        buffer[currentX + 1, y] = cell("", style, hyperlink)
      lastBaseX = currentX

    currentX += width

proc setRunes*(
    buffer: var Buffer,
    pos: Position,
    runes: seq[Rune],
    style: Style = defaultStyle(),
    hyperlink: string = "",
    tabWidth: int = DefaultTabWidth,
) {.inline.} =
  ## Set a sequence of runes starting at the given position
  buffer.setRunes(pos.x, pos.y, runes, style, hyperlink, tabWidth)

proc setString*(
    buffer: var Buffer,
    x, y: int,
    text: string,
    style: Style = defaultStyle(),
    hyperlink: string = "",
    tabWidth: int = DefaultTabWidth,
) =
  ## Set a string starting at the given coordinates.
  ## See `setRunes` for tab and C0 control character semantics.
  if text.len == 0:
    return
  try:
    buffer.setRunes(x, y, text.toRunes, style, hyperlink, tabWidth)
  except CatchableError:
    # Malformed UTF-8 or other unexpected error — stop gracefully.
    return

proc setString*(
    buffer: var Buffer,
    pos: Position,
    text: string,
    style: Style = defaultStyle(),
    hyperlink: string = "",
    tabWidth: int = DefaultTabWidth,
) {.inline.} =
  ## Set a string starting at the given position
  buffer.setString(pos.x, pos.y, text, style, hyperlink, tabWidth)

proc setString*(
    buffer: var Buffer,
    area: Rect,
    text: string,
    style: Style = defaultStyle(),
    hAlign: HAlign = hLeft,
    vAlign: VAlign = vTop,
    hyperlink: string = "",
) =
  ## Set a string within the given area with alignment
  ## Text is clipped to the area boundaries.
  ## Handles Unicode characters and wide characters properly for alignment calculation
  ##
  ## C0 control characters (including `\t`) are substituted with a single
  ## space — tab-stop expansion is intentionally skipped here because the
  ## alignment math is built around a fixed `textWidth`; the (x, y) overload
  ## of `setString` is the place to use real tab semantics.
  if text.len == 0 or area.isEmpty:
    return

  let runes = text.toRunes

  # Calculate display width of text by grapheme cluster (control chars treated
  # as 1 column). `clusterMetrics` measures without building cluster strings;
  # the layout loop below re-segments with `graphemeClusters` for the (small,
  # visible) clusters it actually draws. Re-segmenting is deterministic on the
  # same runes, so the two passes cannot diverge, and we avoid materializing a
  # cluster string for every off-screen cluster.
  var textWidth = 0
  for (leadIdx, width) in clusterMetrics(runes):
    if isC0Control(int(runes[leadIdx])):
      textWidth.inc
    else:
      textWidth += width

  # Calculate x position based on horizontal alignment
  let x =
    case hAlign
    of hLeft:
      area.x
    of hCenter:
      area.x + (area.width - textWidth) div 2
    of hRight:
      area.x + area.width - textWidth

  # Calculate y position based on vertical alignment
  let y =
    case vAlign
    of vTop:
      area.y
    of vMiddle:
      area.y + (area.height - 1) div 2
    of vBottom:
      area.y + area.height - 1

  var currentX = x
  var lastBaseX = -1 # Last base cell written within the area; see `setRunes`.
  try:
    for (leadIdx, clusterText, width) in graphemeClusters(runes):
      if isC0Control(int(runes[leadIdx])):
        # Substitute control char with single space.
        if currentX + 1 <= area.x:
          currentX.inc
          continue
        if currentX >= area.right:
          break
        if buffer.isValidPos(currentX, y):
          buffer[currentX, y] = cell(" ", style, hyperlink)
          lastBaseX = currentX
        currentX.inc
        continue

      # Zero-width cluster: fold into the base cell rather than giving it a
      # column of its own (see `setRunes`). A leading mark with no base
      # cell in the area is dropped.
      if width == 0:
        buffer.foldClusterInto(lastBaseX, y, clusterText)
        continue

      # Skip clusters whose base cell starts before the area. A wide cluster
      # straddling the left edge (currentX == area.x - 1) is dropped whole —
      # the right half cannot be drawn without an orphaned lead outside the
      # area, mirroring how the right edge drops a cluster overflowing it below.
      if currentX < area.x:
        currentX += width
        continue

      # Stop after the area
      if currentX >= area.right:
        break
      if currentX + width > area.right:
        break

      if buffer.isValidPos(currentX, y):
        buffer[currentX, y] = cell(clusterText, style, hyperlink)
        if width == 2 and buffer.isValidPos(currentX + 1, y):
          buffer[currentX + 1, y] = cell("", style, hyperlink)
        lastBaseX = currentX

      currentX += width
  except ValueError:
    return
  except CatchableError:
    return

proc foldZeroWidthRune*(buffer: var Buffer, x, y: int, rune: Rune) =
  ## Fold a zero-width rune (combining mark, ZWJ, variation selector) into the
  ## base cell immediately to the left of column `x`, keeping the grapheme
  ## cluster in a single cell.
  ##
  ## For per-rune `setCell` callers: after writing a base glyph and advancing
  ## the cursor to `x`, pass the following width-0 rune here. If the cell at
  ## `x - 1` is the shadow (right half) of a wide character, the rune is folded
  ## into the wide lead at `x - 2`. It is a no-op (the rune is dropped) when
  ## there is no base cell to the left or the coordinates are out of range —
  ## mirroring how `setRunes` drops a leading mark with nothing to attach to.
  if y < 0 or y >= buffer.area.height:
    return
  var bx = x - 1
  if bx < 0 or bx >= buffer.area.width:
    return
  if buffer.content[y][bx].isShadow and bx - 1 >= 0:
    dec bx
  buffer.foldClusterInto(bx, y, $rune)

proc setCell*(
    buffer: var Buffer,
    x, y: int,
    symbol: string,
    width: int,
    style: Style = defaultStyle(),
    hyperlink: string = "",
) =
  ## Set a single character cell at (x, y) with a known display width.
  ## Unlike setString, this skips UTF-8 parsing and width calculation.
  ## For wide characters (width=2), the next cell is automatically marked empty.
  ## If there is not enough room for the shadow cell, the character is not written.
  ## Caller is responsible for providing correct width.
  ##
  ## Wide-character consistency is maintained via `[]=` (see its doc).
  ##
  ## Unlike `setString`/`setRunes`, this does NOT fold zero-width runes
  ## (combining marks, ZWJ, variation selectors) into the preceding cell — it
  ## writes a standalone cell at (x, y). A caller rendering one rune at a time
  ## (e.g. to give each glyph its own style) must fold width-0 runes itself, or
  ## use `foldZeroWidthRune`; otherwise the mark lands on the next column and is
  ## overwritten.
  if x < 0 or x >= buffer.area.width or y < 0 or y >= buffer.area.height:
    return
  if width == 2 and x + 1 >= buffer.area.width:
    return
  buffer[x, y] = Cell(symbol: symbol, style: style, hyperlink: hyperlink)
  if width == 2:
    buffer[x + 1, y] = Cell(symbol: "", style: style, hyperlink: hyperlink)

proc setCell*(
    buffer: var Buffer,
    x, y: int,
    rune: Rune,
    width: int,
    style: Style = defaultStyle(),
    hyperlink: string = "",
) =
  ## Rune overload — converts to string once, then delegates.
  buffer.setCell(x, y, $rune, width, style, hyperlink)

proc setCell*(
    buffer: var Buffer,
    pos: Position,
    symbol: string,
    width: int,
    style: Style = defaultStyle(),
    hyperlink: string = "",
) =
  ## Position overload for setCell.
  buffer.setCell(pos.x, pos.y, symbol, width, style, hyperlink)

proc setCell*(
    buffer: var Buffer,
    pos: Position,
    rune: Rune,
    width: int,
    style: Style = defaultStyle(),
    hyperlink: string = "",
) =
  ## Position + Rune overload for setCell.
  buffer.setCell(pos.x, pos.y, $rune, width, style, hyperlink)

proc setString*(
    buffer: var Buffer,
    x, y: int,
    runes: seq[Rune],
    style: Style = defaultStyle(),
    hyperlink: string = "",
    tabWidth: int = DefaultTabWidth,
) =
  ## Alias for setRunes for convenience
  buffer.setRunes(x, y, runes, style, hyperlink, tabWidth)

proc setString*(
    buffer: var Buffer,
    pos: Position,
    runes: seq[Rune],
    style: Style = defaultStyle(),
    hyperlink: string = "",
    tabWidth: int = DefaultTabWidth,
) =
  ## Alias for setRunes for convenience
  buffer.setRunes(pos, runes, style, hyperlink, tabWidth)

proc resize*(buffer: var Buffer, newArea: Rect) =
  ## Resize the buffer to a new area
  let oldContent = buffer.content
  let oldArea = buffer.area

  buffer.area = newArea
  buffer.content = newSeqWith(newArea.height, newSeqWith(newArea.width, cell()))
  # Drop any per-row dirty state from the old size, then re-grow to the new
  # height with default-initialized RowDirty entries. markDirtyRect below
  # repopulates the dirty spans for the new area.
  buffer.dirty.rows.setLen(0)
  buffer.dirty.rows.setLen(newArea.height)
  buffer.dirty.anyDirty = false

  # Copy old content where it overlaps
  let intersection = oldArea.intersection(newArea)
  if not intersection.isEmpty:
    for y in intersection.y ..< intersection.bottom:
      for x in intersection.x ..< intersection.right:
        let oldX = x - oldArea.x
        let oldY = y - oldArea.y
        let newX = x - newArea.x
        let newY = y - newArea.y

        if oldX >= 0 and oldX < oldArea.width and oldY >= 0 and oldY < oldArea.height and
            newX >= 0 and newX < newArea.width and newY >= 0 and newY < newArea.height:
          buffer.content[newY][newX] = oldContent[oldY][oldX]

  # Mark entire new buffer as dirty after resize
  buffer.markDirtyRect(newArea)

# Buffer comparison and diffing
proc `==`*(a, b: Buffer): bool =
  ## Compare two buffers for equality
  if a.area != b.area:
    return false

  for y in 0 ..< a.area.height:
    for x in 0 ..< a.area.width:
      if a.content[y][x] != b.content[y][x]:
        return false

  return true

proc diff*(old, new: Buffer): seq[tuple[pos: Position, cell: Cell]] =
  ## Calculate differences between two buffers with dirty region optimization.
  ## Returns a sequence of changes needed to transform `old` into `new`.
  ##
  ## Uses per-row dirty tracking: rows untouched in `new` are skipped
  ## entirely, and within each dirty row only `[minX..maxX]` is scanned.
  ## When the total dirty cell count is very large, a full scan is used
  ## instead because it tends to be more cache-friendly than chasing
  ## many small spans.
  ##
  ## Performance characteristics:
  ## - No changes: O(1) – immediate return
  ## - Sparse changes: O(sum of dirty spans) – tight per-row loop
  ## - Large changes (> 2000 dirty cells): O(width × height) full scan
  result = @[]

  # Handle area mismatch - full redraw required
  if old.area != new.area:
    for y in 0 ..< new.area.height:
      for x in 0 ..< new.area.width:
        result.add((pos(x, y), new.content[y][x]))
    return

  # Fast path: no changes at all - O(1) via anyDirty.
  if not new.dirty.anyDirty:
    return

  const MaxDirtyRegionBeforeFullScan = 2000
  let dirtySize = new.getDirtyRegionSize()

  if dirtySize > MaxDirtyRegionBeforeFullScan:
    # Large dirty footprint - full scan is more cache-efficient
    for y in 0 ..< new.area.height:
      for x in 0 ..< new.area.width:
        if old.content[y][x] != new.content[y][x]:
          result.add((pos(x, y), new.content[y][x]))
  else:
    # Sparse scan: walk only dirty rows, only their column spans
    for y in 0 ..< new.dirty.rows.len:
      let row = new.dirty.rows[y]
      if not row.isDirty:
        continue
      for x in row.minX .. row.maxX:
        if old.content[y][x] != new.content[y][x]:
          result.add((pos(x, y), new.content[y][x]))

# Buffer merging and copying
proc merge*(dest: var Buffer, src: Buffer, srcArea: Rect, destPos: Position) =
  ## Merge part of source buffer into destination buffer
  let clippedSrcArea = src.area.intersection(srcArea)

  for y in clippedSrcArea.y ..< clippedSrcArea.bottom:
    for x in clippedSrcArea.x ..< clippedSrcArea.right:
      let srcX = x - src.area.x
      let srcY = y - src.area.y
      let destX = destPos.x + (x - clippedSrcArea.x)
      let destY = destPos.y + (y - clippedSrcArea.y)

      if src.isValidPos(srcX, srcY) and dest.isValidPos(destX, destY):
        dest[destX, destY] = src[srcX, srcY]

  # Mark merged area as dirty
  let mergedRect =
    rect(destPos.x, destPos.y, clippedSrcArea.width, clippedSrcArea.height)
  dest.markDirtyRect(mergedRect)

proc merge*(dest: var Buffer, src: Buffer, destPos: Position = pos(0, 0)) {.inline.} =
  ## Merge entire source buffer into destination buffer
  dest.merge(src, src.area, destPos)

# Rendering utilities
proc toStrings*(buffer: Buffer): seq[string] =
  ## Convert buffer to sequence of strings (one per row)
  result = newSeq[string](buffer.area.height)

  for y in 0 ..< buffer.area.height:
    var line = ""
    for x in 0 ..< buffer.area.width:
      line.add(buffer.content[y][x].symbol)
    result[y] = line

proc clone*(buffer: Buffer): Buffer =
  ## Create a deep copy of the buffer
  result = Buffer(
    area: buffer.area,
    content: newSeq[seq[Cell]](buffer.area.height),
    dirty: buffer.dirty,
  )
  for y in 0 ..< buffer.area.height:
    result.content[y] = buffer.content[y]

proc getCell*(buffer: Buffer, x, y: int): Cell {.inline.} =
  ## Get cell at coordinates (alias for [] operator)
  buffer[x, y]

proc `$`*(buffer: Buffer): string =
  ## String representation of Buffer
  let lines = buffer.toStrings()
  &"Buffer({buffer.area}):\n" & lines.join("\n")
