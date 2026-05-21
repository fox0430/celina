## Tests for window management system

import std/[unittest, options, strutils]

import ../celina/core/[geometry, buffer, colors, events]

import ../celina/core/windows {.all.}

# These tests deliberately exercise the legacy `bool`-returning handler
# overloads to verify backward compatibility, so the `Deprecated`
# warnings they emit are expected noise — silence them here.
{.push warning[Deprecated]: off.}

suite "Window Tests":
  test "Create window with default settings":
    let area = rect(10, 5, 50, 20)
    let window = newWindow(area, "Test Window")

    check window.area == area
    check window.title == "Test Window"
    check window.state == wsNormal
    check window.visible == true
    check window.focused == false
    check window.resizable == true
    check window.movable == true
    check window.modal == false
    check window.border.isSome()

  test "Create window without border":
    let area = rect(0, 0, 30, 10)
    let window = newWindow(area, "No Border", border = none(WindowBorder))

    check window.border.isNone()
    check window.contentArea == area # Content area equals window area when no border

  test "Window content area calculation with border":
    let area = rect(5, 5, 20, 10)
    let window = newWindow(area, "With Border")

    # Content area should be smaller due to borders
    check window.contentArea.width == area.width - 2 # Left + right border
    check window.contentArea.height == area.height - 2 # Top + bottom border
    check window.contentArea.x == area.x + 1
    check window.contentArea.y == area.y + 1

  test "Window move operation":
    let area = rect(10, 10, 30, 15)
    let window = newWindow(area, "Movable")
    let newPos = pos(20, 25)

    window.move(newPos)

    check window.area.x == newPos.x
    check window.area.y == newPos.y
    check window.area.width == area.width # Size unchanged
    check window.area.height == area.height

  test "Window resize operation":
    let area = rect(10, 10, 30, 15)
    let window = newWindow(area, "Resizable")
    let newSize = size(40, 25)

    window.resize(newSize)

    check window.area.width == newSize.width
    check window.area.height == newSize.height
    check window.area.x == area.x # Position unchanged
    check window.area.y == area.y

  test "Non-movable window ignores move":
    let area = rect(10, 10, 30, 15)
    let window = newWindow(area, "Fixed", movable = false)
    let originalPos = window.area.position

    window.move(pos(50, 50))

    check window.area.position == originalPos

  test "Non-resizable window ignores resize":
    let area = rect(10, 10, 30, 15)
    let window = newWindow(area, "Fixed Size", resizable = false)
    let originalSize = window.area.size

    window.resize(size(100, 100))

    check window.area.size == originalSize

  test "Window state operations":
    let area = rect(10, 10, 30, 15)
    let window = newWindow(area, "Test")
    let screenArea = rect(0, 0, 80, 24)

    # Test minimize
    window.minimize()
    check window.state == wsMinimized
    check window.visible == false

    # Test maximize
    window.maximize(screenArea)
    check window.state == wsMaximized
    check window.area == screenArea

    # Test restore
    window.restore(area)
    check window.state == wsNormal
    check window.visible == true
    check window.area == area

