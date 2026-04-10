#!/bin/bash
set -euo pipefail

# Independent verification script for Docker data migration pre-flight.
# Confirms pre-flight results AFTER preflight.sh has run — read-only, no mutations.
#
# Usage:
#   ./verify-preflight.sh           # Quick verify (checks 1-5)
#   ./verify-preflight.sh --full    # Full verify (adds D-05 checks 6-7)

DOCKER_SETTINGS_DIR="$HOME/Library/Group Containers/group.com.docker"
DOCKER_RAW_PATH="$HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
TARGET_DIR="/Volumes/Unitek-B/Docker"
PASS=0
FAIL=0

# Parse arguments
FULL_MODE=false
for arg in "$@"; do
  case "$arg" in
    --full) FULL_MODE=true ;;
    *) echo "Unknown argument: $arg"; echo "Usage: $0 [--full]"; exit 1 ;;
  esac
done

preflight_pass() { echo "[ PASS ] $1"; PASS=$((PASS + 1)); }
preflight_fail() { echo "[ FAIL ] $1"; FAIL=$((FAIL + 1)); }
preflight_info() { echo "[ INFO ] $1"; }

echo "Pre-flight Verification Results"
echo "================================"

# ── Check 1 (PREFLT-01): Docker processes not running ────────────
# pgrep returns non-zero when no match — that is the expected pass state.
# Trust pgrep exclusively (Pitfall 2 — do not use launchctl).
RUNNING=""
RUNNING+=$(pgrep -f 'Docker Desktop'          2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.backend'      2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.virtualization' 2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.helper'       2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.build'        2>/dev/null || true)

if [[ -z "$RUNNING" ]]; then
  preflight_pass "PREFLT-01: No Docker processes running"
else
  preflight_fail "PREFLT-01: Docker processes still running (PIDs: $RUNNING)"
fi

# ── Check 2 (PREFLT-02): External volume is APFS ─────────────────
# Parse Type (Bundle) field — authoritative filesystem type (Pitfall 4).
FSTYPE=$(diskutil info /Volumes/Unitek-B 2>/dev/null \
  | awk -F': ' '/Type \(Bundle\)/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')

if [[ "$FSTYPE" == "apfs" ]]; then
  preflight_pass "PREFLT-02: /Volumes/Unitek-B is APFS format"
else
  preflight_fail "PREFLT-02: /Volumes/Unitek-B is '${FSTYPE}', not APFS"
fi

# ── Check 3 (PREFLT-03): Sufficient free space ───────────────────
# Re-measure — space may have changed since preflight.sh ran.
DOCKER_RAW_KB=$(du -sk "$DOCKER_RAW_PATH" | awk '{print $1}')
REQUIRED_KB=$((DOCKER_RAW_KB * 2))
AVAIL_KB=$(df -k /Volumes/Unitek-B | awk 'NR==2 {print $4}')
DOCKER_RAW_GB=$(echo "scale=1; $DOCKER_RAW_KB / 1048576" | bc)
REQUIRED_GB=$(echo "scale=1; $REQUIRED_KB / 1048576" | bc)
AVAIL_GB=$(echo "scale=0; $AVAIL_KB / 1048576" | bc)

if [[ $AVAIL_KB -ge $REQUIRED_KB ]]; then
  preflight_pass "PREFLT-03: Free space ${AVAIL_GB} GB >= required ${REQUIRED_GB} GB (2x Docker.raw on-disk ${DOCKER_RAW_GB} GB)"
else
  preflight_fail "PREFLT-03: Free space ${AVAIL_GB} GB < required ${REQUIRED_GB} GB"
fi

# ── Check 4 (PREFLT-04): Backup files exist ──────────────────────
# Both .bak files must be present in same directory (D-04).
BACKUPS_OK=true
[[ -f "$DOCKER_SETTINGS_DIR/settings-store.json.bak" ]] || BACKUPS_OK=false
[[ -f "$DOCKER_SETTINGS_DIR/settings.json.bak" ]]       || BACKUPS_OK=false

if [[ "$BACKUPS_OK" == "true" ]]; then
  preflight_pass "PREFLT-04: Backup files present: settings-store.json.bak, settings.json.bak"
