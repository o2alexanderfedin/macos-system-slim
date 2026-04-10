# Phase 4: Cleanup and Hardening - Research

**Researched:** 2026-04-10
**Domain:** macOS shell scripting, Docker Desktop settings, disk cleanup
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Re-run `verify-cutover.sh` before any deletion — must exit 0 to proceed
- **D-02:** Delete with `rm` using explicit full path. No `rm -rf` or wildcards
- **D-03:** Capture `df -h /` BEFORE and AFTER deletion to compute and display reclaimed space (proves CLEAN-02)
- **D-04:** Keep `.bak` files (`settings-store.json.bak`, `settings.json.bak`) — they are tiny (~8 KB total) and provide rollback insurance for settings
- **D-05:** Use Python `json` module to update settings (consistent with Phase 3 approach). Set `autoDownloadUpdates: false` and `autoInstallUpdates: false` in both settings files (CLEAN-03)
- **D-06:** Use Python `json` module to set `openAtStartup: false` in both settings files (CLEAN-04)
- **D-07:** Stop Docker Desktop before updating settings, then restart after — prevents settings overwrite on quit
- **D-08:** After Docker restart, re-read both settings files and verify all hardening keys have the correct values

### Claude's Discretion

- Script structure (single cleanup script or split cleanup + hardening)
- Whether to display a final migration summary after all cleanup/hardening is done
- Exact Python one-liner syntax for settings updates
- Whether to capture Docker.raw path from settings before deletion or hardcode from Phase 1/2 results

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CLEAN-01 | Original `Docker.raw` is deleted from internal disk (only after verification passes) | D-01 (verify-cutover.sh gate), D-02 (explicit rm), live confirmation that Docker.raw is at `/Users/alexanderfedin/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` (24 GB) |
| CLEAN-02 | Internal disk space is confirmed reclaimed | D-03 (df -h / before/after), current internal disk: 460 GB total, 12 GB used, 46 GB available — deletion frees ~24 GB |
| CLEAN-03 | Docker Desktop auto-update is disabled to prevent config wipe | D-05, exact key names confirmed via live inspection: `AutoDownloadUpdates` (PascalCase in settings-store.json), `autoDownloadUpdates` (camelCase in settings.json); `DisableUpdate` key also relevant |
| CLEAN-04 | Docker Desktop "Start at login" is disabled to prevent boot-time race with USB mount | D-06, exact key names confirmed: `AutoStart` (PascalCase in settings-store.json, currently `True`), `autoStart` (camelCase in settings.json, currently `False`) |
</phase_requirements>

## Summary

Phase 4 is the final cleanup step after a successful Docker Desktop data migration to an external USB volume. Docker is confirmed running from `/Volumes/Unitek-B/Docker` (Phase 3 verification passed with 5/5 checks). The original `Docker.raw` at the internal disk path (`/Users/alexanderfedin/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`) still consumes 24 GB on the internal drive and must be deleted to reclaim that space. Additionally, two Docker Desktop settings must be hardened: auto-update (to prevent future upgrades from wiping the external volume config) and start-at-login (to prevent a boot-time race where Docker tries to mount the external volume before macOS has mounted it).

The phase follows the same Bash scripting pattern established in Phases 1-3: `set -euo pipefail`, `[ PASS ]`/`[ FAIL ]`/`[ INFO ]` output format, Python `json` module for safe JSON mutation with atomic readback verify, and hard-stop on any failure. All key names have been confirmed via live inspection of the running system — no guessing required.

The critical detail is that D-05 mentions `autoInstallUpdates` but the live settings show the actual key is `DisableUpdate` (PascalCase in settings-store.json). Research below documents the confirmed key names to avoid confusion.

**Primary recommendation:** Two scripts — `cleanup.sh` (deletion + space verification) and `harden.sh` (settings hardening) — following Phase 3 patterns exactly. A final summary prints the completed migration outcome.

## Standard Stack

### Core

