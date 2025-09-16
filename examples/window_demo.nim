## Window Management Demo
##
## This example demonstrates Celina's window management system features:
## - Multiple overlapping windows
## - Window focus management
## - Window movement and resizing
## - Modal dialogs
## - Window borders and titles
## - Mouse interaction with windows

import pkg/celina

import std/[strformat, strutils, random, options]

type WindowDemo = ref object
  messageLog: seq[string]
  nextWindowNum: int
  selectedWindowId: Option[WindowId]

proc newWindowDemo(): WindowDemo =
  WindowDemo(messageLog: @[], nextWindowNum: 1, selectedWindowId: none(WindowId))

proc addMessage(demo: WindowDemo, msg: string) =
  demo.messageLog.add(msg)
  # Keep only the last 10 messages
  if demo.messageLog.len > 10:
    demo.messageLog = demo.messageLog[1 ..^ 1]

proc createTestWindow(
    demo: WindowDemo, app: App, title: string, area: Rect, modal: bool = false
): WindowId =
  ## Create a test window with content
  let window = newWindow(
    area = area,
    title = title,
    border = some(defaultBorder()),
    resizable = true,
    movable = true,
    modal = modal,
  )

  # Set up key handler for the window
  window.setKeyHandler(
    proc(win: Window, key: KeyEvent): bool =
      case key.code
      of KeyCode.Char:
        case key.char
        of 'c':
          demo.addMessage(&"Window '{win.title}' received 'c' key")
          return true
        of 'x':
          demo.addMessage(&"Closing window '{win.title}'")
          app.removeWindow(win.id)
          return true
        else:
          discard
      of KeyCode.Delete:
        demo.addMessage(&"Deleting window '{win.title}'")
        app.removeWindow(win.id)
        return true
      else:
        discard
      return false
  )

  # Set up mouse handler for the window
  window.setMouseHandler(
    proc(win: Window, mouse: MouseEvent): bool =
      let relativeX = mouse.x - win.contentArea.x
      let relativeY = mouse.y - win.contentArea.y

      case mouse.kind
      of Press:
        case mouse.button
        of Left:
          demo.addMessage(&"Left click in '{win.title}' at ({relativeX}, {relativeY})")
          demo.selectedWindowId = some(win.id)
          return true
        of Right:
          demo.addMessage(&"Right click in '{win.title}' - creating modal dialog")
          # Create a modal dialog
          let dialogArea = rect(win.area.x + 5, win.area.y + 3, 30, 8)
          discard demo.createTestWindow(app, "Modal Dialog", dialogArea, modal = true)
          return true
        else:
          discard
      else:
        discard
      return false
  )

  return app.addWindow(window)

proc updateWindowContent(demo: WindowDemo, app: App) =
  ## Update content for all windows
  let windows = app.getWindows()

  for window in windows:
    var buffer = window.getContentBuffer()
    buffer.clear()

    let area = buffer.area
    let centerX = area.width div 2

    # Window title and info
    let titleLine = &"Window: {window.title}"
    let xPos = max(0, centerX - titleLine.len div 2)
    buffer.setString(
      xPos, 0, titleLine, Style(fg: rgb(100, 200, 255), modifiers: {Bold})
    )

    # Window ID and status
    let idLine = &"ID: {window.id}"
    let statusLine = if window.focused: "Status: FOCUSED" else: "Status: Normal"
    buffer.setString(1, 2, idLine, Style(fg: rgb(255, 255, 100)))
    buffer.setString(
      1,
      3,
      statusLine,
      Style(
        fg:
          if window.focused:
            rgb(0, 255, 0)
          else:
            rgb(150, 150, 150),
        modifiers:
          if window.focused:
            {Bold}
          else:
            {},
      ),
    )

    # Instructions
    let instructions = [
      "", "Controls:", "• Click to focus window", "• Right-click for modal",
      "• Press 'c' for message", "• Press 'x' to close", "• Press Del to delete",
      "• Press 'f' to cycle focus", "• Use arrow keys to move window",
    ]

    for i, instruction in instructions:
      let y = 5 + i
      if y < area.height:
        buffer.setString(1, y, instruction, defaultStyle())

    # Show selection indicator
    if demo.selectedWindowId.isSome() and demo.selectedWindowId.get() == window.id:
      let indicator = ">>> SELECTED <<<"
      let indX = max(0, centerX - indicator.len div 2)
      if area.height > 2:
        buffer.setString(
          indX,
          area.height - 2,
          indicator,
          Style(fg: rgb(255, 100, 100), modifiers: {Bold, SlowBlink}),
        )

