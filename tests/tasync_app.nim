## Tests for AsyncApp

import std/[unittest, options]

import ../celina/async/async_backend

when hasAsyncSupport:
  import ../celina/async/async_app
  import ../celina/async/async_buffer as celina_async_buffer
  import ../celina/core/[geometry, events, windows]

  # Alias for clarity
  type CelinaAsyncBuffer = celina_async_buffer.AsyncBuffer

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

      app.onRenderAsync proc(buffer: CelinaAsyncBuffer): Future[void] {.async.} =
        handlerCalled = true

      # Handler is set but not called until run
      check handlerCalled == false

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
    test "getWindowAsync with no window mode":
      let app = newAsyncApp()
      let windowOpt = waitFor app.getWindowAsync(WindowId(1))
      check windowOpt.isNone()

    test "focusWindowAsync with no window mode":
      let app = newAsyncApp()
      let result = waitFor app.focusWindowAsync(WindowId(1))
      check result == false

    test "removeWindowAsync with no window mode":
      let app = newAsyncApp()
      let result = waitFor app.removeWindowAsync(WindowId(1))
      check result == false

    test "getFocusedWindowAsync with no window mode":
      let app = newAsyncApp()
      let windowOpt = waitFor app.getFocusedWindowAsync()
      check windowOpt.isNone()

  suite "AsyncApp Window Management - Window Mode Enabled":
    test "enableWindowMode enables window management":
      let app = newAsyncApp()
      app.enableWindowMode()
      # Window mode enabled successfully (no crash)

    test "addWindowAsync with window mode":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let window = newWindow(rect(10, 10, 30, 15), "Test Window")
      let windowId = waitFor app.addWindowAsync(window)
      check windowId.int > 0

    test "addWindowAsync enables window mode if not enabled":
      let app = newAsyncApp() # windowMode = false

      let window = newWindow(rect(10, 10, 30, 15), "Test Window")
      let windowId = waitFor app.addWindowAsync(window)
      check windowId.int > 0

    test "getWindowAsync retrieves added window":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let window = newWindow(rect(10, 10, 30, 15), "Test Window")
      let windowId = waitFor app.addWindowAsync(window)

      let retrievedOpt = waitFor app.getWindowAsync(windowId)
      check retrievedOpt.isSome()
      check retrievedOpt.get().title == "Test Window"

    test "getWindowAsync with invalid ID returns none":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let windowOpt = waitFor app.getWindowAsync(WindowId(999))
      check windowOpt.isNone()

    test "removeWindowAsync removes window":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let window = newWindow(rect(10, 10, 30, 15), "Test Window")
      let windowId = waitFor app.addWindowAsync(window)

      # Verify window exists
      var windowOpt = waitFor app.getWindowAsync(windowId)
      check windowOpt.isSome()

      # Remove window
      let removed = waitFor app.removeWindowAsync(windowId)
      check removed == true

      # Verify window no longer exists
      windowOpt = waitFor app.getWindowAsync(windowId)
      check windowOpt.isNone()

    test "focusWindowAsync focuses window":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
      let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")

      let id1 = waitFor app.addWindowAsync(window1)
      discard waitFor app.addWindowAsync(window2)

      # Focus first window
      let focused = waitFor app.focusWindowAsync(id1)
      check focused == true

      # Verify focused window
      let focusedOpt = waitFor app.getFocusedWindowAsync()
      check focusedOpt.isSome()
      check focusedOpt.get().id == id1

    test "getFocusedWindowAsync with multiple windows":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
      let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")

      let id1 = waitFor app.addWindowAsync(window1)
      discard waitFor app.addWindowAsync(window2)

      # First window should be focused (async behavior differs from sync)
      let focusedOpt = waitFor app.getFocusedWindowAsync()
      check focusedOpt.isSome()
      check focusedOpt.get().id == id1

  suite "AsyncApp Integration Tests":
    test "multiple windows management":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
      let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")
      let window3 = newWindow(rect(5, 5, 20, 10), "Window 3")

      let id1 = waitFor app.addWindowAsync(window1)
      let id2 = waitFor app.addWindowAsync(window2)
      let id3 = waitFor app.addWindowAsync(window3)

      # All windows should exist
      check (waitFor app.getWindowAsync(id1)).isSome()
      check (waitFor app.getWindowAsync(id2)).isSome()
      check (waitFor app.getWindowAsync(id3)).isSome()

      # Remove middle window
      let removed = waitFor app.removeWindowAsync(id2)
      check removed == true

      # Verify removal
      check (waitFor app.getWindowAsync(id1)).isSome()
      check (waitFor app.getWindowAsync(id2)).isNone()
      check (waitFor app.getWindowAsync(id3)).isSome()

    test "window focus management with multiple windows":
      let config = AppConfig(windowMode: true)
      let app = newAsyncApp(config)

      let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
      let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")

      let id1 = waitFor app.addWindowAsync(window1)
      let id2 = waitFor app.addWindowAsync(window2)

      # First window should be focused initially (async behavior)
      var focusedOpt = waitFor app.getFocusedWindowAsync()
      check focusedOpt.isSome()
      check focusedOpt.get().id == id1

      # Focus second window
      discard waitFor app.focusWindowAsync(id2)
      focusedOpt = waitFor app.getFocusedWindowAsync()
      check focusedOpt.isSome()
      check focusedOpt.get().id == id2

      # Focus first window
      discard waitFor app.focusWindowAsync(id1)
      focusedOpt = waitFor app.getFocusedWindowAsync()
      check focusedOpt.isSome()
      check focusedOpt.get().id == id1

  suite "AsyncApp quitAsync":
    test "quitAsync sets running to false":
      let app = newAsyncApp()

      # Initially not running
      check app.isRunning() == false

      # Quit should work even if not running
      waitFor app.quitAsync()
      check app.isRunning() == false
else:
  echo "Skipping AsyncApp tests - no async backend available"
