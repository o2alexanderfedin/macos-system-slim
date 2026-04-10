# Phase 4: Cleanup and Hardening - Context

**Gathered:** 2026-04-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Delete the original Docker.raw from the internal disk to reclaim ~24 GB, and harden Docker Desktop settings to prevent auto-update config wipes and login-time race conditions with USB mount. The external volume copy is already verified and Docker is running from it (Phase 3 complete).

</domain>

<decisions>
## Implementation Decisions

### Deletion safety
- **D-01:** Re-run `verify-cutover.sh` before any deletion — must exit 0 to proceed. Consistent with hard-stop philosophy from Phases 1-3.
- **D-02:** Delete with `rm` using explicit full path. No `rm -rf` or wildcards.
- **D-03:** Capture `df -h /` BEFORE and AFTER deletion to compute and display reclaimed space (proves CLEAN-02).
- **D-04:** Keep `.bak` files (`settings-store.json.bak`, `settings.json.bak`) — they're tiny (~8 KB total) and provide rollback insurance for settings.

### Hardening configuration
- **D-05:** Use Python `json` module to update settings (consistent with Phase 3 approach). Set `autoDownloadUpdates: false` and `autoInstallUpdates: false` in both settings files (CLEAN-03).
- **D-06:** Use Python `json` module to set `openAtStartup: false` in both settings files (CLEAN-04).
- **D-07:** Stop Docker Desktop before updating settings, then restart after — prevents settings overwrite on quit. Same pattern as Phase 3.
- **D-08:** After Docker restart, re-read both settings files and verify all hardening keys have the correct values. Belt-and-suspenders verification.

### Claude's Discretion
- Script structure (single cleanup script or split cleanup + hardening)
- Whether to display a final migration summary after all cleanup/hardening is done
- Exact Python one-liner syntax for settings updates
- Whether to capture Docker.raw path from settings before deletion or hardcode from Phase 1/2 results

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Docker Desktop settings
- `.planning/research/STACK.md` — Settings file paths, key names (DataFolder, autoDownloadUpdates, openAtStartup)
- `.planning/research/PITFALLS.md` — Auto-update config wipe risk, login race condition

### Prior phase outputs
- `.planning/phases/01-pre-flight/01-CONTEXT.md` — Backup file locations (.bak suffix in same dir)
- `.planning/phases/03-cutover-and-verification/verify-cutover.sh` — Pre-deletion gate (must pass)
- `.planning/phases/03-cutover-and-verification/cutover.sh` — Python json update pattern to reuse

### Project context
- `.planning/PROJECT.md` — Core value, constraints
- `.planning/REQUIREMENTS.md` — CLEAN-01 through CLEAN-04 acceptance criteria

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `cutover.sh` Python json update pattern — exact same approach for settings modification
- `verify-cutover.sh` — pre-deletion gate script
- Phase 1/2/3 script patterns: `set -euo pipefail`, `[ PASS ]`/`[ FAIL ]` format, fail-fast

### Established Patterns
- Stop Docker → modify settings → restart Docker → verify (Phase 3 pattern)
- Python json module for safe JSON updates (Phase 3 pattern)
- Independent verification scripts that can be re-run safely

### Integration Points
- verify-cutover.sh must pass before deletion begins (Phase 3 → Phase 4 gate)
- Original Docker.raw path from Phase 1/2 results
- Settings file locations from Phase 1 research

</code_context>

<specifics>
## Specific Ideas

- User chose safety and precision: re-verify before destructive action, before/after df comparison
- Keep .bak files as insurance — the cost is negligible (8 KB)
- Hardening prevents two specific risks: (1) Docker auto-update could rewrite settings and reset DataFolder, (2) Docker start-at-login could fail if external volume isn't mounted yet at boot

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-cleanup-and-hardening*
*Context gathered: 2026-04-10*
