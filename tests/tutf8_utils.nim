## Tests for utf8_utils module
##
## This test suite verifies that the shared UTF-8 processing utilities
## work correctly for both sync and async implementations.

import std/options
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
    # 0xC0 and 0xC1 can only ever lead an overlong ASCII encoding, so they are
    # rejected as start bytes rather than reported as 2-byte leads.
    check utf8ByteLength(0xC0) == 0
    check utf8ByteLength(0xC1) == 0
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

  test "Overlong 2-byte encoding (C0 80) is rejected at the start byte":
    # 0xC0/0xC1 can only encode an ASCII code point overlong, so they fail as
    # invalid start bytes before continuation validation even begins.
    for lead in [byte(0xC0), byte(0xC1)]:
      let result = validateUtf8Sequence([lead, byte(0x80)])
      check not result.isValid
      check result.errorMessage == "Invalid UTF-8 start byte"

  test "Overlong 3-byte encoding (E0 80 80) is rejected":
    # E0 requires a second byte in A0..BF; 0x80 would encode U+0000..U+07FF.
    let result = validateUtf8Sequence([byte(0xE0), byte(0x80), byte(0x80)])
    check not result.isValid
    check result.errorMessage == "Overlong or surrogate encoding"

  test "UTF-16 surrogate (ED A0 80) is rejected":
    # ED requires a second byte in 80..9F; 0xA0 lands in U+D800..U+DFFF.
    let result = validateUtf8Sequence([byte(0xED), byte(0xA0), byte(0x80)])
    check not result.isValid
    check result.errorMessage == "Overlong or surrogate encoding"

  test "Valid boundary 3-byte sequences around the surrogate gap":
    # ED 9F BF = U+D7FF (last before the gap) and EE 80 80 = U+E000 (first
    # after) must both stay valid.
    check validateUtf8Sequence([byte(0xED), byte(0x9F), byte(0xBF)]).isValid
    check validateUtf8Sequence([byte(0xEE), byte(0x80), byte(0x80)]).isValid

  test "Overlong 4-byte encoding (F0 80 80 80) is rejected":
    # F0 requires a second byte in 90..BF; 0x80 would encode below U+10000.
    let result = validateUtf8Sequence([byte(0xF0), byte(0x80), byte(0x80), byte(0x80)])
    check not result.isValid
    check result.errorMessage == "Overlong or surrogate encoding"

  test "4-byte code point beyond U+10FFFF (F4 90 80 80) is rejected":
    # F4 requires a second byte in 80..8F; 0x90 would encode > U+10FFFF.
    let result = validateUtf8Sequence([byte(0xF4), byte(0x90), byte(0x80), byte(0x80)])
    check not result.isValid
    check result.errorMessage == "Overlong or surrogate encoding"

  test "Valid maximum code point (F4 8F BF BF = U+10FFFF) stays valid":
    check validateUtf8Sequence([byte(0xF4), byte(0x8F), byte(0xBF), byte(0xBF)]).isValid

suite "UTF-8 Second Byte Range (Table 3-7)":
  test "Narrowed ranges for E0/ED/F0/F4":
    check utf8SecondByteRange(0xE0) == (0xA0.byte, 0xBF.byte)
    check utf8SecondByteRange(0xED) == (0x80.byte, 0x9F.byte)
    check utf8SecondByteRange(0xF0) == (0x90.byte, 0xBF.byte)
    check utf8SecondByteRange(0xF4) == (0x80.byte, 0x8F.byte)

  test "Unrestricted lead bytes use the full continuation range":
    check utf8SecondByteRange(0xC3) == (0x80.byte, 0xBF.byte)
    check utf8SecondByteRange(0xE3) == (0x80.byte, 0xBF.byte)
    check utf8SecondByteRange(0xF1) == (0x80.byte, 0xBF.byte)

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

suite "UTF-8 Replacement Character":
  test "Utf8ReplacementChar is exactly U+FFFD (EF BF BD)":
    # Guards against accidental rewrites that would emit a different byte
    # sequence for ill-formed input. KeyEvent.char invariant relies on this.
    check Utf8ReplacementChar.len == 3
    check Utf8ReplacementChar[0].byte == 0xEF
    check Utf8ReplacementChar[1].byte == 0xBF
    check Utf8ReplacementChar[2].byte == 0xBD

  test "Utf8ReplacementChar passes UTF-8 validation":
    # The replacement we emit must itself be valid UTF-8 — otherwise we
    # would just be swapping one invalid sequence for another.
    let bytes = [
      Utf8ReplacementChar[0].byte,
      Utf8ReplacementChar[1].byte,
      Utf8ReplacementChar[2].byte,
    ]
    let v = validateUtf8Sequence(bytes)
    check v.isValid
    check v.expectedBytes == 3

  test "Utf8ReplacementChar counts as one UTF-8 character":
    check utf8CharLength(Utf8ReplacementChar) == 1

