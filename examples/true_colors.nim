## True Color (24-bit RGB) Example
##
## This example demonstrates Celina's true color support with 24-bit RGB colors.
## It showcases various color formats, gradients, HSV colors, and color interpolation.

import std/[strformat, math]
import ../src/celina

proc main() =
  quickRun(
    eventHandler = proc(event: Event): bool =
      case event.kind
      of EventKind.Key:
        if event.key.code == KeyCode.Char and event.key.char == 'q':
          return false
        elif event.key.code == KeyCode.Escape:
          return false
      else:
        discard
      return true,
    renderHandler = proc(buffer: var Buffer) =
      buffer.clear()

      let area = buffer.area
      var currentY = 1

      # Title
      let title = "True Color (24-bit RGB) Showcase"
      buffer.setString(
        area.width div 2 - title.len div 2,
        currentY,
        title,
        style(rgb("#FF6B35"), modifiers = {Bold, Underline}),
      )
      currentY += 3

      # RGB Colors Section
      buffer.setString(
        2, currentY, "RGB Colors:", style(rgb(255, 255, 255), modifiers = {Bold})
      )
      currentY += 1

      # Different RGB constructor formats
      let rgbExamples = [
        ("rgb(255, 0, 0)", rgb(255, 0, 0)),
        ("rgb(0, 255, 0)", rgb(0, 255, 0)),
        ("rgb(0, 0, 255)", rgb(0, 0, 255)),
        ("rgb(\"#FF00FF\")", rgb("#FF00FF")),
        ("rgb(\"00FFFF\")", rgb("00FFFF")),
        ("rgb(\"#FFD700\")", rgb("#FFD700")),
      ]

      for i, (label, color) in rgbExamples:
        let x = 4 + (i mod 3) * 20
        let y = currentY + (i div 3)
        buffer.setString(x, y, label, style(color, modifiers = {Bold}))

      currentY += 3

      # Predefined True Colors
      buffer.setString(
        2,
        currentY,
        "Predefined True Colors:",
        style(rgb(255, 255, 255), modifiers = {Bold}),
      )
      currentY += 1

      let predefColors = [
        ("hotPink", hotPink()),
        ("deepSkyBlue", deepSkyBlue()),
        ("limeGreen", limeGreen()),
        ("orange", orange()),
        ("violet", violet()),
        ("gold", gold()),
        ("crimson", crimson()),
        ("teal", teal()),
        ("indigo", indigo()),
        ("salmon", salmon()),
      ]

      for i, (name, color) in predefColors:
        let x = 4 + (i mod 5) * 14
        let y = currentY + (i div 5)
        buffer.setString(x, y, name, style(color, modifiers = {Bold}))

      currentY += 3

      # HSV Colors
      buffer.setString(
        2,
        currentY,
        "HSV Colors (Hue, Saturation, Value):",
        style(rgb(255, 255, 255), modifiers = {Bold}),
      )
      currentY += 1

      # Rainbow using HSV
      let rainbowText = "HSV Rainbow!"
      let startX = 4
      for i, ch in rainbowText:
        let hue = (i * 360) div rainbowText.len
        let color = hsv(hue.float, 1.0, 1.0)
        buffer.setString(
          startX + i * 2, currentY, $ch, style(color, modifiers = {Bold})
        )

      currentY += 2

      # Saturation gradient
      buffer.setString(4, currentY, "Saturation gradient:", style(rgb(200, 200, 200)))
      currentY += 1
      for i in 0 ..< 20:
        let saturation = i.float / 19.0
        let color = hsv(240.0, saturation, 1.0) # Blue hue
        buffer.setString(4 + i, currentY, "█", style(color))

      currentY += 2

      # Value (brightness) gradient
      buffer.setString(4, currentY, "Brightness gradient:", style(rgb(200, 200, 200)))
      currentY += 1
      for i in 0 ..< 20:
        let brightness = i.float / 19.0
        let color = hsv(120.0, 1.0, brightness) # Green hue
        buffer.setString(4 + i, currentY, "█", style(color))

      currentY += 3

      # Color Interpolation
      buffer.setString(
        2,
        currentY,
        "Color Interpolation (lerp):",
        style(rgb(255, 255, 255), modifiers = {Bold}),
      )
      currentY += 1

      # Red to Blue gradient
      let redColor = rgb(255, 0, 0).rgb
      let blueColor = rgb(0, 0, 255).rgb
      buffer.setString(4, currentY, "Red → Blue:", style(rgb(200, 200, 200)))
      currentY += 1
      for i in 0 ..< 30:
        let t = i.float / 29.0
        let interpolated = lerp(redColor, blueColor, t)
        let color = ColorValue(kind: Rgb, rgb: interpolated)
        buffer.setString(4 + i, currentY, "█", style(color))

      currentY += 2

      # Green to Yellow gradient
      let greenColor = rgb(0, 255, 0).rgb
      let yellowColor = rgb(255, 255, 0).rgb
      buffer.setString(4, currentY, "Green → Yellow:", style(rgb(200, 200, 200)))
      currentY += 1
      for i in 0 ..< 30:
        let t = i.float / 29.0
        let interpolated = lerp(greenColor, yellowColor, t)
        let color = ColorValue(kind: Rgb, rgb: interpolated)
        buffer.setString(4 + i, currentY, "█", style(color))

      currentY += 3

      # Background Colors
      buffer.setString(
        2, currentY, "Background Colors:", style(rgb(255, 255, 255), modifiers = {Bold})
      )
      currentY += 1

      let bgExamples = [
        ("Red BG", rgb(255, 255, 255), rgb(255, 0, 0)),
        ("Blue BG", rgb(255, 255, 255), rgb(0, 0, 255)),
        ("Green BG", rgb(0, 0, 0), rgb(0, 255, 0)),
        ("Purple BG", rgb(255, 255, 255), rgb(128, 0, 128)),
      ]

      for i, (text, fg, bg) in bgExamples:
        let x = 4 + i * 12
        buffer.setString(x, currentY, text, style(fg, bg, modifiers = {Bold}))

      currentY += 3

      # Technical information
      buffer.setString(
        2, currentY, "Technical Info:", style(rgb(255, 255, 0), modifiers = {Bold})
      )
      currentY += 1

      let techInfo = [
        "• 24-bit RGB: 16,777,216 colors", "• ANSI escape: \\e[38;2;r;g;b m",
        "• Hex format: #RRGGBB or RRGGBB", "• HSV support for color generation",
        "• Color interpolation (lerp) for gradients",
      ]

      for info in techInfo:
        buffer.setString(4, currentY, info, style(rgb(180, 180, 180)))
        currentY += 1

      # Instructions
      let instruction = "Press 'q' or ESC to quit"
      buffer.setString(
        area.width div 2 - instruction.len div 2,
        area.height - 2,
        instruction,
        style(rgb(128, 128, 128)),
      ),
  )

when isMainModule:
  echo "Starting True Color example..."
  echo "This demonstrates 24-bit RGB color support"
  echo "Your terminal must support true color (most modern terminals do)"
  main()
