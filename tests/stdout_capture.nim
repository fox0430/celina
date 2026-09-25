## Shared test helper that captures what a block writes to stdout.

import std/[os, posix, tempfiles, termios]

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

proc withFailingStdout*(body: proc()) =
  ## Run `body` with stdout on a read-only fd, so every write to it fails
  ## with EBADF.
  stdout.flushFile()
  let saved = dup(STDOUT_FILENO)
  let roFd = open("/dev/null", O_RDONLY)
  doAssert saved != -1 and roFd != -1
  discard dup2(roFd, STDOUT_FILENO)
  discard close(roFd)
  try:
    body()
  finally:
    discard dup2(saved, STDOUT_FILENO)
    discard close(saved)

when defined(linux):
  var RLIMIT_FSIZE {.importc: "RLIMIT_FSIZE", header: "<sys/resource.h>".}: cint

  var cutWritesLeft = 0
    ## Writes still to fail at the limit before `liftFileSizeLimit` lifts it.

  proc liftFileSizeLimit(sig: cint) {.noconv.} =
    let savedErrno = errno
    dec cutWritesLeft
    if cutWritesLeft <= 0:
      var limit: RLimit
      if getrlimit(RLIMIT_FSIZE, limit) == 0:
        limit.rlim_cur = limit.rlim_max
        discard setrlimit(RLIMIT_FSIZE, limit)
    errno = savedErrno

  proc clearerr(f: File) {.importc, header: "<stdio.h>".}

  proc captureCutStdout*(limit: int, body: proc(), failedWrites = 1): string =
    ## Run `body` with stdout on a file that takes only `limit` bytes, and
    ## return what reached the file. The write that crosses `limit` stops
    ## there and the next `failedWrites` writes fail at once, like a tty that
    ## stopped draining but with no retry budget to wait out; the SIGXFSZ from
    ## the last of them lifts the limit, so later writes go through. Clears
    ## the stdio error flag a cut `fflush` sets, so a later `stdout.write`
    ## does not raise. Linux only: other systems may refuse the whole crossing
    ## write.
    let (file, path) = createTempFile("celina_cut_stdout_", "")
    defer:
      file.close()
      removeFile(path)
    stdout.flushFile()
    var act, oldAct: Sigaction
    act.sa_handler = liftFileSizeLimit
    discard sigemptyset(act.sa_mask)
    doAssert sigaction(SIGXFSZ, act, oldAct) == 0
    var saved: RLimit
    doAssert getrlimit(RLIMIT_FSIZE, saved) == 0
    let savedStdout = dup(STDOUT_FILENO)
    doAssert savedStdout != -1
    discard dup2(file.getFileHandle(), STDOUT_FILENO)
    cutWritesLeft = failedWrites
    var limited = saved
    limited.rlim_cur = limit
    doAssert setrlimit(RLIMIT_FSIZE, limited) == 0
    try:
      body()
    finally:
      discard setrlimit(RLIMIT_FSIZE, saved)
      discard sigaction(SIGXFSZ, oldAct, nil)
      clearerr(stdout)
      discard dup2(savedStdout, STDOUT_FILENO)
      discard close(savedStdout)
    readFile(path)

proc withStdinInput*(input: string, body: proc()) =
  ## Run `body` with stdin replaced by a pipe that holds `input`. The write
  ## end stays open until `body` returns, so once `input` is read, stdin
  ## has no data (and no EOF) to report.
  var fds: array[2, cint]
  doAssert pipe(fds) == 0
  let saved = dup(STDIN_FILENO)
  doAssert saved != -1
  discard dup2(fds[0], STDIN_FILENO)
  discard close(fds[0])
  try:
    if input.len > 0:
      doAssert posix.write(fds[1], unsafeAddr input[0], input.len) == input.len
    body()
  finally:
    discard dup2(saved, STDIN_FILENO)
    discard close(saved)
    discard close(fds[1])

proc posix_openpt(flags: cint): cint {.importc, header: "<stdlib.h>".}
proc grantpt(fd: cint): cint {.importc, header: "<stdlib.h>".}
proc unlockpt(fd: cint): cint {.importc, header: "<stdlib.h>".}
proc ptsname(fd: cint): cstring {.importc, header: "<stdlib.h>".}
var TIOCSWINSZ {.importc, header: "<sys/ioctl.h>".}: culong

proc withPtyStdout*(cols, rows: int, body: proc()): bool =
  ## Run `body` with stdout on a pty of the given size; output is discarded.
  ## Returns false without running `body` if the pty cannot be set up.
  ## Output is drained only afterwards, so keep it within the pty buffer.
  stdout.flushFile()
  let master = posix_openpt(O_RDWR or O_NOCTTY)
  if master == -1:
    return false
  defer:
    discard close(master)
  if grantpt(master) != 0 or unlockpt(master) != 0:
    return false
  let slaveName = ptsname(master)
  if slaveName == nil:
    return false
  let slave = open(slaveName, O_RDWR or O_NOCTTY)
  if slave == -1:
    return false
  var ws = IOctl_WinSize(ws_row: rows.cushort, ws_col: cols.cushort)
  if ioctl(slave, TIOCSWINSZ, addr ws) != 0:
    discard close(slave)
    return false
  let saved = dup(STDOUT_FILENO)
  if saved == -1:
    discard close(slave)
    return false
  if dup2(slave, STDOUT_FILENO) == -1:
    discard close(slave)
    discard close(saved)
    return false
  discard close(slave)
  try:
    body()
  finally:
    stdout.flushFile()
    discard dup2(saved, STDOUT_FILENO)
    discard close(saved)
    discard fcntl(master, F_SETFL, fcntl(master, F_GETFL) or O_NONBLOCK)
    var buf: array[4096, char]
    while posix.read(master, addr buf[0], buf.len) > 0:
      discard
  true
