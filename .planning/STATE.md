# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-09)

**Core value:** Docker data lives on the external volume so the internal disk is no longer constrained by Docker storage.
**Current focus:** Phase 1 — Pre-flight

## Current Position

Phase: 1 of 4 (Pre-flight)
Plan: 0 of ? in current phase
Status: Ready to plan
Last activity: 2026-04-09 — Roadmap created, requirements mapped, ready for Phase 1 planning

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: -
- Trend: -

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Use `dataFolder` setting over symlink: built-in Docker Desktop feature, cleaner than symlink hacks
- Migrate data instead of fresh start: preserve existing images and containers

### Pending Todos

None yet.

### Blockers/Concerns

- Research gap: Verify Docker VMM backend is Apple Virtualization Framework (not Docker VMM) before migrating. Docker VMM incorrectly prepends `/host_mnt` to external volume paths.
- Research gap: Confirm `cp -c` clonefile behavior across APFS volumes (may not be near-instant cross-device; only affects duration, not correctness).
- `diskSizeMiB` discrepancy: `settings-store.json` shows 32768; `settings.json` shows 61035 — actual on-disk size to be confirmed in Phase 1.

## Session Continuity

Last session: 2026-04-09
Stopped at: Roadmap written. STATE.md initialized. Ready to run /gsd:plan-phase 1.
Resume file: None