else
  preflight_fail "PREFLT-04: One or both backup files missing"
  if [[ ! -f "$DOCKER_SETTINGS_DIR/settings-store.json.bak" ]]; then
    echo "         Missing: $DOCKER_SETTINGS_DIR/settings-store.json.bak"
  fi
  if [[ ! -f "$DOCKER_SETTINGS_DIR/settings.json.bak" ]]; then
    echo "         Missing: $DOCKER_SETTINGS_DIR/settings.json.bak"
  fi
fi

# ── Check 5 (PREFLT-05): Target directory writable ───────────────
# Read-only check: verify directory exists and is writable (no write test).
if test -d "$TARGET_DIR" && test -w "$TARGET_DIR"; then
  preflight_pass "PREFLT-05: $TARGET_DIR exists and is writable"
else
  if [[ ! -d "$TARGET_DIR" ]]; then
    preflight_fail "PREFLT-05: $TARGET_DIR does not exist"
  else
    preflight_fail "PREFLT-05: $TARGET_DIR exists but is not writable"
  fi
fi

# ── Checks 6-7: --full mode only ─────────────────────────────────
if [[ "$FULL_MODE" == "true" ]]; then

  # Check 6 (D-05): Apple Virtualization Framework backend
  USE_VF=$(python3 -c "
import json
with open('$DOCKER_SETTINGS_DIR/settings-store.json') as f:
    d = json.load(f)
print(d.get('UseVirtualizationFramework', False))
")

  if [[ "$USE_VF" == "True" ]]; then
    preflight_pass "D-05: Apple Virtualization Framework backend confirmed (not Docker VMM)"
  else
    preflight_fail "D-05: Docker VMM backend detected — switch to Apple Virtualization Framework"
  fi

  # Check 7: Backup content matches source (no edits happened in Phase 1)
  SETTINGS_STORE_MATCH=true
  SETTINGS_MATCH=true

  if [[ -f "$DOCKER_SETTINGS_DIR/settings-store.json.bak" ]]; then
    diff "$DOCKER_SETTINGS_DIR/settings-store.json" \
         "$DOCKER_SETTINGS_DIR/settings-store.json.bak" > /dev/null 2>&1 || SETTINGS_STORE_MATCH=false
  else
    SETTINGS_STORE_MATCH=false
  fi

  if [[ -f "$DOCKER_SETTINGS_DIR/settings.json.bak" ]]; then
    diff "$DOCKER_SETTINGS_DIR/settings.json" \
         "$DOCKER_SETTINGS_DIR/settings.json.bak" > /dev/null 2>&1 || SETTINGS_MATCH=false
  else
    SETTINGS_MATCH=false
  fi

  if [[ "$SETTINGS_STORE_MATCH" == "true" && "$SETTINGS_MATCH" == "true" ]]; then
    preflight_pass "Backup content matches source files (no post-backup edits detected)"
  elif [[ "$SETTINGS_STORE_MATCH" == "false" && "$SETTINGS_MATCH" == "false" ]]; then
    preflight_fail "Both backup files differ from source — settings may have been edited post-backup"
  elif [[ "$SETTINGS_STORE_MATCH" == "false" ]]; then
    preflight_fail "settings-store.json.bak differs from settings-store.json — file may have been edited post-backup"
  else
    preflight_fail "settings.json.bak differs from settings.json — file may have been edited post-backup"
  fi

fi

# ── UseVirtualizationFramework info (quick mode) ─────────────────
if [[ "$FULL_MODE" == "false" && -f "$DOCKER_SETTINGS_DIR/settings-store.json" ]]; then
  USE_VF=$(python3 -c "
import json
with open('$DOCKER_SETTINGS_DIR/settings-store.json') as f:
    d = json.load(f)
print(d.get('UseVirtualizationFramework', False))
" 2>/dev/null || echo "unknown")
  preflight_info "UseVirtualizationFramework: $USE_VF (run --full for full D-05 check)"
fi

# ── Summary ──────────────────────────────────────────────────────
echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "All $PASS verification checks passed."
else
  echo "$FAIL check(s) failed. Pre-flight results are not fully confirmed."
  exit 1
fi
