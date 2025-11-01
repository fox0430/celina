## Input Widget Demo
##
## Different input types including password fields

import pkg/celina
import pkg/celina/widgets/input

proc main() =
  var inputs = [
    newInput(
      placeholder = "Enter username",
      borderStyle = SingleBorder,
      borderNormalStyle = style(BrightBlack, Reset),
      borderFocusedStyle = style(Blue, Reset),
      normalStyle = style(White, Reset),
      focusedStyle = style(White, Blue),
      placeholderStyle = style(BrightBlack, Reset),
    ),
    newInput(
      placeholder = "Email address",
      borderStyle = RoundedBorder,
      borderNormalStyle = style(BrightBlack, Reset),
      borderFocusedStyle = style(Green, Reset),
      normalStyle = style(White, Reset),
      focusedStyle = style(Black, Green),
      placeholderStyle = style(BrightBlack, Reset),
    ),
    passwordInput(placeholder = "Enter password").withStyles(
      normal = style(White, Reset),
      focused = style(White, Red),
      placeholder = style(BrightBlack, Reset),
    ),
    searchInput(placeholder = "Search..."),
  ]

  # Add some demo values
  inputs[0].setText("user123")
  inputs[1].setText("user@example.com")

  var focusedInput = 0
  inputs[focusedInput].setFocus(true)

  var app = newApp()

  app.onEvent proc(event: Event): bool =
    case event.kind
    of EventKind.Key:
      # Always handle ESC at app level first, regardless of focus
      if event.key.code == KeyCode.Escape:
        return false

      case event.key.code
      of KeyCode.Tab:
        # Switch focus
        inputs[focusedInput].setFocus(false)
        focusedInput = (focusedInput + 1) mod inputs.len
        inputs[focusedInput].setFocus(true)
        return true
      else:
        # Forward to focused input
        discard inputs[focusedInput].handleKeyEvent(event.key)
        return true
    else:
      discard
    return true

  app.onRender proc(buffer: var Buffer) =
    buffer.clear()
    let area = buffer.area

    if area.height < 25 or area.width < 60:
      buffer.setString(
        1, 1, "Terminal too small! Need at least 60x25", style(Red, Reset)
      )
      return

    buffer.setString(
      1,
      1,
      "Input Widget Demo - Tab to switch, ESC to quit",
      style(Yellow, Reset, {StyleModifier.Bold}),
    )

    let labels = ["Username:", "Email:", "Password:", "Search:"]
    var y = 4

    for i, input in inputs:
      buffer.setString(2, y, labels[i], style(White, Reset, {StyleModifier.Bold}))

      # Calculate rect based on border style
      let inputHeight = if input.borderStyle != NoBorder: 3 else: 1
      let inputX = 14
      let inputY =
        if input.borderStyle != NoBorder:
          y - 1
        else:
          y
      let inputRect = rect(inputX, inputY, min(area.width - 16, 40), inputHeight)

      input.render(inputRect, buffer)

      # Show cursor for focused input
      if i == focusedInput:
        let (cursorX, cursorY, visible) = input.getCursorPosition(inputRect)
        if visible:
          app.showCursorAt(cursorX, cursorY)
        else:
          app.hideCursor()

      # Show input value for password fields (for demo purposes)
      if i == focusedInput and input.password and input.getText().len > 0:
        buffer.setString(
          inputX + inputRect.width + 2,
          y,
          "(" & $input.getText().len & " chars)",
          style(BrightBlack, Reset),
        )

      y += inputHeight + 2

    # Instructions
    buffer.setString(2, y, "Instructions:", style(Green, Reset, {StyleModifier.Bold}))
    buffer.setString(
      2, y + 1, "• Tab - Switch between inputs", style(BrightBlack, Reset)
    )
    buffer.setString(
      2,
      y + 2,
      "• Type to enter text (password fields show *)",
      style(BrightBlack, Reset),
    )
    buffer.setString(
      2, y + 3, "• Home/End - Jump to start/end", style(BrightBlack, Reset)
    )
    buffer.setString(2, y + 4, "• ESC - Quit", style(BrightBlack, Reset))

    # Show values for demo (showing actual password for demonstration)
    buffer.setString(
      2,
      y + 7,
      "Current Values (Demo - passwords shown):",
      style(Green, Reset, {StyleModifier.Bold}),
    )
    for i, input in inputs:
      let value = input.getText()
      let displayValue = if value.len == 0: "(empty)" else: value
      buffer.setString(
        2, y + 8 + i, labels[i] & " " & displayValue, style(BrightBlack, Reset)
      )

  app.run()

when isMainModule:
  main()