suite "WindowManager Tests":
  test "Create empty window manager":
    let wm = newWindowManager()

    check wm.windows.len == 0
    check wm.focusedWindow.isNone()
    check wm.modalStack.len == 0
    check wm.currentModal().isNone()

  test "Add window to manager":
    let wm = newWindowManager()
    let window = newWindow(rect(10, 10, 30, 15), "Test")

    let windowId = wm.addWindow(window)

    check wm.windows.len == 1
    check window.id == windowId
    check wm.focusedWindow.isSome()
    check wm.focusedWindow.get() == windowId
    check window.focused == true

  test "Remove window from manager":
    let wm = newWindowManager()
    let window1 = newWindow(rect(10, 10, 30, 15), "Test1")
    let window2 = newWindow(rect(20, 20, 30, 15), "Test2")

    let id1 = wm.addWindow(window1)
    let id2 = wm.addWindow(window2)

    check wm.windows.len == 2

    check wm.removeWindow(id1) == true

    check wm.windows.len == 1
    check wm.getWindow(id1).isNone()
    check wm.getWindow(id2).isSome()

  test "Window.manager is set after addWindow":
    let wm = newWindowManager()
    let window = newWindow(rect(10, 10, 30, 15), "Test")

    check window.manager == nil
    check window.focused == false

    discard wm.addWindow(window)

    check window.manager == wm
    check window.focused == true

  test "addWindow autoFocus parameter":
    let wm = newWindowManager()

    # First window is always auto-focused regardless of autoFocus.
    let first = newWindow(rect(0, 0, 10, 10), "First")
    let firstId = wm.addWindow(first, autoFocus = false)
    check first.focused == true
    check wm.focusedWindow == some(firstId)

    # Subsequent window with autoFocus=false does not steal focus.
    let second = newWindow(rect(10, 10, 10, 10), "Second")
    discard wm.addWindow(second, autoFocus = false)
    check first.focused == true
    check second.focused == false
    check wm.focusedWindow == some(firstId)

    # Subsequent window with autoFocus=true (default) takes focus.
    let third = newWindow(rect(20, 20, 10, 10), "Third")
    let thirdId = wm.addWindow(third)
    check third.focused == true
    check first.focused == false
    check second.focused == false
    check wm.focusedWindow == some(thirdId)

  test "modal window always takes focus on add":
    let wm = newWindowManager()

    # Seed with a non-modal focused window.
    let first = newWindow(rect(0, 0, 10, 10), "First")
    discard wm.addWindow(first)
    check first.focused == true

    # Modal window must take focus even when autoFocus = false, since a
    # modal that is not focused would silently grab events anyway.
    let dialog = newWindow(rect(5, 5, 10, 10), "Dialog", modal = true)
    let dialogId = wm.addWindow(dialog, autoFocus = false)
    check dialog.focused == true
    check first.focused == false
    check wm.focusedWindow == some(dialogId)
    check wm.currentModal() == some(dialogId)

  test "removeWindow refocuses next window (focused getter)":
    # When the focused window is removed, the next window must become
    # focused as observed through the computed `focused` getter — not just
    # through wm.focusedWindow.
    let wm = newWindowManager()
    let window1 = newWindow(rect(0, 0, 10, 10), "First")
    let window2 = newWindow(rect(10, 10, 10, 10), "Second")

    discard wm.addWindow(window1)
    let id2 = wm.addWindow(window2)

    # window2 is focused (autoFocus default).
    check window2.focused == true
    check window1.focused == false

    # Removing the focused window must promote window1 via the getter.
    check wm.removeWindow(id2) == true
    check window1.focused == true
    check wm.focusedWindow == some(window1.id)

  test "focusWindow with invalid id does not disturb existing focus":
    # The old code unfocused every window before focusing the target —
    # so an invalid id would silently un-focus everything. The new code
    # derives focus from the manager, so an invalid id is a pure no-op.
    let wm = newWindowManager()
    let window1 = newWindow(rect(0, 0, 10, 10), "First")
    let window2 = newWindow(rect(10, 10, 10, 10), "Second")

    discard wm.addWindow(window1)
    let id2 = wm.addWindow(window2)

    check window2.focused == true

    # Focus a window that was never added.
    check wm.focusWindow(WindowId(9999)) == false

    # Existing focus is intact.
    check window2.focused == true
    check window1.focused == false
    check wm.focusedWindow == some(id2)

  test "removeWindow detaches window from manager":
    let wm = newWindowManager()
    let window1 = newWindow(rect(10, 10, 30, 15), "Test1")
    let window2 = newWindow(rect(20, 20, 30, 15), "Test2")

    let id1 = wm.addWindow(window1)
    discard wm.addWindow(window2)

    # window1 is currently not focused (window2 is), but is still attached.
    check window1.manager == wm

    check wm.removeWindow(id1) == true

    # After removal, manager link is cleared and focused getter returns false
    # regardless of any stale state.
    check window1.manager == nil
    check window1.focused == false

  test "Focus window management":
    let wm = newWindowManager()
    let window1 = newWindow(rect(10, 10, 30, 15), "Test1")
    let window2 = newWindow(rect(20, 20, 30, 15), "Test2")

    let id1 = wm.addWindow(window1)
    let id2 = wm.addWindow(window2)

    # Second window should be focused initially
    check wm.focusedWindow.get() == id2
    check window2.focused == true
    check window1.focused == false

    # Focus first window
    check wm.focusWindow(id1) == true

    check wm.focusedWindow.get() == id1
    check window1.focused == true
    check window2.focused == false

  test "Z-index management":
    let wm = newWindowManager()
    let window1 = newWindow(rect(10, 10, 30, 15), "Test1")
    let window2 = newWindow(rect(20, 20, 30, 15), "Test2")
    let window3 = newWindow(rect(30, 30, 30, 15), "Test3")

    let id1 = wm.addWindow(window1)
    discard wm.addWindow(window2)
    discard wm.addWindow(window3)

    # Windows should have increasing Z-index
    check window1.zIndex < window2.zIndex
    check window2.zIndex < window3.zIndex

    # Focus first window should bring it to front
    check wm.focusWindow(id1) == true

    check window1.zIndex > window2.zIndex
    check window1.zIndex > window3.zIndex

  test "focusWindow with invalid ID returns false":
    let wm = newWindowManager()
    let window = newWindow(rect(10, 10, 30, 15), "Test")
    discard wm.addWindow(window)

    # Try to focus non-existent window
    check wm.focusWindow(WindowId(999)) == false

  test "removeWindow with invalid ID returns false":
    let wm = newWindowManager()
    let window = newWindow(rect(10, 10, 30, 15), "Test")
    discard wm.addWindow(window)

    # Try to remove non-existent window
    check wm.removeWindow(WindowId(999)) == false
    check wm.windows.len == 1

  test "Modal window handling":
    let wm = newWindowManager()
    let normalWindow = newWindow(rect(10, 10, 30, 15), "Normal")
    let modalWindow = newWindow(rect(20, 20, 40, 20), "Modal", modal = true)

    discard wm.addWindow(normalWindow)
    let modalId = wm.addWindow(modalWindow)

    # Modal window should be focused and pushed onto the modal stack
    check wm.focusedWindow.get() == modalId
    check wm.currentModal().isSome()
    check wm.currentModal().get() == modalId
    check wm.modalStack.len == 1

  test "Find window at position":
    let wm = newWindowManager()
    let window1 = newWindow(rect(10, 10, 20, 10), "Test1")
    let window2 = newWindow(rect(15, 15, 20, 10), "Test2") # Overlapping

    let id1 = wm.addWindow(window1)
    let id2 = wm.addWindow(window2)

    # Position in window1 only
    let found1 = wm.findWindowAt(pos(12, 12))
    check found1.isSome()
    check found1.get().id == id1

    # Position in overlapping area - should return top window (window2)
    let found2 = wm.findWindowAt(pos(18, 18))
    check found2.isSome()
    check found2.get().id == id2

    # Position outside both windows
    let foundNone = wm.findWindowAt(pos(50, 50))
    check foundNone.isNone()

  test "Visible windows ordering":
    let wm = newWindowManager()
    let window1 = newWindow(rect(10, 10, 30, 15), "Test1")
    let window2 = newWindow(rect(20, 20, 30, 15), "Test2")
    let window3 = newWindow(rect(30, 30, 30, 15), "Test3")

    let id1 = wm.addWindow(window1)
    discard wm.addWindow(window2)
    let id3 = wm.addWindow(window3)

    # Hide middle window
    window2.hide()

    let visibleWindows = wm.getVisibleWindows()

    check visibleWindows.len == 2
    check visibleWindows[0].id == id1 # Lower Z-index first
    check visibleWindows[1].id == id3

