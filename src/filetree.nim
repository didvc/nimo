## File tree sidebar model: lazily lists directories, tracks expanded state
## by path, and flattens the visible entries for rendering. Nim stdlib only.

import std/[os, algorithm, sets, tables, strutils]

type
  FlatEntry* = object
    path*, name*: string
    isDir*: bool
    depth*: int

  FileTree* = ref object
    root*: string
    expanded: HashSet[string]
    cache: Table[string, seq[FlatEntry]]
    flat*: seq[FlatEntry]
    sel*, scroll*: int

proc listChildren(t: FileTree, dir: string): seq[FlatEntry] =
  if dir in t.cache:
    return t.cache[dir]
  var dirs, files: seq[FlatEntry]
  try:
    for kind, path in walkDir(dir):
      let name = path.lastPathPart
      if name == ".git": continue
      case kind
      of pcDir, pcLinkToDir:
        dirs.add FlatEntry(path: path, name: name, isDir: true)
      of pcFile, pcLinkToFile:
        files.add FlatEntry(path: path, name: name, isDir: false)
  except OSError:
    discard
  proc byName(a, b: FlatEntry): int = cmpIgnoreCase(a.name, b.name)
  dirs.sort(byName)
  files.sort(byName)
  result = dirs & files
  t.cache[dir] = result

proc rebuild*(t: FileTree) =
  t.flat.setLen 0
  proc recurse(dir: string, depth: int) =
    for e in t.listChildren(dir):
      var entry = e
      entry.depth = depth
      t.flat.add entry
      if e.isDir and e.path in t.expanded:
        recurse(e.path, depth + 1)
  recurse(t.root, 0)
  t.sel = clamp(t.sel, 0, max(0, t.flat.len - 1))

proc newFileTree*(root: string): FileTree =
  result = FileTree(root: root)
  result.rebuild()

proc refresh*(t: FileTree) =
  t.cache.clear()
  t.rebuild()

proc isExpanded*(t: FileTree, path: string): bool =
  path in t.expanded

proc hasSelection*(t: FileTree): bool =
  t.flat.len > 0 and t.sel in 0 ..< t.flat.len

proc selected*(t: FileTree): FlatEntry =
  t.flat[t.sel]

proc toggle*(t: FileTree) =
  if not t.hasSelection: return
  let e = t.selected
  if e.isDir:
    if e.path in t.expanded: t.expanded.excl e.path
    else: t.expanded.incl e.path
    t.rebuild()

proc expandSel*(t: FileTree) =
  if not t.hasSelection: return
  let e = t.selected
  if e.isDir:
    if e.path notin t.expanded:
      t.expanded.incl e.path
      t.rebuild()
    elif t.sel < t.flat.len - 1:
      inc t.sel # already open: step into first child

proc collapseSel*(t: FileTree) =
  if not t.hasSelection: return
  let e = t.selected
  if e.isDir and e.path in t.expanded:
    t.expanded.excl e.path
    t.rebuild()
  elif e.depth > 0:
    # jump to the parent entry
    var i = t.sel - 1
    while i >= 0:
      if t.flat[i].depth < e.depth:
        t.sel = i
        break
      dec i

proc revealPath*(t: FileTree, path: string) =
  ## Selects `path` in the tree if it is under the root, expanding as needed.
  if not path.isRelativeTo(t.root): return
  var dir = path.parentDir
  while dir.len > t.root.len and dir.isRelativeTo(t.root):
    t.expanded.incl dir
    dir = dir.parentDir
  t.rebuild()
  for i, e in t.flat:
    if e.path == path:
      t.sel = i
      break
