## Tests for window management system

import std/[unittest, options]

import ../celina/core/[geometry, buffer, colors, events]

import ../celina/core/windows {.all.}

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
    check wm.modalWindow.isNone()

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

    wm.removeWindow(id1)

    check wm.windows.len == 1
    check wm.getWindow(id1).isNone()
    check wm.getWindow(id2).isSome()

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
    wm.focusWindow(id1)

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
    wm.focusWindow(id1)

    check window1.zIndex > window2.zIndex
    check window1.zIndex > window3.zIndex

  test "Modal window handling":
    let wm = newWindowManager()
    let normalWindow = newWindow(rect(10, 10, 30, 15), "Normal")
    let modalWindow = newWindow(rect(20, 20, 40, 20), "Modal", modal = true)

    discard wm.addWindow(normalWindow)
    let modalId = wm.addWindow(modalWindow)

    # Modal window should be focused and set as modal
    check wm.focusedWindow.get() == modalId
    check wm.modalWindow.isSome()
    check wm.modalWindow.get() == modalId

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
      wm.removeWindow(windowIds[i * 2])

    check wm.windows.len == 50

    # Focus should still work
    if windowIds.len > 1:
      wm.focusWindow(windowIds[1])
      check wm.focusedWindow.get() == windowIds[1]

suite "Window Event System Tests":
  test "WindowEvent creation and manipulation":
    let keyEvent = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))
    var windowEvent = WindowEvent(
      originalEvent: keyEvent,
      phase: epTarget,
      target: WindowId(1),
      currentTarget: WindowId(1),
      propagationStopped: false,
      defaultPrevented: false,
    )

    check:
      windowEvent.originalEvent.kind == EventKind.Key
      windowEvent.phase == epTarget
      windowEvent.target == WindowId(1)
      not windowEvent.propagationStopped
      not windowEvent.defaultPrevented

    # Test event manipulation
    windowEvent.stopPropagation()
    windowEvent.preventDefault()

    check:
      windowEvent.propagationStopped
      windowEvent.defaultPrevented

  test "Window event handler assignment":
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
      result == true
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
      result == true
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
      result == true
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
      result == true
      keyHandlerCalled
      not generalHandlerCalled # Specific handler should take precedence

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
      result == false # Should not handle events when acceptsEvents is false
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
      result == false
      not handlerCalled

suite "WindowManager Event System Tests":
  test "DispatchEvent to focused window":
    let wm = newWindowManager()
    let window = newWindow(rect(10, 10, 30, 20), "Test")
    var handlerCalled = false

    window.setKeyHandler(
      proc(w: Window, k: KeyEvent): bool =
        handlerCalled = true
        return true
    )

    let windowId = wm.addWindow(window)
    wm.focusWindow(windowId)

    let keyEvent = Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))
    let result = wm.dispatchEvent(keyEvent)

    check:
      result == true
      handlerCalled

  test "DispatchEvent mouse to window at position":
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
    let result = wm.dispatchEvent(mouseEvent)

    check:
      result == true
      not window1HandlerCalled
      window2HandlerCalled

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
      result == true
      not normalHandlerCalled
      modalHandlerCalled

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
    wm.removeWindow(id1)
    wm.removeWindow(id2)

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
