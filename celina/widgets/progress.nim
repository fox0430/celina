## Progress bar widget for displaying task progress
##
## This module provides progress bar widgets with customizable styles,
## labels, and visual representations.
##
## ### Usage Example:
## ```nim
## var progress = newProgressBar(0.0, "Processing")
##
## # Update progress
## progress.setValue(0.5)
## progress.label = "Half complete"
## let percentage = progress.getPercentageText()
## ```

import std/[strformat, math]

import base
import ../core/[geometry, buffer, colors]

type
  ProgressKind* = enum
    ## Progress bar visual style kinds.
    ##
    ## Previously named `ProgressStyle` (when it was both the enum and the
    ## object name); the color aggregate is now `ProgressColors`. Use the
    ## deprecated aliases (`Block`, `Line`, `Arrow`, `Hash`, `Custom`) for
    ## legacy code.
    pkBlock ## Block characters: ███░░░
    pkLine ## Line characters: ━━━── or [━━━──]
    pkArrow ## Arrow style: ══════> or [═════>]
    pkHash ## Hash characters: ####-- or [####--]
    pkCustom ## Custom characters

  ProgressColors* = object ## Style aggregate for progress bar colors
    bar*: Style ## Style for filled portion
    background*: Style ## Style for unfilled portion
    text*: Style ## Style for text/label
    percentage*: Style ## Style for percentage text

  ProgressChars* = object
    ## Glyphs for the bar. Any field left empty falls back to the kind's
    ## default glyph, so a `chars = ...` override applies to *every* kind
    ## (not just `pkCustom`); `pkCustom`, having no glyphs of its own, falls
    ## back to the `pkBlock` defaults.
    filled*: string
    empty*: string
    partial*: string

  ProgressBar* = ref object of Widget ## Progress bar widget
    value: float ## Current progress value (0.0 to 1.0)
    label: string ## Optional label text
    showPercentage: bool ## Show percentage text
    showBar: bool ## Show progress bar visual
    kindVal: ProgressKind
      ## Backing field for the visual kind. External access goes through
      ## the `kind*`/`kind=*` accessors so the setter can keep the per-kind
      ## character fields in sync.
    barStyle: Style ## Style for filled portion
    backgroundStyle: Style ## Style for unfilled portion
    textStyle: Style ## Style for text/label
    percentageStyle: Style ## Style for percentage text
    filledChar: string ## Character for filled portion (custom style)
    emptyChar: string ## Character for empty portion (custom style)
    fillChar: string ## Character for partial fill (custom style)
    minWidth: int ## Minimum bar width
    onUpdate: proc(value: float) ## Called when value changes
    showBrackets: bool ## Show brackets for Hash style [####--]

# Deprecated aliases for the old enum values (template-based so legacy code
# such as `widget.style = Block` and `newProgressBar(..., kind = Block)`
# continues to compile with a warning).
template Block*(): ProgressKind {.deprecated: "Use `pkBlock`".} =
  pkBlock

template Line*(): ProgressKind {.deprecated: "Use `pkLine`".} =
  pkLine

template Arrow*(): ProgressKind {.deprecated: "Use `pkArrow`".} =
  pkArrow

template Hash*(): ProgressKind {.deprecated: "Use `pkHash`".} =
  pkHash

template Custom*(): ProgressKind {.deprecated: "Use `pkCustom`".} =
  pkCustom

proc defaultProgressColors*(kind: ProgressKind = pkBlock): ProgressColors =
  ## Build a default `ProgressColors` whose colors fit the given visual kind.
  ##
  ## Block uses a Green background to make the bar visible on a dark
  ## background; Line/Arrow/Hash omit the background so the line glyphs
  ## stand on their own; Custom uses a neutral default so callers picking
  ## arbitrary glyphs don't get a surprise background colour.
  let bar =
    case kind
    of pkHash, pkLine, pkArrow:
      style(White)
    of pkCustom:
      defaultStyle()
    of pkBlock:
      style(White, Green)
  let bg =
    case kind
    of pkHash, pkLine, pkArrow, pkCustom:
      defaultStyle()
    of pkBlock:
      style(BrightBlack, Reset)
  ProgressColors(
    bar: bar, background: bg, text: defaultStyle(), percentage: style(Cyan, Reset)
  )

