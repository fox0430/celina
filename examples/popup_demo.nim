## Popup and Tooltip Demo Example
##
## This example demonstrates popup windows and tooltips in Celina.
## Use keyboard navigation to explore different popup features:
## - Arrow keys to navigate between items
## - Space to show/hide popups
## - Enter to toggle detailed information
## - Tab to switch between different demo sections

import ../src/celina
import ../src/widgets/popup
import std/strformat

type
  DemoItem = object
    name: string
    description: string
    details: seq[string]
    x, y: int
    hasPopup: bool
    hasTooltip: bool

  PopupDemoApp = object
    currentSection: int # 0 = colors, 1 = widgets, 2 = actions
    currentItem: int
    showingPopup: bool
    showingTooltip: bool
    popup: Popup
    tooltip: Tooltip
    colorItems: seq[DemoItem]
    widgetItems: seq[DemoItem]
    actionItems: seq[DemoItem]

proc initDemoItems(): (seq[DemoItem], seq[DemoItem], seq[DemoItem]) =
  ## Initialize demo items for each section

  let colorItems =
    @[
      DemoItem(
        name: "Red",
        description: "Primary color",
        details:
          @[
            "RGB: 255, 0, 0", "Hex: #FF0000", "Warm color",
            "Associated with passion, energy",
          ],
        x: 5,
        y: 3,
        hasPopup: true,
        hasTooltip: true,
      ),
      DemoItem(
        name: "Blue",
        description: "Cool primary color",
        details:
          @[
            "RGB: 0, 0, 255", "Hex: #0000FF", "Cool color",
            "Associated with calm, trust",
          ],
        x: 15,
        y: 3,
        hasPopup: true,
        hasTooltip: true,
      ),
      DemoItem(
        name: "Green",
        description: "Nature's color",
        details:
          @[
            "RGB: 0, 255, 0", "Hex: #00FF00", "Secondary color",
            "Associated with growth, harmony",
          ],
        x: 25,
        y: 3,
        hasPopup: true,
        hasTooltip: true,
      ),
      DemoItem(
        name: "Purple",
        description: "Royal color",
        details:
          @[
            "RGB: 128, 0, 128", "Hex: #800080", "Mix of red and blue",
            "Associated with luxury, mystery",
          ],
        x: 35,
        y: 3,
        hasPopup: true,
        hasTooltip: true,
      ),
    ]

  let widgetItems =
    @[
      DemoItem(
        name: "Button",
        description: "Interactive element",
        details:
          @[
            "Clickable UI element", "Can trigger actions",
            "Usually has visual feedback", "Common in forms and menus",
          ],
        x: 5,
        y: 8,
        hasPopup: true,
        hasTooltip: true,
      ),
      DemoItem(
        name: "TextBox",
        description: "Text input field",
        details:
          @[
            "Accepts user text input", "Can be single or multi-line",
            "Often has validation", "Essential for forms",
          ],
        x: 20,
        y: 8,
        hasPopup: true,
        hasTooltip: true,
      ),
      DemoItem(
        name: "List",
        description: "Item collection",
        details:
          @[
            "Displays multiple items", "Can be scrollable", "Supports selection",
            "Good for large datasets",
          ],
        x: 35,
        y: 8,
        hasPopup: true,
        hasTooltip: true,
      ),
    ]

  let actionItems =
    @[
      DemoItem(
        name: "Save",
        description: "Persist data",
        details:
          @[
            "Writes data to storage", "Prevents data loss", "Usually has confirmation",
            "Critical for user work",
          ],
        x: 5,
        y: 13,
        hasPopup: true,
        hasTooltip: true,
      ),
      DemoItem(
        name: "Load",
        description: "Retrieve data",
        details:
          @[
            "Reads data from storage", "Restores previous state",
            "May have file selection", "Enables continuity",
          ],
        x: 20,
        y: 13,
        hasPopup: true,
        hasTooltip: true,
      ),
      DemoItem(
        name: "Export",
        description: "Data conversion",
        details:
          @[
            "Converts to external format", "Enables data sharing",
            "Multiple format options", "Useful for reports",
          ],
        x: 35,
        y: 13,
        hasPopup: true,
        hasTooltip: true,
      ),
    ]

  (colorItems, widgetItems, actionItems)

proc getCurrentItems(app: PopupDemoApp): seq[DemoItem] =
  ## Get current section's items
  case app.currentSection
  of 0:
    app.colorItems
  of 1:
    app.widgetItems
  of 2:
    app.actionItems
  else:
    @[]

proc getCurrentItem(app: PopupDemoApp): DemoItem =
  ## Get currently selected item
  let items = app.getCurrentItems()
  if app.currentItem < items.len:
    items[app.currentItem]
  else:
    DemoItem()

