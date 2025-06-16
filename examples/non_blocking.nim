## Non-blocking Input Example
##
## This example demonstrates non-blocking input handling with real-time updates.
## It shows a live clock, timer, and progress bar that update continuously
## without requiring user input, while still responding to key presses.

import std/[times, strformat, strutils]
import ../src/celina

type AppState = object
  startTime: DateTime
  isPaused: bool
  counter: int
  showMillis: bool

proc formatDuration(duration: Duration): string =
  ## Format a duration as HH:MM:SS
  let totalSeconds = duration.inSeconds
  let hours = totalSeconds div 3600
  let minutes = (totalSeconds mod 3600) div 60
  let seconds = totalSeconds mod 60
  &"{hours:02d}:{minutes:02d}:{seconds:02d}"

proc formatDurationWithMillis(duration: Duration): string =
  ## Format a duration as HH:MM:SS.mmm
  let totalMs = duration.inMilliseconds
  let hours = totalMs div 3600000
  let minutes = (totalMs mod 3600000) div 60000
  let seconds = (totalMs mod 60000) div 1000
  let millis = totalMs mod 1000
  &"{hours:02d}:{minutes:02d}:{seconds:02d}.{millis:03d}"

proc main() =
  var state = AppState(startTime: now(), isPaused: false, counter: 0, showMillis: false)

  quickRun(
    eventHandler = proc(event: Event): bool =
      case event.kind
      of EventKind.Key:
        case event.key.code
        of KeyCode.Char:
          case event.key.char
          of 'q':
            return false # Quit
          of ' ':
            state.isPaused = not state.isPaused # Toggle pause
          of 'r':
            state.startTime = now() # Reset timer
            state.counter = 0
          of 'm':
            state.showMillis = not state.showMillis # Toggle milliseconds
          of '+', '=':
            inc state.counter
          of '-', '_':
            dec state.counter
          else:
            discard
        of KeyCode.Escape:
          return false
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
      let title = "Non-blocking Input Demo"
      buffer.setString(
        area.width div 2 - title.len div 2,
        currentY,
        title,
        style(Color.Cyan, modifiers = {Bold, Underline}),
      )
      currentY += 3

      # Current time
      let currentTime = now()
      let timeStr = currentTime.format("yyyy-MM-dd HH:mm:ss")
      buffer.setString(
        4, currentY, "Current Time: ", style(Color.Yellow, modifiers = {Bold})
      )
      buffer.setString(
        4 + "Current Time: ".len,
        currentY,
        timeStr,
        style(Color.White, modifiers = {Bold}),
      )
      currentY += 2

      # Timer
      let elapsed =
        if state.isPaused:
          initDuration()
        else:
          currentTime - state.startTime

      let timerLabel = "Timer: "
      let timerStr =
        if state.showMillis:
          formatDurationWithMillis(elapsed)
        else:
          formatDuration(elapsed)

      buffer.setString(4, currentY, timerLabel, style(Color.Yellow, modifiers = {Bold}))
      buffer.setString(
        4 + timerLabel.len,
        currentY,
        timerStr,
        style(if state.isPaused: Color.Red else: Color.Green, modifiers = {Bold}),
      )

      let statusText = if state.isPaused: " (PAUSED)" else: " (Running)"
      buffer.setString(
        4 + timerLabel.len + timerStr.len,
        currentY,
        statusText,
        style(if state.isPaused: Color.Red else: Color.BrightBlack),
      )
      currentY += 2

      # Counter
      let counterLabel = "Counter: "
      let counterStr = $state.counter
      buffer.setString(
        4, currentY, counterLabel, style(Color.Yellow, modifiers = {Bold})
      )
      buffer.setString(
        4 + counterLabel.len,
        currentY,
        counterStr,
        style(
          if state.counter > 0:
            Color.Green
          elif state.counter < 0:
            Color.Red
          else:
            Color.White,
          modifiers = {Bold},
        ),
      )
      currentY += 3

      # Progress bar (based on seconds)
      let progressWidth = 40
      let secondsElapsed = elapsed.inSeconds mod 60
      let progress = (secondsElapsed * progressWidth) div 60

      buffer.setString(
        4, currentY, "Progress (60s cycle): ", style(Color.Magenta, modifiers = {Bold})
      )
      currentY += 1

      # Draw progress bar
      let barStart = 4
      for i in 0 ..< progressWidth:
        let ch = if i < progress: "█" else: "░"
        let color = if i < progress: Color.Green else: Color.BrightBlack
        buffer.setString(barStart + i, currentY, ch, style(color))

      # Progress percentage
      let percentage = (progress * 100) div progressWidth
      buffer.setString(
        barStart + progressWidth + 2,
        currentY,
        &"{percentage:3d}%",
        style(Color.White, modifiers = {Bold}),
      )
      currentY += 3

      # Animated dots
      let dotsCount = (elapsed.inMilliseconds div 500) mod 4
      let dots = ".".repeat(dotsCount)
      let animLabel = "Animation: "
      buffer.setString(4, currentY, animLabel, style(Color.Blue, modifiers = {Bold}))
      buffer.setString(
        4 + animLabel.len,
        currentY,
        dots & " ".repeat(3 - dotsCount),
        style(Color.BrightCyan),
      )
      currentY += 3

      # Instructions
      buffer.setString(
        4, currentY, "Controls:", style(Color.Yellow, modifiers = {Bold})
      )
      currentY += 1

      let instructions = [
        "Space  - Pause/Resume timer", "r      - Reset timer and counter",
        "m      - Toggle milliseconds display", "+/-    - Increment/Decrement counter",
        "q/ESC  - Quit",
      ]

      for instruction in instructions:
        buffer.setString(6, currentY, instruction, style(Color.BrightBlack))
        currentY += 1

      # Status message
      let statusMsg = "This updates in real-time without blocking input!"
      buffer.setString(
        area.width div 2 - statusMsg.len div 2,
        area.height - 3,
        statusMsg,
        style(Color.Green, modifiers = {Italic}),
      )

      # Quit instruction
      let quitText = "Press 'q' or ESC to quit"
      buffer.setString(
        area.width div 2 - quitText.len div 2,
        area.height - 2,
        quitText,
        style(Color.BrightBlack),
      ),
  )

when isMainModule:
  echo "Starting Non-blocking Input example..."
  echo "This demonstrates real-time updates with responsive input handling"
  echo "The display updates continuously while still responding to key presses"
  main()
