# Phase 3: Cutover and Verification - Context

**Gathered:** 2026-04-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Redirect Docker Desktop to use the external volume copy by updating settings-store.json, start Docker, and verify it runs correctly with data intact. The original Docker.raw on internal disk is NOT touched in this phase (deletion is Phase 4).

</domain>

<decisions>
## Implementation Decisions

### Settings update strategy
- **D-01:** Use Python `json` module to parse and update `settings-store.json`. Python is pre-installed on macOS and handles JSON safely (no risk of breaking formatting like sed).
- **D-02:** Update `DataFolder` key in `settings-store.json` to `/Volumes/Unitek-B/Docker`
- **D-03:** Also update `dataFolder` key in `settings.json` to `/Volumes/Unitek-B/Docker` for consistency (belt-and-suspenders)
- **D-04:** Verify the update by reading back the file and confirming the new value is correct before starting Docker

### Docker start & readiness
- **D-05:** Start Docker Desktop with `open -a "Docker Desktop"`
- **D-06:** Poll `docker info` every 5 seconds with a 120-second timeout to detect readiness
- **D-07:** `docker info` exit code 0 means daemon is fully ready — any non-zero means still starting or failed

### Pre-migration inventory
- **D-08:** Do NOT start Docker from old location to capture baseline — unnecessary complexity
- **D-09:** There is a Compose group that already fails to start (broken before migration). Failure of this group or any of its containers is expected and acceptable — do not treat as migration failure.
- **D-10:** Verify images exist with `docker images` (count should be > 0). Verify containers exist with `docker ps -a` (count should be > 0). Run `docker run --rm hello-world` as smoke test. These are sufficient without exact pre/post comparison.

### Rollback strategy
- **D-11:** No automatic rollback. If Docker fails to start from the new location: stop Docker, investigate the issue first. The .bak files exist as insurance but are not auto-restored.
- **D-12:** Report diagnostic info on failure: docker info output, Docker Desktop logs path, settings file contents — help user investigate rather than blindly reverting.
- **D-13:** Hard-stop on settings update failure (file not writable, Python error) — abort before starting Docker with a broken config.

### Claude's Discretion
- Script structure (single cutover script vs split cutover + verify)
- Exact Python one-liner syntax for JSON update
- Whether to capture image/container lists to a file for reference (recommended but not required)
- How to format verification results (follow Phase 1/2 `[ PASS ]`/`[ FAIL ]` pattern)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Docker Desktop configuration
- `.planning/research/STACK.md` — Tool inventory, settings file paths, DataFolder key details
- `.planning/research/ARCHITECTURE.md` — Docker Desktop data structure, component boundaries
- `.planning/research/PITFALLS.md` — Critical failure modes and prevention strategies

### Phase 1 outputs (backup locations)
- `.planning/phases/01-pre-flight/01-CONTEXT.md` — D-03/D-04: Backup file locations (same dir, .bak suffix)
- `.planning/phases/01-pre-flight/preflight.sh` — Docker settings directory path resolution

### Phase 2 outputs (copy verification)
- `.planning/phases/02-data-copy/02-CONTEXT.md` — Copy decisions and destination path
- `.planning/phases/02-data-copy/copy-results.txt` — Verified copy sizes and integrity

### Project context
- `.planning/PROJECT.md` — Core value, constraints, key decisions
- `.planning/REQUIREMENTS.md` — CONF-01, CONF-02, VERIF-01, VERIF-02, VERIF-03 acceptance criteria

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `preflight.sh` / `copy-docker.sh` pattern: `set -euo pipefail`, `[ PASS ]`/`[ FAIL ]`/`[ INFO ]` output format
- Docker settings directory: `~/Library/Group Containers/group.com.docker/`
- Docker process names from Phase 1: Docker Desktop, com.docker.backend, com.docker.virtualization, com.docker.helper, com.docker.build

### Established Patterns
- Fail-fast bash scripts with counters (PASS/FAIL)
- Independent verification scripts that can be re-run safely
- Scripts located in `.planning/phases/{phase_dir}/`
- Human checkpoints for critical state changes

### Integration Points
- Settings files backed up by Phase 1 (`.bak` files in Docker settings directory)
- Docker.raw copy verified by Phase 2 at `/Volumes/Unitek-B/Docker/Docker.raw`
- Cutover result gates Phase 4 (Cleanup) — Docker must be running from new location before deleting old data

</code_context>

<specifics>
## Specific Ideas

- User explicitly chose "investigate first" over auto-rollback — they want to understand failures, not mask them
- Existing Compose group is already broken — this is known and acceptable, not a migration failure indicator
- Python json module chosen over jq/sed for safety — JSON files must not be corrupted
- 120-second timeout for Docker readiness is generous — typical startup is 15-30 seconds

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-cutover-and-verification*
*Context gathered: 2026-04-10*
