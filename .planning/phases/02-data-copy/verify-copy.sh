#!/bin/bash
set -euo pipefail

# verify-copy.sh — Independent read-only verification of Docker.raw copy.
#
# Requirements covered:
#   MIGR-01: Confirms Docker.raw exists at destination
#   MIGR-02: Verifies copy integrity via dual-metric size comparison
#            MIGR-02a: Logical size match (stat -f %z) — catches truncation
#            MIGR-02b: On-disk size match (du -sk) — catches sparse-to-dense inflation
#
# This script is READ-ONLY. It does not copy, move, or delete anything.
# It can be run repeatedly without side effects.
# Run after copy-docker.sh completes. Must pass before proceeding to Phase 3.

SOURCE="$HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
DEST="/Volumes/Unitek-B/Docker/Docker.raw"
PASS=0
FAIL=0

# ── Helper functions (Phase 1 pattern) ───────────────────────────────────────

verify_pass() { echo "[ PASS ] $1"; PASS=$((PASS + 1)); }
verify_fail() { echo "[ FAIL ] $1"; FAIL=$((FAIL + 1)); }
verify_info() { echo "[ INFO ] $1"; }

echo "Copy Verification Results"
echo "========================="

# ── Check 1: Destination file exists (MIGR-01) ───────────────────────────────
if [[ ! -f "$DEST" ]]; then
  verify_fail "MIGR-01: Destination file not found: $DEST"
  echo ""
  echo "VERIFICATION FAILED -- do not proceed to Phase 3"
  exit 1
fi
verify_pass "MIGR-01: Destination file exists: $DEST"

# ── Check 2: Logical size match (MIGR-02a, D-08) ─────────────────────────────
# stat -f %z reports true logical file size in bytes.
# A mismatch here means the copy was truncated — data loss.
SRC_LOGICAL=$(stat -f %z "$SOURCE")
DST_LOGICAL=$(stat -f %z "$DEST")

verify_info "Logical size — source: ${SRC_LOGICAL} bytes  dest: ${DST_LOGICAL} bytes"

if [[ "$SRC_LOGICAL" == "$DST_LOGICAL" ]]; then
  verify_pass "MIGR-02a: Logical size matches: ${SRC_LOGICAL} bytes"
else
  verify_fail "MIGR-02a: Logical size mismatch: source=${SRC_LOGICAL} dest=${DST_LOGICAL}"
fi

# ── Check 3: On-disk size match (MIGR-02b, D-09) ─────────────────────────────
# du -sk reports committed on-disk blocks in KB (respects APFS sparse allocation).
# A large mismatch means sparse holes were expanded to dense data (inflation).
# Within 1% is tolerated for APFS transparent compression effects (Pitfall 3).
SRC_DISK_KB=$(du -sk "$SOURCE" | awk '{print $1}')
DST_DISK_KB=$(du -sk "$DEST" | awk '{print $1}')

verify_info "On-disk size — source: ${SRC_DISK_KB} KB  dest: ${DST_DISK_KB} KB"

# 1% threshold: if SRC_DISK_KB is 0 for any reason, threshold defaults to 0
THRESHOLD=$(echo "scale=0; $SRC_DISK_KB / 100" | bc)
DIFF=$(( DST_DISK_KB - SRC_DISK_KB ))
ABS_DIFF=$(( DIFF < 0 ? -DIFF : DIFF ))

if [[ $ABS_DIFF -eq 0 ]]; then
  verify_pass "MIGR-02b: On-disk size matches exactly: ${SRC_DISK_KB} KB"
elif [[ $ABS_DIFF -le $THRESHOLD ]]; then
  verify_pass "MIGR-02b: On-disk size within 1% tolerance (source=${SRC_DISK_KB}KB dest=${DST_DISK_KB}KB diff=${ABS_DIFF}KB)"
  verify_info "Small on-disk difference is consistent with APFS transparent compression"
else
  verify_fail "MIGR-02b: On-disk size mismatch exceeds 1%: source=${SRC_DISK_KB}KB dest=${DST_DISK_KB}KB diff=${ABS_DIFF}KB"
fi

# ── Check 4: Source still exists and unchanged (D-13) ────────────────────────
# The original Docker.raw must be untouched — Phase 4 handles deletion.
if [[ -f "$SOURCE" ]]; then
  VERIFY_SRC_LOGICAL=$(stat -f %z "$SOURCE")
  if [[ "$VERIFY_SRC_LOGICAL" == "$SRC_LOGICAL" ]]; then
    verify_pass "D-13: Source Docker.raw still present and unchanged (${SRC_LOGICAL} bytes)"
  else
    verify_fail "D-13: Source Docker.raw size changed! was=${SRC_LOGICAL} now=${VERIFY_SRC_LOGICAL}"
  fi
else
  verify_fail "D-13: Source Docker.raw missing: $SOURCE"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
echo "======================================="

if [[ $FAIL -gt 0 ]]; then
  echo "VERIFICATION FAILED -- do not proceed to Phase 3"
  exit 1
fi

echo "All checks passed -- safe to proceed to Phase 3"
exit 0
