## Raw terminal input/output. POSIX only, Nim stdlib only.
##
## Handles raw mode via termios, the alternate screen, bracketed paste,
## SIGWINCH, and decoding of keyboard escape sequences into `Key` values.

import std/[termios, posix, strutils]

when defined(linux):
  const SIGWINCH = cint(28)
elif defined(macosx) or defined(bsd):
  const SIGWINCH = cint(28)
else:
  const SIGWINCH = cint(28)

type
  KeyKind* = enum
    kNone, kChar, kCtrl, kEnter, kTab, kShiftTab, kBackspace, kDelete, kEsc,
    kUp, kDown, kLeft, kRight, kHome, kEnd, kPageUp, kPageDown,
    kCtrlUp, kCtrlDown, kCtrlLeft, kCtrlRight, kCtrlHome, kCtrlEnd,
    kF5, kPaste, kResize

  Key* = object
    kind*: KeyKind
    ch*: string ## UTF-8 char (kChar), ctrl letter "a".."z" (kCtrl), text (kPaste)

var
  origTios: Termios
  rawOn = false
  resized = false

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
  # alt screen on, bracketed paste on, clear
  stdout.write "\e[?1049h\e[?2004h\e[2J\e[H"
  stdout.flushFile

proc exitRaw*() =
  if rawOn:
    stdout.write "\e[?2004l\e[?1049l\e[?25h\e[0m"
    stdout.flushFile
    discard tcSetAttr(0, TCSAFLUSH, addr origTios)
    rawOn = false

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

proc readCsi(): Key =
  var params = ""
  while true:
    if not pendingInput(50): return Key(kind: kEsc)
    let b = readByte()
    if b < 0: return Key(kind: kEsc)
    let c = char(b)
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
      of "5": return Key(kind: kPageUp)
      of "6": return Key(kind: kPageDown)
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
