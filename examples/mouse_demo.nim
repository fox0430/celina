## Mouse Support Demo
##
## This example demonstrates how to handle mouse events
## Features:
## - Left/right/middle mouse button clicks
## - Mouse wheel scrolling
## - Mouse movement and dragging
## - Visual feedback for all mouse interactions

import pkg/celina

import std/[strformat, strutils]

type MouseDemo = ref object
  lastMousePos: Position
  clickCount: int
  dragStart: Position
  isDragging: bool
  wheelOffset: int
  messages: seq[string]

proc newMouseDemo(): MouseDemo =
  MouseDemo(
    lastMousePos: pos(0, 0),
    clickCount: 0,
    dragStart: pos(0, 0),
    isDragging: false,
    wheelOffset: 0,
    messages: @[],
  )

proc addMessage(demo: MouseDemo, msg: string) =
  demo.messages.add(msg)
  # Keep only the last 3 messages for better performance
  if demo.messages.len > 3:
    demo.messages = demo.messages[1 ..^ 1]

proc formatModifiers(modifiers: set[KeyModifier]): string =
  var parts: seq[string]
  if Ctrl in modifiers:
    parts.add("Ctrl")
  if Shift in modifiers:
    parts.add("Shift")
  if Alt in modifiers:
    parts.add("Alt")
  if parts.len > 0:
    return parts.join("+") & "+"
  return ""

proc handleMouseEvent(demo: MouseDemo, mouse: MouseEvent) =
  let modStr = formatModifiers(mouse.modifiers)

  case mouse.kind
  of Press:
    demo.lastMousePos = pos(mouse.x, mouse.y)
    case mouse.button
    of Left:
      demo.clickCount.inc()
      demo.dragStart = pos(mouse.x, mouse.y)
      demo.addMessage(
        &"Left click #{demo.clickCount} at ({mouse.x}, {mouse.y}) {modStr}"
      )
    of Right:
      demo.addMessage(&"Right click at ({mouse.x}, {mouse.y}) {modStr}")
    of Middle:
      demo.addMessage(&"Middle click at ({mouse.x}, {mouse.y}) {modStr}")
    of WheelUp:
      demo.wheelOffset.inc()
      demo.addMessage(
        &"Wheel up at ({mouse.x}, {mouse.y}) {modStr}(offset: {demo.wheelOffset})"
      )
    of WheelDown:
      demo.wheelOffset.dec()
      demo.addMessage(
        &"Wheel down at ({mouse.x}, {mouse.y}) {modStr}(offset: {demo.wheelOffset})"
      )
  of Release:
    demo.lastMousePos = pos(mouse.x, mouse.y)
    if demo.isDragging:
      demo.isDragging = false
      demo.addMessage(&"Drag ended at ({mouse.x}, {mouse.y}) {modStr}")
    else:
      demo.addMessage(&"Released {mouse.button} at ({mouse.x}, {mouse.y}) {modStr}")
  of Move:
    # Always update mouse position for smooth tracking
    demo.lastMousePos = pos(mouse.x, mouse.y)
  of Drag:
    # Always update position for smooth dragging
    demo.lastMousePos = pos(mouse.x, mouse.y)

    if not demo.isDragging:
      demo.isDragging = true
      demo.addMessage(
        &"Drag started from ({demo.dragStart.x}, {demo.dragStart.y}) {modStr}"
      )
    # Reduce drag event logging but keep it more responsive
    demo.addMessage(&"Dragging to ({mouse.x}, {mouse.y}) {modStr}")

proc renderDemo(demo: MouseDemo, buffer: var Buffer) =
  buffer.clear()

  let area = buffer.area
  let centerX = area.width div 2

  # Title
  let title = "🖱️  Celina Mouse Support Demo"
  buffer.setString(
    centerX - title.len div 2,
    1,
    title,
    Style(fg: rgb(100, 200, 255), modifiers: {Bold}),
  )

  # Instructions
  let instructions = [
    "Try the following interactions:", "• Click left/right/middle mouse buttons",
    "• Scroll with mouse wheel", "• Drag with left mouse button",
    "• Hold Ctrl/Shift/Alt while clicking", "• Move mouse around the screen", "",
    "Press 'q' or Ctrl+C to quit",
  ]

  for i, instruction in instructions:
    buffer.setString(2, 4 + i, instruction, defaultStyle())

  # Current mouse position indicator
  let mouseInfo =
    &"Current mouse position: ({demo.lastMousePos.x}, {demo.lastMousePos.y})"
  buffer.setString(2, 14, mouseInfo, Style(fg: rgb(255, 255, 0), modifiers: {Bold}))

  # Stats
  let stats = [
    &"Total clicks: {demo.clickCount}",
    &"Wheel offset: {demo.wheelOffset}",
    &"Is dragging: {demo.isDragging}",
  ]

  for i, stat in stats:
    buffer.setString(2, 16 + i, stat, Style(fg: rgb(0, 255, 100)))

  # Recent messages
  buffer.setString(
    2, 20, "Recent mouse events:", Style(fg: rgb(255, 200, 100), modifiers: {Bold})
  )

  for i, msg in demo.messages:
    let y = 21 + i
    if y < area.height - 1:
      buffer.setString(4, y, &"• {msg}", defaultStyle())

  # Draw a simple crosshair at mouse position (if within bounds)
  if demo.lastMousePos.x >= 0 and demo.lastMousePos.x < area.width and
      demo.lastMousePos.y >= 0 and demo.lastMousePos.y < area.height:
    # Center point only (lighter crosshair for better performance)

    buffer.setString(
      demo.lastMousePos.x,
      demo.lastMousePos.y - 1,
      "|",
      Style(fg: rgb(255, 0, 0), modifiers: {Bold}),
    )
    buffer.setString(
      demo.lastMousePos.x - 2,
      demo.lastMousePos.y,
      "--+--",
      Style(fg: rgb(255, 0, 0), modifiers: {Bold}),
    )
    buffer.setString(
      demo.lastMousePos.x,
      demo.lastMousePos.y + 1,
      "|",
      Style(fg: rgb(255, 0, 0), modifiers: {Bold}),
    )

proc main() =
  let demo = newMouseDemo()

  let config = AppConfig(
    title: "Mouse Demo",
    alternateScreen: true,
    mouseCapture: true, # Enable mouse support!
    rawMode: true,
    windowMode: false,
  )

  var app = newApp(config)

  app.onEvent proc(event: Event): bool =
    case event.kind
    of Key:
      # Handle keyboard events
      if event.key.code == Char and event.key.char == 'q':
        return false # Quit on 'q'
      elif event.key.code == Escape:
        return false # Quit on Escape
    of Mouse:
      # Handle mouse events
      demo.handleMouseEvent(event.mouse)
    of Quit:
      return false # Quit on Ctrl+C
    else:
      discard

    return true # Continue running

  app.onRender proc(buffer: var Buffer) =
    demo.renderDemo(buffer)

  try:
    app.run(config)
  except TerminalError as e:
    echo "Terminal error: ", e.msg
  except CatchableError as e:
    echo "Error: ", e.msg

when isMainModule:
  main()
