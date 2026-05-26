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
