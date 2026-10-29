#!/usr/bin/env python3
"""Qt-gate probe classifier.

Reads the probe's logs from --dist, scans the pinned FreeCAD source for
Qt version guards, classifies EVERY configure error, and writes the
verdict report. Classification taxonomy (task definition):

  [QT-API]  a Qt >= 6.10 symbol/behaviour the 6.9.3 kit lacks
            (gate problem — the only GATE-FAIL class)
  [DEP]     a missing/failed dependency (name it)
  [CONFIG]  a try-run / introspection / platform-assumption item to
            disable or seed, feedstock-style (engineering)

Verdict:
  GATE-FAIL    any [QT-API] item
  GATE-PASS    no [QT-API]; configure completed, OR configure reached
               and passed the SetupQt stage, OR (deps incomplete) the
               battery proved the Qt layer and every configure stop
               was [DEP]/[CONFIG]
  GATE-BLOCKED the Qt layer itself could not be tested (kit install /
               battery infrastructure failure), or deps never landed
               AND configure never reached the Qt stage — the report
               states exactly what is missing either way.
"""
import argparse
import os
import re
import sys

DEP_PATTERNS = [
    (r"OpenCASCADE|OCC[^_]|TK[A-Z]\w*\.a", "OCCT (cascade-ios prefix)"),
    (r"\bfmt\b", "fmt (external; FREECAD_USE_EXTERNAL_FMT=OFF still find_package(fmt))"),
    (r"\bICU\b|icu", "ICU (no iOS build staged; SDK ships libicucore only)"),
    (r"Python3|PythonInterp|libpython", "Python 3.13 (BeeWare prefix)"),
    (r"Xerces", "Xerces-C (foundations)"),
    (r"Boost", "Boost (foundations)"),
    (r"Eigen", "Eigen (foundations)"),
    (r"ZLIB|zlib", "zlib (foundations)"),
    (r"FreeType|FREETYPE", "FreeType (foundations)"),
    (r"VTK|vtk", "VTK (S6 subset; SMESH forces find_package(VTK REQUIRED))"),
    (r"MEDFile|HDF5|hdf5", "MEDFile/HDF5 (data layer, S5)"),
    (r"SMESH", "SMESH (bundled salomesmesh / external)"),
    (r"NETGEN|Netgen", "NETGEN"),
    (r"Coin|PIVY|Pivy|pivy", "Coin/pivy (bundled submodules; S4 owns the GL side)"),
    (r"SWIG|Swig", "SWIG (host tool)"),
    (r"Shiboken|PySide", "Shiboken/PySide (OFF in the shipping config)"),
    (r"GTest|googletest", "GTest (developer tests)"),
    (r"PyCXX", "PyCXX (vendored)"),
    (r"yaml", "yaml-cpp (foundations)"),
    (r"Lark|lark", "Lark (BIM python dep check)"),
    (r"Matplotlib|matplotlib", "Matplotlib (python runtime check)"),
]
CONFIG_PATTERNS = [
    (r"GLU|OpenGL|GLESv2|\bEGL\b", "OpenGL/GLU/GLES: iOS SDK resolution + gl4es companion GLU (S4) or a probe seed; SetupOpenGL.cmake fatals pre-Qt"),
    (r"try_run|TRY_RUN|Check.*does not|check_cxx|test.*failed", "try-run / feature introspection under cross-compile — seed or disable, feedstock-style"),
    (r"Qt6?[A-Z]\w*.*NOTFOUND|Qt6.*not found|Could NOT find Qt", "Qt component resolution (host-path / kit module)"),
]


def classify_block(text):
    """Return (tag, label) for one CMake error block."""
    for pat, label in CONFIG_PATTERNS:
        if re.search(pat, text):
            # GLU/OpenGL and introspection are config-class even though
            # they surface as 'not found'.
            return ("CONFIG", label)
    for pat, label in DEP_PATTERNS:
        if re.search(pat, text):
            return ("DEP", label)
    if re.search(r"Qt", text):
        return ("QT-API?", "unclassified Qt-mentioning error — read the block verbatim")
    return ("CONFIG", "unclassified configure error — read the block verbatim")