suite "Window Rendering Tests":
  test "Window border rendering":
    var destBuffer = newBuffer(50, 20)
    let window = newWindow(rect(5, 5, 20, 10), "Test Border")

    window.render(destBuffer)

    # Check corners
    check destBuffer[5, 5].symbol == "┌"
    check destBuffer[24, 5].symbol == "┐"
    check destBuffer[5, 14].symbol == "└"
    check destBuffer[24, 14].symbol == "┘"

    # Check title rendering
    check destBuffer[7, 5].symbol == "T" # First character of "Test Border"

  test "Window without border rendering":
    var destBuffer = newBuffer(50, 20)
    let window = newWindow(rect(5, 5, 20, 10), "No Border", border = none(WindowBorder))

    # Fill window content with test character
    window.buffer.setString(0, 0, "Content")

    window.render(destBuffer)

    # Should not have border characters
    check destBuffer[5, 5].symbol != "┌"
    # Should have content
    check destBuffer[5, 5].symbol == "C" # First character of "Content"

  test "Hidden window not rendered":
    var destBuffer = newBuffer(50, 20)
    let window = newWindow(rect(5, 5, 20, 10), "Hidden")

    window.hide()
    window.render(destBuffer)

    # Buffer should remain empty where window would be
    check destBuffer[5, 5].symbol == " "
    check destBuffer[10, 10].symbol == " "

  test "WindowManager rendering order":
    let wm = newWindowManager()
    var destBuffer = newBuffer(50, 20)

    let window1 = newWindow(rect(5, 5, 10, 5), "Back")
    let window2 = newWindow(rect(10, 8, 10, 5), "Front")

    # Fill windows with identifiable content
    window1.buffer.setString(0, 0, "BACK")
    window2.buffer.setString(0, 0, "FRONT")

    discard wm.addWindow(window1)
    discard wm.addWindow(window2)

    wm.render(destBuffer)

    # In overlapping area, front window should be visible
    # Window2 starts at (10, 8), so position (10, 8) should show window2's content
    # But we need to account for borders, so actual content starts at (11, 9)
    check destBuffer[11, 9].symbol == "F" # First character of "FRONT"

suite "Coordinate System Consistency Tests":
  test "Buffer always starts at (0,0) after creation":
    let window = newWindow(rect(50, 30, 100, 60), "Test")

    check:
      window.buffer.area.x == 0
      window.buffer.area.y == 0
      # Width/height should match content area, not window area
      window.buffer.area.width == window.contentArea.width
      window.buffer.area.height == window.contentArea.height

  test "Buffer remains at (0,0) after resize":
    let window = newWindow(rect(10, 10, 50, 30))

    # Resize multiple times
    window.resize(size(80, 40))
    check window.buffer.area.x == 0
    check window.buffer.area.y == 0

    window.resize(size(30, 20))
    check window.buffer.area.x == 0
    check window.buffer.area.y == 0

    window.resize(size(100, 70))
    check window.buffer.area.x == 0
    check window.buffer.area.y == 0

  test "Buffer remains at (0,0) after move":
    let window = newWindow(rect(10, 10, 50, 30))

    window.move(pos(100, 100))
    check:
      window.area.x == 100
      window.area.y == 100
      window.buffer.area.x == 0
      window.buffer.area.y == 0

  test "SetArea API maintains (0,0) buffer coordinates":
    let window = newWindow(rect(5, 5, 40, 25))

    # Use the safe setArea API
    window.setArea(rect(50, 60, 70, 80))

    check:
      window.area == rect(50, 60, 70, 80)
      window.buffer.area.x == 0
      window.buffer.area.y == 0
      window.buffer.area.width > 0
      window.buffer.area.height > 0