proc defaultProgressChars*(kind: ProgressKind = pkBlock): ProgressChars =
  ## Build the default characters for a progress kind. `pkCustom` returns
  ## empty strings; the constructor and `setCustomChars` fall back to the
  ## `pkBlock` defaults for any empty field.
  case kind
  of pkBlock:
    ProgressChars(filled: "█", empty: "░", partial: "▒")
  of pkLine:
    ProgressChars(filled: "=", empty: " ", partial: ">")
  of pkArrow:
    ProgressChars(filled: "═", empty: " ", partial: ">")
  of pkHash:
    ProgressChars(filled: "#", empty: "-", partial: "=")
  of pkCustom:
    ProgressChars()

# Progress bar constructors
proc newProgressBar*(
    value: float = 0.0,
    label: string = "",
    kind: ProgressKind = pkBlock,
    style: ProgressColors = defaultProgressColors(kind),
    chars: ProgressChars = defaultProgressChars(kind),
    showPercentage: bool = true,
    showBar: bool = true,
    showBrackets: bool = true,
    minWidth: int = 10,
    onUpdate: proc(value: float) = nil,
): ProgressBar =
  ## Create a new progress bar widget.
  ##
  ## The visual style is determined by `kind` (an enum). Colors come from
  ## the `style` aggregate, and characters from `chars`. For `pkCustom`,
  ## supply the glyphs via `chars`.
  # Per-field fallback: substitute the kind's default glyph for any field the
  # caller left empty, so partial customizations (e.g. supplying only `empty`)
  # are not silently discarded. This applies to every kind, not just
  # `pkCustom`: `getProgressChars` reads these stored fields directly, so a
  # non-custom bar must end up with a complete glyph set even when `chars` is
  # partial. `pkCustom` has no glyphs of its own, so it falls back to the
  # `pkBlock` defaults.
  let fallback = defaultProgressChars(if kind == pkCustom: pkBlock else: kind)
  let effectiveChars = ProgressChars(
    filled: if chars.filled.len > 0: chars.filled else: fallback.filled,
    empty: if chars.empty.len > 0: chars.empty else: fallback.empty,
    partial: if chars.partial.len > 0: chars.partial else: fallback.partial,
  )
  result = ProgressBar(
    value: clamp(value, 0.0, 1.0),
    label: label,
    showPercentage: showPercentage,
    showBar: showBar,
    kindVal: kind,
    barStyle: style.bar,
    backgroundStyle: style.background,
    textStyle: style.text,
    percentageStyle: style.percentage,
    filledChar: effectiveChars.filled,
    emptyChar: effectiveChars.empty,
    fillChar: effectiveChars.partial,
    minWidth: minWidth,
    onUpdate: onUpdate,
    showBrackets: showBrackets,
  )

proc newProgressBar*(
    value: float,
    label: string = "",
    showPercentage: bool = true,
    showBar: bool = true,
    style: ProgressKind,
    barStyle: Style = defaultStyle(),
    backgroundStyle: Style = defaultStyle(),
    textStyle: Style = defaultStyle(),
    percentageStyle: Style = defaultStyle(),
    filledChar: string = "",
    emptyChar: string = "",
    fillChar: string = "",
    minWidth: int = 10,
    onUpdate: proc(value: float) = nil,
    showBrackets: bool = true,
): ProgressBar {.
    deprecated:
      "Use the aggregate form: newProgressBar(value, label, kind, style: ProgressColors, chars: ProgressChars, ...)"
.} =
  ## Deprecated legacy overload taking the old `style: ProgressKind`
  ## parameter plus individual color/glyph fields. The required positional
  ## `style` disambiguates from the new aggregate-form overload.
  let baseStyle = defaultProgressColors(style)
  let theme = ProgressColors(
    bar: if barStyle == defaultStyle(): baseStyle.bar else: barStyle,
    background:
      if backgroundStyle == defaultStyle(): baseStyle.background else: backgroundStyle,
    text: if textStyle == defaultStyle(): baseStyle.text else: textStyle,
    percentage:
      if percentageStyle == defaultStyle(): baseStyle.percentage else: percentageStyle,
  )
  let chars = ProgressChars(filled: filledChar, empty: emptyChar, partial: fillChar)
  newProgressBar(
    value = value,
    label = label,
    kind = style,
    style = theme,
    chars = chars,
    showPercentage = showPercentage,
    showBar = showBar,
    showBrackets = showBrackets,
    minWidth = minWidth,
    onUpdate = onUpdate,
  )

