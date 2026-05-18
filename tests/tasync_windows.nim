# Test suite for async_windows module

import std/[unittest, options]

import ../celina/async/[async_backend, async_windows, async_buffer]
import ../celina/core/[geometry, colors, events, buffer]
import ../celina/core/windows

# Legacy `bool`-returning handler overloads are exercised below to
# verify backward compatibility; silence their Deprecated warnings.
{.push warning[Deprecated]: off.}

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
    let awm = newAsyncWindowManager()
    let window = newWindow(rect(0, 0, 10, 10), "State Window")

    # Test initial state (before being added to a manager)
    check window.visible == true
    check window.focused == false

    # Test visibility change
    window.visible = false
    check window.visible == false

    # Focus is derived from the owning manager
    discard awm.addWindowSync(window)
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
  test "Async window memory management - automatic cleanup":
    # Windows are automatically freed by Nim's GC when removed
    # This test verifies that removeWindowAsync properly removes windows
    let awm = newAsyncWindowManager()

    # Add some windows first
    let window1 = newWindow(rect(0, 0, 10, 10), "Window 1")
    let window2 = newWindow(rect(10, 10, 15, 15), "Window 2")

    let id1 = waitFor awm.addWindowAsync(window1)
    let id2 = waitFor awm.addWindowAsync(window2)

    # Verify windows were added
    let beforeStats = awm.getStats()
    check beforeStats.windowCount == 2
    # Second add takes focus with default autoFocus = true.
    check beforeStats.focusedId == id2.int

    # Remove windows - GC will handle cleanup automatically
    discard waitFor awm.removeWindowAsync(id1)
    discard waitFor awm.removeWindowAsync(id2)

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

  test "addWindow autoFocus parameter":
    let awm = newAsyncWindowManager()

    # First window is always auto-focused regardless of autoFocus.
    let first = newWindow(rect(0, 0, 10, 10), "First")
    let firstId = awm.addWindowSync(first, autoFocus = false)
    check first.focused == true
    check awm.getStats().focusedId == firstId.int

    # Subsequent window with autoFocus=false does not steal focus.
    let second = newWindow(rect(10, 10, 10, 10), "Second")
    discard awm.addWindowSync(second, autoFocus = false)
    check first.focused == true
    check second.focused == false

    # Subsequent window with default autoFocus (true) takes focus.
    let third = newWindow(rect(20, 20, 10, 10), "Third")
    let thirdId = awm.addWindowSync(third)
    check third.focused == true
    check first.focused == false
    check awm.getStats().focusedId == thirdId.int

    # Async variant defaults the same way.
    let fourth = newWindow(rect(30, 30, 10, 10), "Fourth")
    let fourthId = waitFor awm.addWindowAsync(fourth)
    check fourth.focused == true
    check awm.getStats().focusedId == fourthId.int

  test "modal window always takes focus on add":
    let awm = newAsyncWindowManager()

    # Seed with a non-modal focused window.
    let first = newWindow(rect(0, 0, 10, 10), "First")
    discard awm.addWindowSync(first)
    check first.focused == true

    # Modal window must take focus even when autoFocus = false.
    let dialog = newWindow(rect(5, 5, 10, 10), "Dialog", modal = true)
    let dialogId = awm.addWindowSync(dialog, autoFocus = false)
    check dialog.focused == true
    check first.focused == false
    check awm.getStats().focusedId == dialogId.int

  test "removeWindowAsync refocuses next window (focused getter)":
    let awm = newAsyncWindowManager()
    let window1 = newWindow(rect(0, 0, 10, 10), "First")
    let window2 = newWindow(rect(10, 10, 10, 10), "Second")

    discard waitFor awm.addWindowAsync(window1)
    let id2 = waitFor awm.addWindowAsync(window2)

    # window2 is focused (autoFocus default).
    check window2.focused == true
    check window1.focused == false

    # Removing the focused window must promote window1 via the getter.
    check (waitFor awm.removeWindowAsync(id2)) == true
    check window1.focused == true
    check awm.getStats().focusedId == window1.id.int

  test "focusWindowAsync with invalid id does not disturb existing focus":
    let awm = newAsyncWindowManager()
    let window1 = newWindow(rect(0, 0, 10, 10), "First")
    let window2 = newWindow(rect(10, 10, 10, 10), "Second")

    discard waitFor awm.addWindowAsync(window1)
    let id2 = waitFor awm.addWindowAsync(window2)

    check window2.focused == true

    # Focus a window that was never added.
    check (waitFor awm.focusWindowAsync(WindowId(9999))) == false

    # Existing focus is intact.
    check window2.focused == true
    check window1.focused == false
    check awm.getStats().focusedId == id2.int

  test "focusWindowAsync functionality":
    let awm = newAsyncWindowManager()

    # Add multiple windows
    let window1 = newWindow(rect(0, 0, 10, 10), "Window 1")
    let window2 = newWindow(rect(10, 10, 10, 10), "Window 2")

    let id1 = waitFor awm.addWindowAsync(window1)
    let id2 = waitFor awm.addWindowAsync(window2)

    # id2 is focused initially (autoFocus defaults to true).
    let initialStats = awm.getStats()
    check initialStats.focusedId == id2.int

    # Switch focus to the first window.
    let focused = waitFor awm.focusWindowAsync(id1)
    check focused == true

    # Verify focus changed
    let focusStats = awm.getStats()
    check focusStats.focusedId == id1.int

    # Get focused window
    let focusedWindowOpt = waitFor awm.getFocusedWindowAsync()
    check focusedWindowOpt.isSome()
    check focusedWindowOpt.get().title == "Window 1"

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

  test "handleEventSync routing returns EventResult":
    let awm = newAsyncWindowManager()
    let window = newWindow(rect(0, 0, 20, 20), "Event Window")
    var keyCalled = false
    window.setKeyHandler(
      proc(w: Window, k: KeyEvent): bool =
        keyCalled = true
        true
    )
    discard waitFor awm.addWindowAsync(window)

    let keyEvent = Event(kind: Key, key: KeyEvent(code: Char, char: "a"))
    let r = awm.handleEventSync(keyEvent)
    check r == erConsume
    check keyCalled

    # An event with no handler must yield erContinue so the global
    # handler can pick it up.
    let other = newAsyncWindowManager()
    discard waitFor other.addWindowAsync(newWindow(rect(0, 0, 20, 20), "Bare"))
    check other.handleEventSync(keyEvent) == erContinue

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

