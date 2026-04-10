#!/bin/bash
set -euo pipefail

# harden.sh — Disable Docker Desktop auto-update and start-at-login.
#
# Requirements covered:
#   CLEAN-03: Docker Desktop auto-update is disabled to prevent config wipe
#             Sets AutoDownloadUpdates=False + DisableUpdate=True in both
#             settings files (belt-and-suspenders per research)
#   CLEAN-04: Docker Desktop "Start at login" is disabled to prevent boot-time
#             race condition with USB volume mount
#             Sets AutoStart=False in both settings files
#
# Safety notes:
#   - MUST stop Docker Desktop before modifying settings (D-07): Docker
#     overwrites settings on quit, reverting any mid-run changes
#   - Uses Python json module for safe JSON mutation (D-05, D-06, Phase 3 pattern)
#   - Includes readback verify after each write to catch partial/corrupt writes
#   - After Docker restart, re-reads both settings files to confirm keys
#     survived restart (D-08) -- belt-and-suspenders verification
#   - Key names are confirmed from live inspection (see 04-RESEARCH.md):
#       settings-store.json (PascalCase): AutoDownloadUpdates, DisableUpdate, AutoStart
#       settings.json (camelCase):        autoDownloadUpdates, disableUpdate, autoStart
#   - DO NOT use autoInstallUpdates or openAtStartup -- those keys do not exist

SETTINGS_DIR="$HOME/Library/Group Containers/group.com.docker"
SETTINGS_STORE="$SETTINGS_DIR/settings-store.json"
SETTINGS_JSON="$SETTINGS_DIR/settings.json"
TIMEOUT=120
INTERVAL=5
RESULTS_FILE="$(dirname "$0")/harden-results.txt"
PASS=0
FAIL=0

# ── Tee all output to results file ───────────────────────────────────────────

exec > >(tee "$RESULTS_FILE") 2>&1

# ── Helper functions (Phase 1/2/3 pattern) ────────────────────────────────────

harden_pass()  { echo "[ PASS ] $1"; PASS=$((PASS + 1)); }
harden_fail()  { echo "[ FAIL ] $1"; FAIL=$((FAIL + 1)); }
harden_info()  { echo "[ INFO ] $1"; }
harden_abort() {
  echo ""
  echo "ABORT: $1"
  echo "Fix the issue above, then re-run or investigate manually."
  exit 1
}

# ── Header ────────────────────────────────────────────────────────────────────

echo "Docker Desktop Hardening"
echo "========================"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""

# ── Settings files guard ──────────────────────────────────────────────────────
if [[ ! -f "$SETTINGS_STORE" ]]; then
  harden_abort "settings-store.json not found at $SETTINGS_STORE"
fi
if [[ ! -f "$SETTINGS_JSON" ]]; then
  harden_abort "settings.json not found at $SETTINGS_JSON"
fi
harden_pass "Both settings files found"

# ── D-07: Stop Docker Desktop before modifying settings ──────────────────────
# Docker Desktop overwrites settings on quit -- must stop before writing.
harden_info "Stopping Docker Desktop..."
killall "Docker Desktop"       2>/dev/null || true
killall com.docker.backend      2>/dev/null || true
killall com.docker.virtualization 2>/dev/null || true
killall com.docker.helper       2>/dev/null || true
killall com.docker.build        2>/dev/null || true
sleep 3

