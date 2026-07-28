## nimo (Nim Terminal Text Editor) — a nano-inspired terminal text editor.
##
## Layout: a file-tree sidebar on the left, a tab bar across the top of the
## editor pane, the editor below it, then a status line and a keybinding hint
## line at the bottom. Mouse clicks select tree entries, switch/close tabs and
## place the cursor; the wheel scrolls whichever pane is under the pointer.
## Nim standard library only.

import std/[os, strutils, unicode, exitprocs]
import term, textbuffer, filetree

type
  Focus = enum foEditor, foTree

  Mode = enum mNormal, mPrompt

  PromptKind = enum
    pkNone, pkSave, pkQuitConfirm, pkCloseConfirm, pkSearch, pkGoto, pkNewFile

  TabSpan = tuple[idx, x0, x1, markerX: int] ## terminal columns of one tab

  Editor = ref object
    buffers: seq[TextBuffer] ## open tabs
    current: int             ## index of the active tab
    tree: FileTree
    focus: Focus
    mode: Mode
    rows, cols: int
    sidebarW: int
    showTree: bool
    status: string
    statusIsError: bool
    prompt: PromptKind
    promptLabel: string
    promptInput: string
    lastSearch: string
    running: bool
    pendingClose: int        ## tab awaiting close confirmation
    tabScroll: int           ## index of the leftmost visible tab
    tabSpans: seq[TabSpan]    ## hit-test regions, recomputed each render

const
  SidebarDefault = 30
  TopBarRows = 1 ## the tab / sidebar-header row
  Version = "0.1.0"

template buf(e: Editor): TextBuffer = e.buffers[e.current]

# ---- small helpers ----------------------------------------------------------

proc setStatus(e: Editor, msg: string, err = false) =
  e.status = msg
  e.statusIsError = err

proc editorWidth(e: Editor): int =
  if e.showTree: e.cols - e.sidebarW - 1 else: e.cols
proc editorHeight(e: Editor): int =
  max(1, e.rows - 2 - TopBarRows) # minus status + hint + top bar
proc editorX0(e: Editor): int =
  if e.showTree: e.sidebarW + 1 else: 0

proc updateWinsize(e: Editor) =
  let (w, h) = terminalSize()
  e.rows = h
  e.cols = w
  e.sidebarW = min(SidebarDefault, e.cols div 3)
  if e.cols < 40: e.showTree = false

proc bufName(b: TextBuffer): string =
  if b.path.len > 0: b.path.lastPathPart else: "[No Name]"

const TabNameMax = 24

proc tabLabel(b: TextBuffer): string
proc tabWidth(e: Editor, i: int): int

proc ensureTabVisible(e: Editor) =
  ## Scrolls the tab strip so the active tab is on screen. Called only when the
  ## active tab changes, so the user's own horizontal scrolling is preserved.
  e.tabScroll = clamp(e.tabScroll, 0, e.buffers.high)
  if e.current < e.tabScroll:
    e.tabScroll = e.current
    return
  let barW = e.editorWidth
  while e.tabScroll < e.current:
    var used = (if e.tabScroll > 0: 1 else: 0) + 1 # left + right chevron reserve
    for i in e.tabScroll .. e.current: used += e.tabWidth(i)
    if used <= barW: break
    inc e.tabScroll

# ---- rendering --------------------------------------------------------------

proc ellipsize(s: string, w: int): string =
  if w <= 0: return ""
  if s.runeLen <= w: return s
  if w == 1: return "…"
  result = ""
  var used = 0
  for r in s.runes:
    if used >= w - 1: break
    result.add r
    inc used
  result.add "…"

proc tabLabel(b: TextBuffer): string = ellipsize(bufName(b), TabNameMax)
proc tabWidth(e: Editor, i: int): int = tabLabel(e.buffers[i]).runeLen + 4 # " name × "

const
  cReset = "\e[0m"
  cSideBar = "\e[38;5;244m"      # dim gray for tree chrome
  cDir = "\e[1;38;5;39m"         # bold blue directories
  cSelActive = "\e[48;5;24m"     # focused selection: teal bg
  cSelInactive = "\e[48;5;236m"  # unfocused selection: gray bg
  cStatus = "\e[48;5;24m\e[97m"  # status bar
  cStatusErr = "\e[48;5;88m\e[97m"
  cHint = "\e[38;5;245m"
  cLineNo = "\e[38;5;240m"
  cModified = "\e[38;5;214m"     # amber dot
  cHeader = "\e[48;5;235m\e[1;38;5;250m" # sidebar header
  cTabBar = "\e[48;5;235m"       # empty tab strip
  cTabActive = "\e[48;5;24m\e[97m"
  cTabInactive = "\e[48;5;237m\e[38;5;250m"
  cTabDim = "\e[38;5;244m"       # the × close glyph