suite "AsyncWindows Sync Helpers and handleEventSync":
  test "getVisibleWindowsSync returns visible windows sorted by zIndex":
    let awm = newAsyncWindowManager()
    let w1 = newWindow(rect(0, 0, 10, 10), "First")
    let w2 = newWindow(rect(10, 0, 10, 10), "Second")
    let w3 = newWindow(rect(20, 0, 10, 10), "Hidden")

    discard awm.addWindowSync(w1)
    discard awm.addWindowSync(w2)
    discard awm.addWindowSync(w3)
    w3.visible = false
    w1.zIndex = 5
    w2.zIndex = 2

    let visible = awm.getVisibleWindowsSync()
    check visible.len == 2
    check visible[0].id == w2.id # lowest zIndex first
    check visible[1].id == w1.id

  test "findWindowAtSync returns topmost window at position":
    let awm = newAsyncWindowManager()
    let bottom = newWindow(rect(0, 0, 20, 20), "Bottom")
    let top = newWindow(rect(5, 5, 10, 10), "Top")

    discard awm.addWindowSync(bottom)
    discard awm.addWindowSync(top)
    bottom.zIndex = 1
    top.zIndex = 2

    let found = awm.findWindowAtSync(pos(7, 7))
    check found.isSome()
    check found.get().id == top.id

    let outside = awm.findWindowAtSync(pos(50, 50))
    check outside.isNone()

  test "handleEventSync routes key events to focused window":
    let awm = newAsyncWindowManager()
    let w = newWindow(rect(0, 0, 10, 10), "W")
    var handled = false
    w.setKeyHandler(
      proc(win: Window, k: KeyEvent): bool =
        handled = true
        return true
    )
    discard awm.addWindowSync(w)

    let ev = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))
    check awm.handleEventSync(ev) == erConsume
    check handled

  test "handleEventSync routes modal event to modal window only":
    let awm = newAsyncWindowManager()
    let normal = newWindow(rect(0, 0, 10, 10), "Normal")
    let modal = newWindow(rect(20, 20, 10, 10), "Modal", modal = true)

    var normalCalled = false
    var modalCalled = false
    normal.setKeyHandler(
      proc(win: Window, k: KeyEvent): bool =
        normalCalled = true
        return true
    )
    modal.setKeyHandler(
      proc(win: Window, k: KeyEvent): bool =
        modalCalled = true
        return true
    )

    discard awm.addWindowSync(normal)
    discard awm.addWindowSync(modal)

    # Focus the non-modal window explicitly. Modal routing must still win.
    discard awm.focusWindowSync(normal.id)

    let ev = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))
    check awm.handleEventSync(ev) == erConsume
    check modalCalled
    check not normalCalled

  test "removeWindowSync removes modal from stack when modal removed":
    let awm = newAsyncWindowManager()
    let modal = newWindow(rect(0, 0, 10, 10), "Modal", modal = true)
    let modalId = awm.addWindowSync(modal)

    check awm.currentModal().isSome()
    check awm.currentModal().get() == modalId

    discard awm.removeWindowSync(modalId)
    check awm.currentModal().isNone()
    check awm.modalStack.len == 0

  test "handleEventSync mouse Press auto-focuses target window":
    let awm = newAsyncWindowManager()
    let w1 = newWindow(rect(0, 0, 10, 10), "First")
    let w2 = newWindow(rect(20, 20, 10, 10), "Second")

    var w1Called = false
    var w2Called = false
    w1.setMouseHandler(
      proc(win: Window, m: MouseEvent): bool =
        w1Called = true
        return true
    )
    w2.setMouseHandler(
      proc(win: Window, m: MouseEvent): bool =
        w2Called = true
        return true
    )

    let id1 = awm.addWindowSync(w1)
    let id2 = awm.addWindowSync(w2)

    # w2 is focused (most recently added). Click on w1.
    check awm.focusedWindow.get() == id2

    let ev = Event(
      kind: EventKind.Mouse, mouse: MouseEvent(x: 5, y: 5, kind: Press, button: Left)
    )
    check awm.handleEventSync(ev) == erConsume

    # Focus moves to w1, and its handler is the one invoked.
    check awm.focusedWindow.get() == id1
    check w1Called
    check not w2Called

  test "removeWindowAsync removes modal from stack when modal removed":
    let awm = newAsyncWindowManager()
    let modal = newWindow(rect(0, 0, 10, 10), "Modal", modal = true)
    let modalId = waitFor awm.addWindowAsync(modal)

    check awm.currentModal().isSome()
    check awm.currentModal().get() == modalId

    discard waitFor awm.removeWindowAsync(modalId)
    check awm.currentModal().isNone()
    check awm.modalStack.len == 0

  test "Modal stack: addWindowSync nested modals route to top":
    let awm = newAsyncWindowManager()
    let m1 = newWindow(rect(0, 0, 10, 10), "M1", modal = true)
    let m2 = newWindow(rect(2, 2, 6, 6), "M2", modal = true)
    let id1 = awm.addWindowSync(m1)
    let id2 = awm.addWindowSync(m2)

    check awm.modalStack == @[id1, id2]
    check awm.currentModal().get() == id2

    # Removing the top modal restores the prior one.
    discard awm.removeWindowSync(id2)
    check awm.currentModal().get() == id1

  test "removeWindowSync refocuses next active modal when top is removed":
    # Focus must follow the new modal-stack top, not the last-added
    # window. Mirrors `core/windows.nim` behavior.
    let awm = newAsyncWindowManager()
    let base = newWindow(rect(0, 0, 30, 30), "Base")
    let m1 = newWindow(rect(5, 5, 20, 20), "M1", modal = true)
    let m2 = newWindow(rect(10, 10, 10, 10), "M2", modal = true)

    discard awm.addWindowSync(base)
    let m1Id = awm.addWindowSync(m1)
    let m2Id = awm.addWindowSync(m2)

    check awm.focusedWindow.get() == m2Id

    discard awm.removeWindowSync(m2Id)
    check awm.modalStack == @[m1Id]
    check awm.currentModal().get() == m1Id
    check awm.focusedWindow.get() == m1Id

  test "removeWindowAsync refocuses next active modal when top is removed":
    let awm = newAsyncWindowManager()
    let base = newWindow(rect(0, 0, 30, 30), "Base")
    let m1 = newWindow(rect(5, 5, 20, 20), "M1", modal = true)
    let m2 = newWindow(rect(10, 10, 10, 10), "M2", modal = true)

    discard waitFor awm.addWindowAsync(base)
    let m1Id = waitFor awm.addWindowAsync(m1)
    let m2Id = waitFor awm.addWindowAsync(m2)

    check awm.focusedWindow.get() == m2Id

    discard waitFor awm.removeWindowAsync(m2Id)
    check awm.modalStack == @[m1Id]
    check awm.currentModal().get() == m1Id
    check awm.focusedWindow.get() == m1Id

  test "handleEventSync blocks mouse clicks on non-modal windows when modal is active":
    let awm = newAsyncWindowManager()
    let normal = newWindow(rect(0, 0, 10, 10), "Normal")
    let modal = newWindow(rect(20, 20, 10, 10), "Modal", modal = true)

    var normalCalled = false
    normal.setMouseHandler(
      proc(win: Window, m: MouseEvent): bool =
        normalCalled = true
        return true
    )

    discard awm.addWindowSync(normal)
    discard awm.addWindowSync(modal)

    # Click within the non-modal window's area. Even though the click position
    # is inside `normal`, modal routing must intercept the event so the
    # non-modal handler is never invoked.
    let ev = Event(
      kind: EventKind.Mouse, mouse: MouseEvent(x: 5, y: 5, kind: Press, button: Left)
    )
    discard awm.handleEventSync(ev)
    check not normalCalled

  test "handleEventSync drops out-of-bounds clicks on modal general handler":
    # A modal with only a general eventHandler must not observe clicks
    # outside its own area; the manager drops them with erConsume.
    let awm = newAsyncWindowManager()
    let modal = newWindow(rect(20, 20, 10, 10), "Modal", modal = true)
    var generalCalled = false
    modal.setEventHandler(
      proc(w: Window, e: Event): EventResult =
        generalCalled = true
        return erContinue
    )
    discard awm.addWindowSync(modal)

    let outside = Event(
      kind: EventKind.Mouse, mouse: MouseEvent(x: 0, y: 0, kind: Press, button: Left)
    )
    check awm.handleEventSync(outside) == erConsume
    check not generalCalled

    let inside = Event(
      kind: EventKind.Mouse, mouse: MouseEvent(x: 25, y: 25, kind: Press, button: Left)
    )
    discard awm.handleEventSync(inside)
    check generalCalled

{.pop.}
