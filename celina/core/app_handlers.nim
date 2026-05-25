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

template defineEventHandlerSetters*(AppT: untyped) =
  ## Generate the sync `onEvent` setter family for `AppT`.
  ##
  ## Produces 4 overloads that mirror the historic hand-written setters:
  ##   - `onEvent(handler: proc(Event): EventResult)`
  ##   - `onEvent(handler: proc(Event, AppT): EventResult)`
  ##   - `onEvent(handler: proc(Event): bool)` (deprecated)
  ##   - `onEvent(handler: proc(Event, AppT): bool)` (deprecated)
  ##
  ## The legacy `bool` overloads translate `false` to `erQuit` and
  ## `true` to `erContinue`. Stores the wrapped callback in
  ## `app.handlers.event`, so the App type must expose that field.

  proc onEvent*(app: AppT, handler: proc(event: Event): EventResult) =
    ## Set the event handler for the application.
    ##
    ## Returning `erQuit` from the handler exits the application loop.
    ## `erConsume` and `erContinue` are equivalent at the global layer
    ## because no further layer follows it.
    app.handlers.event = wrapHandler(handler):
      proc(event: Event, app: AppT): EventResult =
        captured(event)

  proc onEvent*(app: AppT, handler: proc(event: Event, app: AppT): EventResult) =
    ## Set the event handler with `AppT` context for the application.
    ##
    ## See the single-arg overload for the return-value contract.
    app.handlers.event = handler

  proc onEvent*(
      app: AppT, handler: proc(event: Event): bool
  ) {.deprecated: "Use a handler returning EventResult instead of bool".} =
    ## Legacy `bool`-returning overload. `false` -> `erQuit`,
    ## `true` -> `erContinue`. Prefer the `EventResult`-returning overload
    ## in new code.
    app.handlers.event = wrapHandler(handler):
      proc(event: Event, app: AppT): EventResult =
        if captured(event): erContinue else: erQuit

  proc onEvent*(
      app: AppT, handler: proc(event: Event, app: AppT): bool
  ) {.deprecated: "Use a handler returning EventResult instead of bool".} =
    ## Legacy `bool`-returning overload with `AppT` context.
    ## `false` -> `erQuit`, `true` -> `erContinue`.
    ## Prefer the `EventResult`-returning overload in new code.
    app.handlers.event = wrapHandler(handler):
      proc(event: Event, app: AppT): EventResult =
        if captured(event, app): erContinue else: erQuit

template defineRenderHandlerSetters*(AppT: untyped) =
  ## Generate the sync `onRender` setter family for `AppT`.
  ##
  ## Produces 2 overloads:
  ##   - `onRender(handler: proc(var Buffer))`
  ##   - `onRender(handler: proc(var Buffer, AppT))`

  proc onRender*(app: AppT, handler: proc(buffer: var Buffer)) =
    ## Set the render handler for the application.
    ##
    ## For access to the App object (e.g., to query FPS, window state,
    ## or terminal size during rendering), use the overload that accepts
    ## `proc(buffer: var Buffer, app: AppT)` instead.
    app.handlers.render = wrapHandler(handler):
      proc(buffer: var Buffer, app: AppT) =
        captured(buffer)

  proc onRender*(app: AppT, handler: proc(buffer: var Buffer, app: AppT)) =
    ## Set the render handler with App context for the application.
    ##
    ## This overload provides access to the App object, enabling the
    ## render handler to query runtime state such as current FPS,
    ## terminal size, or window manager information.
    app.handlers.render = handler

template defineTickHandlerSetters*(AppT: untyped) =
  ## Generate the sync `onTick` setter family for `AppT`.
  ##
  ## Produces 4 overloads matching `onEvent`'s pattern but returning
  ## `TickResult` (`trContinue` / `trQuit`).

  proc onTick*(app: AppT, handler: proc(): TickResult) =
    ## Set the tick handler called each frame between event processing
    ## and rendering.
    ##
    ## Return `trContinue` to keep running, `trQuit` to exit the loop.
    app.handlers.tick = wrapHandler(handler):
      proc(app: AppT): TickResult =
        captured()

  proc onTick*(app: AppT, handler: proc(app: AppT): TickResult) =
    ## Set the tick handler with App context.
    ##
    ## Return `trContinue` to keep running, `trQuit` to exit the loop.
    app.handlers.tick = handler

  proc onTick*(
      app: AppT, handler: proc(): bool
  ) {.deprecated: "Use a handler returning TickResult instead of bool".} =
    ## Legacy `bool`-returning overload. `false` -> `trQuit`,
    ## `true` -> `trContinue`. Prefer the `TickResult`-returning overload.
    app.handlers.tick = wrapHandler(handler):
      proc(app: AppT): TickResult =
        if captured(): trContinue else: trQuit

  proc onTick*(
      app: AppT, handler: proc(app: AppT): bool
  ) {.deprecated: "Use a handler returning TickResult instead of bool".} =
    ## Legacy `bool`-returning overload with App context.
    ## `false` -> `trQuit`, `true` -> `trContinue`.
    app.handlers.tick = wrapHandler(handler):
      proc(app: AppT): TickResult =
        if captured(app): trContinue else: trQuit

