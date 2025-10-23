import std/unittest

import ../celina/widgets/text
import ../celina/core/[buffer, geometry, colors]

# Test suite for Text widget module
suite "Text Widget Tests":
  suite "Text Widget Creation":
    test "Create simple text widget":
      let widget = newText("Hello, World!")
      check widget != nil
      check widget.content == "Hello, World!"
      check widget.alignment == Left
      check widget.wrap == NoWrap

    test "Create text widget with style":
      let style = style(Red, Blue)
      let widget = newText("Styled", style)
      check widget.style == style

    test "Create text widget with alignment":
      let widget = newText("Centered", alignment = Center)
      check widget.alignment == Center

    test "Create text widget with wrap mode":
      let widget = newText("Wrapped", wrap = WordWrap)
      check widget.wrap == WordWrap

    test "Convenience constructor":
      let widget = text("Convenient")
      check widget != nil
      check widget.content == "Convenient"

  suite "Text Alignment":
    test "Left aligned text rendering":
      let widget = newText("Left", alignment = Left)
      var buf = newBuffer(20, 3)
      let area = rect(0, 0, 20, 3)

      widget.render(area, buf)

      let firstCell = buf[0, 0]
      check firstCell.symbol.len > 0

    test "Center aligned text rendering":
      let widget = newText("Center", alignment = Center)
      var buf = newBuffer(20, 3)
      let area = rect(0, 0, 20, 3)

      widget.render(area, buf)

      # "Center" has 6 characters, in a 20-char width
      # Check that some content is rendered
      var hasContent = false
      for x in 0 ..< 20:
        if buf[x, 0].symbol != " ":
          hasContent = true
          break
      check hasContent

    test "Right aligned text rendering":
      let widget = newText("Right", alignment = Right)
      var buf = newBuffer(20, 3)
      let area = rect(0, 0, 20, 3)

      widget.render(area, buf)

      # Check that content is rendered at the right side
      var hasContent = false
      for x in 10 ..< 20:
        if buf[x, 0].symbol != " ":
          hasContent = true
          break
      check hasContent

  suite "Text Wrapping":
    test "NoWrap mode truncates long text":
      let widget =
        newText("This is a very long line that should be truncated", wrap = NoWrap)
      var buf = newBuffer(10, 3)
      let area = rect(0, 0, 10, 3)

      widget.render(area, buf)

      # Check that content is rendered within bounds
      let firstCell = buf[0, 0]
      check firstCell.symbol.len > 0

    test "WordWrap mode wraps at word boundaries":
      let widget = newText("Hello World Test", wrap = WordWrap)
      var buf = newBuffer(8, 3)
      let area = rect(0, 0, 8, 3)

      widget.render(area, buf)

      # Check that content is rendered on multiple lines
      let line1HasContent = buf[0, 0].symbol != " "
      let line2HasContent = buf[0, 1].symbol != " "

      check line1HasContent
      check line2HasContent

    test "CharWrap mode wraps at any character":
      let widget = newText("ABCDEFGHIJKLMNOP", wrap = CharWrap)
      var buf = newBuffer(5, 4)
      let area = rect(0, 0, 5, 4)

      widget.render(area, buf)

      # Check that content is rendered and wrapped
      let line1HasContent = buf[0, 0].symbol != " "
      let line2HasContent = buf[0, 1].symbol != " "
      let line3HasContent = buf[0, 2].symbol != " "

      check line1HasContent
      check line2HasContent
      check line3HasContent

  suite "Multiline Text":
    test "Render multiline text":
      let widget = newText("Line 1\nLine 2\nLine 3")
      var buf = newBuffer(10, 5)
      let area = rect(0, 0, 10, 5)

      widget.render(area, buf)

      # Check that content is rendered on multiple lines
      let line1HasContent = buf[0, 0].symbol != " "
      let line2HasContent = buf[0, 1].symbol != " "
      let line3HasContent = buf[0, 2].symbol != " "

      check line1HasContent
      check line2HasContent
      check line3HasContent

    test "Multiline text respects height limit":
      let widget = newText("Line 1\nLine 2\nLine 3\nLine 4\nLine 5")
      var buf = newBuffer(10, 3)
      let area = rect(0, 0, 10, 3)

      widget.render(area, buf)

      # First 3 lines should have content
      let line1HasContent = buf[0, 0].symbol != " "
      let line2HasContent = buf[0, 1].symbol != " "
      let line3HasContent = buf[0, 2].symbol != " "

      check line1HasContent
      check line2HasContent
      check line3HasContent

  suite "Widget Sizing":
    test "getMinSize for single line":
      let widget = newText("Hello")
      let minSize = widget.getMinSize()

      check minSize.width == 5
      check minSize.height == 1

    test "getMinSize for multiline":
      let widget = newText("Short\nLonger line\nMedium")
      let minSize = widget.getMinSize()

      check minSize.width == 11 # "Longer line" is longest
      check minSize.height == 3

    test "getMinSize with word wrap":
      let widget = newText("Hello World", wrap = WordWrap)
      let minSize = widget.getMinSize()

      # Minimum width should be longest word
      check minSize.width >= 5 # "Hello" or "World"

    test "getPreferredSize with NoWrap":
      let widget = newText("Hello", wrap = NoWrap)
      let available = size(10, 5)
      let preferred = widget.getPreferredSize(available)

      check preferred.width <= available.width
      check preferred.height <= available.height

    test "getPreferredSize with wrapping":
      let widget = newText("Hello World Test", wrap = WordWrap)
      let available = size(10, 5)
      let preferred = widget.getPreferredSize(available)

      check preferred.width == available.width

  suite "Widget Modifiers":
    test "withStyle creates new widget":
      let original = newText("Test")
      let newStyle = style(Red)
      let modified = original.withStyle(newStyle)

      check modified.content == original.content
      check modified.style == newStyle
      check original.style != newStyle

    test "withAlignment creates new widget":
      let original = newText("Test", alignment = Left)
      let modified = original.withAlignment(Center)

      check modified.content == original.content
      check modified.alignment == Center
      check original.alignment == Left

    test "withWrap creates new widget":
      let original = newText("Test", wrap = NoWrap)
      let modified = original.withWrap(WordWrap)

      check modified.content == original.content
      check modified.wrap == WordWrap
      check original.wrap == NoWrap

  suite "Convenience Constructors":
    test "boldText creates bold styled text":
      let widget = boldText("Bold")
      check widget.content == "Bold"
      check Bold in widget.style.modifiers

    test "colorText creates colored text":
      let widget = colorText("Colored", Red)
      check widget.content == "Colored"
      check widget.style.fg.kind == Indexed
      check widget.style.fg.indexed == Red

    test "styledText with full styling":
      let widget = styledText("Styled", Red, Blue, {Bold, Underline}, Center)
      check widget.content == "Styled"
      check widget.style.fg.kind == Indexed
      check widget.style.fg.indexed == Red
      check widget.style.bg.kind == Indexed
      check widget.style.bg.indexed == Blue
      check Bold in widget.style.modifiers
      check Underline in widget.style.modifiers
      check widget.alignment == Center

  suite "Edge Cases":
    test "Empty text widget":
      let widget = newText("")
      var buf = newBuffer(10, 3)
      let area = rect(0, 0, 10, 3)

      widget.render(area, buf)
      # Should not crash

      let minSize = widget.getMinSize()
      check minSize.width == 0
      check minSize.height == 0

    test "Empty area rendering":
      let widget = newText("Test")
      var buf = newBuffer(10, 3)
      let emptyArea = rect(0, 0, 0, 0)

      widget.render(emptyArea, buf)
      # Should not crash

    test "Text wider than buffer":
      let widget = newText("This is a very long text that exceeds buffer width")
      var buf = newBuffer(10, 3)
      let area = rect(0, 0, 10, 3)

      widget.render(area, buf)
      # Should truncate or wrap based on wrap mode

    test "Unicode text handling":
      let widget = newText("こんにちは世界")
      var buf = newBuffer(20, 3)
      let area = rect(0, 0, 20, 3)

      widget.render(area, buf)
      # Should handle unicode correctly

    test "Text with only newlines":
      let widget = newText("\n\n\n")
      let minSize = widget.getMinSize()
      check minSize.height == 4 # 4 lines (empty lines + newlines)
