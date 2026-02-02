# Package

version = "0.7.0"
author = "fox0430"
description = "A CLI library inspired by Ratatui"
license = "MIT"

# Dependencies

requires "nim >= 2.0.2"
requires "unicodedb"

task test, "test":
  exec "nim c -d:asyncBackend=none -r tests/all_tests.nim"
  exec "nim c -d:asyncBackend=asyncdispatch -r tests/all_tests.nim"
  exec "nim c -d:asyncBackend=chronos -r tests/all_tests.nim"
