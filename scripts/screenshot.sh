#!/usr/bin/env bash
#
# Generate a showcase screenshot of nimo driving *this* repository.
#
# It runs nimo inside a detached tmux pane, expands the src/ and tests/ folders
# in the sidebar, opens README.md plus three source files as tabs (README made
# the active tab), then captures the pane and renders it to a PNG with freeze:
#
#     tmux capture-pane -e -p | freeze -o images/screenshot.png
#
# Requirements: tmux, freeze (charmbracelet), and the Nim compiler.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION="nimo_shot"
OUT="${1:-$REPO/images/screenshot.png}"
COLS=110
ROWS=32
FREEZE_ARGS=(--window --padding 0 --border.radius 8)

cd "$REPO"

# 1. Build the binary if it is missing or out of date.
if [[ ! -x ./nimo || src/nimo.nim -nt ./nimo ]]; then
  echo "Building nimo…"
  nim c -d:release --hints:off --out:nimo src/nimo.nim
fi
mkdir -p "$(dirname "$OUT")"

# 2. Fresh tmux session running nimo on README.md at a fixed size.
tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" -x "$COLS" -y "$ROWS"
tmux send-keys -t "$SESSION" "cd $REPO && ./nimo README.md" Enter
sleep 1.0

send() { tmux send-keys -t "$SESSION" "$@"; }

# Flat index (0-based) of a sidebar entry, searching only the 30-col sidebar.
flat_index() {
  local name="$1" line
  line=$(tmux capture-pane -p -t "$SESSION" | cut -c1-30 \
         | grep -nE "(^|[ ▸▾])$name( |$)" | head -1 | cut -d: -f1 || true)
  [[ -n "$line" ]] && echo $(( line - 2 )) || echo -1
}

# Move the tree selection to a flat index (Home = top, then N × Down).
goto() {
  local idx="$1" k
  send Home
  for (( k = 0; k < idx; k++ )); do send Down; done
}

focus_tree() { send C-o; sleep 0.2; }
expand()   { focus_tree; goto "$(flat_index "$1")"; send Right; sleep 0.3; }
open_file() { focus_tree; goto "$(flat_index "$1")"; send Enter; sleep 0.3; }

# 3. Drive the UI: expand folders, open tabs, land on README.
expand "src"
expand "tests"
open_file "filetree.nim"
open_file "term.nim"
open_file "textbuffer.nim"
open_file "README.md"     # already open (tab 0) → just switches back to it
sleep 0.4

# 4. Capture the pane with colors and render to a PNG.
tmux capture-pane -e -p -t "$SESSION" | freeze "${FREEZE_ARGS[@]}" -o "$OUT"

tmux kill-session -t "$SESSION" 2>/dev/null || true
echo "Wrote $OUT"
