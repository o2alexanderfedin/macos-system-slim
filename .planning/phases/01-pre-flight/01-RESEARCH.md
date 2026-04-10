# Phase 1: Pre-flight - Research

**Researched:** 2026-04-09
**Domain:** macOS system administration — Docker Desktop process management, APFS volume validation, JSON settings backup
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Stop procedure**
- **D-01:** Full kill sequence — quit Docker Desktop app, then `killall` all Docker-related processes, then verify with `pgrep`
- **D-02:** Hard block — if any Docker process is still running after kill sequence, abort pre-flight entirely. Do not proceed with migration while any Docker process could hold Docker.raw open.

**Backup strategy**
- **D-03:** Back up BOTH `settings-store.json` AND `settings.json` (belt and suspenders — research says only settings-store.json matters for v29.3.1 but we back up both for safety)
- **D-04:** Backup location is same directory with `.bak` suffix: `settings-store.json.bak` and `settings.json.bak` in `~/Library/Group Containers/group.com.docker/`

**Validation depth**
- **D-05:** Full validation — all 5 requirements PLUS verify Apple Virtualization Framework backend (not Docker VMM), resolve diskSizeMiB discrepancy, and check actual Docker.raw on-disk size with `du -sh`
- **D-06:** APFS verification via `diskutil info /Volumes/Unitek-B` — parse filesystem type from authoritative source
- **D-07:** Free space requirement is 2x actual Docker.raw size — accounts for growth during copy and future use
- **D-08:** Hard stop on ANY pre-flight failure — abort entire migration, fix the issue first, then re-run pre-flight. No "warn and continue" mode.

### Claude's Discretion

- Exact order of pre-flight checks (optimize for fail-fast — cheapest checks first)
- Specific pgrep patterns for Docker processes
- How to present pre-flight results to user (table, checklist, etc.)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PREFLT-01 | Docker Desktop is verified fully stopped (including menubar agent and background processes) | Kill sequence via `osascript` + `killall` documented; pgrep patterns verified against live system |
| PREFLT-02 | External volume `/Volumes/Unitek-B/` is verified as APFS format | `diskutil info` APFS check verified live — returns `Type (Bundle): apfs` |
| PREFLT-03 | External volume has sufficient free space for Docker.raw (~24 GB on-disk) | 2x 24.1 GB = 48.3 GB required; 1.6 TB available; `df -k` scripting pattern confirmed |
| PREFLT-04 | `settings-store.json` is backed up before any modifications | `cp` backup to `.bak` in same directory; both files confirmed present; no backup exists yet |
| PREFLT-05 | Target directory `/Volumes/Unitek-B/Docker/` is created and writable | Directory already exists and is writable (verified live); write test pattern documented |
</phase_requirements>

---

## Summary

Phase 1 is a pure system administration phase — no application code, no external libraries, no package installations. All tools are macOS built-ins (`diskutil`, `df`, `pgrep`, `killall`, `cp`, `osascript`, `python3`). The phase gates all subsequent migration phases and must produce zero ambiguous results: every check either hard-passes or hard-fails.

The live system environment has been directly inspected. Several pre-flight checks are already partially satisfied: the target directory `/Volumes/Unitek-B/Docker/` exists and is writable, the volume is confirmed APFS with 1.6 TB free (far exceeding the 48 GB 2x requirement), and Docker Desktop is using the Apple Virtualization Framework backend (not the buggy Docker VMM). The critical unsatisfied pre-condition is that Docker Desktop must be fully stopped before any other action, and settings backups do not yet exist.

The `diskSizeMiB` discrepancy (settings-store.json shows 32768; settings.json shows 61035) is now resolved by the live `du -sh` measurement: Docker.raw is 24.1 GB on-disk, 32 GB logical. The discrepancy is a stale settings.json value from an old disk limit. The authoritative on-disk size for planning purposes is **24.1 GB actual** (on-disk, sparse APFS) and **32 GB logical**.

**Primary recommendation:** Execute checks in fail-fast order — cheapest and most likely to fail first (process check), then volume format, then free space, then target writability, then backup creation.

