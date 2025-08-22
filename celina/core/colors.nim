## Color and style definitions for Celina CLI library
##
## This module provides color definitions, styling options, and utilities
## for terminal text formatting.

import std/[strformat, strutils, math]

## Note on Style.default() vs defaultStyle():
## ==========================================
## Nim automatically generates a default() function for all types, which returns
## zero values for all fields. For Style, this would be Style(fg: Black, bg: Black),
## which creates invisible black text on black background.
##
## To avoid this issue, we explicitly override Style.default() to return the same
## result as defaultStyle(), which uses the terminal's default colors.
##
## Both Style.default() and defaultStyle() can be used interchangeably.

type
  Color* = enum
    ## Basic 16 terminal colors
    Black = 0
    Red = 1
    Green = 2
    Yellow = 3
    Blue = 4
    Magenta = 5
    Cyan = 6
    White = 7
    BrightBlack = 8 # Often used as gray
    BrightRed = 9
    BrightGreen = 10
    BrightYellow = 11
    BrightBlue = 12
    BrightMagenta = 13
    BrightCyan = 14
    BrightWhite = 15
    Reset = 16 # Special value for default/reset

  RgbColor* = object ## 24-bit RGB color support
    r*, g*, b*: uint8

  ColorKind* = enum
    Indexed # 16-color palette
    Rgb # 24-bit RGB
    Indexed256 # 256-color palette
    Default # Use terminal default

  ColorValue* = object ## Union type for different color formats
    case kind*: ColorKind
    of Indexed:
      indexed*: Color
    of Rgb:
      rgb*: RgbColor
    of Indexed256:
      indexed256*: uint8 # 0-255 color index
    of Default:
      discard

  StyleModifier* = enum
    ## Text modifiers/attributes
    Bold
    Dim
    Italic
    Underline
    SlowBlink
    RapidBlink
    Reversed
    Crossed
    Hidden

  Style* = object ## Complete styling information for a cell
    fg*: ColorValue = ColorValue(kind: Default) # Foreground color
    bg*: ColorValue = ColorValue(kind: Default) # Background color
    modifiers*: set[StyleModifier] # Text modifiers

# Equality comparison for RgbColor
proc `==`*(a, b: RgbColor): bool {.inline.} =
  ## Compare two RgbColor objects
  return a.r == b.r and a.g == b.g and a.b == b.b

# Equality comparison for ColorValue
proc `==`*(a, b: ColorValue): bool =
  ## Compare two ColorValue objects
  if a.kind != b.kind:
    return false

  case a.kind
  of Indexed:
    a.indexed == b.indexed
  of Rgb:
    a.rgb == b.rgb
  of Indexed256:
    a.indexed256 == b.indexed256
  of Default:
    true

proc `==`*(a, b: Style): bool {.inline.} =
  ## Compare two Style objects
  a.fg == b.fg and a.bg == b.bg and a.modifiers == b.modifiers

# Color constructors
proc color*(c: Color): ColorValue {.inline.} =
  ## Create a ColorValue from a basic Color
  ColorValue(kind: Indexed, indexed: c)

proc rgb*(r, g, b: uint8): ColorValue {.inline.} =
  ## Create a ColorValue from RGB values
  ColorValue(kind: Rgb, rgb: RgbColor(r: r, g: g, b: b))

proc rgb*(r, g, b: int): ColorValue {.inline.} =
  ## Create a ColorValue from RGB integer values (0-255)
  ColorValue(kind: Rgb, rgb: RgbColor(r: r.uint8, g: g.uint8, b: b.uint8))

proc rgb*(hex: string): ColorValue =
  ## Create a ColorValue from hex string (e.g., "#FF0000" or "FF0000")
  ## 
  ## Parameters:
  ## - hex: Hex color string, with or without '#' prefix
  ##
  ## Returns:
  ## - ColorValue with parsed RGB color, or black (0,0,0) if parsing fails
  ##
  ## Note: This function handles errors gracefully by returning black instead of raising exceptions
  try:
    var hexStr = hex
    if hexStr.startsWith("#"):
      hexStr = hexStr[1 ..^ 1]

    if hexStr.len != 6:
      return ColorValue(kind: Rgb, rgb: RgbColor(r: 0, g: 0, b: 0))

    let r = parseHexInt(hexStr[0 .. 1]).uint8
    let g = parseHexInt(hexStr[2 .. 3]).uint8
    let b = parseHexInt(hexStr[4 .. 5]).uint8
    ColorValue(kind: Rgb, rgb: RgbColor(r: r, g: g, b: b))
  except ValueError:
    # Return black on parsing error
    ColorValue(kind: Rgb, rgb: RgbColor(r: 0, g: 0, b: 0))
  except CatchableError:
    # Return black on any other error
    ColorValue(kind: Rgb, rgb: RgbColor(r: 0, g: 0, b: 0))

