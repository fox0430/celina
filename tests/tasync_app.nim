## Tests for AsyncApp

import std/[unittest, options]

import ../celina/async/async_backend

when hasAsyncSupport:
  import ../celina/async/async_app
  import ../celina/core/[geometry, events, windows, buffer, terminal_common]

  suite "AsyncApp Creation and Configuration":
    test "newAsyncApp with default config":
      let app = newAsyncApp()
      check app.isRunning() == false
      check app.getFrameCount() == 0

    test "newAsyncApp with custom config":
      let config = AppConfig(
        title: "Test App",
        alternateScreen: false,
        mouseCapture: true,
        rawMode: false,
        windowMode: true,
        targetFps: 30,
      )
      let app = newAsyncApp(config)
      check app.isRunning() == false
      check app.getFrameCount() == 0

    test "newAsyncApp stores config for use by runAsync":
      ## Regression test: config passed to newAsyncApp should be stored
      ## and used by runAsync (GitHub issue: config not stored bug)
      let config = AppConfig(
        title: "Stored Config Test",
        alternateScreen: true,
        mouseCapture: true,
        rawMode: true,
        bracketedPaste: true,
        windowMode: false,
        targetFps: 45,
      )
      let app = newAsyncApp(config)

      # Verify config is stored and accessible
      let storedConfig = app.getConfig()
      check storedConfig.title == "Stored Config Test"
      check storedConfig.alternateScreen == true
      check storedConfig.mouseCapture == true
      check storedConfig.rawMode == true
      check storedConfig.bracketedPaste == true
      check storedConfig.windowMode == false
      check storedConfig.targetFps == 45

    test "getConfig returns same config passed to newAsyncApp":
      ## Verify that getConfig returns exactly the config passed to newAsyncApp
      let config = AppConfig(mouseCapture: true, targetFps: 120)
      let app = newAsyncApp(config)

      check app.getConfig().mouseCapture == config.mouseCapture
      check app.getConfig().targetFps == config.targetFps

    test "default config is stored when no config provided":
      let app = newAsyncApp()
      let storedConfig = app.getConfig()

      # Should match DefaultAppConfig values
      check storedConfig.alternateScreen == DefaultAppConfig.alternateScreen
      check storedConfig.mouseCapture == DefaultAppConfig.mouseCapture
      check storedConfig.rawMode == DefaultAppConfig.rawMode
      check storedConfig.targetFps == DefaultAppConfig.targetFps

  suite "AsyncApp Event and Render Handlers":
    test "onEventAsync sets event handler":
      let app = newAsyncApp()
      var handlerCalled = false

      app.onEventAsync proc(event: Event): Future[bool] {.async.} =
        handlerCalled = true
        return true

      # Handler is set but not called until run
      check handlerCalled == false

    test "onRenderAsync sets render handler":
      let app = newAsyncApp()
      var handlerCalled = false

      app.onRenderAsync proc(buffer: var Buffer) =
        handlerCalled = true

      # Handler is set but not called until run
      check handlerCalled == false

    test "onTickAsync sets tick handler":
      let app = newAsyncApp()
      var handlerCalled = false

      app.onTickAsync proc(): Future[bool] {.async.} =
        handlerCalled = true
        return true

      # Handler is set but not called until run
      check handlerCalled == false

    test "onTickAsync with AsyncApp context sets tick handler":
      let app = newAsyncApp()
      var handlerCalled = false

      app.onTickAsync proc(app: AsyncApp): Future[bool] {.async.} =
        handlerCalled = true
        return true

      # Handler is set but not called until run
      check handlerCalled == false

    test "onTickAsync overloads are mutually exclusive":
      let app = newAsyncApp()
      var simpleCalled = false
      var appCalled = false

      # Set simple handler first
      app.onTickAsync proc(): Future[bool] {.async.} =
        simpleCalled = true
        return true

      # Setting App-context handler should clear simple handler
      app.onTickAsync proc(app: AsyncApp): Future[bool] {.async.} =
        appCalled = true
        return true

      # Now set simple handler again, should clear App-context handler
      app.onTickAsync proc(): Future[bool] {.async.} =
        simpleCalled = true
        return true

      check simpleCalled == false
      check appCalled == false

  suite "AsyncApp State Management":
    test "isRunning returns false before run":
      let app = newAsyncApp()
      check app.isRunning() == false

    test "getFrameCount starts at zero":
      let app = newAsyncApp()
      check app.getFrameCount() == 0

    test "getTerminalSize returns valid size":
      let app = newAsyncApp()
      let size = app.getTerminalSize()
      check size.width > 0
      check size.height > 0

  suite "AsyncApp Window Management - No Window Mode":
    test "getWindow with no window mode":
      let app = newAsyncApp()
      let windowOpt = app.getWindow(WindowId(1))
      check windowOpt.isNone()

    test "focusWindow with no window mode":
      let app = newAsyncApp()
      let result = app.focusWindow(WindowId(1))
      check result == false

    test "removeWindow with no window mode":
      let app = newAsyncApp()
      let result = app.removeWindow(WindowId(1))
      check result == false

    test "getFocusedWindow with no window mode":
      let app = newAsyncApp()
      let windowOpt = app.getFocusedWindow()
      check windowOpt.isNone()

  suite "AsyncApp Window Management - Window Mode Enabled":
    test "enableWindowMode enables window management":
      let app = newAsyncApp()
      app.enableWindowMode()
      # Window mode enabled successfully (no crash)

    test "addWindow with window mode":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let window = newWindow(rect(10, 10, 30, 15), "Test Window")
      let windowId = app.addWindow(window)
      check windowId.int > 0

    test "addWindow enables window mode if not enabled":
      let app = newAsyncApp() # windowMode = false

      let window = newWindow(rect(10, 10, 30, 15), "Test Window")
      let windowId = app.addWindow(window)
      check windowId.int > 0

    test "getWindow retrieves added window":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let window = newWindow(rect(10, 10, 30, 15), "Test Window")
      let windowId = app.addWindow(window)

      let retrievedOpt = app.getWindow(windowId)
      check retrievedOpt.isSome()
      check retrievedOpt.get().title == "Test Window"

    test "getWindow with invalid ID returns none":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let windowOpt = app.getWindow(WindowId(999))
      check windowOpt.isNone()

    test "removeWindow removes window":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let window = newWindow(rect(10, 10, 30, 15), "Test Window")
      let windowId = app.addWindow(window)

      # Verify window exists
      var windowOpt = app.getWindow(windowId)
      check windowOpt.isSome()

      # Remove window
      let removed = app.removeWindow(windowId)
      check removed == true

      # Verify window no longer exists
      windowOpt = app.getWindow(windowId)
      check windowOpt.isNone()

    test "focusWindow focuses window":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
      let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")

      let id1 = app.addWindow(window1)
      discard app.addWindow(window2)

      # Focus first window
      let focused = app.focusWindow(id1)
      check focused == true

      # Verify focused window
      let focusedOpt = app.getFocusedWindow()
      check focusedOpt.isSome()
      check focusedOpt.get().id == id1

    test "getFocusedWindow with multiple windows":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
      let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")

      let id1 = app.addWindow(window1)
      discard app.addWindow(window2)

      # First window should be focused
      let focusedOpt = app.getFocusedWindow()
      check focusedOpt.isSome()
      check focusedOpt.get().id == id1

  suite "AsyncApp Integration Tests":
    test "multiple windows management":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
      let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")
      let window3 = newWindow(rect(5, 5, 20, 10), "Window 3")

      let id1 = app.addWindow(window1)
      let id2 = app.addWindow(window2)
      let id3 = app.addWindow(window3)

      # All windows should exist
      check app.getWindow(id1).isSome()
      check app.getWindow(id2).isSome()
      check app.getWindow(id3).isSome()

      # Remove middle window
      let removed = app.removeWindow(id2)
      check removed == true

      # Verify removal
      check app.getWindow(id1).isSome()
      check app.getWindow(id2).isNone()
      check app.getWindow(id3).isSome()

    test "window focus management with multiple windows":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
      let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")

      let id1 = app.addWindow(window1)
      let id2 = app.addWindow(window2)

      # First window should be focused initially
      var focusedOpt = app.getFocusedWindow()
      check focusedOpt.isSome()
      check focusedOpt.get().id == id1

      # Focus second window
      discard app.focusWindow(id2)
      focusedOpt = app.getFocusedWindow()
      check focusedOpt.isSome()
      check focusedOpt.get().id == id2

      # Focus first window
      discard app.focusWindow(id1)
      focusedOpt = app.getFocusedWindow()
      check focusedOpt.isSome()
      check focusedOpt.get().id == id1

  suite "AsyncApp Window APIs":
    test "getWindows returns all windows":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
      let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")
      let window3 = newWindow(rect(5, 5, 20, 10), "Window 3")

      discard app.addWindow(window1)
      discard app.addWindow(window2)
      discard app.addWindow(window3)

      let windows = app.getWindows()
      check windows.len == 3

    test "getWindows with no window mode returns empty":
      let app = newAsyncApp()
      let windows = app.getWindows()
      check windows.len == 0

    test "getWindowCount returns correct count":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      check app.getWindowCount() == 0

      let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
      let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")

      discard app.addWindow(window1)
      check app.getWindowCount() == 1

      discard app.addWindow(window2)
      check app.getWindowCount() == 2

    test "getWindowCount with no window mode returns zero":
      let app = newAsyncApp()
      check app.getWindowCount() == 0

    test "getFocusedWindowId returns focused window ID":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      # No window initially
      check app.getFocusedWindowId().isNone()

      let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
      let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")

      let id1 = app.addWindow(window1)
      check app.getFocusedWindowId().isSome()
      check app.getFocusedWindowId().get() == id1

      discard app.addWindow(window2)
      # First window should still be focused
      check app.getFocusedWindowId().get() == id1

    test "getFocusedWindowId with no window mode returns none":
      let app = newAsyncApp()
      check app.getFocusedWindowId().isNone()

    test "getWindowInfo returns window information":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let windowArea = rect(15, 8, 40, 20)
      let window = newWindow(windowArea, "Test Window", resizable = false, modal = true)
      let windowId = app.addWindow(window)

      let windowInfo = app.getWindowInfo(windowId)
      check windowInfo.isSome()

      let info = windowInfo.get()
      check info.id == windowId
      check info.title == "Test Window"
      check info.area == windowArea
      check info.resizable == false
      check info.modal == true

    test "getWindowInfo with invalid ID returns none":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let windowInfo = app.getWindowInfo(WindowId(999))
      check windowInfo.isNone()

    test "getWindowInfo with no window mode returns none":
      let app = newAsyncApp()
      check app.getWindowInfo(WindowId(1)).isNone()

  suite "AsyncApp quit":
    test "quit sets running to false":
      let app = newAsyncApp()

      # Initially not running
      check app.isRunning() == false

      # Quit should work even if not running
      app.quit()
      check app.isRunning() == false

  suite "AsyncApp Cursor Management":
    test "cursor is hidden by default":
      let app = newAsyncApp()
      check app.isCursorVisible() == false

    test "showCursorAt sets position and visibility":
      let app = newAsyncApp()
      app.showCursorAt(10, 5)
      check app.isCursorVisible() == true
      check app.getCursorPosition() == (10, 5)

    test "showCursorAt with Position type":
      let app = newAsyncApp()
      app.showCursorAt(pos(20, 15))
      check app.isCursorVisible() == true
      check app.getCursorPosition() == (20, 15)

    test "hideCursor hides cursor":
      let app = newAsyncApp()
      app.showCursorAt(10, 5)
      check app.isCursorVisible() == true
      app.hideCursor()
      check app.isCursorVisible() == false

    test "showCursor shows cursor without changing position":
      let app = newAsyncApp()
      app.setCursorPosition(15, 10)
      app.showCursor()
      check app.isCursorVisible() == true
      check app.getCursorPosition() == (15, 10)

    test "setCursorPosition sets position without changing visibility":
      let app = newAsyncApp()
      app.setCursorPosition(5, 3)
      check app.getCursorPosition() == (5, 3)
      check app.isCursorVisible() == false # Still hidden

    test "setCursorPosition with Position type":
      let app = newAsyncApp()
      app.setCursorPosition(pos(8, 12))
      check app.getCursorPosition() == (8, 12)

    test "moveCursorBy moves cursor relatively":
      let app = newAsyncApp()
      app.setCursorPosition(10, 10)
      app.moveCursorBy(5, -3)
      check app.getCursorPosition() == (15, 7)

    test "setCursorStyle changes cursor style":
      let app = newAsyncApp()
      check app.getCursorStyle() == CursorStyle.Default
      app.setCursorStyle(CursorStyle.BlinkingBar)
      check app.getCursorStyle() == CursorStyle.BlinkingBar

    test "resetCursor resets to default state":
      let app = newAsyncApp()
      app.showCursorAt(10, 5)
      app.setCursorStyle(CursorStyle.SteadyBlock)
      app.resetCursor()
      check app.isCursorVisible() == false
      check app.getCursorPosition() == (-1, -1)
      check app.getCursorStyle() == CursorStyle.Default

  suite "AsyncApp handleWindowEvent":
    test "handleWindowEvent with no window mode returns false":
      let app = newAsyncApp()
      let event = Event(kind: Key)
      check app.handleWindowEvent(event) == false

    test "handleWindowEvent with window mode enabled but no handlers":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)
      let event = Event(kind: Key)
      # No window has handlers, so should return false
      check app.handleWindowEvent(event) == false

    test "handleWindowEvent with window that has key handler":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

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
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

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

    test "handleWindowEvent resize event":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let window = newWindow(rect(10, 10, 30, 15), "Test Window")
      window.setResizeHandler(
        proc(w: Window, newSize: Size): bool =
          true
      )
      discard app.addWindow(window)

      let event = Event(kind: Resize)
      # Resize events are handled separately via dispatchResize, not handleEvent
      # This is consistent with sync WindowManager behavior
      check app.handleWindowEvent(event) == false
else:
  echo "Skipping AsyncApp tests - no async backend available"
