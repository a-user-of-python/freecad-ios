# Spike S3 probe — runs inside the embedded interpreter on the iOS
# Simulator (Phase A1) and writes a plain-text report to
# S3_RESULT_PATH (injected by main.m; falls back to ~/Documents).
#
# Every import is recorded individually: a failed stdlib import is
# packaging data for the port, not a spike failure. The spike-level
# success marker is PYTHON-EMBED-OK, written once the interpreter has
# run this script end to end.

import os
import sys
import traceback

RESULT = globals().get("S3_RESULT_PATH") or os.path.expanduser(
    "~/Documents/s3-result.txt")

lines = []


def log(s):
    lines.append(s)
    print(s, flush=True)


MODULES = [
    # core / language services
    "sys", "os", "io", "re", "json", "math", "cmath", "random",
    "collections", "itertools", "functools", "pathlib", "datetime",
    "zoneinfo", "struct", "array", "csv", "argparse", "importlib",
    "unittest", "logging", "threading", "concurrent.futures",
    # binary / OS-adjacent
    "ctypes", "_ctypes", "mmap", "select", "socket", "ssl", "_ssl",
    "hashlib", "_hashlib", "hmac", "sqlite3", "_sqlite3", "zlib",
    "bz2", "lzma", "tarfile", "zipfile", "tempfile", "subprocess",
    "multiprocessing", "asyncio", "signal", "termios", "unicodedata",
    # data / text
    "decimal", "_decimal", "xml.etree.ElementTree", "pyexpat",
    "_elementtree", "email", "urllib.request", "shelve", "dbm",
    # expected-absent candidates (recorded, not fatal)
    "tkinter", "turtle", "idlelib", "venv", "ensurepip",
]

results = {}
try:
    log("PYTHON-EMBED-OK")
    log("VERSION: %s" % sys.version.replace("\n", " "))
    log("VERSION_INFO: %d.%d.%d" % sys.version_info[:3])
    log("PLATFORM: %s" % sys.platform)
    log("EXECUTABLE: %s" % sys.executable)
    log("PREFIX: %s" % sys.prefix)
    for mod in MODULES:
        try:
            __import__(mod)
            results[mod] = "OK"
            log("IMPORT %s OK" % mod)
        except Exception as exc:  # noqa: BLE001 - recording, not hiding
            results[mod] = "FAIL: %s: %s" % (type(exc).__name__, exc)
            log("IMPORT %s FAIL: %s: %s" % (mod, type(exc).__name__, exc))
    # ctypes must do more than import: libffi has to actually call.
    try:
        import ctypes
        import ctypes.util
        libc = ctypes.CDLL(None)
        log("CTYPES-CDLL-MAIN OK: %r" % (libc is not None))
    except Exception as exc:  # noqa: BLE001
        log("CTYPES-CDLL-MAIN FAIL: %s: %s" % (type(exc).__name__, exc))
    ok = sorted(k for k, v in results.items() if v == "OK")
    bad = sorted(k for k, v in results.items() if v != "OK")
    log("IMPORT-SUMMARY OK=%d FAIL=%d" % (len(ok), len(bad)))
    log("IMPORT-FAILURES: %s" % (", ".join(bad) if bad else "(none)"))
    log("PROBE-DONE")
except Exception:  # noqa: BLE001
    log("PROBE-EXCEPTION")
    log(traceback.format_exc())
finally:
    try:
        with open(RESULT, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
    except Exception:  # noqa: BLE001
        print("could not write result file", flush=True)
