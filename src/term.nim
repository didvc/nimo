## Raw terminal input/output. Nim stdlib only.
##
## Handles raw mode, the alternate screen, bracketed paste, window resize and
## decoding of keyboard escape sequences into `Key` values.
##
## Two backends share one escape-sequence decoder:
##
## * POSIX — termios raw mode, SIGWINCH for resize, SIGTSTP for suspend.
## * Windows — `SetConsoleMode` with `ENABLE_VIRTUAL_TERMINAL_INPUT` and
##   `ENABLE_VIRTUAL_TERMINAL_PROCESSING`, which makes the console emit and
##   understand the same VT sequences the POSIX path uses. Requires Windows 10
##   1703 or newer; Windows Terminal is recommended. Resize is polled rather
##   than signalled, and suspend has no equivalent.

import std/strutils

when defined(windows):
  import std/winlean
else:
  import std/[termios, posix]

type
  KeyKind* = enum
    kNone, kChar, kCtrl, kEnter, kTab, kShiftTab, kBackspace, kDelete, kEsc,
    kUp, kDown, kLeft, kRight, kHome, kEnd, kPageUp, kPageDown,
    kCtrlUp, kCtrlDown, kCtrlLeft, kCtrlRight, kCtrlHome, kCtrlEnd,
    kF5, kPaste, kResize,
    kCtrlPageUp, kCtrlPageDown,
    kMouseDown, kScrollUp, kScrollDown

  Key* = object
    kind*: KeyKind
    ch*: string ## UTF-8 char (kChar), ctrl letter "a".."z" (kCtrl), text (kPaste)
    mx*, my*: int ## 1-based column/row for mouse events

var
  rawOn = false
  resized = false

# ---- platform backends ------------------------------------------------------
#
# Each backend provides: installWinchHandler, enterRaw, exitRaw, suspend,
# terminalSize, isTerminal, and the two input primitives readByte/pendingInput.

