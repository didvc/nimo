## ternimal — a nano-inspired terminal text editor in Nim.
##
## Layout: a file-tree sidebar on the left, the editor pane on the right,
## a status line and a keybinding hint line at the bottom. Nim stdlib only.

import std/[os, posix, termios, strutils, exitprocs]
import term, textbuffer, filetree

type
  Focus = enum foEditor, foTree

  Mode = enum mNormal, mPrompt

  PromptKind = enum pkNone, pkSave, pkOpenConfirm, pkQuitConfirm, pkSearch, pkGoto, pkNewFile

  Editor = ref object
    buf: TextBuffer
    tree: FileTree
    focus: Focus
    mode: Mode
    rows, cols: int
    sidebarW: int
    showTree: bool
    editTop, editLeft: int ## scroll offset of the editor viewport
    status: string
    statusIsError: bool
    prompt: PromptKind
    promptLabel: string
    promptInput: string
    lastSearch: string
    running: bool
    pendingOpen: string ## path awaiting confirm when buffer is modified

const
  SidebarDefault = 30
  Version = "0.1.0"

# ---- small helpers ----------------------------------------------------------

proc setStatus(e: Editor, msg: string, err = false) =
  e.status = msg
  e.statusIsError = err

proc editorWidth(e: Editor): int =
  if e.showTree: e.cols - e.sidebarW - 1 else: e.cols
proc editorHeight(e: Editor): int =
  e.rows - 2 # status line + hint line
proc editorX0(e: Editor): int =
  if e.showTree: e.sidebarW + 1 else: 0

proc updateWinsize(e: Editor) =
  var ws: IOctl_WinSize
  if ioctl(1, TIOCGWINSZ, addr ws) == 0 and ws.ws_row > 0:
    e.rows = int(ws.ws_row)
    e.cols = int(ws.ws_col)
  else:
    e.rows = 24
    e.cols = 80
  e.sidebarW = min(SidebarDefault, e.cols div 3)
  if e.cols < 40: e.showTree = false

# ---- rendering --------------------------------------------------------------

proc ellipsize(s: string, w: int): string =
  if w <= 0: return ""
  if s.len <= w: return s
  if w == 1: return "…"
  s[0 ..< w - 1] & "…"

proc scrollToCursor(e: Editor) =
  let h = e.editorHeight
  let w = e.editorWidth
  if e.buf.cursor.line < e.editTop: e.editTop = e.buf.cursor.line
  elif e.buf.cursor.line >= e.editTop + h: e.editTop = e.buf.cursor.line - h + 1
  let cx = dispCol(e.buf.curLine, e.buf.cursor.col)
  if cx < e.editLeft: e.editLeft = cx
  elif cx >= e.editLeft + w: e.editLeft = cx - w + 1
  if e.editLeft < 0: e.editLeft = 0

proc ensureTreeVisible(e: Editor) =
  let h = e.editorHeight
  if e.tree.sel < e.tree.scroll: e.tree.scroll = e.tree.sel
  elif e.tree.sel >= e.tree.scroll + h: e.tree.scroll = e.tree.sel - h + 1

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

proc drawTree(e: Editor, sb: var string) =
  let h = e.editorHeight
  e.ensureTreeVisible()
  for row in 0 ..< h:
    sb.add "\e[" & $(row + 1) & ";1H"
    let idx = e.tree.scroll + row
    if idx >= e.tree.flat.len:
      sb.add cSideBar & " ".repeat(e.sidebarW) & cReset
      continue
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
    var line = indent & indicator & name
    if entry.isDir and not isSel:
      line = indent & indicator & cDir & name & cReset
      if isSel: line.add cSelActive
    # pad to sidebar width
    let visLen = indent.len + indicator.len + name.len
    line.add " ".repeat(max(0, e.sidebarW - visLen))
    sb.add line & cReset
    # vertical divider
    sb.add "\e[" & $(row + 1) & ";" & $(e.sidebarW + 1) & "H" & cSideBar & "│" & cReset

