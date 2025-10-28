## Tests for utf8_utils module
##
## This test suite verifies that the shared UTF-8 processing utilities
## work correctly for both sync and async implementations.

import unittest
import ../celina/core/utf8_utils

suite "UTF-8 Byte Length Detection":
  test "ASCII character (1 byte)":
    check utf8ByteLength(0x41) == 1 # 'A'
    check utf8ByteLength(0x7F) == 1 # DEL
    check utf8ByteLength(0x00) == 1 # NUL

  test "2-byte UTF-8 character":
    check utf8ByteLength(0xC2) == 2 # Start of 2-byte sequence
    check utf8ByteLength(0xDF) == 2 # End of 2-byte range

  test "3-byte UTF-8 character":
    check utf8ByteLength(0xE0) == 3 # Start of 3-byte sequence
    check utf8ByteLength(0xEF) == 3 # End of 3-byte range

  test "4-byte UTF-8 character":
    check utf8ByteLength(0xF0) == 4 # Start of 4-byte sequence
    check utf8ByteLength(0xF4) == 4 # End of valid 4-byte range

  test "Invalid UTF-8 start bytes":
    check utf8ByteLength(0x80) == 0 # Continuation byte
    # Note: 0xC0 and 0xC1 are technically invalid but detected as 2-byte for compatibility
    check utf8ByteLength(0xF5) == 0 # Beyond valid 4-byte range
    check utf8ByteLength(0xFF) == 0 # Invalid

suite "UTF-8 Continuation Byte Validation":
  test "Valid continuation bytes":
    check isUtf8ContinuationByte(0x80)
    check isUtf8ContinuationByte(0x9F)
    check isUtf8ContinuationByte(0xBF)

  test "Invalid continuation bytes":
    check not isUtf8ContinuationByte(0x00) # ASCII
    check not isUtf8ContinuationByte(0x7F) # ASCII
    check not isUtf8ContinuationByte(0xC0) # Start byte
    check not isUtf8ContinuationByte(0xFF) # Invalid

suite "UTF-8 Sequence Validation":
  test "Valid ASCII sequence":
    let bytes = [byte(0x41)] # 'A'
    let result = validateUtf8Sequence(bytes)
    check result.isValid
    check result.expectedBytes == 1

  test "Valid 2-byte sequence":
    let bytes = [byte(0xC3), byte(0xA9)] # 'é'
    let result = validateUtf8Sequence(bytes)
    check result.isValid
    check result.expectedBytes == 2

  test "Valid 3-byte sequence":
    let bytes = [byte(0xE3), byte(0x81), byte(0x82)] # 'あ'
    let result = validateUtf8Sequence(bytes)
    check result.isValid
    check result.expectedBytes == 3

  test "Valid 4-byte sequence":
    let bytes = [byte(0xF0), byte(0x9F), byte(0x98), byte(0x80)] # 😀
    let result = validateUtf8Sequence(bytes)
    check result.isValid
    check result.expectedBytes == 4

  test "Invalid start byte":
    let bytes = [byte(0xFF), byte(0x80)]
    let result = validateUtf8Sequence(bytes)
    check not result.isValid
    check result.errorMessage == "Invalid UTF-8 start byte"

  test "Incomplete sequence":
    let bytes = [byte(0xC3)] # Missing continuation byte
    let result = validateUtf8Sequence(bytes)
    check not result.isValid
    check result.errorMessage == "Incomplete UTF-8 sequence"

  test "Invalid continuation byte":
    let bytes = [byte(0xC3), byte(0x41)] # Second byte should be 10xxxxxx
    let result = validateUtf8Sequence(bytes)
    check not result.isValid
    check result.errorMessage == "Invalid UTF-8 continuation byte"

  test "Empty sequence":
    let bytes: seq[byte] = @[]
    let result = validateUtf8Sequence(bytes)
    check not result.isValid
    check result.errorMessage == "Empty byte sequence"

suite "UTF-8 String Building":
  test "Build ASCII character":
    let s = buildUtf8String(0x41, [])
    check s == "A"

  test "Build 2-byte character":
    let s = buildUtf8String(0xC3, [byte(0xA9)])
    check s == "é"

  test "Build 3-byte character":
    let s = buildUtf8String(0xE3, [byte(0x81), byte(0x82)])
    check s == "あ"

  test "Build 4-byte character":
    let s = buildUtf8String(0xF0, [byte(0x9F), byte(0x98), byte(0x80)])
    check s == "😀"

suite "UTF-8 Character Length Counting":
  test "Count ASCII string":
    check utf8CharLength("hello") == 5

  test "Count mixed ASCII and multi-byte":
    check utf8CharLength("hello世界") == 7 # 5 + 2

  test "Count Japanese characters":
    check utf8CharLength("こんにちは") == 5

  test "Count emoji":
    check utf8CharLength("😀😁😂") == 3

  test "Empty string":
    check utf8CharLength("") == 0

  test "String with invalid UTF-8":
    # Invalid bytes are counted as 1 character each
    let s = "hello" & $char(0xFF) & "world"
    check utf8CharLength(s) == 11 # 5 + 1 + 5

suite "UTF-8 String Truncation":
  test "Truncate ASCII string":
    check truncateUtf8("hello", 3) == "hel"
    check truncateUtf8("hello", 10) == "hello"

  test "Truncate at character boundary":
    # "こん" = 6 bytes (3 bytes each)
    check truncateUtf8("こんにちは", 6) == "こん"

  test "Truncate before character boundary":
    # Requesting 7 bytes but "こんに" = 9 bytes
    # Should truncate to "こん" (6 bytes)
    check truncateUtf8("こんにちは", 7) == "こん"

  test "Truncate emoji":
    # Each emoji is 4 bytes
    check truncateUtf8("😀😁😂", 4) == "😀"
    check truncateUtf8("😀😁😂", 8) == "😀😁"

  test "Truncate mixed content":
    let s = "AB世界CD" # AB(2) + 世(3) + 界(3) + CD(2) = 10 bytes
    check truncateUtf8(s, 5) == "AB世" # 2 + 3 = 5 bytes
    check truncateUtf8(s, 6) == "AB世" # Can't fit 界
    check truncateUtf8(s, 8) == "AB世界" # 2 + 3 + 3 = 8 bytes

  test "Empty string truncation":
    check truncateUtf8("", 10) == ""

  test "Exact length match":
    check truncateUtf8("hello", 5) == "hello"
