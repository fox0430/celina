## Async File Manager Demo
##
## `nimble install chronos`
## `nim c -d:asyncBackend=chronos examples/async_file_manager.nim`
##
## A comprehensive example demonstrating real-world usage of Celina's async capabilities.
## Features:
## - Multi-window interface (directory list, file preview, status bar)
## - Async file operations with non-blocking I/O
## - Keyboard navigation (vim-style)

import std/[os, strformat, times, strutils, algorithm, options, sequtils]

import pkg/celina

when not defined(asyncBackend) or asyncBackend != "chronos":
  {.fatal: "This example require `-d:asyncBackend=chronos`".}

type
  # Performance optimization flags
  UpdateFlags = object
    directory: bool
    preview: bool
    status: bool

  FileManagerApp = ref object
    app: AsyncApp
    dirListWindow: WindowId
    previewWindow: WindowId
    statusWindow: WindowId
    currentDir: string
    selectedIndex: int
    files: seq[string]
    fileItems: seq[FileItem] # Cache file items to avoid repeated getFileInfo calls
    isLoading: bool
    statusMessage: string
    updateFlags: UpdateFlags # Track what needs updating
    lastSelectedIndex: int # Track selection changes
    scrollOffset: int # Track current scroll position

  FileType = enum
    ftDirectory
    ftRegularFile
    ftExecutable
    ftSymlink
    ftOther

  FileItem = object
    name: string
    path: string
    fileType: FileType
    size: int64
    modified: Time

proc getFileType(path: string): FileType =
  ## Determine file type for display and navigation
  if path.dirExists():
    return ftDirectory
  elif path.fileExists():
    let info = path.getFileInfo()
    if (info.permissions * {fpUserExec, fpGroupExec, fpOthersExec}) != {}:
      return ftExecutable
    else:
      return ftRegularFile
  elif path.symlinkExists():
    return ftSymlink
  else:
    return ftOther

proc getFileIcon(fileType: FileType): string =
  ## Get icon character for file type
  case fileType
  of ftDirectory: "[D]"
  of ftRegularFile: "[F]"
  of ftExecutable: "[X]"
  of ftSymlink: "[L]"
  of ftOther: "[?]"

proc formatFileSize(size: int64): string =
  ## Format file size for human reading
  if size < 1024:
    return fmt"{size} B"
  elif size < 1024 * 1024:
    return fmt"{size div 1024} KB"
  elif size < 1024 * 1024 * 1024:
    return fmt"{size div (1024 * 1024)} MB"
  else:
    return fmt"{size div (1024 * 1024 * 1024)} GB"

proc loadDirectoryAsync(
    fm: FileManagerApp, path: string
): Future[seq[FileItem]] {.async.} =
  ## Asynchronously load directory contents with caching
  fm.isLoading = true
  fm.statusMessage = fmt"Loading directory: {path}"
  fm.updateFlags.status = true

  # Yield to allow UI update
  await sleepAsync(chronos.milliseconds(1))

  try:
    result = @[]

    # Add parent directory entry if not root
    if path != "/" and path != "":
      result.add(
        FileItem(
          name: "/..",
          path: path.parentDir(),
          fileType: ftDirectory,
          size: 0,
          modified: getTime(),
        )
      )

    # Read directory contents
    for kind, itemPath in walkDir(path):
      let name = itemPath.extractFilename()

      # Skip hidden files for now (can be made configurable)
      if name.startsWith(".") and name != "..":
        continue

      var item = FileItem(name: name, path: itemPath, fileType: getFileType(itemPath))

      # Get file info safely - this is expensive, so we cache it
      try:
        let info = itemPath.getFileInfo()
        item.size = info.size
        item.modified = info.lastWriteTime
      except:
        item.size = 0
        item.modified = getTime()

      result.add(item)

    # Sort: directories first, then by name
    result.sort(
      proc(a, b: FileItem): int =
        if a.fileType == ftDirectory and b.fileType != ftDirectory:
          return -1
        elif a.fileType != ftDirectory and b.fileType == ftDirectory:
          return 1
        else:
          return cmp(a.name.toLowerAscii(), b.name.toLowerAscii())
    )

    fm.statusMessage = fmt"Loaded {result.len} items from {path}"
    fm.updateFlags.status = true
  except Exception as e:
    fm.statusMessage = fmt"Error loading directory: {e.msg}"
    fm.updateFlags.status = true
    result = @[]
  finally:
    fm.isLoading = false

  # Small delay to show loading state
  await sleepAsync(chronos.milliseconds(50))

