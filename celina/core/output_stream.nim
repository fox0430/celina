## Output stream state shared by the writes to stdout
##
## Ground state between writes: no open escape sequence, default SGR, no OSC 8
## link, no celina-opened sync block. Only this module restores it.
##
## A write names its partial-write reset via `onPartial`; the next celina write
## sends it first as its own write. A reset that fails stays pending and `data`
## is skipped. Resends are harmless. `resume` marks one too.
##
## Frames/clears only name the reset (a wrapped frame adds `srSyncEnd`).
##
## Not covered: the emergency restores that write straight to the fd (the
## blocking `Terminal.emergencyRestore` and the blocking async-mode
## `AsyncTerminal.emergencyRestore`), since their reset starts with its own
## abort; `emergencyRestoreAsync` goes through `writeStdoutAsync`, so it sends
## a pending reset first like any other write. C stdio / async flushes that
## bypass this state do too.
##
## Internal: not re-exported. Process-global, not thread-safe; no blocking
## write while a `writeStdoutAsync` is parked mid-write.

import std/posix
import ../async/async_backend
import colors, terminal_common

type
  StreamWrite* = enum
    swAll ## every byte of the data went out
    swNone ## no byte of the data went out
    swPartial ## some bytes went out, or the write was cancelled mid-way

  StreamReset* = enum
    srAbort ## AbortPartialSeq (CAN ST); part of every reset a cut write marks
    srOsc8 ## Osc8Reset: an OSC 8 link a cut write left open
    srSgr ## resetSequence(): attributes a cut write left set
    srSyncEnd ## SyncOutputDisable: a block celina wrapped that a cut write left open

var pendingReset: set[StreamReset] ## The next write must send this first.

proc resetSeq(reset: StreamReset): string {.inline.} =
  ## The bytes of one reset.
  case reset
  of srAbort:
    AbortPartialSeq
  of srOsc8:
    Osc8Reset
  of srSgr:
    resetSequence()
  of srSyncEnd:
    SyncOutputDisable

proc resetSeq(reset: set[StreamReset]): string =
  ## The bytes of a whole reset, in enum order, so the abort comes first and a
  ## block celina opened is closed last. "" while no reset is pending, without
  ## allocating.
  for r in StreamReset:
    if r in reset:
      result.add resetSeq(r)

proc outcomeOf*(written, length: int): StreamWrite {.inline.} =
  ## Byte count to outcome. 0 covers both an unsent write and a reset-blocked
  ## one; both leave the screen unchanged.
  if written >= length:
    swAll
  elif written > 0:
    swPartial
  else:
    swNone

proc resetPending*(): bool {.inline.} =
  ## Whether the next write must send a reset first.
  pendingReset != {}

proc clearPendingReset*() {.inline.} =
  ## Record that the pending reset went out in full.
  pendingReset = {}

proc setPendingReset*(reset: set[StreamReset]) {.inline.} =
  ## Queue `reset` on top of the pending one (widening). For off-model bytes;
  ## an unneeded resend is harmless in the ground state.
  pendingReset = pendingReset + reset

proc markPartialWrite*(onPartial: set[StreamReset]) =
  ## Mark the reset for a stopped/cancelled write and retry it once without
  ## waiting. Widening: an already-pending reset survives. Never raises.
  pendingReset = pendingReset + {srAbort} + onPartial
  let reset = resetSeq(pendingReset)
  if writeAllBlocking(STDOUT_FILENO.cint, reset, maxBlockedWaits = 1) == reset.len:
    pendingReset = {}

proc sendPendingReset*(): bool =
  ## Write a pending reset to stdout with the normal wait budget. Returns true
  ## when no reset is pending any more. Never raises.
  if pendingReset != {}:
    let reset = resetSeq(pendingReset)
    if writeAllBlocking(STDOUT_FILENO.cint, reset) == reset.len:
      pendingReset = {}
  pendingReset == {}

proc writeStream*(data: string, onPartial: set[StreamReset]): int =
  ## Blocking `data` write via `writeAllBlocking`. Pending reset goes first;
  ## on failure `data` is skipped (returns 0). Empty `data` writes nothing.
  ## Short count = truncated; a stopped write is followed by `markPartialWrite`.
  ## Never raises.
  if data.len == 0 or not sendPendingReset():
    return 0
  result = writeAllBlocking(STDOUT_FILENO.cint, data)
  if result > 0 and result < data.len:
    markPartialWrite(onPartial)

when defined(celinaDebug):
  proc writeProgress(total, dataLen, resetLeft, resetTotal: int): string =
    ## Bytes of `data` written for the give-up warnings in `writeStreamLocked`,
    ## plus the progress of the pending reset that goes out before it.
    result = $total & "/" & $dataLen & " bytes"
    if resetTotal > 0:
      result.add ", pending reset " & $(resetTotal - resetLeft) & "/" & $resetTotal &
        " bytes"

