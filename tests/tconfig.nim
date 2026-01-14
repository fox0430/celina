# Test suite for config module

import std/unittest

import ../celina/core/config

suite "Config Module Tests":
  suite "DefaultAppConfig Tests":
    test "DefaultAppConfig has expected default values":
      check DefaultAppConfig.title == "Celina App"
      check DefaultAppConfig.alternateScreen == true
      check DefaultAppConfig.mouseCapture == false
      check DefaultAppConfig.bracketedPaste == false
      check DefaultAppConfig.rawMode == true
      check DefaultAppConfig.windowMode == false
      check DefaultAppConfig.targetFps == 60

    test "defaultAppConfig() returns DefaultAppConfig":
      let config = defaultAppConfig()
      check config == DefaultAppConfig

  suite "Builder Pattern Tests":
    test "withTitle changes title":
      let config = DefaultAppConfig.withTitle("My App")
      check config.title == "My App"
      check config.alternateScreen == true
      check config.mouseCapture == false
      check config.rawMode == true
      check config.windowMode == false
      check config.targetFps == 60

    test "withTitle with empty string":
      let config = DefaultAppConfig.withTitle("")
      check config.title == ""

    test "withAlternateScreen enables alternate screen":
      let config = DefaultAppConfig.withAlternateScreen(true)
      check config.alternateScreen == true

    test "withAlternateScreen disables alternate screen":
      let config = DefaultAppConfig.withAlternateScreen(false)
      check config.alternateScreen == false

    test "withMouseCapture enables mouse capture":
      let config = DefaultAppConfig.withMouseCapture(true)
      check config.mouseCapture == true

    test "withMouseCapture disables mouse capture":
      let config = DefaultAppConfig.withMouseCapture(false)
      check config.mouseCapture == false

    test "withBracketedPaste enables bracketed paste":
      let config = DefaultAppConfig.withBracketedPaste(true)
      check config.bracketedPaste == true

    test "withBracketedPaste disables bracketed paste":
      let config = DefaultAppConfig.withBracketedPaste(false)
      check config.bracketedPaste == false

    test "withRawMode enables raw mode":
      let config = DefaultAppConfig.withRawMode(true)
      check config.rawMode == true

    test "withRawMode disables raw mode":
      let config = DefaultAppConfig.withRawMode(false)
      check config.rawMode == false

    test "withWindowMode enables window mode":
      let config = DefaultAppConfig.withWindowMode(true)
      check config.windowMode == true

    test "withWindowMode disables window mode":
      let config = DefaultAppConfig.withWindowMode(false)
      check config.windowMode == false

    test "withTargetFps sets target FPS":
      let config = DefaultAppConfig.withTargetFps(30)
      check config.targetFps == 30

    test "withTargetFps with high value":
      let config = DefaultAppConfig.withTargetFps(144)
      check config.targetFps == 144

    test "withTargetFps with zero":
      let config = DefaultAppConfig.withTargetFps(0)
      check config.targetFps == 0

  suite "Builder Chaining Tests":
    test "multiple builders can be chained":
      let config = DefaultAppConfig
        .withTitle("Chained App")
        .withMouseCapture(true)
        .withTargetFps(30)

      check config.title == "Chained App"
      check config.mouseCapture == true
      check config.targetFps == 30
      check config.alternateScreen == true
      check config.rawMode == true
      check config.windowMode == false

    test "all builders can be chained":
      let config = DefaultAppConfig
        .withTitle("Full Config")
        .withAlternateScreen(false)
        .withMouseCapture(true)
        .withBracketedPaste(true)
        .withRawMode(false)
        .withWindowMode(true)
        .withTargetFps(120)

      check config.title == "Full Config"
      check config.alternateScreen == false
      check config.mouseCapture == true
      check config.bracketedPaste == true
      check config.rawMode == false
      check config.windowMode == true
      check config.targetFps == 120

    test "builder order does not matter":
      let config1 = DefaultAppConfig.withTitle("App").withTargetFps(30)

      let config2 = DefaultAppConfig.withTargetFps(30).withTitle("App")

      check config1 == config2

    test "later builder calls override earlier ones":
      let config = DefaultAppConfig.withTitle("First").withTitle("Second")

      check config.title == "Second"

  suite "Immutability Tests":
    test "original config is not modified by builder":
      let original = DefaultAppConfig
      let modified = original.withTitle("Modified")

      check original.title == "Celina App"
      check modified.title == "Modified"

    test "chained modifications do not affect intermediate configs":
      let step1 = DefaultAppConfig.withTitle("Step 1")
      let step2 = step1.withMouseCapture(true)
      let step3 = step2.withTargetFps(30)

      check step1.title == "Step 1"
      check step1.mouseCapture == false
      check step1.targetFps == 60

      check step2.title == "Step 1"
      check step2.mouseCapture == true
      check step2.targetFps == 60

      check step3.title == "Step 1"
      check step3.mouseCapture == true
      check step3.targetFps == 30
