## Unit tests for List widget

import std/[unittest, sequtils, options]

import ../celina
import ../celina/widgets/list {.all.}

suite "List Widget Tests":
  test "List creation and initialization":
    # Test basic list creation
    let items = @["Item 1", "Item 2", "Item 3"]
    let listWidget = list(items, Single)

    check:
      listWidget.items.len == 3
      listWidget.selectionMode == Single
      listWidget.highlightedIndex == 0
      listWidget.selectedIndices.len == 0
      listWidget.scrollOffset == 0
      listWidget.state == Normal

  test "List item creation":
    # Test ListItem creation
    let item1 = listItem("Simple item")
    let item2 = listItem("Styled item", style(Red))
    let item3 = newListItem("Unselectable", none(Style), false)

    check:
      item1.text == "Simple item"
      item1.style.isNone
      item1.selectable == true

      item2.text == "Styled item"
      item2.style.isSome
      item2.selectable == true

      item3.text == "Unselectable"
      item3.selectable == false

  test "Empty list handling":
    # Test empty list behavior
    let emptyList = newList()

    check:
      emptyList.items.len == 0
      emptyList.highlightedIndex == -1
      emptyList.selectedIndices.len == 0

  test "Item management":
    # Test adding and removing items
    var listWidget = newList()

    # Add items
    listWidget.addItem("First")
    listWidget.addItem(listItem("Second"))
    listWidget.addItem(newListItem("Third", none(Style), false))

    check:
      listWidget.items.len == 3
      listWidget.items[0].text == "First"
      listWidget.items[1].text == "Second"
      listWidget.items[2].text == "Third"
      listWidget.highlightedIndex == 0 # First selectable item

    # Remove item
    listWidget.removeItem(1)
    check:
      listWidget.items.len == 2
      listWidget.items[0].text == "First"
      listWidget.items[1].text == "Third"

    # Clear all items
    listWidget.clearItems()
    check:
      listWidget.items.len == 0
      listWidget.highlightedIndex == -1
      listWidget.selectedIndices.len == 0

    # Set items in bulk
    let newItems = @["A", "B", "C"]
    listWidget.setItems(newItems)
    check:
      listWidget.items.len == 3
      listWidget.highlightedIndex == 0

  test "removeItem resets highlight to -1 when emptied":
    var listWidget = newList(@[listItem("Only")])
    check listWidget.highlightedIndex == 0

    listWidget.removeItem(0)
    check:
      listWidget.items.len == 0
      listWidget.highlightedIndex == -1

  test "removeItem keeps highlight on the same item when removing before it":
    var listWidget = newList(@["A", "B", "C", "D"].mapIt(listItem(it)))
    listWidget.highlightedIndex = 2 # "C"

    # Removing an item before the highlight should keep the highlight on "C"
    listWidget.removeItem(0)
    check:
      listWidget.items.len == 3
      listWidget.highlightedIndex == 1
      listWidget.items[listWidget.highlightedIndex].text == "C"

    # Removing the highlighted item clamps within range
    listWidget.removeItem(2) # remove "D"
    check listWidget.highlightedIndex == 1 # still "C"

    listWidget.removeItem(1) # remove highlighted "C"
    check:
      listWidget.items.len == 1
      listWidget.highlightedIndex == 0

  test "Single selection mode":
    # Test single selection behavior
    var selectedIdx = -1
    var listWidget = selectList(
      @["Option 1", "Option 2", "Option 3"],
      onSelect = proc(index: int) =
        selectedIdx = index,
    )

    # Select first item
    listWidget.selectItem(0)
    check:
      listWidget.selectedIndices == @[0]
      listWidget.isSelected(0) == true
      listWidget.isSelected(1) == false
      selectedIdx == 0

    # Select another item (should replace selection)
    listWidget.selectItem(2)
    check:
      listWidget.selectedIndices == @[2]
      listWidget.isSelected(0) == false
      listWidget.isSelected(2) == true
      selectedIdx == 2

    # Clear selection
    listWidget.clearSelection()
    check:
      listWidget.selectedIndices.len == 0
      listWidget.isSelected(2) == false

  test "Multiple selection mode":
    # Test multiple selection behavior
    var selectedIndices: seq[int] = @[]
    var listWidget = checkList(
      @["Task 1", "Task 2", "Task 3"],
      onMultiSelect = proc(indices: seq[int]) =
        selectedIndices = indices,
    )

    # Select multiple items
    listWidget.selectItem(0)
    listWidget.selectItem(2)
    check:
      listWidget.selectedIndices == @[0, 2]
      listWidget.isSelected(0) == true
      listWidget.isSelected(1) == false
      listWidget.isSelected(2) == true
      selectedIndices == @[0, 2]

    # Toggle selection
    listWidget.toggleSelection(1) # Add
    check:
      listWidget.selectedIndices == @[0, 2, 1]
      listWidget.isSelected(1) == true

    listWidget.toggleSelection(0) # Remove
    check:
      listWidget.selectedIndices == @[2, 1]
      listWidget.isSelected(0) == false

    # Deselect specific item
    listWidget.deselectItem(2)
    check:
      listWidget.selectedIndices == @[1]
      listWidget.isSelected(2) == false

  test "No selection mode":
    # Test list with no selection
    let displayList = bulletList(@["Info 1", "Info 2", "Info 3"])

    check:
      displayList.selectionMode == None
      displayList.bulletPrefix == "• "

    # Attempt to select (should do nothing)
    displayList.selectItem(0)
    check:
      displayList.selectedIndices.len == 0

  test "Navigation - highlighting":
    # Test navigation through items
    var highlightIdx = -1
    var listWidget = newList(
      @[
        listItem("Item 1"),
        newListItem("Unselectable", none(Style), false),
        listItem("Item 3"),
        listItem("Item 4"),
      ].toSeq,
      Single,
      callbacks = ListCallbacks(
        onHighlight: proc(index: int) =
          highlightIdx = index
      ),
    )

    check listWidget.highlightedIndex == 0

    # Navigate forward (should skip unselectable)
    listWidget.highlightNext()
    check:
      listWidget.highlightedIndex == 2 # Skipped index 1
      highlightIdx == 2

    # Navigate backward
    listWidget.highlightPrevious()
    check:
      listWidget.highlightedIndex == 0 # Skipped index 1
      highlightIdx == 0

    # Navigate to last
    listWidget.highlightLast()
    check:
      listWidget.highlightedIndex == 3
      highlightIdx == 3

    # Navigate to first
    listWidget.highlightFirst()
    check:
      listWidget.highlightedIndex == 0
      highlightIdx == 0

  test "Scrolling behavior":
    # Test scrolling with long list
    let items = (1 .. 100).mapIt($it)
    var listWidget = list(items)
    listWidget.visibleCount = 10 # Simulate visible area

    check:
      listWidget.scrollOffset == 0

    # Scroll down
    listWidget.scrollDown(5)
    check:
      listWidget.scrollOffset == 5

    # Scroll up
    listWidget.scrollUp(2)
    check:
      listWidget.scrollOffset == 3

    # Page down
    listWidget.pageDown()
    check:
      listWidget.scrollOffset == 13 # 3 + 10

    # Page up
    listWidget.pageUp()
    check:
      listWidget.scrollOffset == 3 # 13 - 10

    # Scroll to bottom (with highlightLast)
    listWidget.highlightLast()
    check:
      listWidget.highlightedIndex == 99
      listWidget.scrollOffset == 90 # 100 - 10

  test "Keyboard event handling":
    # Test keyboard input
    var listWidget = selectList(@["A", "B", "C"])
    listWidget.setFocus(true)

    # Arrow down
    let downEvent = KeyEvent(code: ArrowDown, char: "", modifiers: {})
    check listWidget.handleKeyEvent(downEvent) == erConsume
    check listWidget.highlightedIndex == 1

    # Arrow up
    let upEvent = KeyEvent(code: ArrowUp, char: "", modifiers: {})
    check listWidget.handleKeyEvent(upEvent) == erConsume
    check listWidget.highlightedIndex == 0

    # Vim keys
    let jEvent = KeyEvent(code: Char, char: "j", modifiers: {})
    check listWidget.handleKeyEvent(jEvent) == erConsume
    check listWidget.highlightedIndex == 1

    let kEvent = KeyEvent(code: Char, char: "k", modifiers: {})
    check listWidget.handleKeyEvent(kEvent) == erConsume
    check listWidget.highlightedIndex == 0

    # Enter to select
    let enterEvent = KeyEvent(code: Enter, char: "", modifiers: {})
    check listWidget.handleKeyEvent(enterEvent) == erConsume
    check listWidget.selectedIndices == @[0]

    # Home/End
    let endEvent = KeyEvent(code: End, char: "", modifiers: {})
    check listWidget.handleKeyEvent(endEvent) == erConsume
    check listWidget.highlightedIndex == 2

    let homeEvent = KeyEvent(code: Home, char: "", modifiers: {})
    check listWidget.handleKeyEvent(homeEvent) == erConsume
    check listWidget.highlightedIndex == 0

    # Disabled list shouldn't respond
    listWidget.setState(Disabled)
    check listWidget.handleKeyEvent(downEvent) == erContinue

  test "Mouse event handling":
    # Test mouse input
    var listWidget = selectList(
      @[
        "Click 1", "Click 2", "Click 3", "Item 4", "Item 5", "Item 6", "Item 7",
        "Item 8",
      ]
    )
    listWidget.setFocus(true)
    let area = rect(10, 5, 20, 3) # Small area to enable scrolling

    # Click on first item
    let clickEvent = MouseEvent(kind: Press, button: Left, x: 15, y: 5, modifiers: {})
    check listWidget.handleMouseEvent(clickEvent, area) == erConsume
    check listWidget.highlightedIndex == 0

    # Release to select
    let releaseEvent =
      MouseEvent(kind: Release, button: Left, x: 15, y: 5, modifiers: {})
    check listWidget.handleMouseEvent(releaseEvent, area) == erConsume
    check listWidget.selectedIndices == @[0]

    # Click outside bounds
    let outsideEvent = MouseEvent(
      kind: Press,
      button: Left,
      x: 5, # Outside area
      y: 5,
      modifiers: {},
    )
    check listWidget.handleMouseEvent(outsideEvent, area) == erContinue

    # Wheel scrolling
    # Reset scroll offset for wheel test
    listWidget.scrollOffset = 5
    let wheelUpEvent =
      MouseEvent(kind: Press, button: WheelUp, x: 15, y: 7, modifiers: {})
    check listWidget.handleMouseEvent(wheelUpEvent, area) == erConsume
    check listWidget.scrollOffset == 4

    # Reset again for down test
    listWidget.scrollOffset = 4
    let wheelDownEvent =
      MouseEvent(kind: Press, button: WheelDown, x: 15, y: 7, modifiers: {})
    check listWidget.handleMouseEvent(wheelDownEvent, area) == erConsume
    check listWidget.scrollOffset == 5

  test "Multi-select with Ctrl+Click":
    # Test multiple selection with Ctrl modifier
    var listWidget = checkList(@["A", "B", "C"])
    listWidget.setFocus(true)
    let area = rect(0, 0, 10, 5)

    # First click
    let click1 = MouseEvent(kind: Press, button: Left, x: 5, y: 0, modifiers: {})
    let release1 = MouseEvent(kind: Release, button: Left, x: 5, y: 0, modifiers: {})
    discard listWidget.handleMouseEvent(click1, area)
    discard listWidget.handleMouseEvent(release1, area)
    check listWidget.selectedIndices == @[0]

    # Ctrl+Click to add to selection
    let click2 = MouseEvent(kind: Press, button: Left, x: 5, y: 2, modifiers: {})
    let release2 =
      MouseEvent(kind: Release, button: Left, x: 5, y: 2, modifiers: {Ctrl})
    discard listWidget.handleMouseEvent(click2, area)
    discard listWidget.handleMouseEvent(release2, area)
    check listWidget.selectedIndices == @[0, 2]

  test "Rendering and styling":
    # Test rendering output
    var buffer = newBuffer(30, 10)
    let area = rect(0, 0, 30, 5)

    # Create styled list
    var listWidget = newList(
      @[
        listItem("Normal"), listItem("Custom", style(Red, Yellow)), listItem("Selected")
      ],
      Single,
      style = ListStyle(
        normal: style(White),
        selected: style(Black, White),
        highlighted: style(Yellow, BrightBlack),
        disabled: style(BrightBlack, Reset),
      ),
    )

    # Select and highlight different items
    listWidget.selectedIndices = @[2]
    listWidget.highlightedIndex = 1
    listWidget.setFocus(true)

    # Render the list
    listWidget.render(area, buffer)

    # Check that items were rendered
    check buffer[0, 0].symbol != "" # First item rendered
    check buffer[0, 1].symbol != "" # Second item rendered
    check buffer[0, 2].symbol != "" # Third item rendered

    # Check styles
    let item0Style = listWidget.getItemStyle(0)
    let item1Style = listWidget.getItemStyle(1) # Custom style
    let item2Style = listWidget.getItemStyle(2) # Selected

    check:
      item0Style == style(White) # Normal style
      item1Style == style(Red, Yellow) # Custom style takes precedence
      item2Style == style(Black, White) # Selected style

  test "Scrollbar rendering":
    # Test scrollbar display
    var buffer = newBuffer(30, 10)
    let area = rect(0, 0, 30, 5)

    # Create list with more items than visible
    let items = (1 .. 20).mapIt($it)
    var listWidget = newList(items.mapIt(listItem(it)), showScrollbar = true)
    listWidget.visibleCount = 5
    listWidget.scrollOffset = 5

    # Render with scrollbar
    listWidget.render(area, buffer)

    # Check scrollbar rendered on right edge
    check buffer[29, 0].symbol != "" # Scrollbar position

  test "List widget builders":
    # Test convenience constructors
    let simpleList = simpleList(@["A", "B", "C"])
    check:
      simpleList.selectionMode == None
      simpleList.items.len == 3

    let selectList = selectList(@["X", "Y", "Z"])
    check:
      selectList.selectionMode == Single
      selectList.items.len == 3

    let checkList = checkList(@["Task 1", "Task 2"])
    check:
      checkList.selectionMode == Multiple
      checkList.bulletPrefix == "[ ] "
      checkList.items.len == 2

    let bulletList = bulletList(@["Point 1", "Point 2"], "→ ")
    check:
      bulletList.selectionMode == None
      bulletList.bulletPrefix == "→ "
      bulletList.items.len == 2

  test "Widget modifiers":
    # Test widget modification methods
    let original = list(@["A", "B"], Single)

    # Modify selection mode
    let multiSelect = original.withSelectionMode(Multiple)
    check:
      multiSelect.selectionMode == Multiple
      original.selectionMode == Single # Original unchanged

    # Modify styles
    let styled = original.withStyles(normal = style(Green), selected = style(Blue))
    check:
      styled.normalStyle == style(Green)
      styled.selectedStyle == style(Blue)

    # Modify bullet prefix
    let bulleted = original.withBulletPrefix("* ")
    check:
      bulleted.bulletPrefix == "* "
      original.bulletPrefix == ""

    # Modify scrollbar
    let noScrollbar = original.withScrollbar(false)
    check:
      noScrollbar.showScrollbar == false
      original.showScrollbar == true

  test "State management":
    # Test widget state changes
    var listWidget = list(@["A", "B", "C"])

    # Initial state
    check:
      listWidget.state == Normal
      listWidget.isEnabled() == true

    # Disable
    listWidget.setEnabled(false)
    check:
      listWidget.state == Disabled
      listWidget.isEnabled() == false

    # Re-enable
    listWidget.setEnabled(true)
    check:
      listWidget.state == Normal
      listWidget.isEnabled() == true

  test "Size calculations":
    # Test minimum and preferred size
    let listWidget = newList(
      @[
        listItem("Short"),
        listItem("A very long item that needs more space"),
        listItem("Medium item"),
      ],
      bulletPrefix = "• ",
    )

    # Minimum size
    let minSize = listWidget.getMinSize()
    check:
      minSize.width >= 12 # Bullet + minimum content
      minSize.height == 1

    # Preferred size
    let available = size(50, 10)
    let preferred = listWidget.getPreferredSize(available)
    check:
      preferred.height == 3 # All 3 items
      preferred.width > 0

    # Empty list must not crash on getPreferredSize (max() over empty seq)
    let emptyList = newList()
    let emptyPreferred = emptyList.getPreferredSize(available)
    check:
      emptyPreferred.width == 0
      emptyPreferred.height == 0

  test "Focus capability":
    # Test focus determination
    var listWidget = list(@["A", "B"])
    check listWidget.canFocus() == true

    # Disabled list can't focus
    listWidget.setState(Disabled)
    check listWidget.canFocus() == false

    # Empty list can't focus
    let emptyList = newList()
    check emptyList.canFocus() == false

    # List with only unselectable items can't focus
    let unselectableList = newList(@[newListItem("Can't select", none(Style), false)])
    check unselectableList.canFocus() == false

  test "Wide-character list items render and pad by display width":
    let listWidget = newList(@[newListItem("日本"), newListItem("ab")])
    var buf = newBuffer(6, 2)
    listWidget.render(rect(0, 0, 6, 2), buf)
    # Row 0: "日本" (4 cols) + 2 trailing spaces
    check buf[0, 0].symbol == "日"
    check buf[2, 0].symbol == "本"
    check buf[4, 0].symbol == " "
    check buf[5, 0].symbol == " "
    # Row 1: "ab" + 4 trailing spaces
    check buf[0, 1].symbol == "a"
    check buf[1, 1].symbol == "b"
    check buf[5, 1].symbol == " "

  test "Wide-character list item truncates with ellipsis":
    let listWidget = newList(@[newListItem("日本語ABCDE")])
    var buf = newBuffer(5, 1)
    listWidget.render(rect(0, 0, 5, 1), buf)
    # Width 5: keep first 2 cols of content then "..."
    # truncateToWidth("日本語ABCDE", 2) = "日" (2 cols); + "..." => "日..." total 5
    check buf[0, 0].symbol == "日"
    check buf[2, 0].symbol == "."
    check buf[4, 0].symbol == "."

  test "isFocused reflects keyboardFocused after setFocus":
    var listWidget = list(@["A", "B", "C"])
    check not listWidget.isFocused()
    check not listWidget.keyboardFocused

    listWidget.setFocus(true)
    check listWidget.isFocused()
    check listWidget.keyboardFocused
    # setFocus tracks `keyboardFocused` only; the visual `state` is untouched.
    check listWidget.state == Normal

    listWidget.setFocus(false)
    check not listWidget.isFocused()
    check not listWidget.keyboardFocused
    check listWidget.state == Normal

  test "setEnabled(false) clears keyboard focus":
    var listWidget = list(@["A", "B", "C"])
    listWidget.setFocus(true)
    check listWidget.isFocused()

    listWidget.setEnabled(false)
    check not listWidget.isFocused()
    check not listWidget.keyboardFocused
    check listWidget.state == Disabled

  test "setState(Disabled) clears keyboard focus":
    var listWidget = list(@["A", "B", "C"])
    listWidget.setFocus(true)
    check listWidget.isFocused()

    listWidget.setState(Disabled)
    check not listWidget.isFocused()
    check not listWidget.keyboardFocused
    check listWidget.state == Disabled

  test "setFocus does not clobber Disabled state":
    var listWidget = list(@["A", "B", "C"])
    listWidget.setEnabled(false)
    # A disabled list ignores setFocus and stays disabled/unfocused.
    listWidget.setFocus(true)
    check not listWidget.isFocused()
    check listWidget.state == Disabled

  test "Highlight style only applies while keyboard focused":
    var listWidget = newList(
      @[listItem("A"), listItem("B")],
      Single,
      style = ListStyle(
        normal: style(White),
        selected: style(Black, White),
        highlighted: style(Yellow, BrightBlack),
        disabled: style(BrightBlack, Reset),
      ),
    )
    listWidget.highlightedIndex = 0

    # Not focused: highlighted row renders with the normal style.
    check listWidget.getItemStyle(0) == style(White)

    # Focused: the highlighted row picks up the highlight style.
    listWidget.setFocus(true)
    check listWidget.getItemStyle(0) == style(Yellow, BrightBlack)

  test "handleKeyEvent ignores keys when not focused":
    var listWidget = selectList(@["A", "B", "C"])
    check listWidget.highlightedIndex == 0

    # Not focused: navigation keys are not consumed and the highlight is unmoved.
    let downEvent = KeyEvent(code: ArrowDown, char: "", modifiers: {})
    check listWidget.handleKeyEvent(downEvent) == erContinue
    check listWidget.highlightedIndex == 0

    # Vim 'j' is also ignored while unfocused.
    let jEvent = KeyEvent(code: Char, char: "j", modifiers: {})
    check listWidget.handleKeyEvent(jEvent) == erContinue
    check listWidget.highlightedIndex == 0

  test "handleKeyEvent consumes keys when focused":
    var listWidget = selectList(@["A", "B", "C"])
    listWidget.setFocus(true)
    check listWidget.highlightedIndex == 0

    let downEvent = KeyEvent(code: ArrowDown, char: "", modifiers: {})
    check listWidget.handleKeyEvent(downEvent) == erConsume
    check listWidget.highlightedIndex == 1

    # Vim 'j' moves down once focused.
    let jEvent = KeyEvent(code: Char, char: "j", modifiers: {})
    check listWidget.handleKeyEvent(jEvent) == erConsume
    check listWidget.highlightedIndex == 2

  test "Disabling a focused list fires onBlur":
    # A focused list that gets disabled loses keyboard focus, so onBlur must
    # fire -- consistently via both setEnabled(false) and setState(Disabled),
    # matching setFocus(false) and Button's setEnabled(false).
    var blurCount = 0
    var listWidget = list(@["A", "B", "C"])
    listWidget.onBlur = proc() =
      blurCount.inc()

    listWidget.setFocus(true)
    listWidget.setEnabled(false)
    check blurCount == 1
    check not listWidget.isFocused()

    # Re-enable, re-focus, then disable via setState(Disabled): onBlur again.
    listWidget.setEnabled(true)
    listWidget.setFocus(true)
    listWidget.setState(Disabled)
    check blurCount == 2
    check not listWidget.isFocused()

    # Disabling an already-unfocused list does not fire onBlur.
    listWidget.setEnabled(true)
    listWidget.setEnabled(false)
    check blurCount == 2

  test "setFocus fires onFocus/onBlur on transition":
    var focusCount = 0
    var blurCount = 0
    var listWidget = list(@["A", "B", "C"])
    listWidget.onFocus = proc() =
      focusCount.inc()
    listWidget.onBlur = proc() =
      blurCount.inc()

    listWidget.setFocus(true)
    check focusCount == 1
    check blurCount == 0

    # Re-focusing an already-focused list does not re-fire onFocus.
    listWidget.setFocus(true)
    check focusCount == 1

    listWidget.setFocus(false)
    check focusCount == 1
    check blurCount == 1

    # Re-blurring does not re-fire onBlur.
    listWidget.setFocus(false)
    check blurCount == 1

  test "setFocus is refused when the list cannot focus":
    # An empty list and an enabled list with no selectable item are both
    # non-focusable (canFocus() == false), so acquiring focus is refused instead
    # of silently swallowing navigation keys.
    var emptyList = list(newSeq[string]())
    check not emptyList.canFocus()
    emptyList.setFocus(true)
    check not emptyList.isFocused()
    check not emptyList.keyboardFocused

    var unselectableList = newList(@[newListItem("A", selectable = false)])
    check not unselectableList.canFocus()
    unselectableList.setFocus(true)
    check not unselectableList.isFocused()

  test "clearItems drops keyboard focus and fires onBlur":
    var blurCount = 0
    var listWidget = list(@["A", "B"])
    listWidget.onBlur = proc() =
      blurCount.inc()
    listWidget.setFocus(true)
    check listWidget.isFocused()

    # Clearing every item makes the list non-focusable, so it must relinquish
    # focus instead of reporting focus / swallowing keys with nothing to navigate.
    listWidget.clearItems()
    check not listWidget.canFocus()
    check not listWidget.isFocused()
    check not listWidget.keyboardFocused
    check blurCount == 1
    # An unfocused empty list no longer consumes navigation keys.
    check listWidget.handleKeyEvent(KeyEvent(code: ArrowDown)) == erContinue

  test "removeItem of the last selectable item drops keyboard focus":
    var blurCount = 0
    var listWidget = list(@["A"])
    listWidget.onBlur = proc() =
      blurCount.inc()
    listWidget.setFocus(true)
    check listWidget.isFocused()

    listWidget.removeItem(0)
    check not listWidget.canFocus()
    check not listWidget.isFocused()
    check blurCount == 1

  test "setItems keeps focus while items stay selectable, drops it when empty":
    var blurCount = 0
    var listWidget = list(@["A", "B"])
    listWidget.onBlur = proc() =
      blurCount.inc()
    listWidget.setFocus(true)

    # Replacing with fresh selectable items keeps the list focusable -> focus held.
    listWidget.setItems(@["x", "y", "z"])
    check listWidget.isFocused()
    check blurCount == 0

    # Replacing with no items relinquishes focus exactly once.
    listWidget.setItems(newSeq[string]())
    check not listWidget.isFocused()
    check blurCount == 1
