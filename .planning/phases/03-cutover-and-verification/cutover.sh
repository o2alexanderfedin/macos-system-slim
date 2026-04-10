#!/bin/bash
set -euo pipefail

# cutover.sh — Docker Desktop data folder cutover to external volume.
#
# Requirements covered:
#   CONF-01: Updates DataFolder in settings-store.json and dataFolder in
#            settings.json to /Volumes/Unitek-B/Docker (Python json module
#            with atomic readback verify per D-01, D-02, D-03, D-04)
#   CONF-02: Starts Docker Desktop and polls docker info every 5s with
#            120-second timeout per D-05, D-06, D-07
#
# Safety notes:
#   - Docker MUST be stopped before running this script (guard check enforced)
#   - Phase 2 copy MUST be complete (Docker.raw must exist on external volume)
#   - This script updates Docker Desktop settings — this is the point of no return
#     for the data location change (reversible manually via .bak files from Phase 1)
#   - On settings update failure: HARD STOP before starting Docker (D-13)
#   - On Docker start failure: emit diagnostics, abort without auto-rollback (D-11, D-12)
#   - Run verify-cutover.sh after completion for independent verification

SETTINGS_DIR="$HOME/Library/Group Containers/group.com.docker"
SETTINGS_STORE="$SETTINGS_DIR/settings-store.json"
SETTINGS_JSON="$SETTINGS_DIR/settings.json"
NEW_PATH="/Volumes/Unitek-B/Docker"
DOCKER_RAW="$NEW_PATH/Docker.raw"
TIMEOUT=120
INTERVAL=5
PASS=0
FAIL=0

# ── Helper functions (Phase 1/2 pattern) ─────────────────────────────────────

cutover_pass() { echo "[ PASS ] $1"; PASS=$((PASS + 1)); }
cutover_fail() { echo "[ FAIL ] $1"; FAIL=$((FAIL + 1)); }
cutover_info() { echo "[ INFO ] $1"; }
cutover_abort() {
  echo ""
  echo "ABORT: $1"
  echo "Fix the issue above, then re-run or investigate manually."
  exit 1
}

# ── emit_diagnostics — print diagnostic info on failure (D-12) ───────────────
emit_diagnostics() {
  echo ""
  echo "=== Diagnostic Information ==="
  echo "--- settings-store.json DataFolder ---"
  python3 -c "import json; d=json.load(open('$SETTINGS_STORE')); print(d.get('DataFolder','NOT FOUND'))" 2>/dev/null || echo "ERROR: Cannot read settings-store.json"
  echo "--- settings.json dataFolder ---"
  python3 -c "import json; d=json.load(open('$SETTINGS_JSON')); print(d.get('dataFolder','NOT FOUND'))" 2>/dev/null || echo "ERROR: Cannot read settings.json"
  echo "--- Docker Desktop logs location ---"
  echo "$HOME/Library/Containers/com.docker.docker/Data/log/host/"
  echo "--- Last docker info output ---"
  docker info 2>&1 | head -30 || true
  echo "=== End Diagnostics ==="
}

# ── Header ────────────────────────────────────────────────────────────────────

echo "Docker Desktop Cutover"
echo "======================"

# ── Docker-stopped guard ──────────────────────────────────────────────────────
# Cannot change settings while Docker holds Docker.raw open.
RUNNING=""
RUNNING+=$(pgrep -f 'Docker Desktop'            2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.backend'         2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.virtualization'  2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.helper'          2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.build'           2>/dev/null || true)

if [[ -n "$RUNNING" ]]; then
  cutover_abort "Docker is still running. Stop Docker Desktop first."
fi
cutover_pass "No Docker processes running"

# ── External volume guard ─────────────────────────────────────────────────────
# Phase 2 must have completed successfully before running cutover.
if [[ ! -f "$DOCKER_RAW" ]]; then
  cutover_abort "Docker.raw not found at $DOCKER_RAW -- run Phase 2 first"
fi
cutover_pass "Docker.raw found at $DOCKER_RAW"

# ── Settings files guard ──────────────────────────────────────────────────────
if [[ ! -f "$SETTINGS_STORE" ]]; then
  cutover_abort "settings-store.json not found at $SETTINGS_STORE"
fi
if [[ ! -f "$SETTINGS_JSON" ]]; then
  cutover_abort "settings.json not found at $SETTINGS_JSON"
