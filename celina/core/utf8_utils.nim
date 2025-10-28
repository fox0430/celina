## UTF-8 Processing Utilities
##
## This module contains pure business logic for UTF-8 character processing,
## shared between synchronous and asynchronous implementations.
##
## No I/O operations are performed here - only data validation and parsing.

type Utf8ValidationResult* = object ## Result of UTF-8 validation
  isValid*: bool
  expectedBytes*: int
  errorMessage*: string

proc utf8ByteLength*(firstByte: byte): int =
  ## Determine the number of bytes in a UTF-8 character from its first byte
  ## Returns 1 for ASCII, 2-4 for multi-byte characters, 0 for invalid
  ##
  ## Example:
  ## ```nim
  ## assert utf8ByteLength(0x41) == 1  # 'A' (ASCII)
  ## assert utf8ByteLength(0xC3) == 2  # Start of 2-byte UTF-8
  ## assert utf8ByteLength(0xE0) == 3  # Start of 3-byte UTF-8
  ## assert utf8ByteLength(0xF0) == 4  # Start of 4-byte UTF-8
  ## assert utf8ByteLength(0xFF) == 0  # Invalid
  ## ```
  if (firstByte and 0x80) == 0:
    return 1 # ASCII: 0xxxxxxx
  elif (firstByte and 0xE0) == 0xC0:
    return 2 # 110xxxxx
  elif (firstByte and 0xF0) == 0xE0:
    return 3 # 1110xxxx
  elif (firstByte and 0xF8) == 0xF0:
    # Valid 4-byte UTF-8 is 0xF0-0xF4 (U+10000 to U+10FFFF)
    if firstByte >= 0xF0 and firstByte <= 0xF4:
      return 4 # 11110xxx
    else:
      return 0 # Invalid (> 0xF4 or pattern mismatch)
  else:
    return 0 # Invalid UTF-8 start byte

proc isUtf8ContinuationByte*(b: byte): bool {.inline.} =
  ## Check if a byte is a valid UTF-8 continuation byte (10xxxxxx)
  ##
  ## Example:
  ## ```nim
  ## assert isUtf8ContinuationByte(0x80)  # true
  ## assert isUtf8ContinuationByte(0xBF)  # true
  ## assert not isUtf8ContinuationByte(0xC0)  # false
  ## ```
  (b and 0xC0) == 0x80

proc validateUtf8Sequence*(bytes: openArray[byte]): Utf8ValidationResult =
  ## Validate a UTF-8 byte sequence
  ##
  ## Returns validation result with detailed error information
  if bytes.len == 0:
    return Utf8ValidationResult(
      isValid: false, expectedBytes: 0, errorMessage: "Empty byte sequence"
    )

  let expectedLen = utf8ByteLength(bytes[0])
  if expectedLen == 0:
    return Utf8ValidationResult(
      isValid: false, expectedBytes: 0, errorMessage: "Invalid UTF-8 start byte"
    )

  if bytes.len < expectedLen:
    return Utf8ValidationResult(
      isValid: false,
      expectedBytes: expectedLen,
      errorMessage: "Incomplete UTF-8 sequence",
    )

  # Validate continuation bytes
  for i in 1 ..< expectedLen:
    if i >= bytes.len or not isUtf8ContinuationByte(bytes[i]):
      return Utf8ValidationResult(
        isValid: false,
        expectedBytes: expectedLen,
        errorMessage: "Invalid UTF-8 continuation byte",
      )

  return
    Utf8ValidationResult(isValid: true, expectedBytes: expectedLen, errorMessage: "")

proc buildUtf8String*(firstByte: byte, continuationBytes: openArray[byte]): string =
  ## Build a UTF-8 string from first byte and continuation bytes
  ##
  ## This is a pure function that doesn't perform I/O - it just constructs
  ## the string from the provided bytes.
  ##
  ## Example:
  ## ```nim
  ## let s = buildUtf8String(0xC3.byte, [0xA9.byte])  # é
  ## assert s == "é"
  ## ```
  let totalLen = 1 + continuationBytes.len
  result = newString(totalLen)
  result[0] = char(firstByte)

  for i in 0 ..< continuationBytes.len:
    result[i + 1] = char(continuationBytes[i])

proc utf8CharLength*(s: string): int =
  ## Get the number of UTF-8 characters in a string (not bytes)
  ##
  ## Example:
  ## ```nim
  ## assert utf8CharLength("hello") == 5
  ## assert utf8CharLength("こんにちは") == 5  # 5 characters, 15 bytes
  ## ```
  result = 0
  var i = 0
  while i < s.len:
    let byteLen = utf8ByteLength(s[i].byte)
    if byteLen == 0:
      # Invalid UTF-8, count as 1 character
      i += 1
    else:
      i += byteLen
    result += 1

proc truncateUtf8*(s: string, maxBytes: int): string =
  ## Truncate a UTF-8 string to at most maxBytes, ensuring valid UTF-8
  ##
  ## This will not split multi-byte characters - it truncates at character
  ## boundaries.
  ##
  ## Example:
  ## ```nim
  ## assert truncateUtf8("hello", 3) == "hel"
  ## assert truncateUtf8("こんにちは", 7) == "こん"  # 6 bytes (2 chars)
  ## ```
  if s.len <= maxBytes:
    return s

  result = ""
  var byteCount = 0
  var i = 0

  while i < s.len:
    let byteLen = utf8ByteLength(s[i].byte)
    if byteLen == 0:
      # Invalid UTF-8, skip
      i += 1
      continue

    if byteCount + byteLen > maxBytes:
      # Would exceed max, stop here
      break

    # Add this character
    for j in 0 ..< byteLen:
      if i + j < s.len:
        result.add(s[i + j])

    byteCount += byteLen
    i += byteLen