proc progressBar*(
    value: float = 0.0,
    label: string = "",
    showPercentage: bool = true,
    showBar: bool = true,
    kind: ProgressKind = pkBlock,
): ProgressBar =
  ## Convenience constructor for progress bar with defaults.
  newProgressBar(
    value = value,
    label = label,
    kind = kind,
    showPercentage = showPercentage,
    showBar = showBar,
  )

# Progress value management
proc setValue*(widget: ProgressBar, value: float) =
  ## Set the progress value (0.0 to 1.0)
  widget.value = clamp(value, 0.0, 1.0)
  if widget.onUpdate != nil:
    widget.onUpdate(widget.value)

proc getValue*(widget: ProgressBar): float =
  ## Get the current progress value
  result = widget.value

proc getBackgroundStyle*(widget: ProgressBar): Style =
  ## Get the background style
  result = widget.backgroundStyle

proc setProgress*(widget: ProgressBar, current, total: float) =
  ## Set progress based on current and total values
  if total > 0:
    widget.setValue(current / total)
  else:
    widget.setValue(0.0)

proc increment*(widget: ProgressBar, amount: float = 0.01) =
  ## Increment the progress by a given amount
  widget.setValue(widget.value + amount)

proc decrement*(widget: ProgressBar, amount: float = 0.01) =
  ## Decrement the progress by a given amount
  widget.setValue(widget.value - amount)

proc reset*(widget: ProgressBar) =
  ## Reset progress to 0
  widget.setValue(0.0)

proc complete*(widget: ProgressBar) =
  ## Set progress to 100%
  widget.setValue(1.0)

proc isComplete*(widget: ProgressBar): bool =
  ## Check if progress is at 100%
  result = widget.value >= 1.0

# Style character selection
proc getProgressChars*(widget: ProgressBar): tuple[filled, empty, partial: string] =
  ## Get the characters to use for rendering.
  ##
  ## `filledChar`/`emptyChar`/`fillChar` are the single source of truth: the
  ## constructor, the `kind=` setter and `setCustomChars` all keep them in sync
  ## with the active kind's defaults and any caller overrides. Returning them
  ## directly means a `chars = ...` override is honoured for *every* kind, not
  ## just `pkCustom`. Previously the non-custom kinds returned hardcoded glyphs
  ## here and silently discarded the override.
  result = (widget.filledChar, widget.emptyChar, widget.fillChar)

