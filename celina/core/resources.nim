## Resource management and RAII patterns
##
## This module provides centralized resource management with:
## - RAII-style automatic resource cleanup
## - Resource leak detection and monitoring
## - Performance optimization through pooling
## - Thread-safe resource tracking

import std/[tables, sets, options, times, locks, hashes]
import errors

type
  ResourceType* = enum
    ## Types of resources being managed
    RsTerminal
    RsBuffer
    RsFile
    RsNetwork
    RsAsyncHandle
    RsSelector

  ResourceState* = enum
    ## Current state of a resource
    RsActive
    RsReleasing
    RsReleased
    RsError

  ResourceId* = distinct uint64 ## Unique identifier for each resource

  ResourceInfo* = object ## Information about a managed resource
    id*: ResourceId
    resourceType*: ResourceType
    state*: ResourceState
    createdAt*: Time
    lastAccessed*: Time
    name*: string
    cleanupProc*: proc() {.closure.}

  ResourceManager* = ref object ## Central resource manager with leak detection
    resources*: Table[ResourceId, ResourceInfo]
    nextId: uint64
    lock: Lock
    leakDetectionEnabled*: bool
    maxResourceAge*: Duration

  ResourceGuard*[T] = object ## RAII guard for automatic resource cleanup
    resource*: T
    cleanup*: proc(r: T) {.closure.}
    resourceId*: ResourceId
    isValid*: bool

  ResourcePool*[T] = ref object ## Generic resource pool for reuse
    available*: seq[T]
    inUse*: HashSet[T]
    maxSize*: int
    createProc*: proc(): T {.closure.}
    resetProc*: proc(item: T) {.closure.}
    destroyProc*: proc(item: T) {.closure.}

# Global resource manager
var
  globalLock: Lock
  globalResourceManager* {.guard: globalLock.}: ResourceManager

# ============================================================================
# ResourceId Operations
# ============================================================================

proc `$`*(id: ResourceId): string =
  $uint64(id)

proc `==`*(a, b: ResourceId): bool =
  uint64(a) == uint64(b)

proc hash*(id: ResourceId): Hash =
  hash(uint64(id))

# ============================================================================
# ResourceManager Implementation
# ============================================================================

proc newResourceManager*(): ResourceManager =
  ## Create a new resource manager
  result = ResourceManager(
    resources: initTable[ResourceId, ResourceInfo](),
    nextId: 1,
    leakDetectionEnabled: true,
    maxResourceAge: initDuration(minutes = 30),
  )
  initLock(result.lock)

proc initGlobalResourceManager*() =
  ## Initialize the global resource manager (thread-safe)
  withLock(globalLock):
    if globalResourceManager.isNil:
      globalResourceManager = newResourceManager()

proc getGlobalResourceManager*(): ResourceManager =
  ## Get the global resource manager, initializing if needed
  withLock(globalLock):
    if globalResourceManager.isNil:
      globalResourceManager = newResourceManager()
    result = globalResourceManager

proc generateId(rm: ResourceManager): ResourceId =
  ## Generate a unique resource ID (assumes lock is held)
  result = ResourceId(rm.nextId)
  rm.nextId.inc()

proc registerResource*(
    rm: ResourceManager,
    resourceType: ResourceType,
    name: string,
    cleanupProc: proc() {.closure.} = nil,
): ResourceId =
  ## Register a new resource for tracking
  withLock(rm.lock):
    let id = rm.generateId()
    let now = getTime()
    rm.resources[id] = ResourceInfo(
      id: id,
      resourceType: resourceType,
      state: RsActive,
      createdAt: now,
      lastAccessed: now,
      name: name,
      cleanupProc: cleanupProc,
    )
    result = id

proc unregisterResource*(rm: ResourceManager, id: ResourceId) =
  ## Unregister a resource
  withLock(rm.lock):
    if id in rm.resources:
      rm.resources[id].state = RsReleased
      rm.resources.del(id)

proc touchResource*(rm: ResourceManager, id: ResourceId) =
  ## Update last accessed time for a resource
  withLock(rm.lock):
    if id in rm.resources:
      rm.resources[id].lastAccessed = getTime()

proc getResourceInfo*(rm: ResourceManager, id: ResourceId): Option[ResourceInfo] =
  ## Get information about a resource
  withLock(rm.lock):
    result =
      if id in rm.resources:
        some(rm.resources[id])
      else:
        none(ResourceInfo)

proc getAllResources*(rm: ResourceManager): seq[ResourceInfo] =
  ## Get information about all active resources
  withLock(rm.lock):
    result = @[]
    for info in rm.resources.values:
      result.add(info)

proc checkForLeaks*(rm: ResourceManager): seq[ResourceInfo] =
  ## Check for potential resource leaks
  if not rm.leakDetectionEnabled:
    return @[]

  let now = getTime()
  withLock(rm.lock):
    result = @[]
    for info in rm.resources.values:
      if info.state == RsActive and (now - info.lastAccessed) > rm.maxResourceAge:
        result.add(info)

proc cleanupLeakedResources*(rm: ResourceManager): int =
  ## Cleanup leaked resources and return count
  let leaks = rm.checkForLeaks()
  result = leaks.len

  for leak in leaks:
    try:
      if not leak.cleanupProc.isNil:
        leak.cleanupProc()
      rm.unregisterResource(leak.id)
    except CatchableError as e:
      when defined(celinaDebug):
        stderr.writeLine(&"Failed to cleanup leaked resource {leak.id}: {e.msg}")
      else:
        discard e

