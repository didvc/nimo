# ternimal

A smsall, friendly terminal text editor written in Nim using only the standard
library. It's nano-inspired (discoverable shortcuts, a hint bar at the bottom)
but comfortable for people coming from VSCode: a file-tree sidebar on the left
shows the whole current working directory by default, and the editing keys are
the ones you already know (arrows, Home/End, Ctrl+arrows for word jumps, Ctrl+S
to save, Ctrl+Z/Ctrl+Y).

```
┌─ files ───────┬─────────────────────────────────────────────┐
│ ▾ src         │   1  ## ternimal — a terminal text editor    │
│     term.nim  │   2                                          │
│   ▸ assets    │   3  proc main() =                           │
│     main.nim  │   4    echo "hi"                              │
├───────────────┴─────────────────────────────────────────────┤
│ main.nim  ●   Saved main.nim              Ln 4, Col 12        │
│ ^S Save  ^F Find  ^G GoTo  ^Z Undo  ^B Tree  ^Q Quit         │
└──────────────────────────────────────────────────────────────┘
```

## Build

Requires Nim >= 2.0 (tested on 2.2.10). No dependencies to fetch.

```sh
nim c -d:release --out:ternimal src/ternimal.nim
```

Or via nimble:

```sh
nimble build          # produces ./ternimal
nimble run            # build + open the current directory
```

## Run

```sh
./ternimal            # open the editor rooted at the current directory
./ternimal path/file  # open (or create) a specific file
```

## Keybindings

### Everywhere
| Key | Action |
| --- | --- |
| `Ctrl+S` | Save (prompts for a name if the buffer has none) |
| `Ctrl+Q` | Quit (asks to confirm if there are unsaved changes) |
| `Ctrl+B` | Toggle the file-tree sidebar |
| `Ctrl+O` | Jump focus to the file tree to browse/open |
| `Shift+Tab` | Switch focus between the editor and the tree |

### Editor pane
| Key | Action |
| --- | --- |
| Arrows / `Home` / `End` | Move the cursor |
| `Ctrl+←` / `Ctrl+→` | Move by word |
| `Ctrl+Home` / `Ctrl+End` | Jump to start / end of file |
| `PageUp` / `PageDown` | Scroll by a screen |
| `Ctrl+F` | Find (smart-case; `Ctrl+N` repeats the last search) |
| `Ctrl+G` | Go to line number |
| `Ctrl+Z` / `Ctrl+Y` | Undo / redo |
| `Ctrl+A` / `Ctrl+E` | Start / end of line (nano-style) |

### File-tree pane
| Key | Action |
| --- | --- |
| `↑` / `↓` | Move the selection |
| `→` / `←` | Expand / collapse (or step into / out of) a folder |
| `Enter` | Open a file, or expand/collapse a folder |
| `n` | Create a new file in the selected folder |
| `r` / `F5` | Refresh the tree from disk |
| `Tab` | Return focus to the editor |

## Design notes

- **Four modules.** `term.nim` handles raw mode, escape-sequence decoding,
  bracketed paste and window-resize (SIGWINCH); `textbuffer.nim` is the editing
  core (UTF-8 aware, tab-expansion display math, undo/redo, smart-case search);
  `filetree.nim` is the lazy, cached sidebar model; `ternimal.nim` wires them
  together with rendering and the input loop.
- **UTF-8 aware.** Cursor movement, deletion and horizontal scrolling all work
  in terms of whole runes and their on-screen display columns.
- **Undo/redo** is a full edit journal; the "modified" dot in the status bar
  tracks the exact save point (undoing back past a save clears it).
- **Binary and oversized files** are refused rather than mangled.

## Tests

```sh
nim c -r tests/test_buffer.nim   # unit tests for the editing core
python3 tests/pty_smoke.py       # drives the real TUI through a pty
```