# Rendering utilities
proc renderWithBrackets(
    widget: ProgressBar,
    width: int,
    buf: var Buffer,
    x, y: int,
    chars: tuple[filled, empty, partial: string],
) =
  ## Common rendering logic for styles with bracket support
  if width < 3: # Need at least space for []
    return

  # Calculate inner bar width (excluding brackets)
  let innerWidth = width - 2
  let filledWidth = int(floor(widget.value * float(innerWidth)))

  # Draw opening bracket
  buf.setString(x, y, "[", defaultStyle())

  if widget.kindVal == pkHash:
    # Special handling for Hash - spaces in empty portion to avoid color inheritance
    for i in 0 ..< filledWidth:
      buf.setString(x + 1 + i, y, chars.filled, widget.barStyle)

    # Empty portion as spaces for Hash style
    for i in filledWidth ..< innerWidth:
      buf.setString(x + 1 + i, y, " ", defaultStyle())
  else:
    # Line/Arrow styles with partial fill support
    let hasPartial = (widget.value * float(innerWidth)) - float(filledWidth) >= 0.5

    # Draw filled portion
    for i in 0 ..< filledWidth:
      buf.setString(x + 1 + i, y, chars.filled, widget.barStyle)

    # Draw partial fill for arrow if applicable
    if hasPartial and filledWidth < innerWidth and widget.kindVal == pkArrow:
      buf.setString(x + 1 + filledWidth, y, chars.partial, widget.barStyle)
      # Draw remaining empty portion
      for i in (filledWidth + 1) ..< innerWidth:
        buf.setString(x + 1 + i, y, chars.empty, widget.backgroundStyle)
    else:
      # Draw empty portion
      for i in filledWidth ..< innerWidth:
        buf.setString(x + 1 + i, y, chars.empty, widget.backgroundStyle)

  # Draw closing bracket
  buf.setString(x + innerWidth + 1, y, "]", defaultStyle())

proc renderWithoutBrackets(
    widget: ProgressBar,
    width: int,
    buf: var Buffer,
    x, y: int,
    chars: tuple[filled, empty, partial: string],
) =
  ## Common rendering logic for styles without brackets
  let filledWidth = int(floor(widget.value * float(width)))

  if widget.kindVal == pkHash:
    # Hash style: simple filled/empty rendering
    for i in 0 ..< filledWidth:
      buf.setString(x + i, y, chars.filled, widget.barStyle)

    # Draw empty portion
    let emptyStyle =
      if widget.backgroundStyle != defaultStyle():
        widget.backgroundStyle
      else:
        defaultStyle()
    for i in filledWidth ..< width:
      buf.setString(x + i, y, chars.empty, emptyStyle)
  else:
    # Line/Arrow styles with partial fill support
    let hasPartial = (widget.value * float(width)) - float(filledWidth) >= 0.5

    # Draw filled portion
    for i in 0 ..< filledWidth:
      buf.setString(x + i, y, chars.filled, widget.barStyle)

    # Draw partial fill for arrow if applicable
    if hasPartial and filledWidth < width and widget.kindVal == pkArrow:
      buf.setString(x + filledWidth, y, chars.partial, widget.barStyle)
      # Draw remaining empty portion
      for i in (filledWidth + 1) ..< width:
        buf.setString(x + i, y, chars.empty, widget.backgroundStyle)
    else:
      # Draw empty portion
      for i in filledWidth ..< width:
        buf.setString(x + i, y, chars.empty, widget.backgroundStyle)

proc renderProgressBar(widget: ProgressBar, width: int, buf: var Buffer, x, y: int) =
  ## Render the progress bar visual at the given position
  if width <= 0:
    return

  let chars = widget.getProgressChars()

  case widget.kindVal
  of pkHash, pkLine, pkArrow:
    # Use the helper functions for bracket-capable styles
    if widget.showBrackets:
      widget.renderWithBrackets(width, buf, x, y, chars)
    else:
      widget.renderWithoutBrackets(width, buf, x, y, chars)
  else:
    # Standard rendering for Block and Custom styles (no bracket support)
    let filledWidth = int(floor(widget.value * float(width)))
    let hasPartial = (widget.value * float(width)) - float(filledWidth) >= 0.5

    # Draw filled portion
    for i in 0 ..< filledWidth:
      buf.setString(x + i, y, chars.filled, widget.barStyle)

    # Draw partial fill if applicable
    if hasPartial and filledWidth < width:
      buf.setString(x + filledWidth, y, chars.partial, widget.barStyle)
      if widget.backgroundStyle != defaultStyle():
        for i in (filledWidth + 1) ..< width:
          buf.setString(x + i, y, chars.empty, widget.backgroundStyle)
    else:
      if widget.backgroundStyle != defaultStyle():
        for i in filledWidth ..< width:
          buf.setString(x + i, y, chars.empty, widget.backgroundStyle)

