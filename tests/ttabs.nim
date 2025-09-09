## Test suite for tabs widget

import std/[unittest, strformat, strutils]

import ../celina/widgets/[base, tabs, text]
import ../celina/core/[geometry, buffer, colors]

suite "Tabs Widget":
  test "Tab creation":
    let tab = tab("Test Tab", newText("Test Content"))
    check tab.title == "Test Tab"
    check tab.content != nil

  test "Tabs widget initialization":
    let tabs =
      @[
        tab("Tab 1", newText("Content 1")),
        tab("Tab 2", newText("Content 2")),
        tab("Tab 3", newText("Content 3")),
      ]

    let widget = newTabs(tabs, activeIndex = 1)
    check widget.tabs.len == 3
    check widget.activeIndex == 1
    check widget.position == Top
    check widget.showBorder == true

  test "Add and remove tabs":
    var widget = newTabs()
    check widget.tabs.len == 0

    widget.addTab("Tab 1", newText("Content 1"))
    widget.addTab("Tab 2", newText("Content 2"))
    check widget.tabs.len == 2

    widget.removeTab(0)
    check widget.tabs.len == 1
    check widget.tabs[0].title == "Tab 2"

  test "Tab navigation":
    let tabs =
      @[
        tab("Tab 1", newText("Content 1")),
        tab("Tab 2", newText("Content 2")),
        tab("Tab 3", newText("Content 3")),
      ]

    var widget = newTabs(tabs, activeIndex = 0)
    check widget.activeIndex == 0

    widget.nextTab()
    check widget.activeIndex == 1

    widget.nextTab()
    check widget.activeIndex == 2

    widget.nextTab() # Should wrap to 0
    check widget.activeIndex == 0

    widget.prevTab() # Should wrap to 2
    check widget.activeIndex == 2

    widget.setActiveTab(1)
    check widget.activeIndex == 1

  test "Tab widget rendering":
    let tabs = @[tab("Tab 1", newText("Content 1")), tab("Tab 2", newText("Content 2"))]

    let widget = newTabs(tabs, activeIndex = 0)
    var buf = newBuffer(40, 10)

    widget.render(rect(0, 0, 40, 10), buf)

    # Check that something was rendered
    var hasContent = false
    for y in 0 ..< 10:
      for x in 0 ..< 40:
        let cell = buf[x, y]
        if cell.symbol != " " and cell.symbol != "":
          hasContent = true
          break
      if hasContent:
        break

    check hasContent

  test "Tab styles":
    let customStyle = TabStyle(
      activeStyle: style(White, Blue),
      inactiveStyle: style(BrightBlack),
      borderStyle: style(Green),
      dividerChar: "|",
    )

    let widget = newTabs(@[], tabStyle = customStyle)
    check widget.tabStyle.dividerChar == "|"
    # Style is properly set - we can't directly compare ColorValue with Color enum

  test "Calculate tab widths":
    # This tests the internal width calculation logic
    let tabs =
      @[
        tab("Short", newText("")),
        tab("Very Long Tab Title That Should Be Truncated", newText("")),
        tab("Medium Tab", newText("")),
      ]

    let widget = newTabs(tabs)
    var buf = newBuffer(30, 5)

    # Render to trigger width calculations
    widget.render(rect(0, 0, 30, 5), buf)

    # Just check that rendering completes without error
    check true

  test "Tab position":
    let tabs = @[tab("Test", newText("Content"))]

    let topWidget = newTabs(tabs, position = Top)
    check topWidget.position == Top

    let bottomWidget = newTabs(tabs, position = Bottom)
    check bottomWidget.position == Bottom

  test "Border toggle":
    let tabs = @[tab("Test", newText("Content"))]

    let withBorder = newTabs(tabs, showBorder = true)
    check withBorder.showBorder == true

    let withoutBorder = newTabs(tabs, showBorder = false)
    check withoutBorder.showBorder == false

  test "Builder methods":
    let tabs = @[tab("Test", newText("Content"))]
    let widget = newTabs(tabs)

    let styledWidget = widget.withStyle(defaultTabStyle())
    check styledWidget.tabs.len == widget.tabs.len

    let bottomWidget = widget.withPosition(Bottom)
    check bottomWidget.position == Bottom

    let noBorderWidget = widget.withBorder(false)
    check noBorderWidget.showBorder == false

  test "Simple tabs constructor":
    let titles = @["Tab 1", "Tab 2", "Tab 3"]
    let contents: seq[Widget] =
      @[
        Widget(newText("Content 1")),
        Widget(newText("Content 2")),
        Widget(newText("Content 3")),
      ]

    let widget = simpleTabs(titles, contents)
    check widget.tabs.len == 3
    check widget.tabs[0].title == "Tab 1"
    check widget.tabs[1].title == "Tab 2"
    check widget.tabs[2].title == "Tab 3"

  test "Text tabs constructor":
    let items = @[("Tab 1", "This is content 1"), ("Tab 2", "This is content 2")]

    let widget = textTabs(items)
    check widget.tabs.len == 2
    check widget.tabs[0].title == "Tab 1"
    check widget.tabs[1].title == "Tab 2"

  test "Minimum size":
    let tabs = @[tab("Tab 1", newText("Content")), tab("Tab 2", newText("Content"))]

    let widget = newTabs(tabs)
    let minSize = widget.getMinSize()

    check minSize.width >= 10
    check minSize.height >= 3 # Tab bar + borders

  test "Can focus":
    let widget = newTabs(@[])
    check widget.canFocus() == true

  test "Empty tabs widget":
    let widget = newTabs(@[])
    var buf = newBuffer(20, 10)

    # Should not crash when rendering empty tabs
    widget.render(rect(0, 0, 20, 10), buf)
    check widget.tabs.len == 0

  test "Active index bounds":
    let tabs = @[tab("Tab 1", newText("Content 1")), tab("Tab 2", newText("Content 2"))]

    # Test with out of bounds index - should clamp to valid range
    let widget = newTabs(tabs, activeIndex = 10)
    check widget.activeIndex == 1 # Should be clamped to tabs.len - 1

    let widget2 = newTabs(tabs, activeIndex = -1)
    check widget2.activeIndex == 0 # Should be clamped to 0

  test "Remove tab edge cases":
    let tabs =
      @[
        tab("Tab 1", newText("Content 1")),
        tab("Tab 2", newText("Content 2")),
        tab("Tab 3", newText("Content 3")),
      ]

    # Test removing tab before active tab
    var widget = newTabs(tabs, activeIndex = 2)
    widget.removeTab(0) # Remove first tab
    check widget.activeIndex == 1 # Should decrement from 2 to 1
    check widget.tabs.len == 2
    check widget.tabs[0].title == "Tab 2"

    # Test removing active tab
    widget.removeTab(1) # Remove active tab
    check widget.activeIndex == 0 # Should adjust to valid index
    check widget.tabs.len == 1

    # Test removing last tab
    widget.removeTab(0)
    check widget.activeIndex == 0
    check widget.tabs.len == 0

  test "Extreme rendering conditions":
    let tabs = @[tab("VeryLongTabTitleThatWouldNormallyBeVeryLong", newText(""))]
    let widget = newTabs(tabs)

    # Test with very small buffer
    var smallBuf = newBuffer(5, 3)
    widget.render(rect(0, 0, 5, 3), smallBuf)
    check true # Should not crash

    # Test with single character width
    var tinyBuf = newBuffer(1, 1)
    widget.render(rect(0, 0, 1, 1), tinyBuf)
    check true # Should not crash

    # Test with zero width
    var zeroBuf = newBuffer(10, 10)
    widget.render(rect(0, 0, 0, 5), zeroBuf)
    check true # Should not crash

  test "Tab width calculation edge cases":
    # This tests extreme conditions in width calculations
    let manyTabs =
      @[
        tab("A", newText("")),
        tab("B", newText("")),
        tab("C", newText("")),
        tab("D", newText("")),
        tab("E", newText("")),
      ]

    let widget = newTabs(manyTabs)
    var buf = newBuffer(8, 5) # Very constrained width

    widget.render(rect(0, 0, 8, 5), buf)
    check true # Should handle gracefully without crashing

  test "Unicode and wide character handling":
    # Test with Japanese, Chinese, and emojis
    let unicodeTabs =
      @[
        tab("日本語", newText("Japanese content")),
        tab("中文", newText("Chinese content")),
        tab("🚀✨", newText("Emoji content")),
        tab("Mixed英語", newText("Mixed content")),
      ]

    let widget = newTabs(unicodeTabs)
    var buf = newBuffer(40, 10)

    # Should render without crashing
    widget.render(rect(0, 0, 40, 10), buf)

    # Check that wide characters are handled properly
    var foundWideChar = false
    for y in 0 ..< buf.area.height:
      for x in 0 ..< buf.area.width:
        let cell = buf[x, y]
        if cell.symbol.len > 1:
          foundWideChar = true
          break
    check foundWideChar # Should find multi-byte characters

  test "Content area calculation and rendering":
    let testContent = newText("This is test content")
    let tabs = @[tab("Test", testContent)]

    # Test with border
    let widgetWithBorder = newTabs(tabs, showBorder = true)
    var buf = newBuffer(20, 8)
    widgetWithBorder.render(rect(0, 0, 20, 8), buf)

    # Check that content is rendered in correct area
    var contentFound = false
    # Content should be inside borders (x: 1..18, y: 2..6)
    for y in 2 ..< 7:
      for x in 1 ..< 19:
        let cell = buf[x, y]
        if cell.symbol != " " and cell.symbol != "":
          contentFound = true
          break
    check contentFound

    # Test without border
    let widgetNoBorder = newTabs(tabs, showBorder = false)
    buf = newBuffer(20, 8)
    widgetNoBorder.render(rect(0, 0, 20, 8), buf)
    check true # Should render successfully

  test "Tab bar visual verification":
    let tabs =
      @[
        tab("Active", newText("Active content")),
        tab("Inactive", newText("Inactive content")),
      ]

    let widget = newTabs(tabs, activeIndex = 0)
    var buf = newBuffer(30, 5)
    widget.render(rect(0, 0, 30, 5), buf)

    # Check tab bar is on first row
    var tabBarContent = ""
    for x in 0 ..< buf.area.width:
      let cell = buf[x, 0]
      tabBarContent.add(cell.symbol)

    # Should contain both tab titles
    check tabBarContent.contains("Active")
    check tabBarContent.contains("Inactive")

    # Test bottom position
    let bottomWidget = newTabs(tabs, position = Bottom)
    buf = newBuffer(30, 5)
    bottomWidget.render(rect(0, 0, 30, 5), buf)

    # Check tab bar is on last row
    tabBarContent = ""
    for x in 0 ..< buf.area.width:
      let cell = buf[x, buf.area.height - 1]
      tabBarContent.add(cell.symbol)

    check tabBarContent.contains("Active") or tabBarContent.contains("Inactive")

  test "Invalid operations handling":
    var widget = newTabs(@[tab("Test", newText("Content"))])

    # Test removing invalid indices
    widget.removeTab(-1) # Should not crash
    check widget.tabs.len == 1

    widget.removeTab(10) # Should not crash
    check widget.tabs.len == 1

    # Test setting invalid active tab
    widget.setActiveTab(-1) # Should not change active index
    check widget.activeIndex == 0

    widget.setActiveTab(10) # Should not change active index
    check widget.activeIndex == 0

    # Test navigation on empty tabs
    var emptyWidget = newTabs(@[])
    emptyWidget.nextTab() # Should not crash
    emptyWidget.prevTab() # Should not crash
    check emptyWidget.activeIndex == 0

  test "Nil content handling":
    # Test tab with nil content
    let tab1 = Tab(title: "Valid", content: newText("Content"))
    let tab2 = Tab(title: "Nil Content", content: nil)

    let widget = newTabs(@[tab1, tab2])
    var buf = newBuffer(20, 8)

    # Should render without crashing even with nil content
    widget.render(rect(0, 0, 20, 8), buf)
    check widget.tabs.len == 2

    # Test switching to tab with nil content
    widget.setActiveTab(1)
    widget.render(rect(0, 0, 20, 8), buf)
    check widget.activeIndex == 1

  test "Stress test with many tabs":
    # Create many tabs to test performance
    var manyTabs: seq[Tab] = @[]
    for i in 1 .. 20:
      manyTabs.add(tab(&"Tab{i}", newText(&"Content {i}")))

    let widget = newTabs(manyTabs)
    var buf = newBuffer(100, 20)

    # Should handle many tabs without issues
    widget.render(rect(0, 0, 100, 20), buf)
    check widget.tabs.len == 20

    # Test navigation through all tabs
    for i in 0 ..< 20:
      widget.setActiveTab(i)
      check widget.activeIndex == i

  test "Border rendering accuracy":
    let tabs = @[tab("Test", newText("Content"))]
    let widget = newTabs(tabs, showBorder = true)
    var buf = newBuffer(20, 8)

    widget.render(rect(0, 0, 20, 8), buf)

    # Check corners are rendered
    check buf[0, 1].symbol == "┌" # Top-left
    check buf[19, 1].symbol == "┐" # Top-right
    check buf[0, 7].symbol == "└" # Bottom-left
    check buf[19, 7].symbol == "┘" # Bottom-right

    # Check borders are rendered
    check buf[0, 2].symbol == "│" # Left border
    check buf[19, 2].symbol == "│" # Right border
    check buf[1, 1].symbol == "─" # Top border
    check buf[1, 7].symbol == "─" # Bottom border
