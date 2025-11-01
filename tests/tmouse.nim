import std/unittest

import ../celina/core/events

suite "MouseEvent Creation":
  test "MouseEvent creation with Press":
    let mouseEvent =
      MouseEvent(kind: Press, button: Left, x: 10, y: 20, modifiers: {Ctrl})

    check mouseEvent.kind == Press
    check mouseEvent.button == Left
    check mouseEvent.x == 10
    check mouseEvent.y == 20
    check Ctrl in mouseEvent.modifiers

  test "MouseEvent creation with Release":
    let mouseEvent =
      MouseEvent(kind: Release, button: Right, x: 5, y: 15, modifiers: {})

    check mouseEvent.kind == Release
    check mouseEvent.button == Right
    check mouseEvent.x == 5
    check mouseEvent.y == 15

  test "MouseEvent creation with Move":
    let mouseEvent = MouseEvent(kind: Move, button: Left, x: 100, y: 100, modifiers: {})

    check mouseEvent.kind == Move
    check mouseEvent.button == Left

  test "MouseEvent creation with Drag":
    let mouseEvent =
      MouseEvent(kind: Drag, button: Middle, x: 50, y: 50, modifiers: {Shift})

    check mouseEvent.kind == Drag
    check mouseEvent.button == Middle
    check Shift in mouseEvent.modifiers

suite "Event with MouseEvent":
  test "Event wrapping MouseEvent":
    let mouseEvent =
      MouseEvent(kind: Press, button: Right, x: 5, y: 15, modifiers: {Shift, Alt})

    let event = Event(kind: Mouse, mouse: mouseEvent)

    check event.kind == Mouse
    check event.mouse.button == Right
    check event.mouse.x == 5
    check event.mouse.y == 15
    check Shift in event.mouse.modifiers
    check Alt in event.mouse.modifiers

  test "Event with different mouse buttons":
    let leftEvent = Event(
      kind: Mouse,
      mouse: MouseEvent(kind: Press, button: Left, x: 0, y: 0, modifiers: {}),
    )
    let rightEvent = Event(
      kind: Mouse,
      mouse: MouseEvent(kind: Press, button: Right, x: 0, y: 0, modifiers: {}),
    )
    let middleEvent = Event(
      kind: Mouse,
      mouse: MouseEvent(kind: Press, button: Middle, x: 0, y: 0, modifiers: {}),
    )

    check leftEvent.mouse.button == Left
    check rightEvent.mouse.button == Right
    check middleEvent.mouse.button == Middle

suite "Mouse Button Types":
  test "Mouse button types are distinct":
    check Left != Right
    check Right != Middle
    check Middle != WheelUp
    check WheelUp != WheelDown

  test "All mouse button types exist":
    var buttons = @[Left, Right, Middle, WheelUp, WheelDown]
    check buttons.len == 5

suite "Mouse Event Kinds":
  test "Mouse event kinds are distinct":
    check Press != Release
    check Release != Move
    check Move != Drag

  test "All mouse event kinds exist":
    var kinds = @[Press, Release, Move, Drag]
    check kinds.len == 4

suite "Mouse Event Modifiers":
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

  test "Mouse event with single modifier":
    let ctrlEvent = MouseEvent(kind: Press, button: Left, x: 0, y: 0, modifiers: {Ctrl})
    let altEvent = MouseEvent(kind: Press, button: Left, x: 0, y: 0, modifiers: {Alt})
    let shiftEvent =
      MouseEvent(kind: Press, button: Left, x: 0, y: 0, modifiers: {Shift})

    check Ctrl in ctrlEvent.modifiers
    check Alt in altEvent.modifiers
    check Shift in shiftEvent.modifiers

  test "Mouse event with multiple modifiers":
    let event1 =
      MouseEvent(kind: Press, button: Left, x: 0, y: 0, modifiers: {Ctrl, Alt})
    let event2 =
      MouseEvent(kind: Press, button: Left, x: 0, y: 0, modifiers: {Shift, Alt})
    let event3 =
      MouseEvent(kind: Press, button: Left, x: 0, y: 0, modifiers: {Ctrl, Shift})

    check Ctrl in event1.modifiers and Alt in event1.modifiers
    check Shift in event2.modifiers and Alt in event2.modifiers
    check Ctrl in event3.modifiers and Shift in event3.modifiers

suite "Mouse Event Coordinates":
  test "Mouse event at origin":
    let mouseEvent = MouseEvent(kind: Press, button: Left, x: 0, y: 0, modifiers: {})

    check mouseEvent.x == 0
    check mouseEvent.y == 0

  test "Mouse event at positive coordinates":
    let mouseEvent =
      MouseEvent(kind: Press, button: Left, x: 100, y: 200, modifiers: {})

    check mouseEvent.x == 100
    check mouseEvent.y == 200

  test "Mouse event with various coordinates":
    let event1 = MouseEvent(kind: Move, button: Left, x: 1, y: 1, modifiers: {})
    let event2 = MouseEvent(kind: Move, button: Left, x: 50, y: 25, modifiers: {})
    let event3 = MouseEvent(kind: Move, button: Left, x: 999, y: 999, modifiers: {})

    check event1.x == 1 and event1.y == 1
    check event2.x == 50 and event2.y == 25
    check event3.x == 999 and event3.y == 999

suite "Mouse Event Combinations":
  test "Wheel events with modifiers":
    let wheelUpCtrl =
      MouseEvent(kind: Press, button: WheelUp, x: 10, y: 10, modifiers: {Ctrl})
    let wheelDownShift =
      MouseEvent(kind: Press, button: WheelDown, x: 10, y: 10, modifiers: {Shift})

    check wheelUpCtrl.button == WheelUp
    check Ctrl in wheelUpCtrl.modifiers
    check wheelDownShift.button == WheelDown
    check Shift in wheelDownShift.modifiers

  test "Drag event sequence":
    let pressEvent = MouseEvent(kind: Press, button: Left, x: 10, y: 10, modifiers: {})
    let dragEvent = MouseEvent(kind: Drag, button: Left, x: 20, y: 20, modifiers: {})
    let releaseEvent =
      MouseEvent(kind: Release, button: Left, x: 20, y: 20, modifiers: {})

    check pressEvent.kind == Press
    check dragEvent.kind == Drag
    check releaseEvent.kind == Release
    check dragEvent.x != pressEvent.x # Mouse moved during drag

when isMainModule:
  echo "Running mouse event tests..."
