## Resource management tests

import std/[unittest, times, os, tables, options, hashes]
import ../celina/core/[resources]

suite "Resource Management Tests":
  setup:
    # Initialize fresh resource manager for each test
    cleanupAllResources()
    initGlobalResourceManager()

  test "ResourceManager creation and basic operations":
    let rm = newResourceManager()
    check rm != nil
    check rm.leakDetectionEnabled == true

    let stats = rm.getResourceStats()
    check stats.total == 0

  test "Resource registration and unregistration":
    let rm = getGlobalResourceManager()

    let id = rm.registerResource(RsBuffer, "test-buffer")
    check uint64(id) > 0

    let stats = rm.getResourceStats()
    check stats.total == 1
    check stats.byType.getOrDefault(RsBuffer) == 1

    rm.unregisterResource(id)
    let statsAfter = rm.getResourceStats()
    check statsAfter.total == 0

  test "Resource information tracking":
    let rm = getGlobalResourceManager()

    let id = rm.registerResource(RsTerminal, "test-terminal")
    let info = rm.getResourceInfo(id)

    check info.isSome
    check info.get.resourceType == RsTerminal
    check info.get.name == "test-terminal"
    check info.get.state == RsActive

  test "Resource access time tracking":
    let rm = getGlobalResourceManager()

    let id = rm.registerResource(RsBuffer, "test-buffer")
    let initialInfo = rm.getResourceInfo(id).get

    sleep(10) # Small delay
    rm.touchResource(id)

    let updatedInfo = rm.getResourceInfo(id).get
    check updatedInfo.lastAccessed > initialInfo.lastAccessed

  test "ResourceGuard RAII pattern":
    var cleanupCalled = false
    let cleanup = proc(val: int) =
      cleanupCalled = true

    block:
      var guard = newResourceGuard(42, cleanup, RsBuffer, "test-guard")
      check guard.isValid
      check guard.get() == 42

    # Guard should be automatically released when going out of scope
    # But we need to manually call release for testing
    # In real usage, this would be handled by destructors

  test "ResourceGuard manual release":
    var cleanupCalled = false
    let cleanup = proc(val: int) =
      cleanupCalled = true

    var guard = newResourceGuard(42, cleanup, RsBuffer, "test-guard")
    check guard.isValid

    guard.release()
    check not guard.isValid
    check cleanupCalled

  test "ResourcePool creation and usage":
    var createCount = 0
    let createProc = proc(): int =
      createCount.inc()
      createCount

    let pool = newResourcePool[int](maxSize = 3, createProc = createProc)

    # Acquire items
    let item1 = pool.acquire()
    let item2 = pool.acquire()
    check item1 == 1
    check item2 == 2
    check createCount == 2

    # Return items
    pool.release(item1)
    pool.release(item2)

    # Acquire again - should reuse
    discard pool.acquire()
    check createCount == 2 # No new creation

    pool.clear()

  test "Leak detection":
    let rm = newResourceManager()
    rm.maxResourceAge = initDuration(milliseconds = 50)

    # Create a resource and don't touch it
    let id = rm.registerResource(RsBuffer, "leak-test")

    sleep(100) # Wait longer than maxResourceAge

    let leaks = rm.checkForLeaks()
    check leaks.len == 1
    check leaks[0].id == id

  test "Cleanup leaked resources":
    let rm = newResourceManager()
    rm.maxResourceAge = initDuration(milliseconds = 50)

    var cleanupCount = 0
    let cleanupProc = proc() =
      cleanupCount.inc()

    # Create multiple resources
    discard rm.registerResource(RsBuffer, "leak1", cleanupProc)
    discard rm.registerResource(RsTerminal, "leak2", cleanupProc)

    sleep(100) # Wait for them to become stale

    let cleanedCount = rm.cleanupLeakedResources()
    check cleanedCount == 2
    check cleanupCount == 2

    # Resources should be gone
    let statsAfter = rm.getResourceStats()
    check statsAfter.total == 0

  test "Resource statistics by type":
    let rm = getGlobalResourceManager()

    discard rm.registerResource(RsBuffer, "buffer1")
    discard rm.registerResource(RsBuffer, "buffer2")
    discard rm.registerResource(RsTerminal, "terminal1")

    let stats = rm.getResourceStats()
    check stats.total == 3
    check stats.byType.getOrDefault(RsBuffer) == 2
    check stats.byType.getOrDefault(RsTerminal) == 1

  test "Emergency cleanup all resources":
    let rm = getGlobalResourceManager()

    var cleanupCount = 0
    let cleanupProc = proc() =
      cleanupCount.inc()

    # Register several resources
    discard rm.registerResource(RsBuffer, "test1", cleanupProc)
    discard rm.registerResource(RsTerminal, "test2", cleanupProc)
    discard rm.registerResource(RsFile, "test3", cleanupProc)

    let statsBefore = rm.getResourceStats()
    check statsBefore.total == 3

    cleanupAllResources()

    let statsAfter = rm.getResourceStats()
    check statsAfter.total == 0
    check cleanupCount == 3

  test "ResourceGuard with invalid access":
    var guard = newResourceGuard(
      42,
      proc(x: int) =
        discard,
      RsBuffer,
      "test",
    )
    guard.release()

    # Attempting to access released guard should raise ValueError
    expect ValueError:
      discard guard.get()

  test "Resource pool overflow handling":
    # Use string type which already has hash function
    var idCounter = 0
    let pool = newResourcePool[string](
      maxSize = 2,
      createProc = proc(): string =
        idCounter.inc()
        "item-" & $idCounter,
      destroyProc = proc(x: string) =
        discard, # Track destruction if needed
    )

    let item1 = pool.acquire()
    let item2 = pool.acquire()
    let item3 = pool.acquire()

    # Verify we got 3 different strings
    check item1 == "item-1"
    check item2 == "item-2"
    check item3 == "item-3"

    # Return items - only 2 should fit in pool
    pool.release(item1)
    pool.release(item2)
    pool.release(item3) # This should be destroyed

    let stats = pool.getStats()
    check stats.available == 2
