## True Color demonstration
## Shows various 24-bit RGB color capabilities including gradients, palettes, and animations

import std/[math, times]

import pkg/celina

proc drawGradientBar(
    buf: var Buffer, x, y, width: int, startColor, endColor: RgbColor, label: string
) =
  # Draw gradient label
  buf.setString(x, y, label, Style(fg: color(White)))

  # Draw gradient bar
  for i in 0 ..< width:
    let t = i.float / (width - 1).float
    let gradColor = lerp(startColor, endColor, t)
    buf.setString(
      x + i, y + 1, " ", Style(bg: rgb(gradColor.r, gradColor.g, gradColor.b))
    )

proc drawColorPalette(buf: var Buffer, x, y: int) =
  # Draw predefined true colors
  let colors = @[
    ("Hot Pink", hotPink()),
    ("Deep Sky Blue", deepSkyBlue()),
    ("Lime Green", limeGreen()),
    ("Orange", orange()),
    ("Violet", violet()),
    ("Gold", gold()),
    ("Crimson", crimson()),
    ("Teal", teal()),
    ("Indigo", indigo()),
    ("Salmon", salmon()),
  ]

  buf.setString(
    x, y, "Predefined True Colors:", Style(fg: color(White), modifiers: {Bold})
  )

  for i, (name, col) in colors:
    let row = y + 2 + i
    buf.setString(x, row, "    ", Style(bg: col))
    buf.setString(x + 5, row, name, Style(fg: color(BrightWhite)))

proc drawHexColors(buf: var Buffer, x, y: int) =
  # Demonstrate hex color parsing
  buf.setString(x, y, "Hex Colors:", Style(fg: color(White), modifiers: {Bold}))

  let hexColors = @[
    ("#FF6B6B", "Coral"),
    ("#4ECDC4", "Turquoise"),
    ("#45B7D1", "Sky"),
    ("#96CEB4", "Sage"),
    ("#FFEAA7", "Butter"),
    ("#DDA0DD", "Plum"),
  ]

  for i, (hex, name) in hexColors:
    let row = y + 2 + i
    let col = rgb(hex)
    buf.setString(x, row, "    ", Style(bg: col))
    buf.setString(x + 5, row, hex & " " & name, Style(fg: color(BrightWhite)))

proc drawRainbowText(buf: var Buffer, x, y: int, text: string, offset: float) =
  # Draw text with rainbow colors
  # This draws the entire string at once with a single color
  let hue = offset.mod(360.0)
  let color = hsv(hue, 1.0, 1.0)
  buf.setString(x, y, text, Style(fg: color, modifiers: {Bold}))

proc draw16ColorPalette(buf: var Buffer, x, y: int) =
  # Show standard 16-color palette
  buf.setString(x, y, "Standard 16 Colors:", Style(fg: color(White), modifiers: {Bold}))

  # First row - normal colors
  let normalColors = @[
    (Black, "Black"),
    (Red, "Red"),
    (Green, "Green"),
    (Yellow, "Yellow"),
    (Blue, "Blue"),
    (Magenta, "Magenta"),
    (Cyan, "Cyan"),
    (White, "White"),
  ]

  for i, (col, name) in normalColors:
    buf.setString(x + i * 20, y + 2, "   ", Style(bg: color(col)))
    buf.setString(x + i * 20, y + 3, name, Style(fg: color(BrightWhite)))

  # Second row - bright colors
  let brightColors = @[
    (BrightBlack, "Gray"),
    (BrightRed, "Bright Red"),
    (BrightGreen, "Bright Green"),
    (BrightYellow, "Bright Yellow"),
    (BrightBlue, "Bright Blue"),
    (BrightMagenta, "Bright Magenta"),
    (BrightCyan, "Bright Cyan"),
    (BrightWhite, "Bright White"),
  ]

  for i, (col, name) in brightColors:
    buf.setString(x + i * 20, y + 5, "   ", Style(bg: color(col)))
    buf.setString(x + i * 20, y + 6, name, Style(fg: color(BrightWhite)))

