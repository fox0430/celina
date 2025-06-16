## Tests for window management system

import std/[unittest, options]
import ../src/core/[windows, geometry, buffer]

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
    let id2 = wm.addWindow(window2)
    let id3 = wm.addWindow(window3)

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

    let normalId = wm.addWindow(normalWindow)
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
    let id2 = wm.addWindow(window2)
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

    let id1 = wm.addWindow(window1)
    let id2 = wm.addWindow(window2)

    wm.render(destBuffer)

    # In overlapping area, front window should be visible
    # Window2 starts at (10, 8), so position (10, 8) should show window2's content
    # But we need to account for borders, so actual content starts at (11, 9)
    check destBuffer[11, 9].symbol == "F" # First character of "FRONT"
