## Celina CLI Library
## ==================
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
##
## when isMainModule:
##   main()
## ```
##
## Async Usage (requires Chronos and `-d:asyncBackend=chronos`):
## ```nim
## import pkg/celina
##
## proc main() {.async.} =
##   var app = newAsyncApp()
##   await app.runAsync()
##
## when isMainModule:
##   waitFor main()
## ```

import std/[unicode, strformat]

import
  celina/core/[
    geometry, colors, buffer, events, terminal, layout, errors, resources,
    terminal_common, app, renderer, cursor, fps,
  ]

import celina/async/async_backend

export unicode

export
  geometry, colors, buffer, events, layout, terminal, errors, resources,
  terminal_common, app, renderer, cursor, fps

export windows, text, base, button, input, list, table

export async_backend, hasAsyncSupport, hasChronos, hasAsyncDispatch

# ============================================================================
# Convenience Functions
# ============================================================================

proc quickRun*(
    eventHandler: proc(event: Event): bool,
    renderHandler: proc(buffer: var Buffer),
    config: AppConfig = AppConfig(
      title: "Celina App",
      alternateScreen: true,
      mouseCapture: false,
      rawMode: true,
      windowMode: false,
      targetFps: 60,
    ),
) =
  ## Quick way to run a simple CLI application
  ##
  ## Example:
  ## ```nim
  ## quickRun(
  ##   eventHandler = proc(event: Event): bool =
  ##     case event.kind
  ##     of EventKind.Key:
  ##       if event.key.code == KeyCode.Char and event.key.char == 'q':
  ##         return false
  ##     else: discard
  ##     return true,
  ##
  ##   renderHandler = proc(buffer: var Buffer) =
  ##     buffer.clear()
  ##     let area = buffer.area
  ##     buffer.setString(10, area.height div 2, "Press 'q' to quit", defaultStyle())
  ## )
  ## ```
  var app = newApp(config)
  app.onEvent(eventHandler)
  app.onRender(renderHandler)
  app.run()

# ============================================================================
# Async API (when Chronos is available)
# ============================================================================

when hasAsyncSupport and hasChronos:
  import celina/async/[async_app, async_terminal, async_buffer, async_events]

  export async_app, async_terminal, async_buffer, async_events

  # Utility function to convert async to sync
  proc asyncToSync*[T](asyncProc: Future[T]): T =
    ## Convert async procedure to synchronous (blocks until complete)
    return waitFor asyncProc

# ============================================================================
# Version Information
# ============================================================================

const
  celinaVersionMajor* = 0
  celinaVersionMinor* = 1
  celinaVersionPatch* = 0

proc versionStr(): string {.compileTime.} =
  return fmt"{celinaVersionMajor}.{celinaVersionMinor}.{celinaVersionPatch}"

proc celinaVersion*(): string =
  ## Get the library version string
  return versionStr()
