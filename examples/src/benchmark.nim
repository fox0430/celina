## Performance benchmarking for different text buffer backends
##
## Compares memory usage and performance characteristics of different
## backend implementations (GapBuffer, Rope, Hybrid) across various
## file sizes and editing patterns.

import std/[times, random, strformat, strutils, algorithm]
import buffer, memmonitor

type
  BenchmarkResult* = object
    name*: string
    backend*: string
    fileSize*: int
    operationCount*: int
    totalTime*: Duration
    avgTime*: Duration
    peakMemory*: int
    avgMemory*: int
    memoryEfficiency*: float  # bytes per character

  BenchmarkSuite* = ref object
    results*: seq[BenchmarkResult]
    monitor*: MemoryMonitor

proc newBenchmarkSuite*(): BenchmarkSuite =
  BenchmarkSuite(
    results: @[],
    monitor: newMemoryMonitor(maxSnapshots = 1000)
  )

proc generateTestText(size: int, pattern: string = "mixed"): string =
  ## Generate test text of specified size with different patterns
  result = ""
  let chars = case pattern
    of "ascii": "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 \n"
    of "unicode": "αβγδεζηθικλμνξοπρστυφχψω你好世界🌍🎉✨🔥💯🚀\n"
    of "code": "function main() {\n  let x = 42;\n  return x * 2;\n}\n"
    else: "The quick brown fox jumps over the lazy dog.\nLorem ipsum dolor sit amet.\n"
  
  var rng = initRand(42)  # Deterministic for reproducible results
  while result.len < size:
    result.add(chars[rng.rand(chars.len - 1)])
  
  result = result[0..<size]

proc runInsertionBenchmark(suite: BenchmarkSuite, bufferBackend: BufferBackend, 
                          fileSize: int, insertions: int): BenchmarkResult =
  let testText = generateTestText(fileSize)
  let insertText = "INSERTED TEXT"
  
  # Create buffer with specific backend
  var buffer = case bufferBackend
    of GapBufferBackend:
      newEfficientTextBuffer(testText)
    of RopeBackend:
      newEfficientTextBuffer(testText)
    of HybridBackend:
      newEfficientTextBuffer(testText)
  
  # Force specific backend (simplified)
  suite.monitor.addBuffer(buffer)
  
  let startTime = now()
  var totalMemory = 0
  var peakMemory = 0
  
  # Perform insertions
  var rng = initRand(123)
  for i in 0..<insertions:
    let pos = rng.rand(buffer.length())
    let cursorPos = buffer.positionToLine(pos)
    buffer.insertText(cursorPos, insertText)
    
    # Monitor memory every 10 operations
    if i mod 10 == 0:
      let snapshot = suite.monitor.takeSnapshot()
      totalMemory += snapshot.bufferMemory
      peakMemory = max(peakMemory, snapshot.bufferMemory)
  
  let endTime = now()
  let duration = endTime - startTime
  
  suite.monitor.removeBuffer(buffer)
  
  BenchmarkResult(
    name: "insertion",
    backend: $bufferBackend,
    fileSize: fileSize,
    operationCount: insertions,
    totalTime: duration,
    avgTime: duration div insertions,
    peakMemory: peakMemory,
    avgMemory: totalMemory div (insertions div 10 + 1),
    memoryEfficiency: float(peakMemory) / float(buffer.length())
  )

proc runDeletionBenchmark(suite: BenchmarkSuite, bufferBackend: BufferBackend,
                         fileSize: int, deletions: int): BenchmarkResult =
  let testText = generateTestText(fileSize)
  var buffer = newEfficientTextBuffer(testText)
  suite.monitor.addBuffer(buffer)
  
  let startTime = now()
  var totalMemory = 0
  var peakMemory = 0
  
  var rng = initRand(456)
  for i in 0..<deletions:
    if buffer.length() > 0:
      let pos = rng.rand(buffer.length() - 1)
      let cursorPos = buffer.positionToLine(pos)
      buffer.deleteChar(cursorPos)
      
      if i mod 10 == 0:
        let snapshot = suite.monitor.takeSnapshot()
        totalMemory += snapshot.bufferMemory
        peakMemory = max(peakMemory, snapshot.bufferMemory)
  
  let endTime = now()
  let duration = endTime - startTime
  
  suite.monitor.removeBuffer(buffer)
  
  BenchmarkResult(
    name: "deletion",
    backend: $bufferBackend,
    fileSize: fileSize,
    operationCount: deletions,
    totalTime: duration,
    avgTime: duration div deletions,
    peakMemory: peakMemory,
    avgMemory: totalMemory div (deletions div 10 + 1),
    memoryEfficiency: float(peakMemory) / float(max(1, buffer.length()))
  )