proc color256*(index: uint8): ColorValue {.inline.} =
  ## Create a ColorValue from 256-color palette index (0-255)
  ColorValue(kind: Indexed256, indexed256: index)

proc color256*(index: int): ColorValue {.inline.} =
  ## Create a ColorValue from 256-color palette index (0-255)
  ## Clamps to valid range if out of bounds
  let clampedIndex = clamp(index, 0, 255)
  ColorValue(kind: Indexed256, indexed256: clampedIndex.uint8)

proc defaultColor*(): ColorValue {.inline.} =
  ## Create a default ColorValue
  ColorValue(kind: Default)

# HSV color support
proc hsvToRgb*(h, s, v: float): RgbColor =
  ## Convert HSV (Hue, Saturation, Value) to RGB
  ## h: 0.0-360.0, s: 0.0-1.0, v: 0.0-1.0
  let c = v * s
  let x = c * (1.0 - abs((h / 60.0).mod(2.0) - 1.0))
  let m = v - c

  let (r_prime, g_prime, b_prime) =
    if h < 60.0:
      (c, x, 0.0)
    elif h < 120.0:
      (x, c, 0.0)
    elif h < 180.0:
      (0.0, c, x)
    elif h < 240.0:
      (0.0, x, c)
    elif h < 300.0:
      (x, 0.0, c)
    else:
      (c, 0.0, x)

  RgbColor(
    r: ((r_prime + m) * 255.0).uint8,
    g: ((g_prime + m) * 255.0).uint8,
    b: ((b_prime + m) * 255.0).uint8,
  )

proc hsv*(h, s, v: float): ColorValue {.inline.} =
  ## Create a ColorValue from HSV values
  ## h: 0.0-360.0 (hue), s: 0.0-1.0 (saturation), v: 0.0-1.0 (value)
  ColorValue(kind: Rgb, rgb: hsvToRgb(h, s, v))

# Common color palettes and utilities
proc lerp*(a, b: RgbColor, t: float): RgbColor =
  ## Linear interpolation between two RGB colors
  ## t: 0.0-1.0 (0.0 = color a, 1.0 = color b)
  let t_clamped = clamp(t, 0.0, 1.0)
  RgbColor(
    r: (a.r.float * (1.0 - t_clamped) + b.r.float * t_clamped).uint8,
    g: (a.g.float * (1.0 - t_clamped) + b.g.float * t_clamped).uint8,
    b: (a.b.float * (1.0 - t_clamped) + b.b.float * t_clamped).uint8,
  )

proc lerp*(a, b: ColorValue, t: float): ColorValue =
  ## Linear interpolation between two ColorValues (only works with RGB)
  if a.kind == Rgb and b.kind == Rgb:
    ColorValue(kind: Rgb, rgb: lerp(a.rgb, b.rgb, t))
  else:
    a # Fallback to first color for non-RGB

# Predefined true color values
proc hotPink*(): ColorValue {.inline.} =
  rgb(255, 105, 180)

proc deepSkyBlue*(): ColorValue {.inline.} =
  rgb(0, 191, 255)

proc limeGreen*(): ColorValue {.inline.} =
  rgb(50, 205, 50)

proc orange*(): ColorValue {.inline.} =
  rgb(255, 165, 0)

proc violet*(): ColorValue {.inline.} =
  rgb(238, 130, 238)

proc gold*(): ColorValue {.inline.} =
  rgb(255, 215, 0)

proc crimson*(): ColorValue {.inline.} =
  rgb(220, 20, 60)

proc teal*(): ColorValue {.inline.} =
  rgb(0, 128, 128)