proc padTo(s: string, visibleLen, width: int): string =
  ## Appends spaces so a string of known visible length fills `width` columns.
  result = s
  if visibleLen < width: result.add " ".repeat(width - visibleLen)

proc drawTopBar(e: Editor, sb: var string) =
  e.tabSpans.setLen 0
  # sidebar header (left)
  if e.showTree:
    let root = e.tree.root.lastPathPart
    let head = ellipsize(" " & root.toUpperAscii, e.sidebarW)
    sb.add "\e[1;1H" & cHeader & padTo(head, head.runeLen, e.sidebarW) & cReset
    sb.add "\e[1;" & $(e.sidebarW + 1) & "H" & cSideBar & "│" & cReset
  # tab bar (over the editor pane), horizontally scrollable when it overflows
  let x0 = e.editorX0
  let barW = e.editorWidth
  let lastCol = x0 + barW            # rightmost editor-pane column (1-based)
  var total = 0
  for i in 0 ..< e.buffers.len: total += e.tabWidth(i)
  let scrolling = total > barW
  if not scrolling: e.tabScroll = 0
  e.tabScroll = clamp(e.tabScroll, 0, e.buffers.high)
  let leftChev = e.tabScroll > 0
  var col = x0 + 1
  if leftChev:
    sb.add "\e[1;" & $col & "H" & cTabBar & "‹" & cReset
    e.tabSpans.add (idx: -1, x0: col, x1: col, markerX: -1) # scroll-left hit
    inc col
  else:
    sb.add "\e[1;" & $col & "H"
  let drawMax = if scrolling: lastCol - 1 else: lastCol # reserve › when scrolling
  var lastDrawn = e.tabScroll - 1
  var i = e.tabScroll
  while i < e.buffers.len:
    let w = e.tabWidth(i)
    if col + w - 1 > drawMax: break
    let label = tabLabel(e.buffers[i])
    let style = if i == e.current: cTabActive else: cTabInactive
    let marker = if e.buffers[i].modified: cModified & "●" else: cTabDim & "×"
    sb.add style & " " & label & " " & marker & style & " " & cReset
    e.tabSpans.add (idx: i, x0: col, x1: col + w - 1, markerX: col + label.runeLen + 2)
    col += w
    lastDrawn = i
    inc i
  let rightChev = lastDrawn < e.buffers.high
  let fillTo = if rightChev: lastCol - 1 else: lastCol
  if col <= fillTo:
    sb.add cTabBar & " ".repeat(fillTo - col + 1) & cReset
  if rightChev:
    sb.add "\e[1;" & $lastCol & "H" & cTabBar & "›" & cReset
    e.tabSpans.add (idx: -2, x0: lastCol, x1: lastCol, markerX: -1) # scroll-right hit

proc drawTree(e: Editor, sb: var string) =
  let h = e.editorHeight
  if e.tree.sel < e.tree.scroll: e.tree.scroll = e.tree.sel
  elif e.tree.sel >= e.tree.scroll + h: e.tree.scroll = e.tree.sel - h + 1
  for row in 0 ..< h:
    let ty = row + 1 + TopBarRows # terminal row
    sb.add "\e[" & $ty & ";1H"
    let idx = e.tree.scroll + row
    if idx >= e.tree.flat.len:
      sb.add cSideBar & " ".repeat(e.sidebarW) & cReset
    else:
      let entry = e.tree.flat[idx]
      let isSel = idx == e.tree.sel
      if isSel:
        sb.add (if e.focus == foTree: cSelActive else: cSelInactive)
      var indicator = "  "
      if entry.isDir:
        indicator = if e.tree.isExpanded(entry.path): "▾ " else: "▸ "
      let indent = "  ".repeat(entry.depth)
      let avail = e.sidebarW - indent.len - indicator.len
      let name = ellipsize(entry.name, avail)
      let visLen = indent.len + indicator.len + name.runeLen
      var line = indent & indicator
      if entry.isDir and not isSel: line.add cDir & name & cReset
      elif entry.isDir: line.add name
      else: line.add name
      if isSel and entry.isDir:
        line = indent & indicator & name # keep selection bg unbroken
      line.add " ".repeat(max(0, e.sidebarW - visLen))
      sb.add line & cReset
    sb.add "\e[" & $ty & ";" & $(e.sidebarW + 1) & "H" & cSideBar & "│" & cReset

