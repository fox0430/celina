# Package

version = "0.1.0"
author = "fox0430"
description = "A CLI library inspired by Ratatui"
license = "MIT"
srcDir = "src"

# Dependencies

requires "nim >= 2.0.2"
requires "unicodedb"

task test, "test":
  exec "nim c -r tests/all_tests.nim"
