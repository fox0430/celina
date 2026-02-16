import ../celina

proc main() =
  var app = newApp()

  var lastKey = "Press any key..."
  var keyHistory: seq[string] = @[]

  # Set up the render handler
  app.onRender(
    proc(buf: var Buffer) =
      # Draw title
      let title = "Key Input Display Demo"
      buf.setString(
        (buf.area.width - title.len) div 2, 1, title, Style(fg: rgb(100, 200, 255))
      )

      # Draw instructions
      buf.setString(
        2, 3, "Press any key to see its representation", Style(fg: rgb(150, 150, 150))
      )
      buf.setString(2, 4, "Press Escape to quit", Style(fg: rgb(150, 150, 150)))

      # Draw current key
      buf.setString(2, 6, "Last Key: ", Style(fg: rgb(200, 200, 200)))
      buf.setString(12, 6, lastKey, Style(fg: rgb(255, 255, 100)))

      # Draw history
      if keyHistory.len > 0:
        buf.setString(2, 8, "History:", Style(fg: rgb(200, 200, 200)))
        for i, key in keyHistory:
          let alpha = 255 - (i * 20)
          buf.setString(4, 9 + i, "• " & key, Style(fg: rgb(alpha, alpha, alpha)))
  )

  # Set up the event handler
  app.onEvent(
    proc(event: Event): bool =
      if event.kind == EventKind.Key:
        let keyInfo =
          case event.key.code
          of KeyCode.Enter:
            "Enter (or Ctrl-m)"
          of KeyCode.Escape:
            "Escape"
          of KeyCode.Backspace:
            "Backspace (or Ctrl-h)"
          of KeyCode.Tab:
            "Tab (or Ctrl-i)"
          of KeyCode.BackTab:
            "BackTab"
          of KeyCode.Space:
            "Space"
          of KeyCode.ArrowUp:
            "Up Arrow"
          of KeyCode.ArrowDown:
            "Down Arrow"
          of KeyCode.ArrowLeft:
            "Left Arrow"
          of KeyCode.ArrowRight:
            "Right Arrow"
          of KeyCode.Home:
            "Home"
          of KeyCode.End:
            "End"
          of KeyCode.PageUp:
            "Page Up"
          of KeyCode.PageDown:
            "Page Down"
          of KeyCode.Delete:
            "Delete"
          of KeyCode.Insert:
            "Insert"
          of KeyCode.F1 .. KeyCode.F12:
            "F" & $(ord(event.key.code) - ord(KeyCode.F1) + 1)
          of KeyCode.Char:
            "'" & event.key.char & "'"

        var modifiers = ""
        if Ctrl in event.key.modifiers:
          modifiers.add("Ctrl+")
        if Alt in event.key.modifiers:
          modifiers.add("Alt+")
        if Shift in event.key.modifiers and event.key.code != KeyCode.Char:
          modifiers.add("Shift+")

        lastKey = modifiers & keyInfo
        keyHistory.insert(lastKey, 0)
        if keyHistory.len > 10:
          keyHistory.setLen(10)

        # Quit on Escape
        if event.key.code == KeyCode.Escape:
          return false

      return true
  )

  # Start the main event loop
  app.run()

when isMainModule:
  main()
