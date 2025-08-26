# Celina

A CLI library in Nim, inspired by Ratatui.

Still under development

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
- **[`color_demo.nim`](examples/color_demo.nim)**: 24-bit RGB color support demonstration with gradients, palettes, and animations
- **[`cursor_demo.nim`](examples/cursor_demo.nim)**: Terminal cursor control including position, visibility, and style management
- **[`mouse_demo.nim`](examples/mouse_demo.nim)**: Mouse event handling including clicks, drag, wheel scroll, and movement detection
- **[`window_demo.nim`](examples/window_demo.nim)**: Window management system with multiple overlapping windows, focus control, and modal dialogs
- **[`async_file_manager.nim`](examples/async_file_manager.nim)**: Real-world file manager implementation with async I/O, multi-window UI, and vim-style navigation

## Documentation

https://fox0430.github.io/celina/celina.html