template defineTimeoutHandlerSetters*(AppT: untyped) =
  ## Generate the sync `onTimeout` setter family for `AppT`.
  ##
  ## Produces 4 overloads mirroring `onTick` but invoked when no input
  ## events are received within the application timeout period.

  proc onTimeout*(app: AppT, handler: proc(): TickResult) =
    ## Set the timeout handler for the application.
    ##
    ## The handler is called when no input events are received within
    ## the application timeout period. Return `trContinue` to keep
    ## running, `trQuit` to exit the loop.
    app.handlers.timeout = wrapHandler(handler):
      proc(app: AppT): TickResult =
        captured()

  proc onTimeout*(app: AppT, handler: proc(app: AppT): TickResult) =
    ## Set the timeout handler with App context for the application.
    app.handlers.timeout = handler

  proc onTimeout*(
      app: AppT, handler: proc(): bool
  ) {.deprecated: "Use a handler returning TickResult instead of bool".} =
    ## Legacy `bool`-returning overload. `false` -> `trQuit`,
    ## `true` -> `trContinue`. Prefer the `TickResult`-returning overload.
    app.handlers.timeout = wrapHandler(handler):
      proc(app: AppT): TickResult =
        if captured(): trContinue else: trQuit

  proc onTimeout*(
      app: AppT, handler: proc(app: AppT): bool
  ) {.deprecated: "Use a handler returning TickResult instead of bool".} =
    ## Legacy `bool`-returning overload with App context.
    ## `false` -> `trQuit`, `true` -> `trContinue`.
    app.handlers.timeout = wrapHandler(handler):
      proc(app: AppT): TickResult =
        if captured(app): trContinue else: trQuit

template defineEventHandlerSettersAsync*(AppT: untyped) =
  ## Generate the async `onEventAsync` setter family for `AppT`.
  ##
  ## Produces 4 overloads parallel to `defineEventHandlerSetters` but
  ## using `Future[EventResult] {.async.}` callbacks. The call site must
  ## have `async_backend` imported so `Future` resolves.

  proc onEventAsync*(
      app: AppT, handler: proc(event: Event): Future[EventResult] {.async.}
  ) =
    ## Set the async event handler for the application.
    ##
    ## Return `erQuit` to exit the loop. `erConsume`/`erContinue` are
    ## equivalent at the global layer.
    app.handlers.event = wrapHandler(handler):
      proc(event: Event, app: AppT): Future[EventResult] {.async.} =
        return await captured(event)

  proc onEventAsync*(
      app: AppT, handler: proc(event: Event, app: AppT): Future[EventResult] {.async.}
  ) =
    ## Set the async event handler with `AppT` context.
    ## See the single-arg overload for the return-value contract.
    app.handlers.event = handler

  proc onEventAsync*(
      app: AppT, handler: proc(event: Event): Future[bool] {.async.}
  ) {.
      deprecated: "Use a handler returning Future[EventResult] instead of Future[bool]"
  .} =
    ## Legacy `bool`-returning overload. `false` -> `erQuit`,
    ## `true` -> `erContinue`. Prefer the `EventResult`-returning overload.
    app.handlers.event = wrapHandler(handler):
      proc(event: Event, app: AppT): Future[EventResult] {.async.} =
        let cont = await captured(event)
        return if cont: erContinue else: erQuit

  proc onEventAsync*(
      app: AppT, handler: proc(event: Event, app: AppT): Future[bool] {.async.}
  ) {.
      deprecated: "Use a handler returning Future[EventResult] instead of Future[bool]"
  .} =
    ## Legacy `bool`-returning overload with `AppT` context.
    ## `false` -> `erQuit`, `true` -> `erContinue`.
    app.handlers.event = wrapHandler(handler):
      proc(event: Event, app: AppT): Future[EventResult] {.async.} =
        let cont = await captured(event, app)
        return if cont: erContinue else: erQuit

