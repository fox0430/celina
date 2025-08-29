## Event handling
##
## This module provides comprehensive event handling for keyboard input,
## including escape sequences and arrow keys for POSIX systems.

import std/[os, posix, options, strutils]

import errors

# Define SIGWINCH if not available
when not declared(SIGWINCH):
  const SIGWINCH = 28

# Global flag for resize detection
var resizeDetected* = false

# Signal handler for SIGWINCH
proc sigwinchHandler(sig: cint) {.noconv.} =
  resizeDetected = true

type
  EventKind* = enum
    Key
    Mouse
    Resize
    Quit
    Unknown

  KeyCode* = enum
    # Basic keys
    Char # Regular character
    Enter # Enter/Return key
    Escape # Escape key
    Backspace # Backspace key
    Tab # Tab key
    BackTab # Shift+Tab
    Space # Space key
    # Arrow keys
    ArrowUp
    ArrowDown
    ArrowLeft
    ArrowRight
    # Navigation keys
    Home
    End
    PageUp
    PageDown
    Insert
    Delete
    # Function keys
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

  MouseButton* = enum
    Left
    Right
    Middle
    WheelUp
    WheelDown

  MouseEventKind* = enum
    Press
    Release
    Move
    Drag

  KeyEvent* = object
    code*: KeyCode
    char*: char # Only valid when code == Char
    modifiers*: set[KeyModifier]

  MouseEvent* = object
    kind*: MouseEventKind
    button*: MouseButton
    x*: int
    y*: int
    modifiers*: set[KeyModifier]

  Event* = object
    case kind*: EventKind
    of Key:
      key*: KeyEvent
    of Mouse:
      mouse*: MouseEvent
    of Resize, Quit, Unknown:
      discard

# Mouse modifier parsing functions
proc parseMouseModifiers(button_byte: int): set[KeyModifier] =
  ## Parse mouse modifiers from X10 button byte
  result = {}
  if (button_byte and 0x04) != 0:
    result.incl(Shift)
  if (button_byte and 0x08) != 0:
    result.incl(Alt)
  if (button_byte and 0x10) != 0:
    result.incl(Ctrl)

proc parseMouseModifiersSGR(button_code: int): set[KeyModifier] =
  ## Parse mouse modifiers from SGR button code
  result = {}
  if (button_code and 0x04) != 0:
    result.incl(Shift)
  if (button_code and 0x08) != 0:
    result.incl(Alt)
  if (button_code and 0x10) != 0:
    result.incl(Ctrl)

# Mouse event parsing functions
proc parseMouseEventX10(): Event =
  ## Parse X10 mouse format: ESC[Mbxy
  ## where b is button byte, x,y are coordinate bytes
  var data: array[3, char]
  # Use a timeout to prevent hanging on incomplete sequences
  if stdin.readBuffer(addr data[0], 3) == 3:
    let button_byte = data[0].ord
    let x = data[1].ord - 33 # X10 uses offset 33
    let y = data[2].ord - 33 # X10 uses offset 33

    let button_info = button_byte and 0x03
    let is_drag = (button_byte and 0x20) != 0
    let is_wheel = (button_byte and 0x40) != 0

    var button: MouseButton
    var kind: MouseEventKind

    if is_wheel:
      # X10 wheel events: bit 0 indicates direction
      if (button_byte and 0x01) != 0:
        button = WheelDown
      else:
        button = WheelUp
      kind = Press
    else:
      case button_info
      of 0:
        button = Left
      of 1:
        button = Middle
      of 2:
        button = Right
      else:
        button = Left

      if is_drag:
        kind = Drag
      elif (button_byte and 0x03) == 3:
        kind = Release
      else:
        kind = Press

    let modifiers = parseMouseModifiers(button_byte)

    return Event(
      kind: EventKind.Mouse,
      mouse: MouseEvent(kind: kind, button: button, x: x, y: y, modifiers: modifiers),
    )

  return Event(kind: Unknown)

