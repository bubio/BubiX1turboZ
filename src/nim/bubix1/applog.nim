## Diagnostic lines for whoever started the application from a terminal.
##
## Every such message goes through `note` rather than `stderr.writeLine`,
## because on Windows writing to stderr can take the whole process down -
## and does, whenever there is no console to write to.
##
## The application is linked for the GUI subsystem there (`-mwindows`, see
## scripts/build_nim_app.sh), so a copy started from Explorer - the normal
## way to start it - has no console and no valid standard handles to
## inherit. Measured inside a running build launched that way:
## `_fileno(stderr)` is -2, `fwrite` returns 0 and raises the stream's error
## flag, and `fprintf` returns -1. `File.write` routes Windows output
## through `std/syncio`'s `writeWindows`, which begins
##
##     var i = int c_fprintf(f, "%s", s)
##     while i < s.len:
##       if s[i] == '\0':
##
## so that -1 lands straight in `s[-1]` and raises `IndexDefect` before the
## proc's own error handling is ever consulted. That is a `Defect`, not a
## `CatchableError`, so wrapping the call site in `try` does not help
## either. One such line at the top of the shutdown sequence was enough to
## kill the process before a single save ran, losing the recent-files list,
## the core's config.ini and the host settings on every run. macOS and Linux
## never showed it: they take the `writeBuffer` branch, and fd 2 is open
## there however the process was launched.
##
## So this writes through `fwrite` directly and discards the result, which
## is what `echo` does for stdout and the only shape that cannot fail.
## Writing a counted buffer rather than a `%s` format string also carries an
## embedded NUL correctly, which is the case `writeWindows` loops for in the
## first place.

proc cFwrite(buffer: pointer, size, count: csize_t, stream: File): csize_t
  {.importc: "fwrite", header: "<stdio.h>".}
proc cFflush(stream: File): cint {.importc: "fflush", header: "<stdio.h>".}

proc note*(msg: string) =
  ## Writes one prefixed line to stderr, and gives up silently if there is
  ## nowhere to write it. Never raises.
  let line = "bubix1turboz: " & msg & "\n"
  discard cFwrite(line.cstring, 1, line.len.csize_t, stderr)
  discard cFflush(stderr)
