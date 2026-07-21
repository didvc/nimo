import std/unittest
import "../src/textbuffer"

suite "TextBuffer editing":
  test "insert single line":
    let b = newTextBuffer()
    b.insert("hello")
    check b.lines == @["hello"]
    check b.cursor == Pos(line: 0, col: 5)

  test "insert with newlines":
    let b = newTextBuffer()
    b.insert("ab\ncd\nef")
    check b.lines == @["ab", "cd", "ef"]
    check b.cursor == Pos(line: 2, col: 2)

  test "insert in the middle splits correctly":
    let b = newTextBuffer()
    b.insert("hello world")
    b.cursor = Pos(line: 0, col: 5)
    b.insert("\n>>")
    check b.lines == @["hello", ">> world"]

  test "delete range within a line":
    let b = newTextBuffer()
    b.insert("hello world")
    let removed = b.deleteRange(Pos(line: 0, col: 5), Pos(line: 0, col: 11))
    check removed == " world"
    check b.lines == @["hello"]

  test "delete range across lines (join)":
    let b = newTextBuffer()
    b.insert("ab\ncd\nef")
    let removed = b.deleteRange(Pos(line: 0, col: 1), Pos(line: 2, col: 1))
    check removed == "b\ncd\ne"
    check b.lines == @["af"]

suite "Undo / redo":
  test "undo restores content and cursor":
    let b = newTextBuffer()
    b.insert("hello")
    check b.undo()
    check b.lines == @[""]
    check b.cursor == Pos(line: 0, col: 0)

  test "redo reapplies":
    let b = newTextBuffer()
    b.insert("hello")
    discard b.undo()
    check b.redo()
    check b.lines == @["hello"]
    check b.cursor == Pos(line: 0, col: 5)

  test "undo multiline delete":
    let b = newTextBuffer()
    b.insert("ab\ncd\nef")
    discard b.deleteRange(Pos(line: 0, col: 1), Pos(line: 2, col: 1))
    check b.lines == @["af"]
    check b.undo()
    check b.lines == @["ab", "cd", "ef"]

  test "modified flag tracks saved depth":
    let b = newTextBuffer()
    check not b.modified
    b.insert("x")
    check b.modified
    b.markSaved()
    check not b.modified
    discard b.undo()
    check b.modified # back before save point

suite "Display column math":
  test "tab expansion":
    check dispCol("\tx", 1) == 4
    check dispCol("ab\tx", 3) == 4
    check dispCol("abcd\tx", 5) == 8

  test "byteColForDisp round-trips":
    let line = "ab\tcd"
    check byteColForDisp(line, dispCol(line, 3)) == 3
    check byteColForDisp(line, dispCol(line, 4)) == 4

  test "utf-8 rune navigation":
    let s = "héllo" # é is 2 bytes
    check s.nextRuneStart(1) == 3
    check s.prevRuneStart(3) == 1

  test "expandSlice horizontal scroll":
    check expandSlice("hello world", 6, 5) == "world"
    check expandSlice("\tabc", 0, 6) == "    ab"

suite "Search":
  test "find next wraps around":
    let b = newTextBuffer()
    b.insert("foo\nbar\nfoo baz")
    b.cursor = Pos(line: 2, col: 0)
    check b.findNext("foo") # should wrap to line 0
    check b.cursor.line == 0

  test "smart case: lowercase query is case-insensitive":
    let b = newTextBuffer()
    b.insert("Hello World")
    b.cursor = Pos(line: 0, col: 0)
    check b.findNext("world")
    check b.cursor.col == 6

  test "smart case: mixed-case query is case-sensitive":
    let b = newTextBuffer()
    b.insert("hello Hello")
    b.cursor = Pos(line: 0, col: 0)
    check b.findNext("Hello")
    check b.cursor.col == 6