proc getPercentageText*(widget: ProgressBar): string =
  ## Get the formatted percentage text
  result = fmt"{int(widget.value * 100)}%"

proc getLabelWithPercentage*(widget: ProgressBar): string =
  ## Get combined label and percentage text
  if widget.label.len > 0 and widget.showPercentage:
    result = widget.label & " " & fmt"{int(widget.value * 100)}%"
  elif widget.label.len > 0:
    result = widget.label
  elif widget.showPercentage:
    result = fmt"{int(widget.value * 100)}%"
  else:
    result = ""

# Widget methods
method render*(widget: ProgressBar, area: Rect, buf: var Buffer) =
  ## Render the progress bar widget
  if area.isEmpty:
    return

  # Clear the area first
  let clearStyle = defaultStyle() # Use plain default style for all progress bar types
  for y in 0 ..< area.height:
    for x in 0 ..< area.width:
      buf.setString(area.x + x, area.y + y, " ", clearStyle)

  let text = widget.getLabelWithPercentage()
  let textLen = text.displayWidth

  if widget.showBar:
    # Two-line layout (text above, bar below) requires at least two rows.
    # `pkHash` prefers it even without text, but must still fall back to a
    # single line in a height-1 area — otherwise the bar is drawn at
    # `area.y + 1`, one row outside the widget's area.
    if area.height >= 2 and (textLen > 0 or widget.kindVal == pkHash):
      # Two-line layout: text above, bar below
      let textY = area.y
      let barY = area.y + 1

      # Render text centered
      let textX = area.x + max(0, (area.width - textLen) div 2)
      if widget.label.len > 0 and widget.showPercentage:
        # Split label and percentage
        let labelLen = widget.label.displayWidth
        let percentText = widget.getPercentageText()
        buf.setString(textX, textY, widget.label, widget.textStyle)
        buf.setString(textX + labelLen + 1, textY, percentText, widget.percentageStyle)
      else:
        buf.setString(textX, textY, text, widget.textStyle)

      # Render bar
      widget.renderProgressBar(area.width, buf, area.x, barY)
    else:
      # Single-line layout: bar with overlaid text
      widget.renderProgressBar(area.width, buf, area.x, area.y)

      if textLen > 0 and textLen < area.width - 2:
        # Overlay text on the bar
        let textX = area.x + max(1, (area.width - textLen) div 2)
        buf.setString(textX, area.y, text, widget.textStyle)
  else:
    # Text only, no bar
    if textLen > 0:
      let textX = area.x + max(0, (area.width - textLen) div 2)
      let textY = area.y + max(0, (area.height - 1) div 2)

      if widget.label.len > 0 and widget.showPercentage:
        let labelLen = widget.label.displayWidth
        let percentText = widget.getPercentageText()
        buf.setString(textX, textY, widget.label, widget.textStyle)
        buf.setString(textX + labelLen + 1, textY, percentText, widget.percentageStyle)
      else:
        buf.setString(textX, textY, text, widget.textStyle)

method getMinSize*(widget: ProgressBar): Size =
  ## Get minimum size for progress bar widget
  let textLen = widget.getLabelWithPercentage().displayWidth
  var minBarWidth = max(widget.minWidth, textLen + 2)

  # Hash, Line, Arrow styles need extra space for brackets (if enabled)
  if widget.kindVal in {pkHash, pkLine, pkArrow} and widget.showBar and
      widget.showBrackets:
    minBarWidth = max(minBarWidth, 5) # Minimum [###], [━━━], or [══>] format

  if widget.showBar and widget.getLabelWithPercentage().len > 0:
    size(minBarWidth, 2) # Two lines: text and bar
  else:
    size(minBarWidth, 1) # Single line

method getPreferredSize*(widget: ProgressBar, available: Size): Size =
  ## Get preferred size for progress bar widget
  let minSize = widget.getMinSize()
  size(
    max(minSize.width, min(available.width, 40)), # Prefer up to 40 chars wide
    minSize.height,
  )

