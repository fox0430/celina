## Basic event handling for Celina TUI library
##
## This module provides simple event handling for keyboard input.
## This is a minimal implementation for POSIX systems.

import std/[os, posix]

type
  EventKind* = enum
    Key
    Quit
    Unknown

  KeyCode* = enum
    # Basic keys
    Char # Regular character
    Enter # Enter/Return key
    Escape # Escape key
    Backspace # Backspace key
    Tab # Tab key
    Space # Space key
    # Arrow keys
    ArrowUp
    ArrowDown
    ArrowLeft
    ArrowRight # Function keys
    F1
    F2
    F3
    F4
    F5
    F6
    F7
    F8
    F9
    F10
    F11
    F12

  KeyModifier* = enum
    Ctrl
    Alt
    Shift

  KeyEvent* = object
    code*: KeyCode
    char*: char # Only valid when code == Char
    modifiers*: set[KeyModifier]

  Event* = object
    case kind*: EventKind
    of Key:
      key*: KeyEvent
    of Quit, Unknown:
      discard

# Simple non-blocking key reading
proc readKey*(): Event =
  ## Read a key event (blocking)
  var ch: char
  if stdin.readBuffer(addr ch, 1) == 1:
    case ch
    of '\r', '\n':
      return Event(kind: Key, key: KeyEvent(code: Enter, char: ch))
    of '\t':
      return Event(kind: Key, key: KeyEvent(code: Tab, char: ch))
    of ' ':
      return Event(kind: Key, key: KeyEvent(code: Space, char: ch))
    of '\x08', '\x7f': # Backspace or DEL
      return Event(kind: Key, key: KeyEvent(code: Backspace, char: ch))
    of '\x1b': # Escape
      return Event(kind: Key, key: KeyEvent(code: Escape, char: ch))
    of '\x03': # Ctrl+C
      return Event(kind: Quit)
    else:
      return Event(kind: Key, key: KeyEvent(code: Char, char: ch))
  else:
    return Event(kind: Unknown)

# Polling key reading
proc pollKey*(): Event =
  ## Poll for a key event (non-blocking)
  # Set stdin to non-blocking mode temporarily
  let flags = fcntl(STDIN_FILENO, F_GETFL)
  discard fcntl(STDIN_FILENO, F_SETFL, flags or O_NONBLOCK)

  let event = readKey()

  # Restore blocking mode
  discard fcntl(STDIN_FILENO, F_SETFL, flags)

  return event

# Check if input is available
proc hasInput*(): bool =
  ## Check if input is available without blocking
  # Use select to check if input is available
  var readSet: TFdSet
  FD_ZERO(readSet)
  FD_SET(STDIN_FILENO, readSet)

  var timeout = Timeval(tv_sec: Time(0), tv_usec: 0)
  select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout) > 0

# Event loop utilities
proc waitForKey*(): Event =
  ## Wait for a key press (blocking)
  while true:
    let event = readKey()
    if event.kind != Unknown:
      return event
    sleep(10) # Small delay to prevent busy waiting

proc waitForAnyKey*(): bool =
  ## Wait for any key press, return true if not quit
  let event = waitForKey()
  return event.kind != Quit
