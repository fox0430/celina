## Memory usage monitoring for the editor
##
## Provides real-time memory usage tracking and optimization suggestions
## to help identify memory bottlenecks and performance issues.

import std/[times, tables, strformat, os, strutils]
import buffer
import efficientbuffer

type
  MemorySnapshot* = object
    timestamp*: DateTime
    totalMemory*: int
    bufferMemory*: int
    systemMemory*: int
    activeBuffers*: int

  MemoryMonitor* = ref object
    snapshots*: seq[MemorySnapshot]
    buffers*: seq[buffer.TextBuffer]
    maxSnapshots*: int
    monitoringEnabled*: bool
    warningThreshold*: int  # MB
    criticalThreshold*: int # MB

proc newMemoryMonitor*(maxSnapshots: int = 100, warningMB: int = 100, criticalMB: int = 500): MemoryMonitor =
  MemoryMonitor(
    snapshots: @[],
    buffers: @[],
    maxSnapshots: maxSnapshots,
    monitoringEnabled: true,
    warningThreshold: warningMB * 1024 * 1024,  # Convert to bytes
    criticalThreshold: criticalMB * 1024 * 1024
  )

proc getSystemMemoryUsage(): int =
  ## Get current system memory usage (approximate)
  when defined(linux):
    try:
      let statm = readFile("/proc/self/statm").split()
      if statm.len >= 2:
        # VmRSS in pages, convert to bytes (assuming 4KB pages)
        return parseInt(statm[1]) * 4096
    except:
      discard
  
  # Fallback: return 0 if we can't determine usage
  return 0

proc addBuffer*(monitor: MemoryMonitor, buffer: buffer.TextBuffer) =
  monitor.buffers.add(buffer)

proc removeBuffer*(monitor: MemoryMonitor, buffer: buffer.TextBuffer) =
  for i, buf in monitor.buffers:
    if buf == buffer:
      monitor.buffers.delete(i)
      break

proc calculateBufferMemory(monitor: MemoryMonitor): int =
  result = 0
  for buffer in monitor.buffers:
    result += efficientbuffer.estimateMemoryUsage(buffer)

proc takeSnapshot*(monitor: MemoryMonitor): MemorySnapshot =
  if not monitor.monitoringEnabled:
    return MemorySnapshot()
  
  let bufferMem = monitor.calculateBufferMemory()
  let sysMem = getSystemMemoryUsage()
  
  result = MemorySnapshot(
    timestamp: now(),
    totalMemory: sysMem,
    bufferMemory: bufferMem,
    systemMemory: sysMem - bufferMem,
    activeBuffers: monitor.buffers.len
  )
  
  monitor.snapshots.add(result)
  
  # Limit snapshot history
  if monitor.snapshots.len > monitor.maxSnapshots:
    monitor.snapshots.delete(0)

proc getLatestSnapshot*(monitor: MemoryMonitor): MemorySnapshot =
  if monitor.snapshots.len > 0:
    monitor.snapshots[^1]
  else:
    monitor.takeSnapshot()

proc getAverageMemoryUsage*(monitor: MemoryMonitor, lastN: int = 10): float =
  if monitor.snapshots.len == 0:
    return 0.0
  
  let count = min(lastN, monitor.snapshots.len)
  var total = 0
  
  for i in (monitor.snapshots.len - count)..<monitor.snapshots.len:
    total += monitor.snapshots[i].totalMemory
  
  total.float / count.float

proc getMemoryTrend*(monitor: MemoryMonitor, lastN: int = 20): string =
  ## Analyze memory usage trend over last N snapshots
  if monitor.snapshots.len < 2:
    return "insufficient_data"
  
  let count = min(lastN, monitor.snapshots.len)
  let start = monitor.snapshots.len - count
  
  var increasing = 0
  var decreasing = 0
  var stable = 0
  
  for i in (start + 1)..<monitor.snapshots.len:
    let prev = monitor.snapshots[i - 1].totalMemory
    let curr = monitor.snapshots[i].totalMemory
    let diff = abs(curr - prev)
    
    if diff < 1024 * 1024:  # Less than 1MB difference = stable
      inc stable
    elif curr > prev:
      inc increasing
    else:
      inc decreasing
  
  if increasing > decreasing and increasing > stable:
    return "increasing"
  elif decreasing > increasing and decreasing > stable:
    return "decreasing"
  else:
    return "stable"

