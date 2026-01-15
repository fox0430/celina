## Buffer system
##
## This module provides the core buffer abstraction for managing
## terminal screen content and efficient rendering.

import std/[strformat, unicode, sequtils, strutils]
import unicodedb/widths
import geometry, colors

type
  Cell* = object ## Represents a single character cell in the terminal
    symbol*: string # UTF-8 string to support Unicode
    style*: Style # Visual styling
    hyperlink*: string # OSC 8 hyperlink URL (empty = no link)

  DirtyRegion* = object ## Tracks the rectangular region of changed cells
    isDirty*: bool # Whether any changes have been made
    minX*, minY*: int # Top-left corner of dirty region (inclusive)
    maxX*, maxY*: int # Bottom-right corner of dirty region (inclusive)

  Buffer* = object ## 2D buffer representing terminal screen content
    area*: Rect # The area this buffer covers
    content*: seq[seq[Cell]] # 2D grid of cells
    dirty*: DirtyRegion # Tracks changed region for optimized diff

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

proc runeWidth*(r: Rune): int =
  ## Get the display width of a rune using Unicode standard width detection
  if int(r) > 0x10FFFF:
    return 1
  case r.unicodeWidth
  of UnicodeWidth.uwdtNarrow, UnicodeWidth.uwdtHalf, UnicodeWidth.uwdtAmbiguous,
      UnicodeWidth.uwdtNeutral:
    1
  else:
    2

proc runesWidth*(runes: seq[Rune]): int =
  ## Calculate total display width of a sequence of runes
  result = 0
  for rune in runes:
    result += runeWidth(rune)

proc width*(cell: Cell): int =
  ## Get the display width of the cell's symbol
  if cell.symbol.len == 0:
    return 0
  let runes = cell.symbol.toRunes
  if runes.len == 0:
    return 0
  return runeWidth(runes[0])

proc `==`*(a, b: Cell): bool {.inline.} =
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

proc newBuffer*(area: Rect): Buffer {.inline.} =
  ## Create a new Buffer with the specified area
  Buffer(
    area: area,
    content: newSeqWith(area.height, newSeqWith(area.width, cell())),
    dirty: DirtyRegion(isDirty: false, minX: 0, minY: 0, maxX: 0, maxY: 0),
  )

proc newBuffer*(width, height: int): Buffer {.inline.} =
  ## Create a new Buffer with specified dimensions at origin
  newBuffer(rect(0, 0, width, height))

# Dirty region management
proc markDirty*(buffer: var Buffer, x, y: int) {.inline.} =
  ## Mark a specific cell as dirty for optimized diff calculation
  ## This expands the dirty region to include the specified cell
  if x < 0 or x >= buffer.area.width or y < 0 or y >= buffer.area.height:
    return # Out of bounds, ignore

  if not buffer.dirty.isDirty:
    # First change - initialize dirty region
    buffer.dirty = DirtyRegion(isDirty: true, minX: x, minY: y, maxX: x, maxY: y)
  else:
    # Expand existing dirty region
    buffer.dirty.minX = min(buffer.dirty.minX, x)
    buffer.dirty.minY = min(buffer.dirty.minY, y)
    buffer.dirty.maxX = max(buffer.dirty.maxX, x)
    buffer.dirty.maxY = max(buffer.dirty.maxY, y)

proc markDirtyRect*(buffer: var Buffer, rect: Rect) {.inline.} =
  ## Mark a rectangular area as dirty
  ## More efficient than marking individual cells when multiple cells change
  let clipped = buffer.area.intersection(rect)
  if clipped.isEmpty:
    return

  # Convert to buffer-local coordinates
  let localMinX = clipped.x - buffer.area.x
  let localMinY = clipped.y - buffer.area.y
  let localMaxX = clipped.right - 1 - buffer.area.x
  let localMaxY = clipped.bottom - 1 - buffer.area.y

  if not buffer.dirty.isDirty:
    buffer.dirty = DirtyRegion(
      isDirty: true, minX: localMinX, minY: localMinY, maxX: localMaxX, maxY: localMaxY
    )
  else:
    buffer.dirty.minX = min(buffer.dirty.minX, localMinX)
    buffer.dirty.minY = min(buffer.dirty.minY, localMinY)
    buffer.dirty.maxX = max(buffer.dirty.maxX, localMaxX)
    buffer.dirty.maxY = max(buffer.dirty.maxY, localMaxY)

proc clearDirty*(buffer: var Buffer) {.inline.} =
  ## Clear the dirty region after rendering
  ## Should be called after buffer has been successfully rendered
  buffer.dirty = DirtyRegion(isDirty: false, minX: 0, minY: 0, maxX: 0, maxY: 0)

proc getDirtyRegionSize*(buffer: Buffer): int {.inline.} =
  ## Get the number of cells in the dirty region
  ## Returns 0 if no changes have been made
  if not buffer.dirty.isDirty:
    return 0
  (buffer.dirty.maxX - buffer.dirty.minX + 1) *
    (buffer.dirty.maxY - buffer.dirty.minY + 1)

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

proc `[]=`*(buffer: var Buffer, x, y: int, cell: Cell) =
  ## Set cell at coordinates
  if x >= 0 and x < buffer.area.width and y >= 0 and y < buffer.area.height:
    buffer.content[y][x] = cell
    buffer.markDirty(x, y) # Track this change for optimized diff

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
  ## Clear the entire buffer with the given cell
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