proc drawEditor(e: Editor, sb: var string) =
  let h = e.editorHeight
  let x0 = e.editorX0
  let gutterW = max(3, ($e.buf.lines.len).len) + 1
  let textW = e.editorWidth - gutterW
  for row in 0 ..< h:
    sb.add "\e[" & $(row + 1) & ";" & $(x0 + 1) & "H\e[K"
    let li = e.editTop + row
    if li >= e.buf.lines.len:
      sb.add cLineNo & "~" & cReset
      continue
    let num = align($(li + 1), gutterW - 1)
    sb.add cLineNo & num & " " & cReset
    let visible = expandSlice(e.buf.lines[li], e.editLeft, textW)
    sb.add visible

proc drawStatus(e: Editor, sb: var string) =
  sb.add "\e[" & $(e.rows - 1) & ";1H\e[K"
  let name = if e.buf.path.len > 0: e.buf.path.lastPathPart else: "[No Name]"
  let dirty = if e.buf.modified: cModified & " ●" & cReset & (if e.statusIsError: cStatusErr else: cStatus) else: ""
  let pos = "Ln " & $(e.buf.cursor.line + 1) & ", Col " & $(e.buf.runeCol + 1)
  let left = " " & name & dirty & "  " & (if e.status.len > 0: e.status else: "")
  let barCol = if e.statusIsError: cStatusErr else: cStatus
  sb.add barCol
  # left text, then pos right-aligned
  let plainLeftLen = 1 + name.len + (if e.buf.modified: 2 else: 0) + 2 +
                     (if e.status.len > 0: e.status.len else: 0)
  var content = left
  let padTo = e.cols - pos.len - 1
  if plainLeftLen < padTo:
    content.add " ".repeat(padTo - plainLeftLen)
  content.add pos & " "
  sb.add content & cReset

proc drawHint(e: Editor, sb: var string) =
  sb.add "\e[" & $e.rows & ";1H\e[K" & cHint
  let hint =
    if e.mode == mPrompt:
      e.promptLabel & e.promptInput & "▏"
    elif e.focus == foTree:
      "^S Save  ^O Open  ^B Toggle Tree  Enter Open/Expand  ^Q Quit"
    else:
      "^S Save  ^F Find  ^G GoTo  ^Z Undo  ^Y Redo  ^B Tree  ^Q Quit"
  sb.add ellipsize(hint, e.cols) & cReset

proc placeCursor(e: Editor, sb: var string) =
  if e.mode == mPrompt:
    let cx = e.promptLabel.len + e.promptInput.len + 1
    sb.add "\e[" & $e.rows & ";" & $(min(cx, e.cols)) & "H"
    return
  if e.focus == foTree:
    sb.add "\e[?25l" # hide cursor while navigating tree
    return
  let gutterW = max(3, ($e.buf.lines.len).len) + 1
  let cy = e.buf.cursor.line - e.editTop + 1
  let cx = e.editorX0 + gutterW + dispCol(e.buf.curLine, e.buf.cursor.col) - e.editLeft + 1
  sb.add "\e[?25h\e[" & $cy & ";" & $cx & "H"

proc render(e: Editor) =
  e.scrollToCursor()
  var sb = "\e[?25l\e[H"
  if e.showTree: e.drawTree(sb)
  e.drawEditor(sb)
  e.drawStatus(sb)
  e.drawHint(sb)
  e.placeCursor(sb)
  stdout.write sb
  stdout.flushFile

# ---- file operations --------------------------------------------------------

proc doSave(e: Editor, path: string): bool =
  try:
    writeFile(path, e.buf.toFileString)
    e.buf.path = path
    e.buf.markSaved()
    e.tree.refresh()
    e.tree.revealPath(path)
    e.setStatus("Saved " & path.lastPathPart)
    return true
  except IOError, OSError:
    e.setStatus("Can't save: " & getCurrentExceptionMsg(), err = true)
    return false