proc parseMouseEventSGR(): Event =
  ## Parse SGR mouse format: ESC[<button;x;y;M/m
  ## M for press, m for release
  var buffer: string
  var ch: char
  var readCount = 0
  const maxReadCount = 20 # Prevent infinite loops

  # Read until we get M or m, with safety limits
  while readCount < maxReadCount and stdin.readBuffer(addr ch, 1) == 1:
    readCount.inc()
    if ch == 'M' or ch == 'm':
      break
    buffer.add(ch)

  # If we didn't find a terminator, return unknown event
  if readCount >= maxReadCount or (ch != 'M' and ch != 'm'):
    return Event(kind: Unknown)

  # Parse the SGR format: button;x;y
  let parts = buffer.split(';')
  if parts.len >= 3:
    try:
      let button_code = parseInt(parts[0])
      let x = parseInt(parts[1]) - 1 # SGR uses 1-based coordinates
      let y = parseInt(parts[2]) - 1

      let is_release = (ch == 'm')
      let is_wheel = (button_code and 0x40) != 0
      let button_info = button_code and 0x03

      var button: MouseButton
      var kind: MouseEventKind

      if is_wheel:
        # Wheel events: button_code 64 (0x40) = WheelUp, 65 (0x41) = WheelDown
        if (button_code and 0x01) != 0:
          button = WheelDown
        else:
          button = WheelUp
        kind = Press
      else:
        case button_info
        of 0:
          button = Left
        of 1:
          button = Middle
        of 2:
          button = Right
        else:
          button = Left

        if is_release:
          kind = Release
        elif (button_code and 0x20) != 0:
          kind = Drag
        else:
          kind = Press

      let modifiers = parseMouseModifiersSGR(button_code)

      return Event(
        kind: EventKind.Mouse,
        mouse: MouseEvent(kind: kind, button: button, x: x, y: y, modifiers: modifiers),
      )
    except ValueError:
      return Event(kind: Unknown)

  return Event(kind: Unknown)