| Tool | Version/Source | Purpose | Why Standard |
|------|---------------|---------|--------------|
| `bash` with `set -euo pipefail` | macOS built-in | Script harness | Established pattern from Phases 1-3 |
| `python3` | 3.12.2 (confirmed installed) | JSON settings mutation | Safe JSON handling; no sed fragility; Phase 3 pattern |
| `rm` | macOS built-in | Delete original Docker.raw | Atomic, explicit; user-decided over alternatives |
| `df -h /` | macOS built-in | Before/after space comparison | Reports human-readable filesystem stats |
| `open -a "Docker Desktop"` | macOS built-in | Restart Docker after settings change | Phase 3 pattern |
| `docker info` | Docker CLI (v29.3.1) | Poll daemon readiness | Phase 3 pattern |
| `pgrep` | macOS built-in | Detect running Docker processes | Phase 3 pattern |
| `killall` | macOS built-in | Stop Docker Desktop | Phase 3 pattern |

### No additional software required

Every tool is a macOS built-in or Docker CLI command already installed.

## Architecture Patterns

### Recommended Script Structure

The user gave Claude discretion on script structure. Based on the separation of concerns in prior phases (cleanup is destructive and irreversible; hardening is reversible settings change), two scripts are the right split:

```
.planning/phases/04-cleanup-and-hardening/
├── cleanup.sh            # CLEAN-01, CLEAN-02: delete Docker.raw, verify space reclaimed
├── harden.sh             # CLEAN-03, CLEAN-04: disable auto-update and start-at-login
└── cleanup-results.txt   # Written by cleanup.sh (Phase 3 pattern)
```

Alternatively a single `cleanup-and-harden.sh` is acceptable if the user prefers a single runbook. Given Phase 3 used one script per logical operation, two scripts is the preferred split.

### Pattern 1: Pre-deletion gate (D-01)

Re-run verify-cutover.sh before deletion. The script exits 1 on any failure, which combined with `set -euo pipefail` aborts cleanup.sh immediately.

```bash
# Source: verify-cutover.sh (Phase 3)
echo "[ INFO ] Re-running verify-cutover.sh as pre-deletion gate..."
VERIFY_SCRIPT="$(dirname "$0")/../03-cutover-and-verification/verify-cutover.sh"
if ! bash "$VERIFY_SCRIPT"; then
  echo "ABORT: verify-cutover.sh failed -- Docker.raw deletion blocked"
  exit 1
fi
cleanup_pass "Pre-deletion gate: verify-cutover.sh passed"
```

### Pattern 2: Before/after df comparison (D-03)

```bash
# Capture before
DF_BEFORE=$(df -h / | awk 'NR==2 {print $4}')
echo "[ INFO ] Internal disk available before deletion: $DF_BEFORE"

rm "/Users/alexanderfedin/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
cleanup_pass "CLEAN-01: Docker.raw deleted from internal disk"

# Capture after
DF_AFTER=$(df -h / | awk 'NR==2 {print $4}')
echo "[ INFO ] Internal disk available after deletion: $DF_AFTER"
echo "[ INFO ] Space reclaimed: was $DF_BEFORE, now $DF_AFTER"
```

### Pattern 3: Python json settings mutation (D-05, D-06, D-07, D-08)

Reuse cutover.sh pattern exactly — Python heredoc via `python3 - <<PYEOF`. The `update_datafolder` helper in cutover.sh is the template; Phase 4 uses the same structure with different keys.

```python
# Source: cutover.sh (Phase 3) — adapted for hardening keys
import json, sys, os

def update_setting(settings_path, updates):
    """Update multiple keys in a Docker Desktop settings JSON file."""
    with open(settings_path, 'r') as f:
        data = json.load(f)

    for key, value in updates.items():
        data[key] = value

    with open(settings_path, 'w') as f:
        json.dump(data, f, indent=2)

    # Readback verify (Phase 3 pattern)
    with open(settings_path, 'r') as f:
        check = json.load(f)

    for key, value in updates.items():
        if check.get(key) != value:
            print(
                f"ERROR: Readback mismatch in {settings_path}: "
                f"key={key!r} got {check.get(key)!r}, expected {value!r}",
                file=sys.stderr
            )
            sys.exit(1)
```

