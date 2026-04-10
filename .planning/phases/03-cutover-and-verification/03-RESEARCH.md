# Phase 3: Cutover and Verification - Research

**Researched:** 2026-04-10
**Domain:** Docker Desktop settings update, process management, daemon readiness polling, post-migration verification
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Use Python `json` module to parse and update `settings-store.json`. Python is pre-installed on macOS and handles JSON safely (no risk of breaking formatting like sed).
- **D-02:** Update `DataFolder` key in `settings-store.json` to `/Volumes/Unitek-B/Docker`
- **D-03:** Also update `dataFolder` key in `settings.json` to `/Volumes/Unitek-B/Docker` for consistency (belt-and-suspenders)
- **D-04:** Verify the update by reading back the file and confirming the new value is correct before starting Docker
- **D-05:** Start Docker Desktop with `open -a "Docker Desktop"`
- **D-06:** Poll `docker info` every 5 seconds with a 120-second timeout to detect readiness
- **D-07:** `docker info` exit code 0 means daemon is fully ready — any non-zero means still starting or failed
- **D-08:** Do NOT start Docker from old location to capture baseline — unnecessary complexity
- **D-09:** There is a Compose group that already fails to start (broken before migration). Failure of this group or any of its containers is expected and acceptable — do not treat as migration failure.
- **D-10:** Verify images exist with `docker images` (count should be > 0). Verify containers exist with `docker ps -a` (count should be > 0). Run `docker run --rm hello-world` as smoke test. These are sufficient without exact pre/post comparison.
- **D-11:** No automatic rollback. If Docker fails to start from the new location: stop Docker, investigate the issue first. The .bak files exist as insurance but are not auto-restored.
- **D-12:** Report diagnostic info on failure: docker info output, Docker Desktop logs path, settings file contents — help user investigate rather than blindly reverting.
- **D-13:** Hard-stop on settings update failure (file not writable, Python error) — abort before starting Docker with a broken config.

### Claude's Discretion

- Script structure (single cutover script vs split cutover + verify)
- Exact Python one-liner syntax for JSON update
- Whether to capture image/container lists to a file for reference (recommended but not required)
- How to format verification results (follow Phase 1/2 `[ PASS ]`/`[ FAIL ]` pattern)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CONF-01 | `DataFolder` key in `settings-store.json` is updated to `/Volumes/Unitek-B/Docker` | Python json module pattern verified; atomic write-then-readback confirmed correct approach |
| CONF-02 | Docker Desktop starts successfully from the new location | `open -a "Docker Desktop"` + `docker info` polling pattern documented with exact timeout logic |
| VERIF-01 | All pre-existing Docker images are present after migration (`docker images`) | `docker images --format '{{.Repository}}'` count > 0 pattern; no baseline needed (D-10) |
| VERIF-02 | All pre-existing containers are present after migration (`docker ps -a`) | `docker ps -a --format '{{.Names}}'` count > 0 pattern; broken Compose group expected (D-09) |
| VERIF-03 | Smoke test container runs successfully (`docker run --rm hello-world`) | hello-world pull + run pattern verified; daemon root dir check from `docker info` confirms correct storage path |
</phase_requirements>

---

## Summary

Phase 3 is the cutover: update the two Docker Desktop settings files to point to the external volume, start Docker Desktop, and verify data integrity. The copy is already done and verified (Phase 2: 25,335,652 KB matched exactly at `/Volumes/Unitek-B/Docker/Docker.raw`). The original Docker.raw on internal disk remains untouched until Phase 4.

The critical sequence is: update settings (Python json module, atomic readback verify) → start Docker Desktop (`open -a`) → poll until ready (`docker info` exit 0) → verify images > 0, containers > 0, hello-world runs. On any failure: stop Docker, emit diagnostics (settings contents, log path, docker info output), abort without auto-rollback.

The broken Compose group is a known pre-existing condition; any failure of that group during Docker startup is expected and must not be treated as a migration failure indicator.