# Verify Docker processes are gone
RUNNING=""
RUNNING+=$(pgrep -f 'Docker Desktop'    2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.backend' 2>/dev/null || true)
if [[ -n "$RUNNING" ]]; then
  harden_abort "Docker still running after stop attempt. Stop manually and retry."
fi
harden_pass "Docker Desktop stopped"

# ── D-05 + D-06: Update settings files (CLEAN-03 + CLEAN-04) ─────────────────
# Use Python json module -- safe JSON handling, no sed fragility (Phase 3 pattern).
# Updates BOTH settings files with confirmed key names from live inspection.
harden_info "Writing hardening keys to settings files..."

PYTHON_EXIT=0
python3 - <<'PYEOF' || PYTHON_EXIT=$?
import json, sys, os

SETTINGS_DIR = os.path.expanduser("~/Library/Group Containers/group.com.docker")

# settings-store.json uses PascalCase keys (authoritative for Docker Desktop v4.35+)
# Key names confirmed by live inspection -- do NOT use autoInstallUpdates or openAtStartup
store_updates = {
    "AutoDownloadUpdates": False,   # CLEAN-03: stop background update downloads
    "DisableUpdate": True,          # CLEAN-03: belt-and-suspenders disable flag
    "AutoStart": False,             # CLEAN-04: prevent boot-time race with USB mount
}

# settings.json uses camelCase keys (companion file, both must be updated)
json_updates = {
    "autoDownloadUpdates": False,   # CLEAN-03
    "disableUpdate": True,          # CLEAN-03 belt-and-suspenders
    "autoStart": False,             # CLEAN-04
}

def update_and_verify(path, updates):
    """Update keys in a Docker Desktop settings JSON file with readback verify."""
    # Read current settings
    try:
        with open(path, 'r') as f:
            data = json.load(f)
    except FileNotFoundError as e:
        print(f"ERROR: File not found: {path}: {e}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"ERROR: Cannot parse JSON from {path}: {e}", file=sys.stderr)
        sys.exit(1)

    # Apply updates
    for k, v in updates.items():
        data[k] = v

    # Write back
    try:
        with open(path, 'w') as f:
            json.dump(data, f, indent=2)
    except IOError as e:
        print(f"ERROR: Cannot write {path}: {e}", file=sys.stderr)
        sys.exit(1)

    # Readback verify -- catch partial/truncated writes (Phase 3 D-04 pattern)
    try:
        with open(path, 'r') as f:
            check = json.load(f)
    except json.JSONDecodeError as e:
        print(f"ERROR: Readback failed (file may be corrupt) {path}: {e}", file=sys.stderr)
        sys.exit(1)

    for k, v in updates.items():
        if check.get(k) != v:
            print(
                f"ERROR: Readback mismatch in {path}: "
                f"key={k!r} got {check.get(k)!r}, expected {v!r}",
                file=sys.stderr
            )
            sys.exit(1)

update_and_verify(os.path.join(SETTINGS_DIR, "settings-store.json"), store_updates)
update_and_verify(os.path.join(SETTINGS_DIR, "settings.json"), json_updates)
print("OK")
PYEOF

if [[ $PYTHON_EXIT -ne 0 ]]; then
  harden_abort "Settings update failed -- Docker config unchanged, safe to investigate"
fi
harden_pass "CLEAN-03 + CLEAN-04: Hardening keys written to both settings files"

# ── D-07: Restart Docker Desktop ─────────────────────────────────────────────
harden_info "Starting Docker Desktop..."
open -a "Docker Desktop"

ELAPSED=0
DOCKER_READY=0

while [[ $ELAPSED -lt $TIMEOUT ]]; do
  if docker info > /dev/null 2>&1; then
    DOCKER_READY=1
    break
  fi
  printf "\r[ INFO ] Waiting for daemon... %ds/%ds" "$ELAPSED" "$TIMEOUT"
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done
printf "\n"

if [[ $DOCKER_READY -eq 0 ]]; then
  harden_abort "Docker daemon did not start within ${TIMEOUT}s"
fi
harden_pass "Docker daemon ready after ${ELAPSED}s"

# ── D-08: Post-restart readback verify ───────────────────────────────────────
# Confirms all hardening keys survived Docker Desktop startup.
# Docker Desktop may rewrite settings on startup -- this catches any revert.
harden_info "Verifying hardening keys survived Docker restart (D-08)..."

VERIFY_EXIT=0
python3 - <<'PYEOF' || VERIFY_EXIT=$?
import json, os, sys

SETTINGS_DIR = os.path.expanduser("~/Library/Group Containers/group.com.docker")

store = json.load(open(os.path.join(SETTINGS_DIR, "settings-store.json")))
jsn   = json.load(open(os.path.join(SETTINGS_DIR, "settings.json")))

errors = []

# settings-store.json checks (PascalCase)
if store.get("AutoDownloadUpdates") is not False:
    errors.append(
        f"settings-store.json AutoDownloadUpdates = "
        f"{store.get('AutoDownloadUpdates')!r} (want False)"
    )
if store.get("DisableUpdate") is not True:
    errors.append(
        f"settings-store.json DisableUpdate = "
        f"{store.get('DisableUpdate')!r} (want True)"
    )
if store.get("AutoStart") is not False:
    errors.append(
        f"settings-store.json AutoStart = "
        f"{store.get('AutoStart')!r} (want False)"
    )

# settings.json checks (camelCase)
if jsn.get("autoDownloadUpdates") is not False:
    errors.append(
        f"settings.json autoDownloadUpdates = "
        f"{jsn.get('autoDownloadUpdates')!r} (want False)"
    )
if jsn.get("disableUpdate") is not True:
    errors.append(
        f"settings.json disableUpdate = "
        f"{jsn.get('disableUpdate')!r} (want True)"
    )
if jsn.get("autoStart") is not False:
    errors.append(
        f"settings.json autoStart = "
        f"{jsn.get('autoStart')!r} (want False)"
    )

if errors:
    for e in errors:
        print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)

print("OK -- all hardening keys confirmed after restart")
PYEOF

if [[ $VERIFY_EXIT -ne 0 ]]; then
  harden_abort "Post-restart verification failed -- Docker may have reverted settings"
fi
harden_pass "D-08: Post-restart verification passed"

# ── Final migration summary ───────────────────────────────────────────────────

echo ""
echo "=== Migration Complete ==="
echo "Phase 1: Pre-flight         COMPLETE"
echo "Phase 2: Data copy          COMPLETE"
echo "Phase 3: Cutover            COMPLETE"
echo "Phase 4: Cleanup/Hardening  COMPLETE"
echo ""
echo "Docker data location: /Volumes/Unitek-B/Docker/"
echo "Internal disk freed: ~24 GB (see cleanup-results.txt for df before/after)"
echo "Auto-update: DISABLED"
echo "Start at login: DISABLED"
echo ""
echo "IMPORTANT: Docker requires /Volumes/Unitek-B/ to be mounted before starting."
echo "Always verify the volume is mounted before launching Docker Desktop."
echo "========================="

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
echo "======================================"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi

echo "Hardening complete. Migration fully done."
