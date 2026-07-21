#!/usr/bin/env python3
"""Verify Ctrl+Z suspends nimo to the shell and it resumes on SIGCONT."""
import os, pty, select, subprocess, sys, time, signal, struct, fcntl, termios

BIN = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "nimo"))

def proc_state(pid):
    """Single-char process state from /proc/<pid>/stat (T = stopped)."""
    try:
        with open(f"/proc/{pid}/stat") as f:
            data = f.read()
        return data[data.rindex(")") + 2]
    except (OSError, ValueError):
        return "?"

def wait_state(pid, want, timeout=3.0):
    end = time.time() + timeout
    while time.time() < end:
        if proc_state(pid) in want:
            return True
        time.sleep(0.03)
    return False

def check(name, cond):
    print(("PASS" if cond else "FAIL"), name)
    if not cond:
        sys.exit(1)

master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
p = subprocess.Popen([BIN], stdin=slave, stdout=slave, stderr=slave, close_fds=True)
os.close(slave)

out = bytearray()
def drain(t=0.2):
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([master], [], [], 0.05)
        if r:
            try: out.extend(os.read(master, 65536))
            except OSError: return

drain(0.4)
check("editor is running before suspend", proc_state(p.pid) in "SR")

os.write(master, b"\x1a")   # Ctrl+Z -> should raise SIGTSTP on itself
check("Ctrl+Z stops the process (state T)", wait_state(p.pid, "T"))

# The alt screen must be torn down before stopping so the shell is usable.
drain(0.2)
check("left alt-screen on suspend", out.decode("utf-8", "replace").count("\x1b[?1049l") >= 1)

os.kill(p.pid, signal.SIGCONT)   # shell `fg` equivalent
check("SIGCONT resumes the process", wait_state(p.pid, "SR"))
drain(0.3)
text = out.decode("utf-8", "replace")
check("re-entered alt-screen/raw mode on resume", text.count("\x1b[?1049h") >= 2)

os.write(master, b"\x18")   # Ctrl+X quit
try:
    p.wait(timeout=5)
except subprocess.TimeoutExpired:
    p.kill(); check("quits after resume", False)
check("quits cleanly after resume (rc 0)", p.returncode == 0)
os.close(master)
print("\nSuspend/resume checks passed.")