suite "Content Area Calculation Tests":
  test "Correct content area with full border":
    let window = newWindow(
      rect(0, 0, 100, 50),
      "Test",
      some(
        WindowBorder(
          top: true,
          right: true,
          bottom: true,
          left: true,
          style: defaultStyle(),
          chars: defaultBorderChars(),
        )
      ),
    )

    check:
      window.contentArea.x == 1
      window.contentArea.y == 1
      window.contentArea.width == 98
      window.contentArea.height == 48

  test "Correct content area with partial borders":
    let window = newWindow(rect(10, 10, 50, 30))

    # Only top and bottom borders
    window.setBorder(
      some(
        WindowBorder(
          top: true,
          right: false,
          bottom: true,
          left: false,
          style: defaultStyle(),
          chars: defaultBorderChars(),
        )
      )
    )

    check:
      window.contentArea.x == 10 # No left border
      window.contentArea.y == 11 # Top border adds 1
      window.contentArea.width == 50 # No horizontal reduction
      window.contentArea.height == 28 # Top + bottom borders

  test "Correct content area with left/right borders only":
    let window = newWindow(rect(20, 15, 60, 40))

    window.setBorder(
      some(
        WindowBorder(
          top: false,
          right: true,
          bottom: false,
          left: true,
          style: defaultStyle(),
          chars: defaultBorderChars(),
        )
      )
    )

    check:
      window.contentArea.x == 21 # Left border adds 1
      window.contentArea.y == 15 # No top border
      window.contentArea.width == 58 # Left + right borders
      window.contentArea.height == 40 # No vertical reduction

  test "Content area never becomes negative":
    let window = newWindow(
      rect(0, 0, 2, 2), # Very small window
      "Tiny",
      some(defaultBorder()),
    )

    # Even with borders, content area should have minimum size
    check:
      window.contentArea.width >= 1
      window.contentArea.height >= 1

suite "Safe API Tests":
  test "getContentBuffer returns (0,0) based buffer":
    let window = newWindow(rect(25, 35, 45, 55))
    let buffer = window.getContentBuffer()

    check:
      buffer.area.x == 0
      buffer.area.y == 0
      buffer.area.width > 0
      buffer.area.height > 0

  test "getContentSize returns correct dimensions":
    let window = newWindow(rect(0, 0, 100, 50), "Test", some(defaultBorder()))

    let size = window.getContentSize()
    check:
      size.width == 98 # 100 - 2 for borders
      size.height == 48 # 50 - 2 for borders

  test "Multiple setArea calls maintain consistency":
    let window = newWindow(rect(10, 10, 30, 20))

    # Rapid area changes
    for i in 1 .. 10:
      window.setArea(rect(i * 5, i * 3, 30 + i * 2, 20 + i))

      check:
        window.buffer.area.x == 0
        window.buffer.area.y == 0
        window.buffer.area.width > 0
        window.buffer.area.height > 0

suite "Performance and Efficiency Tests":
  test "getVisibleWindows efficiency":
    let wm = newWindowManager()

    # Add many windows
    for i in 0 .. 19:
      let win = newWindow(rect(i * 2, i, 20, 10), "Window " & $i)
      if i mod 3 == 0:
        win.hide() # Hide some windows
      discard wm.addWindow(win)

    let visibleWindows = wm.getVisibleWindows()

    # Should only return visible windows
    check visibleWindows.len < 20

    # Should be sorted by z-index
    for i in 1 ..< visibleWindows.len:
      check visibleWindows[i - 1].zIndex <= visibleWindows[i].zIndex

  test "Window manager handles many windows":
    let wm = newWindowManager()
    var windowIds: seq[WindowId] = @[]

    # Add 100 windows
    for i in 0 .. 99:
      let win = newWindow(rect(i mod 50, i mod 30, 20, 10), "Win" & $i)
      windowIds.add(wm.addWindow(win))

    check wm.windows.len == 100

    # Remove half of them
    for i in 0 .. 49:
      discard wm.removeWindow(windowIds[i * 2])

    check wm.windows.len == 50

    # Focus should still work
    if windowIds.len > 1:
      discard wm.focusWindow(windowIds[1])
      check wm.focusedWindow.get() == windowIds[1]

