## Complete Color Showcase Example
##
## This example demonstrates all color capabilities available in Celina:
## - Basic 16 colors and bright colors
## - Style modifiers (bold, italic, underline, etc.)
## - RGB/True color support
## - 256-color palette with grayscale and RGB cube
## - Color palette shortcuts (bright, dark, pastels)

import ../src/celina
import std/[strformat, math]

type ColorDemoApp = object
  scroll: int
  mode: int # 0 = basic colors, 1 = 256-color palette, 2 = RGB/effects

proc main() =
  var appState = ColorDemoApp(scroll: 0, mode: 0)

  quickRun(
    eventHandler = proc(event: Event): bool =
      case event.kind
      of EventKind.Key:
        case event.key.code
        of KeyCode.Char:
          case event.key.char
          of 'q':
            return false
          of '1':
            appState.mode = 0
            appState.scroll = 0
          of '2':
            appState.mode = 1
            appState.scroll = 0
          of '3':
            appState.mode = 2
            appState.scroll = 0
          else:
            discard
        of KeyCode.Escape:
          return false
        of KeyCode.ArrowUp:
          if appState.scroll > 0:
            dec appState.scroll
        of KeyCode.ArrowDown:
          inc appState.scroll
        else:
          discard
      else:
        discard
      return true,
    renderHandler = proc(buffer: var Buffer) =
      buffer.clear()

      let area = buffer.area
      var y = 1 - appState.scroll

      case appState.mode
      of 0:
        # Basic Colors Mode
        # Title
        if y >= 0 and y < area.height:
          let title = "Celina Basic Color Showcase"
          buffer.setString(
            area.width div 2 - title.len div 2,
            y,
            title,
            style(Color.White, modifiers = {Bold, Underline}),
          )
        inc y, 2

        # Basic colors section
        if y >= 0 and y < area.height:
          buffer.setString(
            2, y, "Basic Colors:", style(Color.Yellow, modifiers = {Bold})
          )
        inc y

        let basicColors = [
          (Color.Black, "Black"),
          (Color.Red, "Red"),
          (Color.Green, "Green"),
          (Color.Yellow, "Yellow"),
          (Color.Blue, "Blue"),
          (Color.Magenta, "Magenta"),
          (Color.Cyan, "Cyan"),
          (Color.White, "White"),
        ]

        for i, (color, name) in basicColors:
          let row = y + (i div 4)
          if row >= 0 and row < area.height:
            let x = 4 + (i mod 4) * 12
            buffer.setString(x, row, name, style(color, modifiers = {Bold}))

        inc y, 3

        # Bright colors section
        if y >= 0 and y < area.height:
          buffer.setString(
            2, y, "Bright Colors:", style(Color.Yellow, modifiers = {Bold})
          )
        inc y

        let brightColors = [
          (Color.BrightBlack, "BrightBlack"),
          (Color.BrightRed, "BrightRed"),
          (Color.BrightGreen, "BrightGreen"),
          (Color.BrightYellow, "BrightYellow"),
          (Color.BrightBlue, "BrightBlue"),
          (Color.BrightMagenta, "BrightMagenta"),
          (Color.BrightCyan, "BrightCyan"),
          (Color.BrightWhite, "BrightWhite"),
        ]

        for i, (color, name) in brightColors:
          let row = y + (i div 4)
          if row >= 0 and row < area.height:
            let x = 4 + (i mod 4) * 16
            buffer.setString(x, row, name, style(color, modifiers = {Bold}))

        inc y, 3

        # Background colors section
        if y >= 0 and y < area.height:
          buffer.setString(
            2, y, "Background Colors:", style(Color.Yellow, modifiers = {Bold})
          )
        inc y

        let bgColors = [
          (Color.Red, "Red BG"),
          (Color.Green, "Green BG"),
          (Color.Blue, "Blue BG"),
          (Color.Magenta, "Magenta BG"),
        ]

        if y >= 0 and y < area.height:
          for i, (bgColor, name) in bgColors:
            let x = 4 + i * 12
            buffer.setString(
              x, y, name, style(Color.White, bgColor, modifiers = {Bold})
            )

        inc y, 3

        # Style modifiers section
        if y >= 0 and y < area.height:
          buffer.setString(
            2, y, "Style Modifiers:", style(Color.Yellow, modifiers = {Bold})
          )
        inc y

        let styles = [
          ({Bold}, "Bold Text"),
          ({Dim}, "Dim Text"),
          ({Italic}, "Italic Text"),
          ({Underline}, "Underlined Text"),
          ({Reversed}, "Reversed Text"),
          ({Bold, Italic}, "Bold + Italic"),
          ({Bold, Underline}, "Bold + Underlined"),
        ]

        for i, (modifiers, text) in styles:
          let row = y + (i div 2)
          if row >= 0 and row < area.height:
            let x = 4 + (i mod 2) * 20
            buffer.setString(x, row, text, style(Color.Cyan, modifiers = modifiers))
      of 1:
        # 256-Color Palette Mode
        # Title
        if y >= 0 and y < area.height:
          let title = "256-Color Palette Demo"
          buffer.setString(
            area.width div 2 - title.len div 2,
            y,
            title,
            style(color256(226), modifiers = {Bold, Underline}),
          )
        inc y, 2

        # Basic 16 colors
        if y >= 0 and y < area.height:
          buffer.setString(
            2, y, "Basic 16 Colors:", style(Color.White, modifiers = {Bold})
          )
        inc y

        if y >= 0 and y < area.height:
          for i in 0 .. 15:
            let x = 2 + i * 3
            if x + 2 < area.width:
              buffer.setString(x, y, "███", style(color256(i)))
        inc y, 2

        # Grayscale
        if y >= 0 and y < area.height:
          buffer.setString(
            2, y, "Grayscale (24 levels):", style(Color.White, modifiers = {Bold})
          )
        inc y

        if y >= 0 and y < area.height:
          for i in 0 .. 23:
            let x = 2 + i * 2
            if x + 1 < area.width:
              buffer.setString(x, y, "██", style(grayscale(i)))
        inc y, 2

        # RGB Cube samples
        if y >= 0 and y < area.height:
          buffer.setString(
            2, y, "RGB Cube Colors (6x6x6):", style(Color.White, modifiers = {Bold})
          )
        inc y

        # Show a few rows of the RGB cube
        for r in 0 .. 2:
          if y >= 0 and y < area.height:
            for g in 0 .. 5:
              for b in 0 .. 5:
                let x = 2 + (g * 6 + b) * 2
                if x + 1 < area.width:
                  buffer.setString(x, y, "██", style(cubeColor(r, g, b)))
          inc y
        inc y

        # Palette shortcuts
        if y >= 0 and y < area.height:
          buffer.setString(
            2, y, "Bright Colors:", style(Color.White, modifiers = {Bold})
          )
        inc y

        if y >= 0 and y < area.height:
          let brightCols = brightColors()
          for i, color in brightCols:
            let x = 2 + i * 5
            if x + 4 < area.width:
              buffer.setString(x, y, "████", style(color))
        inc y, 2

        if y >= 0 and y < area.height:
          buffer.setString(2, y, "Dark Colors:", style(Color.White, modifiers = {Bold}))
        inc y

        if y >= 0 and y < area.height:
          let darkCols = darkColors()
          for i, color in darkCols:
            let x = 2 + i * 5
            if x + 4 < area.width:
              buffer.setString(x, y, "████", style(color))
        inc y, 2

        if y >= 0 and y < area.height:
          buffer.setString(
            2, y, "Pastel Colors:", style(Color.White, modifiers = {Bold})
          )
        inc y

        if y >= 0 and y < area.height:
          let pastelCols = pastels()
          for i, color in pastelCols:
            let x = 2 + i * 5
            if x + 4 < area.width:
              buffer.setString(x, y, "████", style(color))
      of 2:
        # RGB/True Color and Effects Mode
        # Title
        if y >= 0 and y < area.height:
          let title = "RGB Colors & Effects"
          buffer.setString(
            area.width div 2 - title.len div 2,
            y,
            title,
            style(rgb(255, 100, 200), modifiers = {Bold, Underline}),
          )
        inc y, 2

        # Predefined RGB colors
        if y >= 0 and y < area.height:
          buffer.setString(
            2, y, "Predefined RGB Colors:", style(Color.Yellow, modifiers = {Bold})
          )
        inc y

        let predefinedColors = [
          (hotPink(), "Hot Pink"),
          (deepSkyBlue(), "Deep Sky Blue"),
          (limeGreen(), "Lime Green"),
          (orange(), "Orange"),
          (violet(), "Violet"),
          (gold(), "Gold"),
          (crimson(), "Crimson"),
          (teal(), "Teal"),
          (indigo(), "Indigo"),
          (salmon(), "Salmon"),
        ]

        for i, (color, name) in predefinedColors:
          let row = y + (i div 2)
          if row >= 0 and row < area.height:
            let x = 4 + (i mod 2) * 20
            buffer.setString(x, row, name, style(color, modifiers = {Bold}))

        inc y, 6

        # Rainbow effect
        if y >= 0 and y < area.height:
          buffer.setString(
            2, y, "Rainbow Effect:", style(Color.Yellow, modifiers = {Bold})
          )
        inc y

        if y >= 0 and y < area.height:
          let rainbowText = "Rainbow Colors!"
          let startX = area.width div 2 - rainbowText.len div 2

          for i, ch in rainbowText:
            let hue = (i * 360) div rainbowText.len
            let color = hsv(hue.float, 1.0, 1.0)
            buffer.setString(startX + i, y, $ch, style(color, modifiers = {Bold}))
        inc y, 2

        # Color interpolation demo
        if y >= 0 and y < area.height:
          buffer.setString(
            2, y, "Color Interpolation:", style(Color.Yellow, modifiers = {Bold})
          )
        inc y

        if y >= 0 and y < area.height:
          let redColor = rgb(255, 0, 0)
          let blueColor = rgb(0, 0, 255)
          let interpText = "Red to Blue Gradient"
          let startX = 4

          for i, ch in interpText:
            let t = i.float / (interpText.len - 1).float
            let interpColor = lerp(redColor, blueColor, t)
            buffer.setString(startX + i, y, $ch, style(interpColor, modifiers = {Bold}))
        inc y, 2

        # HSV color space demo
        if y >= 0 and y < area.height:
          buffer.setString(
            2, y, "HSV Color Space:", style(Color.Yellow, modifiers = {Bold})
          )
        inc y

        if y >= 0 and y < area.height:
          for i in 0 .. 11:
            let hue = i * 30
            let color = hsv(hue.float, 1.0, 1.0)
            let x = 4 + i * 3
            if x + 2 < area.width:
              buffer.setString(x, y, "███", style(color))
        inc y, 2

        # True color gradient bars
        if y >= 0 and y < area.height:
          buffer.setString(
            2, y, "True Color Gradients:", style(Color.Yellow, modifiers = {Bold})
          )
        inc y

        # Red gradient
        if y >= 0 and y < area.height:
          buffer.setString(2, y, "Red:", style(Color.White))
          for i in 0 .. min(40, area.width - 8):
            let intensity = (i * 255) div 40
            let color = rgb(intensity, 0, 0)
            buffer.setString(7 + i, y, "█", style(color))
        inc y

        # Green gradient
        if y >= 0 and y < area.height:
          buffer.setString(2, y, "Green:", style(Color.White))
          for i in 0 .. min(40, area.width - 8):
            let intensity = (i * 255) div 40
            let color = rgb(0, intensity, 0)
            buffer.setString(7 + i, y, "█", style(color))
        inc y

        # Blue gradient
        if y >= 0 and y < area.height:
          buffer.setString(2, y, "Blue:", style(Color.White))
          for i in 0 .. min(40, area.width - 8):
            let intensity = (i * 255) div 40
            let color = rgb(0, 0, intensity)
            buffer.setString(7 + i, y, "█", style(color))
        inc y, 2

        # Hue spectrum
        if y >= 0 and y < area.height:
          buffer.setString(
            2, y, "Hue Spectrum (360°):", style(Color.Yellow, modifiers = {Bold})
          )
        inc y

        if y >= 0 and y < area.height:
          for i in 0 .. min(60, area.width - 4):
            let hue = (i * 360) div 60
            let color = hsv(hue.float, 1.0, 1.0)
            buffer.setString(4 + i, y, "█", style(color))
        inc y, 2

        # Saturation demo
        if y >= 0 and y < area.height:
          buffer.setString(
            2,
            y,
            "Saturation (Red at 240° hue):",
            style(Color.Yellow, modifiers = {Bold}),
          )
        inc y

        if y >= 0 and y < area.height:
          for i in 0 .. min(40, area.width - 4):
            let saturation = i.float / 40.0
            let color = hsv(240.0, saturation, 1.0)
            buffer.setString(4 + i, y, "█", style(color))
        inc y, 2

        # Value/Brightness demo
        if y >= 0 and y < area.height:
          buffer.setString(
            2,
            y,
            "Brightness (Green at full saturation):",
            style(Color.Yellow, modifiers = {Bold}),
          )
        inc y

        if y >= 0 and y < area.height:
          for i in 0 .. min(40, area.width - 4):
            let value = i.float / 40.0
            let color = hsv(120.0, 1.0, value)
            buffer.setString(4 + i, y, "█", style(color))
        inc y, 2

        # Color temperature simulation
        if y >= 0 and y < area.height:
          buffer.setString(
            2,
            y,
            "Color Temperature (warm to cool):",
            style(Color.Yellow, modifiers = {Bold}),
          )
        inc y

        if y >= 0 and y < area.height:
          for i in 0 .. min(40, area.width - 4):
            let t = i.float / 40.0
            # Simulate color temperature from warm (red/orange) to cool (blue)
            let r = uint8(255 - t * 100)
            let g = uint8(150 + t * 50)
            let b = uint8(100 + t * 155)
            let color = rgb(r, g, b)
            buffer.setString(4 + i, y, "█", style(color))
        inc y, 2

        # Plasma-like effect
        if y >= 0 and y < area.height:
          buffer.setString(
            2, y, "Plasma Effect:", style(Color.Yellow, modifiers = {Bold})
          )
        inc y

        for row in 0 .. 4:
          if y + row >= 0 and y + row < area.height:
            for col in 0 .. min(50, area.width - 4):
              # Create a plasma-like pattern using sine waves
              let x = col.float * 0.1
              let yPos = row.float * 0.2
              let plasma = sin(x) + sin(yPos) + sin(x + yPos)

              # Map plasma value to RGB
              let normalized = (plasma + 3.0) / 6.0 # Normalize to 0-1
              let hue = normalized * 360.0
              let color = hsv(hue, 0.8, 0.9)
              buffer.setString(4 + col, y + row, "█", style(color))
        inc y, 6

        # RGB cube visualization
        if y >= 0 and y < area.height:
          buffer.setString(
            2, y, "RGB Cube Slices:", style(Color.Yellow, modifiers = {Bold})
          )
        inc y

        # Show RGB cube as 2D slices with different red values
        for redLevel in 0 .. 2:
          if y >= 0 and y < area.height:
            buffer.setString(2, y, &"R={redLevel * 127}: ", style(Color.White))

            for g in 0 .. 7:
              for b in 0 .. 7:
                let x = 12 + g * 8 + b
                if x < area.width:
                  let r = redLevel * 127
                  let gVal = g * 36
                  let bVal = b * 36
                  let color = rgb(r, gVal, bVal)
                  buffer.setString(x, y, "█", style(color))
          inc y
      else:
        discard

      # Mode indicator and instructions
      let modeText =
        case appState.mode
        of 0: "Mode 1: Basic Colors"
        of 1: "Mode 2: 256-Color Palette"
        of 2: "Mode 3: RGB & Effects"
        else: "Unknown Mode"

      if area.height > 4:
        buffer.setString(
          2, area.height - 4, modeText, style(Color.BrightYellow, modifiers = {Bold})
        )

        let instructions =
          ["Controls: 1/2/3 = Switch modes, ↑/↓ = Scroll, q/ESC = Quit"]

        for i, instruction in instructions:
          buffer.setString(
            2, area.height - 3 + i, instruction, style(Color.BrightBlack)
          )
    ,
  )

when isMainModule:
  echo "Starting Complete Color Showcase..."
  echo "Press 1/2/3 to switch between modes:"
  echo "  1 = Basic colors and styles"
  echo "  2 = 256-color palette"
  echo "  3 = RGB colors and effects"
  echo "Use ↑/↓ to scroll, 'q' or ESC to quit"
  main()
