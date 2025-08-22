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
proc splitIntoLines(text: string, maxWidth: int, wrap: Wrap): seq[string] =
  ## Split text into lines based on wrapping mode
  result = @[]

  case wrap
  of NoWrap:
    # Simple split by newlines, truncate if too long
    for line in text.splitLines():
      if line.runeLen <= maxWidth:
        result.add(line)
      else:
        result.add(line.runeSubStr(0, maxWidth))
  of WordWrap:
    # Split by newlines first, then wrap each line
    for line in text.splitLines():
      if line.runeLen <= maxWidth:
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
          if testLine.runeLen <= maxWidth:
            currentLine = testLine
          else:
            if currentLine.len > 0:
              result.add(currentLine)
              currentLine = word
            else:
              # Single word is too long, force break
              result.add(word.runeSubStr(0, maxWidth))

        if currentLine.len > 0:
          result.add(currentLine)
  of CharWrap:
    # Character-level wrapping
    for line in text.splitLines():
      var pos = 0
      while pos < line.runeLen:
        let endPos = min(pos + maxWidth, line.runeLen)
        result.add(line.runeSubStr(pos, endPos - pos))
        pos = endPos

proc alignLine(line: string, width: int, alignment: Alignment): string =
  ## Align a line within the given width
  let lineWidth = line.runeLen

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
    let maxWidth = lines.mapIt(it.runeLen).max()
    size(maxWidth, lines.len)
  of WordWrap, CharWrap:
    # Minimum width is the longest word (for word wrap) or 1 (for char wrap)
    let lines = widget.content.splitLines()
    var minWidth = 1

    if widget.wrap == WordWrap:
      for line in lines:
        for word in line.split(' '):
          minWidth = max(minWidth, word.runeLen)

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
  Text(
    content: widget.content,
    style: style,
    alignment: widget.alignment,
    wrap: widget.wrap,
  )

proc withAlignment*(widget: Text, alignment: Alignment): Text =
  ## Create a copy with different alignment
  Text(
    content: widget.content,
    style: widget.style,
    alignment: alignment,
    wrap: widget.wrap,
  )

proc withWrap*(widget: Text, wrap: Wrap): Text =
  ## Create a copy with different wrap mode
  Text(
    content: widget.content,
    style: widget.style,
    alignment: widget.alignment,
    wrap: wrap,
  )

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
