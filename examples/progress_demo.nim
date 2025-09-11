# Progress Bar Demo
##
## An example demonstrating various progress bar styles and features

import std/times

import pkg/celina
import pkg/celina/widgets/progress

proc main() =
  # Create various progress bars
  var blockProgress = newProgressBar(0.0, "Block Style", style = Block)
  var lineProgress = newProgressBar(0.0, "Line Style", style = Line)
  var arrowProgress = newProgressBar(0.0, "Arrow Style", style = Arrow)
  var hashProgress = newProgressBar(0.0, "Hash Style", style = Hash)

  # Custom styled progress bars using new mutable API
  var coloredProgress = coloredProgressBar(0.0, "Colored Progress", Green)
  var minimalProgress = minimalProgressBar(0.0)
  var textOnlyProgress = textOnlyProgressBar(0.0, "Text Only")

  # Demonstrate mutable API
  var customProgress = newProgressBar(0.0, "Custom")
  customProgress.style = Arrow
  customProgress.barStyle = style(White, Magenta)
  customProgress.minWidth = 25

  # Task and download progress bars
  var taskProgress = taskProgressBar(0, 10, "Tasks")
  var downloadProgress = downloadProgressBar(0, 1024 * 1024 * 100, "Download")

  # Animation state
  var progress = 0.0
  var tasksCompleted = 0
  var bytesDownloaded: int64 = 0
  var lastUpdate = epochTime()
  var incrementDirection = 1.0

  let config = AppConfig(
    title: "Progress Bar Demo",
    alternateScreen: true,
    mouseCapture: false,
    rawMode: true,
    targetFps: 30,
  )

  var app = newApp(config)

  app.onEvent(
    proc(event: Event): bool =
      case event.kind
      of EventKind.Key:
        case event.key.code
        of KeyCode.Char:
          case event.key.char
          of 'q', 'Q':
            return false # Quit
          of 'r', 'R': # Reset
            progress = 0.0
            tasksCompleted = 0
            bytesDownloaded = 0
          of 'c', 'C': # Complete
            progress = 1.0
            tasksCompleted = 10
            bytesDownloaded = 1024 * 1024 * 100
          else:
            discard
        of KeyCode.Space: # Pause/Resume
          incrementDirection = if incrementDirection == 0.0: 1.0 else: 0.0
        of KeyCode.Escape:
          return false
        of KeyCode.ArrowUp: # Increase progress
          progress = min(1.0, progress + 0.1)
          tasksCompleted = min(10, tasksCompleted + 1)
          bytesDownloaded = min(1024 * 1024 * 100, bytesDownloaded + 10 * 1024 * 1024)
        of KeyCode.ArrowDown: # Decrease progress
          progress = max(0.0, progress - 0.1)
          tasksCompleted = max(0, tasksCompleted - 1)
          bytesDownloaded = max(0, bytesDownloaded - 10 * 1024 * 1024)
        else:
          discard
      else:
        discard
      return true
  )

  app.onRender(
    proc(buffer: var Buffer) =
      buffer.clear()
      let area = buffer.area

      # Auto-increment progress
      let currentTime = epochTime()
      if currentTime - lastUpdate > 0.05 and incrementDirection != 0.0:
        # Update every 50ms
        progress += 0.01 * incrementDirection
        if progress >= 1.0:
          progress = 0.0
        elif progress <= 0.0:
          progress = 0.0
          incrementDirection = 1.0

        # Update task progress
        tasksCompleted = int(progress * 10)
        bytesDownloaded = int64(progress * 1024 * 1024 * 100)

        lastUpdate = currentTime

      # Update all progress bars
      blockProgress.setValue(progress)
      lineProgress.setValue(progress)
      arrowProgress.setValue(progress)
      hashProgress.setValue(progress)
      coloredProgress.setValue(progress)
      minimalProgress.setValue(progress)
      textOnlyProgress.setValue(progress)
      customProgress.setValue(progress)
      taskProgress = taskProgressBar(tasksCompleted, 10, "Tasks")
      downloadProgress =
        downloadProgressBar(bytesDownloaded, 1024 * 1024 * 100, "Download")

      # Title
      let title = "Progress Bar Demo"
      buffer.setString(
        (area.width - title.len) div 2, 1, title, style(Cyan, Reset, {Bold, Underline})
      )

      # Instructions
      buffer.setString(2, 3, "Controls:", defaultStyle())
      buffer.setString(
        2,
        4,
        "↑/↓ - Adjust progress | Space - Pause/Resume | R - Reset | C - Complete | Q - Quit",
        defaultStyle(),
      )

      # Render different styles
      var y = 6
      buffer.setString(2, y, "Different Styles:", style(Yellow, Reset, {Bold}))
      y += 2

      # Block style
      blockProgress.render(rect(2, y, area.width - 4, 2), buffer)
      y += 3

      # Line style
      lineProgress.render(rect(2, y, area.width - 4, 2), buffer)
      y += 3

      # Arrow style
      arrowProgress.render(rect(2, y, area.width - 4, 2), buffer)
      y += 3

      # Hash style
      hashProgress.render(rect(2, y, area.width - 4, 2), buffer)
      y += 3

      # Special styles
      buffer.setString(2, y, "Special Styles:", style(Yellow, Reset, {Bold}))
      y += 2

      # Colored progress
      coloredProgress.render(rect(2, y, area.width - 4, 2), buffer)
      y += 3

      # Custom mutable API example
      customProgress.render(rect(2, y, area.width - 4, 2), buffer)
      y += 3

      # Minimal progress
      buffer.setString(2, y, "Minimal (no label):", defaultStyle())
      minimalProgress.render(rect(25, y, area.width - 27, 1), buffer)
      y += 2

      # Text only
      textOnlyProgress.render(rect(2, y, area.width - 4, 1), buffer)
      y += 2

      # Task progress
      taskProgress.render(rect(2, y, area.width - 4, 2), buffer)
      y += 3

      # Download progress
      downloadProgress.render(rect(2, y, area.width - 4, 2), buffer)

      # Status line
      let status = if incrementDirection == 0.0: "PAUSED" else: "RUNNING"
      let statusColor = if incrementDirection == 0.0: Yellow else: Green
      buffer.setString(
        area.width - status.len - 2,
        area.height - 1,
        status,
        style(statusColor, Reset, {Bold}),
      )
  )

  app.run()

when isMainModule:
  main()
