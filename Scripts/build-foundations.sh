#!/bin/bash
# S1 — Foundations (shell only).
#
# Real stage (Action 2): build, in order, all static for iOS arm64 with
# the Qt toolchain file, each self-verifying (lipo -info arm64 + symbol
# smoke): zlib -> FreeType -> HarfBuzz -> yaml-cpp -> Xerces-C (built-in
# transcoder, no ICU) -> Eigen (copy) -> Boost compiled libs only
# (program_options/regex/thread/date_time). Output: the deps tarball
# dist/iosdeps-foundations-$DEPS_HASH.tar.zst containing ios-prefix/.
set -euo pipefail
echo "=============================================================="
echo " STAGE S1 (foundations): SHELL ONLY — not yet implemented"
echo "=============================================================="
mkdir -p dist
{
  echo "S1 foundations is a workflow shell; the real stage lands in Action 2."
  echo "Would produce: iosdeps-foundations-${DEPS_HASH:-UNSET}.tar.zst"
} > dist/STAGE-NOT-IMPLEMENTED.txt
