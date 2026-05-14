## Tests for App window manager APIs

import std/[unittest, options]

import ../celina

suite "App Window Manager API Tests":
  test "getWindows with no window mode":
    let app = newApp()

    let windows = app.getWindows()
    check windows.len == 0

  test "getWindowCount with no window mode":
    let app = newApp()

    let count = app.getWindowCount()
    check count == 0

  test "getFocusedWindowId with no window mode":
    let app = newApp()

    let focusedId = app.getFocusedWindowId()
    check focusedId.isNone()

  test "getWindowInfo with no window mode":
    let app = newApp()

    let windowInfo = app.getWindowInfo(WindowId(1))
    check windowInfo.isNone()

  test "getWindows with window mode enabled":
    let config = AppConfig(windowMode: true)
    let app = newApp(config)

    # Initially no windows
    check app.getWindows().len == 0

    # Add some windows
    let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
    let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")

    let id1 = app.addWindow(window1)
    let id2 = app.addWindow(window2)

    let windows = app.getWindows()
    check windows.len == 2
    check windows[0].id == id1
    check windows[1].id == id2

  test "getWindowCount with windows":
    let config = AppConfig(windowMode: true)
    let app = newApp(config)

    check app.getWindowCount() == 0

    let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
    let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")
    let window3 = newWindow(rect(5, 5, 20, 10), "Window 3")

    discard app.addWindow(window1)
    check app.getWindowCount() == 1

    discard app.addWindow(window2)
    check app.getWindowCount() == 2

    discard app.addWindow(window3)
    check app.getWindowCount() == 3

  test "getFocusedWindowId with windows":
    let config = AppConfig(windowMode: true)
    let app = newApp(config)

    # Initially no focused window
    check app.getFocusedWindowId().isNone()

    # Add windows
    let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
    let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")

    let id1 = app.addWindow(window1)
    let id2 = app.addWindow(window2)

    # Latest added window should be focused
    let focusedId = app.getFocusedWindowId()
    check focusedId.isSome()
    check focusedId.get() == id2

    # Focus first window
    check app.focusWindow(id1) == true
    let newFocusedId = app.getFocusedWindowId()
    check newFocusedId.isSome()
    check newFocusedId.get() == id1

  test "getWindowInfo with valid window":
    let config = AppConfig(windowMode: true)
    let app = newApp(config)

    let windowArea = rect(15, 8, 40, 20)
    let window = newWindow(windowArea, "Test Window", resizable = false, modal = true)
    let windowId = app.addWindow(window)

    let windowInfo = app.getWindowInfo(windowId)
    check windowInfo.isSome()

    let info = windowInfo.get()
    check info.id == windowId
    check info.title == "Test Window"
    check info.area == windowArea
    check info.state == wsNormal
    check info.visible == true
    check info.focused == true # Should be focused since it was the last added
    check info.resizable == false
    check info.movable == true # Default value
    check info.modal == true

  test "getWindowInfo with invalid window":
    let config = AppConfig(windowMode: true)
    let app = newApp(config)

    let window = newWindow(rect(10, 10, 30, 15), "Window")
    discard app.addWindow(window)

    # Try to get info for non-existent window
    let windowInfo = app.getWindowInfo(WindowId(999))
    check windowInfo.isNone()

suite "WindowInfo Tests":
  test "toWindowInfo conversion":
    let windowArea = rect(5, 3, 25, 12)
    let window = newWindow(
      windowArea, "Convert Test", resizable = false, movable = false, modal = true
    )

    # Attach to a manager via the public API so the computed `focused`
    # getter returns true. Override fields afterwards for the test, and
    # re-align focusedWindow to the overridden id.
    let wm = newWindowManager()
    discard wm.addWindow(window)
    window.id = WindowId(42)
    window.state = wsMaximized
    window.zIndex = 5
    window.visible = false
    wm.focusedWindow = some(window.id)

    let info = window.toWindowInfo()

    check info.id == WindowId(42)
    check info.title == "Convert Test"
    check info.area == windowArea
    check info.state == wsMaximized
    check info.zIndex == 5
    check info.visible == false
    check info.focused == true
    check info.resizable == false
    check info.movable == false
    check info.modal == true

  test "WindowInfo reflects window state changes":
    let config = AppConfig(windowMode: true)
    let app = newApp(config)

    let window = newWindow(rect(10, 10, 30, 15), "Dynamic Window")
    let windowId = app.addWindow(window)

    # Get initial info
    let initialInfo = app.getWindowInfo(windowId).get()
    check initialInfo.state == wsNormal
    check initialInfo.visible == true

    # Change window state
    window.minimize()

    # Get updated info
    let updatedInfo = app.getWindowInfo(windowId).get()
    check updatedInfo.state == wsMinimized
    check updatedInfo.visible == false

    # Change title
    window.setTitle("Updated Title")
    let titleUpdatedInfo = app.getWindowInfo(windowId).get()
    check titleUpdatedInfo.title == "Updated Title"

suite "App Window Integration Tests":
  test "Window removal affects counts and focus":
    let config = AppConfig(windowMode: true)
    let app = newApp(config)

    let window1 = newWindow(rect(10, 10, 30, 15), "Window 1")
    let window2 = newWindow(rect(20, 20, 25, 12), "Window 2")
    let window3 = newWindow(rect(5, 5, 20, 10), "Window 3")

    let _ = app.addWindow(window1)
    let _ = app.addWindow(window2)
    let id3 = app.addWindow(window3)

    check app.getWindowCount() == 3
    check app.getFocusedWindowId().get() == id3

    # Remove focused window
    check app.removeWindow(id3) == true

    check app.getWindowCount() == 2
    # Focus should shift to remaining window
    let newFocused = app.getFocusedWindowId()
    check newFocused.isSome()
    check newFocused.get() != id3

    # Window info should no longer exist
    check app.getWindowInfo(id3).isNone()

  test "App without window manager handles gracefully":
    let app = newApp() # windowMode = false by default

    # All APIs should return safe empty values
    check app.getWindows().len == 0
    check app.getWindowCount() == 0
    check app.getFocusedWindowId().isNone()
    check app.getWindowInfo(WindowId(1)).isNone()
    check app.getFocusedWindow().isNone()

  test "App.addWindow autoFocus parameter":
    let config = AppConfig(windowMode: true)
    let app = newApp(config)

    # First window is always focused regardless of autoFocus.
    let first = newWindow(rect(0, 0, 10, 10), "First")
    let firstId = app.addWindow(first, autoFocus = false)
    check first.focused == true
    check app.getFocusedWindowId() == some(firstId)

    # autoFocus = false keeps the existing focus.
    let second = newWindow(rect(10, 10, 10, 10), "Second")
    discard app.addWindow(second, autoFocus = false)
    check first.focused == true
    check second.focused == false

    # autoFocus = true (default) takes focus.
    let third = newWindow(rect(20, 20, 10, 10), "Third")
    let thirdId = app.addWindow(third)
    check third.focused == true
    check first.focused == false
    check app.getFocusedWindowId() == some(thirdId)

  test "App.addWindow forces focus for modal windows":
    let config = AppConfig(windowMode: true)
    let app = newApp(config)

    let first = newWindow(rect(0, 0, 10, 10), "First")
    discard app.addWindow(first)
    check first.focused == true

    # Modal window must take focus even with autoFocus = false.
    let dialog = newWindow(rect(5, 5, 10, 10), "Dialog", modal = true)
    let dialogId = app.addWindow(dialog, autoFocus = false)
    check dialog.focused == true
    check first.focused == false
    check app.getFocusedWindowId() == some(dialogId)
