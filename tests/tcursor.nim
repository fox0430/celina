import std/unittest

import ../celina/core/[cursor, terminal_common]

# Test suite for Cursor module
suite "Cursor Module Tests":
  suite "CursorManager Creation":
    test "Create new cursor manager":
      let manager = newCursorManager()
      check manager != nil

    test "Initial state is correct":
      let manager = newCursorManager()
      let (x, y) = manager.getPosition()
      check x == -1
      check y == -1
      check manager.isVisible() == false
      check manager.getStyle() == CursorStyle.Default

  suite "Position Management":
    test "Set cursor position":
      let manager = newCursorManager()
      manager.setPosition(10, 20)
      let (x, y) = manager.getPosition()
      check x == 10
      check y == 20

    test "Position with visibility":
      let manager = newCursorManager()
      manager.setPosition(5, 10, false)
      let (x, y) = manager.getPosition()
      check x == 5
      check y == 10
      check manager.isVisible() == false

    test "hasPosition returns correct value":
      let manager = newCursorManager()
      check manager.hasPosition() == false

      manager.setPosition(0, 0)
      check manager.hasPosition() == true

      manager.setPosition(-1, 5)
      check manager.hasPosition() == false

  suite "Visibility Control":
    test "Show cursor":
      let manager = newCursorManager()
      manager.show()
      check manager.isVisible() == true

    test "Hide cursor":
      let manager = newCursorManager()
      manager.show()
      manager.hide()
      check manager.isVisible() == false

    test "setPosition makes cursor visible by default":
      let manager = newCursorManager()
      manager.setPosition(10, 10)
      check manager.isVisible() == true

  suite "Style Management":
    test "Set cursor style":
      let manager = newCursorManager()
      manager.setStyle(CursorStyle.SteadyBlock)
      check manager.getStyle() == CursorStyle.SteadyBlock

    test "Style change detection":
      let manager = newCursorManager()
      check manager.styleChanged() == false

      manager.setStyle(CursorStyle.SteadyUnderline)
      check manager.styleChanged() == true

      manager.updateLastStyle()
      check manager.styleChanged() == false

    test "Multiple style changes":
      let manager = newCursorManager()
      manager.setStyle(CursorStyle.SteadyBlock)
      manager.updateLastStyle()

      manager.setStyle(CursorStyle.SteadyBar)
      check manager.styleChanged() == true
      check manager.getStyle() == CursorStyle.SteadyBar

  suite "State Management":
    test "Get full cursor state":
      let manager = newCursorManager()
      manager.setPosition(15, 25)
      manager.setStyle(CursorStyle.SteadyBlock)

      let state = manager.getState()
      check state.x == 15
      check state.y == 25
      check state.visible == true
      check state.style == CursorStyle.SteadyBlock

    test "Reset cursor state":
      let manager = newCursorManager()
      manager.setPosition(10, 20)
      manager.setStyle(CursorStyle.SteadyUnderline)
      manager.show()

      manager.reset()

      let (x, y) = manager.getPosition()
      check x == -1
      check y == -1
      check manager.isVisible() == false
      check manager.getStyle() == CursorStyle.Default
      check manager.hasPosition() == false

  suite "Edge Cases":
    test "Zero position is valid":
      let manager = newCursorManager()
      manager.setPosition(0, 0)
      check manager.hasPosition() == true
      let (x, y) = manager.getPosition()
      check x == 0
      check y == 0

    test "Negative position is invalid":
      let manager = newCursorManager()
      manager.setPosition(-5, -10)
      check manager.hasPosition() == false

    test "Mixed positive and negative position":
      let manager = newCursorManager()
      manager.setPosition(10, -5)
      check manager.hasPosition() == false

      manager.setPosition(-5, 10)
      check manager.hasPosition() == false