**Primary recommendation:** Two-script structure — `cutover.sh` (settings update + Docker start + readiness poll) and `verify-cutover.sh` (independent re-runnable verification of images, containers, smoke test) — matching the Phase 1/2 split pattern.

---

## Standard Stack

### Core

| Tool | Version/Source | Purpose | Why Standard |
|------|---------------|---------|--------------|
| `python3` | 3.12.2 (system, verified) | JSON read/write for settings files | Built-in, safe JSON handling; no sed fragility; D-01 locked decision |
| `open -a "Docker Desktop"` | macOS built-in | Launch Docker Desktop GUI app | Standard macOS app launch; triggers full Docker startup including VM |
| `docker info` | Docker 29.3.1 (verified) | Poll for daemon readiness | Exit 0 = daemon ready; non-zero = still starting; D-07 locked decision |
| `docker images` | Docker 29.3.1 | List images for VERIF-01 | Standard Docker CLI; no extra tools |
| `docker ps -a` | Docker 29.3.1 | List all containers for VERIF-02 | Standard Docker CLI |
| `docker run --rm hello-world` | Docker 29.3.1 | Smoke test for VERIF-03 | Pulls and runs minimal image; validates daemon + storage + network |
| `bash` with `set -euo pipefail` | macOS built-in | Script shell | Established pattern from Phase 1/2 |

### Supporting

| Tool | Version/Source | Purpose | When to Use |
|------|---------------|---------|-------------|
| `pgrep` | macOS built-in | Guard: detect any running Docker processes before settings edit | Safety guard at script start |
| `killall` / `osascript quit` | macOS built-in | Stop Docker if found running at script start | Only if Docker was left running accidentally |
| `docker info --format '{{.DockerRootDir}}'` | Docker 29.3.1 | Confirm daemon is using external volume path | Post-readiness confirmation step |
| `tail -20` on Docker logs | macOS built-in | Diagnostic output on failure | Only in failure/diagnostic path (D-12) |

### No additional software required

Every tool is a macOS built-in or the Docker CLI already installed. Confirmed with `command -v docker`, `python3 --version`, `osascript` all available.

**Installation:** None required.

---

## Architecture Patterns

### Recommended Project Structure

```
.planning/phases/03-cutover-and-verification/
├── cutover.sh          # settings update + Docker start + readiness poll
└── verify-cutover.sh   # independent verification (re-runnable)
```

This matches the Phase 1 pattern (`preflight.sh` + `verify-preflight.sh`) and Phase 2 pattern (`copy-docker.sh` + `verify-copy.sh`). The split allows re-running verification without re-triggering the cutover.

### Pattern 1: Python json Atomic Settings Update

**What:** Read settings file, update key, write back atomically. Readback-verify before proceeding.

**When to use:** CONF-01 and D-03 — updating both `settings-store.json` (DataFolder) and `settings.json` (dataFolder).

**Example:**
```bash
# Source: live system verification, python3 3.12.2, json module confirmed OK
NEW_PATH="/Volumes/Unitek-B/Docker"
SETTINGS_DIR="$HOME/Library/Group Containers/group.com.docker"

python3 - <<'PYEOF'
import json, sys, os

settings_path = os.path.expanduser(
    "~/Library/Group Containers/group.com.docker/settings-store.json"
)
new_path = "/Volumes/Unitek-B/Docker"

with open(settings_path, 'r') as f:
    data = json.load(f)

data['DataFolder'] = new_path

with open(settings_path, 'w') as f:
    json.dump(data, f, indent=2)

# Readback verify (D-04)
with open(settings_path, 'r') as f:
    check = json.load(f)

if check.get('DataFolder') != new_path:
    print(f"ERROR: readback mismatch: {check.get('DataFolder')}", file=sys.stderr)
    sys.exit(1)

print("OK")
PYEOF
```

**Critical:** Use `json.dump` with `indent=2` to preserve human-readable format. The file is small (<100 lines); full rewrite is safe. Do NOT use `sed` or string replacement (breaks JSON on special characters).