proc drawEditor(e: Editor, sb: var string) =
  let h = e.editorHeight
  let x0 = e.editorX0
  let gutterW = max(3, ($e.buf.lines.len).len) + 1
  let textW = e.editorWidth - gutterW
  for row in 0 ..< h:
    let ty = row + 1 + TopBarRows
    sb.add "\e[" & $ty & ";" & $(x0 + 1) & "H\e[K"
    let li = e.buf.editTop + row
    if li >= e.buf.lines.len:
      sb.add cLineNo & "~" & cReset
    else:
      let num = align($(li + 1), gutterW - 1)
      sb.add cLineNo & num & " " & cReset
      sb.add expandSlice(e.buf.lines[li], e.buf.editLeft, textW)

proc drawStatus(e: Editor, sb: var string) =
  sb.add "\e[" & $(e.rows - 1) & ";1H\e[K"
  let barCol = if e.statusIsError: cStatusErr else: cStatus
  let name = bufName(e.buf)
  let dirty = if e.buf.modified: cModified & " ●" & cReset & barCol else: ""
  let tabInfo = if e.buffers.len > 1: "  [" & $(e.current + 1) & "/" &
                $e.buffers.len & "]" else: ""
  let pos = "Ln " & $(e.buf.cursor.line + 1) & ", Col " & $(e.buf.runeCol + 1)
  let left = " " & name & dirty & tabInfo & "  " &
             (if e.status.len > 0: e.status else: "")
  sb.add barCol
  let plainLeftLen = 1 + name.runeLen + (if e.buf.modified: 2 else: 0) +
                     tabInfo.len + 2 + (if e.status.len > 0: e.status.len else: 0)
  var content = left
  let stop = e.cols - pos.len - 1
  if plainLeftLen < stop:
    content.add " ".repeat(stop - plainLeftLen)
  content.add pos & " "
  sb.add content & cReset

proc drawHint(e: Editor, sb: var string) =
  sb.add "\e[" & $e.rows & ";1H\e[K" & cHint
  let hint =
    if e.mode == mPrompt:
      e.promptLabel & e.promptInput & "▏"
    elif e.focus == foTree:
      "click/Enter Open  n New  r Refresh  ^B Tree  ^X Quit"
    else:
      when suspendSupported:
        "^S Save  ^F Find  ^U Undo  ^R Redo  ^W Close  ^B Tree  ^Z Suspend  ^X Quit"
      else: # no job control: don't advertise a key that cannot work
        "^S Save  ^F Find  ^U Undo  ^R Redo  ^W Close  ^B Tree  ^G Goto  ^X Quit"
  sb.add ellipsize(hint, e.cols) & cReset

proc scrollToCursor(e: Editor) =
  let h = e.editorHeight
  let w = e.editorWidth
  if e.buf.cursor.line < e.buf.editTop: e.buf.editTop = e.buf.cursor.line
  elif e.buf.cursor.line >= e.buf.editTop + h: e.buf.editTop = e.buf.cursor.line - h + 1
  let cx = dispCol(e.buf.curLine, e.buf.cursor.col)
  if cx < e.buf.editLeft: e.buf.editLeft = cx
  elif cx >= e.buf.editLeft + w: e.buf.editLeft = cx - w + 1
  if e.buf.editLeft < 0: e.buf.editLeft = 0

proc placeCursor(e: Editor, sb: var string) =
  if e.mode == mPrompt:
    let cx = e.promptLabel.runeLen + e.promptInput.runeLen + 1
    sb.add "\e[" & $e.rows & ";" & $(min(cx, e.cols)) & "H\e[?25h"
    return
  if e.focus == foTree:
    sb.add "\e[?25l" # hide cursor while navigating the tree
    return
  let gutterW = max(3, ($e.buf.lines.len).len) + 1
  let cy = e.buf.cursor.line - e.buf.editTop + 1 + TopBarRows
  let cx = e.editorX0 + gutterW + dispCol(e.buf.curLine, e.buf.cursor.col) -
           e.buf.editLeft + 1
  sb.add "\e[?25h\e[" & $cy & ";" & $cx & "H"