proc draw256ColorComparison(buf: var Buffer, x, y: int) =
  # Show 256-color palette vs true color
  buf.setString(
    x, y, "256-Color vs True Color:", Style(fg: color(White), modifiers: {Bold})
  )

  # Draw 256-color grayscale
  buf.setString(x, y + 2, "256-color grayscale:", Style(fg: color(BrightWhite)))
  for i in 0 .. 23:
    let gray = grayscale(i)
    buf.setString(x + 20 + i, y + 2, " ", Style(bg: gray))

  # Draw true color grayscale
  buf.setString(x, y + 3, "True color grayscale:", Style(fg: color(BrightWhite)))
  let width = min(buf.area.width - x - 20, 128) # Use up to 128 steps or available width
  for i in 0 ..< width:
    let value = (i.float / (width - 1).float * 255.0).uint8
    let gray = rgb(value, value, value)
    buf.setString(x + 20 + i, y + 3, " ", Style(bg: gray))

proc drawAnimatedGradientWave(buf: var Buffer, y: int, offset: float) =
  for x in 0 ..< buf.area.width:
    let phase = (x.float * 0.1 + offset * 0.05).mod(2.0 * PI)
    let intensity = (sin(phase) + 1.0) * 0.5
    let r = (intensity * 100.0 + 155.0).uint8
    let g = (intensity * 150.0 + 105.0).uint8
    let b = (255.0 - intensity * 100.0).uint8
    buf.setString(x, y, "▀", Style(fg: rgb(r, g, b)))
    buf.setString(x, y + 1, "▄", Style(fg: rgb(r, g, b)))

proc drawHints(buf: var Buffer, y: int) =
  let hint = "Press 'q' to quit | True color (24-bit RGB) terminal required"
  let hintX = (buf.area.width - hint.len) div 2
  buf.setString(hintX, y, hint, Style(fg: rgb(150, 150, 150)))

proc main() =
  var app = newApp()

  var animOffset = 0.0
  let startTime = epochTime()

  app.onRender(
    proc(buf: var Buffer) =
      let currentTime = epochTime() - startTime
      animOffset = currentTime * 50.0 # Animation speed

      # Clear buffer with terminal default background
      for y in 0 ..< buf.area.height:
        for x in 0 ..< buf.area.width:
          buf.setString(x, y, " ", defaultStyle())

      # Title with animated rainbow effect
      let title = "✨ Celina True Color Demo ✨"
      let titleX = (buf.area.width - title.len) div 2
      drawRainbowText(buf, titleX, 1, title, animOffset)

      # Gradient bars
      let gradientX = 2
      var gradientY = 3

      drawGradientBar(
        buf,
        gradientX,
        gradientY,
        40,
        RgbColor(r: 255, g: 0, b: 0),
        RgbColor(r: 0, g: 0, b: 255),
        "Red to Blue Gradient:",
      )

      gradientY += 3
      drawGradientBar(
        buf,
        gradientX,
        gradientY,
        40,
        RgbColor(r: 255, g: 255, b: 0),
        RgbColor(r: 255, g: 0, b: 255),
        "Yellow to Magenta Gradient:",
      )

      gradientY += 3
      drawGradientBar(
        buf,
        gradientX,
        gradientY,
        40,
        RgbColor(r: 0, g: 255, b: 255),
        RgbColor(r: 0, g: 255, b: 0),
        "Cyan to Green Gradient:",
      )

      # Predefined colors palette
      drawColorPalette(buf, 2, gradientY + 4)

      # Hex colors demonstration
      drawHexColors(buf, 45, gradientY + 4)

      # 16-color palette
      draw16ColorPalette(buf, 2, buf.area.height - 18)

      # 256 vs True color comparison
      draw256ColorComparison(buf, 2, buf.area.height - 9)

      # Animated gradient wave at the bottom
      drawAnimatedGradientWave(buf, buf.area.height - 4, animOffset)

      # Usage hint
      drawHints(buf, buf.area.height - 1)
  )

  app.onEvent(
    proc(event: Event): bool =
      if event.kind == EventKind.Key:
        if event.key.code == KeyCode.Char and event.key.char == "q":
          return false
      return true
  )

  app.run()

when isMainModule:
  main()