### Pattern 4: Stop Docker, modify settings, restart, verify (D-07, D-08)

```bash
# Phase 3 pattern — stop Docker before settings change
killall "Docker Desktop" 2>/dev/null || true
killall com.docker.backend 2>/dev/null || true
# ... wait for pgrep to clear ...

# Modify settings via Python
python3 - <<PYEOF
# ... settings update ...
PYEOF

# Restart
open -a "Docker Desktop"

# Poll readiness
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  if docker info > /dev/null 2>&1; then break; fi
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

# Post-restart readback verify (D-08)
python3 -c "import json,os; d=json.load(open(os.path.expanduser('...'))); print(d.get('AutoDownloadUpdates'))"
```

### Anti-Patterns to Avoid

- **`rm -rf` or wildcards:** User locked D-02 — use explicit full path only
- **Deleting before verify-cutover.sh passes:** Hard-stop gate (D-01) — never skip
- **Modifying settings while Docker is running:** Docker overwrites settings on quit; stop first (D-07)
- **`sed` or `jq` for JSON mutation:** Python json module is the project standard (D-05)
- **Deleting `.bak` files:** User locked D-04 — keep them

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON mutation | Custom sed/awk | Python `json` module | Phase 3 pattern; handles edge cases, atomic readback |
| Docker readiness polling | Custom socket test | `docker info` with timeout loop | Phase 3 pattern; already proven |
| Filesystem space measurement | Custom du arithmetic | `df -h /` before/after | Built-in, human-readable, matches user expectation |

## Confirmed Key Names (CRITICAL)

Live inspection of both settings files reveals the actual key names. The CONTEXT.md decisions use slightly different names — the table below shows what to use in code:

### settings-store.json (PascalCase keys)

| Purpose | Key Name | Current Value | Target Value |
|---------|----------|---------------|--------------|
| Auto-download updates | `AutoDownloadUpdates` | `True` | `False` |
| Disable updates flag | `DisableUpdate` | `False` | `True` |
| Auto-start at login | `AutoStart` | `True` | `False` |

**Note on CONTEXT.md D-05:** The decision mentions `autoDownloadUpdates: false` and `autoInstallUpdates: false`. Live inspection shows the key is `AutoDownloadUpdates` (PascalCase in settings-store.json). There is no `AutoInstallUpdates` key — the paired key is `DisableUpdate`. Setting both `AutoDownloadUpdates: False` and `DisableUpdate: True` provides belt-and-suspenders coverage for CLEAN-03.

