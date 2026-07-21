## Text buffer: lines of UTF-8 text, cursor, editing primitives, undo/redo,
## search, and display-column math (tab expansion). Nim stdlib only.

import std/[strutils, unicode]

const
  TabWidth* = 4
  MaxFileSize* = 20_000_000

type
  Pos* = object
    line*, col*: int ## col is a byte offset into the line

  EditKind = enum ekInsert, ekDelete
  Edit = object
    kind: EditKind
    pos: Pos ## start of the inserted/deleted text
    text: string ## may contain '\n'
    cursorBefore, cursorAfter: Pos

  TextBuffer* = ref object
    lines*: seq[string]
    path*: string
    modified*: bool
    cursor*: Pos
    wishCol*: int ## desired display column, kept across up/down moves
    undoStack, redoStack: seq[Edit]
    savedDepth: int ## undoStack.len at last save; -1 if unreachable

proc newTextBuffer*(): TextBuffer =
  TextBuffer(lines: @[""])

proc curLine*(b: TextBuffer): string =
  b.lines[b.cursor.line]

proc updateModified(b: TextBuffer) =
  b.modified = b.undoStack.len != b.savedDepth

proc markSaved*(b: TextBuffer) =
  b.savedDepth = b.undoStack.len
  b.modified = false

# ---- rune / display helpers -------------------------------------------------

proc prevRuneStart*(s: string, i: int): int =
  ## Byte index of the rune that ends just before byte i.
  result = i - 1
  while result > 0 and (ord(s[result]) and 0xC0) == 0x80:
    dec result

proc nextRuneStart*(s: string, i: int): int =
  ## Byte index just past the rune starting at byte i.
  if i >= s.len: return s.len
  i + s.runeLenAt(i)

proc snapToRune*(s: string, i: int): int =
  result = min(max(i, 0), s.len)
  while result > 0 and result < s.len and (ord(s[result]) and 0xC0) == 0x80:
    dec result

proc dispCol*(line: string, uptoByte: int): int =
  ## Display column of byte offset `uptoByte`, expanding tabs.
  var i = 0
  while i < uptoByte and i < line.len:
    if line[i] == '\t':
      result += TabWidth - (result mod TabWidth)
      inc i
    else:
      inc result
      i += line.runeLenAt(i)

proc byteColForDisp*(line: string, target: int): int =
  ## Byte offset whose display column is <= target, as close as possible.
  var i = 0
  var d = 0
  while i < line.len:
    let step = if line[i] == '\t': TabWidth - (d mod TabWidth) else: 1
    if d + step > target: break
    d += step
    i = if line[i] == '\t': i + 1 else: i + line.runeLenAt(i)
  i

proc runeCol*(b: TextBuffer): int =
  ## Cursor column counted in runes (for the status bar).
  let line = b.curLine
  var i = 0
  while i < b.cursor.col and i < line.len:
    inc result
    i += line.runeLenAt(i)

proc expandSlice*(line: string, fromDisp, width: int): string =
  ## The part of `line` visible in display columns [fromDisp, fromDisp+width),
  ## with tabs expanded to spaces.
  var i = 0
  var d = 0
  while i < line.len and d < fromDisp + width:
    if line[i] == '\t':
      let stop = d + TabWidth - (d mod TabWidth)
      while d < stop:
        if d >= fromDisp and d < fromDisp + width: result.add ' '
        inc d
      inc i
    else:
      let rl = line.runeLenAt(i)
      if d >= fromDisp: result.add line[i ..< i + rl]
      inc d
      i += rl

# ---- raw editing (no undo bookkeeping) --------------------------------------

proc insertRaw(b: TextBuffer, pos: Pos, text: string): Pos =
  let parts = text.split('\n')
  let line = b.lines[pos.line]
  let head = line[0 ..< pos.col]
  let tail = line[pos.col .. ^1]
  if parts.len == 1:
    b.lines[pos.line] = head & parts[0] & tail
    Pos(line: pos.line, col: pos.col + parts[0].len)
  else:
    b.lines[pos.line] = head & parts[0]
    var mid: seq[string]
    for i in 1 ..< parts.len - 1: mid.add parts[i]
    mid.add parts[^1] & tail
    b.lines = b.lines[0 .. pos.line] & mid & b.lines[pos.line + 1 .. ^1]
    Pos(line: pos.line + parts.len - 1, col: parts[^1].len)

proc deleteRaw(b: TextBuffer, a, z: Pos): string =
  if a.line == z.line:
    result = b.lines[a.line][a.col ..< z.col]
    b.lines[a.line] = b.lines[a.line][0 ..< a.col] & b.lines[a.line][z.col .. ^1]
  else:
    result = b.lines[a.line][a.col .. ^1] & "\n"
    for l in a.line + 1 ..< z.line:
      result.add b.lines[l] & "\n"
    result.add b.lines[z.line][0 ..< z.col]
    b.lines[a.line] = b.lines[a.line][0 ..< a.col] & b.lines[z.line][z.col .. ^1]
    b.lines = b.lines[0 .. a.line] & b.lines[z.line + 1 .. ^1]

