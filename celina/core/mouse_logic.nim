## Mouse Event Parsing Logic
##
## This module contains pure business logic for parsing mouse events,
## shared between synchronous and asynchronous implementations.
##
## No I/O operations are performed here - only data transformation.
## This module defines its own types to avoid circular dependency with events.nim

type
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

  KeyModifier* = enum
    Ctrl
    Alt
    Shift

  MouseEventData* = object ## Parsed mouse event data (pure data structure)
    button*: MouseButton
    kind*: MouseEventKind
    x*, y*: int
    modifiers*: set[KeyModifier]

proc parseMouseModifiers*(buttonByte: int): set[KeyModifier] =
  ## Parse mouse modifiers from button byte
  ## Works for both X10 and SGR formats
  result = {}
  if (buttonByte and 0x04) != 0:
    result.incl(Shift)
  if (buttonByte and 0x08) != 0:
    result.incl(Alt)
  if (buttonByte and 0x10) != 0:
    result.incl(Ctrl)

proc parseMouseDataX10*(data: array[3, char]): MouseEventData =
  ## Parse X10 mouse format data (pure function, no I/O)
  ##
  ## Input: 3-byte array ``[button_byte, x_byte, y_byte]``
  ## Output: Structured mouse event data
  ##
  ## Example:
  ## ```nim
  ## let data: array[3, char] = [char(0x00), char(40), char(50)]
  ## let parsed = parseMouseDataX10(data)
  ## assert parsed.button == Left
  ## assert parsed.x == 7  # 40 - 33
  ## ```
  let buttonByte = data[0].ord
  let x = data[1].ord - 33 # X10 uses offset 33
  let y = data[2].ord - 33 # X10 uses offset 33

  let buttonInfo = buttonByte and 0x03
  let isDrag = (buttonByte and 0x20) != 0
  let isWheel = (buttonByte and 0x40) != 0

  var button: MouseButton
  var kind: MouseEventKind

  if isWheel:
    # X10 wheel events: bit 0 indicates direction
    if (buttonByte and 0x01) != 0:
      button = WheelDown
    else:
      button = WheelUp
    kind = Press
  else:
    case buttonInfo
    of 0:
      button = Left
    of 1:
      button = Middle
    of 2:
      button = Right
    else:
      button = Left

    if isDrag:
      kind = Drag
    elif (buttonByte and 0x03) == 3:
      kind = Release
    else:
      kind = Press

  let modifiers = parseMouseModifiers(buttonByte)

  MouseEventData(button: button, kind: kind, x: x, y: y, modifiers: modifiers)

proc parseMouseDataSGR*(
    buttonCode: int, x: int, y: int, isRelease: bool
): MouseEventData =
  ## Parse SGR mouse format data (pure function, no I/O)
  ##
  ## Input: button code, coordinates, and release flag
  ## Output: Structured mouse event data
  ##
  ## SGR format provides more precise information than X10
  let isWheel = (buttonCode and 0x40) != 0
  let buttonInfo = buttonCode and 0x03

  var button: MouseButton
  var kind: MouseEventKind

  if isWheel:
    # Wheel events: button_code 64 (0x40) = WheelUp, 65 (0x41) = WheelDown
    if (buttonCode and 0x01) != 0:
      button = WheelDown
    else:
      button = WheelUp
    kind = Press
  else:
    case buttonInfo
    of 0:
      button = Left
    of 1:
      button = Middle
    of 2:
      button = Right
    else:
      button = Left

    if isRelease:
      kind = Release
    elif (buttonCode and 0x20) != 0:
      kind = Drag
    else:
      kind = Press

  let modifiers = parseMouseModifiers(buttonCode)

  MouseEventData(button: button, kind: kind, x: x, y: y, modifiers: modifiers)

# Note: Event conversion is done in events.nim to avoid circular dependency
