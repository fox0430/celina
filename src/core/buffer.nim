## Buffer system for Celina TUI library
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

  Buffer* = object ## 2D buffer representing terminal screen content
    area*: Rect # The area this buffer covers
    content*: seq[seq[Cell]] # 2D grid of cells

proc cell*(symbol: string = " ", style: Style = defaultStyle()): Cell {.inline.} =
  ## Create a new Cell
  Cell(symbol: symbol, style: style)

proc cell*(symbol: char, style: Style = defaultStyle()): Cell {.inline.} =
  ## Create a new Cell from a character
  Cell(symbol: $symbol, style: style)

proc cell*(symbol: Rune, style: Style = defaultStyle()): Cell {.inline.} =
  ## Create a new Cell from a Rune
  Cell(symbol: $symbol, style: style)

# Cell utilities
proc isEmpty*(cell: Cell): bool {.inline.} =
  ## Check if cell contains only whitespace
  cell.symbol.strip().len == 0

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
  a.symbol == b.symbol and a.style == b.style

proc `$`*(cell: Cell): string =
  ## String representation of Cell
  if cell.style == defaultStyle():
    &"Cell('{cell.symbol}')"
  else:
    &"Cell('{cell.symbol}', {cell.style})"

proc newBuffer*(area: Rect): Buffer =
  ## Create a new Buffer with the specified area
  result = Buffer(area: area)
  result.content = newSeqWith(area.height, newSeq[Cell](area.width))

  # Initialize with empty cells
  for y in 0 ..< area.height:
    for x in 0 ..< area.width:
      result.content[y][x] = cell()

proc newBuffer*(width, height: int): Buffer {.inline.} =
  ## Create a new Buffer with specified dimensions at origin
  newBuffer(rect(0, 0, width, height))

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

proc fill*(buffer: var Buffer, area: Rect, fillCell: Cell) =
  ## Fill a rectangular area with the given cell
  let clippedArea = buffer.area.intersection(area)

  for y in clippedArea.y ..< clippedArea.bottom:
    for x in clippedArea.x ..< clippedArea.right:
      let localX = x - buffer.area.x
      let localY = y - buffer.area.y
      if buffer.isValidPos(localX, localY):
        buffer[localX, localY] = fillCell

proc setString*(
    buffer: var Buffer, x, y: int, text: string, style: Style = defaultStyle()
) =
  ## Set a string starting at the given coordinates
  ## Handles Unicode characters and wide characters properly
  if text.len == 0:
    return
  
  # Validate starting position
  if not buffer.isValidPos(x, y):
    return

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
        buffer[currentX, y] = cell($rune, style)
        
        # For wide characters, mark the next cell as occupied (empty)
        if width == 2 and buffer.isValidPos(currentX + 1, y):
          buffer[currentX + 1, y] = cell("", style)

      currentX += width
  except ValueError:
    # Handle malformed Unicode gracefully by stopping
    return
  except CatchableError:
    # Handle other unexpected errors
    return

proc setString*(
    buffer: var Buffer, pos: Position, text: string, style: Style = defaultStyle()
) {.inline.} =
  ## Set a string starting at the given position
  buffer.setString(pos.x, pos.y, text, style)

proc setRunes*(
    buffer: var Buffer, x, y: int, runes: seq[Rune], style: Style = defaultStyle()
) =
  ## Set a sequence of runes starting at the given coordinates
  var currentX = x

  for rune in runes:
    let width = runeWidth(rune)
    if currentX + width > buffer.area.width:
      break

    if buffer.isValidPos(currentX, y):
      buffer[currentX, y] = cell($rune, style)
      # For wide characters, mark the next cell as occupied (empty)
      if width == 2 and buffer.isValidPos(currentX + 1, y):
        buffer[currentX + 1, y] = cell("", style)

    currentX += width

proc setRunes*(
    buffer: var Buffer, pos: Position, runes: seq[Rune], style: Style = defaultStyle()
) {.inline.} =
  ## Set a sequence of runes starting at the given position
  buffer.setRunes(pos.x, pos.y, runes, style)

proc setString*(
    buffer: var Buffer, x, y: int, runes: seq[Rune], style: Style = defaultStyle()
) {.inline.} =
  ## Alias for setRunes for convenience
  buffer.setRunes(x, y, runes, style)

proc setString*(
    buffer: var Buffer, pos: Position, runes: seq[Rune], style: Style = defaultStyle()
) {.inline.} =
  ## Alias for setRunes for convenience
  buffer.setRunes(pos, runes, style)

proc resize*(buffer: var Buffer, newArea: Rect) =
  ## Resize the buffer to a new area
  let oldContent = buffer.content
  let oldArea = buffer.area

  buffer.area = newArea
  buffer.content = newSeqWith(newArea.height, newSeq[Cell](newArea.width))

  # Initialize with empty cells
  for y in 0 ..< newArea.height:
    for x in 0 ..< newArea.width:
      buffer.content[y][x] = cell()

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
  ## Calculate differences between two buffers
  ## Returns a sequence of changes needed to transform old into new
  result = @[]

  if old.area != new.area:
    # If areas are different, return all cells of new buffer
    for y in 0 ..< new.area.height:
      for x in 0 ..< new.area.width:
        result.add((pos(x, y), new.content[y][x]))
    return

  # Compare cell by cell
  for y in 0 ..< new.area.height:
    for x in 0 ..< new.area.width:
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
