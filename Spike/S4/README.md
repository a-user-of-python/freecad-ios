# Spike S4 — graphics (gl4es → Coin → QuarterWidget)

Verdict criteria: `00-synthesis.md` §3 row S4 + §6 risk 1; tier definitions
and the gl4es recipe: research front 02 (`02-graphics.md` §4, §10).

- **Tier 0** — gl4es static iOS build per COMPILE.md's iOS recipe
  (`ios-cmake`, `NOX11=ON NOEGL=ON STATICLIB=ON`, GLES2 backend via
  `DEFAULT_ES=2`), one `QOpenGLWidget`, `initialize_gl4es()` after Qt's
  EAGL context is current, one lit fixed-function triangle, `glReadPixels`
  readback with in-app shading assertions. Runs in the CI iOS Simulator
  and builds for device arm64.
  *Kill: gl4es cannot work on a Qt-owned EAGL context → one investigation
  of context ownership (our own EAGL context); still blocked → KILL.*
- **Tier 1** — unmodified Coin 4.0.10 (coin3d GitHub release) + companion
  GLU (Mesa GLU 9.0.3 sources) against gl4es; FreeCAD's vendored
  QuarterWidget from the pinned weekly-2026.09.16 tarball
  (sha256 `1fba830d…`, `src/Gui/Quarter/`) with its
  CompatibilityProfile + DeprecatedFunctions format request intact,
  rendering HelloCone (SoCone) with orbit wired to Quarter's navigation.
  Simulator screenshot + pixel statistics vs an independent software
  reference render of the same scene (`tools/cone_reference.py`).
  *Kill: systemic corruption (lighting/geometry wrong everywhere) →
  Path B disproven.*

Scripts: `Scripts/build-s4-tier0.sh`, `Scripts/build-s4-tier1.sh`
(shared helpers in `Scripts/build-s4-lib.sh`).
Workflow: `.github/workflows/spike-s4.yml` (workflow_dispatch, standard
`macos-26` runners only). All runtime evidence is SIMULATOR unless a
file says otherwise — nothing here is device-verified.