suite "Window Event System Tests":
  test "Window event handler assignment (bool compat)":
    let window = newWindow(rect(10, 10, 30, 20), "Test")
    var handlerCalled = false

    window.setEventHandler(
      proc(w: Window, e: Event): bool =
        handlerCalled = true
        return true
    )

    check window.eventHandler.isSome()

    # Create and dispatch test event
    let testEvent = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))
    let result = window.handleWindowEvent(testEvent)

    check:
      result == erConsume
      handlerCalled

  test "Window event handler assignment (EventResult)":
    let window = newWindow(rect(10, 10, 30, 20), "Test")
    var handlerCalled = false

    window.setEventHandler(
      proc(w: Window, e: Event): EventResult =
        handlerCalled = true
        return erConsume
    )

    let testEvent = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))
    let result = window.handleWindowEvent(testEvent)

    check:
      result == erConsume
      handlerCalled

  test "Window key handler specific":
    let window = newWindow(rect(10, 10, 30, 20), "Test")
    var keyHandlerCalled = false

    window.setKeyHandler(
      proc(w: Window, k: KeyEvent): bool =
        keyHandlerCalled = true
        return true
    )

    let keyEvent = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Escape))
    let result = window.handleWindowEvent(keyEvent)

    check:
      result == erConsume
      keyHandlerCalled

  test "Window mouse handler specific":
    let window = newWindow(rect(10, 10, 30, 20), "Test")
    var mouseHandlerCalled = false

    window.setMouseHandler(
      proc(w: Window, m: MouseEvent): bool =
        mouseHandlerCalled = true
        return true
    )

    let mouseEvent = Event(
      kind: EventKind.Mouse, mouse: MouseEvent(x: 15, y: 15, kind: Press, button: Left)
    )
    let result = window.handleWindowEvent(mouseEvent)

    check:
      result == erConsume
      mouseHandlerCalled

  test "Window event handler priority (specific over general)":
    let window = newWindow(rect(10, 10, 30, 20), "Test")
    var generalHandlerCalled = false
    var keyHandlerCalled = false

    window.setEventHandler(
      proc(w: Window, e: Event): bool =
        generalHandlerCalled = true
        return false
    )

    window.setKeyHandler(
      proc(w: Window, k: KeyEvent): bool =
        keyHandlerCalled = true
        return true
    )

    let keyEvent = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))
    let result = window.handleWindowEvent(keyEvent)

    check:
      result == erConsume
      keyHandlerCalled
      not generalHandlerCalled # Specific handler should take precedence

  test "Specific handler erContinue falls through to general":
    # A specific (key/mouse) handler returning erContinue must allow the
    # general eventHandler to run on the same event.
    let window = newWindow(rect(10, 10, 30, 20), "Test")
    var keyCalled = false
    var generalCalled = false

    window.setKeyHandler(
      proc(w: Window, k: KeyEvent): EventResult =
        keyCalled = true
        return erContinue
    )
    window.setEventHandler(
      proc(w: Window, e: Event): EventResult =
        generalCalled = true
        return erConsume
    )

    let keyEvent = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))
    let result = window.handleWindowEvent(keyEvent)

    check:
      result == erConsume
      keyCalled
      generalCalled

  test "bindWidget skips mouse handler when widget lacks handleMouseEvent":
    # A "widget" with only handleKeyEvent (the shape used by Input/Table)
    # must still bind successfully; the mouse handler is simply omitted.
    type KeyOnlyWidget = ref object
      called: bool

    proc handleKeyEvent(w: KeyOnlyWidget, k: KeyEvent): EventResult =
      w.called = true
      erConsume

    let widget = KeyOnlyWidget()
    let window = newWindow(rect(0, 0, 30, 20), "Key-only")
    bindWidget(window, widget)

    check window.keyHandler.isSome()
    check window.mouseHandler.isNone()

    let ev = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))
    check window.handleWindowEvent(ev) == erConsume
    check widget.called

  test "bindWidget binds both handlers when widget supports both":
    type FullWidget = ref object
      keyCalled, mouseCalled: bool

    proc handleKeyEvent(w: FullWidget, k: KeyEvent): EventResult =
      w.keyCalled = true
      erConsume

    proc handleMouseEvent(w: FullWidget, m: MouseEvent, area: Rect): EventResult =
      w.mouseCalled = true
      erConsume

    let widget = FullWidget()
    let window = newWindow(rect(0, 0, 30, 20), "Full")
    bindWidget(window, widget)

    check window.keyHandler.isSome()
    check window.mouseHandler.isSome()

    discard window.handleWindowEvent(
      Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))
    )
    discard window.handleWindowEvent(
      Event(
        kind: EventKind.Mouse, mouse: MouseEvent(x: 5, y: 5, kind: Press, button: Left)
      )
    )
    check widget.keyCalled
    check widget.mouseCalled

  test "Window handler returning erQuit is normalized to erConsume":
    # Only the global App.onEvent handler can signal quit. A window
    # handler that returns erQuit must be normalized to erConsume so
    # the manager treats it as consumed (rather than silently falling
    # through to the global handler).
    let window = newWindow(rect(10, 10, 30, 20), "Test")
    window.setKeyHandler(
      proc(w: Window, k: KeyEvent): EventResult =
        erQuit
    )
    let ev = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))
    check window.handleWindowEvent(ev) == erConsume

    let window2 = newWindow(rect(0, 0, 30, 30), "Test2")
    window2.setMouseHandler(
      proc(w: Window, m: MouseEvent): EventResult =
        erQuit
    )
    let mev = Event(
      kind: EventKind.Mouse, mouse: MouseEvent(x: 5, y: 5, kind: Press, button: Left)
    )
    check window2.handleWindowEvent(mev) == erConsume

    let window3 = newWindow(rect(10, 10, 30, 20), "Test3")
    window3.setEventHandler(
      proc(w: Window, e: Event): EventResult =
        erQuit
    )
    check window3.handleWindowEvent(ev) == erConsume

  test "Window event handler clearing":
    let window = newWindow(rect(10, 10, 30, 20), "Test")

    window.setEventHandler(
      proc(w: Window, e: Event): bool =
        true
    )
    window.setKeyHandler(
      proc(w: Window, k: KeyEvent): bool =
        true
    )
    window.setMouseHandler(
      proc(w: Window, m: MouseEvent): bool =
        true
    )
    window.setResizeHandler(
      proc(w: Window, newSize: Size): bool =
        true
    )

    check:
      window.eventHandler.isSome()
      window.keyHandler.isSome()
      window.mouseHandler.isSome()
      window.resizeHandler.isSome()

    window.clearEventHandlers()

    check:
      window.eventHandler.isNone()
      window.keyHandler.isNone()
      window.mouseHandler.isNone()
      window.resizeHandler.isNone()

  test "Window acceptsEvents flag":
    let window = newWindow(rect(10, 10, 30, 20), "Test", acceptsEvents = false)
    var handlerCalled = false

    window.setEventHandler(
      proc(w: Window, e: Event): bool =
        handlerCalled = true
        return true
    )

    let testEvent = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))
    let result = window.handleWindowEvent(testEvent)

    check:
      result == erContinue # Should not consume events when acceptsEvents is false
      not handlerCalled

  test "Hidden window ignores events":
    let window = newWindow(rect(10, 10, 30, 20), "Test")
    var handlerCalled = false

    window.setEventHandler(
      proc(w: Window, e: Event): bool =
        handlerCalled = true
        return true
    )

    window.hide()

    let testEvent = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))
    let result = window.handleWindowEvent(testEvent)

    check:
      result == erContinue
      not handlerCalled