# Read accessor for the visual kind
proc kind*(widget: ProgressBar): ProgressKind {.inline.} =
  ## Get the visual kind of the progress bar.
  widget.kindVal

# Setter methods for mutable API
proc `label=`*(widget: ProgressBar, label: string) =
  ## Set the label text
  widget.label = label

proc `showPercentage=`*(widget: ProgressBar, show: bool) =
  ## Set whether to show percentage
  widget.showPercentage = show

proc `showBar=`*(widget: ProgressBar, show: bool) =
  ## Set whether to show the progress bar
  widget.showBar = show

proc `showBrackets=`*(widget: ProgressBar, show: bool) =
  ## Set whether to show brackets for Hash style
  widget.showBrackets = show

proc `kind=`*(widget: ProgressBar, kind: ProgressKind) =
  ## Set the visual kind. Also resets `filledChar`/`emptyChar`/`fillChar`
  ## to the new kind's defaults so a transition to `pkCustom` does not
  ## leave the widget rendering the previous kind's glyphs.
  ##
  ## When switching to `pkCustom`, if the current chars are empty (as they
  ## would be after a fresh `defaultProgressChars(pkCustom)`), the block
  ## defaults are used as fallback so the bar is never silently invisible.
  widget.kindVal = kind
  let c = defaultProgressChars(kind)
  if kind == pkCustom:
    let defaults = defaultProgressChars(pkBlock)
    widget.filledChar = if c.filled.len > 0: c.filled else: defaults.filled
    widget.emptyChar = if c.empty.len > 0: c.empty else: defaults.empty
    widget.fillChar = if c.partial.len > 0: c.partial else: defaults.partial
  else:
    widget.filledChar = c.filled
    widget.emptyChar = c.empty
    widget.fillChar = c.partial

proc style*(widget: ProgressBar): ProgressKind {.deprecated: "Use `kind`".} =
  ## Deprecated accessor for the visual kind (formerly named `style`).
  widget.kindVal

proc `style=`*(widget: ProgressBar, style: ProgressKind) {.deprecated: "Use `kind=`".} =
  ## Deprecated setter for the visual kind (formerly named `style`).
  ## Parameter name is kept as `style` so legacy named-arg callers
  ## (`widget.style = pkLine` is fine; `obj.style=(style: pkLine)` would
  ## otherwise break). Delegates to the `kind=` setter to keep char
  ## state in sync.
  widget.kind = style

proc `barStyle=`*(widget: ProgressBar, style: Style) =
  ## Set the style for filled portion
  widget.barStyle = style

proc `backgroundStyle=`*(widget: ProgressBar, style: Style) =
  ## Set the style for unfilled portion
  widget.backgroundStyle = style

proc `textStyle=`*(widget: ProgressBar, style: Style) =
  ## Set the style for text/label
  widget.textStyle = style

proc `percentageStyle=`*(widget: ProgressBar, style: Style) =
  ## Set the style for percentage text
  widget.percentageStyle = style

proc `minWidth=`*(widget: ProgressBar, width: int) =
  ## Set the minimum bar width
  widget.minWidth = width

proc `onUpdate=`*(widget: ProgressBar, callback: proc(value: float)) =
  ## Set the update callback
  widget.onUpdate = callback

proc setCustomChars*(widget: ProgressBar, filled, empty, partial: string) =
  ## Set custom characters for the progress bar.
  ##
  ## Any empty string is replaced with the corresponding `pkBlock` default
  ## glyph so the bar is never silently invisible. Use ` ` or another
  ## visible whitespace if you really want a blank glyph.
  widget.kind = pkCustom # also resets the char fields via the setter
  let defaults = defaultProgressChars(pkBlock)
  widget.filledChar = if filled.len > 0: filled else: defaults.filled
  widget.emptyChar = if empty.len > 0: empty else: defaults.empty
  widget.fillChar = if partial.len > 0: partial else: defaults.partial

