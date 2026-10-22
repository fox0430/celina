# Inline viewport example for Celina
#
# Draws a progress bar in a few rows at the cursor instead of the whole
# screen. The last frame stays in the scrollback on exit.

import std/[monotimes, times]

import pkg/celina
import pkg/celina/widgets/progress

const durationMs = 3000.0

proc main() =
  let config = defaultAppConfig().withViewport(Viewport(kind: vkInline, height: 3))
  var app = newApp(config)
  installDefaultCrashGuard(app)

  let bar = newProgressBar(0.0, "Downloading")
  var start: MonoTime
  var started = false
  var cancelled = false

  app.onTick(
    proc(): TickResult =
      # Start the clock here: setup in `run` can wait on the terminal
      if not started:
        start = getMonoTime()
        started = true
      bar.setValue((getMonoTime() - start).inMilliseconds.float / durationMs)
      if bar.isComplete: trQuit else: trContinue
  )

  app.onRender(
    proc(buf: var Buffer) =
      buf.clear()
      # Lay out by `buf.area`: it is the viewport, not the terminal, and may
      # be shorter than asked. The hint takes the last row when there is room.
      let barHeight = clamp(buf.area.height - 1, 1, 2)
      bar.render(rect(0, 0, buf.area.width, barHeight), buf)
      let (hint, hintStyle) =
        if cancelled:
          ("Cancelled", Style(fg: color(Red)))
        elif bar.isComplete:
          ("Done", Style(fg: color(Green)))
        else:
          ("Press 'q' or Ctrl-C to cancel", Style(fg: color(BrightBlack)))
      if buf.area.height > barHeight:
        buf.setString(0, barHeight, hint, hintStyle)
  )

  app.onEvent(
    proc(event: Event): EventResult =
      # Raw mode turns Ctrl-C into a Quit event instead of SIGINT
      let isQuit =
        event.kind == EventKind.Quit or (
          event.kind == EventKind.Key and event.key.code == KeyCode.Char and
          event.key.char == "q"
        )
      if isQuit:
        cancelled = true
        return erQuit
      return erContinue
  )

  app.run()

when isMainModule:
  main()