proc openPath(e: Editor, path: string) =
  try:
    e.buf = loadFile(path)
    e.buf.clampCursor()
    e.editTop = 0
    e.editLeft = 0
    e.focus = foEditor
    e.tree.revealPath(path)
    e.setStatus("Opened " & path.lastPathPart)
  except IOError, OSError:
    e.setStatus("Can't open: " & getCurrentExceptionMsg(), err = true)

# ---- prompt handling --------------------------------------------------------

proc startPrompt(e: Editor, kind: PromptKind, label: string, initial = "") =
  e.mode = mPrompt
  e.prompt = kind
  e.promptLabel = label
  e.promptInput = initial

proc endPrompt(e: Editor) =
  e.mode = mNormal
  e.prompt = pkNone
  e.promptInput = ""

proc finishPrompt(e: Editor) =
  let input = e.promptInput
  let kind = e.prompt
  e.endPrompt()
  case kind
  of pkSave:
    if input.len > 0: discard e.doSave(input)
  of pkNewFile:
    if input.len > 0:
      let dir = if e.tree.hasSelection and e.tree.selected.isDir:
                  e.tree.selected.path
                elif e.tree.hasSelection:
                  e.tree.selected.path.parentDir
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
      if not e.buf.findNext(input):
        e.setStatus("Not found: " & input, err = true)
      else:
        e.setStatus("")
  of pkGoto:
    try:
      let n = parseInt(input.strip())
      e.buf.cursor = Pos(line: clamp(n - 1, 0, e.buf.lines.len - 1), col: 0)
      e.buf.clampCursor()
    except ValueError:
      e.setStatus("Bad line number", err = true)
  of pkQuitConfirm:
    if input.toLowerAscii.startsWith("y"): e.running = false
  of pkOpenConfirm:
    if input.toLowerAscii.startsWith("y"): e.openPath(e.pendingOpen)
  of pkNone: discard

proc promptKey(e: Editor, k: term.Key) =
  case k.kind
  of kEsc:
    e.endPrompt()
    e.setStatus("Cancelled")
  of kEnter:
    e.finishPrompt()
  of kBackspace:
    if e.promptInput.len > 0:
      e.promptInput.setLen(e.promptInput.prevRuneStart(e.promptInput.len))
  of kChar:
    e.promptInput.add k.ch
  of kPaste:
    e.promptInput.add k.ch.replace("\n", " ")
  else: discard

# ---- editor key handling ----------------------------------------------------

proc moveVert(e: Editor, delta: int) =
  let target = clamp(e.buf.cursor.line + delta, 0, e.buf.lines.len - 1)
  e.buf.cursor.line = target
  e.buf.cursor.col = byteColForDisp(e.buf.curLine, e.buf.wishCol)

proc setWish(e: Editor) =
  e.buf.wishCol = dispCol(e.buf.curLine, e.buf.cursor.col)

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
    discard e.buf.deleteRange(
      Pos(line: e.buf.cursor.line - 1, col: prevLen), e.buf.cursor)
  e.setWish()

proc deleteForward(e: Editor) =
  if e.buf.cursor.col < e.buf.curLine.len:
    let stop = e.buf.curLine.nextRuneStart(e.buf.cursor.col)
    discard e.buf.deleteRange(e.buf.cursor, Pos(line: e.buf.cursor.line, col: stop))
  elif e.buf.cursor.line < e.buf.lines.len - 1:
    discard e.buf.deleteRange(e.buf.cursor, Pos(line: e.buf.cursor.line + 1, col: 0))

proc requestOpen(e: Editor, path: string) =
  if e.buf.modified:
    e.pendingOpen = path
    e.startPrompt(pkOpenConfirm, "Discard unsaved changes? (y/n): ")
  else:
    e.openPath(path)

proc treeActivate(e: Editor) =
  if not e.tree.hasSelection: return
  let sel = e.tree.selected
  if sel.isDir: e.tree.toggle()
  else: e.requestOpen(sel.path)