proc setColors*(
    widget: ProgressBar,
    barStyle: Style = defaultStyle(),
    backgroundStyle: Style = defaultStyle(),
    textStyle: Style = defaultStyle(),
    percentageStyle: Style = defaultStyle(),
) =
  ## Set multiple colors at once using individual fields.
  ##
  ## Only non-`defaultStyle()` values are applied; callers can pick and
  ## choose which fields to update. Prefer `setColors(widget, colors:
  ## ProgressColors)` when you want to replace every colour at once.
  if barStyle != defaultStyle():
    widget.barStyle = barStyle
  if backgroundStyle != defaultStyle():
    widget.backgroundStyle = backgroundStyle
  if textStyle != defaultStyle():
    widget.textStyle = textStyle
  if percentageStyle != defaultStyle():
    widget.percentageStyle = percentageStyle

proc setColors*(widget: ProgressBar, colors: ProgressColors) =
  ## Replace every colour slot at once from a `ProgressColors` aggregate.
  widget.barStyle = colors.bar
  widget.backgroundStyle = colors.background
  widget.textStyle = colors.text
  widget.percentageStyle = colors.percentage

# Builder methods for fluent API (each returns an independent copy)
proc withValue*(widget: ProgressBar, value: float): ProgressBar =
  ## Create a copy with a different value.
  ##
  ## Note: `setValue` is invoked on the copy, so any `onUpdate` callback
  ## fires for the copy, not the original.
  result = copyWidget(widget)
  result.setValue(value)

proc withLabel*(widget: ProgressBar, label: string): ProgressBar =
  ## Create a copy with a different label
  result = copyWidget(widget)
  result.label = label

proc withKind*(widget: ProgressBar, kind: ProgressKind): ProgressBar =
  ## Create a copy with a different visual kind
  result = copyWidget(widget)
  result.kind = kind

proc withStyle*(
    widget: ProgressBar, style: ProgressKind
): ProgressBar {.deprecated: "Use `withKind`".} =
  ## Deprecated builder for setting the visual kind (formerly `withStyle`).
  ## Parameter is kept as `style` so legacy `widget.withStyle(style = X)`
  ## named-arg callers keep compiling with just a deprecation warning.
  ## Returns an independent copy.
  result = copyWidget(widget)
  result.kind = style

proc withColors*(
    widget: ProgressBar,
    barStyle: Style = defaultStyle(),
    backgroundStyle: Style = defaultStyle(),
    textStyle: Style = defaultStyle(),
    percentageStyle: Style = defaultStyle(),
): ProgressBar =
  ## Create a copy with different colors (per-field overload).
  result = copyWidget(widget)
  result.setColors(barStyle, backgroundStyle, textStyle, percentageStyle)

proc withColors*(widget: ProgressBar, colors: ProgressColors): ProgressBar =
  ## Create a copy with colors from a `ProgressColors` aggregate.
  result = copyWidget(widget)
  result.setColors(colors)

proc withShowPercentage*(widget: ProgressBar, show: bool): ProgressBar =
  ## Create a copy with a different percentage display setting
  result = copyWidget(widget)
  result.showPercentage = show

proc withShowBar*(widget: ProgressBar, show: bool): ProgressBar =
  ## Create a copy with a different bar display setting
  result = copyWidget(widget)
  result.showBar = show

proc withShowBrackets*(widget: ProgressBar, show: bool): ProgressBar =
  ## Create a copy with a different brackets display setting for Hash style
  result = copyWidget(widget)
  result.showBrackets = show

proc withCustomChars*(
    widget: ProgressBar, filled, empty, partial: string
): ProgressBar =
  ## Create a copy with different custom characters
  result = copyWidget(widget)
  result.setCustomChars(filled, empty, partial)

proc withMinWidth*(widget: ProgressBar, minWidth: int): ProgressBar =
  ## Create a copy with a different minimum width
  result = copyWidget(widget)
  result.minWidth = minWidth

