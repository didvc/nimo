# nimo

*Nim Terminal Text Editor.*

A small, friendly terminal text editor written in Nim using only the standard
library. It's nano-inspired (discoverable shortcuts, a hint bar at the bottom)
but comfortable for people coming from VSCode: a file-tree sidebar shows the
whole working directory, editor tabs sit across the top, and the mouse works
for clicking files, switching tabs and placing the cursor.

![nimo editing its own source tree](images/screenshot.png)

## Features

- A file-tree sidebar of the current working directory, shown by default.
- Editor tabs with a modified dot, closable with the mouse or `Ctrl+W`; the
  strip scrolls sideways when more tabs are open than fit.
- Mouse support: click a file to open it, click a tab to switch, and use the
  wheel to scroll whichever pane the pointer is over.
- UTF-8-aware editing with undo/redo and a save-point indicator.
- Smart-case search, go-to-line, and word-wise cursor movement.
- `Ctrl+Z` suspends back to the shell and resumes cleanly with `fg`.
- No external libraries — the Nim standard library is the only requirement.

## Build

Requires Nim >= 2.0 (tested on 2.2.10). No dependencies to fetch.

```sh
nim c -d:release --out:nimo src/nimo.nim
```

Or via nimble:

```sh
nimble build          # produces ./nimo
nimble run            # build + open the current directory
```

## Run

```sh
./nimo                # open the editor rooted at the current directory
./nimo path/file      # open (or create) a specific file
```

## Keybindings

### Everywhere
| Key | Action |
| --- | --- |
| `Ctrl+S` | Save (prompts for a name if the buffer has none) |
| `Ctrl+X` | Quit (`Ctrl+Q` also works; asks to confirm if anything is unsaved) |
| `Ctrl+B` | Toggle the file-tree sidebar |
| `Ctrl+O` | Move focus to the file tree to browse and open |
| `Ctrl+Z` | Suspend to the shell (resume with `fg`) |
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
| `Ctrl+U` / `Ctrl+R` | Undo / redo (`Ctrl+Y` also redoes) |
| `Ctrl+A` / `Ctrl+E` | Start / end of line (nano-style) |
| `Ctrl+W` | Close the current tab |
| `Ctrl+PageUp` / `Ctrl+PageDown` | Switch to the previous / next tab |

### File-tree pane
| Key | Action |
| --- | --- |
| `↑` / `↓` | Move the selection |
| `→` / `←` | Expand / collapse (or step into / out of) a folder |
| `Enter` | Open a file, or expand/collapse a folder |
| `n` | Create a new file in the selected folder |
| `r` / `F5` | Refresh the tree from disk |
| `Tab` | Return focus to the editor |

### Mouse
| Action | Result |
| --- | --- |
| Click a tree entry | Open the file, or expand/collapse the folder |
| Click a tab | Switch to it; click its `×` / `●` marker to close |
| Click the `‹` / `›` chevrons | Scroll the tab strip when it overflows |
| Click in the text | Place the cursor there |
| Scroll wheel | Scroll the tree, the text, or the tab strip under the pointer |

## Design notes

The code splits into four modules. `term.nim` handles raw mode, key and mouse
decoding, bracketed paste, window-resize (SIGWINCH) and shell suspend
(SIGTSTP). `textbuffer.nim` is the editing core: UTF-8 aware, with
tab-expansion display math, an undo/redo journal and smart-case search.
`filetree.nim` is the lazy, cached sidebar model. `nimo.nim` wires them
together with the rendering and input loop.

Each open file is its own buffer with its own cursor and scroll position.
Opening a file from the tree switches to its tab when it is already open, so
nothing is discarded behind your back. Cursor movement, deletion and
horizontal scrolling all count whole runes and their on-screen display
columns, and the modified dot in the status bar tracks the exact save point,
so undoing back past a save clears it. Files that look binary, or that exceed
20 MB, are refused rather than mangled.

## Tests

```sh
nim c -r tests/test_buffer.nim   # unit tests for the editing core
python3 tests/pty_smoke.py       # drives the real TUI through a pty
python3 tests/pty_suspend.py     # checks Ctrl+Z suspend / resume
```

## Screenshot

The image above is generated from this repository with `scripts/screenshot.sh`,
which drives nimo inside a tmux pane and renders the captured screen with
[freeze](https://github.com/charmbracelet/freeze).