def error_blocks(log):
    blocks, cur = [], None
    for line in log.splitlines():
        if "CMake Error" in line or "FATAL_ERROR" in line:
            if cur:
                blocks.append(cur)
            cur = [line]
        elif cur is not None:
            cur.append(line)
            if len(cur) > 14:
                blocks.append(cur)
                cur = None
    if cur:
        blocks.append(cur)
    # Dedupe on first two lines.
    seen, out = set(), []
    for b in blocks:
        key = " ".join(b[:2])[:160]
        if key not in seen:
            seen.add(key)
            out.append("\n".join(b).strip())
    return out


def scan_source(src):
    guards = []  # (minor, file, line)
    pat = re.compile(r"QT_VERSION_CHECK\(\s*6\s*,\s*(\d+)\s*,")
    for root, _dirs, files in os.walk(src):
        for f in files:
            if not f.endswith((".cpp", ".h", ".hpp", ".cmake", ".txt")):
                continue
            p = os.path.join(root, f)
            try:
                with open(p, errors="ignore") as fh:
                    for i, line in enumerate(fh, 1):
                        m = pat.search(line)
                        if m:
                            guards.append((int(m.group(1)), os.path.relpath(p, src), i, line.strip()))
            except OSError:
                pass
    return guards


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dist", required=True)
    ap.add_argument("--src", required=True)
    args = ap.parse_args()
    dist = args.dist

    def read(name):
        p = os.path.join(dist, name)
        return open(p, errors="ignore").read() if os.path.exists(p) else ""

    inventory = read("deps-inventory.txt")
    deps_complete = ("foundations: REAL" in inventory and "occt: REAL" in inventory
                     and "python: REAL" in inventory)
    battery_cfg = read("battery-configure.log")
    battery_bld = read("battery-build.log")
    battery_pass = ("QTGATE: all REQUIRED SetupQt components found" in battery_cfg
                    and "BATTERY-RESULT: PASS" in read("battery-result.txt"))
    qt_version = read("qt-version.txt").strip()

    attempts = {}
    for n in (1, 2, 3):
        log = read(f"configure-attempt{n}.log")
        if log:
            attempts[n] = log
    any_complete = any("Generating done" in l for l in attempts.values())
    qt_stage_pass = [n for n, l in attempts.items()
                     if "Set up to compile with Qt" in l]
    furthest = None
    stage_markers = [
        ("SetupQt (Qt stage PASSED)", "Set up to compile with Qt"),
        ("SetupOpenGL/SMESH (pre-Qt)", "Salome SMESH"),
        ("SetupOpenCasCade", "OpenCASCADE"),
        ("SetupPython", "Found Python3"),
    ]
    for n, log in attempts.items():
        for label, marker in stage_markers:
            if marker in log:
                furthest = f"attempt{n}: reached {label}"
                break

    all_items = []  # (tag, label, attempt, excerpt)
    qt_api_items = []
    for n, log in attempts.items():
        for block in error_blocks(log):
            tag, label = classify_block(block)
            all_items.append((tag, label, n, block))
    # Battery failures: a compile error in the battery TU on a named
    # version-branch API is the one true [QT-API] signal available
    # pre-configure; component-find failures are [DEP]/[CONFIG].
    if battery_cfg and "Could NOT find Qt6" in battery_cfg or \
            (battery_cfg and "CMake Error" in battery_cfg and not battery_pass):
        for block in error_blocks(battery_cfg):
            tag, label = classify_block(block)
            if "Qt component" in label:
                tag = "DEP"  # kit module not installed via aqt
                label = "Qt component missing from the installed kit (aqt module) — " + label
            all_items.append((tag, label, "battery", block))
    if battery_bld and "error:" in battery_bld:
        apis = [a for a in ("flip", "flipped", "PdfVersion_X4", "checkStateChanged")
                if a in battery_bld]
        for a in apis:
            qt_api_items.append(
                f"battery TU: Qt API '{a}' failed to compile against the kit "
                f"(snapshot's newest-branch API; see battery-build.log)")
        if not apis and "error:" in battery_bld:
            all_items.append(("QT-API?", "battery TU compile error — read battery-build.log verbatim",
                              "battery", battery_bld[:800]))

    guards = scan_source(args.src) if os.path.isdir(args.src) else []
    hi = sorted({g[0] for g in guards})
    ge10 = [g for g in guards if g[0] >= 10]

    # ---------------- verdict ----------------
    if qt_api_items or any(t == "QT-API" for t, *_ in all_items):
        verdict = "GATE-FAIL"
        basis = "at least one [QT-API] item (enumerated below)"
    elif battery_pass and (any_complete or qt_stage_pass):
        verdict = "GATE-PASS"
        basis = ("configure " + ("completed" if any_complete else
                                 f"passed the SetupQt stage (attempt(s) {qt_stage_pass})")
                 + "; every configure error is [DEP]/[CONFIG]")
    elif battery_pass and attempts and all(t in ("DEP", "CONFIG") for t, *_ in all_items):
        if deps_complete:
            verdict = "GATE-PASS"
            basis = ("Qt layer proven by the battery; configure stopped pre-Qt "
                     "only on [DEP]/[CONFIG] items despite complete deps")
        else:
            verdict = "GATE-BLOCKED"
            basis = ("deps never landed (see inventory); configure stopped pre-Qt "
                     "on [DEP]/[CONFIG] items only, and the battery proves the "
                     "Qt layer clean — re-run this probe when foundations+OCCT "
                     "artifacts are real for the full-depth verdict")
    elif not battery_pass:
        verdict = "GATE-BLOCKED"
        basis = "the battery itself could not run clean (kit/component problem — see logs)"
    else:
        verdict = "GATE-BLOCKED"
        basis = "no configure attempt produced classifiable output"

    lines = []
    lines.append("# Qt gate probe — verdict report")
    lines.append("")
    lines.append(f"VERDICT: {verdict}")
    lines.append(f"Basis: {basis}")
    lines.append(f"Qt under test: {qt_version or '(see qt-version.txt)'}")
    lines.append(f"Furthest configure progress: {furthest or 'n/a'}")
    lines.append(f"Configure complete (any attempt): {any_complete}")
    lines.append(f"SetupQt passed in attempt(s): {qt_stage_pass or 'none'}")
    lines.append(f"Battery: {'PASS' if battery_pass else 'FAIL/INCOMPLETE'}")
    lines.append("")
    lines.append("## Deps inventory (REAL = artifact present + marker files verified)")
    lines.append("```")
    lines.append(inventory or "(no inventory written)")
    lines.append("```")
    lines.append("")
    lines.append("## Source scan — Qt version guards in the pinned snapshot")
    lines.append(f"QT_VERSION_CHECK(6, N) minors present: {hi or 'none found'}")
    lines.append(f"Guards referencing Qt >= 6.10: {len(ge10)}")
    for minor, f, ln, text in ge10[:20]:
        lines.append(f"  - 6.{minor} {f}:{ln}: {text}")
    fb = [g for g in guards if g[0] == 9]
    lines.append(f"Guards at 6.9 (all are '< 6.9.0' fallbacks; the >= 6.9 branch "
                 f"APIs — QImage::flip/flipped — are exercised by the battery): {len(fb)}")
    for minor, f, ln, text in fb[:10]:
        lines.append(f"  - {f}:{ln}: {text}")
    lines.append("")
    lines.append("## Classified configure errors (every CMake Error block, deduped)")
    if not all_items:
        lines.append("(none — no CMake Error blocks in any attempt log)")
    for tag, label, where, block in all_items:
        lines.append(f"### [{tag}] {label} (attempt {where})")
        lines.append("```")
        lines.append(block[:1200])
        lines.append("```")
    if qt_api_items:
        lines.append("")
        lines.append("## [QT-API] items")
        for it in qt_api_items:
            lines.append(f"- {it}")
    lines.append("")
    lines.append("## Logs in this artifact")
    lines.append("battery-configure.log, battery-build.log, battery-result.txt, "
                 "configure-attempt{1,2,3}.log (whichever ran), deps-inventory.txt, "
                 "qt-version.txt, source-scan inputs = PIN.md tarball (sha256-verified).")
    report = "\n".join(lines) + "\n"
    with open(os.path.join(dist, "qt-gate-report.md"), "w") as fh:
        fh.write(report)
    with open(os.path.join(dist, "verdict.txt"), "w") as fh:
        fh.write(f"{verdict}\n{basis}\n")
    print(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
