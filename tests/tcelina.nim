# Test suite for main celina module

import std/[unittest, strutils, options]

import ../celina

suite "Celina Main Module Tests":
  suite "Basic API Tests":
    test "version returns valid version string":
      let ver = version()
      check ver.len > 0
      check "." in ver # Should contain at least one dot for semantic versioning

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
      )
      let app = newApp(config)
      check not app.isNil

  suite "Async Backend Detection":
    test "asyncBackend constant exists":
      check asyncBackend.len > 0
      check asyncBackend in ["none", "chronos"]

    test "hasAsyncSupport reflects backend status":
      when asyncBackend == "none":
        check hasAsyncSupport == false
      elif asyncBackend == "chronos":
        check hasAsyncSupport == true

    test "hasChronos reflects chronos backend":
      when asyncBackend == "chronos":
        check hasChronos == true
      else:
        check hasChronos == false

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
      )
      check config.title == "Export Test"
      check config.alternateScreen == true

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

when hasAsyncSupport and hasChronos:
  suite "Async API Tests":
    test "async app creation":
      let app = newAsyncApp()
      check not app.isNil

    test "async app with config":
      let config = AsyncAppConfig(
        title: "Async Test App",
        alternateScreen: true,
        mouseCapture: false,
        rawMode: true,
        windowMode: false,
        targetFps: 30,
      )
      let app = newAsyncApp(config)
      check not app.isNil

    test "async performance monitor":
      let monitor = newAsyncPerfMonitor()
      check not monitor.isNil

      # Test initial values
      check monitor.getFPS() >= 0.0
      check monitor.getEventRate() >= 0.0

    test "async utility functions":
      # Test asyncToSync utility (with a simple future)
      proc simpleAsync(): Future[int] {.async.} =
        return 42

      let result = asyncToSync(simpleAsync())
      check result == 42

  suite "Backend Configuration":
    test "async backend is chronos when enabled":
      check asyncBackend == "chronos"
      check hasAsyncSupport == true
      check hasChronos == true
else:
  suite "Sync-Only Mode Tests":
    test "async backend is none":
      check asyncBackend == "none"
      check hasAsyncSupport == false
      check hasChronos == false

    test "no async types available":
      # In sync-only mode, async types should not be available
      # This is enforced at compile time
      when declared(AsyncApp):
        fail("AsyncApp should not be available without async backend")
      else:
        check true # Expected behavior

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

  suite "Module Documentation":
    test "version is semantic":
      let ver = version()
      let parts = ver.split('.')
      check parts.len >= 2 # At least major.minor

      # Check that parts are numeric (or at least start with numbers)
      for part in parts:
        check part.len > 0
        check part[0].isDigit()

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