proc render(e: Editor) =
  e.scrollToCursor()
  var sb = "\e[?25l\e[H"
  e.drawTopBar(sb)
  if e.showTree: e.drawTree(sb)
  e.drawEditor(sb)
  e.drawStatus(sb)
  e.drawHint(sb)
  e.placeCursor(sb)
  stdout.write sb
  stdout.flushFile

# ---- prompts ----------------------------------------------------------------

proc startPrompt(e: Editor, kind: PromptKind, label: string, initial = "") =
  e.mode = mPrompt
  e.prompt = kind
  e.promptLabel = label
  e.promptInput = initial

proc endPrompt(e: Editor) =
  e.mode = mNormal
  e.prompt = pkNone
  e.promptInput = ""

# ---- tab / file operations --------------------------------------------------

proc normPath(p: string): string =
  if p.len == 0: return ""
  try: p.absolutePath except OSError: p

proc setWish(e: Editor) =
  e.buf.wishCol = dispCol(e.buf.curLine, e.buf.cursor.col)

proc openPath(e: Editor, path: string) =
  let full = normPath(path)
  for i, b in e.buffers:
    if b.path.len > 0 and normPath(b.path) == full:
      e.current = i
      e.focus = foEditor
      e.ensureTabVisible()
      e.setStatus("Switched to " & full.lastPathPart)
      return
  try:
    let nb = loadFile(path)
    nb.clampCursor()
    e.buffers.add nb
    e.current = e.buffers.high
    e.focus = foEditor
    e.ensureTabVisible()
    e.tree.revealPath(full)
    e.setStatus("Opened " & path.lastPathPart)
  except IOError, OSError:
    e.setStatus("Can't open: " & getCurrentExceptionMsg(), err = true)

proc forceClose(e: Editor, i: int) =
  if i < 0 or i >= e.buffers.len: return
  e.buffers.delete(i)
  if e.buffers.len == 0:
    e.buffers.add newTextBuffer()
  if e.current >= i and e.current > 0: dec e.current
  e.current = clamp(e.current, 0, e.buffers.high)
  e.ensureTabVisible()
  e.setStatus("Closed tab")

proc closeTabAt(e: Editor, i: int) =
  if i < 0 or i >= e.buffers.len: return
  if e.buffers[i].modified:
    e.pendingClose = i
    e.current = i
    e.startPrompt(pkCloseConfirm, "Close tab without saving? (y/n): ")
  else:
    e.forceClose(i)

proc nextTab(e: Editor) =
  if e.buffers.len > 1:
    e.current = (e.current + 1) mod e.buffers.len
    e.focus = foEditor
    e.ensureTabVisible()

proc prevTab(e: Editor) =
  if e.buffers.len > 1:
    e.current = (e.current - 1 + e.buffers.len) mod e.buffers.len
    e.focus = foEditor
    e.ensureTabVisible()

proc doSave(e: Editor, path: string): bool =
  try:
    writeFile(path, e.buf.toFileString)
    e.buf.path = path
    e.buf.markSaved()
    e.tree.refresh()
    e.tree.revealPath(normPath(path))
    e.setStatus("Saved " & path.lastPathPart)
    return true
  except IOError, OSError:
    e.setStatus("Can't save: " & getCurrentExceptionMsg(), err = true)
    return false

proc handleSave(e: Editor) =
  if e.buf.path.len > 0: discard e.doSave(e.buf.path)
  else: e.startPrompt(pkSave, "Save as: ", e.tree.root / "untitled.txt")

proc anyModified(e: Editor): bool =
  for b in e.buffers:
    if b.modified: return true
  false

proc requestQuit(e: Editor) =
  if e.anyModified():
    e.startPrompt(pkQuitConfirm, "Unsaved changes in open tabs. Quit anyway? (y/n): ")
  else:
    e.running = false