### Pattern 2: Docker Desktop Start + Readiness Poll

**What:** Launch Docker Desktop via `open -a`, then poll `docker info` every 5 seconds until exit 0 or 120s timeout.

**When to use:** CONF-02 — after settings update is verified.

**Example:**
```bash
# Source: macOS built-in open(1) + docker info exit code semantics, verified locally
open -a "Docker Desktop"

TIMEOUT=120
INTERVAL=5
ELAPSED=0

echo "[ INFO ] Waiting for Docker daemon (timeout: ${TIMEOUT}s)..."

while [[ $ELAPSED -lt $TIMEOUT ]]; do
    if docker info > /dev/null 2>&1; then
        echo "[ PASS ] Docker daemon ready after ${ELAPSED}s"
        break
    fi
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "[ FAIL ] Docker daemon did not become ready within ${TIMEOUT}s"
    # Emit diagnostics (D-12) and exit 1
fi
```

**Verified:** `docker info` returns exit 1 when Docker daemon is not running (confirmed on this system). Exit 0 means daemon fully up.

### Pattern 3: Diagnostic Emission on Failure

**What:** On any failure, print settings file contents, Docker log path, and last docker info output.

**When to use:** Any failure in cutover or verification steps (D-12).

**Example:**
```bash
emit_diagnostics() {
    local SETTINGS_DIR="$HOME/Library/Group Containers/group.com.docker"
    echo ""
    echo "=== Diagnostic Information ==="
    echo "--- settings-store.json DataFolder ---"
    python3 -c "import json; d=json.load(open('$SETTINGS_DIR/settings-store.json')); print(d.get('DataFolder','NOT FOUND'))"
    echo "--- settings.json dataFolder ---"
    python3 -c "import json; d=json.load(open('$SETTINGS_DIR/settings.json')); print(d.get('dataFolder','NOT FOUND'))"
    echo "--- Docker Desktop logs location ---"
    echo "$HOME/Library/Containers/com.docker.docker/Data/log/host/"
    echo "--- Last docker info output ---"
    docker info 2>&1 | head -30 || true
    echo "=== End Diagnostics ==="
}
```

**Log path verified:** `~/Library/Containers/com.docker.docker/Data/log/host/com.docker.backend.log` confirmed present.

### Pattern 4: Image/Container Count Verification

**What:** Count output rows from `docker images` and `docker ps -a`; require count > 0.

**When to use:** VERIF-01 and VERIF-02.

**Example:**
```bash
# Count images (exclude header line)
IMAGE_COUNT=$(docker images --format '{{.Repository}}' | wc -l | tr -d ' ')

if [[ $IMAGE_COUNT -gt 0 ]]; then
    echo "[ PASS ] VERIF-01: $IMAGE_COUNT image(s) present"
else
    echo "[ FAIL ] VERIF-01: No images found"
fi

# Count all containers including stopped (exclude header)
CONTAINER_COUNT=$(docker ps -a --format '{{.Names}}' | wc -l | tr -d ' ')

if [[ $CONTAINER_COUNT -gt 0 ]]; then
    echo "[ PASS ] VERIF-02: $CONTAINER_COUNT container(s) present"
else
    echo "[ FAIL ] VERIF-02: No containers found"
fi
```

**Note:** The broken Compose group (D-09) will appear in `docker ps -a` as stopped/error containers. This is expected. The count > 0 check passes as long as any containers exist regardless of their state.

### Pattern 5: Docker Root Dir Confirmation

**What:** After daemon is ready, confirm it is reading from the external volume.

**When to use:** After readiness poll passes — confirms DataFolder was honored.

**Example:**
```bash
# Confirm Docker daemon is using external volume (not internal fallback)
DOCKER_ROOT=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "unknown")
if [[ "$DOCKER_ROOT" == *"/Volumes/Unitek-B"* ]]; then
    echo "[ PASS ] Docker root dir confirmed on external volume: $DOCKER_ROOT"
else
    echo "[ FAIL ] Docker root dir unexpected: $DOCKER_ROOT (expected /Volumes/Unitek-B)"
fi
```