proc checkMemoryAlerts*(monitor: MemoryMonitor): seq[string] =
  result = @[]
  let snapshot = monitor.getLatestSnapshot()
  
  if snapshot.totalMemory > monitor.criticalThreshold:
    result.add(&"CRITICAL: Memory usage {snapshot.totalMemory div (1024*1024)}MB exceeds critical threshold")
  elif snapshot.totalMemory > monitor.warningThreshold:
    result.add(&"WARNING: Memory usage {snapshot.totalMemory div (1024*1024)}MB exceeds warning threshold")
  
  # Check for rapid memory growth
  if monitor.snapshots.len >= 5:
    let recent = monitor.snapshots[^5..^1]
    let growth = recent[^1].totalMemory - recent[0].totalMemory
    if growth > 50 * 1024 * 1024:  # 50MB growth in 5 snapshots
      result.add(&"WARNING: Rapid memory growth detected (+{growth div (1024*1024)}MB)")
  
  # Check buffer efficiency
  if snapshot.activeBuffers > 0:
    let avgBufferSize = snapshot.bufferMemory div snapshot.activeBuffers
    if avgBufferSize > 10 * 1024 * 1024:  # 10MB per buffer seems high
      result.add(&"WARNING: Large average buffer size ({avgBufferSize div (1024*1024)}MB per buffer)")

proc generateMemoryReport*(monitor: MemoryMonitor): string =
  let snapshot = monitor.getLatestSnapshot()
  let trend = monitor.getMemoryTrend()
  let avgUsage = monitor.getAverageMemoryUsage()
  let alerts = monitor.checkMemoryAlerts()
  
  result = &"""
Memory Usage Report
===================
Current Usage: {snapshot.totalMemory div (1024*1024)} MB
  - Buffer Memory: {snapshot.bufferMemory div (1024*1024)} MB
  - System Memory: {snapshot.systemMemory div (1024*1024)} MB
  - Active Buffers: {snapshot.activeBuffers}

Average Usage (last 10): {avgUsage / (1024*1024):.1f} MB
Memory Trend: {trend}

Buffer Details:"""

  for i, buffer in monitor.buffers:
    let stats = getPerformanceStats(buffer)
    result &= &"\n  Buffer {i+1}: {stats.backend}, {stats.memoryUsage div 1024} KB, {stats.length} chars"
  
  if alerts.len > 0:
    result &= "\n\nAlerts:\n"
    for alert in alerts:
      result &= &"  - {alert}\n"

proc getOptimizationSuggestions*(monitor: MemoryMonitor): seq[string] =
  result = @[]
  let snapshot = monitor.getLatestSnapshot()
  
  if snapshot.activeBuffers == 0:
    return @["No active buffers to optimize"]
  
  let avgBufferSize = snapshot.bufferMemory div snapshot.activeBuffers
  
  # Suggest backend optimization
  for buffer in monitor.buffers:
    let stats = getPerformanceStats(buffer)
    if stats.length < 100 * 1024 and stats.backend != "GapBuffer":
      result.add(&"Consider using GapBuffer backend for small file ({stats.length} chars)")
    elif stats.length > 10 * 1024 * 1024 and stats.backend != "Rope":
      result.add(&"Consider using Rope backend for large file ({stats.length div (1024*1024)} MB)")
  
  # Suggest memory cleanup
  if avgBufferSize > 5 * 1024 * 1024:
    result.add("Consider closing unused buffers to reduce memory usage")
  
  # Suggest rebalancing for Rope structures
  for buffer in monitor.buffers:
    let stats = getPerformanceStats(buffer)
    if stats.backend == "Rope" and stats.memoryUsage > stats.length * 2:
      result.add("Consider rebalancing Rope structure to reduce memory overhead")

proc enableMonitoring*(monitor: MemoryMonitor) =
  monitor.monitoringEnabled = true

proc disableMonitoring*(monitor: MemoryMonitor) =
  monitor.monitoringEnabled = false

proc clearHistory*(monitor: MemoryMonitor) =
  monitor.snapshots = @[]

proc exportSnapshots*(monitor: MemoryMonitor, filename: string): bool =
  ## Export snapshots to CSV file for analysis
  try:
    var content = "timestamp,total_memory_mb,buffer_memory_mb,system_memory_mb,active_buffers\n"
    
    for snapshot in monitor.snapshots:
      content &= &"{snapshot.timestamp.toTime().toUnix()},{snapshot.totalMemory div (1024*1024)},{snapshot.bufferMemory div (1024*1024)},{snapshot.systemMemory div (1024*1024)},{snapshot.activeBuffers}\n"
    
    writeFile(filename, content)
    return true
  except:
    return false

# Global memory monitor instance
var globalMemoryMonitor* = newMemoryMonitor()

# Convenience functions for global monitoring
proc monitorBuffer*(buffer: buffer.TextBuffer) =
  globalMemoryMonitor.addBuffer(buffer)

proc unmonitorBuffer*(buffer: buffer.TextBuffer) =
  globalMemoryMonitor.removeBuffer(buffer)

proc takeMemorySnapshot*(): MemorySnapshot =
  globalMemoryMonitor.takeSnapshot()

proc getMemoryReport*(): string =
  globalMemoryMonitor.generateMemoryReport()

proc getMemoryAlerts*(): seq[string] =
  globalMemoryMonitor.checkMemoryAlerts()

proc getOptimizationTips*(): seq[string] =
  globalMemoryMonitor.getOptimizationSuggestions()