# Test suite for async_windows module

import std/[unittest, options]

import ../celina/async/[async_backend, async_windows, async_buffer]
import ../celina/core/[geometry, colors, events, buffer]
import ../celina/core/windows

suite "AsyncWindows Core Tests":
  test "AsyncWindowManager creation":
    let awm = newAsyncWindowManager()
    check awm != nil

    let stats = awm.getStats()
    check stats.windowCount == 0
    check stats.focusedId == -1
    # Note: stats.locked is always true during getStats() call due to withLock template

  test "Window creation without AsyncWindowManager":
    let window = newWindow(rect(10, 10, 20, 15), "Test Window")
    check window != nil
    check window.title == "Test Window"
    check window.area == rect(10, 10, 20, 15)

  test "Thread safety indicators":
    let awm = newAsyncWindowManager()
    discard awm.getStats() # Just verify it doesn't crash
    # Note: stats.locked is always true during getStats() call due to withLock template

suite "AsyncWindows Synchronous Operations":
  test "Synchronous window operations":
    let awm = newAsyncWindowManager()
    discard newWindow(rect(5, 5, 30, 20), "Sync Window")

    # Test synchronous getWindowSync (before window is added)
    let emptyResult = awm.getWindowSync(WindowId(1))
    check emptyResult.isNone()

suite "AsyncWindows Type and Configuration Tests":
  test "AsyncWindowManager basic properties":
    let awm = newAsyncWindowManager()
    check awm != nil

    let initialStats = awm.getStats()
    check initialStats.windowCount == 0
    check initialStats.focusedId == -1

  test "Window creation and basic properties":
    let window = newWindow(rect(5, 5, 30, 20), "Test Window")
    check window != nil
    check window.title == "Test Window"
    check window.area == rect(5, 5, 30, 20)
    check window.visible == true # Default visibility

  test "AsyncBuffer compatibility":
    let asyncBuffer = newAsyncBuffer(40, 30)
    check asyncBuffer != nil
    check asyncBuffer.getSize() == size(40, 30)

  test "Window border configuration":
    let window = newWindow(rect(10, 10, 20, 15), "Border Window")

    # Test setting border
    window.border = some(
      WindowBorder(
        top: true,
        right: true,
        bottom: true,
        left: true,
        style: defaultStyle(),
        chars: BorderChars(
          horizontal: "-",
          vertical: "|",
          topLeft: "+",
          topRight: "+",
          bottomLeft: "+",
          bottomRight: "+",
        ),
      )
    )

    check window.border.isSome()
    let border = window.border.get()
    check border.top == true
    check border.chars.horizontal == "-"

suite "AsyncWindows Error Handling (Sync Tests)":
  test "Invalid WindowId handling":
    let awm = newAsyncWindowManager()
    let invalidId = WindowId(-1)

    # Test synchronous getWindowSync with invalid ID
    let windowOpt = awm.getWindowSync(invalidId)
    check windowOpt.isNone()

  test "Nil window detection":
    # Test nil window creation scenarios
    let awm = newAsyncWindowManager()
    check awm != nil

    # Test that we can detect when operations would fail
    let invalidWindow: Window = nil
    check invalidWindow.isNil

suite "AsyncWindows Configuration and Types":
  test "WindowId type handling":
    let id1 = WindowId(1)
    let id2 = WindowId(2)

    check id1.int == 1
    check id2.int == 2
    check id1 != id2

  test "Window state management":
    let window = newWindow(rect(0, 0, 10, 10), "State Window")

    # Test initial state
    check window.visible == true
    check window.focused == false

    # Test state changes
    window.visible = false
    check window.visible == false

    window.focused = true
    check window.focused == true

