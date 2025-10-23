import std/[unittest, strutils]

import ../celina/widgets/base
import ../celina/core/[geometry, buffer, colors]

# Custom widget types for testing (must be at top level)
type
  CustomWidget = ref object of Widget

  CounterWidget = ref object of Widget
    count: int

# Methods must be defined at top level
method getPreferredSize(widget: CustomWidget, available: Size): Size =
  size(200, 100) # Request more than available

method render(widget: CounterWidget, area: Rect, buf: var Buffer) =
  # Simple render that puts count in buffer
  if area.width > 0 and area.height > 0:
    buf.setString(area.x, area.y, $widget.count, defaultStyle())

# Test suite for Base widget module
suite "Base Widget Tests":
  suite "Widget Creation":
    test "Create base widget":
      let widget = newWidget()
      check widget != nil

    test "Base widget has default render method":
      let widget = newWidget()
      var buf = newBuffer(10, 10)
      let area = rect(0, 0, 10, 10)

      # Should not crash
      widget.render(area, buf)

  suite "Widget Sizing":
    test "Default getMinSize returns zero size":
      let widget = newWidget()
      let minSize = widget.getMinSize()

      check minSize.width == 0
      check minSize.height == 0

    test "Default getPreferredSize returns available size":
      let widget = newWidget()
      let available = size(100, 50)
      let preferred = widget.getPreferredSize(available)

      check preferred.width == available.width
      check preferred.height == available.height

    test "measureWidget respects constraints":
      let widget = newWidget()
      let available = size(100, 50)
      let measured = measureWidget(widget, available)

      check measured.width <= available.width
      check measured.height <= available.height

  suite "Widget Focus":
    test "Default canFocus returns false":
      let widget = newWidget()
      check widget.canFocus() == false

  suite "StatefulWidget Creation":
    type TestState = object
      counter: int
      name: string

    test "Create stateful widget with int state":
      let widget = newStatefulWidget(0)
      check widget != nil
      check widget.state == 0

    test "Create stateful widget with custom state":
      let initialState = TestState(counter: 0, name: "test")
      let widget = newStatefulWidget(initialState)

      check widget != nil
      check widget.state.counter == 0
      check widget.state.name == "test"

  suite "StatefulWidget State Management":
    test "getState returns current state":
      let widget = newStatefulWidget(42)
      let state = widget.getState()

      check state == 42

    test "setState updates state":
      let widget = newStatefulWidget(10)
      widget.setState(20)

      check widget.getState() == 20

    test "updateState with function":
      let widget = newStatefulWidget(5)

      widget.updateState(
        proc(state: int): int =
          state * 2
      )

      check widget.getState() == 10

    test "updateState with complex state":
      type ComplexState = object
        count: int
        enabled: bool

      let widget = newStatefulWidget(ComplexState(count: 0, enabled: false))

      widget.updateState(
        proc(state: ComplexState): ComplexState =
          ComplexState(count: state.count + 1, enabled: true)
      )

      let finalState = widget.getState()
      check finalState.count == 1
      check finalState.enabled == true

  suite "Widget Rendering Utilities":
    test "renderWidget convenience function":
      let widget = newWidget()
      var buf = newBuffer(10, 10)
      let area = rect(0, 0, 10, 10)

      renderWidget(widget, area, buf)
      # Should not crash

    test "renderWidgetAt convenience function":
      let widget = newWidget()
      var buf = newBuffer(20, 20)

      renderWidgetAt(widget, 5, 5, 10, 10, buf)
      # Should not crash

  suite "Size Constraint Utilities":
    test "constrainSize within bounds":
      let requested = size(50, 50)
      let available = size(100, 100)
      let minimum = size(10, 10)

      let constrained = constrainSize(requested, available, minimum)

      check constrained.width == 50
      check constrained.height == 50

    test "constrainSize respects maximum":
      let requested = size(150, 150)
      let available = size(100, 100)
      let minimum = size(10, 10)

      let constrained = constrainSize(requested, available, minimum)

      check constrained.width == 100
      check constrained.height == 100

    test "constrainSize respects minimum":
      let requested = size(5, 5)
      let available = size(100, 100)
      let minimum = size(10, 10)

      let constrained = constrainSize(requested, available, minimum)

      check constrained.width == 10
      check constrained.height == 10

    test "constrainSize with conflicting constraints":
      # When minimum > available, minimum wins
      let requested = size(50, 50)
      let available = size(20, 20)
      let minimum = size(30, 30)

      let constrained = constrainSize(requested, available, minimum)

      check constrained.width == 30
      check constrained.height == 30

  suite "Widget Measurement":
    test "measureWidget with zero minimum":
      let widget = newWidget()
      let available = size(100, 50)
      let measured = measureWidget(widget, available)

      # Widget has no minimum, wants all available space
      check measured.width == 100
      check measured.height == 50

    test "measureWidget constrains to available":
      let widget = CustomWidget()
      let available = size(100, 50)
      let measured = measureWidget(widget, available)

      # Should be constrained to available
      check measured.width == 100
      check measured.height == 50

  suite "Custom Widget Types":
    test "Custom widget render override":
      let widget = CounterWidget(count: 42)
      var buf = newBuffer(10, 10)
      let area = rect(0, 0, 10, 10)

      widget.render(area, buf)

      let cell = buf[0, 0]
      check "42" in cell.symbol or cell.symbol == "4"

  suite "Stateful Widget Rendering":
    test "renderStateful does not crash":
      type TestState = object
        value: int

      let widget = newStatefulWidget(TestState(value: 10))
      var buf = newBuffer(10, 10)
      let area = rect(0, 0, 10, 10)

      renderStateful(widget, area, buf)
      # Default implementation does nothing but should not crash

  suite "Edge Cases":
    test "Widget with zero-sized area":
      let widget = newWidget()
      var buf = newBuffer(10, 10)
      let area = rect(0, 0, 0, 0)

      widget.render(area, buf)
      # Should handle gracefully

    test "measureWidget with zero available space":
      let widget = newWidget()
      let available = size(0, 0)
      let measured = measureWidget(widget, available)

      check measured.width == 0
      check measured.height == 0

    test "constrainSize with all zeros":
      let requested = size(0, 0)
      let available = size(0, 0)
      let minimum = size(0, 0)

      let constrained = constrainSize(requested, available, minimum)

      check constrained.width == 0
      check constrained.height == 0

    test "Multiple state updates":
      let widget = newStatefulWidget(0)

      for i in 1 .. 10:
        widget.setState(i)

      check widget.getState() == 10

    test "Stateful widget with string state":
      let widget = newStatefulWidget("initial")

      widget.setState("updated")
      check widget.getState() == "updated"

      widget.updateState(
        proc(s: string): string =
          s & " more"
      )
      check widget.getState() == "updated more"
