# `bubix1/ui` — the host-dependent layer

Everything in this application that talks to a windowing system, a menu
bar or a file panel goes through this directory. Nothing outside it may
name a platform or reach for a host library: no `defined(macosx)`, no
`{.compile: "*.m".}`, no `{.passL: ...}` lives anywhere else in
`src/nim`. `scripts/check_other_platforms.sh` enforces that, and also
runs `nim check` for the platforms a macOS build never exercises.

Three files outside this directory are excepted, all deliberately:

- **`bubix1/paths.nim`** branches on the platform but needs no backend —
  a storage location is a `string`, not an object with behaviour, so a
  facade around it would be three lines of ceremony per path.
- **`bubix1/deflate.nim`** links zlib with `{.passL: "-lz".}` on every
  platform but Windows, which has no system zlib; there
  `scripts/fetch_zlib_windows.sh` vendors the source and
  `scripts/build_core.sh` compiles it into the core's own static library
  instead, so this file's own exception is only the `when` that skips the
  system `-lz` there.
- **`bubix1/archive.nim`** has one `defined(windows)`, to also try
  Windows' own `%SystemRoot%\System32\tar.exe` (always bsdtar there) as
  an archiver, next to the same-purpose bsdtar/7z/unzip lookups every
  platform already does. No UI, no host library link - the same bar the
  other two exceptions clear.

```
ui/
  types.nim        shared data types, no backend of any kind
  <module>.nim     facade: the API the application calls, plus every
                   piece of logic that is the same on all platforms
  macos/           AppKit backend (the .m files live here)
  linux/           GTK backend
  windows/         Win32 backend
  stub/            does-nothing backend, used by the platforms whose
                   real backend has not been written yet
```

## How a facade is built

A facade selects one backend and keeps everything portable to itself:

```nim
when defined(macosx):
  import ./macos/filedialog as backend
else:
  import ./stub/filedialog as backend
```

The split between the two is deliberate. A backend is given the smallest
possible job — show this panel, return what the user chose — and is
handed plain Nim values (`string`, `seq`, `int`) rather than anything of
its own shape. Everything else stays in the facade, where it is written
once instead of three times:

- closure tables and callback dispatch (`nativemenu`, `volumepanel`),
- every word the user reads, looked up from `i18n` before the call, so a
  new backend inherits the translations rather than repeating them,
- default values, empty-input guards and the "not installed yet" no-op
  behaviour.

## Adding a backend

Write `ui/<platform>/<module>.nim` exporting the same procs as the
`stub/` version of that module — the stub is the interface's written
form — then point the facade's `when` at it. Nothing outside `ui/`
changes.

Note that Nim never compiles the unselected branch of a `when`, so an
unfinished backend cannot break a build it is not part of, and equally
cannot be proved to still compile. `stub/` is what let the Linux and
Windows builds link and run before either had a real backend: no menu bar,
dialogs that answer "cancelled" - a state worth being able to build and
see, rather than a wall of link errors. It is still the answer for any
future platform in the same position, and for a module a backend has not
gotten to yet.