suite "assembleUtf8Char (U+FFFD substitution)":
  # Tests the pure assembly logic used by the blocking and non-blocking stdin
  # readers in core/events. Drives `assembleUtf8Char` with a scripted byte
  # source so we can exercise every truncation / invalid-continuation branch
  # without touching real stdin.

  proc fixedSource(bytes: openArray[byte]): Utf8ByteSource =
    ## Build a byte source that yields the given bytes in order and reports
    ## ok=false once the script is exhausted (simulating EOF / EAGAIN).
    let buf = @bytes
    var idx = 0
    return proc(): tuple[ok: bool, b: byte] =
      if idx < buf.len:
        let b = buf[idx]
        idx.inc
        return (true, b)
      return (false, 0.byte)

  test "ASCII first byte returns the byte verbatim (no source calls)":
    var called = 0
    proc src(): tuple[ok: bool, b: byte] =
      called.inc
      return (false, 0.byte)

    let r = assembleUtf8Char(0x41.byte, src)
    check r.text == "A"
    check r.leftover.isNone
    check called == 0

  test "Valid 2-byte sequence (é)":
    let r = assembleUtf8Char(0xC3.byte, fixedSource([byte(0xA9)]))
    check r.text == "é"
    check r.text.len == 2
    check r.leftover.isNone

  test "Valid 3-byte sequence (あ)":
    let r = assembleUtf8Char(0xE3.byte, fixedSource([byte(0x81), byte(0x82)]))
    check r.text == "あ"
    check r.text.len == 3
    check r.leftover.isNone

  test "Valid 4-byte sequence (😀)":
    let r =
      assembleUtf8Char(0xF0.byte, fixedSource([byte(0x9F), byte(0x98), byte(0x80)]))
    check r.text == "😀"
    check r.text.len == 4
    check r.leftover.isNone

  test "Invalid start byte returns empty (caller substitutes U+FFFD)":
    # The first byte itself was already consumed by the time we are called,
    # so there is no leftover regardless of how the start byte is rejected.
    let r1 = assembleUtf8Char(0xFF.byte, fixedSource([]))
    check r1.text == ""
    check r1.leftover.isNone
    # Bare continuation bytes (0x80-0xBF) are also rejected as start bytes.
    check assembleUtf8Char(0x80.byte, fixedSource([])).text == ""
    check assembleUtf8Char(0xBF.byte, fixedSource([])).text == ""

  test "Truncated 2-byte sequence yields U+FFFD and no leftover":
    # 0xC3 expects one continuation byte; source reports EOF immediately.
    # No leftover: the source already signalled there are no more bytes.
    let r = assembleUtf8Char(0xC3.byte, fixedSource([]))
    check r.text == Utf8ReplacementChar
    check r.leftover.isNone

  test "Truncated 3-byte sequence yields U+FFFD and no leftover":
    let r = assembleUtf8Char(0xE3.byte, fixedSource([byte(0x81)]))
    check r.text == Utf8ReplacementChar
    check r.leftover.isNone

  test "Truncated 4-byte sequence yields U+FFFD and no leftover":
    let r = assembleUtf8Char(0xF0.byte, fixedSource([byte(0x9F)]))
    check r.text == Utf8ReplacementChar
    check r.leftover.isNone

  test "Invalid continuation byte yields U+FFFD AND surfaces leftover":
    # 0x41 ('A') is not a valid continuation byte (not 10xxxxxx). It must be
    # returned via `leftover` so the caller can re-inject it as the next
    # sequence's first byte (Unicode §3.9 best practice).
    let r = assembleUtf8Char(0xC3.byte, fixedSource([byte(0x41)]))
    check r.text == Utf8ReplacementChar
    check r.leftover.isSome
    check r.leftover.get == 0x41.byte

  test "Invalid continuation byte at later position surfaces leftover":
    # First continuation valid, second invalid: leftover is the second byte.
    let r = assembleUtf8Char(0xE3.byte, fixedSource([byte(0x81), byte(0x41)]))
    check r.text == Utf8ReplacementChar
    check r.leftover.isSome
    check r.leftover.get == 0x41.byte

  test "Invalid continuation = next valid start byte (resync case)":
    # 0xC3 expects a continuation, but the next byte is 0xE3 — the start of
    # a 3-byte sequence. Without leftover this byte would be lost; with
    # leftover the caller can recover it as the start of the next event.
    let r = assembleUtf8Char(0xC3.byte, fixedSource([byte(0xE3)]))
    check r.text == Utf8ReplacementChar
    check r.leftover.isSome
    check r.leftover.get == 0xE3.byte

  test "Invalid continuation = ESC preserves the keypress":
    # The motivating pathology: 0xC3 followed by ESC. Before this change ESC
    # was silently dropped; now it must be available for the next event.
    let r = assembleUtf8Char(0xC3.byte, fixedSource([byte(0x1B)]))
    check r.text == Utf8ReplacementChar
    check r.leftover.isSome
    check r.leftover.get == 0x1B.byte

  test "Overlong 3-byte second byte yields U+FFFD AND surfaces leftover":
    # E0 80 ...: 0x80 is a valid continuation pattern but out of E0's A0..BF
    # range, so the maximal subpart ends at E0 and 0x80 must be re-injected.
    let r = assembleUtf8Char(0xE0.byte, fixedSource([byte(0x80), byte(0x80)]))
    check r.text == Utf8ReplacementChar
    check r.leftover.isSome
    check r.leftover.get == 0x80.byte

  test "UTF-16 surrogate second byte yields U+FFFD AND surfaces leftover":
    # ED A0 ...: 0xA0 falls in the surrogate range (out of ED's 80..9F).
    let r = assembleUtf8Char(0xED.byte, fixedSource([byte(0xA0), byte(0x80)]))
    check r.text == Utf8ReplacementChar
    check r.leftover.isSome
    check r.leftover.get == 0xA0.byte

  test "Overlong 4-byte second byte yields U+FFFD AND surfaces leftover":
    let r =
      assembleUtf8Char(0xF0.byte, fixedSource([byte(0x80), byte(0x80), byte(0x80)]))
    check r.text == Utf8ReplacementChar
    check r.leftover.isSome
    check r.leftover.get == 0x80.byte

  test "4-byte beyond U+10FFFF second byte yields U+FFFD AND surfaces leftover":
    let r =
      assembleUtf8Char(0xF4.byte, fixedSource([byte(0x90), byte(0x80), byte(0x80)]))
    check r.text == Utf8ReplacementChar
    check r.leftover.isSome
    check r.leftover.get == 0x90.byte

  test "Valid boundary sequences still assemble (U+D7FF, U+E000, U+10FFFF)":
    # U+D7FF (last before the surrogate gap) and U+E000 (first after) must pass
    # through unchanged rather than collapsing to U+FFFD.
    let d7ff = assembleUtf8Char(0xED.byte, fixedSource([byte(0x9F), byte(0xBF)]))
    check d7ff.text == buildUtf8String(0xED.byte, [byte(0x9F), byte(0xBF)])
    check d7ff.text.len == 3
    check d7ff.leftover.isNone
    let e000 = assembleUtf8Char(0xEE.byte, fixedSource([byte(0x80), byte(0x80)]))
    check e000.text == buildUtf8String(0xEE.byte, [byte(0x80), byte(0x80)])
    check e000.leftover.isNone
    # U+10FFFF, the maximum valid code point.
    let maxCp =
      assembleUtf8Char(0xF4.byte, fixedSource([byte(0x8F), byte(0xBF), byte(0xBF)]))
    check maxCp.text.len == 4
    check maxCp.leftover.isNone

  test "Overlong second byte does not over-consume the source":
    # The out-of-range second byte ends the subpart, so the remaining bytes of
    # the would-be sequence must NOT be read.
    var consumed = 0
    let buf = @[byte(0x80), byte(0x80)]
    proc src(): tuple[ok: bool, b: byte] =
      let b = buf[consumed]
      consumed.inc
      return (true, b)

    discard assembleUtf8Char(0xE0.byte, src)
    check consumed == 1

  test "Output of error path equals the U+FFFD constant exactly":
    # Belt-and-suspenders: catch any future drift where an error branch
    # builds a different replacement (e.g., a partial buffer).
    let r = assembleUtf8Char(0xC3.byte, fixedSource([byte(0xFF)]))
    check r.text.len == 3
    check r.text[0].byte == 0xEF
    check r.text[1].byte == 0xBF
    check r.text[2].byte == 0xBD

  test "Source not consumed past the failure point":
    # When an invalid continuation is hit, the assembler must stop calling
    # the source — otherwise it would silently swallow bytes that belong to
    # the next character.
    var consumed = 0
    let buf = @[byte(0x41), byte(0x42), byte(0x43)] # all invalid as conts
    proc src(): tuple[ok: bool, b: byte] =
      let b = buf[consumed]
      consumed.inc
      return (true, b)

    discard assembleUtf8Char(0xE3.byte, src)
    # 0xE3 expects 2 continuation bytes. The first byte (0x41) is invalid,
    # so the assembler returns immediately and must NOT read the second.
    check consumed == 1