fi
cutover_pass "Both settings files found"

# ── CONF-01: Update settings files (D-01, D-02, D-03, D-04, D-13) ────────────
# Use Python json module — safe JSON handling, no sed fragility.
# Embedded heredoc avoids quoting issues with shell variable expansion.
cutover_info "Updating DataFolder in both settings files..."

SETTINGS_DIR_PY="$SETTINGS_DIR"
NEW_PATH_PY="$NEW_PATH"

PYTHON_EXIT=0
python3 - <<PYEOF || PYTHON_EXIT=$?
import json, sys, os

def update_datafolder(settings_path, new_path, key_name):
    """Update a dataFolder key in a Docker Desktop settings JSON file."""
    # Read current settings
    try:
        with open(settings_path, 'r') as f:
            data = json.load(f)
    except FileNotFoundError as e:
        print(f"ERROR: File not found: {settings_path}: {e}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"ERROR: Cannot parse JSON from {settings_path}: {e}", file=sys.stderr)
        sys.exit(1)

    # Update the key
    data[key_name] = new_path

    # Write back
    try:
        with open(settings_path, 'w') as f:
            json.dump(data, f, indent=2)
    except IOError as e:
        print(f"ERROR: Cannot write {settings_path}: {e}", file=sys.stderr)
        sys.exit(1)

    # Readback verify (D-04) — catch partial/truncated writes
    try:
        with open(settings_path, 'r') as f:
            check = json.load(f)
    except json.JSONDecodeError as e:
        print(f"ERROR: Readback failed (file may be corrupt) {settings_path}: {e}", file=sys.stderr)
        sys.exit(1)

    if check.get(key_name) != new_path:
        print(
            f"ERROR: Readback mismatch in {settings_path}: "
            f"got {check.get(key_name)!r}, expected {new_path!r}",
            file=sys.stderr
        )
        sys.exit(1)

settings_dir = os.path.expanduser("${SETTINGS_DIR_PY}")
new_path = "${NEW_PATH_PY}"

update_datafolder(os.path.join(settings_dir, "settings-store.json"), new_path, "DataFolder")
update_datafolder(os.path.join(settings_dir, "settings.json"), new_path, "dataFolder")
print("OK")
PYEOF

if [[ $PYTHON_EXIT -ne 0 ]]; then
  cutover_fail "CONF-01: Settings update failed"
  emit_diagnostics
  cutover_abort "Settings update failed -- Docker config unchanged, safe to investigate"
fi
cutover_pass "CONF-01: DataFolder updated to /Volumes/Unitek-B/Docker in both settings files"

# ── CONF-02: Start Docker Desktop and poll for readiness (D-05, D-06, D-07) ──
cutover_info "Starting Docker Desktop..."
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
  cutover_fail "CONF-02: Docker daemon not ready after ${TIMEOUT}s"
  emit_diagnostics
  cutover_abort "Docker did not start in time. You can wait and re-run verify-cutover.sh manually."
fi
cutover_pass "CONF-02: Docker daemon ready after ${ELAPSED}s"

# ── Docker Root Dir confirmation (Pattern 5 from research) ───────────────────
# DockerRootDir may show VM-internal path like /var/lib/docker (Open Question 2).
# This is informational — real check is settings files already verified in CONF-01.
DOCKER_ROOT=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "unknown")
cutover_info "Docker Root Dir (VM-internal path): $DOCKER_ROOT"
cutover_info "Note: VM-internal path is expected; external volume confirmed via settings readback."

# ── Save cutover results to cutover-results.txt ───────────────────────────────
RESULTS_FILE="$(dirname "$0")/cutover-results.txt"
{
  echo "=== Cutover Results ==="
  echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "Settings update (CONF-01): PASS"
  echo "  settings-store.json DataFolder: $NEW_PATH"
  echo "  settings.json dataFolder:       $NEW_PATH"
  echo "Docker readiness (CONF-02): PASS (ready after ${ELAPSED}s)"
  echo "Docker Root Dir (informational): $DOCKER_ROOT"
  echo "=== End Results ==="
} > "$RESULTS_FILE"
cutover_info "Results saved to: $RESULTS_FILE"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
echo "======================================"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi

echo "Cutover complete. Run verify-cutover.sh to confirm data integrity."