proc finishPrompt(e: Editor) =
  let input = e.promptInput
  let kind = e.prompt
  e.endPrompt()
  case kind
  of pkSave:
    if input.len > 0: discard e.doSave(input)
  of pkNewFile:
    if input.len > 0:
      let dir =
        if e.tree.hasSelection and e.tree.selected.isDir: e.tree.selected.path
        elif e.tree.hasSelection: e.tree.selected.path.parentDir
        else: e.tree.root
      let full = dir / input
      try:
        if not fileExists(full): writeFile(full, "")
        e.tree.refresh()
        e.openPath(full)
      except IOError, OSError:
        e.setStatus("Can't create: " & getCurrentExceptionMsg(), err = true)
  of pkSearch:
    if input.len > 0:
      e.lastSearch = input
      if not e.buf.findNext(input): e.setStatus("Not found: " & input, err = true)
      else: e.setStatus("")
  of pkGoto:
    try:
      let n = parseInt(input.strip())
      e.buf.cursor = Pos(line: clamp(n - 1, 0, e.buf.lines.len - 1), col: 0)
      e.buf.clampCursor()
      e.setWish()
    except ValueError:
      e.setStatus("Bad line number", err = true)
  of pkQuitConfirm:
    if input.toLowerAscii.startsWith("y"): e.running = false
  of pkCloseConfirm:
    if input.toLowerAscii.startsWith("y"): e.forceClose(e.pendingClose)
  of pkNone: discard

proc promptKey(e: Editor, k: term.Key) =
  case k.kind
  of kEsc:
    e.endPrompt()
    e.setStatus("Cancelled")
  of kEnter: e.finishPrompt()
  of kBackspace:
    if e.promptInput.len > 0:
      e.promptInput.setLen(e.promptInput.prevRuneStart(e.promptInput.len))
  of kChar: e.promptInput.add k.ch
  of kPaste: e.promptInput.add k.ch.replace("\n", " ")
  else: discard

# ---- editor movement / editing ----------------------------------------------

proc moveVert(e: Editor, delta: int) =
  e.buf.cursor.line = clamp(e.buf.cursor.line + delta, 0, e.buf.lines.len - 1)
  e.buf.cursor.col = byteColForDisp(e.buf.curLine, e.buf.wishCol)

proc moveLeft(e: Editor) =
  if e.buf.cursor.col > 0:
    e.buf.cursor.col = e.buf.curLine.prevRuneStart(e.buf.cursor.col)
  elif e.buf.cursor.line > 0:
    dec e.buf.cursor.line
    e.buf.cursor.col = e.buf.curLine.len
  e.setWish()

proc moveRight(e: Editor) =
  if e.buf.cursor.col < e.buf.curLine.len:
    e.buf.cursor.col = e.buf.curLine.nextRuneStart(e.buf.cursor.col)
  elif e.buf.cursor.line < e.buf.lines.len - 1:
    inc e.buf.cursor.line
    e.buf.cursor.col = 0
  e.setWish()

proc backspace(e: Editor) =
  if e.buf.cursor.col > 0:
    let start = e.buf.curLine.prevRuneStart(e.buf.cursor.col)
    discard e.buf.deleteRange(Pos(line: e.buf.cursor.line, col: start), e.buf.cursor)
  elif e.buf.cursor.line > 0:
    let prevLen = e.buf.lines[e.buf.cursor.line - 1].len
    discard e.buf.deleteRange(Pos(line: e.buf.cursor.line - 1, col: prevLen), e.buf.cursor)
  e.setWish()

proc deleteForward(e: Editor) =
  if e.buf.cursor.col < e.buf.curLine.len:
    let stop = e.buf.curLine.nextRuneStart(e.buf.cursor.col)
    discard e.buf.deleteRange(e.buf.cursor, Pos(line: e.buf.cursor.line, col: stop))
  elif e.buf.cursor.line < e.buf.lines.len - 1:
    discard e.buf.deleteRange(e.buf.cursor, Pos(line: e.buf.cursor.line + 1, col: 0))

proc treeActivate(e: Editor) =
  if not e.tree.hasSelection: return
  let sel = e.tree.selected
  if sel.isDir: e.tree.toggle()
  else: e.openPath(sel.path)

