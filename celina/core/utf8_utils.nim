## UTF-8 Processing Utilities
##
## This module contains pure business logic for UTF-8 character processing,
## shared between synchronous and asynchronous implementations.
##
## No I/O operations are performed here - only data validation and parsing.

import std/options

const Utf8ReplacementChar* = "\xEF\xBF\xBD"
  ## UTF-8 encoding of U+FFFD REPLACEMENT CHARACTER (3 bytes: EF BF BD).
  ##
  ## I/O layers substitute this for truncated or ill-formed UTF-8 sequences
  ## so that downstream consumers can rely on every emitted string being
  ## valid UTF-8 (see KeyEvent.char invariant).

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
  ## assert utf8ByteLength(0xC0) == 0  # Invalid (always overlong)
  ## assert utf8ByteLength(0xFF) == 0  # Invalid
  ## ```
  if (firstByte and 0x80) == 0:
    return 1 # ASCII: 0xxxxxxx
  elif (firstByte and 0xE0) == 0xC0:
    # 110xxxxx, but 0xC0/0xC1 can only ever lead an overlong encoding of an
    # ASCII code point (U+0000..U+007F), so they are never a valid start byte.
    if firstByte >= 0xC2:
      return 2
    else:
      return 0 # 0xC0/0xC1: always overlong
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

proc isUtf8ContinuationByte*(b: byte): bool =
  ## Check if a byte is a valid UTF-8 continuation byte (10xxxxxx)
  ##
  ## Example:
  ## ```nim
  ## assert isUtf8ContinuationByte(0x80)  # true
  ## assert isUtf8ContinuationByte(0xBF)  # true
  ## assert not isUtf8ContinuationByte(0xC0)  # false
  ## ```
  (b and 0xC0) == 0x80

proc utf8SecondByteRange*(firstByte: byte): tuple[lo: byte, hi: byte] =
  ## Valid inclusive range for the *second* byte of a multi-byte sequence,
  ## given its lead byte (Unicode Standard Table 3-7).
  ##
  ## A plain `10xxxxxx` continuation check (`isUtf8ContinuationByte`) accepts
  ## the full 0x80..0xBF range, which lets overlong encodings and UTF-16
  ## surrogates through. The narrowed ranges below are exactly what reject
  ## them; every continuation byte *after* the second uses the full range.
  ##
  ## Example:
  ## ```nim
  ## assert utf8SecondByteRange(0xE0) == (0xA0.byte, 0xBF.byte)
  ## assert utf8SecondByteRange(0xC3) == (0x80.byte, 0xBF.byte)
  ## ```
  case firstByte
  of 0xE0:
    (0xA0.byte, 0xBF.byte)
  # exclude overlong U+0000..U+07FF
  of 0xED:
    (0x80.byte, 0x9F.byte)
  # exclude surrogates U+D800..U+DFFF
  of 0xF0:
    (0x90.byte, 0xBF.byte)
  # exclude overlong U+0000..U+FFFF
  of 0xF4:
    (0x80.byte, 0x8F.byte)
  # exclude code points > U+10FFFF
  else:
    (0x80.byte, 0xBF.byte)

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

  # Validate continuation bytes. The second byte (index 1) additionally has to
  # fall inside the lead-byte-specific range that rejects overlong encodings
  # and UTF-16 surrogates; later bytes use the full 0x80..0xBF range.
  let (secondLo, secondHi) = utf8SecondByteRange(bytes[0])
  for i in 1 ..< expectedLen:
    if i >= bytes.len or not isUtf8ContinuationByte(bytes[i]):
      return Utf8ValidationResult(
        isValid: false,
        expectedBytes: expectedLen,
        errorMessage: "Invalid UTF-8 continuation byte",
      )
    if i == 1 and (bytes[1] < secondLo or bytes[1] > secondHi):
      return Utf8ValidationResult(
        isValid: false,
        expectedBytes: expectedLen,
        errorMessage: "Overlong or surrogate encoding",
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

type
  Utf8ByteSource* = proc(): tuple[ok: bool, b: byte] {.closure.}
    ## Continuation-byte supplier for `assembleUtf8Char`. Returns `(true, b)` on
    ## success and `(false, _)` on EOF / read error / EAGAIN / any condition
    ## that should be treated as a truncated UTF-8 sequence.

  Utf8AssemblyResult* = object
    ## Outcome of `assembleUtf8Char`. `leftover` carries a byte that was read
    ## but rejected as an invalid continuation, so the caller can re-inject it
    ## as the first byte of the next sequence — preserving the resync byte per
    ## Unicode Standard §3.9 best practice. `leftover.isSome` only when an
    ## invalid continuation byte was encountered; truncation does not produce
    ## a leftover because the source already reported EOF/EAGAIN.
    text*: string
    leftover*: Option[byte]

proc assembleUtf8Char*(firstByte: byte, next: Utf8ByteSource): Utf8AssemblyResult =
  ## Assemble one complete UTF-8 character from a first byte and a callback
  ## that supplies continuation bytes. Pure logic — no I/O — so this can be
  ## driven by stdin readers, fixed-byte test fixtures, or any other source.
  ##
  ## Returns a `Utf8AssemblyResult` with:
  ## - `text` = a single valid UTF-8 codepoint (1-4 bytes) on the happy path
  ## - `text` = `Utf8ReplacementChar` (U+FFFD) on truncation (`next()` reported
  ##   failure mid-sequence) or invalid continuation byte
  ## - `text` = "" only when `firstByte` itself is not a valid UTF-8 start
  ##   byte; the caller is expected to substitute U+FFFD
  ## - `leftover` = `some(b)` only when an invalid continuation byte was read;
  ##   the caller should treat `b` as the start byte of the next sequence.
  ##   `none` on the happy path, on truncation, and on invalid start byte.
  ##
  ## Per Unicode Standard §3.9 (U+FFFD Substitution of Maximal Subparts) we
  ## emit exactly one U+FFFD per ill-formed maximal subpart, and the byte
  ## immediately following the subpart is treated as the start of the next
  ## sequence (returned via `leftover`).
  let byteLen = utf8ByteLength(firstByte)
  if byteLen == 0:
    return Utf8AssemblyResult(text: "", leftover: none(byte))

  if byteLen == 1:
    return Utf8AssemblyResult(text: $char(firstByte), leftover: none(byte))

  var continuationBytes: seq[byte] = @[]
  let (secondLo, secondHi) = utf8SecondByteRange(firstByte)
  for i in 1 ..< byteLen:
    let r = next()
    if not r.ok:
      # Truncated: source already reports EOF/EAGAIN, nothing to push back.
      return Utf8AssemblyResult(text: Utf8ReplacementChar, leftover: none(byte))
    # The second byte must also stay inside the lead-byte-specific range so
    # overlong encodings and surrogates are rejected, not just non-continuation
    # bytes. An out-of-range second byte is the maximal subpart's end, so it is
    # surfaced as `leftover` for re-injection exactly like an invalid one.
    if not isUtf8ContinuationByte(r.b) or (
      i == 1 and (r.b < secondLo or r.b > secondHi)
    ):
      # Invalid continuation: surface the offending byte so the caller can
      # process it as the next sequence's first byte.
      return Utf8AssemblyResult(text: Utf8ReplacementChar, leftover: some(r.b))
    continuationBytes.add(r.b)

  return Utf8AssemblyResult(
    text: buildUtf8String(firstByte, continuationBytes), leftover: none(byte)
  )

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