proc updateDirectoryWindowAsync(fm: FileManagerApp): Future[void] {.async.} =
  ## Update the directory listing window
  let dirWindowOpt = await fm.app.getWindowAsync(fm.dirListWindow)
  if dirWindowOpt == none(Window):
    return

  let window = dirWindowOpt.get()

  # Clear buffer - work directly with window.buffer, not a copy!
  window.buffer.clear()

  # Header
  let header = fmt"Directory: {fm.currentDir}"
  window.buffer.setString(1, 0, header, Style(fg: color(Cyan), modifiers: {Bold}))

  if fm.isLoading:
    window.buffer.setString(1, 2, "Loading...", Style(fg: color(Yellow)))
    return

  if fm.files.len == 0:
    window.buffer.setString(1, 2, "No files found", Style(fg: color(Red)))
    return

  # File list
  let startY = 2
  let maxVisible = window.buffer.area.height - startY - 1

  # Calculate scroll position - only scroll when at first or last item
  if fm.files.len > maxVisible:
    if fm.selectedIndex == 0:
      # At first item - scroll to top
      fm.scrollOffset = 0
    elif fm.selectedIndex == fm.files.len - 1:
      # At last item - scroll to show last page
      fm.scrollOffset = max(0, fm.files.len - maxVisible)
    else:
      # For middle items, ensure the selected item is visible
      # Only adjust scroll if selected item is outside current view
      if fm.selectedIndex < fm.scrollOffset:
        fm.scrollOffset = fm.selectedIndex
      elif fm.selectedIndex >= fm.scrollOffset + maxVisible:
        fm.scrollOffset = fm.selectedIndex - maxVisible + 1

  let startIndex = fm.scrollOffset

  for i in 0 ..< min(fm.files.len, maxVisible):
    let fileIndex = startIndex + i
    if fileIndex >= fm.files.len:
      break

    let isSelected = fileIndex == fm.selectedIndex
    let y = startY + i

    # Selection highlight
    let style =
      if isSelected:
        Style(fg: color(Black), bg: color(White), modifiers: {Bold})
      else:
        defaultStyle()

    # Format file entry using cached file info
    let fileName = fm.files[fileIndex]
    let displayName =
      if fileName.len > window.buffer.area.width - 10:
        fileName[0 ..< window.buffer.area.width - 13] & "..."
      else:
        fileName

    # Use cached fileItems instead of expensive getFileType call
    let fileType =
      if fileIndex < fm.fileItems.len:
        fm.fileItems[fileIndex].fileType
      else:
        ftOther
    let icon = getFileIcon(fileType)
    let entry = fmt"{icon} {displayName}"

    window.buffer.setString(1, y, entry, style)

  # Status line at bottom
  let statusY = window.buffer.area.height - 1
  let statusText = fmt"{fm.selectedIndex + 1}/{fm.files.len}"
  window.buffer.setString(1, statusY, statusText, Style(fg: color(Green)))

proc updatePreviewWindowAsync(fm: FileManagerApp): Future[void] {.async.} =
  ## Update the file preview window
  let previewWindow = await fm.app.getWindowAsync(fm.previewWindow)
  if previewWindow == none(Window):
    return

  let window = previewWindow.get()

  # Clear buffer - work directly with window.buffer
  window.buffer.clear()

  # Header
  window.buffer.setString(1, 0, "Preview", Style(fg: color(Magenta), modifiers: {Bold}))

  if fm.files.len == 0 or fm.selectedIndex >= fm.files.len:
    window.buffer.setString(1, 2, "No file selected", Style(fg: color(Yellow)))
    return

  let selectedFile = fm.files[fm.selectedIndex]
  let filePath = fm.currentDir / selectedFile

  # Use cached file info for better performance
  let fileItem =
    if fm.selectedIndex < fm.fileItems.len:
      fm.fileItems[fm.selectedIndex]
    else:
      FileItem(
        name: selectedFile,
        path: filePath,
        fileType: getFileType(filePath),
        size: 0,
        modified: getTime(),
      )

  # File info
  var y = 2
  window.buffer.setString(1, y, fmt"Name: {selectedFile}", defaultStyle())
  y.inc()

  window.buffer.setString(1, y, fmt"Type: {fileItem.fileType}", defaultStyle())
  y.inc()

  # File details from cache
  window.buffer.setString(
    1, y, fmt"Size: {formatFileSize(fileItem.size)}", defaultStyle()
  )
  y.inc()

  let modTime = fileItem.modified.format("yyyy-MM-dd HH:mm:ss")
  window.buffer.setString(1, y, fmt"Modified: {modTime}", defaultStyle())
  y.inc()

  # Preview content for text files
  if fileItem.fileType == ftRegularFile and y < window.buffer.area.height - 2:
    y.inc()
    window.buffer.setString(1, y, "--- Content Preview ---", Style(fg: color(Cyan)))
    y.inc()

    try:
      let content = readFile(filePath)
      let lines = content.splitLines()
      let maxLines = min(lines.len, window.buffer.area.height - y - 1)

      for i in 0 ..< maxLines:
        if y >= window.buffer.area.height - 1:
          break
        let line =
          if lines[i].len > window.buffer.area.width - 2:
            lines[i][0 ..< window.buffer.area.width - 5] & "..."
          else:
            lines[i]
        window.buffer.setString(1, y, line, Style(fg: color(White)))
        y.inc()

      if lines.len > maxLines:
        window.buffer.setString(1, y, "...", Style(fg: color(Yellow)))
    except:
      window.buffer.setString(1, y, "Cannot preview file", Style(fg: color(Red)))

