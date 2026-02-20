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

import std/[strformat, unicode, math]

import base
import ../core/[geometry, buffer, colors]

type
  ProgressStyle* = enum
    ## Progress bar visual styles
    Block ## Block characters: ███░░░
    Line ## Line characters: ━━━── or [━━━──]
    Arrow ## Arrow style: ══════> or [═════>]
    Hash ## Hash characters: ####-- or [####--]
    Custom ## Custom characters

  ProgressBar* = ref object of Widget ## Progress bar widget
    value: float ## Current progress value (0.0 to 1.0)
    label: string ## Optional label text
    showPercentage: bool ## Show percentage text
    showBar: bool ## Show progress bar visual
    style: ProgressStyle ## Visual style
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

# Progress bar constructors
proc newProgressBar*(
    value: float = 0.0,
    label: string = "",
    showPercentage: bool = true,
    showBar: bool = true,
    style: ProgressStyle = Block,
    barStyle: Style = defaultStyle(), # Will be set based on progress style
    backgroundStyle: Style = style(BrightBlack, Reset),
    textStyle: Style = defaultStyle(),
    percentageStyle: Style = style(Cyan, Reset),
    filledChar: string = "█",
    emptyChar: string = "░",
    fillChar: string = "▒",
    minWidth: int = 10,
    onUpdate: proc(value: float) = nil,
    showBrackets: bool = true, # Default to true for Hash style
): ProgressBar =
  ## Create a new progress bar widget
  # Determine the actual bar style based on the progress style
  let actualBarStyle =
    if barStyle == defaultStyle():
      # Use default behavior based on style
      case style
      of Hash, Line, Arrow:
        style(White)
      # White foreground, no background
      else:
        style(White, Green) # White on Green for Block and Custom
    else:
      # Use explicitly provided bar style
      barStyle

  # Determine the actual background style based on the progress style
  let actualBgStyle =
    if backgroundStyle == style(BrightBlack, Reset):
      # Use default behavior based on style
      case style
      of Hash, Line, Arrow:
        defaultStyle()
      # No background color
      else:
        style(BrightBlack, Reset) # Keep background for Block and Custom
    else:
      # Use explicitly provided background style
      backgroundStyle

  result = ProgressBar(
    value: clamp(value, 0.0, 1.0),
    label: label,
    showPercentage: showPercentage,
    showBar: showBar,
    style: style,
    barStyle: actualBarStyle,
    backgroundStyle: actualBgStyle,
    textStyle: textStyle,
    percentageStyle: percentageStyle,
    filledChar: filledChar,
    emptyChar: emptyChar,
    fillChar: fillChar,
    minWidth: minWidth,
    onUpdate: onUpdate,
    showBrackets: showBrackets,
  )

proc progressBar*(
    value: float = 0.0,
    label: string = "",
    showPercentage: bool = true,
    showBar: bool = true,
    style: ProgressStyle = Block,
): ProgressBar =
  ## Convenience constructor for progress bar with defaults
  newProgressBar(value, label, showPercentage, showBar, style)

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
  ## Get the characters to use for rendering based on style
  case widget.style
  of Block:
    result = ("█", "░", "▒")
  of Line:
    result = ("=", " ", ">") # Empty is now space instead of dash
  of Arrow:
    result = ("═", " ", ">") # Empty is now space instead of ─
  of Hash:
    result = ("#", "-", "=")
  of Custom:
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

  if widget.style == Hash:
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
    if hasPartial and filledWidth < innerWidth and widget.style == Arrow:
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

  if widget.style == Hash:
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
    if hasPartial and filledWidth < width and widget.style == Arrow:
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

  case widget.style
  of Hash, Line, Arrow:
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
      # Draw empty portion
      if widget.backgroundStyle != defaultStyle():
        for i in (filledWidth + 1) ..< width:
          buf.setString(x + i, y, chars.empty, widget.backgroundStyle)
    else:
      # Draw empty portion
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

  # Clear the area first - force reset to clean terminal state
  buf.setString(area.x, area.y, resetSequence(), defaultStyle()) # Explicit reset
  let clearStyle = defaultStyle() # Use plain default style for all progress bar types
  for y in 0 ..< area.height:
    for x in 0 ..< area.width:
      buf.setString(area.x + x, area.y + y, " ", clearStyle)

  let text = widget.getLabelWithPercentage()
  let textLen = text.runeLen

  if widget.showBar:
    if (area.height >= 2 and textLen > 0) or widget.style == Hash:
      # Two-line layout: text above, bar below
      let textY = area.y
      let barY = area.y + 1

      # Render text centered
      let textX = area.x + max(0, (area.width - textLen) div 2)
      if widget.label.len > 0 and widget.showPercentage:
        # Split label and percentage
        let labelLen = widget.label.runeLen
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
        let labelLen = widget.label.runeLen
        let percentText = widget.getPercentageText()
        buf.setString(textX, textY, widget.label, widget.textStyle)
        buf.setString(textX + labelLen + 1, textY, percentText, widget.percentageStyle)
      else:
        buf.setString(textX, textY, text, widget.textStyle)