---

## Standard Stack

### Core Tools (all macOS built-ins — no installation required)

| Tool | Purpose | Command Pattern |
|------|---------|----------------|
| `osascript` | Gracefully quit Docker Desktop app | `osascript -e 'quit app "Docker Desktop"'` |
| `killall` | Force-terminate remaining Docker processes | `killall -9 'Docker Desktop'` |
| `pgrep` | Verify Docker processes are dead | `pgrep -f "Docker Desktop"` → must return empty |
| `diskutil` | APFS format verification (authoritative) | `diskutil info /Volumes/Unitek-B` |
| `df` | Free space query (scriptable bytes) | `df -k /Volumes/Unitek-B` |
| `du` | Actual on-disk Docker.raw size (sparse-aware) | `du -sk /path/to/Docker.raw` |
| `cp` | Backup settings files | `cp settings-store.json settings-store.json.bak` |
| `python3` | JSON key extraction for settings verification | `python3 -m json.tool` or inline `-c` |
| `touch` + `rm` | Write permission test on target directory | `touch /Volumes/Unitek-B/Docker/.test && rm ...` |

### No External Dependencies

Every pre-flight operation uses macOS built-in tools. No Homebrew, no pip, no npm. This is by design — pre-flight must work on a clean macOS system with only Docker Desktop installed.

---

## Architecture Patterns

### Recommended Check Order (fail-fast, cheapest first)

```
1. PREFLT-01: Docker process check (< 1 second — instant)
   └── If any Docker process running → kill sequence → re-verify → HARD STOP if still running

2. PREFLT-02: APFS format check (< 1 second — diskutil query)
   └── If not APFS → HARD STOP (volume reformatting is out of scope)

3. PREFLT-03: Free space check (< 1 second — df query + arithmetic)
   └── If < 2x Docker.raw on-disk → HARD STOP

4. PREFLT-05: Target directory writable check (< 1 second — touch test)
   └── If /Volumes/Unitek-B/Docker/ absent → create it → retest
   └── If not writable → HARD STOP

5. PREFLT-04: Create settings backups (< 1 second — cp command)
   └── Verify .bak files exist after copy
   └── If cp fails → HARD STOP

6. D-05 Bonus checks: Virtualization backend + diskSizeMiB resolution + du on Docker.raw
   └── These are informational/confirmatory — still hard-stop if VF backend not confirmed
```

Rationale: The process check comes first because Docker holding Docker.raw open is the highest-risk condition and the cheapest to test. Format and space checks are read-only queries. Directory creation and backup creation are the only write operations and come last.

### Docker Kill Sequence (D-01 / D-02)

```bash
# Step 1: Graceful quit (app closes cleanly if running)
osascript -e 'quit app "Docker Desktop"' 2>/dev/null
sleep 3

# Step 2: Force-kill known Docker process names
killall -9 'Docker Desktop'          2>/dev/null
killall -9 'com.docker.backend'      2>/dev/null
killall -9 'com.docker.virtualization' 2>/dev/null
killall -9 'com.docker.helper'       2>/dev/null

# Step 3: Verify — all must return non-zero (no match)
pgrep -f 'Docker Desktop'       && FAIL="Docker Desktop still running"
pgrep -f 'com.docker.backend'   && FAIL="com.docker.backend still running"
pgrep -f 'com.docker.virtualization' && FAIL="com.docker.virtualization still running"
pgrep -f 'com.docker.helper'    && FAIL="com.docker.helper still running"

# D-02: Hard block if any process survived
[[ -n "$FAIL" ]] && echo "ABORT: $FAIL" && exit 1
```

**Process names confirmed** (from live inspection of `/Applications/Docker.app/Contents/MacOS/`):
- `Docker Desktop` — the Electron GUI app
- `com.docker.backend` — backend daemon
- `com.docker.virtualization` — VM manager
- `com.docker.helper` — privilege helper (runs via launchd `com.docker.helper`, state: `not running` when Docker stopped)

