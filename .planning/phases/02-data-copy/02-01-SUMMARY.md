---
phase: 02-data-copy
plan: 01
subsystem: infra
tags: [bash, apfs, docker, cp, ditto, sparse-file, migration]

requires:
  - phase: 01-pre-flight
    provides: confirmed Docker stopped, target dir writable, APFS volume verified, Docker.raw path confirmed

provides:
  - copy-docker.sh: main copy script with background progress bar, cp -c primary + ditto fallback, dual-metric post-copy verification
  - verify-copy.sh: independent read-only verification script with dual-metric size comparison

affects: [03-cutover, 04-cleanup]

tech-stack:
  added: []
  patterns:
    - "Background copy with polling progress: launch cp in background, poll du -sk every 5s, render printf progress bar, wait for PID"
    - "Dual-metric integrity verification: stat -f %z (logical) + du -sk (on-disk KB) both must match"
    - "1% on-disk tolerance: APFS transparent compression may cause small differences, tolerated with INFO note"
    - "Cleanup before retry: always print what is being deleted before rm -f (anti-pattern: never delete silently)"

key-files:
  created:
    - .planning/phases/02-data-copy/copy-docker.sh
    - .planning/phases/02-data-copy/verify-copy.sh
  modified: []

key-decisions:
  - "cp -c as primary (clonefile/copyfile APFS semantics), ditto as fallback — both preserve APFS sparse metadata"
  - "Background polling with du -sk (not ls -la) — du measures committed on-disk blocks, ls reports logical size always"
  - "sleep 2 before verification to allow APFS metadata flush — prevents false on-disk size mismatch"
  - "1% on-disk size tolerance handles APFS transparent compression without blocking valid copies"
  - "cleanup_partial always prints before deleting — aids debugging on re-run after failure"

patterns-established:
  - "Pattern: run_copy() abstracts background launch + poll loop + wait — reusable for both cp -c and ditto"
  - "Pattern: copy script (mutation) + verify script (read-only) — same split as Phase 1 preflight.sh / verify-preflight.sh"

requirements-completed: [MIGR-01, MIGR-02, MIGR-03, MIGR-04]

duration: 1min
completed: 2026-04-10
---

# Phase 02 Plan 01: Data Copy Scripts Summary

**Two bash scripts implementing Docker.raw copy with cp -c/ditto fallback, du -sk background polling progress bar, and dual-metric (logical + on-disk) APFS integrity verification**

## Performance

- **Duration:** 1 min
- **Started:** 2026-04-10T03:49:48Z
- **Completed:** 2026-04-10T03:50:55Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- `copy-docker.sh`: full copy pipeline — Docker-stopped guard, space guard, background cp -c with progress bar, ditto fallback on failure, dual-metric post-copy verification, original-untouched check
- `verify-copy.sh`: independent read-only verification — four checks (dest exists, logical size, on-disk size, source unchanged), Phase 3 gate message on each exit path
- Both scripts follow Phase 1 conventions exactly: `set -euo pipefail`, PASS/FAIL/INFO output format, helper function pattern

## Task Commits

Each task was committed atomically:

1. **Task 1: Create copy-docker.sh** - `00de7fc` (feat)
2. **Task 2: Create verify-copy.sh** - `510f9f0` (feat)

**Plan metadata:** (created after this summary)

## Files Created/Modified

- `.planning/phases/02-data-copy/copy-docker.sh` - Main copy script: Docker-stopped guard, optional space guard, background cp -c with 5s polling progress bar, ditto fallback, dual-metric post-copy verification, source-untouched check, PASS/FAIL summary
- `.planning/phases/02-data-copy/verify-copy.sh` - Independent read-only verification: destination existence, logical size (stat -f %z), on-disk size with 1% tolerance (du -sk), source still present; exits 0 only if all pass

## Decisions Made

- Used `du -sk` for progress polling (not `ls -la`) — du reports committed on-disk blocks written so far; ls always reports full logical size from file creation
- Added `sleep 2` before verification — Open Question 1 from research: APFS may not flush metadata immediately after copy completes
- Applied 1% on-disk tolerance — Pitfall 3 from research: APFS transparent compression may cause small differences; tolerated with INFO note rather than FAIL
- `cleanup_partial()` prints before deleting — research anti-pattern: never delete silently, aids debugging if re-run after failure
- Docker-stopped guard re-verified at copy-docker.sh start — belt-and-suspenders; Phase 1 already confirmed, but conditions may have changed between phases

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required. Scripts are ready for live execution when user is ready to perform Phase 2 (Docker must be stopped, /Volumes/Unitek-B must be mounted).

## Next Phase Readiness

- `copy-docker.sh` and `verify-copy.sh` are ready for live execution
- Run `copy-docker.sh` first (Docker must be fully stopped, external volume mounted)
- Run `verify-copy.sh` after copy completes for independent confirmation
- Both must pass before proceeding to Phase 3 (Cutover — changing Docker Desktop dataFolder setting)
- Phase 02-02 plan (live execution) gates on these scripts

---
*Phase: 02-data-copy*
*Completed: 2026-04-10*