method getMinSize*(widget: ProgressBar): Size =
  ## Get minimum size for progress bar widget
  let textLen = widget.getLabelWithPercentage().runeLen
  var minBarWidth = max(widget.minWidth, textLen + 2)

  # Hash, Line, Arrow styles need extra space for brackets (if enabled)
  if widget.style in {Hash, Line, Arrow} and widget.showBar and widget.showBrackets:
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

proc `style=`*(widget: ProgressBar, style: ProgressStyle) =
  ## Set the visual style
  widget.style = style

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
  ## Set custom characters for the progress bar
  widget.style = Custom
  widget.filledChar = filled
  widget.emptyChar = empty
  widget.fillChar = partial

proc setColors*(
    widget: ProgressBar,
    barStyle: Style = defaultStyle(),
    backgroundStyle: Style = defaultStyle(),
    textStyle: Style = defaultStyle(),
    percentageStyle: Style = defaultStyle(),
) =
  ## Set multiple colors at once
  if barStyle != defaultStyle():
    widget.barStyle = barStyle
  if backgroundStyle != defaultStyle():
    widget.backgroundStyle = backgroundStyle
  if textStyle != defaultStyle():
    widget.textStyle = textStyle
  if percentageStyle != defaultStyle():
    widget.percentageStyle = percentageStyle

# Builder methods for fluent API (returns self for chaining)
proc withValue*(widget: ProgressBar, value: float): ProgressBar =
  ## Set value and return self for chaining
  widget.setValue(value)
  result = widget

proc withLabel*(widget: ProgressBar, label: string): ProgressBar =
  ## Set label and return self for chaining
  widget.label = label
  result = widget

proc withStyle*(widget: ProgressBar, style: ProgressStyle): ProgressBar =
  ## Set style and return self for chaining
  widget.style = style
  result = widget

proc withColors*(
    widget: ProgressBar,
    barStyle: Style = defaultStyle(),
    backgroundStyle: Style = defaultStyle(),
    textStyle: Style = defaultStyle(),
    percentageStyle: Style = defaultStyle(),
): ProgressBar =
  ## Set colors and return self for chaining
  widget.setColors(barStyle, backgroundStyle, textStyle, percentageStyle)
  result = widget

proc withShowPercentage*(widget: ProgressBar, show: bool): ProgressBar =
  ## Set percentage display and return self for chaining
  widget.showPercentage = show
  result = widget

proc withShowBar*(widget: ProgressBar, show: bool): ProgressBar =
  ## Set bar display and return self for chaining
  widget.showBar = show
  result = widget

proc withShowBrackets*(widget: ProgressBar, show: bool): ProgressBar =
  ## Set brackets display for Hash style and return self for chaining
  widget.showBrackets = show
  result = widget

proc withCustomChars*(
    widget: ProgressBar, filled, empty, partial: string
): ProgressBar =
  ## Set custom characters and return self for chaining
  widget.setCustomChars(filled, empty, partial)
  result = widget

proc withMinWidth*(widget: ProgressBar, minWidth: int): ProgressBar =
  ## Set minimum width and return self for chaining
  widget.minWidth = minWidth
  result = widget

proc withOnUpdate*(widget: ProgressBar, callback: proc(value: float)): ProgressBar =
  ## Set update callback and return self for chaining
  widget.onUpdate = callback
  result = widget

# Convenience constructors for common progress bar types
proc simpleProgressBar*(value: float = 0.0, label: string = ""): ProgressBar =
  ## Create a simple progress bar with default styling
  newProgressBar(value, label)

proc minimalProgressBar*(value: float = 0.0): ProgressBar =
  ## Create a minimal progress bar (no label, just bar and percentage)
  newProgressBar(value, "", true, true)

proc textOnlyProgressBar*(value: float = 0.0, label: string = ""): ProgressBar =
  ## Create a text-only progress indicator (no bar visual)
  newProgressBar(value, label, true, false)

proc indeterminateProgressBar*(label: string = "Loading..."): ProgressBar =
  ## Create an indeterminate progress bar (for unknown duration tasks)
  ## Note: Animation would need to be handled externally by updating the value
  newProgressBar(0.0, label, false, true, Arrow)

proc coloredProgressBar*(
    value: float = 0.0,
    label: string = "",
    color: Color = Green,
    style: ProgressStyle = Block,
): ProgressBar =
  ## Create a progress bar with a specific color theme
  let defaultBgStyle =
    case style
    of Hash, Line, Arrow:
      defaultStyle()
    # No background color
    else:
      style(BrightBlack, Reset) # Keep background for Block and Custom

  let defaultBarStyle =
    case style
    of Hash, Line, Arrow:
      style(color)
    # Color foreground, no background
    else:
      style(color, Reset) # Use the color as foreground for Block and Custom

  newProgressBar(
    value,
    label,
    style = style,
    barStyle = defaultBarStyle,
    backgroundStyle = defaultBgStyle,
    percentageStyle = style(color, Reset),
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
