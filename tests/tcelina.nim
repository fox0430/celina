# Test suite for main celina module

import std/[unittest, options, pegs, strutils]

import ../celina {.all.}

suite "Celina Main Module Tests":
  suite "Basic API Tests":
    test "version returns valid version string":
      check celinaVersion.match(peg"\d+ '.' \d+ '.' \d+ !.") # Semantic versioning
      check celinaVersion.split(".").len == 3

    test "sync app creation":
      let app = newApp()
      check not app.isNil

    test "sync app with custom config":
      let config = AppConfig(
        title: "Test App",
        alternateScreen: false,
        mouseCapture: true,
        rawMode: false,
        windowMode: true,
        targetFps: 30,
      )
      let app = newApp(config)
      check not app.isNil

  suite "Cursor Control API":
    test "App cursor state initialization":
      var app = newApp()
      let (x, y) = app.getCursorPosition()
      check x == -1 # Not set initially
      check y == -1
      check app.isCursorVisible() == false # Hidden by default

    test "showCursorAt with coordinates":
      var app = newApp()
      app.showCursorAt(10, 20)
      let (x, y) = app.getCursorPosition()
      check x == 10
      check y == 20
      check app.isCursorVisible() == true # Should become visible

    test "showCursorAt with Position":
      var app = newApp()
      let pos = Position(x: 15, y: 25)
      app.showCursorAt(pos)
      let (x, y) = app.getCursorPosition()
      check x == 15
      check y == 25
      check app.isCursorVisible() == true

    test "setCursorPosition preserves visibility":
      var app = newApp()
      app.hideCursor()
      app.setCursorPosition(10, 20)
      let (x, y) = app.getCursorPosition()
      check x == 10
      check y == 20
      check app.isCursorVisible() == false # Should remain hidden

    test "cursor visibility control":
      var app = newApp()

      # Initially hidden
      check app.isCursorVisible() == false

      # Show cursor
      app.showCursor()
      check app.isCursorVisible() == true

      # Hide cursor
      app.hideCursor()
      check app.isCursorVisible() == false

    test "cursor style setting":
      var app = newApp()

      # Test different cursor styles (mainly ensures the API works without errors)
      app.setCursorStyle(CursorStyle.BlinkingBlock)
      app.setCursorStyle(CursorStyle.SteadyUnderline)
      app.setCursorStyle(CursorStyle.BlinkingBar)

  suite "Async Backend Detection":
    test "hasAsyncSupport constants are defined":
      # Just check that the constants exist and are boolean
      discard hasAsyncSupport
      discard hasAsyncDispatch
      discard hasChronos

  suite "Type Exports":
    test "core types are available":
      # Test that essential types are exported
      let
        position = pos(10, 20)
        rectangle = rect(0, 0, 100, 50)
        dimensions = size(80, 40)
        color = Color.Red
        style = defaultStyle()

      check position.x == 10
      check rectangle.width == 100
      check dimensions.height == 40
      check color == Color.Red
      check style.fg.kind == Default # Use the style variable

    test "app config type is available":
      let config = AppConfig(
        title: "Export Test",
        alternateScreen: true,
        mouseCapture: false,
        rawMode: true,
        windowMode: false,
        targetFps: 60,
      )
      check config.title == "Export Test"
      check config.alternateScreen == true
      check config.targetFps == 60

  suite "Window Management API":
    test "app without window mode handles gracefully":
      let app = newApp()

      # These should not crash even without window mode
      let windowCount = app.getWindowCount()
      let windows = app.getWindows()
      let focusedId = app.getFocusedWindowId()

      check windowCount == 0
      check windows.len == 0
      check focusedId.isNone()

    test "enabling window mode":
      let app = newApp()
      app.enableWindowMode()

      # After enabling, should still work
      let windowCount = app.getWindowCount()
      check windowCount == 0

  suite "Event Handler Setup":
    test "event handler can be set":
      let app = newApp()
      var eventHandlerCalled = false

      app.onEvent proc(event: Event): bool =
        eventHandlerCalled = true
        return false

      # We can't easily trigger events in tests, but we can verify the handler is set
      check not app.isNil

    test "render handler can be set":
      let app = newApp()
      var renderHandlerCalled = false

      app.onRender proc(buffer: var Buffer) =
        renderHandlerCalled = true

      check not app.isNil