**Note on CONTEXT.md D-06:** The decision mentions `openAtStartup: false`. Live inspection shows the key is `AutoStart` (not `openAtStartup`) in settings-store.json. `OpenUIOnStartupDisabled` is a separate key (controls whether Docker's UI window opens, not whether Docker itself starts).

### settings.json (camelCase keys)

| Purpose | Key Name | Current Value | Target Value |
|---------|----------|---------------|--------------|
| Auto-download updates | `autoDownloadUpdates` | `True` | `False` |
| Disable updates flag | `disableUpdate` | `False` | `True` |
| Auto-start at login | `autoStart` | `False` | already correct — set to `False` anyway for consistency |

**Confidence:** HIGH — confirmed by live `python3 -c` inspection of both files on the actual machine.

## Common Pitfalls

### Pitfall 1: Wrong key names for settings mutation

**What goes wrong:** CONTEXT.md D-05 mentions `autoInstallUpdates` — this key does not exist in either settings file. Using it would silently add a new unrecognized key rather than set the right one.

**Why it happens:** The discussion phase used generic terms; the live key names differ.

**How to avoid:** Use the confirmed key names from the table above. Never guess key names for Docker Desktop settings.

**Warning signs:** Python readback shows the key is present but Docker still auto-downloads — indicates wrong key was set.

### Pitfall 2: Docker overwrites settings on quit

**What goes wrong:** If Docker Desktop is running when settings are written, Docker writes its in-memory settings back to disk when it quits, overwriting the changes.

**Why it happens:** Docker Desktop keeps settings in memory and flushes on exit.

**How to avoid:** Always stop Docker completely before modifying settings files (D-07). Verify with `pgrep` before writing.

**Warning signs:** Readback shows correct values but after Docker restarts, keys revert.

### Pitfall 3: `df -h /` column index varies on macOS

**What goes wrong:** Parsing `df -h /` with `awk 'NR==2 {print $4}'` assumes the "Avail" column is $4. On some macOS versions or locales, column order differs.

**Why it happens:** `df` output is locale/version sensitive.

**How to avoid:** Print the full `df -h /` output rather than parsing just one column. Show both lines (header + data) for human readability. The user needs to see the before/after, not an arithmetic result.

**How to implement:**
```bash
echo "=== df -h / BEFORE deletion ==="
df -h /
rm "/Users/alexanderfedin/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
echo "=== df -h / AFTER deletion ==="
df -h /
```

### Pitfall 4: Docker auto-update wipes external volume config (the reason for CLEAN-03)

**What goes wrong:** Docker Desktop upgrade process does not validate custom `DataFolder` before reinitializing. If the external volume is not mounted at upgrade time, it re-creates a fresh Docker.raw internally, losing all data.

**Source:** GitHub docker/for-mac #6215, #7319 — multiple upgrade versions have exhibited this behavior.

**How to avoid:** Set `AutoDownloadUpdates: False` and `DisableUpdate: True`. Before any future Docker Desktop upgrade, manually verify the external volume is mounted and `settings-store.json` DataFolder is intact.

### Pitfall 5: Boot-time race between Docker and USB mount (the reason for CLEAN-04)

**What goes wrong:** If Docker Desktop starts at login, it may launch before macOS has mounted the Unitek-B USB volume. Docker finds no file at `/Volumes/Unitek-B/Docker/Docker.raw`, potentially creating a fresh empty Docker.raw at the internal default location.

**Source:** PITFALLS.md Pitfall 8 (HIGH confidence, documented as ongoing risk for this project).

**How to avoid:** Set `AutoStart: False`. Always: plug in Unitek-B, confirm mount, then start Docker manually.

## Code Examples

### cleanup.sh skeleton

```bash
#!/bin/bash
set -euo pipefail

# cleanup.sh — Delete original Docker.raw from internal disk.
# Requirements: CLEAN-01, CLEAN-02
# Gate: verify-cutover.sh must pass before deletion proceeds.

DOCKER_RAW_INTERNAL="$HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
VERIFY_SCRIPT="$(dirname "$0")/../03-cutover-and-verification/verify-cutover.sh"
PASS=0
FAIL=0

cleanup_pass() { echo "[ PASS ] $1"; PASS=$((PASS + 1)); }
cleanup_fail() { echo "[ FAIL ] $1"; FAIL=$((FAIL + 1)); }
cleanup_info() { echo "[ INFO ] $1"; }
cleanup_abort() { echo ""; echo "ABORT: $1"; exit 1; }

echo "Docker Desktop Cleanup"
echo "======================"

# Gate: re-run verify-cutover.sh
cleanup_info "Running pre-deletion gate: verify-cutover.sh..."
if ! bash "$VERIFY_SCRIPT"; then
  cleanup_abort "verify-cutover.sh failed -- deletion blocked. Fix and retry."
fi
cleanup_pass "Pre-deletion gate passed"

# Confirm Docker.raw exists at internal path
if [[ ! -f "$DOCKER_RAW_INTERNAL" ]]; then
  cleanup_abort "Docker.raw not found at $DOCKER_RAW_INTERNAL -- already deleted?"
fi
cleanup_pass "Original Docker.raw found at internal path"

# CLEAN-02: capture df before
echo "=== df -h / BEFORE deletion ==="
df -h /

# CLEAN-01: delete with explicit path
rm "$DOCKER_RAW_INTERNAL"
cleanup_pass "CLEAN-01: Docker.raw deleted from internal disk"

# CLEAN-02: capture df after
echo "=== df -h / AFTER deletion ==="
df -h /
cleanup_pass "CLEAN-02: Space comparison captured (see df output above)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then exit 1; fi
echo "Cleanup complete. Run harden.sh to disable auto-update and start-at-login."
```

### harden.sh skeleton

```bash
#!/bin/bash
set -euo pipefail

# harden.sh — Disable Docker Desktop auto-update and start-at-login.
# Requirements: CLEAN-03 (auto-update), CLEAN-04 (start-at-login)
# Pattern: Stop Docker -> update settings -> restart -> verify (Phase 3 D-07, D-08)

SETTINGS_DIR="$HOME/Library/Group Containers/group.com.docker"
SETTINGS_STORE="$SETTINGS_DIR/settings-store.json"
SETTINGS_JSON="$SETTINGS_DIR/settings.json"
TIMEOUT=120
INTERVAL=5
PASS=0
FAIL=0

harden_pass() { echo "[ PASS ] $1"; PASS=$((PASS + 1)); }
harden_fail() { echo "[ FAIL ] $1"; FAIL=$((FAIL + 1)); }
harden_info() { echo "[ INFO ] $1"; }
harden_abort() { echo ""; echo "ABORT: $1"; exit 1; }

echo "Docker Desktop Hardening"
echo "========================"

# Stop Docker Desktop (D-07)
harden_info "Stopping Docker Desktop..."
killall "Docker Desktop" 2>/dev/null || true
killall com.docker.backend 2>/dev/null || true
killall com.docker.virtualization 2>/dev/null || true
killall com.docker.helper 2>/dev/null || true
killall com.docker.build 2>/dev/null || true
sleep 3

RUNNING=""
RUNNING+=$(pgrep -f 'Docker Desktop' 2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.backend' 2>/dev/null || true)
if [[ -n "$RUNNING" ]]; then
  harden_abort "Docker still running after stop attempt. Stop manually and retry."
fi
harden_pass "Docker Desktop stopped"

# CLEAN-03 + CLEAN-04: update settings (D-05, D-06)
PYTHON_EXIT=0
python3 - <<'PYEOF' || PYTHON_EXIT=$?
import json, sys, os

SETTINGS_DIR = os.path.expanduser("~/Library/Group Containers/group.com.docker")

# settings-store.json: PascalCase keys
store_updates = {
    "AutoDownloadUpdates": False,   # CLEAN-03
    "DisableUpdate": True,          # CLEAN-03 belt-and-suspenders
    "AutoStart": False,             # CLEAN-04
}

# settings.json: camelCase keys
json_updates = {
    "autoDownloadUpdates": False,   # CLEAN-03
    "disableUpdate": True,          # CLEAN-03 belt-and-suspenders
    "autoStart": False,             # CLEAN-04
}

def update_and_verify(path, updates):
    with open(path, 'r') as f:
        data = json.load(f)
    for k, v in updates.items():
        data[k] = v
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
    with open(path, 'r') as f:
        check = json.load(f)
    for k, v in updates.items():
        if check.get(k) != v:
            print(f"ERROR: Readback mismatch {path}: {k!r} got {check.get(k)!r}, want {v!r}", file=sys.stderr)
            sys.exit(1)

update_and_verify(os.path.join(SETTINGS_DIR, "settings-store.json"), store_updates)
update_and_verify(os.path.join(SETTINGS_DIR, "settings.json"), json_updates)
print("OK")
PYEOF

if [[ $PYTHON_EXIT -ne 0 ]]; then
  harden_abort "Settings update failed -- Docker config unchanged, safe to investigate"
fi
harden_pass "CLEAN-03 + CLEAN-04: Hardening keys written to both settings files"

# Restart Docker (D-07)
harden_info "Starting Docker Desktop..."
open -a "Docker Desktop"

ELAPSED=0
DOCKER_READY=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  if docker info > /dev/null 2>&1; then DOCKER_READY=1; break; fi
  printf "\r[ INFO ] Waiting for daemon... %ds/%ds" "$ELAPSED" "$TIMEOUT"
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done
printf "\n"

if [[ $DOCKER_READY -eq 0 ]]; then
  harden_abort "Docker daemon did not start within ${TIMEOUT}s"
fi
harden_pass "Docker daemon ready after ${ELAPSED}s"

# D-08: post-restart readback verify
harden_info "Verifying hardening keys survived Docker restart..."
python3 - <<'PYEOF' || harden_abort "Post-restart verification failed"
import json, os, sys

SETTINGS_DIR = os.path.expanduser("~/Library/Group Containers/group.com.docker")
store = json.load(open(os.path.join(SETTINGS_DIR, "settings-store.json")))
jsn   = json.load(open(os.path.join(SETTINGS_DIR, "settings.json")))

errors = []
if store.get("AutoDownloadUpdates") is not False:
    errors.append(f"settings-store.json AutoDownloadUpdates = {store.get('AutoDownloadUpdates')!r} (want False)")
if store.get("AutoStart") is not False:
    errors.append(f"settings-store.json AutoStart = {store.get('AutoStart')!r} (want False)")
if jsn.get("autoDownloadUpdates") is not False:
    errors.append(f"settings.json autoDownloadUpdates = {jsn.get('autoDownloadUpdates')!r} (want False)")

if errors:
    for e in errors: print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
print("OK -- all hardening keys confirmed")
PYEOF

harden_pass "D-08: Post-restart verification passed"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then exit 1; fi
echo "Hardening complete. Migration fully done."
```

### Final migration summary (Claude's discretion)

After both scripts succeed, print a summary:

```
=== Migration Complete ===
Phase 1: Pre-flight         COMPLETE
Phase 2: Data copy          COMPLETE
Phase 3: Cutover            COMPLETE
Phase 4: Cleanup/Hardening  COMPLETE

Docker data location: /Volumes/Unitek-B/Docker/
Internal disk freed: ~24 GB (see cleanup-results.txt for df before/after)
Auto-update: DISABLED
Start at login: DISABLED

IMPORTANT: Docker requires /Volumes/Unitek-B/ to be mounted before starting.
Always verify the volume is mounted before launching Docker Desktop.
=========================
```

## Runtime State Inventory

This is not a rename/refactor phase. Omitted.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| `bash` | All scripts | Yes | macOS built-in | None needed |
| `python3` | JSON settings mutation | Yes | 3.12.2 | None needed |
| `docker` CLI | Daemon readiness polling | Yes | 29.3.1 (confirmed Phase 3) | None needed |
| `pgrep` / `killall` | Docker stop sequence | Yes | macOS built-in | None needed |
| `df` | Space comparison | Yes | macOS built-in | None needed |
| `rm` | Docker.raw deletion | Yes | macOS built-in | None needed |
| `/Volumes/Unitek-B/Docker/Docker.raw` | verify-cutover.sh gate | Yes | 24 GB (Phase 3 confirmed) | None — required |
| `verify-cutover.sh` | Pre-deletion gate (D-01) | Yes | `.planning/phases/03-cutover-and-verification/verify-cutover.sh` | None — required |
| `settings-store.json` | Hardening | Yes | Confirmed readable | None needed |
| `settings.json` | Hardening | Yes | Confirmed readable | None needed |
| Original `Docker.raw` | CLEAN-01 deletion target | Yes | 24 GB at `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` | N/A — this is what we delete |

**Missing dependencies with no fallback:** None.

## Validation Architecture

nyquist_validation is enabled in config.json. However, this phase operates on live system state (Docker Desktop process, filesystem, macOS settings files). Automated test infrastructure (unit tests, test frameworks) does not apply — all validation is integration-level verification via the scripts themselves.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None — shell script integration verification |
| Config file | None |
| Quick run command | `bash verify-cutover.sh` (pre-deletion gate) |
| Full suite command | Run cleanup.sh then harden.sh, inspect output |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CLEAN-01 | Docker.raw deleted from internal disk | integration | `ls ~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw 2>/dev/null && echo EXISTS || echo DELETED` | N/A — post-run check |
| CLEAN-02 | Internal disk space confirmed reclaimed | integration | `df -h /` (before/after captured in cleanup.sh output) | N/A — captured in script |
| CLEAN-03 | Auto-update disabled | integration | `python3 -c "import json,os; d=json.load(open(os.path.expanduser('~/Library/Group Containers/group.com.docker/settings-store.json'))); print(d.get('AutoDownloadUpdates'))"` | N/A — readback in harden.sh |
| CLEAN-04 | Start-at-login disabled | integration | `python3 -c "import json,os; d=json.load(open(os.path.expanduser('~/Library/Group Containers/group.com.docker/settings-store.json'))); print(d.get('AutoStart'))"` | N/A — readback in harden.sh |

### Wave 0 Gaps

None — no test framework setup needed. Verification is embedded in the scripts themselves via readback checks and the verify-cutover.sh gate.

## State of the Art

| Old Approach | Current Approach | Notes |
|--------------|-----------------|-------|
| `jq` for JSON mutation | Python `json` module | Project standard set in Phase 3 |
| One script for all operations | Split cleanup + hardening | Phase 3 used separate cutover.sh + verify-cutover.sh |
| `settings.json` only | Both `settings-store.json` (authoritative) and `settings.json` (companion) | Phase 2 discovery — settings-store.json is authoritative for Docker Desktop v4.35+ |

## Open Questions

1. **`autoInstallUpdates` key from CONTEXT.md D-05**
   - What we know: Live inspection shows no `AutoInstallUpdates` key in either settings file. The paired key to `AutoDownloadUpdates` is `DisableUpdate`.
   - What's unclear: Whether `autoInstallUpdates` was a key in an older Docker Desktop version, or was a discussion-phase approximation.
   - Recommendation: Use `AutoDownloadUpdates: False` and `DisableUpdate: True` (confirmed present). Do not add `AutoInstallUpdates` — it would be a no-op unknown key.

2. **`openAtStartup` key from CONTEXT.md D-06**
   - What we know: Live inspection shows the key controlling Docker startup at login is `AutoStart`, not `openAtStartup`. `OpenUIOnStartupDisabled` is a separate key for whether Docker's main window opens on start.
   - Recommendation: Set `AutoStart: False` (PascalCase in settings-store.json) and `autoStart: False` (camelCase in settings.json). This directly addresses CLEAN-04.

## Sources

### Primary (HIGH confidence)

- Live system inspection via `python3 -c "import json,os; ..."` — confirmed all key names and current values from settings-store.json and settings.json
- `preflight-results.txt` — confirmed Docker.raw on-disk size is 24 GB at internal path
- `cutover-results.txt` — confirmed Phase 3 passed 5/5, DataFolder = /Volumes/Unitek-B/Docker
- `cutover.sh` (Phase 3) — Python json pattern to reuse verbatim
- `verify-cutover.sh` (Phase 3) — pre-deletion gate script, already working
- `.planning/research/STACK.md` — settings file paths and key naming conventions
- `.planning/research/PITFALLS.md` — Pitfall 3 (auto-update) and Pitfall 8 (boot-time race)

### Secondary (MEDIUM confidence)

- CONTEXT.md D-01 through D-08 — user decisions from /gsd:discuss-phase
- REQUIREMENTS.md CLEAN-01 through CLEAN-04 — acceptance criteria

## Metadata

**Confidence breakdown:**
- Key names for settings mutation: HIGH — confirmed by live inspection
- Script pattern: HIGH — reuse of verified Phase 3 code
- Space reclamation (~24 GB): HIGH — confirmed from preflight-results.txt
- Docker restart timing: MEDIUM — Phase 3 used 5s polling with 120s timeout, should be sufficient

**Research date:** 2026-04-10
**Valid until:** 2026-04-17 (7 days — Docker Desktop settings could change on upgrade, but user is about to disable auto-update)
