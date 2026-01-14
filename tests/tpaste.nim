# Test suite for bracketed paste mode support

import std/[unittest, strutils]

import ../celina/core/events
import ../celina/core/escape_sequence_logic
import ../celina/core/terminal_common

suite "Bracketed Paste Mode Tests":
  suite "Event Types":
    test "Paste EventKind exists":
      check EventKind.Paste.ord == 3
      check EventKind.Paste.ord > EventKind.Resize.ord
      check EventKind.Paste.ord < EventKind.Quit.ord

    test "Paste Event creation":
      let event = Event(kind: Paste, pastedText: "Hello World")
      check event.kind == Paste
      check event.pastedText == "Hello World"

    test "Empty paste":
      let event = Event(kind: Paste, pastedText: "")
      check event.kind == Paste
      check event.pastedText == ""

    test "Multiline paste":
      let event = Event(kind: Paste, pastedText: "Line 1\nLine 2\nLine 3")
      check event.kind == Paste
      check event.pastedText.contains('\n')
      check event.pastedText == "Line 1\nLine 2\nLine 3"

    test "UTF-8 paste content":
      let event = Event(kind: Paste, pastedText: "こんにちは 🎉")
      check event.kind == Paste
      check event.pastedText == "こんにちは 🎉"

  suite "Sequence Detection":
    test "isPasteStartSequence":
      check isPasteStartSequence('2', '0', '0', '~')
      check not isPasteStartSequence('2', '0', '1', '~')
      check not isPasteStartSequence('1', '5', '~', '\0')
      check not isPasteStartSequence('2', '0', '0', 'A')
      check not isPasteStartSequence('1', '0', '0', '~')

    test "isPasteEndSequence":
      check isPasteEndSequence('2', '0', '1', '~')
      check not isPasteEndSequence('2', '0', '0', '~')
      check not isPasteEndSequence('2', '0', '1', 'A')
      check not isPasteEndSequence('1', '0', '1', '~')

  suite "Terminal Control Sequences":
    test "BracketedPasteEnable format":
      check BracketedPasteEnable == "\e[?2004h"

    test "BracketedPasteDisable format":
      check BracketedPasteDisable == "\e[?2004l"

  suite "SuspendState":
    test "SuspendState has bracketedPaste field":
      var state: SuspendState
      state.suspendedBracketedPaste = true
      check state.suspendedBracketedPaste == true
      state.suspendedBracketedPaste = false
      check state.suspendedBracketedPaste == false

  suite "Edge Cases":
    test "Paste containing escape sequences":
      # Test that escape sequences in paste content are preserved correctly
      # \x1b[31mRed\x1b[0m = ESC[31mRed ESC[0m = 5+3+4 = 12 bytes
      let event = Event(kind: Paste, pastedText: "\x1b[31mRed\x1b[0m")
      check event.pastedText == "\x1b[31mRed\x1b[0m"
      check event.pastedText.len == 12

    test "Very large paste":
      let largeText = 'x'.repeat(100000)
      let event = Event(kind: Paste, pastedText: largeText)
      check event.pastedText.len == 100000

    test "Paste with special characters":
      let event = Event(kind: Paste, pastedText: "\t\r\n\x00\xFF")
      check event.kind == Paste
      check event.pastedText.len == 5

    test "Paste with partial end sequence":
      # Content that looks like start of end sequence but isn't
      let event = Event(kind: Paste, pastedText: "\x1b[20")
      check event.pastedText == "\x1b[20"
