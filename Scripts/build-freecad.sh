#!/bin/bash
# S7/S8 — FreeCAD itself (shell only).
#
# HARD GATE: the real stages behind this script must not run until
# spikes S3 (Python) and S4 (graphics) have both reported against
# their written kill criteria and the main chat authorises Stage 7.
#
# Real shape: phase "core" configures the pinned snapshot (first act:
# the Qt 6.9.3 configure experiment) against the unpacked ios-prefix/
# deps and builds the core libraries -> dist-core/ artifact; phase
# "workbench" builds the Phase-1 workbench set against that core;
# phase "package" assembles the .app (installed tree, iOS Info.plist
# from src/MacAppBundle, launch storyboard via ibtool), runs the
# FEBio verify step (arm64 + QIOSIntegration strings), and zips
# Payload/ -> FreeCAD-unsigned.ipa.
set -euo pipefail
PHASE="${1:-}"
echo "=============================================================="
echo " STAGE S7/S8 (FreeCAD app, phase: ${PHASE:-none}): SHELL ONLY"
echo " Stage 7 is gated on the S3 + S4 spike verdicts (hard gate)."
echo "=============================================================="
case "$PHASE" in
  core)
    mkdir -p dist-core
    echo "core phase is a workflow shell." > dist-core/STAGE-NOT-IMPLEMENTED.txt
    ;;
  workbench|package)
    mkdir -p Payload
    echo "workbench/package phase is a workflow shell; Stage 7 is gated on S3+S4 verdicts." \
      > Payload/STAGE-NOT-IMPLEMENTED.txt
    (cd Payload && zip -qry ../FreeCAD-unsigned.ipa STAGE-NOT-IMPLEMENTED.txt)
    ;;
  *)
    echo "usage: $0 core|workbench|package" >&2
    exit 1
    ;;
esac