suite "WindowManager Event System Tests":
  test "handleEvent to focused window":
    let wm = newWindowManager()
    let window = newWindow(rect(10, 10, 30, 20), "Test")
    var handlerCalled = false

    window.setKeyHandler(
      proc(w: Window, k: KeyEvent): bool =
        handlerCalled = true
        return true
    )

    let windowId = wm.addWindow(window)
    discard wm.focusWindow(windowId)

    let keyEvent = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))
    let result = wm.handleEvent(keyEvent)

    check:
      result == erConsume
      handlerCalled

  test "handleEvent mouse to window at position":
    let wm = newWindowManager()
    let window1 = newWindow(rect(10, 10, 20, 15), "Window1")
    let window2 = newWindow(rect(30, 30, 20, 15), "Window2")
    var window1HandlerCalled = false
    var window2HandlerCalled = false

    window1.setMouseHandler(
      proc(w: Window, m: MouseEvent): bool =
        window1HandlerCalled = true
        return true
    )

    window2.setMouseHandler(
      proc(w: Window, m: MouseEvent): bool =
        window2HandlerCalled = true
        return true
    )

    discard wm.addWindow(window1)
    discard wm.addWindow(window2)

    # Mouse event in window2 area
    let mouseEvent = Event(
      kind: EventKind.Mouse, mouse: MouseEvent(x: 35, y: 35, kind: Press, button: Left)
    )
    let result = wm.handleEvent(mouseEvent)

    check:
      result == erConsume
      not window1HandlerCalled
      window2HandlerCalled

  test "Unhandled event returns erContinue (falls through to global)":
    # A window handler returning erContinue must not consume the event;
    # the manager must propagate erContinue so the app's global handler
    # can run.
    let wm = newWindowManager()
    let window = newWindow(rect(10, 10, 30, 20), "Test")

    window.setKeyHandler(
      proc(w: Window, k: KeyEvent): bool =
        false # not handled
    )

    discard wm.addWindow(window)
    let keyEvent = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))
    check wm.handleEvent(keyEvent) == erContinue

  test "Modal stack: nested modals route to top, removal restores prior":
    let wm = newWindowManager()
    let base = newWindow(rect(0, 0, 30, 30), "Base")
    let m1 = newWindow(rect(5, 5, 20, 20), "M1", modal = true)
    let m2 = newWindow(rect(10, 10, 10, 10), "M2", modal = true)

    var lastTarget = ""
    base.setKeyHandler(
      proc(w: Window, k: KeyEvent): bool =
        lastTarget = "base"
        true
    )
    m1.setKeyHandler(
      proc(w: Window, k: KeyEvent): bool =
        lastTarget = "m1"
        true
    )
    m2.setKeyHandler(
      proc(w: Window, k: KeyEvent): bool =
        lastTarget = "m2"
        true
    )

    discard wm.addWindow(base)
    let m1Id = wm.addWindow(m1)
    let m2Id = wm.addWindow(m2)

    check wm.modalStack.len == 2
    check wm.currentModal().get() == m2Id

    let keyEvent = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))

    # Top of stack receives the event.
    discard wm.handleEvent(keyEvent)
    check lastTarget == "m2"

    # Removing the top modal restores m1 as the active modal.
    discard wm.removeWindow(m2Id)
    check wm.modalStack.len == 1
    check wm.currentModal().get() == m1Id

    discard wm.handleEvent(keyEvent)
    check lastTarget == "m1"

    # Removing the remaining modal clears the stack — base receives events.
    discard wm.removeWindow(m1Id)
    check wm.modalStack.len == 0
    check wm.currentModal().isNone()

    discard wm.focusWindow(base.id)
    discard wm.handleEvent(keyEvent)
    check lastTarget == "base"

  test "Modal stack: removing middle modal keeps top active":
    let wm = newWindowManager()
    let m1 = newWindow(rect(5, 5, 20, 20), "M1", modal = true)
    let m2 = newWindow(rect(10, 10, 10, 10), "M2", modal = true)
    let m3 = newWindow(rect(12, 12, 6, 6), "M3", modal = true)

    let m1Id = wm.addWindow(m1)
    let m2Id = wm.addWindow(m2)
    let m3Id = wm.addWindow(m3)
    check wm.modalStack == @[m1Id, m2Id, m3Id]

    # Removing the middle modal leaves the stack with [m1, m3]; top stays m3.
    discard wm.removeWindow(m2Id)
    check wm.modalStack == @[m1Id, m3Id]
    check wm.currentModal().get() == m3Id

  test "removeWindow refocuses next active modal when top modal is removed":
    # When the focused window is the top modal and it's removed,
    # focus must move to the next-highest remaining modal so the
    # focused window stays in sync with `modalStack` (and modal
    # routing). Without this, focus could land on a non-modal window
    # underneath while modal routing would still divert events
    # elsewhere — confusing for both UI and event handling.
    let wm = newWindowManager()
    let base = newWindow(rect(0, 0, 30, 30), "Base")
    let m1 = newWindow(rect(5, 5, 20, 20), "M1", modal = true)
    let m2 = newWindow(rect(10, 10, 10, 10), "M2", modal = true)

    discard wm.addWindow(base)
    let m1Id = wm.addWindow(m1)
    let m2Id = wm.addWindow(m2)

    check wm.focusedWindow.get() == m2Id

    discard wm.removeWindow(m2Id)
    check wm.modalStack == @[m1Id]
    check wm.currentModal().get() == m1Id
    check wm.focusedWindow.get() == m1Id # not `base.id`

  test "dispatchResize broadcasts to all visible windows":
    let wm = newWindowManager()
    let w1 = newWindow(rect(0, 0, 10, 10), "W1")
    let w2 = newWindow(rect(0, 0, 10, 10), "W2")
    let w3 = newWindow(rect(0, 0, 10, 10), "W3")

    var w1Called = false
    var w2Called = false
    var w3Called = false

    w1.setResizeHandler(
      proc(w: Window, s: Size): bool =
        w1Called = true
        true
    )
    w2.setResizeHandler(
      proc(w: Window, s: Size): bool =
        w2Called = true
        true
    )
    w3.setResizeHandler(
      proc(w: Window, s: Size): bool =
        w3Called = true
        true
    )

    discard wm.addWindow(w1)
    discard wm.addWindow(w2)
    discard wm.addWindow(w3)
    w2.hide() # invisible windows are skipped

    wm.dispatchResize(size(100, 50))

    check w1Called
    check not w2Called
    check w3Called

  test "Modal window intercepts events":
    let wm = newWindowManager()
    let normalWindow = newWindow(rect(10, 10, 30, 20), "Normal")
    let modalWindow = newWindow(rect(20, 20, 30, 20), "Modal", modal = true)
    var normalHandlerCalled = false
    var modalHandlerCalled = false

    normalWindow.setKeyHandler(
      proc(w: Window, k: KeyEvent): bool =
        normalHandlerCalled = true
        return true
    )

    modalWindow.setKeyHandler(
      proc(w: Window, k: KeyEvent): bool =
        modalHandlerCalled = true
        return true
    )

    discard wm.addWindow(normalWindow)
    discard wm.addWindow(modalWindow)

    let keyEvent = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))
    let result = wm.handleEvent(keyEvent)

    check:
      result == erConsume
      not normalHandlerCalled
      modalHandlerCalled

  test "Modal drops out-of-bounds mouse clicks at the manager":
    # When a modal has only a general eventHandler (no mouseHandler),
    # the modal's per-window bounds check would not run. The manager
    # must still suppress out-of-bounds clicks so they don't leak to
    # the modal's general handler or fall through to the global
    # handler.
    let wm = newWindowManager()
    let modalWindow = newWindow(rect(20, 20, 10, 10), "Modal", modal = true)
    var generalCalled = false

    modalWindow.setEventHandler(
      proc(w: Window, e: Event): EventResult =
        generalCalled = true
        return erContinue
    )

    discard wm.addWindow(modalWindow)

    # Click outside the modal's bounds.
    let outside = Event(
      kind: EventKind.Mouse, mouse: MouseEvent(x: 0, y: 0, kind: Press, button: Left)
    )
    check wm.handleEvent(outside) == erConsume
    check not generalCalled

    # Click inside the modal's bounds is delivered normally.
    let inside = Event(
      kind: EventKind.Mouse, mouse: MouseEvent(x: 25, y: 25, kind: Press, button: Left)
    )
    discard wm.handleEvent(inside)
    check generalCalled

  test "Mouse click auto-focuses window":
    let wm = newWindowManager()
    let window1 = newWindow(rect(10, 10, 20, 15), "Window1")
    let window2 = newWindow(rect(30, 30, 20, 15), "Window2")

    let id1 = wm.addWindow(window1)
    let id2 = wm.addWindow(window2)

    # Initially window2 should be focused (last added)
    check wm.focusedWindow.get() == id2

    # Click on window1
    let mouseEvent = Event(
      kind: EventKind.Mouse, mouse: MouseEvent(x: 15, y: 15, kind: Press, button: Left)
    )
    discard wm.handleEvent(mouseEvent)

    # Window1 should now be focused
    check wm.focusedWindow.get() == id1

