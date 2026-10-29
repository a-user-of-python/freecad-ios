# Spike S3 Phase A2 prelude — runs inside the A2 harness BEFORE
# probe_a2.py, through Base::Interpreter().runFile().
#
# Belt-and-braces for the two things Application::init may not have
# done inside an iOS bundle (its AppHomePath derivation assumes a
# desktop/macOS layout):
#   1. sys.path: the bundle's lib/ (C++ extension modules, model 1)
#      and Mod/ (pure-Python packages + Init.py scripts).
#   2. Init.py registration: exec each enabled module's Init.py so
#      FreeCAD.addImportType/addExportType routing (Part BREP/IGES,
#      Import STEP) exists even if init's module auto-load skipped
#      the bundle. Re-running an Init.py is harmless: registrations
#      replace, they do not stack.
#
# Logs go to Documents/s3-a2-prelude.txt (probe_a2.py owns
# s3-a2-result.txt and overwrites it on flush).

import os
import sys
import traceback

bundle = os.environ.get("S3_BUNDLE", "")
docs = os.environ.get("S3_DOCS", os.path.expanduser("~/Documents"))
lines = []


def log(s):
    lines.append(str(s))
    print(s, flush=True)


def flush():
    try:
        with open(os.path.join(docs, "s3-a2-prelude.txt"), "w",
                  encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
    except Exception:  # noqa: BLE001
        pass


log("PRELUDE bundle=%s" % bundle)
for sub in ("lib", "Mod", "Ext"):
    p = os.path.join(bundle, sub)
    if os.path.isdir(p) and p not in sys.path:
        sys.path.insert(0, p)
        log("PRELUDE path+= %s" % p)

try:
    import FreeCAD
    log("PRELUDE FreeCAD import OK version=%s" % ".".join(
        str(x) for x in FreeCAD.Version()[:3]))
except Exception:  # noqa: BLE001
    log("PRELUDE FreeCAD import FAIL")
    log(traceback.format_exc())
    flush()
    raise

# Mod/<Name> directories on sys.path too: some Init.py do sibling
# imports, and TestPartApp lives in Mod/Part/.
mod_root = os.path.join(bundle, "Mod")
if os.path.isdir(mod_root):
    for name in sorted(os.listdir(mod_root)):
        p = os.path.join(mod_root, name)
        if os.path.isdir(p) and p not in sys.path:
            sys.path.append(p)

for mod in ("Part", "Sketcher", "PartDesign", "Import", "Mesh",
            "Spreadsheet", "Test"):
    init_py = os.path.join(mod_root, mod, "Init.py")
    if os.path.isfile(init_py):
        try:
            with open(init_py, "r", encoding="utf-8") as fh:
                code = fh.read()
            exec(compile(code, init_py, "exec"),
                 {"__file__": init_py, "__name__": "__main__"})
            log("PRELUDE Init.py OK %s" % mod)
        except Exception:  # noqa: BLE001
            log("PRELUDE Init.py FAIL %s" % mod)
            log(traceback.format_exc())
    else:
        log("PRELUDE Init.py MISSING %s" % mod)

try:
    log("PRELUDE import-types=%s" % (FreeCAD.getImportType(),))
except Exception:  # noqa: BLE001
    log("PRELUDE getImportType FAIL")
    log(traceback.format_exc())

log("PRELUDE-DONE")
flush()
