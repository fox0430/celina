## Async backend configuration module.
##
## This module provides the async backend configuration and exports the appropriate
## async framework (asyncdispatch or chronos) based on compile-time flags.

# Async backend configuration. `-d:asyncBackend=none|asyncdispatch|chronos|`
# This constant is automatically exported via the * marker
const asyncBackend* {.strdefine.} = "none"

when asyncBackend == "none":
  const
    hasAsyncSupport* = false
    hasAsyncDispatch* = false
    hasChronos* = false
elif asyncBackend == "asyncdispatch":
  const
    hasAsyncSupport* = true
    hasAsyncDispatch* = true
    hasChronos* = false
elif asyncBackend == "chronos":
  const
    hasAsyncSupport* = true
    hasAsyncDispatch* = false
    hasChronos* = true
else:
  {.fatal: "Unknown asyncBackend. Use -d:asyncBackend=none|asyncdispatch|chronos|".}

when hasAsyncSupport:
  when hasAsyncDispatch:
    import std/asyncdispatch
    export asyncdispatch

    template sleepMs*(ms: int): untyped =
      sleepAsync(ms)

    # AsyncFD handling for asyncdispatch
    template registerFD*(fd: AsyncFD): untyped =
      register(fd)

    template unregisterFD*(fd: AsyncFD): untyped =
      unregister(fd)

  else:
    import chronos
    export chronos

    template sleepMs*(ms: int): untyped =
      sleepAsync(chronos.milliseconds(ms))

    # For Chronos, AsyncFD registration is automatic, so provide no-op templates
    template registerFD*(fd: AsyncFD): untyped =
      discard

    template unregisterFD*(fd: AsyncFD): untyped =
      discard
