# Phase 2: Data Copy - Context

**Gathered:** 2026-04-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Safely duplicate Docker.raw from the internal disk to `/Volumes/Unitek-B/Docker/` while preserving APFS sparse structure, with visible progress and verified integrity. The original file on the internal disk is left untouched — deletion happens in Phase 4.

</domain>

<decisions>
## Implementation Decisions

### Copy method
- **D-01:** Primary copy command is `cp -c` (APFS clonefile semantics — preserves sparse structure cross-volume)
- **D-02:** Fallback copy command is `ditto` if `cp -c` fails (exit code non-zero). Both preserve APFS sparse metadata.
- **D-03:** Source path: `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` (confirmed in Phase 1)
- **D-04:** Destination path: `/Volumes/Unitek-B/Docker/Docker.raw`

### Progress visibility
- **D-05:** Copy runs in background; a polling loop checks destination file size with `du` every 5 seconds
- **D-06:** Progress displayed as percentage bar based on expected final on-disk size (24.1 GB from Phase 1 pre-flight results)
- **D-07:** Progress works identically for both `cp -c` and `ditto` fallback (same polling approach)

### Integrity verification
- **D-08:** Compare BOTH logical size (`stat -f %z`) AND on-disk size (`du -sk`) between source and destination
- **D-09:** Logical size comparison catches truncation; on-disk size comparison catches sparse-to-dense inflation
- **D-10:** Verification is fast (seconds, not minutes) — no SHA256 checksums (explicitly out of scope per REQUIREMENTS.md)

### Failure & rollback behavior
- **D-11:** On copy failure: delete partial destination file, then retry ONCE
- **D-12:** On second failure: delete partial destination file, report error with details, abort
- **D-13:** Original file on internal disk is NEVER modified or deleted in this phase
- **D-14:** Consistent with Phase 1 hard-stop philosophy — no "continue anyway" on verification failure

### Claude's Discretion
- Script structure (single script vs split like Phase 1)
- Progress bar formatting (ASCII art, percentage, ETA)
- Exact polling interval (5 seconds is target, can adjust for UX)
- Whether to check disk space again before starting copy (pre-flight already verified, but belt-and-suspenders check is reasonable)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Docker Desktop data structure
- `.planning/research/STACK.md` — Tool inventory, settings file paths, DataFolder key details
- `.planning/research/ARCHITECTURE.md` — Docker Desktop data structure, component boundaries
- `.planning/research/PITFALLS.md` — Critical failure modes and prevention strategies

### Pre-flight results (Phase 1 outputs)
- `.planning/phases/01-pre-flight/preflight-results.txt` — Actual Docker.raw sizes, free space, backend confirmation
- `.planning/phases/01-pre-flight/preflight.sh` — Reference for Docker path resolution and validation patterns
- `.planning/phases/01-pre-flight/01-CONTEXT.md` — Phase 1 decisions (hard-stop philosophy, backup locations)

### Project context
- `.planning/PROJECT.md` — Core value, constraints, key decisions
- `.planning/REQUIREMENTS.md` — MIGR-01 through MIGR-04 acceptance criteria

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `preflight.sh` pattern: fail-fast bash script with `set -euo pipefail`, PASS/FAIL counters, colored output
- `verify-preflight.sh` pattern: independent verification script that re-checks results
- Docker path resolution: `DOCKER_SETTINGS_DIR=~/Library/Group\ Containers/group.com.docker`

### Established Patterns
- Shell scripts use `set -euo pipefail` and fail-fast ordering
- Status indicators: `[ PASS ]` / `[ FAIL ]` / `[ INFO ]` format
- All scripts in `.planning/phases/{phase_dir}/` directory
- Kebab-case script names, `#!/bin/bash` shebang

### Integration Points
- Source path confirmed by Phase 1 pre-flight (`DOCKER_RAW_PATH` variable in preflight.sh)
- Destination directory `/Volumes/Unitek-B/Docker/` already created and verified writable by Phase 1
- Copy result gates Phase 3 (Cutover) — must verify before changing DataFolder

</code_context>

<specifics>
## Specific Ideas

- User chose safety with one retry — not pure hard-stop like Phase 1, but conservative (handles transient I/O without being reckless)
- Both logical and on-disk size comparison gives high confidence without the 5+ minute SHA256 cost
- Phase 1 already confirmed 1495 GB free on external volume — ample headroom for 24.1 GB copy
- Apple Virtualization Framework backend confirmed — no `/host_mnt` path prefix concerns

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-data-copy*
*Context gathered: 2026-04-10*