proc treeKey(e: Editor, k: term.Key) =
  case k.kind
  of kUp: (if e.tree.sel > 0: dec e.tree.sel)
  of kDown: (if e.tree.sel < e.tree.flat.len - 1: inc e.tree.sel)
  of kPageUp: e.tree.sel = max(0, e.tree.sel - e.editorHeight)
  of kPageDown: e.tree.sel = min(e.tree.flat.len - 1, e.tree.sel + e.editorHeight)
  of kHome, kCtrlHome: e.tree.sel = 0
  of kEnd, kCtrlEnd: e.tree.sel = e.tree.flat.len - 1
  of kRight: e.tree.expandSel()
  of kLeft: e.tree.collapseSel()
  of kEnter: e.treeActivate()
  of kChar:
    if k.ch == "n": e.startPrompt(pkNewFile, "New file name: ")
    elif k.ch == "r": (e.tree.refresh(); e.setStatus("Tree refreshed"))
  of kF5: (e.tree.refresh(); e.setStatus("Tree refreshed"))
  else: discard

proc editorKey(e: Editor, k: term.Key) =
  case k.kind
  of kChar: e.buf.insert(k.ch); e.setWish()
  of kEnter: e.buf.insert("\n"); e.setWish()
  of kTab: e.buf.insert("\t"); e.setWish()
  of kPaste: e.buf.insert(k.ch.replace("\r\n", "\n").replace("\r", "\n")); e.setWish()
  of kBackspace: e.backspace()
  of kDelete: e.deleteForward()
  of kLeft: e.moveLeft()
  of kRight: e.moveRight()
  of kUp: e.moveVert(-1)
  of kDown: e.moveVert(1)
  of kPageUp: e.moveVert(-(e.editorHeight - 1))
  of kPageDown: e.moveVert(e.editorHeight - 1)
  of kHome: e.buf.cursor.col = 0; e.setWish()
  of kEnd: e.buf.cursor.col = e.buf.curLine.len; e.setWish()
  of kCtrlLeft: e.buf.wordLeft(); e.setWish()
  of kCtrlRight: e.buf.wordRight(); e.setWish()
  of kCtrlHome: e.buf.cursor = Pos(line: 0, col: 0); e.setWish()
  of kCtrlEnd:
    e.buf.cursor = Pos(line: e.buf.lines.len - 1, col: e.buf.lines[^1].len)
    e.setWish()
  else: discard

# ---- mouse ------------------------------------------------------------------

proc editorClick(e: Editor, mx, my: int) =
  e.focus = foEditor
  let gutterW = max(3, ($e.buf.lines.len).len) + 1
  e.buf.cursor.line = clamp(e.buf.editTop + (my - 1 - TopBarRows), 0, e.buf.lines.len - 1)
  var d = e.buf.editLeft + (mx - 1) - (e.editorX0 + gutterW)
  if d < 0: d = 0
  e.buf.cursor.col = byteColForDisp(e.buf.curLine, d)
  e.setWish()

proc treeClick(e: Editor, my: int) =
  let idx = e.tree.scroll + (my - 1 - TopBarRows)
  if idx < 0 or idx >= e.tree.flat.len: return
  e.focus = foTree
  e.tree.sel = idx
  let sel = e.tree.selected
  if sel.isDir: e.tree.toggle()
  else: e.openPath(sel.path)

proc scrollTabs(e: Editor, delta: int) =
  e.tabScroll = clamp(e.tabScroll + delta, 0, e.buffers.high)

proc tabBarClick(e: Editor, mx: int) =
  for sp in e.tabSpans:
    if mx >= sp.x0 and mx <= sp.x1:
      case sp.idx
      of -1: e.scrollTabs(-1)      # ‹ chevron
      of -2: e.scrollTabs(1)       # › chevron
      else:
        if mx == sp.markerX: e.closeTabAt(sp.idx)
        else: (e.current = sp.idx; e.focus = foEditor)
      return

proc overTree(e: Editor, mx, my: int): bool =
  e.showTree and mx <= e.sidebarW and my >= 1 + TopBarRows

proc handleMouse(e: Editor, k: term.Key) =
  case k.kind
  of kMouseDown:
    if k.my <= TopBarRows: e.tabBarClick(k.mx)
    elif k.my <= e.rows - 2:
      if e.overTree(k.mx, k.my): e.treeClick(k.my)
      elif k.mx > e.editorX0: e.editorClick(k.mx, k.my)
  of kScrollUp:
    if k.my <= TopBarRows: e.scrollTabs(-1)
    elif e.overTree(k.mx, k.my): e.tree.sel = max(0, e.tree.sel - 3)
    else: e.moveVert(-3)
  of kScrollDown:
    if k.my <= TopBarRows: e.scrollTabs(1)
    elif e.overTree(k.mx, k.my): e.tree.sel = min(e.tree.flat.len - 1, e.tree.sel + 3)
    else: e.moveVert(3)
  else: discard

