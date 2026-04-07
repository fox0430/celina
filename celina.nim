## Celina - A CLI library for Nim inspired by Ratatui.
##
## A powerful Terminal User Interface library for Nim, inspired by Ratatui.
## Provides high-performance, type-safe components for building interactive
## terminal applications with both synchronous and asynchronous support.
##
## Basic Usage:
## ```nim
## import pkg/celina
##
## proc main() =
##   var app = newApp()
##   app.run()
## ```
##
## Async Usage (requires `-d:asyncBackend=asyncdispatch` or `-d:asyncBackend=chronos`):
## ```nim
## import pkg/celina
##
## proc main() {.async.} =
##   var app = newAsyncApp()
##   await app.runAsync()
## ```
##
## Modules
## =======
##
## Core
## ----
## - `app <celina/core/app.html>`_ — Application lifecycle and event loop
## - `buffer <celina/core/buffer.html>`_ — Screen buffer for managing terminal content
## - `colors <celina/core/colors.html>`_ — Color and style definitions
## - `cursor <celina/core/cursor.html>`_ — Cursor control and state management
## - `errors <celina/core/errors.html>`_ — Error types
## - `events <celina/core/events.html>`_ — Keyboard and mouse event handling
## - `fps <celina/core/fps.html>`_ — Frame rate monitoring
## - `geometry <celina/core/geometry.html>`_ — Geometric types for positioning and sizing
## - `layout <celina/core/layout.html>`_ — Constraint-based layout system
## - `renderer <celina/core/renderer.html>`_ — Differential rendering and terminal output
## - `terminal <celina/core/terminal.html>`_ — Terminal control using ANSI escape sequences
## - `terminal_common <celina/core/terminal_common.html>`_ — Shared terminal algorithms and utilities
## - `windows <celina/core/windows.html>`_ — Window management with overlapping and focus support
##
## Async
## -----
## - `async_backend <celina/async/async_backend.html>`_ — Async backend configuration (asyncdispatch/chronos)
## - `async_app <celina/async/async_app.html>`_ — Async application framework and event loop
## - `async_buffer <celina/async/async_buffer.html>`_ — Async-safe buffer implementation
## - `async_events <celina/async/async_events.html>`_ — Async keyboard and mouse event handling
## - `async_terminal <celina/async/async_terminal.html>`_ — Async terminal I/O interface
##
## Widgets
## -------
## - `base <celina/widgets/base.html>`_ — Base widget traits and types
## - `button <celina/widgets/button.html>`_ — Interactive button widget
## - `input <celina/widgets/input.html>`_ — Text input widget with cursor and selection
## - `list <celina/widgets/list.html>`_ — List widget with scrolling and selection
## - `progress <celina/widgets/progress.html>`_ — Progress bar widget
## - `table <celina/widgets/table.html>`_ — Table widget for structured data
## - `tabs <celina/widgets/tabs.html>`_ — Tabbed interface widget
## - `text <celina/widgets/text.html>`_ — Text rendering widget with alignment and styling

import std/unicode

import
  celina/core/[
    geometry, colors, buffer, events, terminal, layout, errors, terminal_common, app,
    renderer, cursor, fps, windows,
  ]

import celina/async/async_backend

export unicode

export
  geometry, colors, buffer, events, layout, terminal, errors, terminal_common, app,
  renderer, cursor, fps, windows

export async_backend, hasAsyncSupport, hasChronos, hasAsyncDispatch

when hasAsyncSupport:
  import celina/async/[async_app, async_terminal, async_buffer, async_events]

  export async_app, async_terminal, async_buffer, async_events