when hasAsyncSupport:
  proc writeStreamLocked*(
      data: string, onPartial: set[StreamReset]
  ): Future[int] {.async.} =
    ## Async `writeStream` with the lock already held. Same reset/empty/stop
    ## contract, but yields (`await sleepMs`) instead of blocking and gives up
    ## after `WriteMaxBlockedWaits` no-progress attempts. Single proc to avoid
    ## a per-write Future. A chronos cancel is re-raised instead of swallowed,
    ## so a caller's `finally` can record the stopped write (the frame paths
    ## start their outcome at `swPartial` for exactly that); other errors are
    ## swallowed as a short count.
    if data.len == 0:
      return 0

    var
      total = 0 ## bytes of `data` written
      resetLeft = 0 ## bytes of the pending reset still to write before it
      resetTotal = 0
      blockedWaits = 0
    let fd = STDOUT_FILENO.cint
    # The reset goes through the same loop, ahead of the data, so a cut reset
    # and a cut data write share one wait budget. Which parts of the pending
    # reset it covers is snapshotted here: `resume` does not take the lock, so
    # a reset can be marked pending while this write awaits, and it must
    # survive the clear below.
    let sentReset = pendingReset
    let resetBytes = resetSeq(sentReset)
    resetLeft = resetBytes.len
    resetTotal = resetLeft

    try:
      while resetLeft > 0 or total < data.len:
        let n =
          if resetLeft > 0:
            posix.write(
              fd, unsafeAddr resetBytes[resetBytes.len - resetLeft], resetLeft
            ).int
          else:
            posix.write(fd, unsafeAddr data[total], data.len - total).int

        case classifyWriteResult(n)
        of woProgress:
          if resetLeft > 0:
            resetLeft -= n
            if resetLeft == 0:
              # Only the parts this write sent are done: a reset marked pending
              # while it was in flight stays pending for the next write.
              pendingReset = pendingReset - sentReset
          else:
            total += n
          blockedWaits = 0
        of woInterrupted:
          # Interrupted before writing anything. Yield before retrying so a
          # signal storm (e.g. SIGWINCH during a resize drag) can't starve the
          # event loop, and count it so a relentless storm can't loop forever.
          inc blockedWaits
          if blockedWaits >= WriteMaxBlockedWaits:
            when defined(celinaDebug):
              stderr.writeLine(
                "Warning: writeStreamLocked gave up after " & $WriteMaxBlockedWaits &
                  " interrupted writes (" &
                  writeProgress(total, data.len, resetLeft, resetTotal) & ")"
              )
            break
          await sleepMs(0)
        of woWouldBlock:
          # Stdout not ready (shares O_NONBLOCK with stdin on the same tty).
          # Probe writability, yield, and give up after `WriteMaxBlockedWaits`
          # no-progress waits; drainage resets the counter via woProgress.
          inc blockedWaits
          if blockedWaits >= WriteMaxBlockedWaits:
            when defined(celinaDebug):
              stderr.writeLine(
                "Warning: writeStreamLocked gave up after " & $WriteMaxBlockedWaits &
                  " blocked writes (" &
                  writeProgress(total, data.len, resetLeft, resetTotal) & ")"
              )
            break
          case pollWritable(fd, 0) # non-blocking probe; never blocks the event loop
          of wwError:
            # stdout went away (POLLHUP/POLLERR); stop and report bytes sent.
            when defined(celinaDebug):
              stderr.writeLine(
                "Warning: writeStreamLocked stdout error (" &
                  writeProgress(total, data.len, resetLeft, resetTotal) & ")"
              )
            break
          of wwWritable:
            # Writable again: yield once and retry promptly.
            await sleepMs(0)
          of wwNotReady:
            # Still full: back off cooperatively before re-probing the fd.
            await sleepMs(WriteBlockedWaitMs)
        of woHardError:
          # Hard error, or a 0-byte write we can't make progress on. Stop and
          # report how much actually made it out.
          when defined(celinaDebug):
            stderr.writeLine(
              "Warning: writeStreamLocked hard error (" &
                writeProgress(total, data.len, resetLeft, resetTotal) & ")"
            )
          break
    except CancelledError as e:
      # Let chronos cancellation propagate (the `finally` still marks the
      # reset) so `cancelAndWait`-based shutdown can tear the write down,
      # instead of the catch-all below swallowing it and reporting a normal
      # outcome. asyncdispatch never raises this type, so this is a no-op there.
      raise e
    except CatchableError:
      # Preserve the old contract of never raising on ordinary I/O errors:
      # report however many bytes already made it out.
      discard
    finally:
      # A reset cut off partway stays pending. A data write that stopped (or was
      # cancelled) after some byte went out marks what the write needs undone,
      # and gets one try that never waits. A cancel before the first byte of
      # `data` leaves the stream where the last completed write left it.
      if resetLeft == 0 and total > 0 and total < data.len:
        markPartialWrite(onPartial)

    result = total
