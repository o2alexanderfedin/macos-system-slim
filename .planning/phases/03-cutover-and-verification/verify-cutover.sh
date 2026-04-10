#!/bin/bash
set -euo pipefail

# verify-cutover.sh — Independent post-cutover verification script.
#
# Requirements covered:
#   VERIF-01: Verifies Docker images count > 0 after migration (docker images)
#   VERIF-02: Verifies container count > 0 after migration (docker ps -a, all states)
#   VERIF-03: Smoke test -- runs hello-world container successfully
#   CONF-01 confirmation: Re-reads settings-store.json DataFolder to confirm cutover.sh
#             wrote the correct value
#
# Notes:
#   - Docker Desktop MUST already be running before calling this script
#   - If Docker is not running, run cutover.sh first, then re-run this script
#   - This script is READ-ONLY: does not modify settings files, start/stop Docker,
#     or delete anything -- safe to re-run at any time
#   - A broken Compose group is a known pre-existing condition (D-09): containers
#     in error/stopped state are expected and do NOT indicate migration failure
#   - VERIF-03 (hello-world) requires either cached image or network access

NEW_PATH="/Volumes/Unitek-B/Docker"
SETTINGS_DIR="$HOME/Library/Group Containers/group.com.docker"
SETTINGS_STORE="$SETTINGS_DIR/settings-store.json"
PASS=0
FAIL=0

# ── Helper functions (Phase 1/2 pattern) ─────────────────────────────────────

verify_pass() { echo "[ PASS ] $1"; PASS=$((PASS + 1)); }
verify_fail() { echo "[ FAIL ] $1"; FAIL=$((FAIL + 1)); }
verify_info() { echo "[ INFO ] $1"; }

# ── Header ────────────────────────────────────────────────────────────────────

echo "Cutover Verification Results"
echo "============================"

# ── Docker daemon guard ───────────────────────────────────────────────────────
# This script verifies a running Docker daemon. Cannot proceed without one.
if ! docker info > /dev/null 2>&1; then
  echo "[ FAIL ] Docker daemon is not running. Start Docker Desktop first or run cutover.sh."
  exit 1
fi
verify_pass "Docker daemon is running"

# ── Settings verification (CONF-01 confirmation) ──────────────────────────────
# Re-read DataFolder from settings-store.json to confirm cutover.sh wrote correctly.
# Note: Docker Desktop may rewrite settings on startup — this catches any revert.
CURRENT_DF=$(python3 -c "import json; d=json.load(open('$SETTINGS_STORE')); print(d.get('DataFolder','NOT FOUND'))" 2>/dev/null || echo "ERROR")

if [[ "$CURRENT_DF" == "$NEW_PATH" ]]; then
  verify_pass "CONF-01: DataFolder = /Volumes/Unitek-B/Docker"
else
  verify_fail "CONF-01: DataFolder = $CURRENT_DF (expected /Volumes/Unitek-B/Docker)"
fi

# ── Docker Root Dir check (informational -- per Open Question 2 from research) ─
# DockerRootDir may show VM-internal path like /var/lib/docker (not host path).
# Informational only; the real check is settings file verification above.
DOCKER_ROOT=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "unknown")
verify_info "Docker Root Dir: $DOCKER_ROOT"
verify_info "Note: VM-internal path is expected (see research Open Question 2)"

# ── VERIF-01: Image count > 0 ────────────────────────────────────────────────
# docker images --format avoids header line; wc -l counts actual entries.
IMAGE_COUNT=$(docker images --format '{{.Repository}}' | wc -l | tr -d ' ')

if [[ $IMAGE_COUNT -gt 0 ]]; then
  verify_pass "VERIF-01: $IMAGE_COUNT image(s) present"
else
  verify_fail "VERIF-01: No images found -- migration may have failed"
fi

# Print first 10 image names for reference
if [[ $IMAGE_COUNT -gt 0 ]]; then
  verify_info "First 10 images:"
  docker images --format '  {{.Repository}}:{{.Tag}}' | head -10
fi

# ── VERIF-02: Container count > 0 ────────────────────────────────────────────
# Use docker ps -a (all containers including stopped/error) per D-09.
# The broken Compose group produces error-state containers -- this is expected.
# Count > 0 is the pass condition regardless of container run state.
CONTAINER_COUNT=$(docker ps -a --format '{{.Names}}' | wc -l | tr -d ' ')

if [[ $CONTAINER_COUNT -gt 0 ]]; then
  verify_pass "VERIF-02: $CONTAINER_COUNT container(s) present"
else
  verify_fail "VERIF-02: No containers found -- migration may have failed"
fi

# Print first 10 container names for reference
if [[ $CONTAINER_COUNT -gt 0 ]]; then
  verify_info "First 10 containers (all states):"
  docker ps -a --format '  {{.Names}} ({{.Status}})' | head -10
fi

# ── VERIF-03: hello-world smoke test ─────────────────────────────────────────
# Check if hello-world is already cached locally (from pre-migration state).
# If not cached, a pull is required -- note this requires network access.
if docker images --format '{{.Repository}}' | grep -q '^hello-world$'; then
  verify_info "hello-world image already cached locally"
else
  verify_info "hello-world not cached -- will pull from registry (requires network)"
fi

SMOKE_EXIT=0
docker run --rm hello-world > /dev/null 2>&1 || SMOKE_EXIT=$?

if [[ $SMOKE_EXIT -eq 0 ]]; then
  verify_pass "VERIF-03: hello-world smoke test succeeded"
else
  verify_fail "VERIF-03: hello-world smoke test failed"
  verify_info "Run manually: docker run --rm hello-world"
  verify_info "If hello-world is not cached and network is unavailable, this is a network issue"
  verify_info "not a migration failure (VERIF-01 and VERIF-02 are the primary migration checks)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
echo "======================================"

if [[ $FAIL -gt 0 ]]; then
  echo "VERIFICATION FAILED"
  exit 1
fi

echo "All checks passed -- Docker is running from external volume. Safe to proceed to Phase 4 (cleanup)."