suite "Window State Edge Cases":
  test "Resize to minimum dimensions":
    let window = newWindow(rect(10, 10, 50, 30), "Test", some(defaultBorder()))

    # Try to resize to very small dimensions
    window.resize(size(1, 1))

    check:
      window.area.width == 1
      window.area.height == 1
      window.contentArea.width >= 1
      window.contentArea.height >= 1

  test "Border changes update content area correctly":
    let window = newWindow(rect(10, 10, 50, 30), "Test", none(WindowBorder))

    # Initially no border
    let initialContentArea = window.contentArea
    check initialContentArea == window.area

    # Add full border
    window.setBorder(some(defaultBorder()))

    check:
      window.contentArea.x == window.area.x + 1
      window.contentArea.y == window.area.y + 1
      window.contentArea.width == window.area.width - 2
      window.contentArea.height == window.area.height - 2

    # Remove border again
    window.setBorder(none(WindowBorder))

    check window.contentArea == window.area

  test "Window memory management - automatic cleanup":
    # Windows are automatically freed by Nim's GC when removed
    # This test verifies that removeWindow properly removes the window
    let wm = newWindowManager()
    let window1 = newWindow(rect(10, 10, 30, 20), "Test1")
    let window2 = newWindow(rect(20, 20, 30, 20), "Test2")

    let id1 = wm.addWindow(window1)
    let id2 = wm.addWindow(window2)

    check wm.windows.len == 2

    # Remove windows - GC will handle cleanup automatically
    check wm.removeWindow(id1) == true
    check wm.removeWindow(id2) == true

    check:
      wm.windows.len == 0
      wm.focusedWindow.isNone()