proc main() =
  let (colorItems, widgetItems, actionItems) = initDemoItems()

  # Create popup and tooltip separately to avoid named parameter issues
  let popup = newPopup(@[], "", defaultPopupStyle(), 20, 40)
  let tooltip = newTooltip("", defaultTooltipStyle())

  var appState = PopupDemoApp(
    currentSection: 0,
    currentItem: 0,
    showingPopup: false,
    showingTooltip: false,
    popup: popup,
    tooltip: tooltip,
    colorItems: colorItems,
    widgetItems: widgetItems,
    actionItems: actionItems,
  )

  quickRun(
    eventHandler = proc(event: Event): bool =
      let currentItems = appState.getCurrentItems()

      case event.kind
      of EventKind.Key:
        case event.key.code
        of KeyCode.Char:
          case event.key.char
          of 'q':
            return false
          of ' ': # Space - toggle popup
            if appState.showingPopup:
              appState.popup.hide()
              appState.showingPopup = false
            else:
              let item = appState.getCurrentItem()
              if item.hasPopup:
                appState.popup.setContent(item.details, item.name)
                appState.popup.show(item.x + item.name.len div 2, item.y, Below)
                appState.showingPopup = true
          of 't': # Toggle tooltip
            if appState.showingTooltip:
              appState.tooltip.hide()
              appState.showingTooltip = false
            else:
              let item = appState.getCurrentItem()
              if item.hasTooltip:
                appState.tooltip.show(item.x, item.y - 1, item.description)
                appState.showingTooltip = true
          else:
            discard
        of KeyCode.Tab: # Switch sections
          appState.currentSection = (appState.currentSection + 1) mod 3
          appState.currentItem = 0
          appState.popup.hide()
          appState.tooltip.hide()
          appState.showingPopup = false
          appState.showingTooltip = false
        of KeyCode.Escape:
          return false
        of KeyCode.ArrowLeft:
          if appState.currentItem > 0:
            appState.currentItem -= 1
            appState.popup.hide()
            appState.tooltip.hide()
            appState.showingPopup = false
            appState.showingTooltip = false
        of KeyCode.ArrowRight:
          if appState.currentItem < currentItems.len - 1:
            appState.currentItem += 1
            appState.popup.hide()
            appState.tooltip.hide()
            appState.showingPopup = false
            appState.showingTooltip = false
        of KeyCode.Enter: # Show detailed popup at center
          let item = appState.getCurrentItem()
          if item.hasPopup:
            let detailedContent =
              @[
                &"Name: {item.name}", &"Description: {item.description}", "", "Details:"
              ] & item.details
            appState.popup.setContent(detailedContent, &"Information: {item.name}")
            appState.popup.show(0, 0, Center) # Center position
            appState.showingPopup = true
        else:
          discard
      else:
        discard
      return true,
    renderHandler = proc(buffer: var Buffer) =
      buffer.clear()

      let area = buffer.area

      # Title
      let title = "Popup and Tooltip Demo"
      buffer.setString(
        area.width div 2 - title.len div 2,
        1,
        title,
        style(Color.White, modifiers = {Bold, Underline}),
      )

      # Section tabs
      let sections = @["Colors", "Widgets", "Actions"]
      var tabX = 5
      for i, section in sections:
        let tabStyle =
          if i == appState.currentSection:
            style(Color.Black, Color.White, {Bold})
          else:
            style(Color.White, modifiers = {})

        buffer.setString(tabX, 2, &" {section} ", tabStyle)
        tabX += section.len + 3

      # Current section items
      let currentItems = appState.getCurrentItems()
      for i, item in currentItems:
        let itemStyle =
          if i == appState.currentItem:
            style(Color.Black, Color.Yellow, {Bold}) # Highlighted
          else:
            case appState.currentSection
            of 0:
              style(Color.Red, modifiers = {Bold})
            # Colors section
            of 1:
              style(Color.Green, modifiers = {Bold})
            # Widgets section  
            of 2:
              style(Color.Blue, modifiers = {Bold})
            # Actions section
            else:
              style(Color.White)

        buffer.setString(item.x, item.y, item.name, itemStyle)

      # Selection indicator
      if currentItems.len > 0:
        let currentItem = currentItems[appState.currentItem]
        buffer.setString(
          currentItem.x - 2,
          currentItem.y,
          "->",
          style(Color.BrightYellow, modifiers = {Bold}),
        )

      # Instructions
      let instructions = [
        "Navigation:", "Tab: Switch sections", "←/→: Navigate items",
        "Space: Show/hide popup", "Enter: Detailed view", "t: Toggle tooltip",
        "q/ESC: Quit",
      ]

      for i, instruction in instructions:
        let instrStyle =
          if i == 0:
            style(Color.Cyan, modifiers = {Bold})
          else:
            style(Color.BrightBlack)
        buffer.setString(2, area.height - instructions.len + i, instruction, instrStyle)

      # Status line
      let currentItem = appState.getCurrentItem()
      if currentItem.name.len > 0:
        let status = &"Selected: {currentItem.name} - {currentItem.description}"
        buffer.setString(
          2, area.height - instructions.len - 2, status, style(Color.White)
        )

      # Render popup and tooltip (these render on top)
      appState.popup.render(area, buffer)
      appState.tooltip.render(area, buffer),
  )

when isMainModule:
  echo "Starting Popup Demo..."
  echo "Use Tab to switch sections, arrow keys to navigate, Space for popups"
  echo "Press 'q' or ESC to quit"
  main()