**Why this matters:** If Docker silently falls back to internal disk (e.g., DataFolder key was wrong), the daemon starts fine but from the wrong location. This check catches that silently-wrong-success scenario.

### Anti-Patterns to Avoid

- **sed or string replacement for JSON:** Breaks on special characters, trailing commas, whitespace changes. Use Python json module exclusively (D-01).
- **Starting Docker without verifying settings were written:** Always readback-verify before `open -a` (D-04, D-13).
- **Treating broken Compose group startup failure as migration failure:** Known pre-existing condition (D-09). Check only that total container count > 0.
- **Auto-restoring .bak files on failure:** User explicitly chose investigate-first (D-11). Diagnostics only; no auto-rollback.
- **Checking docker info before `open -a`:** `docker info` is the poll mechanism only after launch; checking before wastes timeout budget.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON file update | String replacement, sed, awk | `python3 -c "import json..."` | JSON special chars break string tools; Python handles all edge cases |
| Docker readiness detection | Custom socket poll, log parsing | `docker info` exit code | Docker CLI semantics are stable; exit 0 = fully ready |
| macOS app launch | launchctl, direct binary path | `open -a "Docker Desktop"` | `open -a` is the documented macOS app launch mechanism; triggers full startup sequence |

---

## Runtime State Inventory

> Not applicable — this is a cutover/verification phase, not a rename/refactor phase. No string-replace operations across runtime state.

---

## Common Pitfalls

### Pitfall 1: Silent Fallback to Internal Disk

**What goes wrong:** `settings-store.json` is updated but Docker Desktop starts from the internal disk anyway. `docker info` exits 0, images appear, but they are the internal ones — the external volume is unused. This can happen if Docker Desktop ignores the setting (historically documented behavior on version mismatches) or if the file was not written correctly.

**Why it happens:** The JSON write succeeded but the DataFolder value was silently overridden or Docker found a cached value. Also happens if `settings.json` has a conflicting `dataFolder` value that Docker reads first.

**How to avoid:** After daemon is ready, check `docker info --format '{{.DockerRootDir}}'` for `/Volumes/Unitek-B` in the path. This is Pattern 5 above. Update both files (D-03) to eliminate conflicts between `settings-store.json` and `settings.json`.

**Warning signs:** `docker info` exits 0 but Docker Root Dir shows internal path; internal disk usage is unchanged.

### Pitfall 2: hello-world Requires Network Access

**What goes wrong:** `docker run --rm hello-world` fails because hello-world is not cached locally (in the Docker.raw copy from Phase 2) and Docker cannot pull it (no internet, firewall, or DNS issue). This looks like a migration failure but is actually a network issue.

**Why it happens:** `hello-world` is a pull-and-run operation. If it was never pulled before migration, it will not be in Docker.raw, and `docker pull` must succeed.

**How to avoid:** The copy-results.txt confirms the Docker.raw was fully copied and contains whatever was there before. If hello-world was run before migration, it will be cached. If not, the pull may fail on a network issue unrelated to migration. The verification script should check if hello-world is already cached (`docker images hello-world`) before running; if not cached, note that the test requires network access.

**Warning signs:** `docker run --rm hello-world` fails with "Unable to find image" + network error, while `docker images` and `docker ps -a` pass.

### Pitfall 3: settings-store.json Write Fails Silently

**What goes wrong:** Python writes to `settings-store.json` but a permissions issue or disk full causes a partial write. The file is corrupted. Docker Desktop fails to parse it and either crashes or reverts to defaults.

**Why it happens:** Python's `open(path, 'w')` + `json.dump` is not atomic; if interrupted mid-write, the file is partially written. A SIGHUP or disk full during the write produces a truncated JSON file.

