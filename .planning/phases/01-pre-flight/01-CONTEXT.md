# Phase 1: Pre-flight - Context

**Gathered:** 2026-04-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Verify the environment is ready for Docker data migration and back up settings before touching anything. This phase gates all subsequent phases — nothing proceeds until every pre-flight check passes.

</domain>

<decisions>
## Implementation Decisions

### Stop procedure
- **D-01:** Full kill sequence — quit Docker Desktop app, then `killall` all Docker-related processes, then verify with `pgrep`
- **D-02:** Hard block — if any Docker process is still running after kill sequence, abort pre-flight entirely. Do not proceed with migration while any Docker process could hold Docker.raw open.

### Backup strategy
- **D-03:** Back up BOTH `settings-store.json` AND `settings.json` (belt and suspenders — research says only settings-store.json matters for v29.3.1 but we back up both for safety)
- **D-04:** Backup location is same directory with `.bak` suffix: `settings-store.json.bak` and `settings.json.bak` in `~/Library/Group Containers/group.com.docker/`

### Validation depth
- **D-05:** Full validation — all 5 requirements PLUS verify Apple Virtualization Framework backend (not Docker VMM), resolve diskSizeMiB discrepancy, and check actual Docker.raw on-disk size with `du -sh`
- **D-06:** APFS verification via `diskutil info /Volumes/Unitek-B` — parse filesystem type from authoritative source
- **D-07:** Free space requirement is 2x actual Docker.raw size — accounts for growth during copy and future use
- **D-08:** Hard stop on ANY pre-flight failure — abort entire migration, fix the issue first, then re-run pre-flight. No "warn and continue" mode.

### Claude's Discretion
- Exact order of pre-flight checks (optimize for fail-fast — cheapest checks first)
- Specific pgrep patterns for Docker processes
- How to present pre-flight results to user (table, checklist, etc.)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Docker Desktop configuration
- `.planning/research/STACK.md` — Tool inventory, settings file paths, DataFolder key details
- `.planning/research/ARCHITECTURE.md` — Docker Desktop data structure, component boundaries
- `.planning/research/PITFALLS.md` — Critical failure modes and prevention strategies

### Project context
- `.planning/PROJECT.md` — Core value, constraints, key decisions
- `.planning/REQUIREMENTS.md` — PREFLT-01 through PREFLT-05 acceptance criteria

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- No application code relevant to this phase — this is a system administration task using macOS built-in tools

### Established Patterns
- Docker Desktop settings at `~/Library/Group Containers/group.com.docker/settings-store.json` (PascalCase keys: `DataFolder`)
- Docker Desktop companion settings at `~/Library/Group Containers/group.com.docker/settings.json` (camelCase keys: `dataFolder`)
- Docker data at path specified by `DataFolder` key (currently `/Users/alexanderfedin/Library/Containers/com.docker.docker/Data/vms/0/data`)

### Integration Points
- Pre-flight results gate Phase 2 (Data Copy) — all checks must pass
- Backup files are the rollback safety net for Phase 3 (Cutover)
- Virtualization backend check informs whether migration is safe at all (Docker VMM bug)

</code_context>

<specifics>
## Specific Ideas

- User explicitly chose safety, precision, and completeness as guiding principles for all pre-flight decisions
- Every check is hard-stop on failure — no soft warnings, no "continue anyway"
- Research identified diskSizeMiB discrepancy (settings-store.json: 32768 vs settings.json: 61035) — resolve during pre-flight by checking actual file size

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-pre-flight*
*Context gathered: 2026-04-09*
