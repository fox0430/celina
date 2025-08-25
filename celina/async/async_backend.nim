## Synchronous backend helper.

# Async backend configuration. `-d:asyncBackend=none|asyncdispatch|chronos|`
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

  import async_app as asyncApp
  import async_terminal, async_events, async_io, async_buffer, async_windows

  export async_app, async_terminal, async_events, async_io, async_buffer, async_windows
