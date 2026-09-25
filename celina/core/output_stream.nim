## Output stream state shared by the writes to stdout
##
## A write that stops partway can leave the terminal inside an escape sequence,
## where it swallows the bytes that come next. The write that stopped gives
## `AbortPartialSeq` one try that never waits. If that does not go out in full,
## the abort stays pending here, and the next write through celina's write
## procs (the sync `Terminal` writes, `writeStdoutAsync` and the blocking
## async-mode writes) sends it first. `resume` sets it pending too: another
## program had the terminal. Frames and clears do not add their own abort.
##
## Not covered: the emergency restores that write straight to the fd
## (`Terminal.emergencyRestore` and the blocking `AsyncTerminal.emergencyRestore`)
## ignore this state, since their reset starts with its own abort;
## `emergencyRestoreAsync` goes through `writeStdoutAsync`, so it sends a
## pending abort first like any other write. Bytes the C stdio buffer flushes
## on its own, or that `flushStdoutAsync` flushes, bypass it too.
##
## Internal: not re-exported from `celina`. Like the async stdout lock, the
## state is process-global and not thread-safe, and it relies on the same
## contract (async/async_io.nim): no blocking write while a `writeStdoutAsync`
## is parked mid-write.

from std/posix import STDOUT_FILENO
import terminal_common

var pendingAbort = false ## The next write must send `AbortPartialSeq` first.

proc abortPending*(): bool {.inline.} =
  ## Whether the next write must send `AbortPartialSeq` first.
  pendingAbort

proc clearPendingAbort*() {.inline.} =
  ## Record that the pending abort went out in full.
  pendingAbort = false

proc setPendingAbort*() {.inline.} =
  ## Make the next write send `AbortPartialSeq` first. For bytes celina did not
  ## write, such as another program's output while the terminal was suspended.
  pendingAbort = true

proc abortPartialWrite*() =
  ## Call after a write to stdout stopped or was cancelled partway. Marks the
  ## abort pending and gives it one try that never waits: the write has just
  ## given up, so on a wedged tty another full wait budget would only double
  ## the stall. Never raises.
  pendingAbort = true
  if writeAllBlocking(STDOUT_FILENO.cint, AbortPartialSeq, maxBlockedWaits = 1) ==
      AbortPartialSeq.len:
    pendingAbort = false

proc sendPendingAbort*(): bool =
  ## Write a pending abort to stdout with the normal wait budget. Returns true
  ## when no abort is pending any more. Never raises.
  if pendingAbort and
      writeAllBlocking(STDOUT_FILENO.cint, AbortPartialSeq) == AbortPartialSeq.len:
    pendingAbort = false
  not pendingAbort

proc writeStream*(data: string): int =
  ## Blocking write of `data` to stdout through `writeAllBlocking`. A pending
  ## abort goes first; if it does not go out in full, `data` is not tried,
  ## since its bytes would land inside the sequence the abort is for, and this
  ## returns 0. A write that stops partway is followed by `abortPartialWrite`.
  ## Returns the number of bytes of `data` written. Never raises.
  if data.len == 0 or not sendPendingAbort():
    return 0
  result = writeAllBlocking(STDOUT_FILENO.cint, data)
  if result > 0 and result < data.len:
    abortPartialWrite()
