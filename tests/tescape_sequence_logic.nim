# Test suite for escape_sequence_logic module

import std/[strutils, unittest]

import ../celina/core/escape_sequence_logic
import ../celina/core/key_logic

suite "Escape Sequence Logic Tests":
  suite "Helper Functions":
    test "escapeKey creates proper escape key event":
      let key = escapeKey()
      check key.code == KeyCode.Escape
      check key.char == "\x1b"

    test "escapeResult creates valid result":
      let result = escapeResult()
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Escape

  suite "SS3 Key Processing":
    test "ss3Action decodes F1-F4":
      check ss3Action('P').key.code == KeyCode.F1
      check ss3Action('Q').key.code == KeyCode.F2
      check ss3Action('R').key.code == KeyCode.F3
      check ss3Action('S').key.code == KeyCode.F4

    test "ss3Action decodes application cursor keys":
      check ss3Action('A').key.code == ArrowUp
      check ss3Action('B').key.code == ArrowDown
      check ss3Action('C').key.code == ArrowRight
      check ss3Action('D').key.code == ArrowLeft
      check ss3Action('H').key.code == Home
      check ss3Action('F').key.code == End

    test "ss3Action ignores other finals":
      for final in ['X', 'j', '~']:
        check ss3Action(final).kind == cakIgnore

  suite "Bracket Sequence Classification":
    test "a second [ is the Linux console's function key form":
      check classifyBracketSequence('[') == BskLinuxFunctionKey

    test "classifyBracketSequence with arrow key A (up)":
      let kind = classifyBracketSequence('A')
      check kind == BskArrowKey

    test "classifyBracketSequence with arrow key B (down)":
      let kind = classifyBracketSequence('B')
      check kind == BskArrowKey

    test "classifyBracketSequence with arrow key C (right)":
      let kind = classifyBracketSequence('C')
      check kind == BskArrowKey

    test "classifyBracketSequence with arrow key D (left)":
      let kind = classifyBracketSequence('D')
      check kind == BskArrowKey

    test "classifyBracketSequence with navigation key H (Home)":
      let kind = classifyBracketSequence('H')
      check kind == BskNavigationKey

    test "classifyBracketSequence with navigation key F (End)":
      let kind = classifyBracketSequence('F')
      check kind == BskNavigationKey

    test "classifyBracketSequence with mouse X10 (M)":
      let kind = classifyBracketSequence('M')
      check kind == BskMouseX10

    test "classifyBracketSequence with mouse SGR (<)":
      let kind = classifyBracketSequence('<')
      check kind == BskMouseSGR

    test "classifyBracketSequence with focus in (I)":
      let kind = classifyBracketSequence('I')
      check kind == BskFocusIn

    test "classifyBracketSequence with focus out (O)":
      let kind = classifyBracketSequence('O')
      check kind == BskFocusOut

    test "classifyBracketSequence leaves the rest to the CSI scan":
      for ch in ['0', '1', '9', ';', '?', 'X', 'u', '~', '\x1b']:
        check classifyBracketSequence(ch) == BskGeneric

  suite "Simple Bracket Sequence Processing":
    test "processSimpleBracketSequence with arrow up":
      let result = processSimpleBracketSequence('A', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.ArrowUp

    test "processSimpleBracketSequence with arrow down":
      let result = processSimpleBracketSequence('B', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.ArrowDown

    test "processSimpleBracketSequence with arrow right":
      let result = processSimpleBracketSequence('C', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.ArrowRight

    test "processSimpleBracketSequence with arrow left":
      let result = processSimpleBracketSequence('D', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.ArrowLeft

    test "processSimpleBracketSequence with Home":
      let result = processSimpleBracketSequence('H', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Home

    test "processSimpleBracketSequence with End":
      let result = processSimpleBracketSequence('F', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.End

    test "processSimpleBracketSequence with invalid flag":
      let result = processSimpleBracketSequence('A', false)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Escape

    test "processSimpleBracketSequence with invalid character":
      let result = processSimpleBracketSequence('X', true)
      check result.isValid == true
      check result.keyEvent.code == KeyCode.Escape

  suite "Edge Cases and Error Handling":
    test "processSimpleBracketSequence with control characters":
      for ch in ['\0', '\x01', '\x7F']:
        let result = processSimpleBracketSequence(ch, true)
        check result.isValid == true
        check result.keyEvent.code == KeyCode.Escape

  suite "Consistency Tests":
    test "All escape fallbacks return same key":
      let key1 = escapeKey()
      let key2 = escapeResult().keyEvent
      let key3 = processSimpleBracketSequence('X', true).keyEvent
      check key1.code == key2.code
      check key2.code == key3.code
      check key1.char == key2.char
      check key2.char == key3.char

    test "Classification functions are deterministic":
      # Same input should always produce same output
      for i in 1 .. 10:
        check classifyBracketSequence('A') == BskArrowKey

    test "Invalid flags always produce escape key":
      let r1 = processSimpleBracketSequence('A', false)
      check r1.keyEvent.code == KeyCode.Escape

  suite "Paste End State Machine":
    proc feed(input: string): tuple[output: string, completed: bool, residual: string] =
      ## Run stepPasteEnd over `input` and return the accumulated output,
      ## whether the paste-end terminator was hit, and any pending bytes left
      ## buffered when the input was exhausted (residual).
      var state = PesNone
      var pending = ""
      var output = ""
      var completed = false
      for ch in input:
        if stepPasteEnd(state, pending, ch, output):
          completed = true
          break
      return (output, completed, pending)

    test "plain text is appended verbatim":
      let r = feed("hello world")
      check r.output == "hello world"
      check r.completed == false
      check r.residual == ""

    test "ESC[201~ is detected and consumed as paste end":
      let r = feed("abc\x1b[201~")
      check r.output == "abc"
      check r.completed == true

    test "terminator bytes are not appended to output":
      let r = feed("\x1b[201~")
      check r.output == ""
      check r.completed == true

    test "ESC[200~ in content is not paste end and is preserved":
      let r = feed("a\x1b[200~b")
      check r.output == "a\x1b[200~b"
      check r.completed == false

    test "non-matching ESC[ sequence is flushed back to output":
      let r = feed("a\x1b[Ab")
      check r.output == "a\x1b[Ab"
      check r.completed == false

    test "incomplete ESC[2 prefix at end is left in residual":
      let r = feed("xy\x1b[2")
      check r.output == "xy"
      check r.residual == "\x1b[2"
      check r.completed == false

    test "incomplete ESC[20 prefix at end is left in residual":
      let r = feed("\x1b[20")
      check r.output == ""
      check r.residual == "\x1b[20"
      check r.completed == false

    test "incomplete ESC[201 prefix (no tilde) is left in residual":
      let r = feed("\x1b[201")
      check r.output == ""
      check r.residual == "\x1b[201"
      check r.completed == false

    test "ESC[202~ is not paste end and is flushed":
      let r = feed("\x1b[202~done")
      check r.output == "\x1b[202~done"
      check r.completed == false

    test "new ESC mid-sequence restarts matching":
      # First ESC[ is incomplete, then a valid ESC[201~ follows
      let r = feed("\x1b[\x1b[201~")
      check r.output == "\x1b["
      check r.completed == true

    test "double ESC stays in PesEsc and flushes the first":
      let r = feed("\x1b\x1b[201~")
      check r.output == "\x1b"
      check r.completed == true

    test "ESC at end of input is left in residual":
      let r = feed("text\x1b")
      check r.output == "text"
      check r.residual == "\x1b"
      check r.completed == false

    test "content after partial match is preserved when match fails":
      let r = feed("\x1b[2X")
      check r.output == "\x1b[2X"
      check r.completed == false

    test "Pes201 with non-tilde non-ESC byte flushes pending and continues":
      let r = feed("\x1b[201X")
      check r.output == "\x1b[201X"
      check r.completed == false

    test "bytes after terminator are not consumed":
      var state = PesNone
      var pending = ""
      var output = ""
      let input = "ab\x1b[201~more"
      var consumed = 0
      for ch in input:
        consumed.inc()
        if stepPasteEnd(state, pending, ch, output):
          break
      check output == "ab"
      check consumed == "ab\x1b[201~".len

  suite "Cursor Position Report":
    test "a lone reply gives the 0-based position":
      let r = extractCursorReply("\x1b[24;80R")
      check r.found
      check r.row == 23
      check r.col == 79
      check r.typeahead == ""

    test "bytes around the reply stay in order":
      let r = extractCursorReply("ab\x1b[5;10Rcd")
      check r.found
      check (r.row, r.col) == (4, 9)
      check r.typeahead == "abcd"

    test "a cut-off reply stays in the typeahead":
      let r = extractCursorReply("x\x1b[24;8")
      check not r.found
      check r.typeahead == "x\x1b[24;8"

    test "key sequences and a lone ESC before the reply are kept":
      let r = extractCursorReply("\x1b\x1b[1;5A\x1b[2;3R")
      check r.found
      check (r.row, r.col) == (1, 2)
      check r.typeahead == "\x1b\x1b[1;5A"

    test "only the first reply is taken":
      let r = extractCursorReply("\x1b[1;1R\x1b[2;2R")
      check (r.row, r.col) == (0, 0)
      check r.typeahead == "\x1b[2;2R"

    test "an overlong number is not a reply":
      let r = extractCursorReply("\x1b[123456;1R")
      check not r.found
      check r.typeahead == "\x1b[123456;1R"

    test "no bytes, no reply":
      let r = extractCursorReply("")
      check not r.found
      check r.typeahead == ""

  suite "CSI Sequences":
    proc scanOf(body: string): CsiScan =
      ## Feed the bytes after `ESC [` until the scan stops.
      for ch in body:
        result.feed(ch)
        if result.state != cssReading:
          break

    proc keyOf(body: string): KeyEvent =
      let action = scanOf(body).action()
      check action.kind == cakKey
      action.key

    proc ignored(body: string): bool =
      scanOf(body).action().kind == cakIgnore

    test "the scan stops at the final byte":
      let scan = scanOf("105;5ux")
      check scan.state == cssDone

    test "a scan with no final byte is cut off, and ignored":
      var scan = scanOf("105;5")
      check scan.state == cssReading
      scan.state = cssTruncated
      check scan.action().kind == cakIgnore

    test "a scan stops at its byte limit":
      for filler in ['1', ';', ' ']:
        var scan = CsiScan()
        for _ in 1 ..< MaxCsiScanBytes:
          scan.feed(filler)
          check scan.state == cssReading
        scan.feed(filler)
        check scan.state == cssTruncated
        check scan.action().kind == cakIgnore

    test "a byte outside the sequence ends the scan":
      for stray in ['\x1b', '\x03', '\xe3']:
        let scan = scanOf("105;" & stray)
        check scan.state == cssStray
        check scan.stray == stray
        check scan.action().kind == cakIgnore

    test "Ctrl+I, Ctrl+M and Ctrl+[ are the keys of their control bytes":
      check keyOf("105;5u") == KeyEvent(code: Tab, char: "\t")
      check keyOf("109;5u") == KeyEvent(code: Enter, char: "\r")
      check keyOf("91;5u") == KeyEvent(code: Escape, char: "\x1b")

    test "a final byte on the last allowed byte still finishes":
      var scan = CsiScan()
      for _ in 1 ..< MaxCsiScanBytes:
        scan.feed('1')
      scan.feed('~')
      check scan.state == cssDone

    test "Ctrl+letter means what its legacy byte means":
      check scanOf("99;5u").action().kind == cakQuit
      check scanOf("27;5;99~").action().kind == cakQuit
      check scanOf("67;5u").action().kind == cakQuit
      check keyOf("104;5u") == KeyEvent(code: Backspace, char: "\x08")
      check keyOf("73;5u") == KeyEvent(code: Tab, char: "\t")
      check keyOf("64;5u") == KeyEvent(code: Space, char: " ", modifiers: {Ctrl})
      check keyOf("92;5u") == KeyEvent(code: Char, char: "4", modifiers: {Ctrl})

    test "other modifiers and plain letters are not control bytes":
      check keyOf("99;7u") == KeyEvent(code: Char, char: "c", modifiers: {Ctrl, Alt})
      check keyOf("99u") == KeyEvent(code: Char, char: "c")
      check keyOf("99;3u") == KeyEvent(code: Char, char: "c", modifiers: {Alt})
      check keyOf("99:67;2u") == KeyEvent(code: Char, char: "C", modifiers: {Shift})

    test "with more modifiers they stay letters":
      check keyOf("105;6u") == KeyEvent(code: Char, char: "i", modifiers: {Ctrl, Shift})
      check keyOf("105;7u") == KeyEvent(code: Char, char: "i", modifiers: {Ctrl, Alt})

    test "CSI u gives a character with its modifiers":
      check keyOf("97;5u") == KeyEvent(code: Char, char: "a", modifiers: {Ctrl})
      check keyOf("46;5u") == KeyEvent(code: Char, char: ".", modifiers: {Ctrl})
      check keyOf("97u") == KeyEvent(code: Char, char: "a")
      check keyOf("12354;3u") == KeyEvent(code: Char, char: "あ", modifiers: {Alt})

    test "CSI u gives named keys":
      check keyOf("13;5u") == KeyEvent(code: Enter, char: "\r", modifiers: {Ctrl})
      check keyOf("9;5u") == KeyEvent(code: Tab, char: "\t", modifiers: {Ctrl})
      check keyOf("127;5u").code == Backspace
      check keyOf("32;5u") == KeyEvent(code: Space, char: " ", modifiers: {Ctrl})
      check keyOf("27;3u") == KeyEvent(code: Escape, char: "\x1b", modifiers: {Alt})

    test "Shift+Tab is BackTab":
      check keyOf("9;2u") == KeyEvent(code: BackTab)
      check keyOf("9;6u") == KeyEvent(code: BackTab, modifiers: {Ctrl})

    test "BackTab holds no Shift in any form":
      check keyOf("1;2Z") == keyOf("9;2u")
      check keyOf("27;2;9~") == keyOf("9;2u")
      check keyOf("1;6Z") == keyOf("9;6u")

    test "modifyOtherKeys is the same key as CSI u":
      check keyOf("27;5;105~") == keyOf("105;5u")
      check keyOf("27;5;97~") == keyOf("97;5u")
      check keyOf("27;5;13~") == keyOf("13;5u")

    test "kitty's sub-fields do not change an unshifted key":
      check keyOf("97:65;5:1u") == keyOf("97;5u")
      check keyOf("97;133u") == KeyEvent(code: Char, char: "a", modifiers: {Ctrl})

    test "Shift uses the alternate key, or the uppercase letter":
      check keyOf("97:65;2u") == KeyEvent(code: Char, char: "A", modifiers: {Shift})
      check keyOf("97;2u") == KeyEvent(code: Char, char: "A", modifiers: {Shift})
      check keyOf("49:33;2u") == KeyEvent(code: Char, char: "!", modifiers: {Shift})
      check keyOf("49;2u") == KeyEvent(code: Char, char: "1", modifiers: {Shift})
      check keyOf("27;2;97~") == KeyEvent(code: Char, char: "A", modifiers: {Shift})

    test "a chord with Super, Hyper or Meta is ignored":
      for body in [
        "97;9u", "97;17u", "97;33u", "97;13u", "13;9u", "32;9u", "27;9;97~", "1;9A",
        "1;33D", "1;17H", "3;9~", "15;9~", "1;9P",
      ]:
        check ignored(body)

    test "Caps Lock and Num Lock do not hide a key":
      check keyOf("97;65u") == KeyEvent(code: Char, char: "a")
      check keyOf("97;129u") == KeyEvent(code: Char, char: "a")
      check keyOf("1;65A") == KeyEvent(code: ArrowUp)
      check keyOf("3;129~") == KeyEvent(code: Delete)

    test "a kitty release is not a key press":
      check ignored("97;5:3u")
      check ignored("1;5:3A")
      check keyOf("97;5:2u").char == "a"

    test "codepoints that are not keys are ignored":
      for body in ["0u", "1;5u", "128u", "55296u", "57344u", "1114112u", "99999999999u"]:
        check ignored(body)

    test "numeric keys keep their modifiers":
      check keyOf("3~").code == Delete
      check keyOf("3;5~") == KeyEvent(code: Delete, modifiers: {Ctrl})
      check keyOf("6;2~") == KeyEvent(code: PageDown, modifiers: {Shift})
      check keyOf("7~") == KeyEvent(code: Home)
      check keyOf("8;5~") == KeyEvent(code: End, modifiers: {Ctrl})

    test "function keys keep their modifiers":
      check keyOf("15~").code == F5
      check keyOf("24~").code == F12
      check keyOf("15;2~") == KeyEvent(code: F5, modifiers: {Shift})
      check keyOf("1;2P") == KeyEvent(code: F1, modifiers: {Shift})
      check keyOf("1;5Q") == KeyEvent(code: F2, modifiers: {Ctrl})
      check keyOf("1;2S") == KeyEvent(code: F4, modifiers: {Shift})

    test "arrows and navigation keys keep their modifiers":
      check keyOf("1;5A") == KeyEvent(code: ArrowUp, modifiers: {Ctrl})
      check keyOf("1;2H") == KeyEvent(code: Home, modifiers: {Shift})
      check keyOf("1;8F") == KeyEvent(code: End, modifiers: {Ctrl, Shift, Alt})

    test "bracketed paste":
      check scanOf("200~").action().kind == cakPaste
      check ignored("201~")

    test "paste start takes no other parameters":
      for body in ["200;5~", "200;2~", "200:1~", "200;~"]:
        check ignored(body)

    test "rxvt's $ ends a sequence after one number":
      for body in ["7$", "3$", "2$", "23$"]:
        let scan = scanOf(body & "x")
        check scan.state == cssDone
        check scan.action().kind == cakIgnore

    test "$ stays an intermediate byte elsewhere":
      for body in ["?1;2$y", "1;2$y", "$y", "?25$y"]:
        let scan = scanOf(body)
        check scan.state == cssDone
        check scan.action().kind == cakIgnore
      check scanOf("1;2$").state == cssReading

    test "sequences that are not keys are ignored":
      for body in [
        "12;40R", "1;5R", "99~", "16~", "X", "?62c", "?1u", ">1;2c", "=1u", "1 q",
        "2 q", "P", "1P",
      ]:
        check ignored(body)

    test "parameters too long to be a key are ignored":
      check ignored("1".repeat(40) & "u")
      check scanOf("1".repeat(40) & "u").state == cssDone