template defineRenderHandlerSettersAsync*(AppT: untyped) =
  ## Generate the async `onRenderAsync` setter family for `AppT`.
  ##
  ## Render handlers are intentionally synchronous (procs, not Futures)
  ## because the buffer mutation runs in the single-threaded async loop.
  ## Produces 2 overloads.

  proc onRenderAsync*(app: AppT, handler: proc(buffer: var Buffer)) =
    ## Set the render handler for the application.
    ##
    ## For access to the AsyncApp object (e.g., to query FPS, window
    ## state, or terminal size during rendering), use the overload that
    ## accepts `proc(buffer: var Buffer, app: AppT)` instead.
    app.handlers.render = wrapHandler(handler):
      proc(buffer: var Buffer, app: AppT) =
        captured(buffer)

  proc onRenderAsync*(app: AppT, handler: proc(buffer: var Buffer, app: AppT)) =
    ## Set the render handler with AsyncApp context for the application.
    app.handlers.render = handler

template defineTickHandlerSettersAsync*(AppT: untyped) =
  ## Generate the async `onTickAsync` setter family for `AppT`. 4 overloads.

  proc onTickAsync*(app: AppT, handler: proc(): Future[TickResult] {.async.}) =
    ## Set the async tick handler called each frame between event
    ## processing and rendering.
    ##
    ## Return `trContinue` to keep running, `trQuit` to exit the loop.
    app.handlers.tick = wrapHandler(handler):
      proc(app: AppT): Future[TickResult] {.async.} =
        return await captured()

  proc onTickAsync*(app: AppT, handler: proc(app: AppT): Future[TickResult] {.async.}) =
    ## Set the async tick handler with AsyncApp context.
    app.handlers.tick = handler

  proc onTickAsync*(
      app: AppT, handler: proc(): Future[bool] {.async.}
  ) {.deprecated: "Use a handler returning TickResult instead of bool".} =
    ## Legacy `bool`-returning overload. `false` -> `trQuit`,
    ## `true` -> `trContinue`. Prefer the `TickResult`-returning overload.
    app.handlers.tick = wrapHandler(handler):
      proc(app: AppT): Future[TickResult] {.async.} =
        return if (await captured()): trContinue else: trQuit

  proc onTickAsync*(
      app: AppT, handler: proc(app: AppT): Future[bool] {.async.}
  ) {.deprecated: "Use a handler returning TickResult instead of bool".} =
    ## Legacy `bool`-returning overload with AsyncApp context.
    ## `false` -> `trQuit`, `true` -> `trContinue`.
    app.handlers.tick = wrapHandler(handler):
      proc(app: AppT): Future[TickResult] {.async.} =
        return if (await captured(app)): trContinue else: trQuit

template defineTimeoutHandlerSettersAsync*(AppT: untyped) =
  ## Generate the async `onTimeoutAsync` setter family for `AppT`.
  ## 4 overloads mirroring `onTickAsync` but invoked on input idle.

  proc onTimeoutAsync*(app: AppT, handler: proc(): Future[TickResult] {.async.}) =
    ## Set the async timeout handler for the application.
    ##
    ## The handler is called when no input events are received within
    ## the application timeout period. Return `trContinue` to keep
    ## running, `trQuit` to exit the loop.
    app.handlers.timeout = wrapHandler(handler):
      proc(app: AppT): Future[TickResult] {.async.} =
        return await captured()

  proc onTimeoutAsync*(
      app: AppT, handler: proc(app: AppT): Future[TickResult] {.async.}
  ) =
    ## Set the async timeout handler with AsyncApp context for the application.
    app.handlers.timeout = handler

  proc onTimeoutAsync*(
      app: AppT, handler: proc(): Future[bool] {.async.}
  ) {.deprecated: "Use a handler returning TickResult instead of bool".} =
    ## Legacy `bool`-returning overload. `false` -> `trQuit`,
    ## `true` -> `trContinue`. Prefer the `TickResult`-returning overload.
    app.handlers.timeout = wrapHandler(handler):
      proc(app: AppT): Future[TickResult] {.async.} =
        return if (await captured()): trContinue else: trQuit

  proc onTimeoutAsync*(
      app: AppT, handler: proc(app: AppT): Future[bool] {.async.}
  ) {.deprecated: "Use a handler returning TickResult instead of bool".} =
    ## Legacy `bool`-returning overload with AsyncApp context.
    ## `false` -> `trQuit`, `true` -> `trContinue`.
    app.handlers.timeout = wrapHandler(handler):
      proc(app: AppT): Future[TickResult] {.async.} =
        return if (await captured(app)): trContinue else: trQuit
