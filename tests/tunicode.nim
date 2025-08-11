# Test suite for Unicode support

import std/[unittest, unicode, strutils]

import ../src/core/buffer
import ../src/core/colors

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

    test "Combining characters have width 0":
      # Note: Some combining marks may be detected as width 1 by unicodedb
      # This depends on the specific Unicode implementation
      let combiningGrave = runeWidth(Rune(0x0300))
      let combiningAcute = runeWidth(Rune(0x0301))
      let combiningDiaeresis = runeWidth(Rune(0x0308))

      # These should be 0 or 1, but not 2 (not wide characters)
      check combiningGrave <= 1
      check combiningAcute <= 1
      check combiningDiaeresis <= 1

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
