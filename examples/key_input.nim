## Key Input Handling Example
##
## This example demonstrates comprehensive key input handling in Celina.
## It shows how to capture and respond to different types of key events.

import std/[strformat, strutils]
import ../src/celina

type InputState = object
  lastKey: string
  keyHistory: seq[string]
  showHelp: bool

proc formatKeyEvent(event: KeyEvent): string =
  ## Format a key event for display
  var parts: seq[string]

  # Add modifiers
  if Ctrl in event.modifiers:
    parts.add("Ctrl")
  if Alt in event.modifiers:
    parts.add("Alt")
  if Shift in event.modifiers:
    parts.add("Shift")

  # Add key code
  let keyName =
    case event.code
    of KeyCode.Char:
      &"'{event.char}'"
    of KeyCode.Enter:
      "Enter"
    of KeyCode.Escape:
      "Escape"
    of KeyCode.Backspace:
      "Backspace"
    of KeyCode.Tab:
      "Tab"
    of KeyCode.Space:
      "Space"
    of KeyCode.ArrowUp:
      "↑"
    of KeyCode.ArrowDown:
      "↓"
    of KeyCode.ArrowLeft:
      "←"
    of KeyCode.ArrowRight:
      "→"
    of KeyCode.F1:
      "F1"
    of KeyCode.F2:
      "F2"
    of KeyCode.F3:
      "F3"
    of KeyCode.F4:
      "F4"
    of KeyCode.F5:
      "F5"
    of KeyCode.F6:
      "F6"
    of KeyCode.F7:
      "F7"
    of KeyCode.F8:
      "F8"
    of KeyCode.F9:
      "F9"
    of KeyCode.F10:
      "F10"
    of KeyCode.F11:
      "F11"
    of KeyCode.F12:
      "F12"

  parts.add(keyName)

  if parts.len > 1:
    parts[0 ..^ 2].join("+") & "+" & parts[^1]
  else:
    parts[0]

proc main() =
  var state = InputState(lastKey: "None", keyHistory: @[], showHelp: true)

  quickRun(
    eventHandler = proc(event: Event): bool =
      case event.kind
      of EventKind.Key:
        let keyStr = formatKeyEvent(event.key)
        state.lastKey = keyStr

        # Add to history (keep last 10 keys)
        state.keyHistory.add(keyStr)
        if state.keyHistory.len > 10:
          state.keyHistory.delete(0)

        # Handle special keys
        case event.key.code
        of KeyCode.Char:
          case event.key.char
          of 'q':
            return false # Quit
          of 'h':
            state.showHelp = not state.showHelp
          of 'c':
            state.keyHistory = @[] # Clear history
          else:
            discard
        of KeyCode.Escape:
          return false
        of KeyCode.F1:
          state.showHelp = not state.showHelp
        else:
          discard
      else:
        discard
      return true,
    renderHandler = proc(buffer: var Buffer) =
      buffer.clear()

      let area = buffer.area
      var currentY = 2

      # Title
      let title = "Key Input Handler"
      buffer.setString(
        area.width div 2 - title.len div 2,
        currentY,
        title,
        style(Color.Cyan, modifiers = {Bold, Underline}),
      )
      currentY += 3

      # Current key display
      let lastKeyLabel = "Last Key Pressed:"
      buffer.setString(
        4, currentY, lastKeyLabel, style(Color.Yellow, modifiers = {Bold})
      )

      buffer.setString(
        4 + lastKeyLabel.len + 1,
        currentY,
        state.lastKey,
        style(Color.Green, modifiers = {Bold}),
      )
      currentY += 3

      # Key history
      buffer.setString(
        4, currentY, "Key History (last 10):", style(Color.Yellow, modifiers = {Bold})
      )
      currentY += 1

      for i, key in state.keyHistory:
        let color =
          if i == state.keyHistory.len - 1: Color.White else: Color.BrightBlack
        buffer.setString(6, currentY + i, &"{i + 1:2}. {key}", style(color))

      currentY += state.keyHistory.len + 2

      # Help section
      if state.showHelp:
        buffer.setString(
          4,
          currentY,
          "Help (h/F1 to toggle):",
          style(Color.Magenta, modifiers = {Bold}),
        )
        currentY += 1

        let helpText = [
          "• Type any character to see it captured",
          "• Use arrow keys, function keys, etc.",
          "• Try Ctrl, Alt, Shift combinations", "• 'c' - Clear key history",
          "• 'h' or F1 - Toggle this help", "• 'q' or ESC - Quit application",
        ]

        for i, line in helpText:
          buffer.setString(6, currentY + i, line, style(Color.BrightBlack))

        currentY += helpText.len + 1
      else:
        buffer.setString(
          4, currentY, "Press 'h' or F1 to show help", style(Color.BrightBlack)
        )
        currentY += 2

      # Special keys demonstration
      buffer.setString(
        4, currentY, "Try these special keys:", style(Color.Blue, modifiers = {Bold})
      )
      currentY += 1

      let specialKeys = [
        "Arrow Keys: ↑ ↓ ← →", "Function Keys: F1-F12",
        "Special: Enter, Tab, Space, Backspace", "Modifiers: Ctrl+[key], Alt+[key]",
      ]

      for i, line in specialKeys:
        buffer.setString(6, currentY + i, line, style(Color.BrightCyan))

      # Status bar at bottom
      let helpStatus = if state.showHelp: "ON" else: "OFF"
      let statusText = &"Keys captured: {state.keyHistory.len} | Help: {helpStatus}"
      buffer.setString(2, area.height - 2, statusText, style(Color.BrightBlack))

      # Quit instruction
      let quitText = "Press 'q' or ESC to quit"
      buffer.setString(
        area.width - quitText.len - 2,
        area.height - 2,
        quitText,
        style(Color.BrightBlack),
      ),
  )

when isMainModule:
  echo "Starting Key Input Handler example..."
  echo "This will capture and display all key presses"
  echo "Press 'h' for help, 'q' or ESC to quit"
  main()
