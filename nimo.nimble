# Package

version       = "0.2.0"
author        = "nimo contributors"
description   = "nimo — a nano-inspired terminal text editor with a file-tree sidebar"
license       = "MIT"
srcDir        = "src"
bin           = @["nimo"]

# Dependencies

requires "nim >= 2.0.0"
# No external libraries — Nim standard library only.

task run, "Build and run nimo on the current directory":
  exec "nim c -d:release --out:nimo src/nimo.nim"
  exec "./nimo"
