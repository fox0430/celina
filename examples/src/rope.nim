## Rope data structure for efficient text operations
## 
## A Rope is a binary tree where each leaf contains a short string and each node
## contains the sum of the lengths of all leaves in its left subtree. This allows
## for efficient concatenation, splitting, and editing operations.

import std/[strutils, unicode, math]

const
  ROPE_LEAF_SIZE = 1024  # Maximum size of a leaf node
  ROPE_MIN_SIZE = 512    # Minimum size before rebalancing

type
  RopeKind* = enum
    Leaf
    Branch

  RopeNode* = ref object
    weight*: int  # Length of left subtree (or this node if leaf)
    case kind*: RopeKind
    of Leaf:
      data*: string
    of Branch:
      left*, right*: RopeNode

  Rope* = object
    root*: RopeNode
    length*: int

  RopeIterator* = object
    rope: Rope
    nodeStack: seq[RopeNode]
    position: int
    currentNode: RopeNode
    currentIndex: int

proc newLeaf*(data: string): RopeNode =
  RopeNode(kind: Leaf, weight: data.len, data: data)

proc newBranch*(left, right: RopeNode): RopeNode =
  let weight = if left != nil: left.weight else: 0
  RopeNode(kind: Branch, weight: weight, left: left, right: right)

proc newRope*(text: string = ""): Rope =
  if text.len == 0:
    Rope(root: newLeaf(""), length: 0)
  elif text.len <= ROPE_LEAF_SIZE:
    Rope(root: newLeaf(text), length: text.len)
  else:
    # Split large text into chunks
    var nodes: seq[RopeNode] = @[]
    var pos = 0
    while pos < text.len:
      let endPos = min(pos + ROPE_LEAF_SIZE, text.len)
      nodes.add(newLeaf(text[pos..<endPos]))
      pos = endPos
    
    # Build balanced tree from leaves
    while nodes.len > 1:
      var newNodes: seq[RopeNode] = @[]
      for i in countup(0, nodes.len - 1, 2):
        if i + 1 < nodes.len:
          newNodes.add(newBranch(nodes[i], nodes[i + 1]))
        else:
          newNodes.add(nodes[i])
      nodes = newNodes
    
    Rope(root: nodes[0], length: text.len)

proc totalWeight(node: RopeNode): int =
  if node == nil:
    return 0
  case node.kind
  of Leaf:
    node.weight
  of Branch:
    node.weight + totalWeight(node.right)

proc charAt*(rope: Rope, index: int): char =
  if index < 0 or index >= rope.length:
    raise newException(IndexDefect, "Rope index out of bounds")
  
  var node = rope.root
  var pos = index
  
  while node != nil:
    case node.kind
    of Leaf:
      if pos < node.data.len:
        return node.data[pos]
      else:
        raise newException(IndexDefect, "Invalid rope structure")
    of Branch:
      if pos < node.weight:
        node = node.left
      else:
        pos -= node.weight
        node = node.right

proc substring*(rope: Rope, start, length: int): string =
  if start < 0 or start >= rope.length or length <= 0:
    return ""
  
  let actualLength = min(length, rope.length - start)
  result = newString(actualLength)
  
  for i in 0..<actualLength:
    result[i] = rope.charAt(start + i)

proc `$`*(rope: Rope): string =
  if rope.root == nil:
    return ""
  rope.substring(0, rope.length)

proc concat*(left, right: Rope): Rope =
  if left.length == 0:
    return right
  if right.length == 0:
    return left
  
  Rope(
    root: newBranch(left.root, right.root),
    length: left.length + right.length
  )

proc `&`*(left, right: Rope): Rope =
  concat(left, right)

proc split*(rope: Rope, index: int): tuple[left, right: Rope] =
  if index <= 0:
    return (newRope(""), rope)
  if index >= rope.length:
    return (rope, newRope(""))
  
  proc splitNode(node: RopeNode, pos: int): tuple[left, right: RopeNode] =
    if node == nil:
      return (nil, nil)
    
    case node.kind
    of Leaf:
      if pos <= 0:
        (nil, node)
      elif pos >= node.data.len:
        (node, nil)
      else:
        (newLeaf(node.data[0..<pos]), newLeaf(node.data[pos..^1]))
    of Branch:
      if pos <= 0:
        (nil, node)
      elif pos >= node.weight:
        let (rightLeft, rightRight) = splitNode(node.right, pos - node.weight)
        let leftPart = if node.left != nil and rightLeft != nil:
                        newBranch(node.left, rightLeft)
                      elif node.left != nil:
                        node.left
                      else:
                        rightLeft
        (leftPart, rightRight)
      else:
        let (leftLeft, leftRight) = splitNode(node.left, pos)
        let rightPart = if leftRight != nil and node.right != nil:
                         newBranch(leftRight, node.right)
                       elif leftRight != nil:
                         leftRight
                       else:
                         node.right
        (leftLeft, rightPart)
  
  let (leftNode, rightNode) = splitNode(rope.root, index)
  let leftRope = if leftNode != nil:
                   Rope(root: leftNode, length: index)
                 else:
                   newRope("")
  let rightRope = if rightNode != nil:
                    Rope(root: rightNode, length: rope.length - index)
                  else:
                    newRope("")
  
  (leftRope, rightRope)

