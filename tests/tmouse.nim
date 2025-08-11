import std/unittest

import ../src/core/events

suite "Mouse event tests":
  test "MouseEvent creation":
    let mouseEvent =
      MouseEvent(kind: Press, button: Left, x: 10, y: 20, modifiers: {Ctrl})

    check mouseEvent.kind == Press
    check mouseEvent.button == Left
    check mouseEvent.x == 10
    check mouseEvent.y == 20
    check Ctrl in mouseEvent.modifiers

  test "Event with MouseEvent":
    let mouseEvent =
      MouseEvent(kind: Press, button: Right, x: 5, y: 15, modifiers: {Shift, Alt})

    let event = Event(kind: Mouse, mouse: mouseEvent)

    check event.kind == Mouse
    check event.mouse.button == Right
    check event.mouse.x == 5
    check event.mouse.y == 15
    check Shift in event.mouse.modifiers
    check Alt in event.mouse.modifiers

  test "Mouse button types":
    check Left != Right
    check Right != Middle
    check Middle != WheelUp
    check WheelUp != WheelDown

  test "Mouse event kinds":
    check Press != Release
    check Release != Move
    check Move != Drag

  test "Mouse event with all modifiers":
    let mouseEvent = MouseEvent(
      kind: Drag, button: Middle, x: 100, y: 200, modifiers: {Ctrl, Alt, Shift}
    )

    check mouseEvent.kind == Drag
    check mouseEvent.button == Middle
    check Ctrl in mouseEvent.modifiers
    check Alt in mouseEvent.modifiers
    check Shift in mouseEvent.modifiers

  test "Mouse event with no modifiers":
    let mouseEvent = MouseEvent(kind: Move, button: Left, x: 0, y: 0, modifiers: {})

    check mouseEvent.modifiers == {}
    check mouseEvent.x == 0
    check mouseEvent.y == 0

when isMainModule:
  echo "Running mouse event tests..."