suite "Complex Integration Tests":
  test "Multiple overlapping windows with events":
    let wm = newWindowManager()
    let window1 = newWindow(rect(10, 10, 30, 20), "Back")
    let window2 = newWindow(rect(20, 15, 30, 20), "Middle")
    let window3 = newWindow(rect(25, 20, 30, 20), "Front")

    var eventCounts = [0, 0, 0]

    window1.setMouseHandler(
      proc(w: Window, m: MouseEvent): bool =
        eventCounts[0].inc
        true
    )
    window2.setMouseHandler(
      proc(w: Window, m: MouseEvent): bool =
        eventCounts[1].inc
        true
    )
    window3.setMouseHandler(
      proc(w: Window, m: MouseEvent): bool =
        eventCounts[2].inc
        true
    )

    discard wm.addWindow(window1)
    discard wm.addWindow(window2)
    discard wm.addWindow(window3)

    # Click in overlapping area - should hit topmost window
    let mouseEvent = Event(
      kind: EventKind.Mouse, mouse: MouseEvent(x: 30, y: 25, kind: Press, button: Left)
    )
    discard wm.handleEvent(mouseEvent)

    check:
      eventCounts[0] == 0 # Back window not hit
      eventCounts[1] == 0 # Middle window not hit  
      eventCounts[2] == 1 # Front window hit

  test "Window focus changes with mixed event types":
    let wm = newWindowManager()
    let window1 = newWindow(rect(10, 10, 30, 20), "Window1")
    let window2 = newWindow(rect(40, 40, 30, 20), "Window2")

    let id1 = wm.addWindow(window1)
    let id2 = wm.addWindow(window2)

    # Initially window2 focused
    check wm.focusedWindow.get() == id2

    # Mouse click on window1
    let mouseEvent = Event(
      kind: EventKind.Mouse, mouse: MouseEvent(x: 15, y: 15, kind: Press, button: Left)
    )
    discard wm.handleEvent(mouseEvent)

    check wm.focusedWindow.get() == id1

    # Key event should go to currently focused window (window1)
    var window1KeyReceived = false
    var window2KeyReceived = false

    window1.setKeyHandler(
      proc(w: Window, k: KeyEvent): bool =
        window1KeyReceived = true
        true
    )
    window2.setKeyHandler(
      proc(w: Window, k: KeyEvent): bool =
        window2KeyReceived = true
        true
    )

    let keyEvent = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Space))
    discard wm.handleEvent(keyEvent)

    check:
      window1KeyReceived
      not window2KeyReceived

suite "Window String Representation":
  test "basic window":
    let area = rect(10, 5, 50, 20)
    let window = newWindow(area, "Test Window")
    let s = $window
    check "Window(" in s
    check "\"Test Window\"" in s
    check "wsNormal" in s

  test "window without title":
    let window = newWindow(rect(0, 0, 10, 10), "")
    let s = $window
    check "\"\"" in s

suite "WindowInfo String Representation":
  test "basic window info":
    let info = WindowInfo(
      id: WindowId(1),
      title: "Info Window",
      area: rect(0, 0, 40, 20),
      state: wsNormal,
      zIndex: 0,
      visible: true,
      focused: false,
    )
    let s = $info
    check "WindowInfo(" in s
    check "\"Info Window\"" in s
    check "wsNormal" in s

{.pop.}
