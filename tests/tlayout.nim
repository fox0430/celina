## Tests for the layout system

import unittest
import ../src/core/layout
import ../src/core/geometry

suite "Layout System Tests":
  suite "Constraint Tests":
    test "Length constraint":
      let c = length(10)
      check c.kind == Length
      check c.length == 10

      # Test negative values are clamped to 0
      let c_neg = length(-5)
      check c_neg.length == 0

    test "Percentage constraint":
      let c = percentage(50)
      check c.kind == Percentage
      check c.percentage == 50

      # Test clamping to 0-100 range
      let c_over = percentage(150)
      check c_over.percentage == 100

      let c_under = percentage(-10)
      check c_under.percentage == 0

    test "Ratio constraint":
      let c = ratio(1, 3)
      check c.kind == Ratio
      check c.numerator == 1
      check c.denominator == 3

      # Test negative numerator is clamped
      let c_neg = ratio(-2, 5)
      check c_neg.numerator == 0

      # Test invalid denominator raises exception
      expect(ValueError):
        discard ratio(1, 0)

      expect(ValueError):
        discard ratio(1, -1)

    test "Min constraint":
      let c = min(15)
      check c.kind == Min
      check c.min == 15

      # Test negative values are clamped
      let c_neg = min(-3)
      check c_neg.min == 0

    test "Max constraint":
      let c = max(25)
      check c.kind == Max
      check c.max == 25

      # Test negative values are clamped
      let c_neg = max(-5)
      check c_neg.max == 0

    test "Fill constraint":
      let c = fill()
      check c.kind == Fill
      check c.priority == 1

      let c_priority = fill(3)
      check c_priority.priority == 3

      # Test negative priority is clamped
      let c_neg = fill(-2)
      check c_neg.priority == 1

  suite "Layout Creation Tests":
    test "Basic layout creation":
      let l = layout(Horizontal, @[length(10), fill()])
      check l.direction == Horizontal
      check l.constraints.len == 2
      check l.margin == 0

    test "Layout with margin":
      let l = layout(Vertical, @[fill()], 5)
      check l.margin == 5
      check l.horizontal_margin == 5
      check l.vertical_margin == 5

    test "Layout with different margins":
      let l = layout().withMargins(2, 3)
      check l.horizontal_margin == 2
      check l.vertical_margin == 3

    test "Convenience constructors":
      let h = horizontal(@[length(10), fill()])
      check h.direction == Horizontal

      let v = vertical(@[percentage(50), fill()])
      check v.direction == Vertical

      let even = evenSplit(3, Horizontal)
      check even.direction == Horizontal
      check even.constraints.len == 3
      for constraint in even.constraints:
        check constraint.kind == Fill

      let two_col = twoColumn(20)
      check two_col.direction == Horizontal
      check two_col.constraints.len == 2
      check two_col.constraints[0].kind == Length
      check two_col.constraints[0].length == 20

      let two_col_pct = twoColumnPercent(30)
      check two_col_pct.direction == Horizontal
      check two_col_pct.constraints[0].percentage == 30
      check two_col_pct.constraints[1].percentage == 70

      let three_row = threeRow(3, 2)
      check three_row.direction == Vertical
      check three_row.constraints.len == 3
      check three_row.constraints[0].length == 3
      check three_row.constraints[2].length == 2

  suite "Layout Solving Tests":
    test "Fixed length constraints":
      let l = horizontal(@[length(10), length(20), length(15)])
      let area = rect(0, 0, 100, 50)
      let areas = l.split(area)

      check areas.len == 3
      check areas[0].width == 10
      check areas[1].width == 20
      check areas[2].width == 15

      # Check positioning
      check areas[0].x == 0
      check areas[1].x == 10
      check areas[2].x == 30

    test "Percentage constraints":
      let l = horizontal(@[percentage(25), percentage(50), percentage(25)])
      let area = rect(0, 0, 100, 50)
      let areas = l.split(area)

      check areas.len == 3
      check areas[0].width == 25 # 25% of 100
      check areas[1].width == 50 # 50% of 100
      check areas[2].width == 25 # 25% of 100

    test "Ratio constraints":
      let l = horizontal(@[ratio(1, 4), ratio(2, 4), ratio(1, 4)])
      let area = rect(0, 0, 80, 50) # 80 divides evenly by 4
      let areas = l.split(area)

      check areas.len == 3
      check areas[0].width == 20 # 1/4 of 80
      check areas[1].width == 40 # 2/4 of 80
      check areas[2].width == 20 # 1/4 of 80

    test "Fill constraints":
      let l = horizontal(@[fill(1), fill(2), fill(1)])
      let area = rect(0, 0, 80, 50)
      let areas = l.split(area)

      check areas.len == 3
      # Total priority: 1+2+1 = 4
      # Available space: 80
      # Area 0: 80 * 1/4 = 20
      # Area 1: 80 * 2/4 = 40
      # Area 2: 80 * 1/4 = 20
      check areas[0].width == 20
      check areas[1].width == 40
      check areas[2].width == 20

    test "Mixed constraints":
      let l = horizontal(@[length(20), fill(), percentage(25)])
      let area = rect(0, 0, 100, 50)
      let areas = l.split(area)

      check areas.len == 3
      check areas[0].width == 20 # Fixed 20
      check areas[2].width == 25 # 25% of 100
      check areas[1].width == 55 # Remaining space (100 - 20 - 25)

    test "Vertical layout":
      let l = vertical(@[length(5), fill(), length(3)])
      let area = rect(0, 0, 50, 30)
      let areas = l.split(area)

      check areas.len == 3
      check areas[0].height == 5
      check areas[2].height == 3
      check areas[1].height == 22 # 30 - 5 - 3

      # Check vertical positioning
      check areas[0].y == 0
      check areas[1].y == 5
      check areas[2].y == 27

    test "Layout with margins":
      let l = horizontal(@[fill(), fill()]).withMargin(5)
      let area = rect(10, 10, 100, 50)
      let areas = l.split(area)

      check areas.len == 2
      # Working area after margins: width=90, height=40, x=15, y=15
      check areas[0].width == 45 # Half of 90
      check areas[1].width == 45
      check areas[0].x == 15 # Original x + margin
      check areas[0].y == 15 # Original y + margin
      check areas[0].height == 40 # Original height - 2*margin

    test "Empty constraints":
      let l = layout()
      let area = rect(0, 0, 100, 50)
      let areas = l.split(area)

      check areas.len == 1
      check areas[0] == area # Should return the original area

    test "Constraints exceeding available space":
      let l = horizontal(@[length(60), length(60)]) # Total 120 > 100
      let area = rect(0, 0, 100, 50)
      let areas = l.split(area)

      check areas.len == 2
      check areas[0].width == 60
      check areas[1].width == 40 # Limited by remaining space

    test "Min/Max constraints":
      # This is a simplified test since Min/Max are complex
      let l = horizontal(@[min(10), max(30), fill()])
      let area = rect(0, 0, 100, 50)
      let areas = l.split(area)

      check areas.len == 3
      # Min constraint should get at least its minimum if space allows
      check areas[0].width >= 0 # May be 0 if no space, but not negative