proc insert*(rope: Rope, index: int, text: string): Rope =
  if text.len == 0:
    return rope
  
  let insertRope = newRope(text)
  if index <= 0:
    return insertRope & rope
  elif index >= rope.length:
    return rope & insertRope
  else:
    let (left, right) = rope.split(index)
    return left & insertRope & right

proc delete*(rope: Rope, start: int, length: int): Rope =
  if length <= 0 or start >= rope.length:
    return rope
  
  let actualStart = max(0, start)
  let actualLength = min(length, rope.length - actualStart)
  let actualEnd = actualStart + actualLength
  
  if actualStart <= 0 and actualEnd >= rope.length:
    return newRope("")
  elif actualStart <= 0:
    let (_, right) = rope.split(actualEnd)
    return right
  elif actualEnd >= rope.length:
    let (left, _) = rope.split(actualStart)
    return left
  else:
    let (left, temp) = rope.split(actualStart)
    let (_, right) = temp.split(actualLength)
    return left & right

proc replace*(rope: Rope, start: int, length: int, text: string): Rope =
  rope.delete(start, length).insert(start, text)

proc depth(node: RopeNode): int =
  if node == nil:
    return 0
  case node.kind
  of Leaf:
    1
  of Branch:
    1 + max(depth(node.left), depth(node.right))

proc isBalanced*(rope: Rope): bool =
  let d = depth(rope.root)
  # Fibonacci-based balance criterion
  d <= int(log2(float(rope.length))) + 2

proc rebalance*(rope: Rope): Rope =
  if rope.length <= ROPE_LEAF_SIZE:
    return newRope($rope)
  
  # Collect all leaves in order
  proc collectLeaves(node: RopeNode, leaves: var seq[string]) =
    if node == nil:
      return
    case node.kind
    of Leaf:
      leaves.add(node.data)
    of Branch:
      collectLeaves(node.left, leaves)
      collectLeaves(node.right, leaves)
  
  var leaves: seq[string] = @[]
  collectLeaves(rope.root, leaves)
  
  # Rebuild from concatenated text
  let fullText = leaves.join("")
  newRope(fullText)

proc findLineStart*(rope: Rope, lineNum: int): int =
  ## Find the character position where the given line starts (0-based)
  var currentLine = 0
  var pos = 0
  
  while pos < rope.length and currentLine < lineNum:
    if rope.charAt(pos) == '\n':
      inc currentLine
    inc pos
  
  if currentLine == lineNum:
    pos
  else:
    rope.length  # Line doesn't exist

proc getLine*(rope: Rope, lineNum: int): string =
  ## Get the content of a specific line (0-based, without newline)
  let lineStart = rope.findLineStart(lineNum)
  if lineStart >= rope.length:
    return ""
  
  var lineEnd = lineStart
  while lineEnd < rope.length and rope.charAt(lineEnd) != '\n':
    inc lineEnd
  
  if lineEnd > lineStart:
    rope.substring(lineStart, lineEnd - lineStart)
  else:
    ""

proc lineCount*(rope: Rope): int =
  ## Count the number of lines in the rope
  var count = 1  # At least one line
  for i in 0..<rope.length:
    if rope.charAt(i) == '\n':
      inc count
  count

proc getLines*(rope: Rope): seq[string] =
  ## Get all lines as a sequence (without newlines)
  result = @[]
  let numLines = rope.lineCount()
  for i in 0..<numLines:
    result.add(rope.getLine(i))

# Iterator support
iterator chars*(rope: Rope): char =
  for i in 0..<rope.length:
    yield rope.charAt(i)

iterator lines*(rope: Rope): string =
  let numLines = rope.lineCount()
  for i in 0..<numLines:
    yield rope.getLine(i)

# Memory usage estimation
proc estimateMemoryUsage*(rope: Rope): int =
  ## Estimate memory usage in bytes
  proc nodeMemory(node: RopeNode): int =
    if node == nil:
      return 0
    case node.kind
    of Leaf:
      sizeof(RopeNode) + node.data.len
    of Branch:
      sizeof(RopeNode) + nodeMemory(node.left) + nodeMemory(node.right)
  
  sizeof(Rope) + nodeMemory(rope.root)