#!/bin/bash
set -euo pipefail

# copy-docker.sh — Docker.raw copy script for macOS external volume migration.
#
# Requirements covered:
#   MIGR-01: Copies Docker.raw to /Volumes/Unitek-B/Docker/ preserving APFS sparse structure
#   MIGR-02: Verifies copy size via dual-metric comparison (logical + on-disk)
#   MIGR-03: Shows progress bar during copy via background polling
#   MIGR-04: Falls back to ditto if cp -c fails
#
# Safety notes:
#   - Docker MUST be stopped before running this script
#   - Original Docker.raw is NEVER modified or deleted (Phase 4 handles deletion)
#   - On copy failure: partial destination is deleted, one retry with ditto
#   - On second failure: abort with details (D-14 hard-stop philosophy)
#   - Run verify-copy.sh after completion for independent verification

SOURCE="$HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
DEST="/Volumes/Unitek-B/Docker/Docker.raw"
POLL_INTERVAL=5
PASS=0
FAIL=0

# ── Helper functions (Phase 1 pattern) ───────────────────────────────────────

copy_pass() { echo "[ PASS ] $1"; PASS=$((PASS + 1)); }
copy_fail() { echo "[ FAIL ] $1"; FAIL=$((FAIL + 1)); }
copy_info() { echo "[ INFO ] $1"; }
copy_abort() {
  echo ""
  echo "ABORT: $1"
  echo "Fix the issue above, then re-run copy-docker.sh."
  exit 1
}

# cleanup_partial — deletes destination file if it exists.
# Always prints what it is deleting before rm (anti-pattern: never delete silently).
cleanup_partial() {
  if [[ -f "$DEST" ]]; then
    copy_info "Deleting partial destination: $DEST"
    rm -f "$DEST"
  fi
}

echo "Docker.raw Copy"
echo "==============="

# ── Docker-stopped guard (Pitfall 5) ─────────────────────────────────────────
# Abort immediately if any Docker process is detected running.
# Docker holds Docker.raw open — copying while Docker runs produces corruption.
RUNNING=""
RUNNING+=$(pgrep -f 'Docker Desktop'            2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.backend'         2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.virtualization'  2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.helper'          2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.build'           2>/dev/null || true)

if [[ -n "$RUNNING" ]]; then
  copy_fail "Docker processes detected running (PIDs: $RUNNING)"
  copy_abort "Stop Docker Desktop completely before running this script."
fi
copy_info "Docker processes: none detected (safe to copy)"

# ── Source file guard ─────────────────────────────────────────────────────────
if [[ ! -f "$SOURCE" ]]; then
  copy_fail "Source file not found: $SOURCE"
  copy_abort "Docker.raw not found at expected path."
fi
copy_info "Source file exists: $SOURCE"

# ── Optional pre-copy space guard (belt-and-suspenders) ──────────────────────
# Phase 1 already confirmed 1495 GB free, but verify again in case conditions changed.
REQUIRED_KB=$(du -sk "$SOURCE" | awk '{print $1}')
AVAIL_KB=$(df -k /Volumes/Unitek-B | awk 'NR==2 {print $4}')

if [[ $AVAIL_KB -lt $REQUIRED_KB ]]; then
  REQUIRED_GB=$(echo "scale=1; $REQUIRED_KB / 1048576" | bc)
  AVAIL_GB=$(echo "scale=1; $AVAIL_KB / 1048576" | bc)
  copy_fail "Insufficient space: ${AVAIL_GB} GB available, ${REQUIRED_GB} GB required"
  copy_abort "Free up space on /Volumes/Unitek-B and retry."
fi

# ── Capture source sizes for verification ────────────────────────────────────
# D-08: Compare both logical size and on-disk size post-copy.
SRC_LOGICAL=$(stat -f %z "$SOURCE")
SRC_DISK_KB=$(du -sk "$SOURCE" | awk '{print $1}')
SRC_LOGICAL_GB=$(echo "scale=1; $SRC_LOGICAL / 1073741824" | bc)
SRC_DISK_GB=$(echo "scale=1; $SRC_DISK_KB / 1048576" | bc)

copy_info "Source logical size: ${SRC_LOGICAL} bytes (${SRC_LOGICAL_GB} GB)"
copy_info "Source on-disk size: ${SRC_DISK_KB} KB (${SRC_DISK_GB} GB sparse)"

