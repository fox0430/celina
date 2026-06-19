## Structural regression tests for `with*` widget builders.
##
## These tests guard against the "silently dropped field" bug class: a builder
## that rebuilds a widget but forgets to carry a field over. Instead of listing
## fields by hand (which can itself miss a field), they walk every field with
## `fieldPairs` and assert that all fields the builder is *not* meant to change
## are preserved. Adding a new widget field is automatically covered.

import std/unittest

import ../celina/core/[geometry, buffer, colors, events, borders]
import ../celina/widgets/[button, input, tabs, text, list, progress]

proc droppedFields[T](src, dst: T, changed: openArray[string]): seq[string] =
  ## Names of fields that should have been carried over from `src` to `dst`
  ## but were not (i.e. fields outside `changed` that differ between the two).
  ## A field whose type has no `==` is reported too, so it cannot hide a drop.
  for name, a, b in fieldPairs(src[], dst[]):
    if name notin changed:
      when compiles(a != b):
        if a != b:
          result.add name
      else:
        result.add name & " (uncomparable)"

proc fullButton(): Button =
  ## A Button with every field set to a distinct non-default value, so any
  ## dropped field shows up as a difference.
  result = newButton("source", minWidth = 5, padding = 3)
  result.normalStyle = style(Red)
  result.hoveredStyle = style(Green)
  result.pressedStyle = style(Blue)
  result.focusedStyle = style(Yellow)
  result.disabledStyle = style(Magenta)
  result.state = Hovered
  result.enabled = false
  result.onClick = proc() =
    discard
  result.onMouseEnter = proc() =
    discard
  result.onMouseLeave = proc() =
    discard
  result.onFocus = proc() =
    discard
  result.onBlur = proc() =
    discard
  result.onKeyPress = proc(key: KeyEvent): EventResult =
    erConsume

proc fullInput(): Input =
  ## An Input with every field set to a distinct non-default value.
  result = newInput(placeholder = "ph", maxLength = 7, readOnly = true, password = true)
  result.setText("hello")
  result.normalStyle = style(Red)
  result.focusedStyle = style(Green)
  result.placeholderStyle = style(Blue)
  result.cursorStyle = style(Yellow)
  result.selectionStyle = style(Magenta)
  result.borderStyle = bkDouble
  result.borderNormalStyle = style(Cyan)
  result.borderFocusedStyle = style(White)
  result.onTextChanged = proc(text: string) =
    discard
  result.onEnter = proc(text: string) =
    discard
  result.onFocus = proc() =
    discard
  result.onBlur = proc() =
    discard
  result.onKeyPress = proc(key: KeyEvent): EventResult =
    erConsume

proc fullTabs(): Tabs =
  ## A Tabs with every field set to a distinct non-default value.
  result = newTabs(
    @[
      Tab(title: "one", content: newText("c1")),
      Tab(title: "two", content: newText("c2")),
    ],
    activeIndex = 1,
    position = Bottom,
    showBorder = false,
  )
  result.tabStyle = TabStyle(
    activeStyle: style(Red),
    inactiveStyle: style(Green),
    borderStyle: style(Blue),
    dividerChar: "|",
  )

proc fullText(): Text =
  ## A Text with every field set to a distinct non-default value.
  newText("source", style(Red), Center, WordWrap)

proc fullList(): List =
  ## A List with every field set to a distinct non-default value.
  result = newList(
    @[listItem("a"), listItem("b")],
    selectionMode = Multiple,
    style = ListStyle(
      normal: style(Red),
      selected: style(Green),
      highlighted: style(Blue),
      disabled: style(Yellow),
    ),
    bulletPrefix = "* ",
    showScrollbar = false,
    callbacks = ListCallbacks(
      onSelect: proc(index: int) =
        discard,
      onMultiSelect: proc(indices: seq[int]) =
        discard,
      onHighlight: proc(index: int) =
        discard,
    ),
  )
  result.state = Disabled
  result.selectedIndices = @[1]
  result.highlightedIndex = 1
  result.scrollOffset = 1
  result.visibleCount = 4

