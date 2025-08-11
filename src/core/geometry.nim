## Core geometric types for Celina CLI library
##
## This module defines the fundamental geometric types used throughout
## the library for positioning, sizing, and area calculations.

import std/strformat

type
  Position* = object ## Represents a 2D position with x and y coordinates
    x*, y*: int

  Size* = object ## Represents dimensions with width and height
    width*, height*: int

  Rect* = object ## Represents a rectangular area with position and dimensions
    x*, y*: int
    width*, height*: int

  Area* = Rect ## Alias for Rect, commonly used for widget areas

# Position constructors and utilities
proc pos*(x, y: int): Position {.inline.} =
  ## Create a new Position
  return Position(x: x, y: y)

proc `+`*(a, b: Position): Position {.inline.} =
  ## Add two positions
  return Position(x: a.x + b.x, y: a.y + b.y)

proc `-`*(a, b: Position): Position {.inline.} =
  ## Subtract two positions
  return Position(x: a.x - b.x, y: a.y - b.y)

proc `$`*(pos: Position): string {.inline.} =
  ## String representation of Position
  return fmt"({pos.x}, {pos.y})"

# Size constructors and utilities
proc size*(width, height: int): Size {.inline.} =
  ## Create a new Size
  return Size(width: width, height: height)

proc area*(size: Size): int {.inline.} =
  ## Calculate the total area (width * height)
  return size.width * size.height

proc `$`*(size: Size): string {.inline.} =
  ## String representation of Size
  return &"{size.width}x{size.height}"

# Rect constructors and utilities
proc rect*(x, y, width, height: int): Rect {.inline.} =
  ## Create a new Rect
  return Rect(x: x, y: y, width: width, height: height)

proc rect*(pos: Position, size: Size): Rect {.inline.} =
  ## Create a Rect from Position and Size
  return Rect(x: pos.x, y: pos.y, width: size.width, height: size.height)

proc position*(r: Rect): Position {.inline.} =
  ## Get the position of a Rect
  return Position(x: r.x, y: r.y)

proc size*(r: Rect): Size {.inline.} =
  ## Get the size of a Rect
  return Size(width: r.width, height: r.height)

proc area*(r: Rect): int {.inline.} =
  ## Calculate the area of a Rect
  return r.width * r.height

proc right*(r: Rect): int {.inline.} =
  ## Get the right edge x-coordinate
  return r.x + r.width

proc bottom*(r: Rect): int {.inline.} =
  ## Get the bottom edge y-coordinate
  return r.y + r.height

proc center*(r: Rect): Position {.inline.} =
  ## Get the center position of a Rect
  return Position(x: r.x + r.width div 2, y: r.y + r.height div 2)

proc contains*(r: Rect, pos: Position): bool {.inline.} =
  ## Check if a Rect contains a Position
  return pos.x >= r.x and pos.x < r.right and pos.y >= r.y and pos.y < r.bottom

proc contains*(r: Rect, x, y: int): bool {.inline.} =
  ## Check if a Rect contains coordinates
  return r.contains(Position(x: x, y: y))

proc intersects*(a, b: Rect): bool {.inline.} =
  ## Check if two Rects intersect
  return a.x < b.right and a.right > b.x and a.y < b.bottom and a.bottom > b.y

proc intersection*(a, b: Rect): Rect =
  ## Calculate the intersection of two Rects
  let
    left = max(a.x, b.x)
    top = max(a.y, b.y)
    right = min(a.right, b.right)
    bottom = min(a.bottom, b.bottom)

  if left < right and top < bottom:
    result = rect(left, top, right - left, bottom - top)
  else:
    result = rect(0, 0, 0, 0) # Empty rect

proc union*(a, b: Rect): Rect =
  ## Calculate the union of two Rects
  let
    left = min(a.x, b.x)
    top = min(a.y, b.y)
    right = max(a.right, b.right)
    bottom = max(a.bottom, b.bottom)

  return rect(left, top, right - left, bottom - top)

proc shrink*(r: Rect, margin: int): Rect {.inline.} =
  ## Shrink a Rect by a margin on all sides
  return rect(
    r.x + margin,
    r.y + margin,
    max(0, r.width - margin * 2),
    max(0, r.height - margin * 2),
  )

proc shrink*(r: Rect, horizontal, vertical: int): Rect {.inline.} =
  ## Shrink a Rect by different margins horizontally and vertically
  return rect(
    r.x + horizontal,
    r.y + vertical,
    max(0, r.width - horizontal * 2),
    max(0, r.height - vertical * 2),
  )

proc expand*(r: Rect, margin: int): Rect {.inline.} =
  ## Expand a Rect by a margin on all sides
  rect(r.x - margin, r.y - margin, r.width + margin * 2, r.height + margin * 2)

proc `$`*(r: Rect): string {.inline.} =
  ## String representation of Rect
  return &"Rect({r.x}, {r.y}, {r.width}, {r.height})"

# Validation utilities
proc isValid*(size: Size): bool {.inline.} =
  ## Check if Size has positive dimensions
  return size.width > 0 and size.height > 0

proc isValid*(r: Rect): bool {.inline.} =
  ## Check if Rect has positive dimensions
  return r.width > 0 and r.height > 0

proc isEmpty*(r: Rect): bool {.inline.} =
  ## Check if Rect is empty (zero area)
  return r.width <= 0 or r.height <= 0
