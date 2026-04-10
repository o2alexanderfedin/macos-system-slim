---
phase: 04-cleanup-and-hardening
plan: 01
subsystem: infra
tags: [bash, docker, macos, shell-scripts, json, python]

requires:
  - phase: 03-cutover-and-verification
    provides: verify-cutover.sh pre-deletion gate and cutover.sh Python json pattern

provides:
  - cleanup.sh: safe Docker.raw deletion from internal disk with verify-cutover gate and df before/after
  - harden.sh: Docker Desktop auto-update and start-at-login hardening with stop-modify-restart-verify

affects:
  - 04-02 plan: these scripts are what the human runs in Plan 02 execution

tech-stack:
  added: []
  patterns:
    - "cleanup_pass/cleanup_fail/cleanup_info/cleanup_abort helper pattern (extends Phase 1-3 pattern)"
    - "harden_pass/harden_fail/harden_info/harden_abort helper pattern"
    - "Python json heredoc with readback verify for settings mutation (reused from cutover.sh)"
    - "Pre-deletion gate: bash invoke verify-cutover.sh, abort on exit 1"
    - "Post-restart readback verify for hardening keys survived restart (D-08)"

key-files:
  created:
    - .planning/phases/04-cleanup-and-hardening/cleanup.sh
    - .planning/phases/04-cleanup-and-hardening/harden.sh
  modified: []

key-decisions:
  - "cleanup.sh gates on verify-cutover.sh (D-01): deletion blocked if Phase 3 verification fails"
  - "rm with explicit full path only -- no rm -rf, no wildcards (D-02)"
  - "df -h / captured BEFORE and AFTER deletion without column parsing (D-03, Pitfall 3)"
  - "harden.sh key names from live inspection: AutoDownloadUpdates/DisableUpdate/AutoStart (PascalCase), autoDownloadUpdates/disableUpdate/autoStart (camelCase)"
  - "D-08 post-restart readback verify added to confirm keys survived Docker Desktop startup flush"

patterns-established:
  - "Gate-before-destruct: always re-run verification before irreversible deletion"
  - "Stop-modify-restart-verify: required sequence for Docker Desktop settings changes"

requirements-completed: [CLEAN-01, CLEAN-02, CLEAN-03, CLEAN-04]

duration: 3min
completed: 2026-04-10
---

# Phase 4 Plan 01: Cleanup and Hardening Scripts Summary

**cleanup.sh (verify-cutover gate + df before/after rm) and harden.sh (stop Docker, Python json to set AutoDownloadUpdates=False/DisableUpdate=True/AutoStart=False, restart, D-08 post-restart verify)**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-04-10T06:13:50Z
- **Completed:** 2026-04-10T06:15:59Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Created cleanup.sh implementing CLEAN-01 and CLEAN-02: pre-deletion gate via verify-cutover.sh, explicit `rm` deletion, df before/after capture, .bak retention notice
- Created harden.sh implementing CLEAN-03 and CLEAN-04: stops Docker, updates both settings files with confirmed PascalCase/camelCase key names, restarts Docker, post-restart D-08 readback verify, final migration summary block
- Both scripts follow Phase 1-3 patterns exactly: set -euo pipefail, PASS/FAIL counters, helper functions, tee to results file

## Task Commits

1. **Task 1: Create cleanup.sh** - `54ad6de` (feat)
2. **Task 2: Create harden.sh** - `bb09114` (feat)

## Files Created/Modified

- `.planning/phases/04-cleanup-and-hardening/cleanup.sh` - Delete original Docker.raw with pre-deletion gate (verify-cutover.sh), before/after df capture, .bak retention note
- `.planning/phases/04-cleanup-and-hardening/harden.sh` - Disable auto-update and start-at-login with stop-modify-restart-verify pattern, post-restart D-08 readback confirm

## Decisions Made

- Used `df -h /` full output (both header and data rows) rather than parsing column 4 with awk, per Pitfall 3 in research — avoids locale/version sensitivity in `df` column order
- Used confirmed key names from live inspection (not CONTEXT.md approximations): `AutoDownloadUpdates`/`DisableUpdate`/`AutoStart` in settings-store.json (PascalCase), `autoDownloadUpdates`/`disableUpdate`/`autoStart` in settings.json (camelCase). Research explicitly warned that `autoInstallUpdates` and `openAtStartup` do not exist in either settings file
- Split into two scripts (cleanup.sh + harden.sh) per research recommendation: deletion is irreversible, hardening is reversible — separation makes each step independently auditable

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - both scripts passed bash -n syntax checks and all acceptance criteria on first pass. Key name confirmation from 04-RESEARCH.md prevented any wrong-key-name bugs.

## User Setup Required

None - no external service configuration required. These are operational scripts ready for human execution in Plan 02.

## Next Phase Readiness

- cleanup.sh and harden.sh are ready for Plan 02 execution
- Plan 02 is the human-run execution phase where the user actually runs these scripts against the live system
- cleanup.sh depends on: external volume mounted, Docker running from external volume, verify-cutover.sh passing
- harden.sh depends on: cleanup.sh completed successfully

## Self-Check: PASSED

All files confirmed present, all commits verified in git log.

---
*Phase: 04-cleanup-and-hardening*
*Completed: 2026-04-10*