proc handleSave(e: Editor) =
  if e.buf.path.len > 0: discard e.doSave(e.buf.path)
  else: e.startPrompt(pkSave, "Save as: ",
                      e.tree.root / "untitled.txt".lastPathPart)

proc requestQuit(e: Editor) =
  if e.buf.modified:
    e.startPrompt(pkQuitConfirm, "Unsaved changes. Quit anyway? (y/n): ")
  else:
    e.running = false

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

proc handleCtrl(e: Editor, letter: string) =
  case letter
  of "q": e.requestQuit()
  of "s": e.handleSave()
  of "b":
    if e.cols >= 40:
      e.showTree = not e.showTree
      if not e.showTree and e.focus == foTree: e.focus = foEditor
  of "o":
    e.showTree = true
    e.focus = foTree
    e.setStatus("Browse files — Enter to open")
  of "f": e.startPrompt(pkSearch, "Find: ", e.lastSearch)
  of "g": e.startPrompt(pkGoto, "Go to line: ")
  of "z": (if not e.buf.undo(): e.setStatus("Nothing to undo"))
  of "y": (if not e.buf.redo(): e.setStatus("Nothing to redo"))
  of "n":
    if e.lastSearch.len > 0:
      if not e.buf.findNext(e.lastSearch):
        e.setStatus("Not found: " & e.lastSearch, err = true)
  of "a": e.buf.cursor.col = 0; e.setWish()          # nano-style home
  of "e": e.buf.cursor.col = e.buf.curLine.len; e.setWish()
  else: discard

proc dispatch(e: Editor, k: term.Key) =
  if k.kind == kResize:
    e.updateWinsize()
    return
  if e.mode == mPrompt:
    e.promptKey(k)
    return
  if k.kind == kCtrl:
    e.handleCtrl(k.ch)
    return
  # Tab toggles focus between panes when tree is shown
  if k.kind == kTab and e.focus == foTree:
    e.focus = foEditor
    return
  if k.kind == kShiftTab and e.showTree:
    e.focus = (if e.focus == foTree: foEditor else: foTree)
    return
  if e.focus == foTree:
    e.treeKey(k)
  else:
    e.editorKey(k)

# ---- setup / teardown -------------------------------------------------------

proc newEditor(startPath: string): Editor =
  result = Editor(
    focus: foEditor, mode: mNormal, showTree: true, running: true,
    tree: newFileTree(getCurrentDir()))
  result.updateWinsize()
  if startPath.len > 0 and fileExists(startPath):
    try:
      result.buf = loadFile(startPath)
      result.tree.revealPath(startPath.absolutePath)
      result.setStatus("Opened " & startPath.lastPathPart)
    except IOError, OSError:
      result.buf = newTextBuffer()
      result.buf.path = startPath.absolutePath
      result.setStatus("New file: " & startPath, err = true)
  elif startPath.len > 0:
    result.buf = newTextBuffer()
    result.buf.path = startPath.absolutePath
    result.setStatus("New file: " & startPath)
  else:
    result.buf = newTextBuffer()
    result.setStatus("ternimal v" & Version & " — ^O to browse files")

proc main() =
  var startPath = ""
  for i in 1 .. paramCount():
    let a = paramStr(i)
    if a == "--help" or a == "-h":
      echo "ternimal v", Version, " — a friendly terminal text editor"
      echo "Usage: ternimal [file]"
      return
    elif a == "--version":
      echo "ternimal v", Version
      return
    elif not a.startsWith("-"):
      startPath = a
  if isatty(0) == 0:
    stderr.writeLine "ternimal: not a terminal"
    quit(1)
  installWinchHandler()
  enterRaw()
  # Restore the terminal no matter how we exit.
  addExitProc(proc() = exitRaw())
  let e = newEditor(startPath)
  try:
    while e.running:
      e.render()
      let k = readKey()
      e.dispatch(k)
  finally:
    exitRaw()

when isMainModule:
  main()
