## Tabs Demo
##
## A example demonstrating tab widget functionality

import pkg/celina
import pkg/celina/widgets/[tabs, text]

proc main() =
  # Create text widgets for tab content
  let homeContent = newText(
    """Welcome to the Tabs Demo!

This is the Home tab. You can navigate between tabs using:
- Tab or Right Arrow: Next tab
- Shift+Tab or Left Arrow: Previous tab
- Number keys (1-4): Jump to specific tab

Try switching between tabs to see different content!""",
    style = style(White),
    wrap = WordWrap,
  )

  let aboutContent = newText(
    """About This Demo

This demo showcases the tab widget capabilities:
- Multiple tabs with different content
- Keyboard navigation support
- Border rendering with active tab highlighting
- Tab bar at the top of the content area
- Automatic tab width calculation
- Long tab titles are truncated with ellipsis

The tab widget is perfect for organizing content into
logical sections in your TUI applications.""",
    style = style(Cyan),
    wrap = WordWrap,
  )

  let featuresContent = newText(
    """Tab Widget Features

• Dynamic tab management (add/remove tabs)
• Customizable styling for active/inactive tabs
• Tab bar position (top or bottom)
• Optional border rendering
• Focus support for keyboard navigation
• Content area automatically adjusts to tab bar
• Tab width calculation with smart truncation
• Support for any widget as tab content
• Builder methods for easy customization
• Wrapping navigation (last tab → first tab)""",
    style = style(Green),
    wrap = WordWrap,
  )

  let codeContent = newText(
    """Example Code

// Creating a simple tab widget
let tabs = @[
  tab("Home", homeWidget),
  tab("Settings", settingsWidget),
  tab("Help", helpWidget),
]

let tabWidget = newTabs(
  tabs,
  activeIndex = 0,
  position = Top,
  showBorder = true,
)

// Navigation methods
tabWidget.nextTab()
tabWidget.prevTab()
tabWidget.setActiveTab(2)

// Dynamic tab management
tabWidget.addTab("New Tab", content)
tabWidget.removeTab(1)""",
    style = style(Yellow),
    wrap = NoWrap,
  )

  # Create tabs
  var tabsWidget = newTabs(
    @[
      tab("Home", homeContent),
      tab("About", aboutContent),
      tab("Features", featuresContent),
      tab("Code Example", codeContent),
    ],
    activeIndex = 0,
    position = Top,
    showBorder = true,
  )

  let config = AppConfig(
    title: "Tabs Demo", alternateScreen: true, mouseCapture: false, rawMode: true
  )

  var app = newApp(config)

  app.onEvent proc(event: Event): bool =
    case event.kind
    of EventKind.Key:
      case event.key.code
      of KeyCode.Char:
        case event.key.char
        of 'q', 'Q':
          return false
        of '1':
          tabsWidget.setActiveTab(0)
        of '2':
          tabsWidget.setActiveTab(1)
        of '3':
          tabsWidget.setActiveTab(2)
        of '4':
          tabsWidget.setActiveTab(3)
        else:
          discard
      of KeyCode.Tab:
        if event.key.modifiers == {Shift}:
          tabsWidget.prevTab()
        else:
          tabsWidget.nextTab()
      of KeyCode.ArrowLeft:
        tabsWidget.prevTab()
      of KeyCode.ArrowRight:
        tabsWidget.nextTab()
      of KeyCode.Escape:
        return false
      else:
        discard
    else:
      discard
    return true

  app.onRender proc(buf: var Buffer) =
    buf.clear()
    let area = buf.area

    # Render title
    buf.setString(
      area.width div 2 - 10,
      0,
      "TABS WIDGET DEMO",
      style(BrightWhite, modifiers = {Bold}),
    )

    # Render tabs widget (leave some space at top and bottom)
    let tabArea = rect(2, 2, area.width - 4, area.height - 4)
    tabsWidget.render(tabArea, buf)

    # Render help text at bottom
    let helpText = "Tab/→: Next | Shift+Tab/←: Previous | 1-4: Jump | q: Quit"
    buf.setString(
      area.width div 2 - helpText.len div 2,
      area.height - 1,
      helpText,
      style(BrightBlack),
    )

  app.run()

when isMainModule:
  main()
