# Spike S3 Phase A2 probe — runs inside the embedded interpreter of
# the A2 harness app (FreeCAD console stack: Base/App/Part/PartDesign/
# Sketcher/Import, GUI OFF, PySide OFF), on the iOS Simulator.
#
# The SAME script is the desktop reference: run it under a desktop
# FreeCAD build of the pinned weekly snapshot (FreeCADCmd
# probe_a2.py) and the VOLUME / STEP-VOLUME lines are the reference
# values the simulator run is compared against. Any numerical
# divergence is a synthesis §3 kill-criterion event (verdict DIVERGE).
#
# Markers:
#   FREECAD-IMPORT-OK / -FAIL
#   TESTPARTAPP tests=<n> failures=<n> errors=<n>
#   STEP-OPEN-OK solids=<n> STEP-VOLUME <v>
#   PARTDESIGN-OK VOLUME <v>
#   STEP-EXPORT-OK STEP-ROUNDTRIP-VOLUME <v>
#   A2-PROBE-DONE

import os
import sys
import traceback

RESULT = globals().get("S3_RESULT_PATH") or os.path.expanduser(
    "~/Documents/s3-a2-result.txt")
WORKDIR = os.path.dirname(RESULT)

lines = []


def log(s):
    lines.append(str(s))
    print(s, flush=True)


def flush():
    with open(RESULT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


try:
    import FreeCAD
    log("FREECAD-IMPORT-OK version=%s" % ".".join(
        str(x) for x in FreeCAD.Version()[:3]))
except Exception:  # noqa: BLE001
    log("FREECAD-IMPORT-FAIL")
    log(traceback.format_exc())
    flush()
    raise SystemExit(1)

import Part  # noqa: E402

# --- (1) FreeCAD's own TestPartApp suite -------------------------------
try:
    import unittest
    suite = unittest.defaultTestLoader.loadTestsFromName("TestPartApp")
    import io
    stream = io.StringIO()
    runner = unittest.TextTestRunner(stream=stream, verbosity=1)
    result = runner.run(suite)
    log("TESTPARTAPP tests=%d failures=%d errors=%d skipped=%d" % (
        result.testsRun, len(result.failures), len(result.errors),
        len(result.skipped)))
    tail = stream.getvalue().strip().splitlines()
    for line in tail[-15:]:
        log("TESTPARTAPP-OUT %s" % line)
except Exception:  # noqa: BLE001
    log("TESTPARTAPP-EXCEPTION")
    log(traceback.format_exc())

# --- (2) Open a STEP file via Init.py registration -> Import -> OCCT ---
try:
    step_in = os.path.join(WORKDIR, "s3-input.step")
    box = Part.makeBox(30.0, 20.0, 10.0)  # exact volume 6000
    box.exportStep(step_in)
    import Import
    doc = FreeCAD.newDocument("S3StepOpen")
    Import.insert(step_in, doc.Name)
    doc.recompute()
    solids = []
    for obj in doc.Objects:
        if hasattr(obj, "Shape") and obj.Shape is not None:
            solids.extend(obj.Shape.Solids)
    vol = sum(s.Volume for s in solids)
    log("STEP-OPEN-OK solids=%d" % len(solids))
    log("STEP-VOLUME %.6f" % vol)
    FreeCAD.closeDocument(doc.Name)
except Exception:  # noqa: BLE001
    log("STEP-OPEN-FAIL")
    log(traceback.format_exc())

# --- (3) PartDesign body, programmatic + recompute ---------------------
pad = None
doc = None
try:
    doc = FreeCAD.newDocument("S3Body")
    body = doc.addObject("PartDesign::Body", "Body")
    sketch = body.newObject("Sketcher::SketchObject", "Sketch")
    xy_plane = None
    for feat in body.Origin.OriginFeatures:
        if getattr(feat, "Role", "") == "XY_Plane":
            xy_plane = feat
            break
    sketch.Support = (xy_plane, [""])
    sketch.MapMode = "FlatFace"
    sketch.addGeometry(
        Part.Circle(FreeCAD.Vector(0, 0, 0), FreeCAD.Vector(0, 0, 1),
                    10.0), False)
    doc.recompute()
    pad = body.newObject("PartDesign::Pad", "Pad")
    pad.Profile = sketch
    pad.Length = 20.0
    doc.recompute()
    vol = pad.Shape.Volume  # analytic: pi * 10^2 * 20 = 6283.185307...
    log("PARTDESIGN-OK VOLUME %.6f" % vol)
    log("PARTDESIGN-ANALYTIC %.6f" % (3.141592653589793 * 100.0 * 20.0))
except Exception:  # noqa: BLE001
    log("PARTDESIGN-FAIL")
    log(traceback.format_exc())

# --- (4) Export STEP and round-trip the volume --------------------------
try:
    if pad is not None and doc is not None:
        step_out = os.path.join(WORKDIR, "s3-body.step")
        pad.Shape.exportStep(step_out)
        log("STEP-EXPORT-OK bytes=%d" % os.path.getsize(step_out))
        back = Part.Shape()
        back.read(step_out)
        log("STEP-ROUNDTRIP-VOLUME %.6f" % back.Volume)
except Exception:  # noqa: BLE001
    log("STEP-EXPORT-FAIL")
    log(traceback.format_exc())

log("A2-PROBE-DONE")
flush()