**Note:** `killall` exits with error code if the process is not found — use `2>/dev/null` to suppress noise. The verification step with `pgrep` is authoritative.

### APFS Verification (D-06)

```bash
# Authoritative check — parse from diskutil
FSTYPE=$(diskutil info /Volumes/Unitek-B 2>/dev/null | awk -F': ' '/Type \(Bundle\)/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')
[[ "$FSTYPE" == "apfs" ]] || { echo "ABORT: /Volumes/Unitek-B is $FSTYPE, not APFS"; exit 1; }
```

**Verified live:** `diskutil info /Volumes/Unitek-B | grep "Type (Bundle)"` returns `apfs` for the Unitek-B volume.

### Free Space Check (D-07 — 2x on-disk Docker.raw)

```bash
# Get Docker.raw actual on-disk size in KB (du -sk respects APFS sparse files)
DOCKER_RAW_KB=$(du -sk "/Users/alexanderfedin/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw" | awk '{print $1}')

# Require 2x on-disk size free
REQUIRED_KB=$((DOCKER_RAW_KB * 2))

# Get available space in KB on target volume
AVAIL_KB=$(df -k /Volumes/Unitek-B | awk 'NR==2 {print $4}')

[[ $AVAIL_KB -ge $REQUIRED_KB ]] || {
    echo "ABORT: Free space ${AVAIL_KB}KB < required ${REQUIRED_KB}KB (2x Docker.raw on-disk)"
    exit 1
}
```

**Current values (verified live):**
- Docker.raw on-disk: 25,334,824 KB (24.1 GB)
- Required (2x): 50,669,648 KB (~48.3 GB)
- Available on Unitek-B: 1,567,783,252 KB (~1,495 GB)
- Result: PASSES by a large margin

### Settings Backup (D-03 / D-04)

```bash
DOCKER_SETTINGS_DIR="$HOME/Library/Group Containers/group.com.docker"

cp "$DOCKER_SETTINGS_DIR/settings-store.json" "$DOCKER_SETTINGS_DIR/settings-store.json.bak"
cp "$DOCKER_SETTINGS_DIR/settings.json"       "$DOCKER_SETTINGS_DIR/settings.json.bak"

# Verify both .bak files exist
[[ -f "$DOCKER_SETTINGS_DIR/settings-store.json.bak" ]] || { echo "ABORT: settings-store.json backup failed"; exit 1; }
[[ -f "$DOCKER_SETTINGS_DIR/settings.json.bak" ]]       || { echo "ABORT: settings.json backup failed"; exit 1; }
```

**Current state:** Neither `.bak` file exists yet. Both source files exist and are readable.

### Target Directory Writability (PREFLT-05)

```bash
TARGET_DIR="/Volumes/Unitek-B/Docker"

# Create if absent
[[ -d "$TARGET_DIR" ]] || mkdir -p "$TARGET_DIR"

# Write test
TEST_FILE="$TARGET_DIR/.preflight_write_test"
touch "$TEST_FILE" && rm "$TEST_FILE" || { echo "ABORT: $TARGET_DIR is not writable"; exit 1; }
```

**Current state:** `/Volumes/Unitek-B/Docker/` already exists and is writable (verified live).

### Virtualization Backend Check (D-05)

```bash
# Confirm Apple VF, not Docker VMM
USE_VF=$(python3 -c "
import json, sys
with open('$HOME/Library/Group Containers/group.com.docker/settings-store.json') as f:
    d = json.load(f)
print(d.get('UseVirtualizationFramework', False))
")
[[ "$USE_VF" == "True" ]] || { echo "ABORT: Docker VMM backend detected — switch to Apple Virtualization Framework before migrating"; exit 1; }
```

**Current state:** `UseVirtualizationFramework: true` — Apple VF confirmed, Docker VMM NOT active. This is the safe state for external volume migration.

### diskSizeMiB Resolution (D-05)

The discrepancy between settings-store.json (`DiskSizeMiB: 32768`) and settings.json (`diskSizeMiB: 61035`) is now resolved:

- **Actual Docker.raw logical size:** 32 GB (34,359,738,368 bytes) — matches settings-store.json
- **Actual Docker.raw on-disk (sparse):** 24.1 GB — this is what matters for copy time and space
- **settings.json value of 61035:** A stale old disk limit from a previous configuration — not the current size
- **Planning numbers:** Use 24.1 GB on-disk for space/time calculations; 32 GB logical is the allocated VM disk size

Report this resolution in the pre-flight output so the user has a clear record.

### Pre-flight Results Presentation

Present results as a pass/fail checklist after all checks complete:

```
Pre-flight Check Results
========================
[ PASS ] PREFLT-01: Docker processes stopped (0 found)
[ PASS ] PREFLT-02: /Volumes/Unitek-B is APFS format
[ PASS ] PREFLT-03: Free space 1495 GB >= required 48 GB (2x Docker.raw on-disk 24.1 GB)
[ PASS ] PREFLT-04: Backups created: settings-store.json.bak, settings.json.bak
[ PASS ] PREFLT-05: /Volumes/Unitek-B/Docker/ exists and is writable
[ INFO ] Backend: Apple Virtualization Framework confirmed (not Docker VMM)
[ INFO ] Docker.raw logical: 32 GB | on-disk: 24.1 GB | diskSizeMiB discrepancy resolved

All pre-flight checks passed. Safe to proceed to Phase 2.
```

Any FAIL line triggers immediate abort with no further output.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON field extraction | Custom parser/regex | `python3 -c 'import json...'` | python3 ships with macOS, handles escaping correctly |
| Free space calculation | Manual arithmetic in awk | `df -k` + shell arithmetic | `df -k` gives 1024-byte blocks directly; avoid floating point |
| APFS detection | Checking volume name or mount flags | `diskutil info` → `Type (Bundle)` field | Authoritative source; `grep -i apfs` on other fields can false-match |
| Process verification | Checking activity monitor or `ps aux | grep docker` | `pgrep -f "process name"` | `pgrep` is purpose-built; `grep docker` in ps output can match grep itself |
| Graceful app quit | `kill PID` directly | `osascript -e 'quit app "Docker Desktop"'` | Gives app time to flush state; `kill` on Electron app leaves orphan processes |

---

## Common Pitfalls

### Pitfall 1: Checking `diskSizeMiB` Instead of `du -sh`
**What goes wrong:** Using the `diskSizeMiB` value from either settings file to estimate Docker.raw size gives the wrong number (61035 MiB in settings.json is stale; 32768 MiB in settings-store.json is the logical limit, not on-disk bytes).
**Why it happens:** Both values are configuration — not measurements of actual disk usage.
**How to avoid:** Always use `du -sk` on the actual Docker.raw file to get the real on-disk size. This is what matters for the 2x free space check.
**Warning signs:** If your free space requirement calculates to 64 GB instead of ~48 GB, you're using the logical size instead of the on-disk size.

### Pitfall 2: `pgrep` Returns False Negative for `com.docker.helper`
**What goes wrong:** `com.docker.helper` runs via launchd and may appear in launchctl list even when Docker is stopped (state: "not running"). `pgrep` on `com.docker.helper` returns nothing when the process is not actually running — this is correct behavior, not a bug.
**Why it happens:** launchd keeps service registrations alive even when the service process has exited. The launchctl listing shows the service record, not an active process.
**How to avoid:** Trust `pgrep -f com.docker.helper` — if it returns nothing, the process is not running. Do not use `launchctl list | grep docker` as evidence that Docker is still running.
**Warning signs:** Confusion between launchd service registration vs. active process.

### Pitfall 3: `killall` Error Code Causes Script Abort
**What goes wrong:** If Docker Desktop is already stopped when the kill sequence runs, `killall 'Docker Desktop'` exits with a non-zero code ("no matching processes"). A script with `set -e` aborts here.
**Why it happens:** `killall` treats "no processes found" as an error condition.
**How to avoid:** Always use `2>/dev/null` after each `killall` command. The kill sequence is idempotent — killing a non-running process is not an error from the script's perspective. Only `pgrep` at the end is authoritative.