proc setString*(
    buffer: var Buffer,
    x, y: int,
    text: string,
    style: Style = defaultStyle(),
    hyperlink: string = "",
) =
  ## Set a string starting at the given coordinates
  ## Handles Unicode characters and wide characters properly
  ## If hyperlink is provided, the text becomes a clickable link (OSC 8)
  if text.len == 0:
    return

  # Validate starting position
  if not buffer.isValidPos(x, y):
    return

  let startX = x
  var currentX = x

  try:
    for rune in text.runes:
      let width = runeWidth(rune)

      # Check if we have enough space for this character
      if currentX < 0 or currentX >= buffer.area.width:
        break
      if currentX + width > buffer.area.width:
        break

      if buffer.isValidPos(currentX, y):
        buffer[currentX, y] = cell($rune, style, hyperlink)

        # For wide characters, mark the next cell as occupied (empty)
        # Also inherit the hyperlink for proper link region handling
        if width == 2 and buffer.isValidPos(currentX + 1, y):
          buffer[currentX + 1, y] = cell("", style, hyperlink)

      currentX += width

    # Mark the changed region as dirty
    if currentX > startX:
      buffer.markDirty(startX, y)
      buffer.markDirty(currentX - 1, y)
  except ValueError:
    # Handle malformed Unicode gracefully by stopping
    return
  except CatchableError:
    # Handle other unexpected errors
    return

proc setString*(
    buffer: var Buffer,
    pos: Position,
    text: string,
    style: Style = defaultStyle(),
    hyperlink: string = "",
) {.inline.} =
  ## Set a string starting at the given position
  buffer.setString(pos.x, pos.y, text, style, hyperlink)

proc setRunes*(
    buffer: var Buffer,
    x, y: int,
    runes: seq[Rune],
    style: Style = defaultStyle(),
    hyperlink: string = "",
) =
  ## Set a sequence of runes starting at the given coordinates
  ## If hyperlink is provided, the text becomes a clickable link (OSC 8)
  let startX = x
  var currentX = x

  for rune in runes:
    let width = runeWidth(rune)
    if currentX + width > buffer.area.width:
      break

    if buffer.isValidPos(currentX, y):
      buffer[currentX, y] = cell($rune, style, hyperlink)
      # For wide characters, mark the next cell as occupied (empty)
      # Also inherit the hyperlink for proper link region handling
      if width == 2 and buffer.isValidPos(currentX + 1, y):
        buffer[currentX + 1, y] = cell("", style, hyperlink)

    currentX += width

  # Mark the changed region as dirty
  if currentX > startX:
    buffer.markDirty(startX, y)
    buffer.markDirty(currentX - 1, y)

proc setRunes*(
    buffer: var Buffer,
    pos: Position,
    runes: seq[Rune],
    style: Style = defaultStyle(),
    hyperlink: string = "",
) {.inline.} =
  ## Set a sequence of runes starting at the given position
  buffer.setRunes(pos.x, pos.y, runes, style, hyperlink)

proc setString*(
    buffer: var Buffer,
    x, y: int,
    runes: seq[Rune],
    style: Style = defaultStyle(),
    hyperlink: string = "",
) {.inline.} =
  ## Alias for setRunes for convenience
  buffer.setRunes(x, y, runes, style, hyperlink)

proc setString*(
    buffer: var Buffer,
    pos: Position,
    runes: seq[Rune],
    style: Style = defaultStyle(),
    hyperlink: string = "",
) {.inline.} =
  ## Alias for setRunes for convenience
  buffer.setRunes(pos, runes, style, hyperlink)

proc resize*(buffer: var Buffer, newArea: Rect) =
  ## Resize the buffer to a new area
  let oldContent = buffer.content
  let oldArea = buffer.area

  buffer.area = newArea
  buffer.content = newSeqWith(newArea.height, newSeqWith(newArea.width, cell()))

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
  ## Calculate differences between two buffers with dirty region optimization
  ## Returns a sequence of changes needed to transform old into new
  ##
  ## This optimized implementation uses the dirty region tracking to avoid
  ## scanning unchanged portions of the buffer, providing significant performance
  ## improvements for typical use cases (e.g., single character edits, cursor movement).
  ##
  ## Performance characteristics:
  ## - No changes: O(1) - immediate return
  ## - Small changes (1-100 cells): O(dirty region size) - highly optimized
  ## - Large changes (>2000 cells): O(width × height) - fallback to full scan
  result = @[]

  # Handle area mismatch - full redraw required
  if old.area != new.area:
    for y in 0 ..< new.area.height:
      for x in 0 ..< new.area.width:
        result.add((pos(x, y), new.content[y][x]))
    return

  # Fast path: no changes at all
  if not new.dirty.isDirty:
    return

  # Calculate dirty region size
  const MaxDirtyRegionBeforeFullScan = 2000
  let dirtySize = new.getDirtyRegionSize()

  # Adaptive strategy: use dirty region optimization for small/medium changes
  # but fall back to full scan for very large dirty regions
  if dirtySize > MaxDirtyRegionBeforeFullScan:
    # Large dirty region - full scan may be more cache-efficient
    for y in 0 ..< new.area.height:
      for x in 0 ..< new.area.width:
        if old.content[y][x] != new.content[y][x]:
          result.add((pos(x, y), new.content[y][x]))
  else:
    # Small/medium dirty region - scan only the changed area
    for y in new.dirty.minY .. new.dirty.maxY:
      for x in new.dirty.minX .. new.dirty.maxX:
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

proc `$`*(buffer: Buffer): string =
  ## String representation of Buffer
  let lines = buffer.toStrings()
  &"Buffer({buffer.area}):\n" & lines.join("\n")
