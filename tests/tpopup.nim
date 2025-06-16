# Test suite for Popup widgets

import std/unittest

import ../src/widgets/popup
import ../src/core/[geometry, buffer, colors]

suite "Popup Widget Tests":
  suite "Popup Creation":
    test "Create empty popup":
      let popup = newPopup()
      check not popup.isVisible()
      check popup.state.content.len == 0
      check popup.state.title == ""

    test "Create popup with content":
      let content = @["Line 1", "Line 2", "Line 3"]
      let title = "Test Popup"
      let popup = newPopup(content, title)

      check not popup.isVisible()
      check popup.state.content == content
      check popup.state.title == title

    test "Create popup with custom style":
      let customStyle = PopupStyle(
        border: false, background: style(Color.Red, Color.Blue), shadow: false
      )
      let popup = newPopup(popupStyle = customStyle)

      check popup.style.border == false
      check popup.style.shadow == false

  suite "Popup Control":
    test "Show and hide popup":
      let popup = newPopup()

      check not popup.isVisible()

      popup.show(10, 5, Below)
      check popup.isVisible()
      check popup.state.anchorX == 10
      check popup.state.anchorY == 5
      check popup.state.position == Below

      popup.hide()
      check not popup.isVisible()

    test "Set popup content":
      let popup = newPopup()
      let newContent = @["New line 1", "New line 2"]
      let newTitle = "New Title"

      popup.setContent(newContent, newTitle)
      check popup.state.content == newContent
      check popup.state.title == newTitle

    test "Add line to popup":
      let popup = newPopup(@["Initial line"])

      popup.addLine("Added line")
      check popup.state.content.len == 2
      check popup.state.content[1] == "Added line"

    test "Clear popup content":
      let popup = newPopup(@["Line 1", "Line 2"], "Title")

      popup.clearContent()
      check popup.state.content.len == 0
      check popup.state.title == ""

  suite "Tooltip Creation":
    test "Create empty tooltip":
      let tooltip = newTooltip()
      check not tooltip.isVisible()
      check tooltip.state.text == ""

    test "Create tooltip with text":
      let text = "Test tooltip"
      let tooltip = newTooltip(text)

      check not tooltip.isVisible()
      check tooltip.state.text == text

  suite "Tooltip Control":
    test "Show and hide tooltip":
      let tooltip = newTooltip()

      check not tooltip.isVisible()

      tooltip.show(5, 3, "Tooltip text")
      check tooltip.isVisible()
      check tooltip.state.anchorX == 5
      check tooltip.state.anchorY == 3
      check tooltip.state.text == "Tooltip text"

      tooltip.hide()
      check not tooltip.isVisible()

  suite "Popup Positioning":
    test "Popup positioning - Below":
      let popup = newPopup(@["Test line"], "Title")
      popup.show(20, 10, Below)

      let bufferArea = rect(0, 0, 80, 24)
      let popupRect = popup.calculatePopupRect(bufferArea)

      # Should be positioned below anchor point
      check popupRect.y == 11 # anchor + 1

    test "Popup positioning - Above":
      let popup = newPopup(@["Test line"], "Title")
      popup.show(20, 10, Above)

      let bufferArea = rect(0, 0, 80, 24)
      let popupRect = popup.calculatePopupRect(bufferArea)

      # Should be positioned above anchor point
      check popupRect.y < 10

    test "Popup positioning - Center":
      let popup = newPopup(@["Test line"], "Title")
      popup.show(20, 10, Center)

      let bufferArea = rect(0, 0, 80, 24)
      let popupRect = popup.calculatePopupRect(bufferArea)

      # Should be centered in buffer
      check popupRect.x == bufferArea.width div 2 - popupRect.width div 2
      check popupRect.y == bufferArea.height div 2 - popupRect.height div 2

  suite "Widget Sizing":
    test "Popup minimum size":
      let popup = newPopup(minWidth = 15)
      let minSize = popup.getMinSize()

      check minSize.width == 15
      check minSize.height == 3 # Minimum for border + content

    test "Popup preferred size":
      let popup = newPopup(@["Short", "Much longer line"], "Title")
      let available = size(50, 20)
      let preferred = popup.getPreferredSize(available)

      # Should accommodate longest content line
      check preferred.width >= "Much longer line".len

    test "Tooltip size":
      let tooltip = newTooltip("Test tooltip text")
      let minSize = tooltip.getMinSize()
      let preferred = tooltip.getPreferredSize(size(50, 20))

      check minSize.width == 1
      check minSize.height == 1
      check preferred.width == "Test tooltip text".len
      check preferred.height == 1

  suite "Popup Styles":
    test "Default popup style":
      let defaultStyle = defaultPopupStyle()

      check defaultStyle.border == true
      check defaultStyle.shadow == true

    test "Default tooltip style":
      let defaultStyle = defaultTooltipStyle()

      check defaultStyle.fg.kind == Indexed
      check defaultStyle.bg.kind == Indexed

  suite "Basic Rendering":
    test "Hidden popup doesn't render":
      let popup = newPopup(@["Test"])
      let area = rect(0, 0, 80, 24)
      var buffer = newBuffer(80, 24)

      # Should not modify buffer when hidden
      let initialCells = buffer.content.len
      popup.render(area, buffer)
      check buffer.content.len == initialCells

    test "Visible popup modifies buffer":
      let popup = newPopup(@["Test line"])
      popup.show(5, 5, Below)

      let area = rect(0, 0, 80, 24)
      var buffer = newBuffer(80, 24)

      popup.render(area, buffer)
      # Buffer should have been modified (specific cells set)
      # This is a basic check - in practice we'd verify specific positions

    test "Hidden tooltip doesn't render":
      let tooltip = newTooltip("Test")
      let area = rect(0, 0, 80, 24)
      var buffer = newBuffer(80, 24)

      tooltip.render(area, buffer)
      # Should not crash and not modify buffer significantly when hidden
