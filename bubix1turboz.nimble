# Package

version       = "0.1.0"
author         = "bubio"
description    = "Multi-platform Sharp X1 turbo Z emulator"
license        = "GPL-2.0-or-later"
srcDir         = "src/nim"

# Dependencies

requires "nim >= 2.0.0"
# Pinned exactly: these are the versions the application has been developed
# and verified against, and CI installs its dependencies from this file. An
# open range would let a release be built against a package nobody here has
# ever run.
requires "sdl2 == 2.0.6"
requires "uing == 0.8.2"

# NOTE: `bin` is intentionally left unset. The application is not built by
# nimble but by scripts/build_nim_app.sh, which has to pass the flags that
# link the C++ core and the SDL2 framework. This file is the single source
# of truth for the application version; the Nim toolchain version is pinned
# separately in mise.toml.