# Advanced key reading with escape sequence support
proc readKey*(): Event =
  ## Read a key event (blocking mode)
  ## Raises IOError if unable to read from stdin
  try:
    var ch: char
    let bytesRead = tryRecover(
      proc(): int =
        stdin.readBuffer(addr ch, 1),
      fallback = 0,
    )

    if bytesRead == 1:
      case ch
      of '\r', '\n':
        return Event(kind: Key, key: KeyEvent(code: Enter, char: ch))
      of '\t':
        return Event(kind: Key, key: KeyEvent(code: Tab, char: ch))
      of ' ':
        return Event(kind: Key, key: KeyEvent(code: Space, char: ch))
      of '\x08', '\x7f': # Backspace or DEL
        return Event(kind: Key, key: KeyEvent(code: Backspace, char: ch))
      of '\x1b': # Escape or start of escape sequence
        # Try to read escape sequence in blocking mode
        var next: char
        if stdin.readBuffer(addr next, 1) == 1 and next == '[':
          var final: char
          if stdin.readBuffer(addr final, 1) == 1:
            case final
            of 'A': # Arrow Up
              return Event(kind: Key, key: KeyEvent(code: ArrowUp, char: '\0'))
            of 'B': # Arrow Down
              return Event(kind: Key, key: KeyEvent(code: ArrowDown, char: '\0'))
            of 'C': # Arrow Right
              return Event(kind: Key, key: KeyEvent(code: ArrowRight, char: '\0'))
            of 'D': # Arrow Left
              return Event(kind: Key, key: KeyEvent(code: ArrowLeft, char: '\0'))
            of 'H': # Home
              return Event(kind: Key, key: KeyEvent(code: Home, char: '\0'))
            of 'F': # End
              return Event(kind: Key, key: KeyEvent(code: End, char: '\0'))
            of 'Z': # Shift+Tab (BackTab)
              return Event(kind: Key, key: KeyEvent(code: BackTab, char: '\0'))
            of 'M': # Mouse event (X10 format)
              return parseMouseEventX10()
            of '<': # SGR mouse format
              return parseMouseEventSGR()
            of '1' .. '6':
              # Could be function key or special key with modifiers
              var seq: string = $final
              var nextChar: char
              if stdin.readBuffer(addr nextChar, 1) == 1:
                seq.add(nextChar)
                if nextChar == '~':
                  # Special keys with numeric codes
                  case final
                  of '1': # Home (alternative)
                    return Event(kind: Key, key: KeyEvent(code: Home, char: '\0'))
                  of '2': # Insert
                    return Event(kind: Key, key: KeyEvent(code: Insert, char: '\0'))
                  of '3': # Delete
                    return Event(kind: Key, key: KeyEvent(code: Delete, char: '\0'))
                  of '4': # End (alternative)
                    return Event(kind: Key, key: KeyEvent(code: End, char: '\0'))
                  of '5': # PageUp
                    return Event(kind: Key, key: KeyEvent(code: PageUp, char: '\0'))
                  of '6': # PageDown
                    return Event(kind: Key, key: KeyEvent(code: PageDown, char: '\0'))
                  else:
                    return Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
                elif nextChar == ';':
                  # Modified key sequence ESC[1;modifierX where X is the key
                  var modSeq: string = seq & nextChar
                  var modChar: char
                  if stdin.readBuffer(addr modChar, 1) == 1:
                    modSeq.add(modChar)
                    # Parse modifier (2=Shift, 3=Alt, 4=Shift+Alt, 5=Ctrl, 6=Ctrl+Shift, 7=Ctrl+Alt, 8=Ctrl+Shift+Alt)
                    let modifier = parseInt($modChar)
                    var modifiers: set[KeyModifier] = {}
                    if (modifier and 1) != 0:
                      modifiers.incl(Shift)
                    if (modifier and 2) != 0:
                      modifiers.incl(Alt)
                    if (modifier and 4) != 0:
                      modifiers.incl(Ctrl)

                    var keyChar: char
                    if stdin.readBuffer(addr keyChar, 1) == 1:
                      case keyChar
                      of 'A': # Modified Arrow Up
                        return Event(
                          kind: Key,
                          key: KeyEvent(code: ArrowUp, char: '\0', modifiers: modifiers),
                        )
                      of 'B': # Modified Arrow Down
                        return Event(
                          kind: Key,
                          key:
                            KeyEvent(code: ArrowDown, char: '\0', modifiers: modifiers),
                        )
                      of 'C': # Modified Arrow Right
                        return Event(
                          kind: Key,
                          key:
                            KeyEvent(code: ArrowRight, char: '\0', modifiers: modifiers),
                        )
                      of 'D': # Modified Arrow Left
                        return Event(
                          kind: Key,
                          key:
                            KeyEvent(code: ArrowLeft, char: '\0', modifiers: modifiers),
                        )
                      of 'H': # Modified Home
                        return Event(
                          kind: Key,
                          key: KeyEvent(code: Home, char: '\0', modifiers: modifiers),
                        )
                      of 'F': # Modified End
                        return Event(
                          kind: Key,
                          key: KeyEvent(code: End, char: '\0', modifiers: modifiers),
                        )
                      of '~':
                        # Modified special keys
                        case final
                        of '1': # Modified Home
                          return Event(
                            kind: Key,
                            key: KeyEvent(code: Home, char: '\0', modifiers: modifiers),
                          )
                        of '2': # Modified Insert
                          return Event(
                            kind: Key,
                            key:
                              KeyEvent(code: Insert, char: '\0', modifiers: modifiers),
                          )
                        of '3': # Modified Delete
                          return Event(
                            kind: Key,
                            key:
                              KeyEvent(code: Delete, char: '\0', modifiers: modifiers),
                          )
                        of '4': # Modified End
                          return Event(
                            kind: Key,
                            key: KeyEvent(code: End, char: '\0', modifiers: modifiers),
                          )
                        of '5': # Modified PageUp
                          return Event(
                            kind: Key,
                            key:
                              KeyEvent(code: PageUp, char: '\0', modifiers: modifiers),
                          )
                        of '6': # Modified PageDown
                          return Event(
                            kind: Key,
                            key:
                              KeyEvent(code: PageDown, char: '\0', modifiers: modifiers),
                          )
                        else:
                          return
                            Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
                      else:
                        return
                          Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
                else:
                  # Might be function key, but we'll skip for now
                  return Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
              else:
                return Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
            else:
              return Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
          else:
            return Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
        else:
          return Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
      of '\x03': # Ctrl+C
        return Event(kind: Quit)
      else:
        return Event(kind: Key, key: KeyEvent(code: Char, char: ch))
    else:
      return Event(kind: Unknown)
  except IOError:
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

