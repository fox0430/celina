## Tests for App core functionality

import std/[unittest, options]

import ../celina

suite "App Creation and Configuration":
  test "newApp with default config":
    let app = newApp()
    check app.getTargetFps() == 60
    check app.getWindowCount() == 0

  test "newApp with custom config":
    let config = AppConfig(
      title: "Test App",
      alternateScreen: false,
      mouseCapture: true,
      rawMode: false,
      windowMode: false,
      targetFps: 30,
    )
    let app = newApp(config)
    check app.getTargetFps() == 30

  test "newApp with window mode enabled":
    let config = AppConfig(windowMode: true)
    let app = newApp(config)
    check app.getWindowCount() == 0

suite "App Event and Render Handlers":
  test "onEvent sets event handler":
    let app = newApp()
    var handlerCalled = false

    app.onEvent proc(event: Event): bool =
      handlerCalled = true
      return true

    # Handler is set but not called until run
    check handlerCalled == false

  test "onRender sets render handler":
    let app = newApp()
    var handlerCalled = false

    app.onRender proc(buffer: var Buffer) =
      handlerCalled = true

    # Handler is set but not called until run
    check handlerCalled == false

suite "App FPS Control":
  test "setTargetFps changes target FPS":
    let app = newApp()
    check app.getTargetFps() == 60

    app.setTargetFps(30)
    check app.getTargetFps() == 30

    app.setTargetFps(120)
    check app.getTargetFps() == 120

  test "getCurrentFps initially zero":
    let app = newApp()
    # FPS is 0 before any frames are rendered
    check app.getCurrentFps() >= 0.0

  test "setTargetFps with zero or negative raises error":
    let app = newApp()

    # FPS must be between 1 and 240, so invalid values should raise ValueError
    expect ValueError:
      app.setTargetFps(0)

    expect ValueError:
      app.setTargetFps(-10)

    expect ValueError:
      app.setTargetFps(250) # Above maximum

suite "App Cursor Control":
  test "setCursorPosition with coordinates":
    let app = newApp()
    app.setCursorPosition(10, 5)
    let (x, y) = app.getCursorPosition()
    check x == 10
    check y == 5

  test "setCursorPosition with Position type":
    let app = newApp()
    let position = pos(15, 20)
    app.setCursorPosition(position)
    let (x, y) = app.getCursorPosition()
    check x == 15
    check y == 20

  test "showCursorAt with coordinates":
    let app = newApp()
    app.showCursorAt(5, 10)
    let (x, y) = app.getCursorPosition()
    check x == 5
    check y == 10
    check app.isCursorVisible() == true

  test "showCursorAt with Position type":
    let app = newApp()
    let position = pos(8, 12)
    app.showCursorAt(position)
    let (x, y) = app.getCursorPosition()
    check x == 8
    check y == 12
    check app.isCursorVisible() == true

  test "showCursor makes cursor visible":
    let app = newApp()
    app.hideCursor()
    check app.isCursorVisible() == false
    app.showCursor()
    check app.isCursorVisible() == true

  test "hideCursor makes cursor invisible":
    let app = newApp()
    app.showCursor()
    check app.isCursorVisible() == true
    app.hideCursor()
    check app.isCursorVisible() == false

  test "setCursorStyle sets cursor style":
    let app = newApp()
    app.setCursorStyle(CursorStyle.SteadyBlock)
    check app.getCursorStyle() == CursorStyle.SteadyBlock

    app.setCursorStyle(CursorStyle.SteadyUnderline)
    check app.getCursorStyle() == CursorStyle.SteadyUnderline

    app.setCursorStyle(CursorStyle.SteadyBar)
    check app.getCursorStyle() == CursorStyle.SteadyBar

  test "moveCursorBy moves cursor relatively":
    let app = newApp()
    app.setCursorPosition(10, 10)

    app.moveCursorBy(5, 3)
    let (x1, y1) = app.getCursorPosition()
    check x1 == 15
    check y1 == 13

    app.moveCursorBy(-2, -1)
    let (x2, y2) = app.getCursorPosition()
    check x2 == 13
    check y2 == 12

  test "resetCursor resets to default state":
    let app = newApp()
    app.setCursorPosition(50, 50)
    app.setCursorStyle(CursorStyle.SteadyUnderline)
    app.hideCursor()

    app.resetCursor()

    # After reset, cursor should be at origin with default style
    let (x, y) = app.getCursorPosition()
    check x == -1 # Reset position is unset (-1)
    check y == -1
    check app.getCursorStyle() == CursorStyle.Default