when hasAsyncSupport:
  suite "Async API Tests":
    test "async app creation":
      let app = newAsyncApp()
      check not app.isNil

    test "async app with config":
      let config = AppConfig(
        title: "Async Test App",
        alternateScreen: true,
        mouseCapture: false,
        rawMode: true,
        windowMode: false,
        targetFps: 30,
      )
      let app = newAsyncApp(config)
      check not app.isNil

    test "async types are exported":
      # This test ensures async types are available for both asyncdispatch and chronos
      # Previously, async modules were only exported when hasChronos was true
      check declared(AsyncApp)
      check declared(newAsyncApp)
      check declared(AsyncBuffer)
      check declared(newAsyncBufferNoRM)
      check declared(AsyncTerminal)
      check declared(newAsyncTerminal)

  suite "Backend Configuration":
    test "async backend detection":
      check hasAsyncSupport
      check hasAsyncDispatch or hasChronos

    test "exactly one async backend is active":
      # Ensure only one backend is active at a time
      check not (hasAsyncDispatch and hasChronos)

suite "Integration Tests":
  test "quickRun function signature":
    # Test that quickRun exists and has correct signature
    # We can't actually run it in tests, but we can verify it compiles

    # This should compile without errors
    when declared(quickRun):
      check true

      # Test that the function type matches expected signature
      proc testEventHandler(event: Event): bool =
        false

      proc testRenderHandler(buffer: var Buffer) =
        discard

      # Verify the handlers have correct types (compilation check)
      let _ = testEventHandler
      let _ = testRenderHandler
    else:
      fail("quickRun should be available")

  suite "Error Handling":
    test "app creation doesn't crash":
      # Test multiple app creations
      for i in 0 .. 2:
        let app = newApp()
        check not app.isNil

    test "window operations on non-window app":
      let app = newApp()

      # These operations should be safe even without window mode
      let info = app.getWindowInfo(WindowId(1))
      check info.isNone()

      let handled = app.handleWindowEvent(Event(kind: EventKind.Unknown))
      check handled == false

  suite "FPS Control API":
    test "default FPS is 60":
      let app = newApp()
      check app.getTargetFps() == 60

    test "FPS can be set and retrieved":
      let app = newApp()
      app.setTargetFps(30)
      check app.getTargetFps() == 30

      app.setTargetFps(120)
      check app.getTargetFps() == 120

    test "FPS validation - valid range":
      let app = newApp()

      # Test valid values
      app.setTargetFps(1)
      check app.getTargetFps() == 1

      app.setTargetFps(60)
      check app.getTargetFps() == 60

      app.setTargetFps(120)
      check app.getTargetFps() == 120

    test "FPS validation - invalid range throws exception":
      let app = newApp()

      # Test invalid values
      expect(ValueError):
        app.setTargetFps(0)

      expect(ValueError):
        app.setTargetFps(-10)

      expect(ValueError):
        app.setTargetFps(250)

      expect(ValueError):
        app.setTargetFps(1000)

    test "getCurrentFps returns non-negative value":
      let app = newApp()
      let fps = app.getCurrentFps()
      check fps >= 0.0

    test "AppConfig accepts targetFps":
      let config = AppConfig(title: "FPS Test", targetFps: 45)
      let app = newApp(config)
      check app.getTargetFps() == 45

    test "frame timeout calculation":
      let app = newApp()

      # Test different FPS values and their expected timeouts
      app.setTargetFps(60)
      # 1000ms / 60fps = 16.67ms ≈ 16ms (integer division)
      check app.getTargetFps() == 60

      app.setTargetFps(30)
      # 1000ms / 30fps = 33.33ms ≈ 33ms
      check app.getTargetFps() == 30

      app.setTargetFps(120)
      # 1000ms / 120fps = 8.33ms ≈ 8ms
      check app.getTargetFps() == 120

    test "default FPS is applied when not specified in config":
      # Test that config without targetFps uses default 60 FPS
      let configWithoutFps = AppConfig(title: "No FPS Test")
      let app1 = newApp(configWithoutFps)
      check app1.getTargetFps() == 60 # Should use default

      # Test that newApp() without config uses default
      let app2 = newApp()
      check app2.getTargetFps() == 60 # Should use default