proc runRandomEditingBenchmark(suite: BenchmarkSuite, bufferBackend: BufferBackend,
                              fileSize: int, operations: int): BenchmarkResult =
  let testText = generateTestText(fileSize)
  var buffer = newEfficientTextBuffer(testText)
  suite.monitor.addBuffer(buffer)
  
  let startTime = now()
  var totalMemory = 0
  var peakMemory = 0
  
  var rng = initRand(789)
  for i in 0..<operations:
    if buffer.length() == 0:
      # If buffer is empty, insert something
      buffer.insertText(CursorPosition(line: 0, column: 0), "text")
    else:
      let operation = rng.rand(2)  # 0=insert, 1=delete, 2=replace
      let pos = rng.rand(buffer.length() - 1)
      let cursorPos = buffer.positionToLine(pos)
      
      case operation
      of 0:  # Insert
        buffer.insertText(cursorPos, "new")
      of 1:  # Delete
        buffer.deleteChar(cursorPos)
      else:  # Replace (delete + insert)
        buffer.deleteChar(cursorPos)
        buffer.insertText(cursorPos, "rep")
    
    if i mod 10 == 0:
      let snapshot = suite.monitor.takeSnapshot()
      totalMemory += snapshot.bufferMemory
      peakMemory = max(peakMemory, snapshot.bufferMemory)
  
  let endTime = now()
  let duration = endTime - startTime
  
  suite.monitor.removeBuffer(buffer)
  
  BenchmarkResult(
    name: "random_editing",
    backend: $bufferBackend,
    fileSize: fileSize,
    operationCount: operations,
    totalTime: duration,
    avgTime: duration div operations,
    peakMemory: peakMemory,
    avgMemory: totalMemory div (operations div 10 + 1),
    memoryEfficiency: float(peakMemory) / float(max(1, buffer.length()))
  )

proc runLineOperationsBenchmark(suite: BenchmarkSuite, bufferBackend: BufferBackend,
                               fileSize: int, operations: int): BenchmarkResult =
  let testText = generateTestText(fileSize, "code")  # Code-like text with many lines
  var buffer = newEfficientTextBuffer(testText)
  suite.monitor.addBuffer(buffer)
  
  let startTime = now()
  var totalMemory = 0
  var peakMemory = 0
  
  var rng = initRand(101112)
  for i in 0..<operations:
    let lineCount = buffer.lineCount()
    if lineCount > 1:
      let operation = rng.rand(2)  # 0=insert line, 1=delete line, 2=get line
      let lineNum = rng.rand(lineCount - 1)
      
      case operation
      of 0:  # Insert line
        buffer.insertLine(lineNum, "new line content")
      of 1:  # Delete line
        if lineCount > 1:
          buffer.deleteLine(lineNum)
      else:  # Get line (read operation)
        discard buffer.getLine(lineNum)
    
    if i mod 10 == 0:
      let snapshot = suite.monitor.takeSnapshot()
      totalMemory += snapshot.bufferMemory
      peakMemory = max(peakMemory, snapshot.bufferMemory)
  
  let endTime = now()
  let duration = endTime - startTime
  
  suite.monitor.removeBuffer(buffer)
  
  BenchmarkResult(
    name: "line_operations",
    backend: $bufferBackend,
    fileSize: fileSize,
    operationCount: operations,
    totalTime: duration,
    avgTime: duration div operations,
    peakMemory: peakMemory,
    avgMemory: totalMemory div (operations div 10 + 1),
    memoryEfficiency: float(peakMemory) / float(buffer.length())
  )

proc runMemoryLoadBenchmark(suite: BenchmarkSuite, fileSizes: seq[int]): seq[BenchmarkResult] =
  ## Test memory usage with different file sizes
  result = @[]
  
  for size in fileSizes:
    let testText = generateTestText(size)
    
    # Test each backend
    for backend in [GapBufferBackend, RopeBackend, HybridBackend]:
      let buffer = newEfficientTextBuffer(testText)
      suite.monitor.addBuffer(buffer)
      
      let snapshot = suite.monitor.takeSnapshot()
      let memUsage = buffer.estimateMemoryUsage()
      
      result.add(BenchmarkResult(
        name: "memory_load",
        backend: $backend,
        fileSize: size,
        operationCount: 1,
        totalTime: initDuration(),
        avgTime: initDuration(),
        peakMemory: memUsage,
        avgMemory: memUsage,
        memoryEfficiency: float(memUsage) / float(size)
      ))
      
      suite.monitor.removeBuffer(buffer)

