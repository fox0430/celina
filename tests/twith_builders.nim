## Structural regression tests for `with*` widget builders.
##
## These tests guard against the "silently dropped field" bug class: a builder
## that rebuilds a widget but forgets to carry a field over. Instead of listing
## fields by hand (which can itself miss a field), they walk every field with
## `fieldPairs` and assert that all fields the builder is *not* meant to change
## are preserved. Adding a new widget field is automatically covered.

import std/unittest

import ../celina/core/[geometry, buffer, colors, events, borders]
import ../celina/widgets/[button, input]

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
