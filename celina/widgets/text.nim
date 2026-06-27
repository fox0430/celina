## Text widget for Celina CLI library
##
## This module provides text rendering widgets with various alignment
## and styling options.

import std/[strutils, unicode, sequtils]

import base

import ../core/[geometry, buffer, colors]

type
  Alignment* = enum
    ## Text alignment options
    Left
    Center
    Right

  Wrap* = enum
    ## Text wrapping options
    NoWrap # Don't wrap, truncate if necessary
    WordWrap # Wrap at word boundaries
    CharWrap # Wrap at any character

  Text* = ref object of Widget ## Simple text widget
    content*: string
    style*: Style
    alignment*: Alignment
    wrap*: Wrap

# Text widget constructors
proc newText*(
    content: string,
    style: Style = defaultStyle(),
    alignment: Alignment = Left,
    wrap: Wrap = NoWrap,
): Text =
  ## Create a new Text widget
  Text(content: content, style: style, alignment: alignment, wrap: wrap)

proc text*(
    content: string,
    style: Style = defaultStyle(),
    alignment: Alignment = Left,
    wrap: Wrap = NoWrap,
): Text =
  ## Convenience constructor for Text widget
  newText(content, style, alignment, wrap)

# Text processing utilities
proc wrapByWidth(line: string, maxWidth: int): seq[string] =
  ## Break a string into chunks whose display width each fit within
  ## `maxWidth`, splitting at grapheme-cluster boundaries. A cluster wider than
  ## `maxWidth` (e.g. a wide CJK glyph, or a VS16/ZWJ emoji that renders in two
  ## columns, when maxWidth is 1) cannot fit and is dropped, since it can be
  ## neither placed nor split.
  ##
  ## Measuring and splitting by cluster keeps a multi-rune emoji whole and makes
  ## the width agree with `displayWidth`, which the caller uses to decide when a
  ## word needs wrapping at all.
  var chunk = ""
  var w = 0
  for (_, clusterText, cw) in graphemeClusters(line.toRunes):
    if cw > maxWidth:
      # A single wide cluster cannot fit; flush and drop it
      if chunk.len > 0:
        result.add(chunk)
        chunk = ""
        w = 0
      continue
    if w + cw > maxWidth:
      result.add(chunk)
      chunk = clusterText
      w = cw
    else:
      chunk.add(clusterText)
      w += cw
  if chunk.len > 0:
    result.add(chunk)

proc splitIntoLines(text: string, maxWidth: int, wrap: Wrap): seq[string] =
  ## Split text into lines based on wrapping mode
  result = @[]

  case wrap
  of NoWrap:
    # Simple split by newlines, truncate if too long
    for line in text.splitLines():
      if line.displayWidth <= maxWidth:
        result.add(line)
      else:
        result.add(line.truncateToWidth(maxWidth))
  of WordWrap:
    # Split by newlines first, then wrap each line
    for line in text.splitLines():
      if line.displayWidth <= maxWidth:
        result.add(line)
      else:
        # Word wrap this line
        var words = line.split(' ')
        var currentLine = ""

        for word in words:
          let testLine =
            if currentLine.len == 0:
              word
            else:
              currentLine & " " & word
          if testLine.displayWidth <= maxWidth:
            currentLine = testLine
          else:
            # The word does not fit on the current line; flush it first.
            if currentLine.len > 0:
              result.add(currentLine)
              currentLine = ""
            if word.displayWidth <= maxWidth:
              currentLine = word
            else:
              # The word alone is wider than a whole line. Break it across
              # lines instead of dropping the overflow; the trailing chunk
              # stays current so the next word can join it.
              let chunks = wrapByWidth(word, maxWidth)
              for i in 0 ..< max(chunks.len - 1, 0):
                result.add(chunks[i])
              if chunks.len > 0:
                currentLine = chunks[^1]

        if currentLine.len > 0:
          result.add(currentLine)
  of CharWrap:
    # Character-level wrapping by display width
    for line in text.splitLines():
      if line.displayWidth <= maxWidth:
        result.add(line)
      else:
        result.add(wrapByWidth(line, maxWidth))

proc alignLine(line: string, width: int, alignment: Alignment): string =
  ## Align a line within the given width
  let lineWidth = line.displayWidth

  if lineWidth >= width:
    return line

  let padding = width - lineWidth

  case alignment
  of Left:
    line & " ".repeat(padding)
  of Right:
    " ".repeat(padding) & line
  of Center:
    let leftPadding = padding div 2
    let rightPadding = padding - leftPadding
    " ".repeat(leftPadding) & line & " ".repeat(rightPadding)

# Text widget methods
method render*(widget: Text, area: Rect, buf: var Buffer) =
  ## Render the text widget
  if area.isEmpty or widget.content.len == 0:
    return

  let lines = splitIntoLines(widget.content, area.width, widget.wrap)

  for i, line in lines:
    if i >= area.height:
      break # Not enough vertical space

    let alignedLine = alignLine(line, area.width, widget.alignment)
    buf.setString(area.x, area.y + i, alignedLine, widget.style)

method getMinSize*(widget: Text): Size =
  ## Get minimum size for text widget
  if widget.content.len == 0:
    return size(0, 0)

  case widget.wrap
  of NoWrap:
    let lines = widget.content.splitLines()
    let maxWidth = lines.mapIt(it.displayWidth).max()
    size(maxWidth, lines.len)
  of WordWrap, CharWrap:
    # Minimum width is the longest word (for word wrap) or 1 (for char wrap)
    let lines = widget.content.splitLines()
    var minWidth = 1

    if widget.wrap == WordWrap:
      for line in lines:
        for word in line.split(' '):
          minWidth = max(minWidth, word.displayWidth)

    size(minWidth, lines.len)

method getPreferredSize*(widget: Text, available: Size): Size =
  ## Get preferred size for text widget
  if widget.content.len == 0:
    return size(0, 0)

  case widget.wrap
  of NoWrap:
    # Use natural size, but constrain to available space
    let minSize = widget.getMinSize()
    size(min(minSize.width, available.width), min(minSize.height, available.height))
  of WordWrap, CharWrap:
    # Use available width, calculate required height
    let lines = splitIntoLines(widget.content, available.width, widget.wrap)
    size(available.width, min(lines.len, available.height))

# Text widget builders and modifiers
proc withStyle*(widget: Text, style: Style): Text =
  ## Create a copy with different style
  result = copyWidget(widget)
  result.style = style

proc withAlignment*(widget: Text, alignment: Alignment): Text =
  ## Create a copy with different alignment
  result = copyWidget(widget)
  result.alignment = alignment

proc withWrap*(widget: Text, wrap: Wrap): Text =
  ## Create a copy with different wrap mode
  result = copyWidget(widget)
  result.wrap = wrap

# Convenience constructors for common styles
proc boldText*(content: string, alignment: Alignment = Left): Text =
  ## Create bold text
  newText(content, bold(), alignment)

proc colorText*(content: string, color: Color, alignment: Alignment = Left): Text =
  ## Create colored text
  newText(content, style(color), alignment)

proc styledText*(
    content: string,
    fg: Color,
    bg: Color = Reset,
    modifiers: set[StyleModifier] = {},
    alignment: Alignment = Left,
): Text =
  ## Create text with full styling
  newText(content, style(fg, bg, modifiers), alignment)
