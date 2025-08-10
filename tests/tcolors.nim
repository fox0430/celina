import std/[unittest, strutils]

import ../src/core/colors

# Test suite for Colors module
suite "Colors Module Tests":
  suite "Color Enum Tests":
    test "Basic color enum values":
      check Color.Black.ord == 0
      check Color.Red.ord == 1
      check Color.Green.ord == 2
      check Color.Yellow.ord == 3
      check Color.Blue.ord == 4
      check Color.Magenta.ord == 5
      check Color.Cyan.ord == 6
      check Color.White.ord == 7

    test "Bright color enum values":
      check Color.BrightBlack.ord == 8
      check Color.BrightRed.ord == 9
      check Color.BrightGreen.ord == 10
      check Color.BrightYellow.ord == 11
      check Color.BrightBlue.ord == 12
      check Color.BrightMagenta.ord == 13
      check Color.BrightCyan.ord == 14
      check Color.BrightWhite.ord == 15

    test "Reset color value":
      check Color.Reset.ord == 16

  suite "RgbColor Tests":
    test "RgbColor creation":
      let rgb = RgbColor(r: 255, g: 128, b: 64)
      check rgb.r == 255
      check rgb.g == 128
      check rgb.b == 64

    test "RgbColor equality":
      let rgb1 = RgbColor(r: 255, g: 0, b: 0)
      let rgb2 = RgbColor(r: 255, g: 0, b: 0)
      let rgb3 = RgbColor(r: 0, g: 255, b: 0)

      check rgb1 == rgb2
      check rgb1 != rgb3
      check rgb2 != rgb3

    test "RgbColor string representation":
      let rgb = RgbColor(r: 123, g: 45, b: 67)
      let str = $rgb
      check str == "RGB(123, 45, 67)"

  suite "ColorKind Tests":
    test "ColorKind enum values":
      check ColorKind.Indexed.ord == 0
      check ColorKind.Rgb.ord == 1
      check ColorKind.Indexed256.ord == 2
      check ColorKind.Default.ord == 3

  suite "ColorValue Tests":
    test "ColorValue indexed creation":
      let colorVal = ColorValue(kind: Indexed, indexed: Color.Red)
      check colorVal.kind == Indexed
      check colorVal.indexed == Color.Red

    test "ColorValue RGB creation":
      let rgb = RgbColor(r: 255, g: 128, b: 0)
      let colorVal = ColorValue(kind: Rgb, rgb: rgb)
      check colorVal.kind == Rgb
      check colorVal.rgb == rgb

    test "ColorValue default creation":
      let colorVal = ColorValue(kind: Default)
      check colorVal.kind == Default

    test "ColorValue equality - same indexed colors":
      let color1 = ColorValue(kind: Indexed, indexed: Color.Blue)
      let color2 = ColorValue(kind: Indexed, indexed: Color.Blue)
      check color1 == color2

    test "ColorValue equality - different indexed colors":
      let color1 = ColorValue(kind: Indexed, indexed: Color.Blue)
      let color2 = ColorValue(kind: Indexed, indexed: Color.Red)
      check color1 != color2

    test "ColorValue equality - same RGB colors":
      let rgb = RgbColor(r: 100, g: 150, b: 200)
      let color1 = ColorValue(kind: Rgb, rgb: rgb)
      let color2 = ColorValue(kind: Rgb, rgb: rgb)
      check color1 == color2

    test "ColorValue equality - different RGB colors":
      let rgb1 = RgbColor(r: 100, g: 150, b: 200)
      let rgb2 = RgbColor(r: 200, g: 150, b: 100)
      let color1 = ColorValue(kind: Rgb, rgb: rgb1)
      let color2 = ColorValue(kind: Rgb, rgb: rgb2)
      check color1 != color2

    test "ColorValue equality - default colors":
      let color1 = ColorValue(kind: Default)
      let color2 = ColorValue(kind: Default)
      check color1 == color2

    test "ColorValue 256-color creation":
      let color256Val = ColorValue(kind: Indexed256, indexed256: 42)
      check color256Val.kind == Indexed256
      check color256Val.indexed256 == 42

    test "ColorValue equality - same 256 colors":
      let color1 = ColorValue(kind: Indexed256, indexed256: 128)
      let color2 = ColorValue(kind: Indexed256, indexed256: 128)
      check color1 == color2

    test "ColorValue equality - different 256 colors":
      let color1 = ColorValue(kind: Indexed256, indexed256: 100)
      let color2 = ColorValue(kind: Indexed256, indexed256: 200)
      check color1 != color2

    test "ColorValue equality - different kinds":
      let indexed = ColorValue(kind: Indexed, indexed: Color.Red)
      let rgb = ColorValue(kind: Rgb, rgb: RgbColor(r: 255, g: 0, b: 0))
      let indexed256 = ColorValue(kind: Indexed256, indexed256: 9)
      let default = ColorValue(kind: Default)

      check indexed != rgb
      check indexed != indexed256
      check indexed != default
      check rgb != indexed256
      check rgb != default
      check indexed256 != default

    test "ColorValue string representation":
      let indexed = ColorValue(kind: Indexed, indexed: Color.Red)
      let rgb = ColorValue(kind: Rgb, rgb: RgbColor(r: 255, g: 128, b: 64))
      let indexed256 = ColorValue(kind: Indexed256, indexed256: 217)
      let default = ColorValue(kind: Default)

      check $indexed == "Red"
      check $rgb == "RGB(255, 128, 64)"
      check $indexed256 == "Color256(217)"
      check $default == "Default"

  suite "Color Constructor Functions":
    test "color() function":
      let colorVal = color(Color.Green)
      check colorVal.kind == Indexed
      check colorVal.indexed == Color.Green

    test "rgb() function":
      let colorVal = rgb(100, 200, 50)
      check colorVal.kind == Rgb
      check colorVal.rgb.r == 100
      check colorVal.rgb.g == 200
      check colorVal.rgb.b == 50

    test "color256() function with uint8":
      let colorVal = color256(123u8)
      check colorVal.kind == Indexed256
      check colorVal.indexed256 == 123

    test "color256() function with int":
      let colorVal = color256(200)
      check colorVal.kind == Indexed256
      check colorVal.indexed256 == 200

    test "color256() function bounds clamping":
      # Test that out of bounds values are clamped instead of throwing
      let colorVal1 = color256(-1)  # Should clamp to 0
      let colorVal2 = color256(256)  # Should clamp to 255
      check colorVal1.indexed256 == 0
      check colorVal2.indexed256 == 255

    test "hex color parsing":
      let colorVal1 = rgb("FF0080")
      let colorVal2 = rgb("#00FF80")

      check colorVal1.kind == Rgb
      check colorVal1.rgb.r == 255
      check colorVal1.rgb.g == 0
      check colorVal1.rgb.b == 128

      check colorVal2.kind == Rgb
      check colorVal2.rgb.r == 0
      check colorVal2.rgb.g == 255
      check colorVal2.rgb.b == 128

    test "hex color parsing error handling":
      # Test that invalid hex strings return black instead of throwing
      let colorVal1 = rgb("FF00")      # Too short -> should return black
      let colorVal2 = rgb("FF0080CC")  # Too long -> should return black
      let colorVal3 = rgb("INVALID")   # Invalid hex -> should return black
      
      check colorVal1.kind == Rgb
      check colorVal1.rgb == RgbColor(r: 0, g: 0, b: 0)
      check colorVal2.kind == Rgb
      check colorVal2.rgb == RgbColor(r: 0, g: 0, b: 0)
      check colorVal3.kind == Rgb
      check colorVal3.rgb == RgbColor(r: 0, g: 0, b: 0)

    test "defaultColor() function":
      let colorVal = defaultColor()
      check colorVal.kind == Default

  suite "StyleModifier Tests":
    test "StyleModifier enum values":
      check StyleModifier.Bold.ord == 0
      check StyleModifier.Dim.ord == 1
      check StyleModifier.Italic.ord == 2
      check StyleModifier.Underline.ord == 3
      check StyleModifier.SlowBlink.ord == 4
      check StyleModifier.RapidBlink.ord == 5
      check StyleModifier.Reversed.ord == 6
      check StyleModifier.Crossed.ord == 7
      check StyleModifier.Hidden.ord == 8

  suite "Style Tests":
    test "Style creation - default":
      let style = Style(fg: defaultColor(), bg: defaultColor(), modifiers: {})
      check style.fg.kind == Default
      check style.bg.kind == Default
      check style.modifiers.len == 0

    test "Style creation - with colors and modifiers":
      let style =
        Style(fg: color(Color.Red), bg: color(Color.Blue), modifiers: {Bold, Italic})
      check style.fg.kind == Indexed
      check style.fg.indexed == Color.Red
      check style.bg.kind == Indexed
      check style.bg.indexed == Color.Blue
      check Bold in style.modifiers
      check Italic in style.modifiers
      check style.modifiers.len == 2

    test "Style equality - same styles":
      let style1 =
        Style(fg: color(Color.Green), bg: defaultColor(), modifiers: {Underline})
      let style2 =
        Style(fg: color(Color.Green), bg: defaultColor(), modifiers: {Underline})
      check style1 == style2

    test "Style equality - different foreground":
      let style1 = Style(fg: color(Color.Red), bg: defaultColor(), modifiers: {})
      let style2 = Style(fg: color(Color.Blue), bg: defaultColor(), modifiers: {})
      check style1 != style2

    test "Style equality - different background":
      let style1 = Style(fg: defaultColor(), bg: color(Color.Red), modifiers: {})
      let style2 = Style(fg: defaultColor(), bg: color(Color.Blue), modifiers: {})
      check style1 != style2

    test "Style equality - different modifiers":
      let style1 = Style(fg: defaultColor(), bg: defaultColor(), modifiers: {Bold})
      let style2 = Style(fg: defaultColor(), bg: defaultColor(), modifiers: {Italic})
      check style1 != style2

  suite "Style Constructor Functions":
    test "style() function - no parameters":
      let s = style()
      check s.fg.kind == Default
      check s.bg.kind == Default
      check s.modifiers.len == 0

    test "style() function - with ColorValue parameters":
      let s =
        style(fg = color(Color.Red), bg = color(Color.Blue), modifiers = {Bold, Italic})
      check s.fg.indexed == Color.Red
      check s.bg.indexed == Color.Blue
      check Bold in s.modifiers
      check Italic in s.modifiers

    test "style() function - with Color parameters":
      let s = style(Color.Green, Color.Yellow, {Underline})
      check s.fg.indexed == Color.Green
      check s.bg.indexed == Color.Yellow
      check Underline in s.modifiers

    test "style() function - with Reset background":
      let s = style(Color.Red, Color.Reset)
      check s.fg.indexed == Color.Red
      check s.bg.kind == Default # Reset becomes default

  suite "Style Manipulation Functions":
    test "withFg() with ColorValue":
      let original = style(Color.Red, Color.Blue, {Bold})
      let modified = original.withFg(color(Color.Green))

      check modified.fg.indexed == Color.Green
      check modified.bg.indexed == Color.Blue
      check Bold in modified.modifiers

    test "withFg() with Color":
      let original = style(Color.Red, Color.Blue, {Bold})
      let modified = original.withFg(Color.Cyan)

      check modified.fg.indexed == Color.Cyan
      check modified.bg.indexed == Color.Blue
      check Bold in modified.modifiers

    test "withBg() with ColorValue":
      let original = style(Color.Red, Color.Blue, {Bold})
      let modified = original.withBg(color(Color.Magenta))

      check modified.fg.indexed == Color.Red
      check modified.bg.indexed == Color.Magenta
      check Bold in modified.modifiers

    test "withBg() with Color":
      let original = style(Color.Red, Color.Blue, {Bold})
      let modified = original.withBg(Color.White)

      check modified.fg.indexed == Color.Red
      check modified.bg.indexed == Color.White
      check Bold in modified.modifiers

    test "withModifiers()":
      let original = style(Color.Red, Color.Blue, {Bold})
      let modified = original.withModifiers({Italic, Underline})

      check modified.fg.indexed == Color.Red
      check modified.bg.indexed == Color.Blue
      check Italic in modified.modifiers
      check Underline in modified.modifiers
      check Bold notin modified.modifiers

    test "addModifier()":
      let original = style(Color.Red, Color.Blue, {Bold})
      let modified = original.addModifier(Italic)

      check modified.fg.indexed == Color.Red
      check modified.bg.indexed == Color.Blue
      check Bold in modified.modifiers
      check Italic in modified.modifiers

    test "removeModifier()":
      let original = style(Color.Red, Color.Blue, {Bold, Italic})
      let modified = original.removeModifier(Bold)

      check modified.fg.indexed == Color.Red
      check modified.bg.indexed == Color.Blue
      check Bold notin modified.modifiers
      check Italic in modified.modifiers

  suite "Predefined Style Functions":
    test "defaultStyle()":
      let s = defaultStyle()
      check s.fg.kind == Default
      check s.bg.kind == Default
      check s.modifiers.len == 0
    
    test "Style.default() override":
      # Verify that Style.default() returns the same as defaultStyle()
      # instead of Nim's auto-generated zero values
      let style1 = Style.default()
      let style2 = defaultStyle()
      check style1 == style2
      check style1.fg.kind == Default
      check style1.bg.kind == Default
      # Without our override, this would be Style(fg: Black, bg: Black)

    test "bold() with default color":
      let s = bold()
      check s.fg.kind == Indexed # Reset is treated as indexed color
      check s.fg.indexed == Color.Reset
      check s.bg.kind == Default
      check Bold in s.modifiers

    test "bold() with specific color":
      let s = bold(Color.Red)
      check s.fg.indexed == Color.Red
      check s.bg.kind == Default
      check Bold in s.modifiers

    test "italic() with default color":
      let s = italic()
      check s.fg.kind == Indexed # Reset is treated as indexed color
      check s.fg.indexed == Color.Reset
      check s.bg.kind == Default
      check Italic in s.modifiers

    test "italic() with specific color":
      let s = italic(Color.Green)
      check s.fg.indexed == Color.Green
      check s.bg.kind == Default
      check Italic in s.modifiers

    test "underline() with default color":
      let s = underline()
      check s.fg.kind == Indexed # Reset is treated as indexed color
      check s.fg.indexed == Color.Reset
      check s.bg.kind == Default
      check Underline in s.modifiers

    test "underline() with specific color":
      let s = underline(Color.Blue)
      check s.fg.indexed == Color.Blue
      check s.bg.kind == Default
      check Underline in s.modifiers

    test "reversed()":
      let s = reversed()
      check s.fg.kind == Default
      check s.bg.kind == Default
      check Reversed in s.modifiers

  suite "ANSI Code Generation":
    test "toAnsiCode() for basic colors":
      check Color.Black.toAnsiCode() == "30"
      check Color.Red.toAnsiCode() == "31"
      check Color.Green.toAnsiCode() == "32"
      check Color.Yellow.toAnsiCode() == "33"
      check Color.Blue.toAnsiCode() == "34"
      check Color.Magenta.toAnsiCode() == "35"
      check Color.Cyan.toAnsiCode() == "36"
      check Color.White.toAnsiCode() == "37"

    test "toAnsiCode() for bright colors":
      check Color.BrightBlack.toAnsiCode() == "90"
      check Color.BrightRed.toAnsiCode() == "91"
      check Color.BrightGreen.toAnsiCode() == "92"
      check Color.BrightYellow.toAnsiCode() == "93"
      check Color.BrightBlue.toAnsiCode() == "94"
      check Color.BrightMagenta.toAnsiCode() == "95"
      check Color.BrightCyan.toAnsiCode() == "96"
      check Color.BrightWhite.toAnsiCode() == "97"

    test "toAnsiCode() for reset":
      check Color.Reset.toAnsiCode() == "39"

    test "toBgAnsiCode() for basic colors":
      check Color.Black.toBgAnsiCode() == "40"
      check Color.Red.toBgAnsiCode() == "41"
      check Color.Green.toBgAnsiCode() == "42"
      check Color.Yellow.toBgAnsiCode() == "43"
      check Color.Blue.toBgAnsiCode() == "44"
      check Color.Magenta.toBgAnsiCode() == "45"
      check Color.Cyan.toBgAnsiCode() == "46"
      check Color.White.toBgAnsiCode() == "47"

    test "toBgAnsiCode() for bright colors":
      check Color.BrightBlack.toBgAnsiCode() == "100"
      check Color.BrightRed.toBgAnsiCode() == "101"
      check Color.BrightGreen.toBgAnsiCode() == "102"
      check Color.BrightYellow.toBgAnsiCode() == "103"
      check Color.BrightBlue.toBgAnsiCode() == "104"
      check Color.BrightMagenta.toBgAnsiCode() == "105"
      check Color.BrightCyan.toBgAnsiCode() == "106"
      check Color.BrightWhite.toBgAnsiCode() == "107"

    test "toBgAnsiCode() for reset":
      check Color.Reset.toBgAnsiCode() == "49"

    test "RgbColor toAnsiCode() - foreground":
      let rgb = RgbColor(r: 255, g: 128, b: 64)
      check rgb.toAnsiCode(false) == "38;2;255;128;64"

    test "RgbColor toAnsiCode() - background":
      let rgb = RgbColor(r: 100, g: 200, b: 50)
      check rgb.toAnsiCode(true) == "48;2;100;200;50"

    test "ColorValue toAnsiCode() - indexed foreground":
      let colorVal = color(Color.Red)
      check colorVal.toAnsiCode(false) == "31"

    test "ColorValue toAnsiCode() - indexed background":
      let colorVal = color(Color.Blue)
      check colorVal.toAnsiCode(true) == "44"

    test "ColorValue toAnsiCode() - RGB foreground":
      let colorVal = rgb(255, 0, 128)
      check colorVal.toAnsiCode(false) == "38;2;255;0;128"

    test "ColorValue toAnsiCode() - RGB background":
      let colorVal = rgb(64, 128, 255)
      check colorVal.toAnsiCode(true) == "48;2;64;128;255"

    test "ColorValue toAnsiCode() - default foreground":
      let colorVal = defaultColor()
      check colorVal.toAnsiCode(false) == "39"

    test "ColorValue toAnsiCode() - default background":
      let colorVal = defaultColor()
      check colorVal.toAnsiCode(true) == "49"

    test "ColorValue toAnsiCode() - 256-color foreground":
      let colorVal = color256(128)
      check colorVal.toAnsiCode(false) == "38;5;128"

    test "ColorValue toAnsiCode() - 256-color background":
      let colorVal = color256(200)
      check colorVal.toAnsiCode(true) == "48;5;200"

    test "StyleModifier toAnsiCode()":
      check Bold.toAnsiCode() == "1"
      check Dim.toAnsiCode() == "2"
      check Italic.toAnsiCode() == "3"
      check Underline.toAnsiCode() == "4"
      check SlowBlink.toAnsiCode() == "5"
      check RapidBlink.toAnsiCode() == "6"
      check Reversed.toAnsiCode() == "7"
      check Hidden.toAnsiCode() == "8"
      check Crossed.toAnsiCode() == "9"

    test "Style toAnsiSequence() - default style":
      let s = defaultStyle()
      check s.toAnsiSequence() == ""

    test "Style toAnsiSequence() - foreground only":
      let s = style(Color.Red)
      check s.toAnsiSequence() == "\e[31;49m"

    test "Style toAnsiSequence() - background only":
      let s = style(bg = color(Color.Blue))
      check s.toAnsiSequence() == "\e[44m"

    test "Style toAnsiSequence() - modifiers only":
      let s = style(modifiers = {Bold, Italic})
      let seq = s.toAnsiSequence()
      check seq.contains("1") # Bold
      check seq.contains("3") # Italic
      check seq.startsWith("\e[")
      check seq.endsWith("m")

    test "Style toAnsiSequence() - complete style":
      let s = style(Color.Green, Color.Yellow, {Bold, Underline})
      let seq = s.toAnsiSequence()
      check seq.contains("32") # Green foreground
      check seq.contains("43") # Yellow background
      check seq.contains("1") # Bold
      check seq.contains("4") # Underline
      check seq.startsWith("\e[")
      check seq.endsWith("m")

    test "resetSequence()":
      check resetSequence() == "\e[0m"

  suite "Style String Representation":
    test "Style string representation - default":
      let s = defaultStyle()
      check $s == "Style(default)"

    test "Style string representation - foreground only":
      let s = style(Color.Red)
      let str = $s
      check str.contains("fg: Red")
      check not str.contains("bg:")
      check not str.contains("modifiers:")

    test "Style string representation - background only":
      let s = style(bg = color(Color.Blue))
      let str = $s
      check str.contains("bg: Blue")
      check not str.contains("fg:")
      check not str.contains("modifiers:")

    test "Style string representation - modifiers only":
      let s = style(modifiers = {Bold, Italic})
      let str = $s
      check str.contains("modifiers:")
      check str.contains("Bold")
      check str.contains("Italic")
      check not str.contains("fg:")
      check not str.contains("bg:")

    test "Style string representation - complete":
      let s = style(Color.Green, Color.Yellow, {Underline})
      let str = $s
      check str.contains("fg: Green")
      check str.contains("bg: Yellow")
      check str.contains("modifiers:")
      check str.contains("Underline")

  suite "256-Color Palette Functions":
    test "grayscale() function - valid range":
      let gray0 = grayscale(0)
      let gray23 = grayscale(23)

      check gray0.kind == Indexed256
      check gray0.indexed256 == 232 # 232 + 0
      check gray23.kind == Indexed256
      check gray23.indexed256 == 255 # 232 + 23

    test "grayscale() function - boundary values clamping":
      # Test that out of bounds values are clamped instead of throwing
      let gray_neg = grayscale(-1)   # Should clamp to 0
      let gray_high = grayscale(24)  # Should clamp to 23
      check gray_neg.indexed256 == 232  # 232 + 0
      check gray_high.indexed256 == 255  # 232 + 23

    test "cubeColor() function - valid range":
      let cube000 = cubeColor(0, 0, 0)
      let cube555 = cubeColor(5, 5, 5)
      let cube123 = cubeColor(1, 2, 3)

      check cube000.kind == Indexed256
      check cube000.indexed256 == 16 # 16 + 36*0 + 6*0 + 0
      check cube555.kind == Indexed256
      check cube555.indexed256 == 231 # 16 + 36*5 + 6*5 + 5
      check cube123.kind == Indexed256
      check cube123.indexed256 == 67 # 16 + 36*1 + 6*2 + 3

    test "cubeColor() function - boundary values clamping":
      # Test that out of bounds values are clamped instead of throwing
      let cube_neg_r = cubeColor(-1, 0, 0)  # Should clamp r to 0
      let cube_neg_g = cubeColor(0, -1, 0)  # Should clamp g to 0  
      let cube_neg_b = cubeColor(0, 0, -1)  # Should clamp b to 0
      let cube_high_r = cubeColor(6, 0, 0)  # Should clamp r to 5
      let cube_high_g = cubeColor(0, 6, 0)  # Should clamp g to 5
      let cube_high_b = cubeColor(0, 0, 6)  # Should clamp b to 5
      
      check cube_neg_r.indexed256 == 16     # 16 + 36*0 + 6*0 + 0
      check cube_neg_g.indexed256 == 16     # 16 + 36*0 + 6*0 + 0
      check cube_neg_b.indexed256 == 16     # 16 + 36*0 + 6*0 + 0
      check cube_high_r.indexed256 == 196   # 16 + 36*5 + 6*0 + 0
      check cube_high_g.indexed256 == 46    # 16 + 36*0 + 6*5 + 0
      check cube_high_b.indexed256 == 21    # 16 + 36*0 + 6*0 + 5

    test "brightColors() function":
      let colors = brightColors()
      check colors.len == 6
      for i, color in colors:
        check color.kind == Indexed256
        check color.indexed256 == uint8(9 + i)

    test "darkColors() function":
      let colors = darkColors()
      check colors.len == 6
      for i, color in colors:
        check color.kind == Indexed256
        check color.indexed256 == uint8(1 + i)

    test "pastels() function":
      let colors = pastels()
      let expectedIndices = [217u8, 223u8, 229u8, 195u8, 159u8, 183u8]
      check colors.len == 6
      for i, color in colors:
        check color.kind == Indexed256
        check color.indexed256 == expectedIndices[i]

  suite "HSV Color Support":
    test "hsvToRgb() function - primary colors":
      let red = hsvToRgb(0.0, 1.0, 1.0)
      let green = hsvToRgb(120.0, 1.0, 1.0)
      let blue = hsvToRgb(240.0, 1.0, 1.0)

      check red.r == 255 and red.g == 0 and red.b == 0
      check green.r == 0 and green.g == 255 and green.b == 0
      check blue.r == 0 and blue.g == 0 and blue.b == 255

    test "hsvToRgb() function - grayscale":
      let black = hsvToRgb(0.0, 0.0, 0.0)
      let white = hsvToRgb(0.0, 0.0, 1.0)
      let gray = hsvToRgb(0.0, 0.0, 0.5)

      check black.r == 0 and black.g == 0 and black.b == 0
      check white.r == 255 and white.g == 255 and white.b == 255
      check gray.r == 127 and gray.g == 127 and gray.b == 127

    test "hsv() function":
      let colorVal = hsv(60.0, 1.0, 1.0) # Yellow
      check colorVal.kind == Rgb
      check colorVal.rgb.r == 255
      check colorVal.rgb.g == 255
      check colorVal.rgb.b == 0

  suite "Color Interpolation":
    test "lerp() RgbColor - midpoint":
      let red = RgbColor(r: 255, g: 0, b: 0)
      let blue = RgbColor(r: 0, g: 0, b: 255)
      let mid = lerp(red, blue, 0.5)

      check mid.r == 127
      check mid.g == 0
      check mid.b == 127

    test "lerp() RgbColor - endpoints":
      let red = RgbColor(r: 255, g: 0, b: 0)
      let blue = RgbColor(r: 0, g: 0, b: 255)
      let start = lerp(red, blue, 0.0)
      let finish = lerp(red, blue, 1.0)

      check start == red
      check finish == blue

    test "lerp() RgbColor - clamping":
      let red = RgbColor(r: 255, g: 0, b: 0)
      let blue = RgbColor(r: 0, g: 0, b: 255)
      let before = lerp(red, blue, -0.5)
      let after = lerp(red, blue, 1.5)

      check before == red
      check after == blue

    test "lerp() ColorValue - RGB colors":
      let redVal = rgb(255, 0, 0)
      let blueVal = rgb(0, 0, 255)
      let midVal = lerp(redVal, blueVal, 0.5)

      check midVal.kind == Rgb
      check midVal.rgb.r == 127
      check midVal.rgb.g == 0
      check midVal.rgb.b == 127

    test "lerp() ColorValue - non-RGB fallback":
      let indexed = color(Color.Red)
      let color256Val = color256(100)
      let result = lerp(indexed, color256Val, 0.5)

      check result == indexed # Falls back to first color

  suite "Predefined Colors":
    test "predefined RGB colors":
      let hotPinkVal = hotPink()
      let deepSkyBlueVal = deepSkyBlue()
      let limeGreenVal = limeGreen()

      check hotPinkVal.kind == Rgb
      check hotPinkVal.rgb == RgbColor(r: 255, g: 105, b: 180)

      check deepSkyBlueVal.kind == Rgb
      check deepSkyBlueVal.rgb == RgbColor(r: 0, g: 191, b: 255)

      check limeGreenVal.kind == Rgb
      check limeGreenVal.rgb == RgbColor(r: 50, g: 205, b: 50)

    test "more predefined RGB colors":
      check orange().rgb == RgbColor(r: 255, g: 165, b: 0)
      check violet().rgb == RgbColor(r: 238, g: 130, b: 238)
      check gold().rgb == RgbColor(r: 255, g: 215, b: 0)
      check crimson().rgb == RgbColor(r: 220, g: 20, b: 60)
      check teal().rgb == RgbColor(r: 0, g: 128, b: 128)
      check indigo().rgb == RgbColor(r: 75, g: 0, b: 130)
      check salmon().rgb == RgbColor(r: 250, g: 128, b: 114)