proc indigo*(): ColorValue {.inline.} =
  rgb(75, 0, 130)

proc salmon*(): ColorValue {.inline.} =
  rgb(250, 128, 114)

# 256-color palette convenience functions
proc grayscale*(level: int): ColorValue =
  ## Create grayscale color from 256-color palette (levels 0-23)
  ## 0 = black, 23 = white. Clamps to valid range if out of bounds.
  let clampedLevel = clamp(level, 0, 23)
  color256(232 + clampedLevel.uint8)

proc cubeColor*(r, g, b: int): ColorValue =
  ## Create color from 6x6x6 RGB cube in 256-color palette
  ## Each component: 0-5 (0=darkest, 5=brightest). Clamps to valid range if out of bounds.
  let clampedR = clamp(r, 0, 5)
  let clampedG = clamp(g, 0, 5)
  let clampedB = clamp(b, 0, 5)
  color256(16 + 36 * clampedR + 6 * clampedG + clampedB)

# Common 256-color palette shortcuts
proc brightColors*(): seq[ColorValue] =
  ## Get bright colors from 256-color palette
  @[color256(9), color256(10), color256(11), color256(12), color256(13), color256(14)]

proc darkColors*(): seq[ColorValue] =
  ## Get dark colors from 256-color palette
  @[color256(1), color256(2), color256(3), color256(4), color256(5), color256(6)]

proc pastels*(): seq[ColorValue] =
  ## Get pastel colors from 256-color palette
  @[
    color256(217),
    color256(223),
    color256(229),
    color256(195),
    color256(159),
    color256(183),
  ]

# Style constructors
proc style*(
    fg: ColorValue = defaultColor(),
    bg: ColorValue = defaultColor(),
    modifiers: set[StyleModifier] = {},
): Style {.inline.} =
  ## Create a new Style
  Style(fg: fg, bg: bg, modifiers: modifiers)

proc style*(
    fg: Color, bg: Color = Reset, modifiers: set[StyleModifier] = {}
): Style {.inline.} =
  ## Create a Style with basic colors
  Style(
    fg: color(fg),
    bg:
      if bg == Reset:
        defaultColor()
      else:
        color(bg),
    modifiers: modifiers,
  )

# Style manipulation
proc withFg*(s: Style, fg: ColorValue): Style {.inline.} =
  ## Create a new Style with different foreground color
  Style(fg: fg, bg: s.bg, modifiers: s.modifiers)

proc withFg*(s: Style, fg: Color): Style {.inline.} =
  ## Create a new Style with different foreground color
  s.withFg(color(fg))

proc withBg*(s: Style, bg: ColorValue): Style {.inline.} =
  ## Create a new Style with different background color
  Style(fg: s.fg, bg: bg, modifiers: s.modifiers)

proc withBg*(s: Style, bg: Color): Style {.inline.} =
  ## Create a new Style with different background color
  s.withBg(color(bg))

proc withModifiers*(s: Style, modifiers: set[StyleModifier]): Style {.inline.} =
  ## Create a new Style with different modifiers
  Style(fg: s.fg, bg: s.bg, modifiers: modifiers)

proc addModifier*(s: Style, modifier: StyleModifier): Style {.inline.} =
  ## Add a modifier to the Style
  Style(fg: s.fg, bg: s.bg, modifiers: s.modifiers + {modifier})

proc removeModifier*(s: Style, modifier: StyleModifier): Style {.inline.} =
  ## Remove a modifier from the Style
  Style(fg: s.fg, bg: s.bg, modifiers: s.modifiers - {modifier})

# Predefined styles
proc defaultStyle*(): Style {.inline.} =
  ## Default style with no special formatting
  style()

proc default*(T: typedesc[Style]): Style {.inline.} =
  ## Override Nim's default() to return a proper default style
  ## This ensures Style.default() returns the same as defaultStyle()
  ## instead of Style(fg: Black, bg: Black) which would be invisible
  defaultStyle()

proc bold*(fg: Color = Reset): Style {.inline.} =
  ## Bold text style
  style(fg, modifiers = {Bold})

proc italic*(fg: Color = Reset): Style {.inline.} =
  ## Italic text style
  style(fg, modifiers = {Italic})

proc underline*(fg: Color = Reset): Style {.inline.} =
  ## Underlined text style
  style(fg, modifiers = {Underline})