when defined(windows):

  const
    ENABLE_PROCESSED_INPUT = 0x0001'i32
    ENABLE_LINE_INPUT = 0x0002'i32
    ENABLE_ECHO_INPUT = 0x0004'i32
    ENABLE_WINDOW_INPUT = 0x0008'i32
    ENABLE_MOUSE_INPUT = 0x0010'i32
    ENABLE_VIRTUAL_TERMINAL_INPUT = 0x0200'i32
    ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004'i32
    DISABLE_NEWLINE_AUTO_RETURN = 0x0008'i32
    WAIT_OBJECT_0 = 0x0'i32
    CP_UTF8 = 65001'i32

  type
    COORD {.importc, header: "<windows.h>".} = object
      X, Y: int16
    SMALL_RECT {.importc, header: "<windows.h>".} = object
      Left, Top, Right, Bottom: int16
    CONSOLE_SCREEN_BUFFER_INFO {.importc, header: "<windows.h>".} = object
      dwSize: COORD
      dwCursorPosition: COORD
      wAttributes: int16
      srWindow: SMALL_RECT
      dwMaximumWindowSize: COORD

  proc getConsoleMode(h: Handle, mode: ptr int32): WINBOOL
    {.stdcall, dynlib: "kernel32", importc: "GetConsoleMode".}
  proc setConsoleMode(h: Handle, mode: int32): WINBOOL
    {.stdcall, dynlib: "kernel32", importc: "SetConsoleMode".}
  proc getConsoleScreenBufferInfo(h: Handle,
                                  info: ptr CONSOLE_SCREEN_BUFFER_INFO): WINBOOL
    {.stdcall, dynlib: "kernel32", importc: "GetConsoleScreenBufferInfo".}
  proc setConsoleOutputCP(codepage: int32): WINBOOL
    {.stdcall, dynlib: "kernel32", importc: "SetConsoleOutputCP".}
  proc setConsoleCP(codepage: int32): WINBOOL
    {.stdcall, dynlib: "kernel32", importc: "SetConsoleCP".}
  proc waitForSingleObject(h: Handle, ms: int32): int32
    {.stdcall, dynlib: "kernel32", importc: "WaitForSingleObject".}
  # Wide, not ANSI: ReadConsoleA cannot hand back a multi-byte character one
  # byte at a time, so non-ASCII input arrives mangled. Read UTF-16 and do the
  # UTF-8 conversion here, then feed the decoder a clean byte stream.
  proc readConsoleW(h: Handle, buf: pointer, toRead: int32,
                    numRead: ptr int32, reserved: pointer): WINBOOL
    {.stdcall, dynlib: "kernel32", importc: "ReadConsoleW".}
  proc wideCharToMultiByte(codePage, flags: int32, wstr: pointer, wlen: int32,
                           str: pointer, strLen: int32,
                           defaultChar, usedDefault: pointer): int32
    {.stdcall, dynlib: "kernel32", importc: "WideCharToMultiByte".}
  proc getFileType(h: Handle): int32
    {.stdcall, dynlib: "kernel32", importc: "GetFileType".}

  var
    hIn, hOut: Handle
    origInMode, origOutMode: int32
    origInCP, origOutCP: int32
    lastSize: tuple[w, h: int]

  proc getConsoleCP(): int32
    {.stdcall, dynlib: "kernel32", importc: "GetConsoleCP".}
  proc getConsoleOutputCP(): int32
    {.stdcall, dynlib: "kernel32", importc: "GetConsoleOutputCP".}

  proc terminalSize*(): tuple[w, h: int] =
    ## Visible window size, not the (often taller) scrollback buffer.
    var info: CONSOLE_SCREEN_BUFFER_INFO
    if getConsoleScreenBufferInfo(hOut, addr info) != 0:
      let w = int(info.srWindow.Right - info.srWindow.Left) + 1
      let h = int(info.srWindow.Bottom - info.srWindow.Top) + 1
      if w > 0 and h > 0:
        return (w, h)
    (80, 24)

  proc isTerminal*(): bool =
    const FILE_TYPE_CHAR = 0x0002'i32
    let h = getStdHandle(STD_INPUT_HANDLE)
    getFileType(h) == FILE_TYPE_CHAR

  proc installWinchHandler*() =
    ## Windows has no SIGWINCH; `pendingInput` polls the size instead.
    hIn = getStdHandle(STD_INPUT_HANDLE)
    hOut = getStdHandle(STD_OUTPUT_HANDLE)
    lastSize = terminalSize()

  proc enterRaw*() =
    if hIn == 0: installWinchHandler()
    discard getConsoleMode(hIn, addr origInMode)
    discard getConsoleMode(hOut, addr origOutMode)
    origInCP = getConsoleCP()
    origOutCP = getConsoleOutputCP()
    # UTF-8 so the editor's multi-byte output survives the console.
    discard setConsoleCP(CP_UTF8)
    discard setConsoleOutputCP(CP_UTF8)
    # VT input turns keys/mouse into the same escape sequences POSIX sends.
    var inMode = (origInMode and
                  not (ENABLE_PROCESSED_INPUT or ENABLE_LINE_INPUT or
                       ENABLE_ECHO_INPUT or ENABLE_WINDOW_INPUT)) or
                 ENABLE_VIRTUAL_TERMINAL_INPUT or ENABLE_MOUSE_INPUT
    discard setConsoleMode(hIn, inMode)
    var outMode = origOutMode or ENABLE_VIRTUAL_TERMINAL_PROCESSING or
                  DISABLE_NEWLINE_AUTO_RETURN
    discard setConsoleMode(hOut, outMode)
    rawOn = true
    lastSize = terminalSize()
    # alt screen on, bracketed paste on, SGR mouse tracking on, clear
    stdout.write "\e[?1049h\e[?2004h\e[?1000h\e[?1006h\e[2J\e[H"
    stdout.flushFile

  proc exitRaw*() =
    if rawOn:
      stdout.write "\e[?1000l\e[?1006l\e[?2004l\e[?1049l\e[?25h\e[0m"
      stdout.flushFile
      discard setConsoleMode(hIn, origInMode)
      discard setConsoleMode(hOut, origOutMode)
      discard setConsoleCP(origInCP)
      discard setConsoleOutputCP(origOutCP)
      rawOn = false

  const suspendSupported* = false
    ## Windows has no job control, so Ctrl+Z cannot hand back to the shell.
    ## Callers compile the suspend path out entirely.

  proc pollResize() =
    let s = terminalSize()
    if s != lastSize:
      lastSize = s
      resized = true

  var
    inBuf: string ## decoded UTF-8 bytes not yet handed to the decoder
    inPos: int

  proc fillBuf(): bool =
    ## Pulls one ReadConsoleW batch and converts it to UTF-8. A batch may hold a
    ## whole escape sequence, so callers must drain `inBuf` before waiting again.
    var wbuf: array[512, uint16]
    var n: int32 = 0
    if readConsoleW(hIn, addr wbuf[0], int32(wbuf.len), addr n, nil) == 0:
      return false
    if n <= 0: return false
    let need = wideCharToMultiByte(CP_UTF8, 0, addr wbuf[0], n, nil, 0, nil, nil)
    if need <= 0: return false
    var s = newString(need)
    if wideCharToMultiByte(CP_UTF8, 0, addr wbuf[0], n,
                           addr s[0], need, nil, nil) <= 0:
      return false
    inBuf = s
    inPos = 0
    true

  proc pendingInput(timeoutMs: int): bool =
    ## Also the resize poll: a size change wakes the wait like a signal would.
    if inPos < inBuf.len: return true # already buffered; don't block
    pollResize()
    if resized: return false
    waitForSingleObject(hIn, int32(timeoutMs)) == WAIT_OBJECT_0

  proc readByte(): int =
    ## -1 EOF/error, -2 interrupted (resize)
    while true:
      if inPos < inBuf.len:
        result = int(uint8(inBuf[inPos]))
        inc inPos
        return
      pollResize()
      if resized: return -2
      # Wait in slices so a resize during an idle blocking read is noticed.
      if waitForSingleObject(hIn, 50'i32) != WAIT_OBJECT_0:
        continue
      if not fillBuf(): return -1

else:

  when defined(linux):
    const SIGWINCH = cint(28)
    const SIGTSTP = cint(20)
  elif defined(macosx) or defined(bsd):
    const SIGWINCH = cint(28)
    const SIGTSTP = cint(18)
  else:
    const SIGWINCH = cint(28)
    const SIGTSTP = cint(20)

  var origTios: Termios

  proc onWinch(sig: cint) {.noconv.} =
    resized = true

  proc installWinchHandler*() =
    var sa: Sigaction
    sa.sa_handler = onWinch
    sa.sa_flags = 0 # no SA_RESTART: a pending read() returns EINTR so we redraw
    discard sigemptyset(sa.sa_mask)
    discard sigaction(SIGWINCH, sa, nil)

  proc enterRaw*() =
    discard tcGetAttr(0, addr origTios)
    var t = origTios
    t.c_iflag = t.c_iflag and not Cflag(BRKINT or ICRNL or INPCK or ISTRIP or IXON)
    t.c_oflag = t.c_oflag and not Cflag(OPOST)
    t.c_cflag = t.c_cflag or Cflag(CS8)
    t.c_lflag = t.c_lflag and not Cflag(ECHO or ICANON or IEXTEN or ISIG)
    t.c_cc[VMIN] = 1.char
    t.c_cc[VTIME] = 0.char
    discard tcSetAttr(0, TCSAFLUSH, addr t)
    rawOn = true
    # alt screen on, bracketed paste on, SGR mouse tracking on, clear
    stdout.write "\e[?1049h\e[?2004h\e[?1000h\e[?1006h\e[2J\e[H"
    stdout.flushFile

  proc exitRaw*() =
    if rawOn:
      stdout.write "\e[?1000l\e[?1006l\e[?2004l\e[?1049l\e[?25h\e[0m"
      stdout.flushFile
      discard tcSetAttr(0, TCSAFLUSH, addr origTios)
      rawOn = false

  proc suspend*() =
    ## Ctrl+Z: hand control back to the shell via job control, then resume in
    ## raw mode once the process is continued (e.g. with `fg`).
    exitRaw()
    discard kill(getpid(), SIGTSTP)
    enterRaw()

  const suspendSupported* = true

  proc terminalSize*(): tuple[w, h: int] =
    var ws: IOctl_WinSize
    if ioctl(1, TIOCGWINSZ, addr ws) == 0 and ws.ws_row > 0:
      (int(ws.ws_col), int(ws.ws_row))
    else:
      (80, 24)

  proc isTerminal*(): bool =
    isatty(0) != 0

  proc readByte(): int =
    ## -1 EOF/error, -2 interrupted by signal (e.g. resize)
    var b: uint8
    let n = posix.read(0, addr b, 1)
    if n == 1: return int(b)
    if n < 0 and errno == EINTR: return -2
    return -1

  proc pendingInput(timeoutMs: int): bool =
    var fds: TFdSet
    FD_ZERO(fds)
    FD_SET(0, fds)
    var tv: Timeval
    tv.tv_sec = posix.Time(timeoutMs div 1000)
    tv.tv_usec = Suseconds(timeoutMs mod 1000 * 1000)
    result = select(1, addr fds, nil, nil, addr tv) > 0

# ---- shared escape-sequence decoder ----------------------------------------

proc inputPending*(): bool =
  ## True when a key is already buffered, so the caller can drain a burst and
  ## repaint once instead of once per key. Windows has no bracketed paste
  ## (conhost never implemented it and ConPTY strips the markers), so a paste
  ## arrives as thousands of ordinary keystrokes and this is what keeps it from
  ## costing thousands of full-screen repaints.
  pendingInput(0)

proc utf8SeqLen(b: int): int =
  if b < 0x80: 1
  elif b shr 5 == 0b110: 2
  elif b shr 4 == 0b1110: 3
  elif b shr 3 == 0b11110: 4
  else: 1

proc readPaste(): Key =
  ## Reads bracketed-paste payload until ESC [ 2 0 1 ~
  var text = ""
  while true:
    let b = readByte()
    if b < 0: break
    text.add char(b)
    if text.endsWith("\e[201~"):
      text.setLen(text.len - 6)
      break
  Key(kind: kPaste, ch: text)

proc withCtrl(plain, ctrl: KeyKind, params: string): Key =
  # modifier param 5 (or 6) means Ctrl is held
  let parts = params.split(';')
  if parts.len > 1 and parts[^1] in ["5", "6"]:
    Key(kind: ctrl)
  else:
    Key(kind: plain)

proc readMouse(): Key =
  ## Decodes an SGR mouse report: ESC [ < Cb ; Cx ; Cy (M|m)
  var params = ""
  var final = '\0'
  while true:
    if not pendingInput(50): return Key(kind: kNone)
    let b = readByte()
    if b < 0: return Key(kind: kNone)
    let c = char(b)
    if c in {'0'..'9', ';'}: params.add c
    else: (final = c; break)
  let parts = params.split(';')
  if parts.len != 3: return Key(kind: kNone)
  var cb, mx, my: int
  try:
    cb = parseInt(parts[0]); mx = parseInt(parts[1]); my = parseInt(parts[2])
  except ValueError:
    return Key(kind: kNone)
  if (cb and 64) != 0: # scroll wheel
    return if (cb and 1) != 0: Key(kind: kScrollDown, mx: mx, my: my)
           else: Key(kind: kScrollUp, mx: mx, my: my)
  if final == 'm': return Key(kind: kNone)   # button release
  if (cb and 32) != 0: return Key(kind: kNone) # drag/motion
  if (cb and 3) == 0: return Key(kind: kMouseDown, mx: mx, my: my) # left press
  Key(kind: kNone)

proc readCsi(): Key =
  var params = ""
  var first = true
  while true:
    if not pendingInput(50): return Key(kind: kEsc)
    let b = readByte()
    if b < 0: return Key(kind: kEsc)
    let c = char(b)
    if first and c == '<':
      return readMouse()
    first = false
    if c in {'0'..'9', ';'}:
      params.add c
      continue
    case c
    of 'A': return withCtrl(kUp, kCtrlUp, params)
    of 'B': return withCtrl(kDown, kCtrlDown, params)
    of 'C': return withCtrl(kRight, kCtrlRight, params)
    of 'D': return withCtrl(kLeft, kCtrlLeft, params)
    of 'H': return withCtrl(kHome, kCtrlHome, params)
    of 'F': return withCtrl(kEnd, kCtrlEnd, params)
    of 'Z': return Key(kind: kShiftTab)
    of '~':
      let code = params.split(';')[0]
      case code
      of "1", "7": return withCtrl(kHome, kCtrlHome, params)
      of "3": return Key(kind: kDelete)
      of "4", "8": return withCtrl(kEnd, kCtrlEnd, params)
      of "5": return withCtrl(kPageUp, kCtrlPageUp, params)
      of "6": return withCtrl(kPageDown, kCtrlPageDown, params)
      of "15": return Key(kind: kF5)
      of "200": return readPaste()
      else: return Key(kind: kNone)
    else:
      return Key(kind: kNone)

proc readKey*(): Key =
  ## Blocks until one key event is available.
  if resized:
    resized = false
    return Key(kind: kResize)
  let b0 = readByte()
  if b0 == -2:
    resized = false
    return Key(kind: kResize)
  if b0 < 0:
    return Key(kind: kEsc) # EOF: shouldn't happen on a tty
  case b0
  of 13, 10:
    Key(kind: kEnter)
  of 9:
    Key(kind: kTab)
  of 127, 8:
    Key(kind: kBackspace)
  of 27:
    if not pendingInput(30):
      Key(kind: kEsc)
    else:
      let b1 = readByte()
      case char(b1)
      of '[':
        readCsi()
      of 'O':
        if pendingInput(30):
          case char(readByte())
          of 'H': Key(kind: kHome)
          of 'F': Key(kind: kEnd)
          of 'A': Key(kind: kUp)
          of 'B': Key(kind: kDown)
          of 'C': Key(kind: kRight)
          of 'D': Key(kind: kLeft)
          else: Key(kind: kNone)
        else:
          Key(kind: kEsc)
      else:
        Key(kind: kEsc) # Alt+key: treat as Esc
  elif b0 >= 1 and b0 <= 26:
    Key(kind: kCtrl, ch: $char(b0 + ord('a') - 1))
  elif b0 < 32:
    Key(kind: kNone)
  else:
    var s = $char(b0)
    for _ in 1 ..< utf8SeqLen(b0):
      if pendingInput(30):
        let nb = readByte()
        if nb >= 0: s.add char(nb)
    Key(kind: kChar, ch: s)