# Non-blocking event reading
proc readKeyInput*(): Option[Event] =
  ## Read a single key input event (non-blocking)
  ## Returns none(Event) if no input is available or on error
  let flags = fcntl(STDIN_FILENO, F_GETFL, 0)
  if flags == -1:
    return none(Event)

  if fcntl(STDIN_FILENO, F_SETFL, flags or O_NONBLOCK) == -1:
    return none(Event)

  var ch: char
  let bytesRead = read(STDIN_FILENO, addr ch, 1)

  if bytesRead > 0:
    if ch == '\x1b':
      # Use select with timeout to detect escape sequences
      var readSet: TFdSet
      FD_ZERO(readSet)
      FD_SET(STDIN_FILENO, readSet)
      var timeout = Timeval(tv_sec: Time(0), tv_usec: Suseconds(20000)) # 20ms

      # If no more data available in 20ms, it's a standalone ESC
      if select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout) == 0:
        return some(Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b')))

      var next: char
      if read(STDIN_FILENO, addr next, 1) == 1 and next == '[':
        var final: char
        if read(STDIN_FILENO, addr final, 1) == 1:
          # Restore non-blocking mode
          discard fcntl(STDIN_FILENO, F_SETFL, flags or O_NONBLOCK)

          case final
          of 'A': # Arrow Up
            return some(Event(kind: Key, key: KeyEvent(code: ArrowUp, char: '\0')))
          of 'B': # Arrow Down
            return some(Event(kind: Key, key: KeyEvent(code: ArrowDown, char: '\0')))
          of 'C': # Arrow Right
            return some(Event(kind: Key, key: KeyEvent(code: ArrowRight, char: '\0')))
          of 'D': # Arrow Left
            return some(Event(kind: Key, key: KeyEvent(code: ArrowLeft, char: '\0')))
          of 'H': # Home
            return some(Event(kind: Key, key: KeyEvent(code: Home, char: '\0')))
          of 'F': # End
            return some(Event(kind: Key, key: KeyEvent(code: End, char: '\0')))
          of 'Z': # Shift+Tab (BackTab)
            return some(Event(kind: Key, key: KeyEvent(code: BackTab, char: '\0')))
          of 'M': # Mouse event (X10 format)
            let mouseEvent = parseMouseEventX10()
            return some(mouseEvent)
          of '<': # SGR mouse format
            let mouseEvent = parseMouseEventSGR()
            return some(mouseEvent)
          of '1' .. '6':
            # Could be function key or special key with modifiers
            var nextChar: char
            if read(STDIN_FILENO, addr nextChar, 1) == 1:
              if nextChar == '~':
                # Special keys with numeric codes
                case final
                of '1': # Home (alternative)
                  return some(Event(kind: Key, key: KeyEvent(code: Home, char: '\0')))
                of '2': # Insert
                  return some(Event(kind: Key, key: KeyEvent(code: Insert, char: '\0')))
                of '3': # Delete
                  return some(Event(kind: Key, key: KeyEvent(code: Delete, char: '\0')))
                of '4': # End (alternative)
                  return some(Event(kind: Key, key: KeyEvent(code: End, char: '\0')))
                of '5': # PageUp
                  return some(Event(kind: Key, key: KeyEvent(code: PageUp, char: '\0')))
                of '6': # PageDown
                  return
                    some(Event(kind: Key, key: KeyEvent(code: PageDown, char: '\0')))
                else:
                  return
                    some(Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b')))
              elif nextChar == ';':
                # Modified key sequence
                var modChar: char
                if read(STDIN_FILENO, addr modChar, 1) == 1:
                  # Parse modifier
                  let modifier = parseInt($modChar)
                  var modifiers: set[KeyModifier] = {}
                  if (modifier and 1) != 0:
                    modifiers.incl(Shift)
                  if (modifier and 2) != 0:
                    modifiers.incl(Alt)
                  if (modifier and 4) != 0:
                    modifiers.incl(Ctrl)

                  var keyChar: char
                  if read(STDIN_FILENO, addr keyChar, 1) == 1:
                    case keyChar
                    of 'A': # Modified Arrow Up
                      return some(
                        Event(
                          kind: Key,
                          key: KeyEvent(code: ArrowUp, char: '\0', modifiers: modifiers),
                        )
                      )
                    of 'B': # Modified Arrow Down
                      return some(
                        Event(
                          kind: Key,
                          key:
                            KeyEvent(code: ArrowDown, char: '\0', modifiers: modifiers),
                        )
                      )
                    of 'C': # Modified Arrow Right
                      return some(
                        Event(
                          kind: Key,
                          key:
                            KeyEvent(code: ArrowRight, char: '\0', modifiers: modifiers),
                        )
                      )
                    of 'D': # Modified Arrow Left
                      return some(
                        Event(
                          kind: Key,
                          key:
                            KeyEvent(code: ArrowLeft, char: '\0', modifiers: modifiers),
                        )
                      )
                    of 'H': # Modified Home
                      return some(
                        Event(
                          kind: Key,
                          key: KeyEvent(code: Home, char: '\0', modifiers: modifiers),
                        )
                      )
                    of 'F': # Modified End
                      return some(
                        Event(
                          kind: Key,
                          key: KeyEvent(code: End, char: '\0', modifiers: modifiers),
                        )
                      )
                    of '~':
                      # Modified special keys
                      case final
                      of '1': # Modified Home
                        return some(
                          Event(
                            kind: Key,
                            key: KeyEvent(code: Home, char: '\0', modifiers: modifiers),
                          )
                        )
                      of '2': # Modified Insert
                        return some(
                          Event(
                            kind: Key,
                            key:
                              KeyEvent(code: Insert, char: '\0', modifiers: modifiers),
                          )
                        )
                      of '3': # Modified Delete
                        return some(
                          Event(
                            kind: Key,
                            key:
                              KeyEvent(code: Delete, char: '\0', modifiers: modifiers),
                          )
                        )
                      of '4': # Modified End
                        return some(
                          Event(
                            kind: Key,
                            key: KeyEvent(code: End, char: '\0', modifiers: modifiers),
                          )
                        )
                      of '5': # Modified PageUp
                        return some(
                          Event(
                            kind: Key,
                            key:
                              KeyEvent(code: PageUp, char: '\0', modifiers: modifiers),
                          )
                        )
                      of '6': # Modified PageDown
                        return some(
                          Event(
                            kind: Key,
                            key:
                              KeyEvent(code: PageDown, char: '\0', modifiers: modifiers),
                          )
                        )
                      else:
                        return some(
                          Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
                        )
                    else:
                      return some(
                        Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b'))
                      )
                  else:
                    return
                      some(Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b')))
                else:
                  return
                    some(Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b')))
              else:
                # Might be function key, but we'll skip for now
                return some(Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b')))
            else:
              return some(Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b')))
          else:
            return some(Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b')))
        else:
          # Not an escape sequence we recognize
          return some(Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b')))
      else:
        # Not an escape sequence (no '[' after ESC)
        return some(Event(kind: Key, key: KeyEvent(code: Escape, char: '\x1b')))
    else:
      # Restore non-blocking mode
      discard fcntl(STDIN_FILENO, F_SETFL, flags)

      let event = Event(
        kind: EventKind.Key,
        key: KeyEvent(
          code:
            case ch
            of '\r', '\n':
              KeyCode.Enter
            of '\x08', '\x7f':
              KeyCode.Backspace
            of '\t':
              KeyCode.Tab
            of ' ':
              KeyCode.Space
            of '\x03':
              return some(Event(kind: Quit))
            else:
              KeyCode.Char,
          char: ch,
          modifiers: {},
        ),
      )
      return some(event)
  else:
    # Restore non-blocking mode
    discard fcntl(STDIN_FILENO, F_SETFL, flags)
    return none(Event)

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

# Initialize signal handling
proc initSignalHandling*() =
  ## Initialize signal handling for terminal resize
  signal(SIGWINCH, sigwinchHandler)

# Check for resize event
proc checkResize*(): Option[Event] =
  ## Check if a resize event occurred
  if resizeDetected:
    resizeDetected = false
    return some(Event(kind: Resize))
  return none(Event)

# Event polling with timeout
proc pollEvents*(timeoutMs: int): bool =
  ## Poll for available events with a timeout
  ## Returns true if events are available, false if timeout occurred
  ## Similar to crossterm::event::poll()
  var readSet: TFdSet
  FD_ZERO(readSet)
  FD_SET(STDIN_FILENO, readSet)

  var timeout = Timeval(
    tv_sec: Time(timeoutMs div 1000), tv_usec: Suseconds((timeoutMs mod 1000) * 1000)
  )

  # Use select to check if input is available with timeout
  let r = select(STDIN_FILENO + 1, addr readSet, nil, nil, addr timeout)
  return r > 0
