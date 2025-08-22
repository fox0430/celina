# Test suite for Geometry module

import std/[unittest, strformat]

import ../celina/core/geometry

suite "Geometry Module Tests":
  suite "Position Tests":
    test "Position creation with pos()":
      let p = pos(10, 20)
      check p.x == 10
      check p.y == 20

    test "Position direct creation":
      let p = Position(x: 5, y: 15)
      check p.x == 5
      check p.y == 15

    test "Position addition":
      let p1 = pos(10, 20)
      let p2 = pos(5, 8)
      let result = p1 + p2
      check result.x == 15
      check result.y == 28

    test "Position subtraction":
      let p1 = pos(20, 30)
      let p2 = pos(5, 10)
      let result = p1 - p2
      check result.x == 15
      check result.y == 20

    test "Position string representation":
      let p = pos(42, 84)
      check $p == "(42, 84)"

    test "Position with negative coordinates":
      let p = pos(-10, -5)
      check p.x == -10
      check p.y == -5
      check $p == "(-10, -5)"

  suite "Size Tests":
    test "Size creation with size()":
      let s = size(100, 50)
      check s.width == 100
      check s.height == 50

    test "Size direct creation":
      let s = Size(width: 80, height: 24)
      check s.width == 80
      check s.height == 24

    test "Size area calculation":
      let s = size(10, 20)
      check s.area() == 200

    test "Size area calculation with zero":
      let s1 = size(0, 10)
      let s2 = size(10, 0)
      let s3 = size(0, 0)
      check s1.area() == 0
      check s2.area() == 0
      check s3.area() == 0

    test "Size string representation":
      let s = size(640, 480)
      check $s == "640x480"

    test "Size validation - valid sizes":
      let s1 = size(10, 20)
      let s2 = size(1, 1)
      let s3 = size(1000, 800)
      check s1.isValid()
      check s2.isValid()
      check s3.isValid()

    test "Size validation - invalid sizes":
      let s1 = size(0, 10)
      let s2 = size(10, 0)
      let s3 = size(0, 0)
      let s4 = size(-10, 20)
      let s5 = size(10, -20)
      check not s1.isValid()
      check not s2.isValid()
      check not s3.isValid()
      check not s4.isValid()
      check not s5.isValid()

  suite "Rect Creation Tests":
    test "Rect creation with coordinates and dimensions":
      let r = rect(10, 20, 100, 50)
      check r.x == 10
      check r.y == 20
      check r.width == 100
      check r.height == 50

    test "Rect creation from Position and Size":
      let p = pos(5, 15)
      let s = size(80, 60)
      let r = rect(p, s)
      check r.x == 5
      check r.y == 15
      check r.width == 80
      check r.height == 60

    test "Rect direct creation":
      let r = Rect(x: 0, y: 0, width: 10, height: 10)
      check r.x == 0
      check r.y == 0
      check r.width == 10
      check r.height == 10

  suite "Rect Property Tests":
    test "Rect position extraction":
      let r = rect(15, 25, 50, 40)
      let p = r.position()
      check p.x == 15
      check p.y == 25

    test "Rect size extraction":
      let r = rect(10, 20, 80, 60)
      let s = r.size()
      check s.width == 80
      check s.height == 60

    test "Rect area calculation":
      let r = rect(0, 0, 10, 20)
      check r.area() == 200

    test "Rect right edge":
      let r = rect(10, 20, 30, 40)
      check r.right() == 40 # x + width = 10 + 30

    test "Rect bottom edge":
      let r = rect(10, 20, 30, 40)
      check r.bottom() == 60 # y + height = 20 + 40

    test "Rect center calculation":
      let r = rect(10, 20, 20, 10)
      let center = r.center()
      check center.x == 20 # 10 + 20/2
      check center.y == 25 # 20 + 10/2

    test "Rect center with odd dimensions":
      let r = rect(0, 0, 11, 13)
      let center = r.center()
      check center.x == 5 # 0 + 11/2 (integer division)
      check center.y == 6 # 0 + 13/2 (integer division)

  suite "Rect Validation Tests":
    test "Rect validation - valid rects":
      let r1 = rect(0, 0, 10, 10)
      let r2 = rect(-10, -10, 1, 1)
      let r3 = rect(100, 200, 50, 25)
      check r1.isValid()
      check r2.isValid()
      check r3.isValid()

    test "Rect validation - invalid rects":
      let r1 = rect(0, 0, 0, 10)
      let r2 = rect(0, 0, 10, 0)
      let r3 = rect(0, 0, 0, 0)
      let r4 = rect(0, 0, -10, 10)
      let r5 = rect(0, 0, 10, -10)
      check not r1.isValid()
      check not r2.isValid()
      check not r3.isValid()
      check not r4.isValid()
      check not r5.isValid()

    test "Rect isEmpty":
      let r1 = rect(0, 0, 10, 10)
      let r2 = rect(0, 0, 0, 10)
      let r3 = rect(0, 0, 10, 0)
      let r4 = rect(0, 0, 0, 0)
      let r5 = rect(0, 0, -5, 10)
      check not r1.isEmpty()
      check r2.isEmpty()
      check r3.isEmpty()
      check r4.isEmpty()
      check r5.isEmpty()

  suite "Rect Containment Tests":
    test "Rect contains Position - inside":
      let r = rect(10, 20, 30, 40)
      let p1 = pos(15, 25) # Inside
      let p2 = pos(10, 20) # Top-left corner (inclusive)
      let p3 = pos(39, 59) # Bottom-right corner (exclusive boundary)
      check r.contains(p1)
      check r.contains(p2)
      check r.contains(p3)

    test "Rect contains Position - outside":
      let r = rect(10, 20, 30, 40)
      let p1 = pos(5, 25) # Left of rect
      let p2 = pos(45, 25) # Right of rect
      let p3 = pos(15, 15) # Above rect
      let p4 = pos(15, 65) # Below rect
      let p5 = pos(40, 20) # On right boundary (exclusive)
      let p6 = pos(10, 60) # On bottom boundary (exclusive)
      check not r.contains(p1)
      check not r.contains(p2)
      check not r.contains(p3)
      check not r.contains(p4)
      check not r.contains(p5)
      check not r.contains(p6)

    test "Rect contains coordinates":
      let r = rect(0, 0, 10, 10)
      check r.contains(5, 5)
      check r.contains(0, 0)
      check r.contains(9, 9)
      check not r.contains(10, 5)
      check not r.contains(5, 10)
      check not r.contains(-1, 5)
      check not r.contains(5, -1)

  suite "Rect Intersection Tests":
    test "Rect intersects - overlapping":
      let r1 = rect(10, 10, 20, 20) # (10,10) to (30,30)
      let r2 = rect(20, 20, 20, 20) # (20,20) to (40,40)
      let r3 = rect(15, 15, 10, 10) # (15,15) to (25,25) - fully inside r1
      check r1.intersects(r2)
      check r2.intersects(r1)
      check r1.intersects(r3)
      check r3.intersects(r1)

    test "Rect intersects - non-overlapping":
      let r1 = rect(10, 10, 10, 10) # (10,10) to (20,20)
      let r2 = rect(25, 10, 10, 10) # (25,10) to (35,20)
      let r3 = rect(10, 25, 10, 10) # (10,25) to (20,35)
      check not r1.intersects(r2)
      check not r2.intersects(r1)
      check not r1.intersects(r3)
      check not r3.intersects(r1)

    test "Rect intersects - touching edges":
      let r1 = rect(10, 10, 10, 10) # (10,10) to (20,20)
      let r2 = rect(20, 10, 10, 10) # (20,10) to (30,20) - touching right edge
      let r3 = rect(10, 20, 10, 10) # (10,20) to (20,30) - touching bottom edge
      check not r1.intersects(r2) # Touching edges don't intersect
      check not r1.intersects(r3)

    test "Rect intersection calculation":
      let r1 = rect(10, 10, 20, 20) # (10,10) to (30,30)
      let r2 = rect(20, 20, 20, 20) # (20,20) to (40,40)
      let intersection = r1.intersection(r2)

      check intersection.x == 20
      check intersection.y == 20
      check intersection.width == 10
      check intersection.height == 10

    test "Rect intersection - no overlap":
      let r1 = rect(10, 10, 10, 10)
      let r2 = rect(25, 10, 10, 10)
      let intersection = r1.intersection(r2)

      check intersection.x == 0
      check intersection.y == 0
      check intersection.width == 0
      check intersection.height == 0
      check intersection.isEmpty()

    test "Rect intersection - one fully inside another":
      let r1 = rect(10, 10, 30, 30) # Large rect
      let r2 = rect(15, 15, 10, 10) # Small rect inside
      let intersection = r1.intersection(r2)

      check intersection == r2 # Intersection is the smaller rect

  suite "Rect Union Tests":
    test "Rect union - overlapping":
      let r1 = rect(10, 10, 20, 20) # (10,10) to (30,30)
      let r2 = rect(20, 20, 20, 20) # (20,20) to (40,40)
      let union = r1.union(r2)

      check union.x == 10
      check union.y == 10
      check union.width == 30 # From 10 to 40
      check union.height == 30 # From 10 to 40

    test "Rect union - non-overlapping":
      let r1 = rect(10, 10, 10, 10) # (10,10) to (20,20)
      let r2 = rect(30, 30, 10, 10) # (30,30) to (40,40)
      let union = r1.union(r2)

      check union.x == 10
      check union.y == 10
      check union.width == 30 # From 10 to 40
      check union.height == 30 # From 10 to 40

    test "Rect union - one inside another":
      let r1 = rect(10, 10, 30, 30) # Large rect
      let r2 = rect(15, 15, 10, 10) # Small rect inside
      let union = r1.union(r2)

      check union == r1 # Union is the larger rect

  suite "Rect Shrink/Expand Tests":
    test "Rect shrink - uniform margin":
      let r = rect(10, 20, 30, 40)
      let shrunk = r.shrink(5)

      check shrunk.x == 15 # 10 + 5
      check shrunk.y == 25 # 20 + 5
      check shrunk.width == 20 # 30 - 5*2
      check shrunk.height == 30 # 40 - 5*2

    test "Rect shrink - different horizontal/vertical margins":
      let r = rect(10, 20, 30, 40)
      let shrunk = r.shrink(3, 7)

      check shrunk.x == 13 # 10 + 3
      check shrunk.y == 27 # 20 + 7
      check shrunk.width == 24 # 30 - 3*2
      check shrunk.height == 26 # 40 - 7*2

    test "Rect shrink - overshrinking":
      let r = rect(10, 20, 10, 8)
      let shrunk1 = r.shrink(6) # Would make width negative
      let shrunk2 = r.shrink(3, 5) # Would make height negative

      check shrunk1.width == 0 # Clamped to 0
      check shrunk1.height == 0 # Clamped to 0
      check shrunk2.width == 4 # 10 - 3*2
      check shrunk2.height == 0 # Clamped to 0

    test "Rect expand - uniform margin":
      let r = rect(10, 20, 30, 40)
      let expanded = r.expand(5)

      check expanded.x == 5 # 10 - 5
      check expanded.y == 15 # 20 - 5
      check expanded.width == 40 # 30 + 5*2
      check expanded.height == 50 # 40 + 5*2

    test "Rect expand - negative coordinates":
      let r = rect(2, 3, 10, 10)
      let expanded = r.expand(5)

      check expanded.x == -3 # 2 - 5
      check expanded.y == -2 # 3 - 5
      check expanded.width == 20 # 10 + 5*2
      check expanded.height == 20 # 10 + 5*2

  suite "Rect String Representation Tests":
    test "Rect string representation":
      let r = rect(10, 20, 100, 50)
      check $r == "Rect(10, 20, 100, 50)"

    test "Rect string representation with zero coordinates":
      let r = rect(0, 0, 640, 480)
      check $r == "Rect(0, 0, 640, 480)"

    test "Rect string representation with negative coordinates":
      let r = rect(-10, -5, 20, 15)
      check $r == "Rect(-10, -5, 20, 15)"

  suite "Area Alias Tests":
    test "Area is alias for Rect":
      let area: Area = rect(10, 20, 30, 40)
      check area.x == 10
      check area.y == 20
      check area.width == 30
      check area.height == 40

    test "Area supports all Rect operations":
      let area: Area = rect(10, 10, 20, 20)
      check area.area() == 400
      check area.right() == 30
      check area.bottom() == 30
      check area.contains(15, 15)

  suite "Edge Cases and Boundary Tests":
    test "Zero-sized rectangles":
      let r1 = rect(10, 10, 0, 10)
      let r2 = rect(10, 10, 10, 0)
      let r3 = rect(10, 10, 0, 0)

      check r1.isEmpty()
      check r2.isEmpty()
      check r3.isEmpty()
      check not r1.isValid()
      check not r2.isValid()
      check not r3.isValid()

    test "Single-pixel rectangle":
      let r = rect(10, 10, 1, 1)

      check r.isValid()
      check not r.isEmpty()
      check r.area() == 1
      check r.contains(10, 10)
      check not r.contains(11, 10)
      check not r.contains(10, 11)

    test "Large coordinates":
      let r = rect(1000000, 2000000, 500000, 300000)

      check r.isValid()
      check r.right() == 1500000
      check r.bottom() == 2300000
      check r.area() == 150000000000

    test "Position arithmetic edge cases":
      let p1 = pos(0, 0)
      let p2 = pos(-10, -20)
      let p3 = pos(1000000, 2000000)

      let sum = p2 + p3
      let diff = p3 - p2

      check sum.x == 999990
      check sum.y == 1999980
      check diff.x == 1000010
      check diff.y == 2000020

    test "Intersection edge cases":
      # Test rectangles that just touch
      let r1 = rect(0, 0, 10, 10)
      let r2 = rect(10, 0, 10, 10) # Touching right edge
      let r3 = rect(0, 10, 10, 10) # Touching bottom edge

      check not r1.intersects(r2)
      check not r1.intersects(r3)

      let int1 = r1.intersection(r2)
      let int2 = r1.intersection(r3)

      check int1.isEmpty()
      check int2.isEmpty()
