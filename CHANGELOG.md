# Changelog

Changes to nimo, newest first.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-07-28

### Added

- **Windows support.** Linux, macOS/BSD and Windows now share one codebase, and
  only `term.nim` differs. The Windows backend switches the console into VT mode
  (`ENABLE_VIRTUAL_TERMINAL_INPUT` / `ENABLE_VIRTUAL_TERMINAL_PROCESSING`) so it
  emits and understands the same escape sequences as a POSIX terminal, which
  lets both platforms share the entire key and mouse decoder. Requires Windows
  10 1703 or newer. Tested on 10.0.19045 with Nim 2.2.4 and mingw64.
- `terminalSize()`, `isTerminal()` and `inputPending()` in `term.nim`, so
  `nimo.nim` no longer imports `posix`/`termios` directly and is now free of
  platform-specific code.

### Fixed

- **Pasting large amounts of text was extremely slow on Windows.** A 500-line
  paste took over a minute. Windows has no bracketed paste, because the legacy
  console never implemented it and ConPTY strips the `ESC[200~` / `ESC[201~`
  markers, so a paste arrives as thousands of ordinary keystrokes and the input
  loop repainted the whole screen for every one of them. The loop now drains all
  buffered input before repainting. A 500-line paste went from 58.5s to 0.2s on
  Windows, and from 0.47s to 0.02s on Linux when bracketed paste is unavailable.
  Bursts from held keys, fast typing and the scroll wheel benefit equally.

### Changed

- On Windows the hint bar advertises `^G Goto` in place of `^Z Suspend`, and
  `Ctrl+Z` reports that suspend is unavailable instead of doing nothing.

### Known limitations on Windows

- `Ctrl+Z` suspend needs job control, which Windows has no equivalent for.
- Window resize is polled rather than delivered by a signal.
- Without bracketed paste, each pasted character is its own undo step, so
  `Ctrl+U` after a paste undoes one character at a time rather than the whole
  paste.
- Windows Terminal is recommended over the legacy console host, particularly
  for mouse support.

## [0.1.0] - 2026-07-21

The first release of a nano-inspired terminal text editor written in Nim using
only the standard library.

### Added

- File-tree sidebar of the working directory, shown by default.
- Editor tabs with a modified indicator, closable with the mouse or `Ctrl+W`.
  The strip scrolls sideways when more tabs are open than fit.
- Mouse support for opening files, switching tabs, and scrolling whichever pane
  the pointer is over.
- UTF-8-aware editing with undo/redo and a save-point indicator.
- Smart-case search, go-to-line, and word-wise cursor movement.
- `Ctrl+Z` suspends back to the shell and resumes cleanly with `fg`.
- Refuses files that look binary or exceed 20 MB rather than mangling them.

[Unreleased]: https://github.com/didvc/nimo/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/didvc/nimo/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/didvc/nimo/releases/tag/v0.1.0