proc endOf(pos: Pos, text: string): Pos =
  ## Position just past `text` when it starts at `pos`.
  let parts = text.split('\n')
  if parts.len == 1:
    Pos(line: pos.line, col: pos.col + parts[0].len)
  else:
    Pos(line: pos.line + parts.len - 1, col: parts[^1].len)

# ---- public editing with undo -----------------------------------------------

proc pushEdit(b: TextBuffer, e: Edit) =
  if b.redoStack.len > 0 and b.undoStack.len < b.savedDepth:
    b.savedDepth = -1 # saved state is no longer reachable via undo/redo
  b.redoStack.setLen 0
  b.undoStack.add e
  b.updateModified()

proc insert*(b: TextBuffer, text: string) =
  if text.len == 0: return
  var e = Edit(kind: ekInsert, pos: b.cursor, text: text, cursorBefore: b.cursor)
  b.cursor = b.insertRaw(b.cursor, text)
  e.cursorAfter = b.cursor
  b.pushEdit e

proc deleteRange*(b: TextBuffer, a, z: Pos): string =
  if a == z: return ""
  var e = Edit(kind: ekDelete, pos: a, cursorBefore: b.cursor)
  result = b.deleteRaw(a, z)
  e.text = result
  b.cursor = a
  e.cursorAfter = a
  b.pushEdit e

proc undo*(b: TextBuffer): bool =
  if b.undoStack.len == 0: return false
  let e = b.undoStack.pop()
  case e.kind
  of ekInsert:
    discard b.deleteRaw(e.pos, endOf(e.pos, e.text))
  of ekDelete:
    discard b.insertRaw(e.pos, e.text)
  b.cursor = e.cursorBefore
  b.redoStack.add e
  b.updateModified()
  true

proc redo*(b: TextBuffer): bool =
  if b.redoStack.len == 0: return false
  let e = b.redoStack.pop()
  case e.kind
  of ekInsert:
    discard b.insertRaw(e.pos, e.text)
  of ekDelete:
    discard b.deleteRaw(e.pos, endOf(e.pos, e.text))
  b.cursor = e.cursorAfter
  b.undoStack.add e
  b.updateModified()
  true

proc clampCursor*(b: TextBuffer) =
  b.cursor.line = clamp(b.cursor.line, 0, b.lines.len - 1)
  b.cursor.col = b.curLine.snapToRune(b.cursor.col)

# ---- word movement ----------------------------------------------------------

proc isWordRune(r: Rune): bool =
  r == Rune(ord('_')) or r.isAlpha() or (r.int < 128 and char(r.int) in {'0'..'9'})

proc wordLeft*(b: TextBuffer) =
  var (l, c) = (b.cursor.line, b.cursor.col)
  if c == 0:
    if l > 0:
      dec l
      c = b.lines[l].len
  else:
    # skip separators, then a run of word runes
    while c > 0:
      let p = b.lines[l].prevRuneStart(c)
      if b.lines[l].runeAt(p).isWordRune: break
      c = p
    while c > 0:
      let p = b.lines[l].prevRuneStart(c)
      if not b.lines[l].runeAt(p).isWordRune: break
      c = p
  b.cursor = Pos(line: l, col: c)

proc wordRight*(b: TextBuffer) =
  var (l, c) = (b.cursor.line, b.cursor.col)
  if c >= b.lines[l].len:
    if l < b.lines.len - 1:
      inc l
      c = 0
  else:
    while c < b.lines[l].len and not b.lines[l].runeAt(c).isWordRune:
      c = b.lines[l].nextRuneStart(c)
    while c < b.lines[l].len and b.lines[l].runeAt(c).isWordRune:
      c = b.lines[l].nextRuneStart(c)
  b.cursor = Pos(line: l, col: c)

# ---- search -----------------------------------------------------------------

proc findNext*(b: TextBuffer, query: string): bool =
  ## Finds the next match after the cursor, wrapping around.
  ## Case-insensitive when the query is all lowercase (smart case).
  if query.len == 0: return false
  let caseIns = query == query.toLowerAscii
  let q = if caseIns: query.toLowerAscii else: query
  let startCol = min(b.cursor.col + 1, b.lines[b.cursor.line].len)
  for step in 0 .. b.lines.len:
    let li = (b.cursor.line + step) mod b.lines.len
    let hay = if caseIns: b.lines[li].toLowerAscii else: b.lines[li]
    let fromCol = if step == 0: startCol else: 0
    let idx = hay.find(q, fromCol)
    if idx >= 0:
      b.cursor = Pos(line: li, col: idx)
      b.wishCol = dispCol(b.lines[li], idx)
      return true
  false

# ---- file I/O ---------------------------------------------------------------

proc loadFile*(path: string): TextBuffer =
  ## Raises IOError for unreadable/binary/oversized files.
  var content = readFile(path)
  if content.len > MaxFileSize:
    raise newException(IOError, "file too large (> 20 MB)")
  if content.contains('\0'):
    raise newException(IOError, "binary file")
  content = content.replace("\r\n", "\n").replace("\r", "\n")
  result = TextBuffer(path: path, lines: content.split('\n'))
  # a trailing newline yields one empty trailing element; drop it
  if result.lines.len > 1 and result.lines[^1] == "":
    result.lines.setLen(result.lines.len - 1)

proc toFileString*(b: TextBuffer): string =
  b.lines.join("\n") & "\n"