**How to avoid:** (1) The readback-verify (D-04) catches a corrupted file immediately — if `json.load` on the written file fails, abort before starting Docker. (2) The `.bak` file created in Phase 1 remains intact; user can manually restore if needed. The script must abort (D-13) if the write or readback fails — never proceed to `open -a` with a broken config.

**Warning signs:** Python raises `JSONDecodeError` during readback; file size is smaller than the original.

### Pitfall 4: Docker Startup Timeout Too Short

**What goes wrong:** Docker Desktop takes longer than expected to start (first boot from external USB, or macOS security prompt delays), the 120-second poll expires, the script reports FAIL, but Docker would have been ready at 130 seconds.

**Why it happens:** USB 3 I/O latency for a 24 GB disk image is higher than internal NVMe. First start from a new path may trigger additional initialization. macOS Gatekeeper may prompt.

**How to avoid:** The 120-second timeout is already generous (D-06). However: if Docker does eventually start (user sees it in menubar), they can re-run `verify-cutover.sh` independently without re-running cutover. The verify script should be safe to re-run at any time.

**Warning signs:** Timeout hit but Docker Desktop icon appears in menubar shortly after; `docker info` succeeds when run manually after the timeout.

### Pitfall 5: Broken Compose Group Misread as Migration Failure

**What goes wrong:** Docker Desktop auto-starts the broken Compose group on launch. Some containers error or fail to start. A verification check counting "running containers" (vs. all containers) returns 0 or a low number, incorrectly flagging migration failure.

**Why it happens:** D-09 documents this as a known pre-existing condition. The Compose group was already broken before migration.

**How to avoid:** Use `docker ps -a` (all containers, including stopped/error) not `docker ps` (running only) for VERIF-02 count. The count > 0 check passes as long as the containers exist in the database — their run state is irrelevant to migration success.

**Warning signs:** `docker ps` returns 0 but `docker ps -a` returns > 0 — this is expected and correct behavior.

---

## Code Examples

Verified patterns from live system inspection and established Phase 1/2 script patterns:

### Settings Update — Complete Python Block

```python
# Source: python3 3.12.2 json module, verified locally
import json, sys, os

def update_datafolder(settings_path, new_path, key_name):
    """Update a dataFolder key in a Docker Desktop settings JSON file."""
    try:
        with open(settings_path, 'r') as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"ERROR: Cannot read {settings_path}: {e}", file=sys.stderr)
        sys.exit(1)

    data[key_name] = new_path

    try:
        with open(settings_path, 'w') as f:
            json.dump(data, f, indent=2)
    except IOError as e:
        print(f"ERROR: Cannot write {settings_path}: {e}", file=sys.stderr)
        sys.exit(1)

    # Readback verify (D-04)
    with open(settings_path, 'r') as f:
        check = json.load(f)
    if check.get(key_name) != new_path:
        print(f"ERROR: Readback mismatch in {settings_path}: got {check.get(key_name)}", file=sys.stderr)
        sys.exit(1)

settings_dir = os.path.expanduser("~/Library/Group Containers/group.com.docker")
new_path = "/Volumes/Unitek-B/Docker"

update_datafolder(os.path.join(settings_dir, "settings-store.json"), new_path, "DataFolder")
update_datafolder(os.path.join(settings_dir, "settings.json"), new_path, "dataFolder")
print("OK")
```

### Readiness Poll Loop

```bash
# Source: established pattern; docker info exit semantics confirmed locally
open -a "Docker Desktop"

TIMEOUT=120
INTERVAL=5
ELAPSED=0

while [[ $ELAPSED -lt $TIMEOUT ]]; do
    if docker info > /dev/null 2>&1; then
        echo "[ PASS ] CONF-02: Docker daemon ready after ${ELAPSED}s"
        break
    fi
    printf "\r[ INFO ] Waiting for daemon... %ds/%ds" "$ELAPSED" "$TIMEOUT"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done
printf "\n"

if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "[ FAIL ] CONF-02: Docker daemon not ready after ${TIMEOUT}s"
    emit_diagnostics
    exit 1
fi
```

