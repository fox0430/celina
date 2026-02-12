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

import std/unicode

import
  celina/core/[
    geometry, colors, buffer, events, terminal, layout, errors, resources,
    terminal_common, app, renderer, cursor, fps, windows,
  ]

import celina/async/async_backend

export unicode

export
  geometry, colors, buffer, events, layout, terminal, errors, resources,
  terminal_common, app, renderer, cursor, fps, windows

export async_backend, hasAsyncSupport, hasChronos, hasAsyncDispatch

when hasAsyncSupport:
  import celina/async/[async_app, async_terminal, async_buffer, async_events]

  export async_app, async_terminal, async_buffer, async_events