proc withOnUpdate*(widget: ProgressBar, callback: proc(value: float)): ProgressBar =
  ## Create a copy with a different update callback
  result = copyWidget(widget)
  result.onUpdate = callback

# Convenience constructors for common progress bar types
proc simpleProgressBar*(value: float = 0.0, label: string = ""): ProgressBar =
  ## Create a simple progress bar with default styling
  newProgressBar(value, label)

proc minimalProgressBar*(value: float = 0.0): ProgressBar =
  ## Create a minimal progress bar (no label, just bar and percentage)
  newProgressBar(value, "", showPercentage = true, showBar = true)

proc textOnlyProgressBar*(value: float = 0.0, label: string = ""): ProgressBar =
  ## Create a text-only progress indicator (no bar visual)
  newProgressBar(value, label, showPercentage = true, showBar = false)

proc indeterminateProgressBar*(label: string = "Loading..."): ProgressBar =
  ## Create an indeterminate progress bar (for unknown duration tasks)
  ## Note: Animation would need to be handled externally by updating the value
  newProgressBar(
    value = 0.0, label = label, kind = pkArrow, showPercentage = false, showBar = true
  )

proc coloredProgressBar*(
    value: float = 0.0,
    label: string = "",
    color: Color = Green,
    kind: ProgressKind = pkBlock,
    chars: ProgressChars = defaultProgressChars(kind),
): ProgressBar =
  ## Create a progress bar with a specific color theme.
  ##
  ## `chars` is forwarded to `newProgressBar` so callers can build a
  ## colored custom-glyph bar via `coloredProgressBar(kind = pkCustom,
  ## chars = ProgressChars(filled: ..., ...))`.
  let defaultBgStyle =
    case kind
    of pkHash, pkLine, pkArrow:
      defaultStyle()
    of pkCustom:
      defaultStyle()
    of pkBlock:
      style(BrightBlack, Reset)

  let defaultBarStyle =
    case kind
    of pkHash, pkLine, pkArrow:
      style(color)
    of pkCustom, pkBlock:
      style(color, Reset)

  let theme = ProgressColors(
    bar: defaultBarStyle,
    background: defaultBgStyle,
    text: defaultStyle(),
    percentage: style(color, Reset),
  )
  newProgressBar(
    value = value, label = label, kind = kind, style = theme, chars = chars
  )

# Utility functions
proc formatBytes*(bytes: int64): string =
  ## Format bytes as human-readable string (for download progress bars)
  const units = ["B", "KB", "MB", "GB", "TB"]
  var size = float(bytes)
  var unitIndex = 0

  while size >= 1024.0 and unitIndex < units.high:
    size /= 1024.0
    inc unitIndex

  if unitIndex == 0:
    fmt"{int(size)} {units[unitIndex]}"
  else:
    fmt"{size:.2f} {units[unitIndex]}"

proc formatTime*(seconds: float): string =
  ## Format seconds as human-readable time (for ETA display)
  let totalSeconds = int(seconds)
  let hours = totalSeconds div 3600
  let minutes = (totalSeconds mod 3600) div 60
  let secs = totalSeconds mod 60

  if hours > 0:
    fmt"{hours}h {minutes}m {secs}s"
  elif minutes > 0:
    fmt"{minutes}m {secs}s"
  else:
    fmt"{secs}s"

proc downloadProgressBar*(
    current, total: int64, label: string = "Downloading"
): ProgressBar =
  ## Create a progress bar for download tracking
  let value =
    if total > 0:
      float(current) / float(total)
    else:
      0.0
  let sizeText = fmt"{formatBytes(current)} / {formatBytes(total)}"
  newProgressBar(value, fmt"{label}: {sizeText}")

proc taskProgressBar*(completed, total: int, label: string = "Progress"): ProgressBar =
  ## Create a progress bar for task completion tracking
  let value =
    if total > 0:
      float(completed) / float(total)
    else:
      0.0
  let taskText = fmt"{completed}/{total} tasks"
  newProgressBar(value, fmt"{label}: {taskText}")
