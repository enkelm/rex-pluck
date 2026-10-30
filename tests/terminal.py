#!/usr/bin/env python3
"""Small standard-library PTY bridge for Rex-embedded Lua integration tests."""
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios

transcript = os.environ["REX_PLUCK_TEST_PTY_OUTPUT"]
rows = int(os.environ.get("REX_TEST_ROWS", "14"))
columns = int(os.environ.get("REX_TEST_COLUMNS", "100"))
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])


def resize(row_count, column_count):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", row_count, column_count, 0, 0))


def stop(_sig, _frame):
    try:
        os.kill(pid, signal.SIGHUP)
    except ProcessLookupError:
        pass


def narrow(_sig, _frame):
    resize(4, 12)


def restore(_sig, _frame):
    resize(rows, columns)


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGUSR1, narrow)
signal.signal(signal.SIGUSR2, restore)
resize(rows, columns)
inputs = [fd, 0]
with open(transcript, "ab", buffering=0) as output:
    while True:
        ready, _, _ = select.select(inputs, [], [], 0.1)
        if fd in ready:
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            if not data:
                break
            output.write(data)
        if 0 in ready:
            data = os.read(0, 4096)
            if data:
                os.write(fd, data)
            else:
                inputs.remove(0)
    _, status = os.waitpid(pid, 0)
    try:
        attrs = termios.tcgetattr(fd)
        restored = bool(attrs[3] & termios.ICANON and attrs[3] & termios.ECHO)
    except OSError:
        restored = False
    output.write(("\nPTY_RESTORED=" + str(restored) + "\n").encode())
os._exit(os.waitstatus_to_exitcode(status))