proc reversed*(): Style {.inline.} =
  ## Reversed colors style
  style(modifiers = {Reversed})

# ANSI escape sequence generation
proc toAnsiCode*(color: Color): string =
  ## Convert Color to ANSI color code
  case color
  of Black: "30"
  of Red: "31"
  of Green: "32"
  of Yellow: "33"
  of Blue: "34"
  of Magenta: "35"
  of Cyan: "36"
  of White: "37"
  of BrightBlack: "90"
  of BrightRed: "91"
  of BrightGreen: "92"
  of BrightYellow: "93"
  of BrightBlue: "94"
  of BrightMagenta: "95"
  of BrightCyan: "96"
  of BrightWhite: "97"
  of Reset: "39"

proc toBgAnsiCode*(color: Color): string =
  ## Convert Color to ANSI background color code
  case color
  of Black: "40"
  of Red: "41"
  of Green: "42"
  of Yellow: "43"
  of Blue: "44"
  of Magenta: "45"
  of Cyan: "46"
  of White: "47"
  of BrightBlack: "100"
  of BrightRed: "101"
  of BrightGreen: "102"
  of BrightYellow: "103"
  of BrightBlue: "104"
  of BrightMagenta: "105"
  of BrightCyan: "106"
  of BrightWhite: "107"
  of Reset: "49"

proc toAnsiCode*(rgb: RgbColor, background: bool = false): string =
  ## Convert RGB color to ANSI 24-bit color code
  let prefix = if background: "48" else: "38"
  &"{prefix};2;{rgb.r};{rgb.g};{rgb.b}"

proc toAnsiCode*(colorValue: ColorValue, background: bool = false): string =
  ## Convert ColorValue to ANSI color code
  case colorValue.kind
  of Indexed:
    if background:
      colorValue.indexed.toBgAnsiCode()
    else:
      colorValue.indexed.toAnsiCode()
  of Rgb:
    colorValue.rgb.toAnsiCode(background)
  of Indexed256:
    let prefix = if background: "48" else: "38"
    &"{prefix};5;{colorValue.indexed256}"
  of Default:
    if background: "49" else: "39"

proc toAnsiCode*(modifier: StyleModifier): string =
  ## Convert Modifier to ANSI code
  case modifier
  of Bold: "1"
  of Dim: "2"
  of Italic: "3"
  of Underline: "4"
  of SlowBlink: "5"
  of RapidBlink: "6"
  of Reversed: "7"
  of Hidden: "8"
  of Crossed: "9"

proc toAnsiSequence*(style: Style): string =
  ## Convert Style to complete ANSI escape sequence
  var codes: seq[string] = @[]

  # Foreground color
  if style.fg.kind != Default:
    codes.add(style.fg.toAnsiCode(false))

  # Background color - always set to ensure terminal default is used
  if style.bg.kind != Default:
    codes.add(style.bg.toAnsiCode(true))
  elif style.fg.kind != Default:
    # When only foreground is set, explicitly reset background to terminal default
    codes.add("49")

  # Modifiers
  for modifier in style.modifiers:
    codes.add(modifier.toAnsiCode())

  if codes.len > 0:
    "\e[" & codes.join(";") & "m"
  else:
    ""

proc resetSequence*(): string {.inline.} =
  ## ANSI sequence to reset all formatting
  "\e[0m"

# String representation
proc `$`*(rgb: RgbColor): string {.inline.} =
  &"RGB({rgb.r}, {rgb.g}, {rgb.b})"

proc `$`*(colorValue: ColorValue): string =
  case colorValue.kind
  of Indexed:
    $colorValue.indexed
  of Rgb:
    $colorValue.rgb
  of Indexed256:
    &"Color256({colorValue.indexed256})"
  of Default:
    "Default"

proc `$`*(style: Style): string =
  var parts: seq[string] = @[]

  if style.fg.kind != Default:
    parts.add(&"fg: {style.fg}")

  if style.bg.kind != Default:
    parts.add(&"bg: {style.bg}")

  if style.modifiers.len > 0:
    parts.add(&"modifiers: {style.modifiers}")

  if parts.len > 0:
    "Style(" & parts.join(", ") & ")"
  else:
    "Style(default)"
