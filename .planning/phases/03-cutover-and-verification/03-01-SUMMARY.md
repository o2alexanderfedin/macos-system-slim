---
phase: 03-cutover-and-verification
plan: 01
subsystem: infra
tags: [docker, bash, python, settings, migration, cutover, verification]

# Dependency graph
requires:
  - phase: 02-data-copy
    provides: Docker.raw copied to /Volumes/Unitek-B/Docker/ (Phase 2 complete)
  - phase: 01-pre-flight
    provides: settings files backed up (.bak), PASS/FAIL/INFO script patterns established
provides:
  - cutover.sh: updates Docker Desktop settings to external volume, starts Docker, polls readiness
  - verify-cutover.sh: independent re-runnable post-cutover verification (images, containers, smoke test)
affects:
  - 03-02 (Phase 3 Plan 02 -- live execution)
  - 04-cleanup (Phase 4 -- cleanup gates on cutover verification passing)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Python json module embedded via heredoc for safe JSON settings update with atomic readback verify"
    - "docker info polling loop (5s interval, 120s timeout) for Docker Desktop readiness detection"
    - "emit_diagnostics function pattern for structured failure investigation output"

key-files:
  created:
    - .planning/phases/03-cutover-and-verification/cutover.sh
    - .planning/phases/03-cutover-and-verification/verify-cutover.sh
  modified: []

key-decisions:
  - "Python json module (not sed) for settings update -- safe JSON handling, readback verify before Docker start (D-01, D-04)"
  - "Hard-stop on settings update failure before starting Docker (D-13) -- never start Docker with broken config"
  - "docker ps -a (not docker ps) for VERIF-02 -- counts stopped/error containers from known broken Compose group (D-09)"
  - "emit_diagnostics on failure -- settings values, log path, docker info output -- investigate-first not auto-rollback (D-11, D-12)"
  - "DockerRootDir is informational only -- may show VM-internal /var/lib/docker, not host path (Open Question 2)"

patterns-established:
  - "Pattern: embedded Python heredoc for JSON mutation in bash scripts"
  - "Pattern: two-script structure (mutate + independent verify) matching Phase 1/2 split"
  - "Pattern: emit_diagnostics function for structured failure output"

requirements-completed: [CONF-01, CONF-02, VERIF-01, VERIF-02, VERIF-03]

# Metrics
duration: 2min
completed: 2026-04-10
---

# Phase 3 Plan 01: Cutover and Verification Scripts Summary

**cutover.sh + verify-cutover.sh: Docker Desktop settings update via Python json module with readback verify, 120s readiness poll, and independent post-migration image/container/smoke-test verification**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-10T05:20:47Z
- **Completed:** 2026-04-10T05:23:05Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- cutover.sh: updates both settings files (DataFolder in settings-store.json, dataFolder in settings.json) via embedded Python json module with atomic readback verify, then starts Docker Desktop with `open -a` and polls `docker info` every 5 seconds up to 120 seconds, emits diagnostics on any failure
- verify-cutover.sh: re-runnable read-only verification confirming settings, image count > 0, container count > 0 (all states via `docker ps -a`), and hello-world smoke test with cache check
- Both scripts follow Phase 1/2 conventions: `set -euo pipefail`, `[ PASS ]`/`[ FAIL ]`/`[ INFO ]` output format, PASS/FAIL counters, summary block

## Task Commits

Each task was committed atomically:

1. **Task 1: Create cutover.sh** - `01c53b7` (feat)
2. **Task 2: Create verify-cutover.sh** - `d809777` (feat)

**Plan metadata:** [pending final commit] (docs: complete plan)

## Files Created/Modified

- `.planning/phases/03-cutover-and-verification/cutover.sh` - Docker Desktop settings update + Docker start + readiness poll; saves results to cutover-results.txt
- `.planning/phases/03-cutover-and-verification/verify-cutover.sh` - Independent re-runnable verification of settings, images, containers, hello-world smoke test; gates Phase 4

## Decisions Made

- Python json module via embedded heredoc chosen over sed/jq for JSON safety -- no special character fragility; atomic readback verify (D-04) catches partial writes before Docker starts
- Hard-stop on Python exit code non-zero (D-13) -- script aborts before `open -a` when settings update fails, leaving Docker config unchanged
- `docker ps -a` for VERIF-02 (not `docker ps`) -- known broken Compose group produces stopped/error containers (D-09); count > 0 passes as long as containers exist regardless of run state
- `emit_diagnostics` function prints settings DataFolder values, Docker Desktop logs path, and `docker info` output on failure -- enables investigation without auto-rollback (D-11, D-12)
- DockerRootDir from `docker info --format '{{.DockerRootDir}}'` reported informational only -- may show VM-internal path `/var/lib/docker`, not macOS host path (research Open Question 2)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required. Scripts are ready for live execution in Plan 03-02.

## Next Phase Readiness

- cutover.sh and verify-cutover.sh are syntax-valid, executable, and ready for live execution
- Plan 03-02 orchestrates the live run: user stops Docker, runs cutover.sh, runs verify-cutover.sh
- Phase 4 (cleanup/deletion of original Docker.raw) gates on verify-cutover.sh passing
- No blockers

---
*Phase: 03-cutover-and-verification*
*Completed: 2026-04-10*
