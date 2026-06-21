## Border styles and characters for widgets and windows
##
## Centralizes border kind selection and the character glyphs used when
## drawing them. Previously, `widgets/input.nim`, `widgets/table.nim`, and
## `core/windows.nim` each carried their own definitions, which both
## duplicated logic and named the enum `BorderStyle` despite using different
## value sets. This module provides one `BorderKind` enum that covers the
## union of those values, and one `BorderChars` object that supports both
## simple borders (windows, input) and grid borders (table) via the extra
## intersection glyph fields.
##
## It also provides `drawBox`, the single edge/corner painter shared by
## `core/windows` and `widgets/panel` so the two framing primitives can never
## disagree on how a box is drawn.

import buffer, geometry, colors

type
  BorderKind* = enum
    ## Border drawing style.
    ##
    ## The previous per-widget `BorderStyle` enums used unprefixed names
    ## (e.g. `NoBorder`). Those identifiers are preserved as deprecated
    ## aliases in the widgets that defined them, so legacy code continues
    ## to compile with a warning.
    bkNone ## No border drawn
    bkSingle ## Single-line box: ┌─┐ │ └─┘
    bkDouble ## Double-line box: ╔═╗ ║ ╚═╝
    bkRounded ## Rounded corners: ╭─╮ │ ╰─╯
    bkSimple ## ASCII fallback: +-+ | +-+

  BorderChars* = object ## Characters used for drawing borders
    horizontal*: string
    vertical*: string
    topLeft*: string
    topRight*: string
    bottomLeft*: string
    bottomRight*: string
    # Grid extensions (used by table; empty/duplicated for simple frames)
    cross*: string ## Four-way intersection
    topT*: string ## Top T-junction
    bottomT*: string ## Bottom T-junction
    leftT*: string ## Left T-junction
    rightT*: string ## Right T-junction

  BorderStyle* {.deprecated: "Use `BorderKind`".} = BorderKind
    ## Deprecated aliases for the legacy per-widget `BorderStyle` enums and
    ## their unprefixed values. Centralized here so that importing both
    ## `widgets/input` and `widgets/table` does not produce ambiguous-identifier
    ## errors for symbols that previously lived in each widget module.

proc getBorderChars*(kind: BorderKind): BorderChars =
  ## Get border characters for the specified border kind.
  case kind
  of bkNone:
    BorderChars()
  of bkSingle:
    BorderChars(
      horizontal: "─",
      vertical: "│",
      topLeft: "┌",
      topRight: "┐",
      bottomLeft: "└",
      bottomRight: "┘",
      cross: "┼",
      topT: "┬",
      bottomT: "┴",
      leftT: "├",
      rightT: "┤",
    )
  of bkDouble:
    BorderChars(
      horizontal: "═",
      vertical: "║",
      topLeft: "╔",
      topRight: "╗",
      bottomLeft: "╚",
      bottomRight: "╝",
      cross: "╬",
      topT: "╦",
      bottomT: "╩",
      leftT: "╠",
      rightT: "╣",
    )
  of bkRounded:
    BorderChars(
      horizontal: "─",
      vertical: "│",
      topLeft: "╭",
      topRight: "╮",
      bottomLeft: "╰",
      bottomRight: "╯",
      cross: "┼",
      topT: "┬",
      bottomT: "┴",
      leftT: "├",
      rightT: "┤",
    )
  of bkSimple:
    BorderChars(
      horizontal: "-",
      vertical: "|",
      topLeft: "+",
      topRight: "+",
      bottomLeft: "+",
      bottomRight: "+",
      cross: "+",
      topT: "+",
      bottomT: "+",
      leftT: "+",
      rightT: "+",
    )

proc defaultBorderChars*(): BorderChars =
  ## Default border characters using single-line box drawing.
  getBorderChars(bkSingle)

proc drawBox*(
    buf: var Buffer,
    area: Rect,
    chars: BorderChars,
    top, right, bottom, left: bool,
    style: Style = defaultStyle(),
) =
  ## Paint a box frame into `area`: the requested edges plus the corner glyphs
  ## where two adjacent requested edges meet.
  ##
  ## Edges are drawn with `fill` (one pre-built cell per position, avoiding the
  ## per-cell UTF-8 re-parse a `setString` loop incurs) and the four corners
  ## are written last, so a corner glyph always wins its cell — no per-corner
  ## size guards are needed. Degenerate areas collapse predictably: in a
  ## one-row area the top edge wins over the bottom, and in a one-column area
  ## the left wins over the right, so a parallel edge is never silently
  ## overwritten by its twin. The caller is responsible for not invoking this
  ## with a `bkNone`/empty-edge frame (it would simply draw nothing).
  if area.isEmpty:
    return

  let
    drawTop = top
    drawBottom = bottom and (area.height > 1 or not top)
    drawLeft = left
    drawRight = right and (area.width > 1 or not left)

  # Edges first, full span; corners overwrite the ends below.
  if drawTop:
    buf.fill(rect(area.x, area.y, area.width, 1), cell(chars.horizontal, style))
  if drawBottom:
    buf.fill(
      rect(area.x, area.bottom - 1, area.width, 1), cell(chars.horizontal, style)
    )
  if drawLeft:
    buf.fill(rect(area.x, area.y, 1, area.height), cell(chars.vertical, style))
  if drawRight:
    buf.fill(rect(area.right - 1, area.y, 1, area.height), cell(chars.vertical, style))

  # Corners: only where both adjacent edges were actually drawn.
  if drawTop and drawLeft:
    buf.setString(area.x, area.y, chars.topLeft, style)
  if drawTop and drawRight:
    buf.setString(area.right - 1, area.y, chars.topRight, style)
  if drawBottom and drawLeft:
    buf.setString(area.x, area.bottom - 1, chars.bottomLeft, style)
  if drawBottom and drawRight:
    buf.setString(area.right - 1, area.bottom - 1, chars.bottomRight, style)

template NoBorder*(): BorderKind {.deprecated: "Use `bkNone`".} =
  bkNone

template SingleBorder*(): BorderKind {.deprecated: "Use `bkSingle`".} =
  bkSingle

template DoubleBorder*(): BorderKind {.deprecated: "Use `bkDouble`".} =
  bkDouble

template RoundedBorder*(): BorderKind {.deprecated: "Use `bkRounded`".} =
  bkRounded

template SimpleBorder*(): BorderKind {.deprecated: "Use `bkSimple`".} =
  bkSimple