### Pitfall 4: APFS Check on Wrong Field
**What goes wrong:** `diskutil info` output contains multiple lines mentioning filesystem-adjacent information (partition type UUID, container type, etc.). Grepping for "APFS" anywhere can false-match on a non-APFS volume that happens to be on an APFS container.
**Why it happens:** APFS Container Free Space appears even for volumes inside APFS containers that might individually be a different type.
**How to avoid:** Parse specifically `Type (Bundle):` field. If it equals `apfs`, the volume itself is APFS. This is the field used by Apple's own tools.
**Command:** `diskutil info /Volumes/Unitek-B | awk -F': ' '/Type \(Bundle\)/ {print $2}'`

### Pitfall 5: Backing Up to Wrong Location
**What goes wrong:** Backup `.bak` files created in a different directory (e.g., home directory, `/tmp`) are not in the rollback path that Phase 3 (Cutover) expects.
**Why it happens:** D-04 specifies same directory with `.bak` suffix. Creating backups elsewhere means Phase 3 tasks must be updated to find them.
**How to avoid:** Back up in-place: `cp settings-store.json settings-store.json.bak` — same directory, same name with `.bak` appended.

### Pitfall 6: Not Resolving diskSizeMiB Discrepancy Before Reporting
**What goes wrong:** If pre-flight passes without resolving the discrepancy, downstream phases may use different size estimates for planning the copy step, leading to inconsistent documentation.
**Why it happens:** The discrepancy exists in the source files and is confusing to anyone reading them.
**How to avoid:** Always report the `du -sh` measurement alongside the settings values in pre-flight output. State explicitly that 61035 MiB in settings.json is a stale value and 24.1 GB on-disk is the ground truth.

---

## Code Examples

### Full Pre-flight Script Skeleton

