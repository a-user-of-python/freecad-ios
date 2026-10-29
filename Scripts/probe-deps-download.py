#!/usr/bin/env python3
"""Qt-gate probe: poll for / download REAL deps artifacts via the API.

The A2 driver gates on tarballs downloaded by its workflow; this probe
additionally polls (bounded) because foundations/OCCT land on their own
agents' schedules. An artifact counts as REAL only above a size floor:
the deps-data/deps-vtk workflows currently upload ~300-byte shell
tarballs, and a shell must never satisfy the gate.

Usage: probe-deps-download.py --outdir DIR --poll-minutes N
Env:   GH_TOKEN (workflow: secrets.GITHUB_TOKEN)
Writes the downloaded *.tar.zst files into --outdir and prints one
"DEPS <kind> REAL|MISSING ..." line per kind to stdout.
"""
import argparse
import io
import json
import os
import sys
import time
import urllib.request
import urllib.error
import zipfile

REPO = "a-user-of-python/freecad-ios"
API = "https://api.github.com"

# kind -> (workflow-name substring, artifact-name prefix, min bytes)
KINDS = {
    "foundations": ("Foundations", "iosdeps-foundations-", 1_000_000),
    "occt": ("OCCT", "iosdeps-occt-", 5_000_000),
    "python": ("Python 3.13", "iosdeps-python-", 10_000_000),
}


def call(path, raw=False):
    req = urllib.request.Request(API + path, headers={
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "Authorization": f"Bearer {os.environ['GH_TOKEN']}",
    })
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            body = resp.read()
            return resp.status, (body if raw else json.loads(body or b"{}"))
    except urllib.error.HTTPError as e:
        if e.code in (301, 302, 303, 307, 308):
            loc = e.headers["Location"]
            req2 = urllib.request.Request(loc)  # no auth on the signed URL
            with urllib.request.urlopen(req2, timeout=300) as resp:
                return resp.status, resp.read()
        body = e.read()
        try:
            return e.code, (body if raw else json.loads(body or b"{}"))
        except Exception:
            return e.code, {}


def find_artifact(kind):
    """Newest non-expired REAL artifact for kind, or None."""
    _, _, min_bytes = KINDS[kind]
    s, runs = call(f"/repos/{REPO}/actions/runs?per_page=50")
    if s != 200:
        return None
    needle = KINDS[kind][0]
    for run in runs.get("workflow_runs", []):
        if needle not in run.get("name", ""):
            continue
        if run.get("status") != "completed" or run.get("conclusion") != "success":
            continue
        s2, arts = call(f"/repos/{REPO}/actions/runs/{run['id']}/artifacts")
        if s2 != 200:
            continue
        for art in arts.get("artifacts", []):
            if art["name"].startswith(KINDS[kind][1]) and not art["expired"] \
                    and art["size_in_bytes"] >= min_bytes:
                return art
    return None


def download(art, outdir):
    s, blob = call(f"/repos/{REPO}/actions/artifacts/{art['id']}/zip", raw=True)
    if s != 200 or not isinstance(blob, bytes):
        print(f"download failed for {art['name']}: HTTP {s}", file=sys.stderr)
        return False
    got = False
    with zipfile.ZipFile(io.BytesIO(blob)) as zf:
        for name in zf.namelist():
            if name.endswith(".tar.zst"):
                data = zf.read(name)
                with open(os.path.join(outdir, os.path.basename(name)), "wb") as fh:
                    fh.write(data)
                print(f"downloaded {os.path.basename(name)} ({len(data)} bytes)")
                got = True
    return got


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--poll-minutes", type=int, default=0)
    args = ap.parse_args()
    os.makedirs(args.outdir, exist_ok=True)
    if "GH_TOKEN" not in os.environ:
        print("DEPS poll skipped: GH_TOKEN not set")
        for kind in KINDS:
            print(f"DEPS {kind} UNKNOWN (no token)")
        return 0
    deadline = time.time() + args.poll_minutes * 60
    state = {}
    while True:
        for kind in KINDS:
            if state.get(kind):
                continue
            # Already on disk (workflow input download)? Count by name.
            have = [f for f in os.listdir(args.outdir)
                    if f.startswith(KINDS[kind][1]) and f.endswith(".tar.zst")
                    and os.path.getsize(os.path.join(args.outdir, f)) >= KINDS[kind][2] // 20]
            if have:
                state[kind] = "REAL (pre-downloaded)"
                continue
            art = find_artifact(kind)
            if art and download(art, args.outdir):
                state[kind] = f"REAL (run artifact {art['name']}, {art['size_in_bytes']} B)"
        if len(state) == len(KINDS) or time.time() >= deadline:
            break
        print(f"DEPS poll: waiting on {[k for k in KINDS if k not in state]} "
              f"({int(deadline - time.time())}s left)")
        time.sleep(180)
    for kind in KINDS:
        print(f"DEPS {kind} {state.get(kind, 'MISSING')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
