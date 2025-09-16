# Celina

A CLI library in Nim, inspired by Ratatui.

## Features

- High-performance terminal rendering with buffer-based system
- Constraint-based responsive layout system  
- Full Unicode support with proper display width handling
- Event-driven architecture for keyboard and mouse input
- Widget system for building interactive components
- Async programming support with [asyncdispatch](https://nim-lang.org/docs/asyncdispatch.html) or [Chronos](https://github.com/status-im/nim-chronos)

## Platform Support

- Unix like operation system (Linux, macOS, etc)

## Install

```bash
nimble install celina
```

## Examples

Check out the [`examples/`](examples/) directory for sample applications demonstrating various features:

- **[`hello_world.nim`](examples/hello_world.nim)**: Basic application displaying "Hello, World!" with simple event handling
- **[`async_hello_world.nim`](examples/async_hello_world.nim)**: Asynchronous version using Chronos
- **[`button_demo.nim`](examples/button_demo.nim)**: Interactive button widget, various styles, and click handling
- **[`color_demo.nim`](examples/color_demo.nim)**: 24-bit RGB color support demonstration with gradients, palettes, and animations
- **[`cursor_demo.nim`](examples/cursor_demo.nim)**: Terminal cursor control including position, visibility, and style management
- **[`input_demo.nim`](examples/input_demo.nim)**: Text input widgets including password fields, borders, search, and real-time value display
- **[`list_demo.nim`](examples/list_demo.nim)**: List widget with single/multiple selection modes, keyboard/mouse navigation, scrolling, and custom styling
- **[`mouse_demo.nim`](examples/mouse_demo.nim)**: Mouse event handling including clicks, drag, wheel scroll, and movement detection
- **[`progress_demo.nim`](examples/progress_demo.nim)**: Progress bar widgets with various styles, customizable colors, bracket display options, and animated demonstrations
- **[`table_demo.nim`](examples/table_demo.nim)**: Table widget with custom column widths, multiple selection modes, border styles, vim-like navigation, and scrolling support for large datasets
- **[`tabs_demo.nim`](examples/tabs_demo.nim)**: Tab widget demonstration with multiple tabs, keyboard navigation, dynamic tab management, and content switching
- **[`window_demo.nim`](examples/window_demo.nim)**: Window management system with multiple overlapping windows, focus control, and modal dialogs
- **[`async_file_manager.nim`](examples/async_file_manager.nim)**: Real-world file manager implementation with async I/O, multi-window UI, and vim-style navigation

## Documentation

## Core
https://fox0430.github.io/celina/celina.html

## Widgets

### Base
https://fox0430.github.io/celina/widgets/base.html

### Button
https://fox0430.github.io/celina/widgets/button.html

### Input
https://fox0430.github.io/celina/widgets/input.html

### List
https://fox0430.github.io/celina/widgets/list.html

### Progress
https://fox0430.github.io/celina/widgets/progress.html

### Table
https://fox0430.github.io/celina/widgets/table.html

### Tabs
https://fox0430.github.io/celina/widgets/tabs.html

### Text
https://fox0430.github.io/celina/widgets/text.html