```bash
#!/bin/bash
set -euo pipefail

DOCKER_SETTINGS_DIR="$HOME/Library/Group Containers/group.com.docker"
DOCKER_RAW_PATH="$HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
TARGET_DIR="/Volumes/Unitek-B/Docker"
PASS=0; FAIL=0

preflight_pass() { echo "[ PASS ] $1"; ((PASS++)); }
preflight_fail() { echo "[ FAIL ] $1"; ((FAIL++)); }
preflight_info() { echo "[ INFO ] $1"; }
preflight_abort() { echo ""; echo "ABORT: $1"; echo "Fix the issue above, then re-run pre-flight."; exit 1; }

echo "Pre-flight Check Results"
echo "========================"

# ── PREFLT-01: Docker processes ──────────────────────────────────
osascript -e 'quit app "Docker Desktop"' 2>/dev/null; sleep 3
killall -9 'Docker Desktop'              2>/dev/null || true
killall -9 'com.docker.backend'          2>/dev/null || true
killall -9 'com.docker.virtualization'   2>/dev/null || true
killall -9 'com.docker.helper'           2>/dev/null || true

RUNNING=$(pgrep -f 'Docker Desktop' 2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.backend' 2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.virtualization' 2>/dev/null || true)
RUNNING+=$(pgrep -f 'com.docker.helper' 2>/dev/null || true)

if [[ -n "$RUNNING" ]]; then
    preflight_fail "PREFLT-01: Docker processes still running (PIDs: $RUNNING)"
    preflight_abort "Cannot proceed while Docker processes hold Docker.raw open (D-02)"
else
    preflight_pass "PREFLT-01: Docker processes stopped"
fi

# ── PREFLT-02: APFS format ───────────────────────────────────────
FSTYPE=$(diskutil info /Volumes/Unitek-B 2>/dev/null \
    | awk -F': ' '/Type \(Bundle\)/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')
if [[ "$FSTYPE" == "apfs" ]]; then
    preflight_pass "PREFLT-02: /Volumes/Unitek-B is APFS format"
else
    preflight_fail "PREFLT-02: /Volumes/Unitek-B is $FSTYPE, not APFS"
    preflight_abort "External volume must be APFS for Docker Desktop compatibility (D-06)"
fi

# ── PREFLT-03: Free space (2x Docker.raw on-disk) ────────────────
DOCKER_RAW_KB=$(du -sk "$DOCKER_RAW_PATH" | awk '{print $1}')
REQUIRED_KB=$((DOCKER_RAW_KB * 2))
AVAIL_KB=$(df -k /Volumes/Unitek-B | awk 'NR==2 {print $4}')
DOCKER_RAW_GB=$(echo "scale=1; $DOCKER_RAW_KB / 1048576" | bc)
REQUIRED_GB=$(echo "scale=1; $REQUIRED_KB / 1048576" | bc)
AVAIL_GB=$(echo "scale=0; $AVAIL_KB / 1048576" | bc)

if [[ $AVAIL_KB -ge $REQUIRED_KB ]]; then
    preflight_pass "PREFLT-03: Free space ${AVAIL_GB} GB >= required ${REQUIRED_GB} GB (2x Docker.raw on-disk ${DOCKER_RAW_GB} GB)"
else
    preflight_fail "PREFLT-03: Free space ${AVAIL_GB} GB < required ${REQUIRED_GB} GB"
    preflight_abort "Insufficient space on /Volumes/Unitek-B (D-07)"
fi

# ── PREFLT-05: Target directory writable ─────────────────────────
[[ -d "$TARGET_DIR" ]] || mkdir -p "$TARGET_DIR"
TEST_FILE="$TARGET_DIR/.preflight_write_test"
if touch "$TEST_FILE" 2>/dev/null && rm "$TEST_FILE" 2>/dev/null; then
    preflight_pass "PREFLT-05: $TARGET_DIR exists and is writable"
else
    preflight_fail "PREFLT-05: $TARGET_DIR is not writable"
    preflight_abort "Cannot write to target directory (PREFLT-05)"
fi

# ── PREFLT-04: Backup settings files ────────────────────────────
cp "$DOCKER_SETTINGS_DIR/settings-store.json" "$DOCKER_SETTINGS_DIR/settings-store.json.bak"
cp "$DOCKER_SETTINGS_DIR/settings.json"       "$DOCKER_SETTINGS_DIR/settings.json.bak"
if [[ -f "$DOCKER_SETTINGS_DIR/settings-store.json.bak" && -f "$DOCKER_SETTINGS_DIR/settings.json.bak" ]]; then
    preflight_pass "PREFLT-04: Backups created: settings-store.json.bak, settings.json.bak"
else
    preflight_fail "PREFLT-04: Backup creation failed"
    preflight_abort "Cannot proceed without settings backup (D-03)"
fi

# ── D-05 Bonus: Virtualization backend + diskSizeMiB resolution ──
USE_VF=$(python3 -c "
import json
with open('$DOCKER_SETTINGS_DIR/settings-store.json') as f:
    d = json.load(f)
print(d.get('UseVirtualizationFramework', False))
")
if [[ "$USE_VF" == "True" ]]; then
    preflight_info "Backend: Apple Virtualization Framework confirmed (not Docker VMM)"
else
    preflight_fail "D-05: Docker VMM backend detected — switch to Apple Virtualization Framework"
    preflight_abort "Docker VMM has a bug with external USB volumes (Pitfall 5 in PITFALLS.md)"
fi

LOGICAL_GB=$(echo "scale=1; $(ls -la "$DOCKER_RAW_PATH" | awk '{print $5}') / 1073741824" | bc)
preflight_info "Docker.raw logical: ${LOGICAL_GB} GB | on-disk (sparse): ${DOCKER_RAW_GB} GB | diskSizeMiB discrepancy resolved (settings.json 61035 MiB is stale; actual on-disk is ${DOCKER_RAW_GB} GB)"

# ── Summary ──────────────────────────────────────────────────────
echo ""
if [[ $FAIL -eq 0 ]]; then
    echo "All $PASS pre-flight checks passed. Safe to proceed to Phase 2."
else
    echo "$FAIL check(s) failed. Fix all failures before proceeding."
    exit 1
fi
```

