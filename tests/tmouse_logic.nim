## Tests for mouse_logic module
##
## This test suite verifies that the shared mouse parsing logic
## works correctly for both sync and async implementations.

import unittest
import ../celina/core/[mouse_logic, events]

suite "Mouse Logic - X10 Format Parsing":
  test "Left button click at position (7, 17)":
    let data: array[3, char] = [char(0x00), char(40), char(50)]
    let result = parseMouseDataX10(data)

    check result.button == Left
    check result.kind == Press
    check result.x == 7 # 40 - 33
    check result.y == 17 # 50 - 33
    check result.modifiers == {}

  test "Middle button click":
    let data: array[3, char] = [char(0x01), char(35), char(45)]
    let result = parseMouseDataX10(data)

    check result.button == Middle
    check result.kind == Press
    check result.x == 2 # 35 - 33
    check result.y == 12 # 45 - 33

  test "Right button click":
    let data: array[3, char] = [char(0x02), char(50), char(60)]
    let result = parseMouseDataX10(data)

    check result.button == Right
    check result.kind == Press
    check result.x == 17 # 50 - 33
    check result.y == 27 # 60 - 33

  test "Wheel up event":
    let data: array[3, char] = [char(0x40), char(45), char(55)]
    let result = parseMouseDataX10(data)

    check result.button == WheelUp
    check result.kind == Press
    check result.x == 12 # 45 - 33
    check result.y == 22 # 55 - 33

  test "Wheel down event":
    let data: array[3, char] = [char(0x41), char(50), char(60)]
    let result = parseMouseDataX10(data)

    check result.button == WheelDown
    check result.kind == Press
    check result.x == 17
    check result.y == 27

  test "Drag event":
    let data: array[3, char] = [char(0x20), char(40), char(50)]
    let result = parseMouseDataX10(data)

    check result.kind == Drag

  test "Release event":
    let data: array[3, char] = [char(0x03), char(40), char(50)]
    let result = parseMouseDataX10(data)

    check result.kind == Release

suite "Mouse Logic - Modifiers":
  test "Left click with Shift":
    let data: array[3, char] = [char(0x04), char(40), char(50)]
    let result = parseMouseDataX10(data)

    check result.button == Left
    check result.modifiers == {Shift}

  test "Left click with Alt":
    let data: array[3, char] = [char(0x08), char(40), char(50)]
    let result = parseMouseDataX10(data)

    check result.button == Left
    check result.modifiers == {Alt}

  test "Left click with Ctrl":
    let data: array[3, char] = [char(0x10), char(40), char(50)]
    let result = parseMouseDataX10(data)

    check result.button == Left
    check result.modifiers == {Ctrl}

  test "Left click with Ctrl+Shift":
    let data: array[3, char] = [char(0x14), char(40), char(50)]
    let result = parseMouseDataX10(data)

    check result.button == Left
    check result.modifiers == {Ctrl, Shift}

  test "Left click with Ctrl+Alt":
    let data: array[3, char] = [char(0x18), char(40), char(50)]
    let result = parseMouseDataX10(data)

    check result.button == Left
    check result.modifiers == {Ctrl, Alt}

  test "Left click with all modifiers":
    let data: array[3, char] = [char(0x1C), char(40), char(50)]
    let result = parseMouseDataX10(data)

    check result.button == Left
    check result.modifiers == {Ctrl, Alt, Shift}

suite "Mouse Logic - SGR Format Parsing":
  test "Left button press at (10, 20)":
    let result = parseMouseDataSGR(0, 10, 20, false)

    check result.button == Left
    check result.kind == Press
    check result.x == 10
    check result.y == 20
    check result.modifiers == {}

  test "Right button release":
    let result = parseMouseDataSGR(2, 15, 25, true)

    check result.button == Right
    check result.kind == Release
    check result.x == 15
    check result.y == 25

  test "Wheel up":
    let result = parseMouseDataSGR(0x40, 12, 22, false)

    check result.button == WheelUp
    check result.kind == Press

  test "Wheel down":
    let result = parseMouseDataSGR(0x41, 12, 22, false)

    check result.button == WheelDown
    check result.kind == Press

  test "Drag with button 0":
    let result = parseMouseDataSGR(0x20, 10, 20, false)

    check result.button == Left
    check result.kind == Drag

  test "SGR with Ctrl modifier":
    let result = parseMouseDataSGR(0x10, 10, 20, false)

    check result.modifiers == {Ctrl}

# Note: Event conversion is tested indirectly through events.nim integration tests

suite "Mouse Logic - Modifier Parsing":
  test "Parse no modifiers":
    let mods = parseMouseModifiers(0x00)
    check mods == {}

  test "Parse Shift only":
    let mods = parseMouseModifiers(0x04)
    check mods == {Shift}

  test "Parse Alt only":
    let mods = parseMouseModifiers(0x08)
    check mods == {Alt}

  test "Parse Ctrl only":
    let mods = parseMouseModifiers(0x10)
    check mods == {Ctrl}

  test "Parse all modifiers":
    let mods = parseMouseModifiers(0x1C)
    check mods == {Shift, Alt, Ctrl}
