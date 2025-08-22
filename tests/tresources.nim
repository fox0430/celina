## Resource management tests for Celina TUI library
##
## This test module verifies that the resource management system works correctly.

import std/[unittest, times, strformat, os, tables, options]
import ../celina/core/[resources, errors, buffer, geometry]

suite "Resource Management Tests":
  setup:
    # Initialize fresh resource manager for each test
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
    let item3 = pool.acquire()
    check createCount == 2 # No new creation

    pool.clear()

  test "Buffer resource management integration":
    let buffer = newBuffer(10, 10)
    let guard = newManagedBuffer(rect(0, 0, 10, 10), "test-managed-buffer")

    check guard.isValid
    let managedBuffer = guard.get()
    check managedBuffer.area.width == 10
    check managedBuffer.area.height == 10

  test "Buffer pool operations":
    initBufferPool(5)
    let pool = getBufferPool()

    let buffer1 = acquirePooledBuffer(rect(0, 0, 10, 10))
    let buffer2 = acquirePooledBuffer(rect(0, 0, 20, 20))

    check buffer1.area.width == 10
    check buffer2.area.width == 20

    releasePooledBuffer(buffer1)
    releasePooledBuffer(buffer2)

    # Pool should now have buffers available
    let stats = pool.getStats()
    check stats.available > 0

  test "withPooledBuffer template":
    initBufferPool(5)

    withPooledBuffer(rect(0, 0, 15, 15)):
      check buffer.area.width == 15
      check buffer.area.height == 15
      var mutableBuffer = buffer
      mutableBuffer.setString(0, 0, "test")

    # Buffer should be automatically returned to pool

  test "Buffer metrics tracking":
    resetBufferMetrics()

    trackBufferCreation(false, 100)
    trackBufferCreation(true, 200)
    trackBufferCreation(true, 150)

    let metrics = getBufferMetrics()
    check metrics.buffersCreated == 3
    check metrics.buffersFromPool == 2
    check metrics.poolHits == (2.0 / 3.0)
    check metrics.averageBufferSize > 0

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
    let id1 = rm.registerResource(RsBuffer, "leak1", cleanupProc)
    let id2 = rm.registerResource(RsTerminal, "leak2", cleanupProc)

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

  test "withManagedResource template":
    let rm = getGlobalResourceManager()
    let initialCount = rm.getResourceStats().total

    withManagedResource(42, RsBuffer, "managed-test"):
      let currentCount = rm.getResourceStats().total
      check currentCount == initialCount + 1

    # Resource should be cleaned up
    let finalCount = rm.getResourceStats().total
    check finalCount == initialCount

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

    expect ValidationError:
      discard guard.get()

  test "Resource pool overflow handling":
    let pool = newResourcePool[int](
      maxSize = 2,
      createProc = proc(): int =
        42,
      destroyProc = proc(x: int) =
        discard, # Track destruction if needed
    )

    let item1 = pool.acquire()
    let item2 = pool.acquire()
    let item3 = pool.acquire()

    # Return items - only 2 should fit in pool
    pool.release(item1)
    pool.release(item2)
    pool.release(item3) # This should be destroyed

    let stats = pool.getStats()
    check stats.available == 2

when defined(celinaDebug):
  test "Debug resource statistics dump":
    let rm = getGlobalResourceManager()

    discard rm.registerResource(RsBuffer, "debug-test")

    # This should not crash
    dumpResourceStats()

when isMainModule:
  echo "Running resource management tests..."