---

## Runtime State Inventory

> This phase is not a rename/refactor/migration phase in terms of code — it is a system administration pre-flight. Runtime state is relevant here because we are checking it (not changing it yet).

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | Docker.raw at `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` — 32 GB logical / 24.1 GB on-disk | Read-only in this phase; copy happens in Phase 2 |
| Live service config | `settings-store.json` (`DataFolder`, `UseVirtualizationFramework`) — authoritative Docker Desktop config | Backed up in this phase (PREFLT-04); edited in Phase 3 |
| OS-registered state | `com.docker.helper` launchd service (state: not running when Docker stopped) | Verified stopped via pgrep; no change in this phase |
| Secrets/env vars | None — Docker Desktop does not use env vars for data location | None |
| Build artifacts | None relevant to pre-flight | None |

---

## Environment Availability

| Dependency | Required By | Available | Version/Value | Fallback |
|------------|------------|-----------|--------------|----------|
| `/Volumes/Unitek-B/` mounted | PREFLT-02, PREFLT-03, PREFLT-05 | YES | APFS, 1.6 TB free | None — must be mounted |
| `/Volumes/Unitek-B/Docker/` directory | PREFLT-05 | YES | Exists, writable | `mkdir -p` creates it |
| `Docker.raw` at expected path | PREFLT-03, D-05 | YES | 24.1 GB on-disk | None — file must exist |
| `settings-store.json` | PREFLT-04, D-05 | YES | `DataFolder` + `UseVirtualizationFramework` present | None — file must exist |
| `settings.json` | PREFLT-04 (D-03 backup) | YES | Present at expected path | None — file must exist |
| `python3` | D-05 virtualization check | YES | macOS built-in | Fallback: `grep` + `awk` on raw JSON |
| `diskutil` | PREFLT-02 | YES | macOS built-in | None needed |
| `osascript` | D-01 graceful quit | YES | macOS built-in | Skip graceful quit, go straight to `killall` |
| `pgrep` / `killall` | D-01, D-02 | YES | macOS built-in | None needed |
| `bc` | Free space arithmetic | YES | macOS built-in (for `scale=1` float display) | Use integer math only if bc absent |
| Docker Desktop running | D-01 kill check | NO (already stopped) | — | Kill sequence still runs idempotently |

**Missing dependencies with no fallback:** None — all required tools confirmed available.

**Pre-existing conditions that simplify execution:**
- Docker Desktop is already stopped (no need to wait for graceful shutdown)
- `/Volumes/Unitek-B/Docker/` already exists and is writable (no `mkdir` needed, but check still required)
- `UseVirtualizationFramework: true` already confirmed (Apple VF backend, not Docker VMM)
- Volume is already APFS with 1.6 TB free (well above 48 GB requirement)
- The only unsatisfied check at research time: `.bak` backup files do not yet exist

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Shell exit codes + manual verification (no test framework — system admin phase) |
| Config file | None — self-contained shell script |
| Quick run command | `bash .planning/phases/01-pre-flight/preflight.sh` |
| Full suite command | Same — script is the test suite |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Verification Command | Automated? |
|--------|----------|-----------|---------------------|-----------|
| PREFLT-01 | Docker processes stopped | smoke | `pgrep -f 'Docker Desktop' \|\| echo PASS` | YES |
| PREFLT-02 | Volume is APFS | smoke | `diskutil info /Volumes/Unitek-B \| awk -F': ' '/Type \(Bundle\)/ {print $2}'` → `apfs` | YES |
| PREFLT-03 | Sufficient free space | smoke | `df -k /Volumes/Unitek-B \| awk 'NR==2 {print $4}'` ≥ 2x `du -sk Docker.raw` | YES |
| PREFLT-04 | Backup files exist | smoke | `ls -la "$DOCKER_SETTINGS_DIR"/*.bak` | YES |
| PREFLT-05 | Target dir writable | smoke | `touch /Volumes/Unitek-B/Docker/.test && rm ...` | YES |
| D-05 | Apple VF backend | smoke | `python3 -c "...UseVirtualizationFramework..."` → `True` | YES |

