## Test for Progress Bar widget

import std/[unittest, strutils]

import ../celina/core/[geometry, colors, buffer]
import ../celina/widgets/progress {.all.}

suite "Progress Bar Widget Tests":
  suite "Progress Bar Creation Tests":
    test "Basic progress bar creation":
      let bar = newProgressBar(0.5, "Test Progress")
      check bar.getValue() == 0.5
      check "Test Progress" in bar.getLabelWithPercentage()
      check bar.getLabelWithPercentage().contains("%")

    test "Progress bar with custom parameters":
      let bar = newProgressBar(
        value = 0.75,
        label = "Custom",
        showPercentage = false,
        showBar = true,
        style = Line,
        minWidth = 20,
      )
      check bar.getValue() == 0.75
      check "Custom" in bar.getLabelWithPercentage()
      check not bar.getLabelWithPercentage().contains("%")

    test "Value clamping":
      let bar1 = newProgressBar(1.5, "Over")
      check bar1.getValue() == 1.0

      let bar2 = newProgressBar(-0.5, "Under")
      check bar2.getValue() == 0.0

    test "Convenience constructors":
      let simple = simpleProgressBar(0.5, "Simple")
      check simple.getValue() == 0.5
      check "Simple" in simple.getLabelWithPercentage()

      let minimal = minimalProgressBar(0.3)
      check minimal.getValue() == 0.3
      check minimal.getLabelWithPercentage() == "30%"

      let textOnly = textOnlyProgressBar(0.7, "Text")
      check textOnly.getValue() == 0.7
      check "Text" in textOnly.getLabelWithPercentage()

      let colored = coloredProgressBar(0.4, "Colored", Cyan)
      check colored.getValue() == 0.4
      check "Colored" in colored.getLabelWithPercentage()

      let indeterminate = indeterminateProgressBar("Loading")
      check indeterminate.getValue() == 0.0
      check "Loading" in indeterminate.getLabelWithPercentage()

  suite "Value Management Tests":
    test "Set and get value":
      var bar = newProgressBar(0.0)
      check bar.getValue() == 0.0

      bar.setValue(0.5)
      check bar.getValue() == 0.5

      bar.setValue(1.5) # Should clamp to 1.0
      check bar.getValue() == 1.0

      bar.setValue(-0.5) # Should clamp to 0.0
      check bar.getValue() == 0.0

    test "Set progress from current/total":
      var bar = newProgressBar(0.0)

      bar.setProgress(50, 100)
      check bar.getValue() == 0.5

      bar.setProgress(75, 100)
      check bar.getValue() == 0.75

      bar.setProgress(100, 100)
      check bar.getValue() == 1.0

      bar.setProgress(10, 0) # Division by zero case
      check bar.getValue() == 0.0

    test "Increment and decrement":
      var bar = newProgressBar(0.5)

      bar.increment(0.1)
      check abs(bar.getValue() - 0.6) < 0.001

      bar.increment(0.5) # Should clamp to 1.0
      check bar.getValue() == 1.0

      bar.decrement(0.3)
      check abs(bar.getValue() - 0.7) < 0.001

      bar.decrement(0.8) # Should clamp to 0.0
      check bar.getValue() == 0.0

    test "Reset and complete":
      var bar = newProgressBar(0.5)

      bar.reset()
      check bar.getValue() == 0.0
      check not bar.isComplete()

      bar.complete()
      check bar.getValue() == 1.0
      check bar.isComplete()

    test "Update callback":
      var callbackValue = 0.0
      var callbackCalled = false

      var bar = newProgressBar(
        0.0,
        onUpdate = proc(value: float) =
          callbackValue = value
          callbackCalled = true,
      )

      bar.setValue(0.75)
      check callbackCalled == true
      check callbackValue == 0.75

  suite "Display Tests":
    test "Get percentage text":
      var bar = newProgressBar(0.0)
      check bar.getPercentageText() == "0%"

      bar.setValue(0.5)
      check bar.getPercentageText() == "50%"

      bar.setValue(0.756)
      check bar.getPercentageText() == "75%" # Should round down

      bar.setValue(1.0)
      check bar.getPercentageText() == "100%"

    test "Get label with percentage":
      var bar = newProgressBar(0.5, "Progress")
      check bar.getLabelWithPercentage() == "Progress 50%"

      bar.showPercentage = false
      check bar.getLabelWithPercentage() == "Progress"

      bar.label = ""
      bar.showPercentage = true
      check bar.getLabelWithPercentage() == "50%"

      bar.showPercentage = false
      check bar.getLabelWithPercentage() == ""

    test "Progress characters by style":
      let blockBar = newProgressBar(0.5, style = Block)
      let (filled1, empty1, partial1) = blockBar.getProgressChars()
      check filled1 == "█"
      check empty1 == "░"
      check partial1 == "▒"

      let lineBar = newProgressBar(0.5, style = Line)
      let (filled2, empty2, partial2) = lineBar.getProgressChars()
      check filled2 == "="
      check empty2 == " "
      check partial2 == ">"

      # Dots style has been removed - skipping this test

      let arrowBar = newProgressBar(0.5, style = Arrow)
      let (filled4, empty4, partial4) = arrowBar.getProgressChars()
      check filled4 == "═"
      check empty4 == " "
      check partial4 == ">"

      let hashBar = newProgressBar(0.5, style = Hash)
      let (filled5, empty5, partial5) = hashBar.getProgressChars()
      check filled5 == "#"
      check empty5 == "-"
      check partial5 == "="

      let customBar = newProgressBar(
        0.5, style = Custom, filledChar = "*", emptyChar = ".", fillChar = "~"
      )
      let (filled6, empty6, partial6) = customBar.getProgressChars()
      check filled6 == "*"
      check empty6 == "."
      check partial6 == "~"

  suite "Size Tests":
    test "Minimum size calculation":
      let bar1 = newProgressBar(0.5, "Test")
      let minSize1 = bar1.getMinSize()
      check minSize1.width >= 10 # Default minWidth
      check minSize1.height == 2 # Two lines with label and bar

      let bar2 = newProgressBar(0.5, "", showBar = true)
      let minSize2 = bar2.getMinSize()
      check minSize2.height == 2 # Bar with percentage takes 2 lines

      let bar3 = newProgressBar(0.5, "Label", showBar = false)
      let minSize3 = bar3.getMinSize()
      check minSize3.height == 1 # Text only

    test "Preferred size calculation":
      let bar = newProgressBar(0.5, "Test")
      let available = size(100, 10)
      let preferred = bar.getPreferredSize(available)
      check preferred.width <= 40 # Prefers up to 40 chars
      check preferred.width >= bar.getMinSize().width

  suite "Rendering Tests":
    test "Basic rendering without crash":
      var buf = newBuffer(50, 10)
      let bar = newProgressBar(0.5, "Test Progress")

      # Should not crash
      bar.render(rect(0, 0, 50, 2), buf)

    test "Render empty area":
      var buf = newBuffer(50, 10)
      let bar = newProgressBar(0.5, "Test")

      # Should handle empty area gracefully
      bar.render(rect(0, 0, 0, 0), buf)

    test "Render different styles":
      var buf = newBuffer(50, 10)

      for style in [Block, Line, Arrow, Hash]:
        let bar = newProgressBar(0.5, "Style Test", style = style)
        bar.render(rect(0, 0, 50, 2), buf)

    test "Render with and without percentage":
      var buf = newBuffer(50, 10)

      let bar1 = newProgressBar(0.5, "With %", showPercentage = true)
      bar1.render(rect(0, 0, 50, 2), buf)

      let bar2 = newProgressBar(0.5, "Without %", showPercentage = false)
      bar2.render(rect(0, 2, 50, 2), buf)

    test "Render text only":
      var buf = newBuffer(50, 10)
      let bar = textOnlyProgressBar(0.75, "Text Only")
      bar.render(rect(0, 0, 50, 1), buf)

  suite "Setter Methods Tests":
    test "Label setter":
      var bar = newProgressBar(0.5, "Original")
      bar.label = "Modified"
      check "Modified" in bar.getLabelWithPercentage()

    test "Style setters":
      var bar = newProgressBar(0.5)
      bar.style = Line
      let (filled, empty, partial) = bar.getProgressChars()
      check filled == "="
      check empty == " "
      check partial == ">"

    test "Boolean setters":
      var bar = newProgressBar(0.5, "Test")
      bar.showPercentage = false
      check bar.getLabelWithPercentage() == "Test"

      bar.showPercentage = true
      check "50%" in bar.getLabelWithPercentage()

    test "Brackets setter":
      var hashBar = newProgressBar(0.5, "Hash", style = Hash)
      hashBar.showBrackets = true
      # Should render with brackets [####----]
      var buf = newBuffer(20, 2)
      hashBar.render(rect(0, 0, 20, 2), buf)

      hashBar.showBrackets = false
      # Should render without brackets ####----
      hashBar.render(rect(0, 0, 20, 2), buf)

      var lineBar = newProgressBar(0.5, "Line", style = Line)
      lineBar.showBrackets = true
      lineBar.render(rect(0, 0, 20, 2), buf)

      lineBar.showBrackets = false
      lineBar.render(rect(0, 0, 20, 2), buf)

      var arrowBar = newProgressBar(0.5, "Arrow", style = Arrow)
      arrowBar.showBrackets = true
      arrowBar.render(rect(0, 0, 20, 2), buf)

      arrowBar.showBrackets = false
      arrowBar.render(rect(0, 0, 20, 2), buf)

    test "Min width setter":
      var bar = newProgressBar(0.5, "Short")
      bar.minWidth = 20
      let minSize = bar.getMinSize()
      check minSize.width >= 20

    test "Custom chars setter":
      var bar = newProgressBar(0.5)
      bar.setCustomChars("*", ".", "~")
      let (filled, empty, partial) = bar.getProgressChars()
      check filled == "*"
      check empty == "."
      check partial == "~"

    test "Set colors helper":
      var bar = newProgressBar(0.5)
      bar.setColors(
        barStyle = style(White, Green), backgroundStyle = style(Black, Reset)
      )
      # Colors are set, but we can't directly access them - test by rendering
      var buf = newBuffer(20, 2)
      bar.render(rect(0, 0, 20, 2), buf)

    test "Update callback setter":
      var called = false
      var bar = newProgressBar(0.5)
      bar.onUpdate = proc(value: float) =
        called = true
      bar.setValue(0.7)
      check called == true

  suite "Builder Methods Tests (Chaining)":
    test "Method chaining with mutating builders":
      let bar = newProgressBar(0.3)
        .withValue(0.7)
        .withLabel("Chained")
        .withStyle(Line)
        .withShowPercentage(false)
        .withShowBrackets(true)

      check bar.getValue() == 0.7
      check "Chained" in bar.getLabelWithPercentage()
      let (filled, _, _) = bar.getProgressChars()
      check filled == "=" # Line style

    test "Chaining returns same object":
      let bar1 = newProgressBar(0.5)
      let bar2 = bar1.withLabel("Test")
      check cast[pointer](bar1) == cast[pointer](bar2)

    test "Complex chaining":
      var callbackCalled = false
      let bar = newProgressBar(0.0)
        .withLabel("Complex")
        .withStyle(Arrow)
        .withColors(
          barStyle = style(White, Green), percentageStyle = style(Cyan, Reset)
        )
        .withShowBar(true)
        .withShowBrackets(false)
        .withMinWidth(30)
        .withOnUpdate(
          proc(value: float) =
            callbackCalled = true
        )
        .withValue(0.5)

      check "Complex" in bar.getLabelWithPercentage()
      let (filled, _, _) = bar.getProgressChars()
      check filled == "═" # Arrow style
      check bar.getValue() == 0.5
      check callbackCalled == true

  suite "Utility Functions Tests":
    test "Format bytes":
      check formatBytes(0) == "0 B"
      check formatBytes(512) == "512 B"
      check formatBytes(1024) == "1.00 KB"
      check formatBytes(1536) == "1.50 KB"
      check formatBytes(1024 * 1024) == "1.00 MB"
      check formatBytes(5 * 1024 * 1024 + 512 * 1024) == "5.50 MB"
      check formatBytes(1024'i64 * 1024 * 1024) == "1.00 GB"
      check formatBytes(1024'i64 * 1024 * 1024 * 1024) == "1.00 TB"

    test "Format time":
      check formatTime(0) == "0s"
      check formatTime(30) == "30s"
      check formatTime(60) == "1m 0s"
      check formatTime(90) == "1m 30s"
      check formatTime(3600) == "1h 0m 0s"
      check formatTime(3661) == "1h 1m 1s"
      check formatTime(7200) == "2h 0m 0s"

    test "Download progress bar":
      let bar = downloadProgressBar(512 * 1024, 1024 * 1024, "Downloading")
      check bar.getValue() == 0.5
      check "512.00 KB / 1.00 MB" in bar.getLabelWithPercentage()
      check "Downloading" in bar.getLabelWithPercentage()

    test "Task progress bar":
      let bar = taskProgressBar(3, 10, "Tasks")
      check bar.getValue() == 0.3
      check "3/10 tasks" in bar.getLabelWithPercentage()
      check "Tasks" in bar.getLabelWithPercentage()
