## App Handler-Setter Helpers
## ==========================
##
## Shared `untyped` template used by `App` and `AsyncApp` handler-setter
## procs. The expansion happens in the caller's scope, so the private
## `handlers.*` fields remain accessible.

template wrapHandler*(handler, body: untyped): untyped =
  ## Wrap a user-supplied handler with the standard nil-safe pattern
  ## used by both `App` and `AsyncApp` handler setters.
  ##
  ## Evaluates to `nil` when `handler` is nil; otherwise binds `captured`
  ## to a local copy of `handler` and evaluates `body`. `body` is
  ## typically an anonymous proc literal that closes over `captured`.
  ##
  ## Example (sync `App`):
  ## ```nim
  ## app.handlers.event = wrapHandler(handler):
  ##   proc(event: Event, app: App): EventResult =
  ##     captured(event)
  ## ```
  ##
  ## Example (async `AsyncApp`):
  ## ```nim
  ## app.handlers.event = wrapHandler(handler):
  ##   proc(event: Event, app: AsyncApp): Future[EventResult] {.async.} =
  ##     return await captured(event)
  ## ```
  ##
  ## The handler expression is evaluated exactly once: it is bound to an
  ## internal local before the nil check, so callers may pass a function
  ## call (e.g. `wrapHandler(buildHandler()): ...`) without double-firing
  ## its side effects.
  block:
    let h = handler
    if h.isNil:
      nil
    else:
      let captured {.inject.} = h
      body