# ---- top-level dispatch -----------------------------------------------------

proc handleCtrl(e: Editor, letter: string) =
  case letter
  of "x", "q": e.requestQuit()                       # ^X quit (nano), ^Q alias
  of "z":                                            # suspend to shell
    when suspendSupported:
      suspend()
      e.updateWinsize()
      e.setStatus("Resumed")
    else:
      e.setStatus("Suspend is not available on this platform", err = true)
  of "s": e.handleSave()
  of "w": e.closeTabAt(e.current)
  of "b":
    if e.cols >= 40:
      e.showTree = not e.showTree
      if not e.showTree and e.focus == foTree: e.focus = foEditor
  of "o":
    e.showTree = true
    e.focus = foTree
    e.setStatus("Browse files — click or Enter to open")
  of "f": e.startPrompt(pkSearch, "Find: ", e.lastSearch)
  of "g": e.startPrompt(pkGoto, "Go to line: ")
  of "u": (if not e.buf.undo(): e.setStatus("Nothing to undo"))
  of "r", "y": (if not e.buf.redo(): e.setStatus("Nothing to redo"))
  of "n":
    if e.lastSearch.len > 0:
      if not e.buf.findNext(e.lastSearch):
        e.setStatus("Not found: " & e.lastSearch, err = true)
  of "a": e.buf.cursor.col = 0; e.setWish()          # nano-style home
  of "e": e.buf.cursor.col = e.buf.curLine.len; e.setWish()
  else: discard

proc dispatch(e: Editor, k: term.Key) =
  case k.kind
  of kResize:
    e.updateWinsize()
    return
  of kMouseDown, kScrollUp, kScrollDown:
    if e.mode != mPrompt: e.handleMouse(k)
    return
  else: discard
  if e.mode == mPrompt:
    e.promptKey(k)
    return
  case k.kind
  of kCtrlPageUp: e.prevTab(); return
  of kCtrlPageDown: e.nextTab(); return
  of kCtrl: e.handleCtrl(k.ch); return
  of kTab:
    if e.focus == foTree: (e.focus = foEditor; return)
  of kShiftTab:
    if e.showTree: (e.focus = (if e.focus == foTree: foEditor else: foTree); return)
  else: discard
  if e.focus == foTree: e.treeKey(k)
  else: e.editorKey(k)

# ---- setup / teardown -------------------------------------------------------

proc newEditor(startPath: string): Editor =
  result = Editor(
    focus: foEditor, mode: mNormal, showTree: true, running: true, current: 0,
    tree: newFileTree(getCurrentDir()))
  result.updateWinsize()
  var b: TextBuffer
  if startPath.len > 0 and fileExists(startPath):
    try:
      b = loadFile(startPath)
      result.tree.revealPath(startPath.absolutePath)
      result.setStatus("Opened " & startPath.lastPathPart)
    except IOError, OSError:
      b = newTextBuffer()
      b.path = startPath.absolutePath
      result.setStatus("New file: " & startPath, err = true)
  elif startPath.len > 0:
    b = newTextBuffer()
    b.path = startPath.absolutePath
    result.setStatus("New file: " & startPath)
  else:
    b = newTextBuffer()
    result.setStatus("nimo v" & Version & " — click a file or ^O to browse")
  result.buffers = @[b]

proc main() =
  var startPath = ""
  for i in 1 .. paramCount():
    let a = paramStr(i)
    if a == "--help" or a == "-h":
      echo "nimo v", Version, " (Nim Terminal Text Editor) — a friendly editor"
      echo "Usage: nimo [file]"
      return
    elif a == "--version":
      echo "nimo v", Version
      return
    elif not a.startsWith("-"):
      startPath = a
  if not isTerminal():
    stderr.writeLine "nimo: not a terminal"
    quit(1)
  installWinchHandler()
  enterRaw()
  addExitProc(proc() = exitRaw()) # restore the terminal no matter how we exit
  let e = newEditor(startPath)
  try:
    while e.running:
      e.render()
      e.dispatch(readKey())
  finally:
    exitRaw()

when isMainModule:
  main()