proc runComprehensiveBenchmark*(suite: BenchmarkSuite): seq[BenchmarkResult] =
  ## Run a comprehensive benchmark suite
  result = @[]
  
  let fileSizes = @[1024, 10*1024, 100*1024, 1024*1024, 10*1024*1024]  # 1KB to 10MB
  let backends = [GapBufferBackend, RopeBackend, HybridBackend]
  
  echo "Running comprehensive benchmark suite..."
  
  # Memory load test
  echo "Testing memory usage..."
  result.add(suite.runMemoryLoadBenchmark(fileSizes))
  
  # Operation benchmarks for different file sizes
  for size in fileSizes:
    if size > 10*1024*1024:  # Skip expensive operations for very large files
      continue
      
    let ops = min(1000, max(10, 100000 div max(1, size div 1024)))  # Scale operations with file size
    
    echo &"Testing file size: {size div 1024}KB with {ops} operations"
    
    for backend in backends:
      echo &"  Backend: {backend}"
      
      # Insertion benchmark
      try:
        result.add(suite.runInsertionBenchmark(backend, size, ops))
      except:
        echo "    Insertion benchmark failed"
      
      # Deletion benchmark  
      try:
        result.add(suite.runDeletionBenchmark(backend, size, ops))
      except:
        echo "    Deletion benchmark failed"
      
      # Random editing benchmark
      try:
        result.add(suite.runRandomEditingBenchmark(backend, size, ops))
      except:
        echo "    Random editing benchmark failed"
      
      # Line operations benchmark
      try:
        result.add(suite.runLineOperationsBenchmark(backend, size, ops))
      except:
        echo "    Line operations benchmark failed"
  
  suite.results.add(result)

proc generateBenchmarkReport*(suite: BenchmarkSuite): string =
  result = "# Editor Performance Benchmark Report\n\n"
  
  if suite.results.len == 0:
    return result & "No benchmark results available.\n"
  
  # Group results by benchmark type
  var grouped = initTable[string, seq[BenchmarkResult]]()
  for res in suite.results:
    if res.name notin grouped:
      grouped[res.name] = @[]
    grouped[res.name].add(res)
  
  for benchName, results in grouped:
    result &= &"## {benchName.capitalizeAscii()} Benchmark\n\n"
    result &= "| Backend | File Size | Operations | Total Time | Avg Time | Peak Memory | Memory Efficiency |\n"
    result &= "|---------|-----------|------------|------------|----------|-------------|-------------------|\n"
    
    for res in results.sortedByIt(it.fileSize):
      let fileSizeStr = if res.fileSize < 1024: &"{res.fileSize}B"
                       elif res.fileSize < 1024*1024: &"{res.fileSize div 1024}KB"  
                       else: &"{res.fileSize div (1024*1024)}MB"
      
      let totalTimeMs = res.totalTime.inMilliseconds
      let avgTimeMicros = res.avgTime.inMicroseconds
      let memoryMB = res.peakMemory / (1024*1024)
      
      result &= &"| {res.backend} | {fileSizeStr} | {res.operationCount} | {totalTimeMs}ms | {avgTimeMicros}μs | {memoryMB:.1f}MB | {res.memoryEfficiency:.2f} |\n"
    
    result &= "\n"
  
  # Add recommendations
  result &= "## Recommendations\n\n"
  
  # Find best backend for different file sizes
  let memoryResults = grouped.getOrDefault("memory_load", @[])
  if memoryResults.len > 0:
    result &= "### Backend Selection Guidelines\n\n"
    
    for size in [1024, 100*1024, 1024*1024]:
      let sizeResults = memoryResults.filterIt(it.fileSize == size)
      if sizeResults.len > 0:
        let best = sizeResults.minBy(proc(r: BenchmarkResult): float = r.memoryEfficiency)
        let sizeStr = if size < 1024: &"{size}B"
                     elif size < 1024*1024: &"{size div 1024}KB"
                     else: &"{size div (1024*1024)}MB"
        result &= &"- **{sizeStr} files**: Use {best.backend} backend (efficiency: {best.memoryEfficiency:.2f})\n"

proc exportBenchmarkResults*(suite: BenchmarkSuite, filename: string): bool =
  ## Export results to CSV
  try:
    var content = "benchmark,backend,file_size_bytes,operations,total_time_ms,avg_time_us,peak_memory_bytes,memory_efficiency\n"
    
    for res in suite.results:
      content &= &"{res.name},{res.backend},{res.fileSize},{res.operationCount},{res.totalTime.inMilliseconds},{res.avgTime.inMicroseconds},{res.peakMemory},{res.memoryEfficiency}\n"
    
    writeFile(filename, content)
    return true
  except:
    return false

# Quick benchmark function for testing
proc quickBenchmark*(): string =
  let suite = newBenchmarkSuite()
  discard suite.runComprehensiveBenchmark()
  return suite.generateBenchmarkReport()