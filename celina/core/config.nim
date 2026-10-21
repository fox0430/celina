## Application Configuration
##
## This module provides shared configuration types for both
## synchronous and asynchronous application modes.

import std/strutils

type
  ViewportKind* = enum
    vkFullscreen ## The whole screen (default)
    vkInline ## `height` rows from the cursor row, left in the scrollback on exit

  Viewport* = object ## Where the app draws
    case kind*: ViewportKind
    of vkFullscreen:
      discard
    of vkInline:
      height*: int ## Rows, at least 1; capped at the terminal height

type AppConfig* = object ## Application configuration options
  title*: string ## Application title (for window managers)
  alternateScreen*: bool ## Use alternate screen buffer; inline viewports ignore it
  mouseCapture*: bool ## Enable mouse event capture
  bracketedPaste*: bool ## Enable bracketed paste mode for paste detection
  focusEvents*: bool ## Enable focus event reporting (FocusIn/FocusOut)
  rawMode*: bool ## Enable raw terminal mode (no line buffering)
  windowMode*: bool ## Enable window management
  targetFps*: int ## Target FPS for rendering (default: 60)
  installSignalHandler*: bool
    ## When true and the chronos backend is active on a POSIX platform,
    ## runAsync installs SIGINT/SIGTERM handlers that trigger
    ## shutdownAsync, so runAsync usually ends with `CancelledError`
    ## after restoring the terminal (it can also return normally; see
    ## `stopSignal`). `exitIfStoppedBySignal` passes the signal on. Ignored
    ## under the sync App, asyncdispatch, and `asyncBackend=none` builds,
    ## and on non-POSIX platforms (e.g. Windows) where the signal-handling
    ## code is not compiled because chronos signal APIs are unavailable.
    ## The sync `App` uses `installDefaultCrashGuard` (an explicit function
    ## call) instead of a config flag for Ctrl-C handling.
  viewport*: Viewport
    ## Fullscreen (default), or inline: `height` rows from the cursor row (the
    ## next row if the cursor is not in column 0), left in the scrollback on
    ## exit with the cursor below them. After a quit, inline runs the render
    ## handler once more unless the last tick drew, so that frame shows the
    ## last events. Inline asks the terminal for the cursor position at start
    ## and on resize (in `rawMode` only), waiting up to 2 s; without an answer
    ## it uses the bottom rows and stops asking. Resizes are best effort: lines
    ## the terminal reflows can stay behind, and without an answer a resize can
    ## leave the old rows or erase the lines just above the viewport. Lay out
    ## by `buffer.area`, not `getTerminalSize`. Not supported inline yet:
    ## `mouseCapture`, `windowMode` and `suspend`; `emergencyRestore` may leave
    ## the cursor in the viewport.

proc `==`*(a, b: Viewport): bool =
  ## Needed because `Viewport` is a case object: the generic `==` for objects
  ## does not compile for one, nor for an `AppConfig` that holds it.
  a.kind == b.kind and (a.kind == vkFullscreen or a.height == b.height)

proc `$`*(viewport: Viewport): string =
  ## String representation of Viewport for debugging
  case viewport.kind
  of vkFullscreen:
    "fullscreen"
  of vkInline:
    "inline(" & $viewport.height & ")"

proc `$`*(config: AppConfig): string =
  ## String representation of AppConfig for debugging
  var parts: seq[string] = @[]
  parts.add("title: \"" & config.title & "\"")
  if config.alternateScreen:
    parts.add("alternateScreen")
  if config.mouseCapture:
    parts.add("mouseCapture")
  if config.bracketedPaste:
    parts.add("bracketedPaste")
  if config.focusEvents:
    parts.add("focusEvents")
  if config.rawMode:
    parts.add("rawMode")
  if config.windowMode:
    parts.add("windowMode")
  if config.installSignalHandler:
    parts.add("installSignalHandler")
  parts.add("targetFps: " & $config.targetFps)
  if config.viewport.kind != vkFullscreen:
    parts.add("viewport: " & $config.viewport)
  "AppConfig(" & parts.join(", ") & ")"

const DefaultAppConfig* = AppConfig(
  title: "Celina App",
  alternateScreen: true,
  mouseCapture: false,
  bracketedPaste: false,
  focusEvents: false,
  rawMode: true,
  windowMode: false,
  targetFps: 60,
  installSignalHandler: false,
  viewport: Viewport(kind: vkFullscreen),
)

proc defaultAppConfig*(): AppConfig {.inline.} =
  ## Create a default application configuration
  DefaultAppConfig

proc withTitle*(config: AppConfig, title: string): AppConfig {.inline.} =
  ## Return a new config with the specified title
  result = config
  result.title = title

proc withAlternateScreen*(config: AppConfig, enabled: bool): AppConfig {.inline.} =
  ## Return a new config with alternate screen setting
  result = config
  result.alternateScreen = enabled

proc withMouseCapture*(config: AppConfig, enabled: bool): AppConfig {.inline.} =
  ## Return a new config with mouse capture setting
  result = config
  result.mouseCapture = enabled

proc withBracketedPaste*(config: AppConfig, enabled: bool): AppConfig {.inline.} =
  ## Return a new config with bracketed paste setting
  result = config
  result.bracketedPaste = enabled

proc withFocusEvents*(config: AppConfig, enabled: bool): AppConfig {.inline.} =
  ## Return a new config with focus events setting
  result = config
  result.focusEvents = enabled

proc withRawMode*(config: AppConfig, enabled: bool): AppConfig {.inline.} =
  ## Return a new config with raw mode setting
  result = config
  result.rawMode = enabled

proc withWindowMode*(config: AppConfig, enabled: bool): AppConfig {.inline.} =
  ## Return a new config with window mode setting
  result = config
  result.windowMode = enabled

proc withTargetFps*(config: AppConfig, fps: int): AppConfig {.inline.} =
  ## Return a new config with target FPS setting
  result = config
  result.targetFps = fps

proc withInstallSignalHandler*(config: AppConfig, enabled: bool): AppConfig {.inline.} =
  ## Return a new config with install-signal-handler setting (chronos only)
  result = config
  result.installSignalHandler = enabled

proc withViewport*(config: AppConfig, viewport: Viewport): AppConfig {.inline.} =
  ## Return a new config with the viewport setting
  result = config
  result.viewport = viewport

# Version Information

const celinaVersion* = block:
  ## Full version string parsed from celina.nimble at compile time
  var v = ""
  for line in staticRead("../../celina.nimble").splitLines:
    if strutils.strip(line).startsWith("version"):
      v = strutils.strip(line.split("=")[1], chars = {'"', ' '})
      break
  v