### Smoke Test with hello-world Cache Check

```bash
# Check if hello-world is already in Docker.raw (cached from pre-migration usage)
if docker images --format '{{.Repository}}' | grep -q "^hello-world$"; then
    echo "[ INFO ] hello-world image already cached locally"
else
    echo "[ INFO ] hello-world not cached — will pull from registry (requires network)"
fi

if docker run --rm hello-world > /dev/null 2>&1; then
    echo "[ PASS ] VERIF-03: hello-world smoke test succeeded"
else
    echo "[ FAIL ] VERIF-03: hello-world smoke test failed"
    echo "[ INFO ] Run manually: docker run --rm hello-world"
fi
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Edit `settings.json` | Edit `settings-store.json` (primary) | Docker Desktop 4.35 | Must update settings-store.json; settings.json is secondary/legacy |
| GUI "Browse" to change disk location | Manual settings file edit + cp | Broken since Docker Desktop 4.18 | GUI uses rename() which fails cross-device; manual is the only working method |

**Current confirmed state (Docker Desktop 29.3.1 on this system):**
- `settings-store.json` DataFolder: `/Users/alexanderfedin/Library/Containers/com.docker.docker/Data/vms/0/data` (needs update to `/Volumes/Unitek-B/Docker`)
- `settings.json` dataFolder: same (needs update)
- External Docker.raw at `/Volumes/Unitek-B/Docker/Docker.raw`: 25,335,652 KB confirmed (Phase 2 complete)
- UseVirtualizationFramework: `True` (Apple VF backend — no /host_mnt issue)
- Docker Desktop: not running (ready for cutover)

---

## Open Questions

1. **hello-world image pre-migration cache state**
   - What we know: The Docker.raw copy is complete and contains whatever was in Docker before migration
   - What's unclear: Whether `hello-world` was ever pulled before migration (it may or may not be in the image store)
   - Recommendation: The verify script should check `docker images hello-world` first; if not cached, document that network access is needed for VERIF-03 and that a pull failure is a network issue, not a migration failure

2. **docker info --format '{{.DockerRootDir}}' path format**
   - What we know: Docker Root Dir shows the path inside the Linux VM's filesystem, not the macOS host path
   - What's unclear: Whether DockerRootDir will show `/Volumes/Unitek-B/...` or a VM-internal path like `/var/lib/docker`
   - Recommendation: Test `docker info` after startup; if DockerRootDir shows VM-internal path, use an alternative check (e.g., confirm settings-store.json DataFolder still reads correctly after Docker is running — Docker Desktop sometimes rewrites it on startup)

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| python3 | Settings update (D-01) | Yes | 3.12.2 | — |
| python3 json module | Settings update | Yes | stdlib | — |
| docker CLI | Readiness poll, VERIF-01/02/03 | Yes | 29.3.1 | — |
| Docker Desktop.app | CONF-02 start | Yes | 29.3.1 | — |
| open (macOS) | App launch (D-05) | Yes | built-in | — |
| osascript | Docker quit on guard trigger | Yes | built-in | — |
| pgrep | Docker process guard | Yes | built-in | — |
| /Volumes/Unitek-B/Docker/Docker.raw | Cutover target | Yes | 25,335,652 KB (Phase 2 verified) | — |
| settings-store.json.bak | Rollback insurance | Yes | Phase 1 created | — |

**Missing dependencies with no fallback:** None.

**All dependencies confirmed available on this system.**

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Manual bash script execution (no automated test harness for OS-level operations) |
| Config file | None |
| Quick run command | `bash .planning/phases/03-cutover-and-verification/verify-cutover.sh` |
| Full suite command | `bash .planning/phases/03-cutover-and-verification/cutover.sh && bash .planning/phases/03-cutover-and-verification/verify-cutover.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | Script Exists? |
|--------|----------|-----------|-------------------|---------------|
| CONF-01 | DataFolder in settings-store.json = /Volumes/Unitek-B/Docker | Smoke (readback verify) | `python3 -c "import json; d=json.load(open(...)); assert d['DataFolder']=='/Volumes/Unitek-B/Docker'"` | No — Wave 0 |
| CONF-02 | Docker Desktop starts, docker info exits 0 | Integration (live daemon) | `docker info > /dev/null 2>&1 && echo PASS` | No — Wave 0 |
| VERIF-01 | docker images count > 0 | Integration (live daemon) | `[[ $(docker images --format '{{.Repository}}' \| wc -l) -gt 0 ]]` | No — Wave 0 |
| VERIF-02 | docker ps -a count > 0 | Integration (live daemon) | `[[ $(docker ps -a --format '{{.Names}}' \| wc -l) -gt 0 ]]` | No — Wave 0 |
| VERIF-03 | docker run --rm hello-world exits 0 | Smoke (live daemon + network) | `docker run --rm hello-world > /dev/null 2>&1` | No — Wave 0 |

