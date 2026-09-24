## Shared test helper that captures what a block writes to stdout.

import std/posix

proc captureStdout*(body: proc()): string =
  ## Run `body` with stdout redirected to a pipe and return what it wrote.
  ## Returns "" without running `body` if the redirect cannot be set up.
  ## The pipe is read only after `body` returns, so `body` must not write
  ## more than the pipe buffer holds.
  stdout.flushFile()
  let saved = dup(STDOUT_FILENO)
  if saved == -1:
    return ""
  var fds: array[2, cint]
  if pipe(fds) != 0:
    discard close(saved)
    return ""
  discard dup2(fds[1], STDOUT_FILENO)
  discard close(fds[1])
  try:
    try:
      body()
    finally:
      discard dup2(saved, STDOUT_FILENO)
      discard close(saved)
    # The write end is closed now, so read until EOF.
    var buf = newString(4096)
    while true:
      let n = posix.read(fds[0], addr buf[0], buf.len.cint)
      if n <= 0:
        break
      result.add buf[0 ..< n]
  finally:
    discard close(fds[0])