All checks are automated within the preflight script. Manual verification is not required for any check.

### Wave 0 Gaps

- [ ] `.planning/phases/01-pre-flight/preflight.sh` — the pre-flight script itself (to be created in Wave 1)

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Edit `settings.json` | Edit `settings-store.json` (primary) | Docker Desktop 4.35 | Wrong file = silent failure; both files must be backed up |
| Docker VMM backend | Apple Virtualization Framework | Docker Desktop 4.35+ introduced Docker VMM as option | Docker VMM has external USB path bug; Apple VF is correct choice |
| GUI disk location change | Manual JSON edit + manual copy | Was never reliable cross-device | GUI uses `rename()` which fails EXDEV across filesystems |

**Deprecated/outdated:**
- `settings.json` as sole authoritative settings file: Superseded by `settings-store.json` in Docker Desktop 4.35. Still present but secondary.
- Docker VMM as default backend: Apple VF is now the stable choice for external volume compatibility.

---

## Open Questions

1. **com.docker.build process**
   - What we know: `/Applications/Docker.app/Contents/MacOS/com.docker.build` binary exists
   - What's unclear: Whether `com.docker.build` spawns a long-running process during normal Docker Desktop operation, or only during `docker build` invocations
   - Recommendation: Add `killall -9 com.docker.build 2>/dev/null || true` to the kill sequence for safety; `pgrep -f com.docker.build` in the verification step

2. **Docker Desktop menubar agent separate process**
   - What we know: CONTEXT.md references "menubar agent" as a process to stop
   - What's unclear: Whether the menubar agent runs as a separate process named differently from "Docker Desktop" (e.g., "Docker Desktop Helper") or is bundled in the main Electron process
   - Recommendation: The `Docker Desktop Helper` and `Docker Desktop Helper (Renderer)` process names visible in `/Applications/Docker.app` may appear as child processes; `killall -9 'Docker Desktop'` should terminate them as children. Monitor output of `ps aux | grep -i docker` after kill sequence in Wave 1 testing to confirm.

---

## Sources

### Primary (HIGH confidence)
- Live system inspection (2026-04-09) — `settings-store.json`, `settings.json`, `diskutil info`, `du -sk`, `df -k`, `ls /Applications/Docker.app/Contents/MacOS/`, `launchctl print gui/501/com.docker.helper` — all values verified against running system
- `.planning/research/STACK.md` — Docker Desktop settings architecture, file paths, version context
- `.planning/research/PITFALLS.md` — Docker VMM bug (Pitfall 5), APFS requirement (Pitfall 4), kill sequence requirements
- `.planning/research/ARCHITECTURE.md` — Component boundaries, data flow

### Secondary (MEDIUM confidence)
- GitHub docker/for-mac #7480 — Docker VMM external USB path bug (`/host_mnt` prepending)
- GitHub docker/for-mac #7310 — cross-device link error on rename across volumes
- Docker Desktop Settings documentation: https://docs.docker.com/desktop/settings-and-maintenance/settings/

### Tertiary (LOW confidence — not needed, primary sources sufficient)
- Community blog posts on Docker external volume migration (pattern-confirmed by official sources)

---

## Metadata

**Confidence breakdown:**
- Process kill sequence: HIGH — verified process names from live app inspection + launchctl
- APFS check: HIGH — verified command output against live volume
- Free space check: HIGH — verified `df -k` and `du -sk` output against live system
- Backup strategy: HIGH — files confirmed present, paths confirmed correct
- Writability check: HIGH — verified live with touch test
- Virtualization backend check: HIGH — `UseVirtualizationFramework: true` confirmed in live settings-store.json

**Research date:** 2026-04-09
**Valid until:** 2026-05-09 (stable macOS CLI tools; Docker Desktop version unlikely to change before migration)