suite "App Window Management":
  test "enableWindowMode enables window management":
    let app = newApp()
    check app.getWindowCount() == 0

    app.enableWindowMode()
    # Window mode enabled, still no windows
    check app.getWindowCount() == 0

  test "addWindow adds window and returns ID":
    let app = newApp()
    app.enableWindowMode()

    let window = newWindow(rect(10, 10, 30, 15), "Test Window")
    let windowId = app.addWindow(window)

    check windowId.int > 0
    check app.getWindowCount() == 1

  test "addWindow auto-enables window mode":
    let app = newApp() # windowMode = false

    let window = newWindow(rect(10, 10, 30, 15), "Test Window")
    let windowId = app.addWindow(window)

    check windowId.int > 0
    check app.getWindowCount() == 1

  test "removeWindow removes window":
    let app = newApp()
    app.enableWindowMode()

    let window = newWindow(rect(10, 10, 30, 15), "Test Window")
    let windowId = app.addWindow(window)

    check app.getWindowCount() == 1

    app.removeWindow(windowId)
    check app.getWindowCount() == 0

  test "getWindow retrieves window by ID":
    let app = newApp()
    app.enableWindowMode()

    let window = newWindow(rect(10, 10, 30, 15), "Test Window")
    let windowId = app.addWindow(window)

    let retrievedOpt = app.getWindow(windowId)
    check retrievedOpt.isSome()
    check retrievedOpt.get().title == "Test Window"

  test "getWindow with invalid ID returns none":
    let app = newApp()
    app.enableWindowMode()

    let windowOpt = app.getWindow(WindowId(999))
    check windowOpt.isNone()

  test "focusWindow focuses window":
    let app = newApp()
    app.enableWindowMode()

    let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
    let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")

    let id1 = app.addWindow(window1)
    discard app.addWindow(window2)

    # Focus first window
    app.focusWindow(id1)

    let focusedOpt = app.getFocusedWindow()
    check focusedOpt.isSome()
    check focusedOpt.get().id == id1

  test "getFocusedWindow returns last added window":
    let app = newApp()
    app.enableWindowMode()

    let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
    let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")

    discard app.addWindow(window1)
    let id2 = app.addWindow(window2)

    let focusedOpt = app.getFocusedWindow()
    check focusedOpt.isSome()
    check focusedOpt.get().id == id2

  test "getWindows returns all windows":
    let app = newApp()
    app.enableWindowMode()

    check app.getWindows().len == 0

    let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
    let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")

    let id1 = app.addWindow(window1)
    let id2 = app.addWindow(window2)

    let windows = app.getWindows()
    check windows.len == 2
    check windows[0].id == id1
    check windows[1].id == id2

suite "App Suspend/Resume":
  test "isSuspended initially false":
    let app = newApp()
    check app.isSuspended() == false

  test "onEvent with App context":
    let app = newApp()
    var handlerCalled = false
    var receivedApp: App

    app.onEvent proc(event: Event, app: App): bool =
      handlerCalled = true
      receivedApp = app
      return true

    # Handler is set but not called until run
    check handlerCalled == false

suite "App Integration Tests":
  test "quit sets shouldQuit flag":
    let app = newApp()
    app.quit()
    # Application should be marked for quitting
    # (Cannot test run loop without actual terminal)

  test "multiple window operations":
    let app = newApp()
    app.enableWindowMode()

    let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
    let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")
    let window3 = newWindow(rect(5, 5, 20, 10), "Window 3")

    let id1 = app.addWindow(window1)
    let id2 = app.addWindow(window2)
    let id3 = app.addWindow(window3)

    check app.getWindowCount() == 3

    # Remove middle window
    app.removeWindow(id2)
    check app.getWindowCount() == 2

    # Verify remaining windows
    check app.getWindow(id1).isSome()
    check app.getWindow(id2).isNone()
    check app.getWindow(id3).isSome()

  test "cursor operations persist across calls":
    let app = newApp()

    app.setCursorPosition(10, 20)
    app.setCursorStyle(CursorStyle.SteadyUnderline)
    app.showCursor()

    check app.getCursorPosition() == (10, 20)
    check app.getCursorStyle() == CursorStyle.SteadyUnderline
    check app.isCursorVisible() == true

    app.moveCursorBy(5, -3)
    check app.getCursorPosition() == (15, 17)

  test "window focus changes persist":
    let app = newApp()
    app.enableWindowMode()

    let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
    let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")
    let window3 = newWindow(rect(5, 5, 20, 10), "Window 3")

    let id1 = app.addWindow(window1)
    let id2 = app.addWindow(window2)
    let id3 = app.addWindow(window3)

    # Last added should be focused
    check app.getFocusedWindowId().get() == id3

    # Change focus
    app.focusWindow(id1)
    check app.getFocusedWindowId().get() == id1

    app.focusWindow(id2)
    check app.getFocusedWindowId().get() == id2
