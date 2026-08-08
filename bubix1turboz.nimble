# Package

version       = "0.1.0"
author         = "bubio"
description    = "Multi-platform Sharp X1 turbo Z emulator"
license        = "GPL-2.0-or-later"
srcDir         = "src/nim"

# Dependencies

requires "nim >= 2.0.0"
requires "sdl2"
requires "uing"

# NOTE: `bin` is intentionally left unset until src/nim/ has an entry point
# (phase 4/5 of docs/dev/DevelopmentPlan.md). This file is the single
# source of truth for the application version; the Nim toolchain version
# is pinned separately in mise.toml.
