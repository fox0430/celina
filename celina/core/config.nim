## Application Configuration
##
## This module provides shared configuration types for both
## synchronous and asynchronous application modes.

type AppConfig* = object ## Application configuration options
  title*: string ## Application title (for window managers)
  alternateScreen*: bool ## Use alternate screen buffer
  mouseCapture*: bool ## Enable mouse event capture
  rawMode*: bool ## Enable raw terminal mode (no line buffering)
  windowMode*: bool ## Enable window management
  targetFps*: int ## Target FPS for rendering (default: 60)

const DefaultAppConfig* = AppConfig(
  title: "Celina App",
  alternateScreen: true,
  mouseCapture: false,
  rawMode: true,
  windowMode: false,
  targetFps: 60,
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
