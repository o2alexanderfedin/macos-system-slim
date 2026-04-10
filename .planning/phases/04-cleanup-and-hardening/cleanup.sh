#!/bin/bash
set -euo pipefail

# cleanup.sh — Delete original Docker.raw from internal disk to reclaim ~24 GB.
#
# Requirements covered:
#   CLEAN-01: Original Docker.raw is deleted from internal disk (only after
#             verification passes)
#   CLEAN-02: Internal disk space is confirmed reclaimed (df -h / before/after)
#
# Safety notes:
#   - GATE: verify-cutover.sh MUST pass (exit 0) before any deletion proceeds
#   - Deletes with explicit full path -- no rm -rf, no wildcards
#   - Captures df -h / BEFORE and AFTER deletion to prove space reclaimed
#   - Does NOT delete .bak files (settings-store.json.bak, settings.json.bak)
#     per D-04 -- they provide rollback insurance and are only ~8 KB total
#   - Run harden.sh after this script to complete Phase 4

DOCKER_RAW_INTERNAL="$HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
VERIFY_SCRIPT="$(dirname "$0")/../03-cutover-and-verification/verify-cutover.sh"
RESULTS_FILE="$(dirname "$0")/cleanup-results.txt"
PASS=0
FAIL=0

# ── Tee all output to results file ───────────────────────────────────────────

exec > >(tee "$RESULTS_FILE") 2>&1

# ── Helper functions (Phase 1/2/3 pattern) ────────────────────────────────────

cleanup_pass()  { echo "[ PASS ] $1"; PASS=$((PASS + 1)); }
cleanup_fail()  { echo "[ FAIL ] $1"; FAIL=$((FAIL + 1)); }
cleanup_info()  { echo "[ INFO ] $1"; }
cleanup_abort() {
  echo ""
  echo "ABORT: $1"
  echo "Fix the issue above, then re-run or investigate manually."
  exit 1
}

# ── Header ────────────────────────────────────────────────────────────────────

echo "Docker Desktop Cleanup"
echo "======================"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""

# ── D-01 gate: Re-run verify-cutover.sh before any deletion ──────────────────
# verify-cutover.sh exits 0 on success, 1 on failure.
# If it fails, we abort immediately -- deletion is blocked until Docker is
# confirmed running correctly from the external volume.
cleanup_info "Running pre-deletion gate: verify-cutover.sh..."
if ! bash "$VERIFY_SCRIPT"; then
  cleanup_abort "verify-cutover.sh failed -- Docker.raw deletion blocked. Fix and retry."
fi
cleanup_pass "Pre-deletion gate: verify-cutover.sh passed"

# ── Confirm Docker.raw exists at internal path ────────────────────────────────
if [[ ! -f "$DOCKER_RAW_INTERNAL" ]]; then
  cleanup_abort "Docker.raw not found at $DOCKER_RAW_INTERNAL -- already deleted?"
fi
cleanup_pass "Original Docker.raw found at internal path"

# ── D-03 BEFORE: Capture df -h / before deletion ─────────────────────────────
echo ""
echo "=== df -h / BEFORE deletion ==="
df -h /
echo ""

# ── D-02: Delete with explicit full path (no rm -rf, no wildcards) ────────────
cleanup_info "Deleting original Docker.raw from internal disk..."
rm "$DOCKER_RAW_INTERNAL"
cleanup_pass "CLEAN-01: Docker.raw deleted from internal disk"

# ── Verify file is gone ───────────────────────────────────────────────────────
if [[ ! -f "$DOCKER_RAW_INTERNAL" ]]; then
  cleanup_pass "Deletion confirmed: Docker.raw no longer exists at internal path"
else
  cleanup_fail "Deletion may have failed: Docker.raw still present at $DOCKER_RAW_INTERNAL"
fi

# ── D-03 AFTER: Capture df -h / after deletion ───────────────────────────────
echo ""
echo "=== df -h / AFTER deletion ==="
df -h /
echo ""
cleanup_pass "CLEAN-02: Space comparison captured (see df output above)"

# ── D-04: Inform user about .bak files retained ──────────────────────────────
cleanup_info "Backup files (.bak) retained per user decision (D-04)"
cleanup_info "  settings-store.json.bak and settings.json.bak provide rollback insurance"
cleanup_info "  Location: $HOME/Library/Group Containers/group.com.docker/"
cleanup_info "  Total size: ~8 KB -- safe to keep indefinitely"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
echo "======================================"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi

echo "Cleanup complete. Run harden.sh next to disable auto-update and start-at-login."
