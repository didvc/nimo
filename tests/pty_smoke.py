#!/usr/bin/env python3
"""Drive the real ternimal TUI through a pty and assert on behavior."""
import os, pty, select, subprocess, sys, time, tempfile, shutil

BIN = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "ternimal"))

def run(keystrokes, argv=None, cols=100, rows=30):
    argv = argv or []
    master, slave = pty.openpty()
    import fcntl, termios, struct
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    p = subprocess.Popen([BIN] + argv, stdin=slave, stdout=slave, stderr=slave,
                         close_fds=True)
    os.close(slave)
    out = bytearray()
    def pump(t=0.25):
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([master], [], [], 0.05)
            if r:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    return
                if not data: return
                out.extend(data)
    pump(0.4)
    for k in keystrokes:
        os.write(master, k if isinstance(k, bytes) else k.encode())
        pump(0.2)
    p.wait(timeout=5)
    os.close(master)
    return out.decode("utf-8", "replace"), p.returncode

def check(name, cond):
    print(("PASS" if cond else "FAIL"), name)
    if not cond:
        sys.exit(1)

# 1. Starts, shows sidebar tree + hint bar, then quits cleanly on ^Q.
out, rc = run(["\x11"])  # Ctrl-Q
check("starts and quits on ^Q", rc == 0)
check("renders alt screen", "\x1b[?1049h" in out)
check("shows hint bar", "^S Save" in out and "^X Quit" in out)
check("lists tree files (src)", "src" in out)

# 2. Type text into a new file, save it, verify contents on disk.
tmp = tempfile.mkdtemp()
target = os.path.join(tmp, "hello.txt")
cwd = os.getcwd()
os.chdir(tmp)
try:
    out, rc = run(["Hello, ternimal!", "\r", "second line", "\x13", "\x11"],
                  argv=[target])
    check("typed-file quits cleanly", rc == 0)
    with open(target) as f:
        content = f.read()
    check("file saved with typed content",
          content == "Hello, ternimal!\nsecond line\n")
finally:
    os.chdir(cwd)
    shutil.rmtree(tmp, ignore_errors=True)

# 3. Undo (Ctrl-U) removes inserted text (buffer back to empty -> no save prompt).
#    NOTE: never send Ctrl-Z (\x1a) here -- it now suspends the process (SIGTSTP)
#    and would hang the test harness.
out, rc = run(["abc", "\x15", "\x15", "\x15", "\x18"])  # 3x Ctrl-U then Ctrl-X quit
check("Ctrl-U undo lets us quit without unsaved prompt (rc 0)", rc == 0)

# 3b. Ctrl-X quits (nano-style) on a clean buffer.
out, rc = run(["\x18"])
check("Ctrl-X quits", rc == 0)

# 4. Search prompt appears on Ctrl-F.
out, rc = run(["\x06", "\x1b", "\x18"])  # Ctrl-F, Esc, then Ctrl-X on clean buffer
check("Ctrl-F opens Find prompt", "Find:" in out)
check("Esc + quit works after Find", rc == 0)

def click(col, row):        # SGR mouse: left button press at (col,row), 1-based
    return f"\x1b[<0;{col};{row}M"
def wheel(up, col, row):    # scroll wheel report
    return f"\x1b[<{64 if up else 65};{col};{row}M"

# 5. Mouse: click files in the tree to open them in tabs (no discard prompt).
tmp = tempfile.mkdtemp()
os.chdir(tmp)
try:
    with open("alpha.txt", "w") as f: f.write("A\n")
    with open("beta.txt", "w") as f: f.write("B\n")
    # tree rows start on terminal row 2 (row 1 is the tab bar). With no
    # subdirectories, alpha.txt is row 2 and beta.txt is row 3.
    out, rc = run([click(3, 2),          # open alpha.txt
                   click(3, 3),          # open beta.txt (second new tab)
                   "\x11"])              # quit (all clean)
    check("clicking a tree file opens it", "Opened alpha.txt" in out)
    check("both files appear as tabs", "alpha.txt" in out and "beta.txt" in out)
    check("no discard prompt when opening via mouse", "Discard" not in out)
    check("tab counter shows 3 open tabs", "[3/3]" in out)
    check("mouse-driven session quits cleanly", rc == 0)

    # 6. Ctrl+W closes the current tab; Ctrl+PageUp/Down switch tabs.
    out, rc = run([click(3, 2), click(3, 3),  # open both -> 3 tabs
                   "\x17",                     # Ctrl-W close beta.txt -> 2 tabs
                   "\x11"])
    check("Ctrl-W closes a tab (2 left)", "[2/2]" in out)
    check("close leaves editor usable", rc == 0)

    # 7. Scroll wheel over the editor doesn't crash and still quits.
    out, rc = run([wheel(False, 40, 5), wheel(True, 40, 5), "\x11"])
    check("scroll wheel handled", rc == 0)
finally:
    os.chdir(cwd)
    shutil.rmtree(tmp, ignore_errors=True)

# 8. Many tabs overflow the bar and become horizontally scrollable (chevrons).
tmp = tempfile.mkdtemp()
os.chdir(tmp)
try:
    for n in range(12):
        with open(f"file{n:02d}.txt", "w") as f: f.write(f"content {n}\n")
    # Open all 12 by clicking tree rows 2..13, then wheel-scroll the tab bar.
    keys = [click(3, 2 + n) for n in range(12)]
    keys += [wheel(True, 50, 1), wheel(False, 50, 1)]  # scroll tabs at row 1
    keys += ["\x18"]                                   # Ctrl-X quit (all clean)
    out, rc = run(keys, cols=80)
    check("opened 13 tabs (1 empty + 12 files)", "[13/13]" in out)
    check("overflowing tabs show a scroll chevron", "›" in out or "‹" in out)
    check("tab-overflow session quits cleanly", rc == 0)
finally:
    os.chdir(cwd)
    shutil.rmtree(tmp, ignore_errors=True)

print("\nAll pty smoke checks passed.")