suite "AsyncWindows Event Types":
  test "Event type construction":
    # Test that we can create events for async handling
    let keyEvent = Event(kind: Key, key: KeyEvent(code: Char, char: "a"))
    check keyEvent.kind == Key
    check keyEvent.key.char == "a"

    let mouseEvent = Event(
      kind: Mouse,
      mouse: MouseEvent(
        x: 10,
        y: 10,
        button: MouseButton.Left,
        kind: MouseEventKind.Press,
        modifiers: {},
      ),
    )
    check mouseEvent.kind == Mouse
    check mouseEvent.mouse.x == 10
    check mouseEvent.mouse.y == 10

    let resizeEvent = Event(kind: Resize)
    check resizeEvent.kind == Resize

suite "AsyncWindows Synchronous Rendering":
  test "renderSync basic functionality":
    let awm = newAsyncWindowManager()
    var destBuffer = newBuffer(rect(0, 0, 80, 24))

    # Test rendering empty window manager
    awm.renderSync(destBuffer)
    check destBuffer.area.width == 80
    check destBuffer.area.height == 24

  test "renderSync with single window":
    let awm = newAsyncWindowManager()
    let window = newWindow(rect(5, 5, 20, 10), "Test Window")
    var destBuffer = newBuffer(rect(0, 0, 80, 24))

    # Add window synchronously (we can't use async here)
    # Instead, we test the internal structure
    check window.title == "Test Window"
    check window.area == rect(5, 5, 20, 10)

    # Test that renderSync doesn't crash with empty manager
    awm.renderSync(destBuffer)

  test "renderSync with window border":
    let awm = newAsyncWindowManager()
    let window = newWindow(rect(10, 10, 25, 15), "Border Window")

    # Set up window with border
    window.border = some(
      WindowBorder(
        top: true,
        right: true,
        bottom: true,
        left: true,
        style: Style(fg: color(White)),
        chars: BorderChars(
          horizontal: "-",
          vertical: "|",
          topLeft: "+",
          topRight: "+",
          bottomLeft: "+",
          bottomRight: "+",
        ),
      )
    )

    var destBuffer = newBuffer(rect(0, 0, 80, 24))

    # Verify border is configured
    check window.border.isSome()
    let border = window.border.get()
    check border.top == true
    check border.chars.horizontal == "-"

    # Test renderSync doesn't crash
    awm.renderSync(destBuffer)

  test "renderSync buffer compatibility":
    let awm = newAsyncWindowManager()

    # Test with different buffer sizes
    var smallBuffer = newBuffer(rect(0, 0, 20, 10))
    var largeBuffer = newBuffer(rect(0, 0, 200, 100))

    # Should handle different buffer sizes without crashing
    awm.renderSync(smallBuffer)
    awm.renderSync(largeBuffer)

    check smallBuffer.area.width == 20
    check largeBuffer.area.width == 200

  test "renderSync thread safety indication":
    let awm = newAsyncWindowManager()
    var destBuffer = newBuffer(rect(0, 0, 40, 20))

    # Test that renderSync uses proper locking
    # (actual concurrency testing would require threading)
    awm.renderSync(destBuffer)

    # Verify buffer state after render
    check destBuffer.area.isEmpty == false

  test "renderSync window visibility handling":
    let awm = newAsyncWindowManager()
    let visibleWindow = newWindow(rect(0, 0, 10, 10), "Visible")
    let hiddenWindow = newWindow(rect(15, 15, 10, 10), "Hidden")

    # Set window visibility states
    visibleWindow.visible = true
    hiddenWindow.visible = false

    var destBuffer = newBuffer(rect(0, 0, 50, 30))

    # Test visibility handling
    check visibleWindow.visible == true
    check hiddenWindow.visible == false

    # renderSync should only render visible windows
    awm.renderSync(destBuffer)

  test "renderSync vs renderAsync compatibility":
    let awm = newAsyncWindowManager()
    let asyncBuffer = newAsyncBuffer(80, 24)
    var syncBuffer = newBuffer(rect(0, 0, 80, 24))

    # Both should work with same AsyncWindowManager
    awm.renderSync(syncBuffer)
    # Note: can't test renderAsync due to async/unittest conflict

    # Verify buffer dimensions match
    check syncBuffer.area.width == asyncBuffer.getSize().width
    check syncBuffer.area.height == asyncBuffer.getSize().height

