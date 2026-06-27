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

    test "ZWJ emoji sequence measures as one cluster":
      # Family "👨‍👩‍👧": 3 emoji joined by two ZWJ (U+200D) form a single
      # grapheme cluster that terminals render in 2 columns (verified on
      # kitty), regardless of how many emoji it joins.
      let family = "👨‍👩‍👧".toRunes
      check runesWidth(family) == 2

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

    test "ZWJ emoji cluster collapses into one wide cell":
      var buffer = newBuffer(10, 1)
      # "👨‍👩": man + ZWJ + woman is one grapheme cluster terminals draw in 2
      # columns (kitty). The whole cluster lands in the lead cell with a single
      # shadow; the next glyph follows at column 2, not 4.
      let zwj = "👨‍👩".toRunes
      buffer.setRunes(0, 0, zwj & @[Rune('!')])

      check buffer[0, 0].symbol == "👨" & $Rune(0x200D) & "👩" # full cluster
      check buffer[0, 0].width() == 2
      check buffer[1, 0].symbol == "" # single shadow cell
      check buffer[2, 0].symbol == "!" # next glyph at column 2
      check buffer[3, 0].symbol == " " # untouched blank

    test "emoji + VS16 promotes to a wide cell":
      var buffer = newBuffer(8, 1)
      # U+2764 HEAVY BLACK HEART (default text presentation, 1 col) + U+FE0F
      # emoji presentation selector. VS16 promotes the cluster to emoji
      # presentation = 2 columns (kitty), so the next glyph lands at column 2.
      buffer.setRunes(0, 0, @[Rune(0x2764), Rune(0xFE0F), Rune('A')])

      check buffer[0, 0].symbol == $Rune(0x2764) & $Rune(0xFE0F)
      check buffer[0, 0].width() == 2
      check buffer[1, 0].symbol == "" # shadow cell
      check buffer[2, 0].symbol == "A" # next glyph at column 2

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

  suite "Grapheme cluster width":
    # Width is a property of the whole grapheme cluster, not of any single code
    # point. VS16 promotes a narrow base to emoji presentation (2 columns); a
    # ZWJ emoji sequence and a regional-indicator flag are each one 2-column
    # cluster. Verified against kitty.
    test "VS16 promotes a narrow pictographic to width 2":
      # ▶ (U+25B6, default text presentation = 1 col) + VS16 -> 2 cols.
      check displayWidth("▶" & $Rune(0xFE0F)) == 2
      check displayWidth("⚠" & $Rune(0xFE0F)) == 2
      # Without VS16 the bare pictographic keeps its text width.
      check displayWidth("▶") == 1
      # VS15 (text presentation) must NOT promote.
      check displayWidth("▶" & $Rune(0xFE0E)) == 1

    test "a trailing VS15 overrides a preceding VS16 back to text width":
      # base + VS16 + VS15 is ill-formed, but the last presentation selector
      # wins: VS15 requests text presentation, so the cluster must report 1 col,
      # not stay promoted at 2 and desync the renderer with a ghost cell.
      check displayWidth("⚠" & $Rune(0xFE0F) & $Rune(0xFE0E)) == 1
      check displayWidth("▶" & $Rune(0xFE0F) & $Rune(0xFE0E)) == 1

    test "VS16 cluster renders as a wide cell with a shadow":
      var buffer = newBuffer(8, 1)
      # ⚠ + VS16 + 'X': cluster occupies 2 columns, X lands at column 2.
      buffer.setRunes(0, 0, "⚠".toRunes & @[Rune(0xFE0F), Rune('X')])

      check buffer[0, 0].symbol == "⚠" & $Rune(0xFE0F)
      check buffer[0, 0].width() == 2
      check buffer[1, 0].symbol == "" # shadow cell
      check buffer[2, 0].symbol == "X"

    test "three-emoji ZWJ family is one width-2 cluster":
      var buffer = newBuffer(10, 1)
      let family = "👨‍👩‍👧".toRunes # man ZWJ woman ZWJ girl
      check runesWidth(family) == 2
      buffer.setRunes(0, 0, family & @[Rune('!')])

      check buffer[0, 0].width() == 2
      check buffer[1, 0].symbol == "" # single shadow
      check buffer[2, 0].symbol == "!" # next glyph at column 2

    test "regional-indicator flag is one width-2 cluster":
      var buffer = newBuffer(8, 1)
      let flag = "🇯🇵".toRunes # U+1F1EF U+1F1F5
      check runesWidth(flag) == 2
      buffer.setRunes(0, 0, flag & @[Rune('!')])

      check buffer[0, 0].width() == 2
      check buffer[1, 0].symbol == "" # shadow of the flag glyph
      check buffer[2, 0].symbol == "!" # next glyph at column 2

    test "emoji modifier (skin tone) promotes a narrow base to width 2":
      # ☝ (U+261D, default text presentation = 1 col) is an Emoji_Modifier_Base.
      # Followed by a Fitzpatrick skin-tone modifier it becomes a 2-column emoji
      # (kitty), even though the modifier is itself a zero-width Extend.
      check displayWidth("☝" & $Rune(0x1F3FB)) == 2
      check displayWidth("✌" & $Rune(0x1F3FD)) == 2
      # A skin-tone modifier after a non-pictographic base must NOT promote.
      check displayWidth("A" & $Rune(0x1F3FB)) == 1

      var buffer = newBuffer(8, 1)
      buffer.setRunes(0, 0, ("☝" & $Rune(0x1F3FB)).toRunes & @[Rune('X')])
      check buffer[0, 0].width() == 2
      check buffer[1, 0].symbol == "" # shadow cell
      check buffer[2, 0].symbol == "X" # next glyph at column 2

    test "keycap sequence promotes a narrow digit to width 2":
      # "1️⃣" = '1' + VS16 + U+20E3 (combining enclosing keycap). The base digit
      # is narrow and not pictographic, but the enclosing keycap makes terminals
      # render it in 2 columns (kitty).
      let keycap = "1" & $Rune(0xFE0F) & $Rune(0x20E3)
      check displayWidth(keycap) == 2
      # '#' and '*' are also valid keycap bases.
      check displayWidth("#" & $Rune(0xFE0F) & $Rune(0x20E3)) == 2
      # The bare digit, without the enclosing keycap, stays 1 column.
      check displayWidth("1") == 1

    test "U+20E3 after a non-keycap base does not promote to width 2":
      # Only digits / '#' / '*' form a keycap. After any other base (here 'A')
      # U+20E3 is a stray combining mark the terminal draws in one column, so it
      # must fold as zero-width and NOT promote — promoting would over-count and
      # leave a ghost cell, the desync this segmentation exists to prevent.
      check displayWidth("A" & $Rune(0x20E3)) == 1

      var buffer = newBuffer(8, 1)
      buffer.setRunes(0, 0, ("A" & $Rune(0x20E3)).toRunes & @[Rune('B')])
      check buffer[0, 0].symbol == "A" & $Rune(0x20E3) # mark folds onto 'A'
      check buffer[0, 0].width() == 1
      check buffer[1, 0].symbol == "B" # next glyph at column 1, nothing reserved

    test "keycap cluster renders as a wide cell with a shadow":
      var buffer = newBuffer(8, 1)
      let keycap = ("1" & $Rune(0xFE0F) & $Rune(0x20E3)).toRunes
      buffer.setRunes(0, 0, keycap & @[Rune('X')])

      check buffer[0, 0].width() == 2
      check buffer[1, 0].symbol == "" # shadow cell
      check buffer[2, 0].symbol == "X" # next glyph at column 2

    test "combining mark after a tab folds onto the expanded space, not dropped":
      var buffer = newBuffer(10, 1)
      # A C0 control (here a tab) is its own cluster, so a combining mark right
      # after it attaches to the last expanded space cell instead of being
      # swallowed into the control's cluster and silently dropped.
      buffer.setRunes(0, 0, @[Rune('\t'), Rune(0x0301)], tabWidth = 4)

      check buffer[3, 0].symbol == " " & $Rune(0x0301) # mark folded onto column 3

    test "ZWJ after a non-emoji base does not swallow the following emoji":
      # TR29 GB11 only joins `ExtPict ... ZWJ × ExtPict`. A ZWJ after a narrow
      # non-emoji base (here 'A') must NOT pull the following emoji into the
      # base's cluster: that collapsed "A ZWJ 👨" to one width-1 cell, so the
      # buffer reserved 1 column while the terminal draws A(1) + man(2) = 3,
      # leaving ghost cells. The ZWJ folds onto 'A'; the man opens its own cell.
      let man = Rune(0x1F468)
      check displayWidth("A" & $Rune(0x200D) & $man) == 3

      var buffer = newBuffer(10, 1)
      buffer.setRunes(0, 0, @[Rune('A'), Rune(0x200D), man, Rune('B')])
      check buffer[0, 0].symbol == "A" & $Rune(0x200D) # ZWJ folds onto 'A'
      check buffer[0, 0].width() == 1
      check buffer[1, 0].symbol == $man # man opens its own wide cell
      check buffer[1, 0].width() == 2
      check buffer[2, 0].symbol == "" # man's shadow
      check buffer[3, 0].symbol == "B" # next glyph at column 3, nothing swallowed

  suite "foldZeroWidthRune":
    # Per-rune setCell callers (one rune at a time, e.g. for per-glyph styling)
    # must fold width-0 runes into the preceding cell themselves; this helper
    # does it, stepping back over a wide character's shadow.
    test "folds a mark onto the previous narrow base":
      var buffer = newBuffer(6, 1)
      buffer.setCell(0, 0, Rune('e'), 1)
      # Cursor advanced to column 1; fold the combining acute into 'e'.
      buffer.foldZeroWidthRune(1, 0, Rune(0x0301))

      check buffer[0, 0].symbol == "e" & $Rune(0x0301)
      check buffer[1, 0].symbol == " " # untouched

    test "folds a mark onto a wide base across its shadow":
      var buffer = newBuffer(6, 1)
      buffer.setCell(0, 0, "漢".toRunes[0], 2) # lead at 0, shadow at 1
      # Cursor advanced to column 2; fold across the shadow onto the lead.
      buffer.foldZeroWidthRune(2, 0, Rune(0x0301))

      check buffer[0, 0].symbol == "漢" & $Rune(0x0301)
      check buffer[1, 0].symbol == "" # shadow preserved

    test "leading mark with no base to the left is dropped":
      var buffer = newBuffer(6, 1)
      buffer.foldZeroWidthRune(0, 0, Rune(0x0301)) # x-1 < 0 -> no-op

      check buffer[0, 0].symbol == " " # untouched