proc fullProgressBar(): ProgressBar =
  ## A ProgressBar with every field set to a distinct non-default value.
  result = newProgressBar(0.42, "source")
  result.setCustomChars("F", "E", "P") # also sets kind = pkCustom
  result.barStyle = style(Red)
  result.backgroundStyle = style(Green)
  result.textStyle = style(Blue)
  result.percentageStyle = style(Yellow)
  result.showPercentage = false
  result.showBar = false
  result.showBrackets = false
  result.minWidth = 7
  result.onUpdate = proc(value: float) =
    discard

let noDrop = newSeq[string]()

suite "Builder field preservation (structural)":
  suite "Button builders preserve every other field":
    test "withText changes only text":
      let src = fullButton()
      check droppedFields(src, src.withText("changed"), ["text"]) == noDrop

    test "withPadding changes only padding":
      let src = fullButton()
      check droppedFields(src, src.withPadding(9), ["padding"]) == noDrop

    test "withMinWidth changes only minWidth":
      let src = fullButton()
      check droppedFields(src, src.withMinWidth(11), ["minWidth"]) == noDrop

    test "withOnClick changes only onClick":
      let src = fullButton()
      let cb = proc() =
        discard
      check droppedFields(src, src.withOnClick(cb), ["onClick"]) == noDrop

    test "withStyles (all overridden) changes only the style fields":
      let src = fullButton()
      let dst = src.withStyles(
        normal = style(Black),
        hovered = style(Cyan),
        pressed = style(White),
        focused = style(BrightBlack),
        disabled = style(BrightRed),
      )
      check droppedFields(
        src,
        dst,
        ["normalStyle", "hoveredStyle", "pressedStyle", "focusedStyle", "disabledStyle"],
      ) == noDrop

    test "withStyles (partial) overrides only the given style":
      let src = fullButton()
      check droppedFields(src, src.withStyles(normal = style(Black)), ["normalStyle"]) ==
        noDrop

    test "withEventHandlers (no args) preserves everything":
      let src = fullButton()
      check droppedFields(src, src.withEventHandlers(), []) == noDrop

    test "withEventHandlers (one handler) changes only that handler":
      let src = fullButton()
      let cb = proc() =
        discard
      check droppedFields(src, src.withEventHandlers(onClick = cb), ["onClick"]) ==
        noDrop

  suite "Input builders preserve every other field":
    test "withText changes only state":
      let src = fullInput()
      check droppedFields(src, src.withText("changed"), ["state"]) == noDrop

    test "withPlaceholder changes only placeholder":
      let src = fullInput()
      check droppedFields(src, src.withPlaceholder("other"), ["placeholder"]) == noDrop

    test "withMaxLength changes only maxLength":
      let src = fullInput()
      check droppedFields(src, src.withMaxLength(9), ["maxLength"]) == noDrop

    test "withStyles (all overridden) changes only the style fields":
      let src = fullInput()
      let dst = src.withStyles(
        normal = style(Black),
        focused = style(White),
        placeholder = style(BrightBlack),
        cursor = style(BrightRed),
        selection = style(BrightGreen),
      )
      check droppedFields(
        src,
        dst,
        [
          "normalStyle", "focusedStyle", "placeholderStyle", "cursorStyle",
          "selectionStyle",
        ],
      ) == noDrop

    test "withStyles (partial) overrides only the given style":
      let src = fullInput()
      check droppedFields(src, src.withStyles(normal = style(Black)), ["normalStyle"]) ==
        noDrop

    test "withEventHandlers (no args) preserves everything":
      let src = fullInput()
      check droppedFields(src, src.withEventHandlers(), []) == noDrop

    test "withEventHandlers (one handler) changes only that handler":
      let src = fullInput()
      let cb = proc(text: string) =
        discard
      check droppedFields(
        src, src.withEventHandlers(onTextChanged = cb), ["onTextChanged"]
      ) == noDrop

  suite "Tabs builders preserve every other field":
    test "withStyle changes only tabStyle":
      let src = fullTabs()
      check droppedFields(src, src.withStyle(defaultTabStyle()), ["tabStyle"]) == noDrop

    test "withPosition changes only position":
      let src = fullTabs()
      check droppedFields(src, src.withPosition(Top), ["position"]) == noDrop

    test "withBorder changes only showBorder":
      let src = fullTabs()
      check droppedFields(src, src.withBorder(true), ["showBorder"]) == noDrop

  suite "Text builders preserve every other field":
    test "withStyle changes only style":
      let src = fullText()
      check droppedFields(src, src.withStyle(style(Blue)), ["style"]) == noDrop

    test "withAlignment changes only alignment":
      let src = fullText()
      check droppedFields(src, src.withAlignment(Right), ["alignment"]) == noDrop

    test "withWrap changes only wrap":
      let src = fullText()
      check droppedFields(src, src.withWrap(CharWrap), ["wrap"]) == noDrop

  suite "List builders preserve every other field":
    test "withItems changes only items and the derived selection fields":
      let src = fullList()
      let dst = src.withItems(@[listItem("x")])
      check droppedFields(
        src, dst, ["items", "selectedIndices", "highlightedIndex", "scrollOffset"]
      ) == noDrop

    test "withSelectionMode changes only mode and selection":
      let src = fullList()
      check droppedFields(
        src, src.withSelectionMode(Single), ["selectionMode", "selectedIndices"]
      ) == noDrop

    test "withStyles (all overridden) changes only the style fields":
      let src = fullList()
      let dst = src.withStyles(
        normal = style(Black),
        selected = style(White),
        highlighted = style(BrightBlack),
        disabled = style(BrightRed),
      )
      check droppedFields(
        src, dst, ["normalStyle", "selectedStyle", "highlightedStyle", "disabledStyle"]
      ) == noDrop

    test "withStyles (partial) overrides only the given style":
      let src = fullList()
      check droppedFields(src, src.withStyles(normal = style(Black)), ["normalStyle"]) ==
        noDrop

    test "withBulletPrefix changes only bulletPrefix":
      let src = fullList()
      check droppedFields(src, src.withBulletPrefix("- "), ["bulletPrefix"]) == noDrop

    test "withScrollbar changes only showScrollbar":
      let src = fullList()
      check droppedFields(src, src.withScrollbar(true), ["showScrollbar"]) == noDrop

  suite "ProgressBar builders preserve every other field":
    test "withValue changes only value":
      let src = fullProgressBar()
      check droppedFields(src, src.withValue(0.84), ["value"]) == noDrop

    test "withLabel changes only label":
      let src = fullProgressBar()
      check droppedFields(src, src.withLabel("changed"), ["label"]) == noDrop

    test "withKind changes only kind and its character fields":
      let src = fullProgressBar()
      check droppedFields(
        src, src.withKind(pkLine), ["kindVal", "filledChar", "emptyChar", "fillChar"]
      ) == noDrop

    test "withColors (per-field, all overridden) changes only the color fields":
      let src = fullProgressBar()
      let dst = src.withColors(
        barStyle = style(Black),
        backgroundStyle = style(White),
        textStyle = style(BrightBlack),
        percentageStyle = style(BrightRed),
      )
      check droppedFields(
        src, dst, ["barStyle", "backgroundStyle", "textStyle", "percentageStyle"]
      ) == noDrop

    test "withColors (aggregate) changes only the color fields":
      let src = fullProgressBar()
      let colors = ProgressColors(
        bar: style(Black),
        background: style(White),
        text: style(BrightBlack),
        percentage: style(BrightRed),
      )
      check droppedFields(
        src,
        src.withColors(colors),
        ["barStyle", "backgroundStyle", "textStyle", "percentageStyle"],
      ) == noDrop

    test "withShowPercentage changes only showPercentage":
      let src = fullProgressBar()
      check droppedFields(src, src.withShowPercentage(true), ["showPercentage"]) ==
        noDrop

    test "withShowBar changes only showBar":
      let src = fullProgressBar()
      check droppedFields(src, src.withShowBar(true), ["showBar"]) == noDrop

    test "withShowBrackets changes only showBrackets":
      let src = fullProgressBar()
      check droppedFields(src, src.withShowBrackets(true), ["showBrackets"]) == noDrop

    test "withCustomChars changes only the character fields":
      let src = fullProgressBar()
      check droppedFields(
        src, src.withCustomChars("X", "Y", "Z"), ["filledChar", "emptyChar", "fillChar"]
      ) == noDrop

    test "withMinWidth changes only minWidth":
      let src = fullProgressBar()
      check droppedFields(src, src.withMinWidth(11), ["minWidth"]) == noDrop

    test "withOnUpdate changes only onUpdate":
      let src = fullProgressBar()
      let cb = proc(value: float) =
        discard
      check droppedFields(src, src.withOnUpdate(cb), ["onUpdate"]) == noDrop