suite "AsyncWindows Async Operations":
  test "destroyAsyncWindowManager functionality":
    let awm = newAsyncWindowManager()

    # Add some windows first
    let window1 = newWindow(rect(0, 0, 10, 10), "Window 1")
    let window2 = newWindow(rect(10, 10, 15, 15), "Window 2")

    let id1 = waitFor awm.addWindowAsync(window1)
    discard waitFor awm.addWindowAsync(window2)

    # Verify windows were added
    let beforeStats = awm.getStats()
    check beforeStats.windowCount == 2
    check beforeStats.focusedId == id1.int # First window is auto-focused

    waitFor awm.destroyAsyncWindowManager()

    # Verify cleanup
    let afterStats = awm.getStats()
    check afterStats.windowCount == 0
    check afterStats.focusedId == -1

  test "addWindowAsync and removeWindowAsync":
    let awm = newAsyncWindowManager()
    let window = newWindow(rect(5, 5, 20, 15), "Test Window")

    # Test async add
    let windowId = waitFor awm.addWindowAsync(window)
    check windowId.int > 0

    # Verify window was added
    let addStats = awm.getStats()
    check addStats.windowCount == 1
    check addStats.focusedId == windowId.int

    # Test async removal
    let removed = waitFor awm.removeWindowAsync(windowId)
    check removed == true

    # Verify window was removed
    let removeStats = awm.getStats()
    check removeStats.windowCount == 0
    check removeStats.focusedId == -1

  test "focusWindowAsync functionality":
    let awm = newAsyncWindowManager()

    # Add multiple windows
    let window1 = newWindow(rect(0, 0, 10, 10), "Window 1")
    let window2 = newWindow(rect(10, 10, 10, 10), "Window 2")

    let id1 = waitFor awm.addWindowAsync(window1)
    let id2 = waitFor awm.addWindowAsync(window2)

    # id1 should be focused initially (first window auto-focused)
    let initialStats = awm.getStats()
    check initialStats.focusedId == id1.int

    # Focus second window
    let focused = waitFor awm.focusWindowAsync(id2)
    check focused == true

    # Verify focus changed
    let focusStats = awm.getStats()
    check focusStats.focusedId == id2.int

    # Get focused window
    let focusedWindowOpt = waitFor awm.getFocusedWindowAsync()
    check focusedWindowOpt.isSome()
    check focusedWindowOpt.get().title == "Window 2"

  test "getWindowAsync and window operations":
    let awm = newAsyncWindowManager()
    let window = newWindow(rect(10, 20, 30, 40), "Operations Test")

    let windowId = waitFor awm.addWindowAsync(window)

    # Test async get
    let retrievedOpt = waitFor awm.getWindowAsync(windowId)
    check retrievedOpt.isSome()
    let retrieved = retrievedOpt.get()
    check retrieved.title == "Operations Test"
    check retrieved.area == rect(10, 20, 30, 40)

    # Test move operation
    let moved = waitFor awm.moveWindowAsync(windowId, pos(50, 60))
    check moved == true

    let movedWindowOpt = waitFor awm.getWindowAsync(windowId)
    check movedWindowOpt.isSome()
    let movedWindow = movedWindowOpt.get()
    check movedWindow.area.x == 50
    check movedWindow.area.y == 60

    # Test resize operation
    let resized = waitFor awm.resizeWindowAsync(windowId, size(100, 200))
    check resized == true

    let resizedWindowOpt = waitFor awm.getWindowAsync(windowId)
    check resizedWindowOpt.isSome()
    let resizedWindow = resizedWindowOpt.get()
    check resizedWindow.area.width == 100
    check resizedWindow.area.height == 200

  test "window layering async operations":
    let awm = newAsyncWindowManager()

    let window1 = newWindow(rect(0, 0, 20, 20), "Bottom")
    let window2 = newWindow(rect(10, 10, 20, 20), "Top")

    let id1 = waitFor awm.addWindowAsync(window1)
    let id2 = waitFor awm.addWindowAsync(window2)

    # Test bring to front
    let broughtToFront = waitFor awm.bringToFrontAsync(id1)
    check broughtToFront == true

    # Test send to back
    let sentToBack = waitFor awm.sendToBackAsync(id2)
    check sentToBack == true

    # Test visible windows
    let visibleWindows = waitFor awm.getVisibleWindowsAsync()
    check visibleWindows.len == 2

  test "findWindowAtAsync functionality":
    let awm = newAsyncWindowManager()

    let window = newWindow(rect(10, 10, 20, 20), "Findable")
    window.visible = true
    discard waitFor awm.addWindowAsync(window)

    # Find window at position inside window
    let foundOpt = waitFor awm.findWindowAtAsync(pos(15, 15))
    check foundOpt.isSome()
    check foundOpt.get().title == "Findable"

    # Find window at position outside window
    let notFoundOpt = waitFor awm.findWindowAtAsync(pos(50, 50))
    check notFoundOpt.isNone()

  test "handleEventAsync functionality":
    let awm = newAsyncWindowManager()
    let window = newWindow(rect(0, 0, 20, 20), "Event Window")
    discard waitFor awm.addWindowAsync(window)

    # Test key event
    let keyEvent = Event(kind: Key, key: KeyEvent(code: Char, char: "a"))
    discard waitFor awm.handleEventAsync(keyEvent)
    # Result depends on handler presence, but should not crash

    # Test mouse event
    let mouseEvent = Event(
      kind: Mouse,
      mouse: MouseEvent(
        x: 10,
        y: 10,
        button: MouseButton.Left,
        kind: MouseEventKind.Press,
        modifiers: {},
      ),
    )
    discard waitFor awm.handleEventAsync(mouseEvent)
    # Result depends on handler presence, but should not crash

    # Test resize event
    let resizeEvent = Event(kind: Resize)
    discard waitFor awm.handleEventAsync(resizeEvent)
    # Result depends on handler presence, but should not crash

  test "renderAsync with AsyncBuffer":
    let awm = newAsyncWindowManager()
    let window = newWindow(rect(5, 5, 25, 15), "Render Test")

    # Set up window with border
    window.border = some(
      WindowBorder(
        top: true,
        right: true,
        bottom: true,
        left: true,
        style: Style(fg: color(White)),
        chars: BorderChars(
          horizontal: "-",
          vertical: "|",
          topLeft: "+",
          topRight: "+",
          bottomLeft: "+",
          bottomRight: "+",
        ),
      )
    )

    discard waitFor awm.addWindowAsync(window)

    # Create async buffer and render
    let asyncBuffer = newAsyncBuffer(80, 24)
    waitFor asyncBuffer.clearAsync()
    waitFor awm.renderAsync(asyncBuffer)

    # Verify rendering completed
    check asyncBuffer.getSize().width == 80
    check asyncBuffer.getSize().height == 24

  test "async error handling":
    let awm = newAsyncWindowManager()

    # Test invalid window operations
    let invalidId = WindowId(-1)

    let windowOpt = waitFor awm.getWindowAsync(invalidId)
    check windowOpt.isNone()

    let focusResult = waitFor awm.focusWindowAsync(invalidId)
    check focusResult == false

    let removeResult = waitFor awm.removeWindowAsync(invalidId)
    check removeResult == false

    let moveResult = waitFor awm.moveWindowAsync(invalidId, pos(0, 0))
    check moveResult == false

    let resizeResult = waitFor awm.resizeWindowAsync(invalidId, size(10, 10))
    check resizeResult == false

    # Test nil window exception
    try:
      discard waitFor awm.addWindowAsync(nil)
      check false # Should not reach here
    except AsyncWindowError:
      discard # Expected
    except CatchableError:
      check false # Unexpected exception type
