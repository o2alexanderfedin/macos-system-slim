#!/bin/bash
set -euo pipefail

# Pre-flight validation script for Docker data migration to external volume.
# Gates all subsequent migration phases — must pass before moving any data.
# Runs checks in fail-fast order: cheapest and highest-risk first.
# D-08: Hard stop on ANY failure — no "warn and continue" mode.

DOCKER_SETTINGS_DIR="$HOME/Library/Group Containers/group.com.docker"
DOCKER_RAW_PATH="$HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
TARGET_DIR="/Volumes/Unitek-B/Docker"
PASS=0
FAIL=0

preflight_pass() { echo "[ PASS ] $1"; ((PASS++)); }
preflight_fail() { echo "[ FAIL ] $1"; ((FAIL++)); }
preflight_info() { echo "[ INFO ] $1"; }
preflight_abort() {
  echo ""
  echo "ABORT: $1"
  echo "Fix the issue above, then re-run pre-flight."
  exit 1
}

echo "Pre-flight Check Results"
echo "========================"

# ── PREFLT-01: Docker processes (D-01, D-02) ─────────────────────
# Graceful quit first, then force-kill all Docker processes.
# killall exits non-zero when no process found (Pitfall 3) — use || true.
osascript -e 'quit app "Docker Desktop"' 2>/dev/null || true
sleep 3

killall -9 'Docker Desktop'              2>/dev/null || true
killall -9 'com.docker.backend'          2>/dev/null || true
killall -9 'com.docker.virtualization'   2>/dev/null || true
killall -9 'com.docker.helper'           2>/dev/null || true
killall -9 'com.docker.build'            2>/dev/null || true

# pgrep is authoritative (Pitfall 2 — do not use launchctl).
RUNNING=""
RUNNING+=$(pgrep -f 'Docker Desktop'          2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.backend'      2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.virtualization' 2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.helper'       2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.build'        2>/dev/null || true)

if [[ -n "$RUNNING" ]]; then
  preflight_fail "PREFLT-01: Docker processes still running (PIDs: $RUNNING)"
  preflight_abort "Cannot proceed while Docker processes hold Docker.raw open (D-02)"
else
  preflight_pass "PREFLT-01: Docker processes stopped"
fi

# ── PREFLT-02: APFS format (D-06) ────────────────────────────────
# Parse Type (Bundle) field — the authoritative filesystem type field.
# Do NOT grep for "APFS" anywhere else (Pitfall 4).
FSTYPE=$(diskutil info /Volumes/Unitek-B 2>/dev/null \
  | awk -F': ' '/Type \(Bundle\)/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')

if [[ "$FSTYPE" == "apfs" ]]; then
  preflight_pass "PREFLT-02: /Volumes/Unitek-B is APFS format"
else
  preflight_fail "PREFLT-02: /Volumes/Unitek-B is '${FSTYPE}', not APFS"
  preflight_abort "External volume must be APFS for Docker Desktop compatibility (D-06)"
fi

# ── PREFLT-03: Free space >= 2x Docker.raw on-disk (D-07) ────────
# Use du -sk for on-disk size (respects APFS sparse files — Pitfall 1).
# Do NOT use diskSizeMiB from settings files.
DOCKER_RAW_KB=$(du -sk "$DOCKER_RAW_PATH" | awk '{print $1}')
REQUIRED_KB=$((DOCKER_RAW_KB * 2))
AVAIL_KB=$(df -k /Volumes/Unitek-B | awk 'NR==2 {print $4}')
DOCKER_RAW_GB=$(echo "scale=1; $DOCKER_RAW_KB / 1048576" | bc)
REQUIRED_GB=$(echo "scale=1; $REQUIRED_KB / 1048576" | bc)
AVAIL_GB=$(echo "scale=0; $AVAIL_KB / 1048576" | bc)

if [[ $AVAIL_KB -ge $REQUIRED_KB ]]; then
  preflight_pass "PREFLT-03: Free space ${AVAIL_GB} GB >= required ${REQUIRED_GB} GB (2x Docker.raw on-disk ${DOCKER_RAW_GB} GB)"
else
  preflight_fail "PREFLT-03: Free space ${AVAIL_GB} GB < required ${REQUIRED_GB} GB (2x Docker.raw on-disk ${DOCKER_RAW_GB} GB)"
  preflight_abort "Insufficient space on /Volumes/Unitek-B (D-07)"
fi

# ── PREFLT-05: Target directory writable ─────────────────────────
# Create if absent, then write-test to confirm permissions.
[[ -d "$TARGET_DIR" ]] || mkdir -p "$TARGET_DIR"
TEST_FILE="$TARGET_DIR/.preflight_write_test"

if touch "$TEST_FILE" 2>/dev/null && rm "$TEST_FILE" 2>/dev/null; then
  preflight_pass "PREFLT-05: $TARGET_DIR exists and is writable"
else
  preflight_fail "PREFLT-05: $TARGET_DIR is not writable"
  preflight_abort "Cannot write to target directory (PREFLT-05)"
fi

# ── PREFLT-04: Backup both settings files (D-03, D-04) ───────────
# Back up in-place with .bak suffix (Pitfall 5 — same directory only).
# D-03: Back up BOTH files even though settings-store.json is authoritative.
cp "$DOCKER_SETTINGS_DIR/settings-store.json" \
   "$DOCKER_SETTINGS_DIR/settings-store.json.bak"
cp "$DOCKER_SETTINGS_DIR/settings.json" \
   "$DOCKER_SETTINGS_DIR/settings.json.bak"

if [[ -f "$DOCKER_SETTINGS_DIR/settings-store.json.bak" \
   && -f "$DOCKER_SETTINGS_DIR/settings.json.bak" ]]; then
  preflight_pass "PREFLT-04: Backups created: settings-store.json.bak, settings.json.bak"
else
  preflight_fail "PREFLT-04: Backup creation failed"
  preflight_abort "Cannot proceed without settings backup (D-03)"
fi

# ── D-05 Bonus: Virtualization backend check ─────────────────────
# Docker VMM has external USB path bug — Apple VF must be active.
USE_VF=$(python3 -c "
import json
with open('$DOCKER_SETTINGS_DIR/settings-store.json') as f:
    d = json.load(f)
print(d.get('UseVirtualizationFramework', False))
")

if [[ "$USE_VF" == "True" ]]; then
  preflight_info "Backend: Apple Virtualization Framework confirmed (not Docker VMM)"
else
  preflight_fail "D-05: Docker VMM backend detected — switch to Apple Virtualization Framework before migrating"
  preflight_abort "Docker VMM has a bug with external USB volumes (/host_mnt path prepend)"
fi

# ── D-05 Bonus: diskSizeMiB discrepancy resolution (Pitfall 6) ───
# Logical size from ls -la; on-disk size already captured as DOCKER_RAW_GB.
# settings.json 61035 MiB is stale from an old disk limit configuration.
LOGICAL_GB=$(echo "scale=1; $(ls -la "$DOCKER_RAW_PATH" | awk '{print $5}') / 1073741824" | bc)
preflight_info "Docker.raw logical: ${LOGICAL_GB} GB | on-disk (sparse): ${DOCKER_RAW_GB} GB | diskSizeMiB discrepancy resolved (settings.json 61035 MiB is stale; actual on-disk is ${DOCKER_RAW_GB} GB)"

# ── Summary ──────────────────────────────────────────────────────
echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "All $PASS pre-flight checks passed. Safe to proceed to Phase 2."
else
  echo "$FAIL check(s) failed. Fix all failures before proceeding."
  exit 1
fi
