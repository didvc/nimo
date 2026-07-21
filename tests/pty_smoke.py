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
check("shows hint bar", "^S Save" in out and "^Q Quit" in out)
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

# 3. Undo removes inserted text (buffer goes back to empty -> no save needed).
out, rc = run(["abc", "\x1a", "\x1a", "\x1a", "\x11"])  # 3x Ctrl-Z then quit
check("undo lets us quit without unsaved prompt (rc 0)", rc == 0)

# 4. Search prompt appears on Ctrl-F.
out, rc = run(["\x06", "\x1b", "\x11"])  # Ctrl-F, Esc, then Ctrl-Q on clean buffer
check("Ctrl-F opens Find prompt", "Find:" in out)
check("Esc + quit works after Find", rc == 0)

print("\nAll pty smoke checks passed.")