# ── run_copy function ─────────────────────────────────────────────────────────
# Launches copy command in background, polls progress, waits for completion.
# Returns exit code of the copy command.
#
# Usage: run_copy <command>
#   command: "cp -c" or "ditto"
run_copy() {
  local CMD="$1"
  local EXPECTED_KB
  EXPECTED_KB=$(du -sk "$SOURCE" | awk '{print $1}')

  # Delete any existing partial destination before starting (D-11)
  cleanup_partial

  # Launch copy in background (D-05, D-07)
  $CMD "$SOURCE" "$DEST" &
  local COPY_PID=$!

  echo ""
  # Polling loop: render progress bar until copy process exits (Pitfall 1, 4)
  # kill -0 returns non-zero when process exits — 2>/dev/null prevents set -e trigger
  while kill -0 "$COPY_PID" 2>/dev/null; do
    # Pitfall 2: du may return 0 at start; guard with || echo 0
    local CURRENT_KB
    CURRENT_KB=$(du -sk "$DEST" 2>/dev/null | awk '{print $1}' || echo 0)

    if [[ $EXPECTED_KB -gt 0 && $CURRENT_KB -gt 0 ]]; then
      local PCT
      PCT=$(echo "scale=0; $CURRENT_KB * 100 / $EXPECTED_KB" | bc)
      # Clamp to 100 (APFS may report slightly more than expected briefly)
      PCT=$(( PCT > 100 ? 100 : PCT ))
      local BARS=$(( PCT / 2 ))
      local BAR
      BAR=$(printf '#%.0s' $(seq 1 "$BARS") 2>/dev/null || true)
      printf "\r  [ COPY ] [%-50s] %3d%%" "$BAR" "$PCT"
    else
      printf "\r  [ COPY ] starting..."
    fi

    sleep $POLL_INTERVAL
  done

  printf "\n"

  # Capture the actual exit code of the copy process (Pitfall 1)
  # wait returns the exit code of the process
  wait "$COPY_PID"
  return $?
}

# ── Copy execution (D-01, D-02, D-11, D-12) ──────────────────────────────────

copy_info "Starting copy: cp -c \"$SOURCE\" \"$DEST\""
COPY_EXIT=0
run_copy "cp -c" || COPY_EXIT=$?

if [[ $COPY_EXIT -ne 0 ]]; then
  copy_info "cp -c failed (exit $COPY_EXIT) -- cleaning partial and retrying with ditto"
  cleanup_partial

  copy_info "Starting fallback copy: ditto \"$SOURCE\" \"$DEST\""
  COPY_EXIT=0
  run_copy "ditto" || COPY_EXIT=$?

  if [[ $COPY_EXIT -ne 0 ]]; then
    cleanup_partial
    copy_fail "Both copy methods failed"
    copy_abort "Cannot copy Docker.raw. Check disk space, volume mount, permissions."
  fi
fi

copy_pass "MIGR-01: Docker.raw copied to $DEST"

# ── Post-copy verification (D-08, D-09, D-10) ────────────────────────────────
# Sleep 2 to allow APFS to flush metadata before measuring (Pitfall 3, Open Question 1).
copy_info "Waiting 2 seconds for APFS metadata flush before verification..."
sleep 2

DST_LOGICAL=$(stat -f %z "$DEST")
DST_DISK_KB=$(du -sk "$DEST" | awk '{print $1}')

# MIGR-02a: Logical size — exact match required (truncation check)
if [[ "$SRC_LOGICAL" == "$DST_LOGICAL" ]]; then
  copy_pass "MIGR-02a: Logical size matches: ${SRC_LOGICAL} bytes"
else
  copy_fail "MIGR-02a: Logical size mismatch: source=${SRC_LOGICAL} dest=${DST_LOGICAL}"
fi

# MIGR-02b: On-disk size — exact match preferred; within 1% tolerated for APFS compression
# (Pitfall 3: APFS transparent compression may cause small differences)
THRESHOLD=$(echo "scale=0; $SRC_DISK_KB / 100" | bc)
DIFF=$(( DST_DISK_KB - SRC_DISK_KB ))
# Absolute value of diff
ABS_DIFF=$(( DIFF < 0 ? -DIFF : DIFF ))

if [[ $ABS_DIFF -eq 0 ]]; then
  copy_pass "MIGR-02b: On-disk size matches exactly: ${SRC_DISK_KB} KB"
elif [[ $ABS_DIFF -le $THRESHOLD ]]; then
  copy_pass "MIGR-02b: On-disk size within 1% tolerance (source=${SRC_DISK_KB}KB dest=${DST_DISK_KB}KB diff=${ABS_DIFF}KB)"
  copy_info "Small on-disk difference is normal APFS compression behavior"
else
  copy_fail "MIGR-02b: On-disk size mismatch exceeds 1%: source=${SRC_DISK_KB}KB dest=${DST_DISK_KB}KB diff=${ABS_DIFF}KB"
fi

# ── Verify original untouched (D-13) ─────────────────────────────────────────
VERIFY_SRC_LOGICAL=$(stat -f %z "$SOURCE")
if [[ "$VERIFY_SRC_LOGICAL" == "$SRC_LOGICAL" ]]; then
  copy_pass "MIGR-01: Original Docker.raw untouched (logical size still ${SRC_LOGICAL} bytes)"
else
  copy_fail "Source file modified! source size changed: was ${SRC_LOGICAL} now ${VERIFY_SRC_LOGICAL}"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
echo "======================================="

if [[ $FAIL -gt 0 ]]; then
  copy_abort "Verification failed -- do not proceed to Phase 3"
fi

echo "All checks passed. Docker.raw copy complete."
echo "Run verify-copy.sh for independent verification before Phase 3."
