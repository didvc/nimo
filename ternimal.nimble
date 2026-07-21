# Package

version       = "0.1.0"
author        = "ternimal contributors"
description   = "A nano-inspired terminal text editor with a file-tree sidebar"
license       = "MIT"
srcDir        = "src"
bin           = @["ternimal"]

# Dependencies

requires "nim >= 2.0.0"
# No external libraries — Nim standard library only.

task run, "Build and run ternimal on the current directory":
  exec "nim c -d:release --out:ternimal src/ternimal.nim"
  exec "./ternimal"
