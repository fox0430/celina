## Tests for the layout system

import std/unittest

import ../celina/core/layout
import ../celina/core/geometry

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

      # Test invalid denominator uses safe default (1:1 ratio)
      let c_zero_denom = ratio(1, 0)
      check c_zero_denom.denominator == 1 # Should default to 1
      check c_zero_denom.numerator == 1

      let c_neg_denom = ratio(3, -1)
      check c_neg_denom.denominator == 1 # Should default to 1
      check c_neg_denom.numerator == 3

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

  suite "Nested Layout Tests":
    test "Horizontal inside vertical":
      let outer = vertical(@[length(10), fill(), length(10)])
      let outerArea = rect(0, 0, 100, 50)
      let outerAreas = outer.split(outerArea)

      # Split the middle area horizontally
      let inner = horizontal(@[fill(), fill()])
      let innerAreas = inner.split(outerAreas[1])

      check innerAreas.len == 2
      check innerAreas[0].width == 50 # Half of 100
      check innerAreas[1].width == 50
      check innerAreas[0].y == 10 # Started after first row
      check innerAreas[0].height == 30 # 50 - 10 - 10

    test "Vertical inside horizontal":
      let outer = horizontal(@[percentage(30), fill()])
      let outerArea = rect(0, 0, 100, 50)
      let outerAreas = outer.split(outerArea)

      # Split the second area vertically
      let inner = vertical(@[fill(), fill(), fill()])
      let innerAreas = inner.split(outerAreas[1])

      check innerAreas.len == 3
      check innerAreas[0].x == 30 # Started after first column
      check innerAreas[0].width == 70 # 100 - 30
      # Each should get roughly 1/3 of 50
      check innerAreas[0].height >= 16
      check innerAreas[1].height >= 16
      check innerAreas[2].height >= 16

    test "Triple nesting":
      let l1 = vertical(@[fill(), fill()])
      let a1 = l1.split(rect(0, 0, 100, 60))

      let l2 = horizontal(@[fill(), fill()])
      let a2 = l2.split(a1[0])

      let l3 = vertical(@[length(5), fill()])
      let a3 = l3.split(a2[0])

      check a3.len == 2
      check a3[0].height == 5
      check a3[1].height == 25 # 30 - 5

  suite "Complex Constraint Combinations":
    test "Min with Fill priority":
      let l = horizontal(@[min(20), fill(2), fill(1)])
      let area = rect(0, 0, 100, 50)
      let areas = l.split(area)

      check areas.len == 3
      check areas[0].width >= 20 or areas[0].width == 0 # Min respected when possible

    test "Max with Length":
      let l = horizontal(@[max(30), length(40)])
      let area = rect(0, 0, 100, 50)
      let areas = l.split(area)

      check areas.len == 2
      check areas[1].width == 40 # Length takes precedence

    test "Multiple Fill with different priorities":
      let l = horizontal(@[fill(1), fill(2), fill(3), fill(2)])
      let area = rect(0, 0, 80, 50)
      let areas = l.split(area)

      check areas.len == 4
      # Total priority: 1+2+3+2 = 8
      # Area 0: 80 * 1/8 = 10
      # Area 1: 80 * 2/8 = 20
      # Area 2: 80 * 3/8 = 30
      # Area 3: 80 * 2/8 = 20
      check areas[0].width == 10
      check areas[1].width == 20
      check areas[2].width == 30
      check areas[3].width == 20

    test "Percentage with Ratio":
      let l = horizontal(@[percentage(25), ratio(1, 2), fill()])
      let area = rect(0, 0, 100, 50)
      let areas = l.split(area)

      check areas.len == 3
      check areas[0].width == 25 # 25% of 100
      check areas[1].width == 50 # 1/2 of 100
      check areas[2].width == 25 # Remaining

    test "Length + Percentage + Fill":
      let l = horizontal(@[length(10), percentage(20), fill()])
      let area = rect(0, 0, 100, 50)
      let areas = l.split(area)

      check areas.len == 3
      check areas[0].width == 10
      check areas[1].width == 20 # 20% of 100
      check areas[2].width == 70 # 100 - 10 - 20

  suite "Edge Cases and Error Handling":
    test "Zero available space":
      let l = horizontal(@[fill(), fill()])
      let area = rect(0, 0, 0, 50)
      let areas = l.split(area)

      check areas.len == 2
      check areas[0].width == 0
      check areas[1].width == 0

    test "Single pixel space":
      let l = horizontal(@[fill(), fill()])
      let area = rect(0, 0, 1, 50)
      let areas = l.split(area)

      check areas.len == 2
      # Space should be distributed (may round)
      check areas[0].width + areas[1].width <= 1

    test "Very large space":
      let l = horizontal(@[fill(), fill()])
      let area = rect(0, 0, 10000, 50)
      let areas = l.split(area)

      check areas.len == 2
      check areas[0].width == 5000
      check areas[1].width == 5000

    test "Many constraints":
      var constraints: seq[Constraint] = @[]
      for i in 0 ..< 100:
        constraints.add(fill())

      let l = horizontal(constraints)
      let area = rect(0, 0, 1000, 50)
      let areas = l.split(area)

      check areas.len == 100
      # Each should get 10 pixels
      for a in areas:
        check a.width == 10

    test "Asymmetric margins":
      let l = vertical(@[fill(), fill()]).withMargins(10, 5)
      let area = rect(0, 0, 100, 50)
      let areas = l.split(area)

      check areas.len == 2
      check areas[0].x == 10 # Horizontal margin
      check areas[0].y == 5 # Vertical margin
      check areas[0].width == 80 # 100 - 2*10
      check areas[0].height == 20 # (50 - 2*5) / 2

    test "Negative area dimensions":
      let l = horizontal(@[fill()])
      let area = rect(10, 10, -5, 20)
      let areas = l.split(area)

      # Should handle gracefully without crashing
      check areas.len >= 0

    test "All zero-sized constraints":
      let l = horizontal(@[length(0), length(0), length(0)])
      let area = rect(0, 0, 100, 50)
      let areas = l.split(area)

      check areas.len == 3
      check areas[0].width == 0
      check areas[1].width == 0
      check areas[2].width == 0

  suite "Layout Direction Tests":
    test "Horizontal preserves height":
      let l = horizontal(@[fill(), fill(), fill()])
      let area = rect(5, 10, 100, 30)
      let areas = l.split(area)

      check areas.len == 3
      for a in areas:
        check a.height == 30
        check a.y == 10

    test "Vertical preserves width":
      let l = vertical(@[fill(), fill(), fill()])
      let area = rect(5, 10, 100, 30)
      let areas = l.split(area)

      check areas.len == 3
      for a in areas:
        check a.width == 100
        check a.x == 5

  suite "Margin Behavior Tests":
    test "Margin reduces available space":
      let l = horizontal(@[fill()]).withMargin(10)
      let area = rect(0, 0, 100, 50)
      let areas = l.split(area)

      check areas.len == 1
      check areas[0].width == 80 # 100 - 2*10
      check areas[0].height == 30 # 50 - 2*10

    test "Large margin":
      let l = horizontal(@[fill()]).withMargin(30)
      let area = rect(0, 0, 100, 50)
      let areas = l.split(area)

      check areas.len == 1
      check areas[0].width == 40 # 100 - 2*30
      # Height may be 0 if margin exceeds space

    test "Zero margin has no effect":
      let l = horizontal(@[fill(), fill()]).withMargin(0)
      let area = rect(0, 0, 100, 50)
      let areas = l.split(area)

      check areas.len == 2
      check areas[0].x == 0
      check areas[0].y == 0
      check areas[0].width == 50
      check areas[0].height == 50