proc updateStatusWindowAsync(fm: FileManagerApp): Future[void] {.async.} =
  ## Update the status bar window
  let statusWindow = await fm.app.getWindowAsync(fm.statusWindow)
  if statusWindow == none(Window):
    return

  let window = statusWindow.get()

  # Clear buffer - work directly with window.buffer
  window.buffer.clear()

  # Status message
  window.buffer.setString(1, 0, fm.statusMessage, Style(fg: color(Green)))

  # Help text
  let helpText = "j/k: navigate  Enter: open  q: quit  r: refresh"
  let helpX = max(1, window.buffer.area.width - helpText.len - 1)
  window.buffer.setString(helpX, 0, helpText, Style(fg: color(Blue)))

proc updateWindowsAsync(fm: FileManagerApp): Future[void] {.async.} =
  ## Update only windows that need updating (performance optimization)
  if fm.updateFlags.directory:
    await fm.updateDirectoryWindowAsync()
    fm.updateFlags.directory = false

  if fm.updateFlags.preview:
    await fm.updatePreviewWindowAsync()
    fm.updateFlags.preview = false

  if fm.updateFlags.status:
    await fm.updateStatusWindowAsync()
    fm.updateFlags.status = false

proc markSelectionChanged(fm: FileManagerApp) =
  ## Mark that selection has changed - triggers preview update
  if fm.selectedIndex != fm.lastSelectedIndex:
    fm.updateFlags.preview = true
    fm.updateFlags.directory = true # Need to update selection highlight
    fm.lastSelectedIndex = fm.selectedIndex

proc refreshAsync(fm: FileManagerApp): Future[void] {.async.} =
  ## Refresh the current directory with performance optimization
  let fileItems = await fm.loadDirectoryAsync(fm.currentDir)
  fm.fileItems = fileItems # Cache the file items
  fm.files = fileItems.mapIt(it.name)

  # Ensure selected index is valid
  if fm.selectedIndex >= fm.files.len:
    fm.selectedIndex = max(0, fm.files.len - 1)

  # Mark all for update due to directory change
  fm.updateFlags.directory = true
  fm.updateFlags.preview = true
  fm.updateFlags.status = true

  # Update only what needs updating
  await fm.updateWindowsAsync()

proc navigateToAsync(fm: FileManagerApp, path: string): Future[void] {.async.} =
  ## Navigate to a new directory
  try:
    let absolutePath = path.absolutePath()
    fm.currentDir = absolutePath
    fm.selectedIndex = 0
    fm.scrollOffset = 0 # Reset scroll position
    fm.lastSelectedIndex = -1 # Force selection update
    await fm.refreshAsync()
  except Exception as e:
    fm.statusMessage = fmt"Cannot navigate to {path}: {e.msg}"
    fm.updateFlags.status = true
    await fm.updateWindowsAsync()

proc openSelectedAsync(fm: FileManagerApp): Future[void] {.async.} =
  ## Open the currently selected file or directory
  if fm.files.len == 0 or fm.selectedIndex >= fm.files.len:
    return

  let selectedFile = fm.files[fm.selectedIndex]
  let fullPath = fm.currentDir / selectedFile

  if selectedFile == "..":
    await fm.navigateToAsync(fm.currentDir.parentDir())
  elif fullPath.dirExists():
    await fm.navigateToAsync(fullPath)
  else:
    fm.statusMessage = fmt"File: {selectedFile} (press Enter again to open)"
    fm.updateFlags.status = true
    await fm.updateWindowsAsync()

