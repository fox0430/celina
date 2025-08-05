## Unicode utilities for text editing
##
## This module provides utilities for handling Unicode text properly
## in the editor, including cursor positioning and character operations.

import std/[unicode, strutils]
import types

proc byteToCharPos*(text: string, bytePos: int): int =
  ## Convert byte position to character position (Unicode-aware)
  var charPos = 0
  var currentByte = 0
  
  for rune in text.runes:
    if currentByte >= bytePos:
      break
    currentByte += rune.size
    charPos += 1
  
  charPos

proc charToBytePos*(text: string, charPos: int): int =
  ## Convert character position to byte position (Unicode-aware)
  var currentChar = 0
  var bytePos = 0
  
  for rune in text.runes:
    if currentChar >= charPos:
      break
    bytePos += rune.size
    currentChar += 1
  
  bytePos

proc getCharAtPos*(text: string, charPos: int): (Rune, int) =
  ## Get the Unicode character at the given character position
  ## Returns (rune, byte_size)
  var currentChar = 0
  var bytePos = 0
  
  for rune in text.runes:
    if currentChar == charPos:
      return (rune, rune.size)
    bytePos += rune.size
    currentChar += 1
  
  # Return null rune if position is out of bounds
  (Rune(0), 0)

proc deleteCharAt*(text: string, charPos: int): string =
  ## Delete a Unicode character at the given character position
  let bytePos = charToBytePos(text, charPos)
  if bytePos >= text.len:
    return text
  
  let (rune, size) = getCharAtPos(text, charPos)
  if size == 0:
    return text
  
  text[0..<bytePos] & text[bytePos + size..^1]

proc insertCharAt*(text: string, charPos: int, newText: string): string =
  ## Insert text at the given character position
  let bytePos = charToBytePos(text, charPos)
  if bytePos >= text.len:
    text & newText
  else:
    text[0..<bytePos] & newText & text[bytePos..^1]

proc nextCharPos*(text: string, charPos: int): int =
  ## Get the next character position (handles Unicode)
  if charPos >= text.runeLen:
    return charPos
  charPos + 1

proc prevCharPos*(text: string, charPos: int): int =
  ## Get the previous character position (handles Unicode)
  if charPos <= 0:
    return 0
  charPos - 1

proc charLen*(text: string): int =
  ## Get character length (not byte length)
  text.runeLen

proc isCharBoundary*(text: string, bytePos: int): bool =
  ## Check if the byte position is at a character boundary
  if bytePos <= 0 or bytePos >= text.len:
    return true
  
  # In UTF-8, character boundaries are where the byte is either:
  # - ASCII (0x00-0x7F)
  # - Start of multi-byte sequence (0xC0-0xFD)
  let b = text[bytePos].ord
  b < 0x80 or (b >= 0xC0 and b <= 0xFD)

proc findCharBoundary*(text: string, bytePos: int, direction: int = 1): int =
  ## Find the nearest character boundary
  ## direction: 1 for forward, -1 for backward
  var pos = bytePos
  
  if direction > 0:
    while pos < text.len and not text.isCharBoundary(pos):
      pos += 1
  else:
    while pos > 0 and not text.isCharBoundary(pos):
      pos -= 1
  
  pos