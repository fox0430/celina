## Tests for App core functionality

import std/[unittest, options, monotimes, times, strutils]

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

    check app.removeWindow(windowId) == true
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
    check app.focusWindow(id1) == true

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

  test "focusWindow with invalid ID returns false":
    let app = newApp()
    app.enableWindowMode()

    let window = newWindow(rect(10, 10, 30, 15), "Test")
    discard app.addWindow(window)

    check app.focusWindow(WindowId(999)) == false

  test "removeWindow with invalid ID returns false":
    let app = newApp()
    app.enableWindowMode()

    let window = newWindow(rect(10, 10, 30, 15), "Test")
    discard app.addWindow(window)

    check app.removeWindow(WindowId(999)) == false
    check app.getWindowCount() == 1

  test "focusWindow with no window mode returns false":
    let app = newApp()
    check app.focusWindow(WindowId(1)) == false

  test "removeWindow with no window mode returns false":
    let app = newApp()
    check app.removeWindow(WindowId(1)) == false

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
    check app.removeWindow(id2) == true
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
    check app.focusWindow(id1) == true
    check app.getFocusedWindowId().get() == id1

    check app.focusWindow(id2) == true
    check app.getFocusedWindowId().get() == id2

suite "App State and Info":
  test "isRunning initially false":
    let app = newApp()
    check app.isRunning() == false

  test "getTerminalSize returns valid size":
    let app = newApp()
    let size = app.getTerminalSize()
    check size.width > 0
    check size.height > 0

  test "getConfig returns stored config":
    let config = AppConfig(title: "Test", targetFps: 45)
    let app = newApp(config)
    check app.getConfig().title == "Test"
    check app.getConfig().targetFps == 45

  test "getConfig returns default config when not specified":
    let app = newApp()
    let storedConfig = app.getConfig()
    check storedConfig.alternateScreen == DefaultAppConfig.alternateScreen
    check storedConfig.mouseCapture == DefaultAppConfig.mouseCapture
    check storedConfig.rawMode == DefaultAppConfig.rawMode
    check storedConfig.targetFps == DefaultAppConfig.targetFps

  test "getFrameCount initially zero":
    let app = newApp()
    check app.getFrameCount() == 0

  test "getLastFrameTime returns valid MonoTime":
    let app = newApp()
    let frameTime = app.getLastFrameTime()
    # MonoTime should be set to current time at creation
    let now = getMonoTime()
    # Check that the frame time is not too far in the past (within last second)
    check (now - frameTime).inMilliseconds < 1000

suite "App handleWindowEvent":
  test "handleWindowEvent with no window mode returns false":
    let app = newApp()
    let event = Event(kind: Key)
    check app.handleWindowEvent(event) == false

  test "handleWindowEvent with window mode enabled but no handlers":
    let config = AppConfig(windowMode: true)
    let app = newApp(config)
    let event = Event(kind: Key)
    # No window has handlers, so should return false
    check app.handleWindowEvent(event) == false

  test "handleWindowEvent with window that has key handler":
    let app = newApp()
    app.enableWindowMode()

    let window = newWindow(rect(10, 10, 30, 15), "Test Window")
    window.setKeyHandler(
      proc(w: Window, k: KeyEvent): bool =
        true
    )
    let windowId = app.addWindow(window)

    # Focus the window
    discard app.focusWindow(windowId)

    let event = Event(kind: Key)
    # Window has a key handler, so should return true
    check app.handleWindowEvent(event) == true

  test "handleWindowEvent mouse event with window that has mouse handler":
    let app = newApp()
    app.enableWindowMode()

    let window = newWindow(rect(10, 10, 30, 15), "Test Window")
    window.setMouseHandler(
      proc(w: Window, m: MouseEvent): bool =
        true
    )
    discard app.addWindow(window)

    # Mouse event within window bounds
    let event = Event(kind: Mouse, mouse: MouseEvent(x: 15, y: 12))
    # Window has a mouse handler, so should return true
    check app.handleWindowEvent(event) == true

  test "handleWindowEvent resize event routes to focused window":
    let app = newApp()
    app.enableWindowMode()

    let window = newWindow(rect(10, 10, 30, 15), "Test Window")
    let windowId = app.addWindow(window)

    # Focus the window
    discard app.focusWindow(windowId)

    let event = Event(kind: Resize)
    # Resize events are routed to focused window but window has no handler
    # so returns false (resize is typically handled separately via dispatchResize)
    check app.handleWindowEvent(event) == false

suite "App String Representation":
  test "new app string representation":
    let app = newApp()
    let s = $app
    check "App(" in s
    check "running: false" in s
    check "frames: 0" in s
    check "windows: 0" in s

  test "app with window mode":
    let config = AppConfig(windowMode: true)
    let app = newApp(config)
    let s = $app
    check "windows: 0" in s