proc handleKeyEventAsync(fm: FileManagerApp, key: KeyEvent): Future[bool] {.async.} =
  ## Handle keyboard input
  case key.code
  of Char:
    case key.char
    of 'q', 'Q':
      return false # Quit
    of 'j', 'J':
      # Move down
      if fm.selectedIndex < fm.files.len - 1:
        fm.selectedIndex.inc()
        fm.markSelectionChanged()
        await fm.updateWindowsAsync()
    of 'k', 'K':
      # Move up
      if fm.selectedIndex > 0:
        fm.selectedIndex.dec()
        fm.markSelectionChanged()
        await fm.updateWindowsAsync()
    of 'r', 'R':
      # Refresh
      await fm.refreshAsync()
    of 'g':
      # Go to top
      fm.selectedIndex = 0
      fm.scrollOffset = 0
      fm.markSelectionChanged()
      await fm.updateWindowsAsync()
    of 'G':
      # Go to bottom
      fm.selectedIndex = max(0, fm.files.len - 1)
      # scrollOffset will be set in updateDirectoryWindowAsync
      fm.markSelectionChanged()
      await fm.updateWindowsAsync()
    else:
      discard
  of Enter:
    await fm.openSelectedAsync()
  of ArrowUp:
    if fm.selectedIndex > 0:
      fm.selectedIndex.dec()
      fm.markSelectionChanged()
      await fm.updateWindowsAsync()
  of ArrowDown:
    if fm.selectedIndex < fm.files.len - 1:
      fm.selectedIndex.inc()
      fm.markSelectionChanged()
      await fm.updateWindowsAsync()
  else:
    discard

  return true

proc createFileManagerWindows(fm: FileManagerApp): Future[void] {.async.} =
  ## Create the file manager window layout
  let termSize = fm.app.getTerminalSize()

  # Directory list window (left side)
  let dirWindow = newWindow(
    area = rect(0, 0, termSize.width * 2 div 3, termSize.height - 2),
    title = "Directory",
  )
  fm.dirListWindow = await fm.app.addWindowAsync(dirWindow)

  # Preview window (right side)
  let previewWindow = newWindow(
    area = rect(termSize.width * 2 div 3, 0, termSize.width div 3, termSize.height - 2),
    title = "Preview",
  )
  fm.previewWindow = await fm.app.addWindowAsync(previewWindow)

  # Status window (bottom)
  let statusWindow =
    newWindow(area = rect(0, termSize.height - 2, termSize.width, 2), title = "")
  fm.statusWindow = await fm.app.addWindowAsync(statusWindow)

proc newFileManagerApp(): Future[FileManagerApp] {.async.} =
  ## Create a new file manager application
  let config = AsyncAppConfig(
    title: "Async File Manager", windowMode: true, mouseCapture: false, targetFps: 30
  )

  result = FileManagerApp(
    app: newAsyncApp(config),
    currentDir: getCurrentDir(),
    selectedIndex: 0,
    files: @[],
    fileItems: @[],
    isLoading: false,
    statusMessage: "Ready",
    updateFlags: UpdateFlags(directory: false, preview: false, status: false),
    lastSelectedIndex: -1,
    scrollOffset: 0,
  )

  # Set up event handling
  let fm = result # Store reference for closure
  result.app.onEventAsync proc(event: Event): Future[bool] {.async.} =
    case event.kind
    of Key:
      return await fm.handleKeyEventAsync(event.key)
    else:
      return true

  # Set up rendering
  result.app.onRenderAsync proc(
      buffer: async_buffer.AsyncBuffer
  ): Future[void] {.async.} =
    # Background is handled by window manager
    discard

  # Create windows
  await result.createFileManagerWindows()

  # Initial load
  await result.refreshAsync()

proc runFileManagerAsync(): Future[void] {.async.} =
  try:
    let fm = await newFileManagerApp()

    let config = AsyncAppConfig(
      title: "Async File Manager", windowMode: true, mouseCapture: false, targetFps: 30
    )

    await fm.app.runAsync(config)
  except CatchableError as e:
    echo "Error in file manager: ", e.msg
  finally:
    echo "👋 File manager closed."

proc main() =
  try:
    waitFor runFileManagerAsync()
  except AssertionDefect:
    discard
  except CatchableError as e:
    echo "Error: ", e.msg

when isMainModule:
  main()