proc getResourceStats*(
    rm: ResourceManager
): tuple[total: int, byType: Table[ResourceType, int]] =
  ## Get resource statistics
  withLock(rm.lock):
    result.total = rm.resources.len
    result.byType = initTable[ResourceType, int]()
    for info in rm.resources.values:
      result.byType.mgetOrPut(info.resourceType, 0).inc()

# ============================================================================
# ResourceGuard Implementation (RAII)
# ============================================================================

proc newResourceGuard*[T](
    resource: T,
    cleanup: proc(r: T) {.closure.},
    resourceType: ResourceType = RsBuffer,
    name: string = "unnamed",
): ResourceGuard[T] =
  ## Create a new RAII resource guard
  let rm = getGlobalResourceManager()
  let id = rm.registerResource(
    resourceType,
    name,
    proc() =
      cleanup(resource),
  )

  result = ResourceGuard[T](
    resource: resource, cleanup: cleanup, resourceId: id, isValid: true
  )

proc release*[T](guard: var ResourceGuard[T]) =
  ## Manually release the resource
  if guard.isValid:
    try:
      guard.cleanup(guard.resource)
    except CatchableError as e:
      let rm = getGlobalResourceManager()
      rm.unregisterResource(guard.resourceId)
      raise newTerminalError("Resource cleanup failed", inner = e)

    let rm = getGlobalResourceManager()
    rm.unregisterResource(guard.resourceId)
    guard.isValid = false

proc isValid*[T](guard: ResourceGuard[T]): bool =
  ## Check if the guard is still valid
  guard.isValid

proc get*[T](guard: ResourceGuard[T]): T =
  ## Get the underlying resource (updates last accessed time)
  if not guard.isValid:
    raise newValidationError("Accessing invalid resource guard", "guard")

  let rm = getGlobalResourceManager()
  rm.touchResource(guard.resourceId)
  guard.resource

template withResourceGuard*[T](
    resource: T,
    cleanup: proc(r: T) {.closure.},
    resourceType: ResourceType,
    name: string,
    body: untyped,
): untyped =
  ## Template for automatic resource management
  var guard = newResourceGuard(resource, cleanup, resourceType, name)
  try:
    # Make the resource available as 'resource' in the body
    template resource(): untyped =
      guard.get()

    body
  finally:
    guard.release()

# ============================================================================
# ResourcePool Implementation
# ============================================================================

proc newResourcePool*[T](
    maxSize: int,
    createProc: proc(): T {.closure.},
    resetProc: proc(item: T) {.closure.} = nil,
    destroyProc: proc(item: T) {.closure.} = nil,
): ResourcePool[T] =
  ## Create a new resource pool
  result = ResourcePool[T](
    available: @[],
    inUse: initHashSet[T](),
    maxSize: maxSize,
    createProc: createProc,
    resetProc: resetProc,
    destroyProc: destroyProc,
  )

proc acquire*[T](pool: ResourcePool[T]): T =
  ## Acquire a resource from the pool
  if pool.available.len > 0:
    result = pool.available.pop()
    if not pool.resetProc.isNil:
      pool.resetProc(result)
  else:
    result = pool.createProc()

  pool.inUse.incl(result)

proc release*[T](pool: ResourcePool[T], item: T) =
  ## Release a resource back to the pool
  if item notin pool.inUse:
    return

  pool.inUse.excl(item)

  if pool.available.len < pool.maxSize:
    pool.available.add(item)
  else:
    # Pool is full, destroy the item
    if not pool.destroyProc.isNil:
      pool.destroyProc(item)

proc clear*[T](pool: ResourcePool[T]) =
  ## Clear all resources from the pool
  for item in pool.available:
    if not pool.destroyProc.isNil:
      pool.destroyProc(item)
  pool.available.setLen(0)

  # Note: We don't force cleanup of in-use items as they may still be needed
  pool.inUse.clear()

proc getStats*[T](pool: ResourcePool[T]): tuple[available: int, inUse: int] =
  ## Get pool statistics
  (available: pool.available.len, inUse: pool.inUse.len)

# ============================================================================
# Convenience Templates and Procedures
# ============================================================================

template withManagedResource*[T](
    resource: T, resourceType: ResourceType, name: string, body: untyped
): untyped =
  ## Simple template for resource management without custom cleanup
  let rm = getGlobalResourceManager()
  let id = rm.registerResource(resourceType, name)
  try:
    body
  finally:
    rm.unregisterResource(id)

proc cleanupAllResources*() =
  ## Emergency cleanup of all registered resources
  let rm = getGlobalResourceManager()
  let resources = rm.getAllResources()

  for resource in resources:
    try:
      if not resource.cleanupProc.isNil:
        resource.cleanupProc()
      rm.unregisterResource(resource.id)
    except CatchableError:
      # Best effort cleanup - don't fail on individual resource errors
      discard

when defined(celinaDebug):
  proc dumpResourceStats*() =
    ## Debug helper to dump resource statistics
    let rm = getGlobalResourceManager()
    let stats = rm.getResourceStats()
    echo &"Total resources: {stats.total}"
    for resourceType, count in stats.byType:
      echo &"  {resourceType}: {count}"

    let leaks = rm.checkForLeaks()
    if leaks.len > 0:
      echo &"Potential leaks: {leaks.len}"
      for leak in leaks:
        let age = getTime() - leak.lastAccessed
        echo &"  {leak.name} ({leak.resourceType}): {age}"

# Initialize global resource manager on module load
initLock(globalLock)