proc renderMainContent(demo: WindowDemo, buffer: var Buffer) =
  buffer.clear()

  let area = buffer.area
  let centerX = area.width div 2

  # Title
  let title = "🪟 Celina Window Management Demo"
  buffer.setString(
    centerX - title.len div 2,
    1,
    title,
    Style(fg: rgb(100, 200, 255), modifiers: {Bold}),
  )

  # Instructions
  let instructions = [
    "",
    "Global Controls:",
    "• Press '1'-'3' to create new windows",
    "• Press 'm' to create a modal dialog",
    "• Press 'r' to create a random window",
    "• Press 'f' to cycle window focus",
    "• Press arrow keys to move focused window",
    "• Press 'q' to quit",
    "",
    "Window Controls:",
    "• Left-click a window to focus it",
    "• Right-click for modal dialog",
    "• Press 'c' while focused for message",
    "• Press Delete to close window",
    "",
    &"Total windows: {demo.messageLog.len}",
  ]

  for i, instruction in instructions:
    let y = 4 + i
    if y < area.height - 8:
      buffer.setString(2, y, instruction, defaultStyle())

  # Message log
  let logStart = area.height - min(demo.messageLog.len + 2, 8)
  buffer.setString(
    2, logStart, "Recent Events:", Style(fg: rgb(255, 200, 100), modifiers: {Bold})
  )

  for i, msg in demo.messageLog:
    let y = logStart + 1 + i
    if y < area.height - 1:
      buffer.setString(2, y, &"• {msg}", Style(fg: rgb(200, 200, 200)))

proc main() =
  randomize()
  let demo = newWindowDemo()

  # App configuration with window mode enabled
  let config = AppConfig(
    title: "Window Demo",
    alternateScreen: true,
    mouseCapture: true,
    rawMode: true,
    windowMode: true, # Enable window management!
  )

  var app = newApp(config)

  # Create initial windows
  discard demo.createTestWindow(app, "Welcome Window", rect(50, 5, 40, 12))
  discard demo.createTestWindow(app, "Info Window", rect(65, 8, 35, 10))

  demo.addMessage("Window demo started")
  demo.addMessage("Two initial windows created")

  app.onEvent proc(event: Event): bool =
    case event.kind
    of Key:
      case event.key.code
      of Char:
        case event.key.char
        of 'q':
          return false # Quit
        of '1', '2', '3':
          let num = parseInt($event.key.char)
          let area = rect(5 + num * 8, 3 + num * 3, 30 + num * 2, 8 + num)
          discard demo.createTestWindow(app, &"Window {demo.nextWindowNum}", area)
          demo.nextWindowNum.inc()
          demo.addMessage(&"Created window #{num}")
        of 'r':
          # Create random window
          let x = rand(5 .. 50)
          let y = rand(3 .. 15)
          let w = rand(25 .. 45)
          let h = rand(8 .. 15)
          let area = rect(x, y, w, h)
          discard demo.createTestWindow(app, &"Random {demo.nextWindowNum}", area)
          demo.nextWindowNum.inc()
          demo.addMessage("Created random window")
        of 'm':
          # Create modal dialog in center
          let area = rect(20, 10, 40, 10)
          discard demo.createTestWindow(app, "Modal Dialog", area, modal = true)
          demo.addMessage("Created modal dialog")
        of 'f':
          # Cycle through window focus
          let windows = app.getWindows()
          if windows.len > 0:
            let currentFocusedOpt = app.getFocusedWindowId()
            if currentFocusedOpt.isSome():
              let currentId = currentFocusedOpt.get()
              # Find current window index
              var currentIndex = -1
              for i, window in windows:
                if window.id == currentId:
                  currentIndex = i
                  break

              # Move to next window (cycle)
              let nextIndex = (currentIndex + 1) mod windows.len
              app.focusWindow(windows[nextIndex].id)
              demo.addMessage(&"Focused window: {windows[nextIndex].title}")
            else:
              # No window focused, focus first one
              app.focusWindow(windows[0].id)
              demo.addMessage(&"Focused first window: {windows[0].title}")
        else:
          discard
      of KeyCode.ArrowUp, KeyCode.ArrowDown, KeyCode.ArrowLeft, KeyCode.ArrowRight:
        # Move focused window with arrow keys
        let focusedWindowOpt = app.getFocusedWindow()
        if focusedWindowOpt.isSome():
          let window = focusedWindowOpt.get()
          if not window.modal: # Don't move modal windows
            let currentPos = pos(window.area.x, window.area.y)
            var newPos = currentPos

            # Calculate movement step (5 pixels)
            const moveStep = 5
            case event.key.code
            of KeyCode.ArrowUp:
              newPos.y = max(0, currentPos.y - moveStep)
            of KeyCode.ArrowDown:
              newPos.y = currentPos.y + moveStep
            of KeyCode.ArrowLeft:
              newPos.x = max(0, currentPos.x - moveStep)
            of KeyCode.ArrowRight:
              newPos.x = currentPos.x + moveStep
            else:
              discard

            # Move the window
            window.move(newPos)
            demo.addMessage(&"Moved '{window.title}' to ({newPos.x}, {newPos.y})")
        else:
          demo.addMessage("No window focused for movement")
      of Escape:
        return false # Quit on Escape
      else:
        discard
    of Mouse:
      # Mouse events are handled by the window system
      discard
    of Quit:
      return false
    else:
      discard

    return true # Continue running

  app.onRender proc(buffer: var Buffer) =
    demo.renderMainContent(buffer)
    demo.updateWindowContent(app)

  try:
    app.run()
  except TerminalError as e:
    echo "Terminal error: ", e.msg
  except CatchableError as e:
    echo "Error: ", e.msg

when isMainModule:
  main()
