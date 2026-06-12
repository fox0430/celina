# Test suite for Unicode support

import std/[unittest, unicode, strutils]

import ../celina/core/buffer
import ../celina/core/geometry
import ../celina/core/colors

suite "Unicode Support Tests":
  suite "Character Width Detection":
    test "ASCII characters have width 1":
      check runeWidth(Rune('A')) == 1
      check runeWidth(Rune('1')) == 1
      check runeWidth(Rune(' ')) == 1
      check runeWidth(Rune('!')) == 1

    test "Japanese characters have width 2":
      check runeWidth("あ".toRunes[0]) == 2 # Hiragana
      check runeWidth("ア".toRunes[0]) == 2 # Katakana
      check runeWidth("漢".toRunes[0]) == 2 # Kanji
      check runeWidth("本".toRunes[0]) == 2 # Kanji

    test "Combining marks have width 0":
      # Nonspacing marks (category Mn) render on top of the preceding base
      # glyph and must not advance the cursor.
      check runeWidth(Rune(0x0300)) == 0 # Combining grave accent
      check runeWidth(Rune(0x0301)) == 0 # Combining acute accent
      check runeWidth(Rune(0x0308)) == 0 # Combining diaeresis
      check runeWidth(Rune(0x0327)) == 0 # Combining cedilla

    test "Zero-width joiners and format controls have width 0":
      check runeWidth(Rune(0x200B)) == 0 # ZERO WIDTH SPACE
      check runeWidth(Rune(0x200C)) == 0 # ZERO WIDTH NON-JOINER
      check runeWidth(Rune(0x200D)) == 0 # ZERO WIDTH JOINER
      check runeWidth(Rune(0xFEFF)) == 0 # ZERO WIDTH NO-BREAK SPACE (BOM)

    test "Variation selectors have width 0":
      check runeWidth(Rune(0xFE0E)) == 0 # VARIATION SELECTOR-15 (text)
      check runeWidth(Rune(0xFE0F)) == 0 # VARIATION SELECTOR-16 (emoji)

    test "Emoji have appropriate width":
      check runeWidth("😀".toRunes[0]) == 2 # Grinning face
      check runeWidth("🌍".toRunes[0]) == 2 # Earth globe
      check runeWidth("🎉".toRunes[0]) == 2 # Party popper

  suite "Rune Sequence Width":
    test "Mixed ASCII and wide characters":
      let runes1 = "Hello世界".toRunes
      check runesWidth(runes1) == 9 # 5 ASCII + 2*2 wide chars

      let runes2 = "Aあ1い".toRunes
      check runesWidth(runes2) == 6 # 2 ASCII + 2*2 wide chars

    test "Pure ASCII string":
      let runes = "Hello World".toRunes
      check runesWidth(runes) == 11

    test "Pure wide character string":
      let runes = "こんにちは".toRunes
      check runesWidth(runes) == 10 # 5 chars * 2 width each

    test "Empty sequence":
      let empty: seq[Rune] = @[]
      check runesWidth(empty) == 0

    test "Decomposed grapheme counts base width only":
      # "é" as base "e" + U+0301 must measure 1 column, same as precomposed.
      let decomposed = @[Rune('e'), Rune(0x0301)]
      check runesWidth(decomposed) == 1
      check runesWidth("é".toRunes) == 1 # precomposed U+00E9

    test "ZWJ emoji sequence measures by visible glyphs":
      # Family "👨‍👩‍👧": 3 wide emoji joined by two ZWJ (U+200D). The joiners
      # are zero-width, so the run measures 3 * 2 = 6 columns.
      let family = "👨‍👩‍👧".toRunes
      check runesWidth(family) == 6

    test "displayWidth ignores combining marks and joiners":
      check displayWidth("é") == 1
      check displayWidth("café") == 4
      let joined = "a" & $Rune(0x200D) & "b" # a + ZWJ + b
      check displayWidth(joined) == 2

  suite "Buffer Unicode Rendering":
    test "setString with Japanese characters":
      var buffer = newBuffer(10, 3)
      buffer.setString(0, 0, "こんにちは", defaultStyle())

      # Check that wide characters are properly placed
      check buffer[0, 0].symbol == "こ"
      check buffer[1, 0].symbol == "" # Empty cell for wide char
      check buffer[2, 0].symbol == "ん"
      check buffer[3, 0].symbol == "" # Empty cell for wide char
      check buffer[4, 0].symbol == "に"

    test "setRunes with mixed content":
      var buffer = newBuffer(8, 2)
      let runes = "A漢B".toRunes
      buffer.setRunes(0, 0, runes, defaultStyle())

      check buffer[0, 0].symbol == "A"
      check buffer[1, 0].symbol == "漢"
      check buffer[2, 0].symbol == "" # Empty cell for wide char
      check buffer[3, 0].symbol == "B"

    test "Wide character truncation at buffer edge":
      var buffer = newBuffer(3, 2)
      # Try to place a wide character that would overflow
      buffer.setString(2, 0, "あ", defaultStyle())

      # Should not place the character since it would overflow
      check buffer[2, 0].symbol == " " # Should remain empty

    test "Cell width calculation":
      let asciiCell = cell("A")
      check asciiCell.width() == 1

      let wideCell = cell("あ")
      check wideCell.width() == 2

      let emptyCell = cell("")
      check emptyCell.width() == 0

  suite "Real-world Unicode Cases":
    test "Japanese sentence rendering":
      var buffer = newBuffer(20, 3)
      buffer.setString(0, 0, "日本最大の都市は東京です。", defaultStyle())

      # Verify the string fits and renders correctly
      let lines = buffer.toStrings()
      # Note: toStrings doesn't handle empty cells for wide chars,
      # so we just check the content was set
      check lines[0].len > 0

    test "Mixed language content":
      var buffer = newBuffer(15, 2)
      buffer.setString(0, 0, "Hello 世界!", defaultStyle())

      # Should fit: H(1) e(1) l(1) l(1) o(1) space(1) 世(2) 界(2) !(1) = 11 total
      check buffer[0, 0].symbol == "H"
      check buffer[6, 0].symbol == "世"
      check buffer[7, 0].symbol == "" # Empty cell
      check buffer[8, 0].symbol == "界"
      check buffer[9, 0].symbol == "" # Empty cell
      check buffer[10, 0].symbol == "!"

    test "Emoji rendering":
      var buffer = newBuffer(6, 2)
      buffer.setString(0, 0, "🎉🌍", defaultStyle())

      check buffer[0, 0].symbol == "🎉"
      check buffer[1, 0].symbol == "" # Empty cell for emoji
      check buffer[2, 0].symbol == "🌍"
      check buffer[3, 0].symbol == "" # Empty cell for emoji

    test "Complex text with combining characters":
      var buffer = newBuffer(10, 2)
      # "é" as e + combining acute accent
      let textWithCombining = "café"
      buffer.setString(0, 0, textWithCombining, defaultStyle())

      # Should render correctly (combining chars have 0 width)
      let result = buffer.toStrings()
      check result[0].contains("café")

  suite "Zero-width grapheme folding":
    # A zero-width rune (combining mark, ZWJ, variation selector) must be
    # folded into the preceding base cell rather than occupying a cell of its
    # own. Otherwise the differential renderer — which advances the cursor one
    # column per written cell — desyncs from the terminal, shifting every
    # following glyph.
    test "setRunes folds a combining mark into the base cell":
      var buffer = newBuffer(8, 1)
      # "é" decomposed: e + U+0301, then "f".
      buffer.setRunes(0, 0, @[Rune('e'), Rune(0x0301), Rune('f')])

      check buffer[0, 0].symbol == "e" & $Rune(0x0301)
      check buffer[0, 0].width() == 1
      check buffer[1, 0].symbol == "f" # follows at column 1, not 2
      check buffer[2, 0].symbol == " " # untouched blank

    test "multiple combining marks all fold into the same base cell":
      var buffer = newBuffer(8, 1)
      # Vietnamese "ệ" decomposed: e + U+0302 (circumflex) + U+0323 (dot
      # below). Both marks are zero-width and stack onto the single base.
      buffer.setRunes(0, 0, @[Rune('e'), Rune(0x0302), Rune(0x0323), Rune('f')])

      check buffer[0, 0].symbol == "e" & $Rune(0x0302) & $Rune(0x0323)
      check buffer[0, 0].width() == 1
      check buffer[1, 0].symbol == "f" # still column 1, not shifted by the marks
      check buffer[2, 0].symbol == " " # untouched blank

    test "combining mark folds onto a wide base, shadow preserved":
      var buffer = newBuffer(8, 1)
      # Wide kanji + combining mark + ASCII.
      buffer.setRunes(0, 0, @["漢".toRunes[0], Rune(0x0301), Rune('X')])

      check buffer[0, 0].symbol == "漢" & $Rune(0x0301)
      check buffer[0, 0].width() == 2
      check buffer[1, 0].symbol == "" # shadow cell preserved
      check buffer[2, 0].symbol == "X" # lands at column 2, not shifted

    test "ZWJ folds into the preceding emoji, not its own cell":
      var buffer = newBuffer(10, 1)
      # "👨‍👩": man + ZWJ + woman. We fold zero-width runes (the ZWJ) into the
      # base, but do not collapse the whole cluster — each visible emoji keeps
      # its own wide cell, matching wcwidth/unicode-width conventions.
      let zwj = "👨‍👩".toRunes
      buffer.setRunes(0, 0, zwj & @[Rune('!')])

      check buffer[0, 0].symbol == "👨" & $Rune(0x200D) # man + ZWJ
      check buffer[0, 0].width() == 2
      check buffer[1, 0].symbol == "" # shadow of man's wide cell
      check buffer[2, 0].symbol == "👩" # woman is a separate base cell
      check buffer[3, 0].symbol == "" # shadow of woman's wide cell
      check buffer[4, 0].symbol == "!" # next glyph at column 4

    test "emoji + variation selector stays in one cell":
      var buffer = newBuffer(8, 1)
      # U+2764 HEAVY BLACK HEART + U+FE0F emoji presentation selector. The
      # selector is zero-width, so the next glyph lands right after the heart
      # (whose own column count is environment-defined — derive it).
      let heartWidth = runeWidth(Rune(0x2764))
      buffer.setRunes(0, 0, @[Rune(0x2764), Rune(0xFE0F), Rune('A')])

      check buffer[0, 0].symbol == $Rune(0x2764) & $Rune(0xFE0F)
      check buffer[heartWidth, 0].symbol == "A"

    test "leading combining mark with no base is dropped":
      var buffer = newBuffer(6, 1)
      buffer.setRunes(0, 0, @[Rune(0x0301), Rune('a')])

      check buffer[0, 0].symbol == "a" # base lands at column 0
      check buffer[1, 0].symbol == " "

    test "area setString folds combining marks":
      var buffer = newBuffer(10, 1)
      let text = "e" & $Rune(0x0301) & "f" # e + combining acute + f
      buffer.setString(rect(0, 0, 10, 1), text)

      check buffer[0, 0].symbol == "e" & $Rune(0x0301)
      check buffer[1, 0].symbol == "f"