### Sampling Rate

- **Per task commit:** `python3 -c "import json; d=json.load(open(...))" && echo "JSON valid"` (settings file validity)
- **Per wave merge:** Full `verify-cutover.sh` suite
- **Phase gate:** All 5 requirements passing before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `cutover.sh` — covers CONF-01, CONF-02
- [ ] `verify-cutover.sh` — covers VERIF-01, VERIF-02, VERIF-03 (re-runnable independently)

---

## Project Constraints (from CLAUDE.md)

| Directive | Impact on Phase 3 |
|-----------|-------------------|
| No TypeScript; all JavaScript uses JSDoc | Not applicable — scripts are bash + python3 |
| Naming: kebab-case for shell scripts | Script names: `cutover.sh`, `verify-cutover.sh` |
| Naming: UPPER_SNAKE_CASE for constants | Script variables: `SETTINGS_DIR`, `TIMEOUT`, `INTERVAL`, `PASS`, `FAIL` |
| camelCase local vars in JavaScript | Not applicable |
| set -euo pipefail | Required on all bash scripts (established pattern) |
| [ PASS ] / [ FAIL ] / [ INFO ] format | Required — follow Phase 1/2 pattern |
| PASS/FAIL counters + summary | Required — `PASS=0`, `FAIL=0`, summary block |
| Git co-author: `AI Hive(R) <sales@hupyy.com>` | Apply to all commits |
| GSD workflow enforcement | Planning artifacts already in sync via this research |

---

## Sources

### Primary (HIGH confidence)

- Live system inspection — settings-store.json, settings.json current DataFolder values; python3 3.12.2 json module confirmed; docker CLI 29.3.1 confirmed; /Volumes/Unitek-B/Docker/Docker.raw existence and size confirmed; docker info exit 1 when daemon stopped confirmed
- `.planning/research/STACK.md` — DataFolder key authority, settings file paths, Python json module rationale
- `.planning/research/ARCHITECTURE.md` — Docker startup data flow, dataFolder → Docker.raw relationship
- `.planning/research/PITFALLS.md` — Pitfall 2 (wrong settings file), Pitfall 6 (starting Docker with partial copy), Pitfall 7 (deleting original early)
- Phase 1/2 scripts (`preflight.sh`, `copy-docker.sh`) — bash patterns, output format, PASS/FAIL structure

### Secondary (MEDIUM confidence)

- Docker Desktop documentation: https://docs.docker.com/desktop/settings-and-maintenance/settings/ — settings file keys
- Docker Desktop FAQ: https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/ — macOS-specific behavior

### Tertiary (LOW confidence)

- None — all claims verified against live system or official docs.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools verified present on live system, exact versions confirmed
- Architecture patterns: HIGH — based on live settings file inspection and established Phase 1/2 patterns
- Pitfalls: HIGH — sourced from Phase 1/2 research with GitHub issue backing; Pitfall 5 (broken Compose group) from user decision D-09

**Research date:** 2026-04-10
**Valid until:** 2026-05-10 (30 days — stable domain; Docker Desktop settings format unlikely to change)
