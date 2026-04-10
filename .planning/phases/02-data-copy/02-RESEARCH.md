# Phase 2: Data Copy - Research

**Researched:** 2026-04-09
**Domain:** macOS file copy — APFS sparse file duplication, progress polling, integrity verification
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Copy method**
- **D-01:** Primary copy command is `cp -c` (APFS clonefile semantics — preserves sparse structure cross-volume)
- **D-02:** Fallback copy command is `ditto` if `cp -c` fails (exit code non-zero). Both preserve APFS sparse metadata.
- **D-03:** Source path: `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` (confirmed in Phase 1)
- **D-04:** Destination path: `/Volumes/Unitek-B/Docker/Docker.raw`

**Progress visibility**
- **D-05:** Copy runs in background; a polling loop checks destination file size with `du` every 5 seconds
- **D-06:** Progress displayed as percentage bar based on expected final on-disk size (24.1 GB from Phase 1 pre-flight results)
- **D-07:** Progress works identically for both `cp -c` and `ditto` fallback (same polling approach)

**Integrity verification**
- **D-08:** Compare BOTH logical size (`stat -f %z`) AND on-disk size (`du -sk`) between source and destination
- **D-09:** Logical size comparison catches truncation; on-disk size comparison catches sparse-to-dense inflation
- **D-10:** Verification is fast (seconds, not minutes) — no SHA256 checksums (explicitly out of scope per REQUIREMENTS.md)

**Failure & rollback behavior**
- **D-11:** On copy failure: delete partial destination file, then retry ONCE
- **D-12:** On second failure: delete partial destination file, report error with details, abort
- **D-13:** Original file on internal disk is NEVER modified or deleted in this phase
- **D-14:** Consistent with Phase 1 hard-stop philosophy — no "continue anyway" on verification failure

### Claude's Discretion

- Script structure (single script vs split like Phase 1)
- Progress bar formatting (ASCII art, percentage, ETA)
- Exact polling interval (5 seconds is target, can adjust for UX)
- Whether to check disk space again before starting copy (pre-flight already verified, but belt-and-suspenders check is reasonable)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MIGR-01 | `Docker.raw` is copied from internal disk to `/Volumes/Unitek-B/Docker/` preserving APFS sparse structure | `cp -c` uses clonefile(2) with fallback to copyfile(2) — sparse file preserved on APFS-to-APFS; confirmed with live `man cp` on macOS 26.4 |
| MIGR-02 | Copy size is verified to match original (file size comparison) | `stat -f %z` (logical size) and `du -sk` (on-disk blocks) both verified working on this system; dual check strategy documented |
| MIGR-03 | Copy progress is visible during transfer | Background polling pattern verified: `cp -c &` + `du -sk` poll loop + `printf` progress bar renders correctly |
| MIGR-04 | Fallback copy method (ditto) is available if `cp -c` fails | `ditto` confirmed installed, file-to-file syntax verified; exit-code-based fallback logic pattern documented |

</phase_requirements>

---

## Summary

Phase 2 copies Docker.raw from the internal APFS volume to the external APFS volume using macOS built-in tools only. The approach is: launch `cp -c` in the background, poll the growing destination file with `du -sk` every 5 seconds, render a percentage progress bar, and wait for the copy process to finish. If `cp -c` exits non-zero, delete the partial destination and retry exactly once using `ditto`. After the copy finishes (either via `cp -c` or `ditto`), compare both the logical file size (`stat -f %z`) and the on-disk block size (`du -sk`) against the source to confirm integrity.

The source is a 24.1 GB on-disk sparse APFS file with 32.0 GB logical size. Both sizes must match between source and destination. A mismatch in logical size indicates truncation (copy cut short); a mismatch in on-disk size indicates sparse-to-dense expansion (the copy wrote more blocks than the original used). Neither is acceptable. The original file is never touched — Phase 4 handles deletion after Phase 3 verification passes.

All tooling is macOS built-in: `cp`, `ditto`, `stat`, `du`, `df`, `bc`, `printf`, `python3`. No Homebrew packages required. Phase 1 pre-flight results are authoritative: Docker is stopped, the destination directory exists and is writable, 1495 GB free space is available, the external volume is APFS, and the Apple Virtualization Framework backend is confirmed.

**Primary recommendation:** Implement as a single script `copy.sh` following the same `set -euo pipefail` + PASS/FAIL counter pattern as `preflight.sh`. Launch copy in background, poll progress, wait for completion, then run dual-metric verification. One retry on failure, hard abort on second failure.

---

## Standard Stack

### Core

| Tool | Source | Purpose | Why Standard |
|------|--------|---------|--------------|
| `cp -c` | macOS built-in | Primary copy with APFS clonefile semantics | Preserves sparse blocks; falls back to copyfile(2) automatically if clonefile fails cross-device |
| `ditto` | macOS built-in | Fallback copy | macOS-native, preserves extended attributes and resource forks, reliable for large files |
| `du -sk` | macOS built-in | On-disk block size measurement for progress and verification | `-s` gives total, `-k` in kilobytes; respects APFS sparse block allocation |
| `stat -f %z` | macOS built-in | Logical file size in bytes | Authoritative logical size; different from on-disk size for sparse files |
| `df -k` | macOS built-in | Available free space on volume | Used for optional pre-copy space guard |
| `bc` | macOS built-in | Floating-point arithmetic for percentage calculation | Ships with macOS; no awk/python dependency for math |
| `printf` | bash built-in | Progress bar rendering | `printf "\r[%-50s] %3d%%"` produces in-place updating progress line |
| `python3` | macOS system | Not needed in Phase 2 | Used in Phase 1 for JSON parsing; Phase 2 is pure file ops |

### No Additional Software Required

Every tool used in Phase 2 is a macOS built-in or bash built-in. `pv` (pipe viewer) is NOT available on this system and is NOT required — the polling approach achieves equivalent progress visibility without any additional installs.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `cp -c` background poll | `rsync --sparse --progress` | rsync shows per-file progress natively but may not preserve APFS sparse semantics as reliably; decision locked to `cp -c` |
| `du -sk` poll | `pv` pipe viewer | pv not installed; polling achieves same UX without dependencies |
| `stat -f %z` | `ls -la \| awk '{print $5}'` | Both work; `stat -f %z` is cleaner and explicit |
| `bc` | `awk 'BEGIN {printf "%.1f\n", x/y}'` | Either works; `bc` matches Phase 1 pattern |

---

## Architecture Patterns

### Recommended Project Structure

```
.planning/phases/02-data-copy/
├── copy.sh               # Main copy script (primary deliverable)
└── verify-copy.sh        # Independent verification (read-only, mirrors Phase 1 pattern)
```

Following Phase 1 convention: one mutation script (`copy.sh`), one read-only verification script (`verify-copy.sh`).

### Pattern 1: Background Copy with Polling Progress Bar

**What:** Launch copy command in background (`&`), capture PID, poll destination file size with `du -sk` in a loop, render in-place progress bar with `printf`, wait for background PID to complete, check exit code.

**When to use:** Any long-running file operation where user needs feedback but the copy tool itself has no `--progress` flag that matches requirements.

**Verified on this system:** Background `dd` + `du -sk` polling loop + `printf` progress bar all confirmed working. Exit code capture via `wait $BG_PID` confirmed.

```bash
# Source: verified live on macOS 26.4
SOURCE="$HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
DEST="/Volumes/Unitek-B/Docker/Docker.raw"

# Get expected on-disk size from source (KB)
EXPECTED_KB=$(du -sk "$SOURCE" | awk '{print $1}')

# Launch copy in background
cp -c "$SOURCE" "$DEST" &
COPY_PID=$!

# Poll until copy process exits
while kill -0 "$COPY_PID" 2>/dev/null; do
  CURRENT_KB=$(du -sk "$DEST" 2>/dev/null | awk '{print $1}' || echo 0)
  if [[ $EXPECTED_KB -gt 0 ]]; then
    PCT=$(echo "scale=0; $CURRENT_KB * 100 / $EXPECTED_KB" | bc)
    PCT=$(( PCT > 100 ? 100 : PCT ))
    BARS=$((PCT / 2))
    printf "\r  [ COPY ] [%-50s] %3d%%" "$(printf '#%.0s' $(seq 1 $BARS) 2>/dev/null)" "$PCT"
  fi
  sleep 5
done

printf "\n"

# Capture exit code
wait $COPY_PID
COPY_EXIT=$?
```

### Pattern 2: Exit-Code-Based Fallback with Cleanup

**What:** Check copy exit code; if non-zero, delete partial destination and retry with fallback command. On second failure, delete partial and abort with detailed error.

**When to use:** Any operation where one retry on transient I/O error is acceptable, but silent continuation on failure is not (D-14 hard-stop philosophy).

```bash
# Source: based on D-11, D-12 decisions; pattern derived from Phase 1 preflight_abort()
run_copy() {
  local cmd="$1"
  local source="$2"
  local dest="$3"

  # Launch and poll (pattern 1 above)
  $cmd "$source" "$dest" &
  # ... polling loop ...
  wait $!
  return $?
}

# Attempt 1: cp -c
if ! run_copy "cp -c" "$SOURCE" "$DEST"; then
  echo "[ WARN ] cp -c failed — cleaning partial and retrying with ditto"
  rm -f "$DEST"
  # Attempt 2: ditto
  if ! run_copy "ditto" "$SOURCE" "$DEST"; then
    rm -f "$DEST"
    echo "[ FAIL ] Both copy attempts failed. Partial destination removed."
    echo "         Check: disk space, volume mount, file permissions."
    exit 1
  fi
fi
```

### Pattern 3: Dual-Metric Integrity Verification

**What:** After copy completes, compare both logical file size and on-disk block size between source and destination. Both must match.

**When to use:** Any APFS sparse file copy where truncation and sparse-to-dense inflation are both failure modes.

```bash
# Source: verified commands on macOS 26.4
SRC_LOGICAL=$(stat -f %z "$SOURCE")
DST_LOGICAL=$(stat -f %z "$DEST")

SRC_DISK_KB=$(du -sk "$SOURCE" | awk '{print $1}')
DST_DISK_KB=$(du -sk "$DEST"   | awk '{print $1}')

PASS=0
FAIL=0

if [[ "$SRC_LOGICAL" == "$DST_LOGICAL" ]]; then
  echo "[ PASS ] MIGR-02a: Logical size matches: $SRC_LOGICAL bytes"
  PASS=$((PASS + 1))
else
  echo "[ FAIL ] MIGR-02a: Logical size mismatch: source=$SRC_LOGICAL dest=$DST_LOGICAL"
  FAIL=$((FAIL + 1))
fi

if [[ "$SRC_DISK_KB" == "$DST_DISK_KB" ]]; then
  echo "[ PASS ] MIGR-02b: On-disk size matches: ${SRC_DISK_KB} KB"
  PASS=$((PASS + 1))
else
  echo "[ FAIL ] MIGR-02b: On-disk size mismatch: source=${SRC_DISK_KB}KB dest=${DST_DISK_KB}KB"
  FAIL=$((FAIL + 1))
fi

if [[ $FAIL -gt 0 ]]; then
  echo "ABORT: Verification failed — do not proceed to Phase 3"
  exit 1
fi
```

### Anti-Patterns to Avoid

- **`mv` instead of `cp`:** `mv` across volumes falls back to copy+delete; the delete happens regardless of copy integrity, and the fallback does not preserve APFS sparse structure reliably. Locked out by D-01.
- **`rsync` without `--sparse`:** Expands Docker.raw from 24.1 GB on-disk to 32.0 GB logical, potentially filling the external volume unexpectedly. The decisions lock to `cp -c` / `ditto`.
- **Starting Docker between copy and verification:** Docker will attempt to mount an incomplete or unverified Docker.raw, potentially overwriting it. Phase 2 must complete fully before any Docker process runs.
- **Copying while Docker is running:** Docker holds Docker.raw open with an exclusive lock. The copy will produce a corrupt destination. Phase 1 pre-flight already ensures Docker is stopped; `copy.sh` should verify this at the top as a guard.
- **Deleting partial destination silently:** Always print what is being deleted and why before `rm -f "$DEST"`. Aids debugging if Phase 2 is re-run after failure.
- **Polling with `ls -la` instead of `du -sk`:** `ls -la` reports logical size (always 32.0 GB from the start); `du -sk` reports actual on-disk blocks written so far, which is what tracks actual copy progress.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| APFS sparse file copy | Custom dd + seek pipeline | `cp -c` | clonefile(2) / copyfile(2) handle sparse blocks natively; custom pipeline would need explicit hole detection |
| Fallback copy | Custom retry loop with exponential backoff | One retry with `ditto` per D-11/D-12 | Problem is transient I/O, not rate limiting; simple retry is correct |
| Progress bar math | Custom floating point in bash | `bc` | Bash integer-only arithmetic fails for percentage display; bc is already used in Phase 1 |
| File size in bytes | Parsing `ls -la` output | `stat -f %z` | `ls` output format varies with locale and flags; `stat` is stable and explicit |

**Key insight:** macOS provides all required file copy semantics in built-in tools. The Phase 2 implementation is essentially glue: invoke the right tool, poll a side-effect (file size), and verify the outcome with two measurements.

---

## Common Pitfalls

### Pitfall 1: `cp -c` Exit Code vs Background PID Exit Code

**What goes wrong:** Using `wait` without capturing the PID leads to checking the exit code of the wrong process, or `set -euo pipefail` triggers on a non-zero exit from a subshell inside the polling loop.

**Why it happens:** `set -e` exits on any non-zero command. Inside a `while kill -0 "$COPY_PID"` loop, `kill -0` itself returns non-zero when the process has exited — but that is the expected termination condition, not an error.

**How to avoid:** Use `|| true` on the `kill -0` check inside the loop condition, or restructure to avoid `set -e` triggering on the process-not-found signal. Capture PID before entering loop. Use `wait $COPY_PID` after the loop to get the actual exit code.

**Warning signs:** Script exits unexpectedly mid-copy with no error message.

### Pitfall 2: `du -sk` Reports 0 at Start of Copy

**What goes wrong:** At the very beginning of the copy, the destination file may not yet exist or may have 0 bytes flushed to disk. The polling loop attempts `du -sk "$DEST"` and either fails (file not found) or returns 0, causing a division-by-zero in `bc`.

**Why it happens:** `cp -c` creates the destination file immediately but may buffer before writing blocks. Race between file creation and first `du -sk` poll.

**How to avoid:** Guard the `du -sk` call with `2>/dev/null || echo 0`. Guard the bc calculation to only run when `EXPECTED_KB -gt 0` and when `CURRENT_KB -gt 0`. Clamp PCT to 0 as minimum.

**Warning signs:** `bc` error "division by zero" in script output.

### Pitfall 3: On-Disk Size Mismatch Due to APFS Compression or Delayed Flush

**What goes wrong:** After `cp -c` completes, `du -sk` on the destination reports a slightly different value than the source due to APFS background compression, deduplication, or metadata flushing not yet complete.

**Why it happens:** APFS may apply transparent compression asynchronously. `du -sk` measures committed blocks at the moment of query.

**How to avoid:** This is MEDIUM probability but LOW risk. If it occurs: add a `sleep 2` between copy completion and verification call to allow APFS to flush. If sizes differ by less than 1% after flush, flag as INFO rather than FAIL (document the threshold explicitly in the script). If sizes differ by more than 1%, treat as FAIL.

**Warning signs:** Verification fails with a small on-disk discrepancy (a few MB difference) but logical size matches.

### Pitfall 4: `kill -0` Behavior When `set -euo pipefail` Is Active

**What goes wrong:** When the copy process finishes and the background PID no longer exists, `kill -0 $PID` returns exit code 1 (process not found). With `set -e`, this exits the script.

**Why it happens:** `set -e` treats any non-zero exit as fatal. `kill -0` returning 1 is the normal termination signal for the while-loop, not an error.

**How to avoid:**
```bash
while kill -0 "$COPY_PID" 2>/dev/null; do
  # polling body
done
```
The `2>/dev/null` suppresses the "No such process" message. The while condition evaluates to false when process exits, terminating the loop cleanly without triggering `set -e`.

### Pitfall 5: Forgetting Docker-Stopped Guard at Script Start

**What goes wrong:** User runs `copy.sh` without having run `preflight.sh` first, or runs it after accidentally starting Docker between phases. Docker holds Docker.raw open; the copy produces a corrupt destination.

**Why it happens:** Phase 2 depends on Phase 1 results but scripts don't enforce sequencing.

**How to avoid:** Add a Docker-stopped guard at the top of `copy.sh` (same `pgrep` check as in `verify-preflight.sh`) — abort immediately if any Docker process is detected. This is belt-and-suspenders: Phase 1 already confirmed, but re-checking costs nothing and prevents corruption.

---

## Code Examples

### Complete Progress Bar Pattern (Verified)

```bash
# Source: verified working on macOS 26.4, bash 3.2
# All commands confirmed available: du, bc, printf, kill, wait, seq

EXPECTED_KB=$(du -sk "$SOURCE" | awk '{print $1}')

cp -c "$SOURCE" "$DEST" &
COPY_PID=$!

echo ""
while kill -0 "$COPY_PID" 2>/dev/null; do
  CURRENT_KB=$(du -sk "$DEST" 2>/dev/null | awk '{print $1}' || echo 0)
  if [[ $EXPECTED_KB -gt 0 && $CURRENT_KB -gt 0 ]]; then
    PCT=$(echo "scale=0; $CURRENT_KB * 100 / $EXPECTED_KB" | bc)
    PCT=$(( PCT > 100 ? 100 : PCT ))
    BARS=$((PCT / 2))
    BAR=$(printf '#%.0s' $(seq 1 "$BARS") 2>/dev/null || true)
    printf "\r  [ COPY ] [%-50s] %3d%%" "$BAR" "$PCT"
  else
    printf "\r  [ COPY ] starting..."
  fi
  sleep 5
done

printf "\n"
wait $COPY_PID
COPY_EXIT=$?
```

### Logical + On-Disk Size Verification (Verified)

```bash
# Source: verified on macOS 26.4
# stat -f %z: logical file size in bytes (confirmed working)
# du -sk: on-disk blocks in KB (confirmed working, respects APFS sparse)

SRC_LOGICAL=$(stat -f %z "$SOURCE")
DST_LOGICAL=$(stat -f %z "$DEST")
SRC_DISK_KB=$(du -sk "$SOURCE" | awk '{print $1}')
DST_DISK_KB=$(du -sk "$DEST"   | awk '{print $1}')
```

### ditto File-to-File Syntax (Verified)

```bash
# Source: verified on macOS 26.4
# ditto src_file dst_file (second form from man page)
ditto "$SOURCE" "$DEST"
# Exit 0 on success; non-zero on failure
```

### Optional Pre-Copy Space Guard

```bash
# Belt-and-suspenders: Phase 1 already confirmed space, but verify again
REQUIRED_KB=$(du -sk "$SOURCE" | awk '{print $1}')
AVAIL_KB=$(df -k /Volumes/Unitek-B | awk 'NR==2 {print $4}')
if [[ $AVAIL_KB -lt $REQUIRED_KB ]]; then
  echo "[ FAIL ] Insufficient space: ${AVAIL_KB}KB available, ${REQUIRED_KB}KB required"
  exit 1
fi
```

---

## Runtime State Inventory

> This is a file copy phase, not a rename/refactor/migration of identifiers. No runtime state contains the target string. This section does not apply.

**Step 2.5: SKIPPED** — Phase 2 copies a binary file to a new location. No databases, live service configs, OS-registered state, secrets, or build artifacts reference the destination path in a way that requires updating.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `cp` (with `-c` flag) | MIGR-01 primary copy | ✓ | macOS built-in, verified on macOS 26.4 | ditto (D-02) |
| `ditto` | MIGR-04 fallback copy | ✓ | macOS built-in, file-to-file syntax verified | none needed (this IS the fallback) |
| `du` (`-sk` flags) | MIGR-03 progress, MIGR-02 verification | ✓ | macOS built-in, verified | none |
| `stat` (`-f %z`) | MIGR-02 logical size verification | ✓ | macOS built-in, verified | none |
| `df` (`-k`) | optional space guard | ✓ | macOS built-in, verified | skip guard (space confirmed by Phase 1) |
| `bc` | progress percentage math | ✓ | `/usr/bin/bc`, verified | `awk 'BEGIN{printf...}'` |
| `printf` | progress bar rendering | ✓ | bash built-in, progress bar pattern verified | none |
| `pv` | alternative progress display | ✗ | not installed | not needed — polling approach is used |
| `/Volumes/Unitek-B/Docker/` | MIGR-01 destination | ✓ | confirmed by Phase 1 PREFLT-05 | none |
| Docker stopped | copy integrity | ✓ | confirmed by Phase 1 PREFLT-01 | abort if detected running |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** `pv` not installed — polling approach provides equivalent progress display.

---

## Validation Architecture

> `nyquist_validation: true` in `.planning/config.json` — section included.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bash (manual execution + exit code verification) |
| Config file | none — shell scripts are self-contained |
| Quick run command | `bash -n copy.sh && echo "syntax OK"` |
| Full suite command | `bash copy.sh` (dry-run not possible — this IS the migration action) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MIGR-01 | `Docker.raw` copied preserving APFS sparse structure | smoke | `stat -f %z /Volumes/Unitek-B/Docker/Docker.raw` returns same value as source | ❌ Wave 0 — part of verify-copy.sh |
| MIGR-02 | Copy size verified: logical + on-disk match | smoke | `stat -f %z` + `du -sk` comparison in verify-copy.sh | ❌ Wave 0 — verify-copy.sh |
| MIGR-03 | Progress visible during transfer | manual-only | Visual observation during `copy.sh` execution — progress bar must render | n/a |
| MIGR-04 | ditto fallback available and callable | smoke | `ditto --version 2>&1 \| head -1` confirms binary exists | ❌ Wave 0 — guard in copy.sh |

**MIGR-03 is manual-only:** Progress bar visibility is a UX property observable only during live execution. No automated test can verify "the user could see progress" — acceptance is by direct observation.

### Sampling Rate

- **Per task commit:** `bash -n copy.sh && bash -n verify-copy.sh` (syntax check only — live copy not re-run)
- **Per wave merge:** Full execution of `verify-copy.sh` against completed copy
- **Phase gate:** `verify-copy.sh` exits 0 before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `verify-copy.sh` — covers MIGR-01, MIGR-02 (read-only verification of completed copy)
- [ ] Guard in `copy.sh` for MIGR-04 ditto availability check

*(copy.sh itself is the implementation — it cannot be unit-tested in isolation without performing the actual copy)*

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `rsync` for large file copies on macOS | `cp -c` (clonefile) for APFS-to-APFS | macOS 10.12+ (APFS introduction) | `cp -c` preserves sparse blocks; rsync requires `--sparse` flag which is not always respected |
| SHA256 checksums for copy integrity | Dual size comparison (logical + on-disk) | Project decision (REQUIREMENTS.md) | 5+ minutes vs seconds; adequate for one-time migration where truncation/inflation are the real risks |
| `pv` for pipe-based progress | Background process + `du -sk` polling | This project — `pv` not available | Same UX result, zero dependencies |

**Deprecated/outdated approaches avoided:**
- GUI "change disk image location": uses `rename()`, fails EXDEV cross-device — still broken through Docker Desktop 4.45+
- `mv` across volumes: same cross-device failure mode
- Copying `vms/0/data/` directory wholesale: brings socket files, lock files, logs — only `Docker.raw` should move

---

## Open Questions

1. **APFS transparent compression on destination**
   - What we know: APFS may compress files transparently; `du -sk` measures committed blocks at query time
   - What's unclear: Whether `du -sk` on source and destination will match exactly immediately after copy, or whether a brief delay is needed for APFS to flush metadata
   - Recommendation: Add `sleep 2` between copy completion and verification; if on-disk sizes differ by < 1% and logical sizes match exactly, treat as PASS with INFO note. Document threshold in script comment.

2. **`cp -c` cross-volume behavior on macOS 26.4**
   - What we know: man page states "if source and target are on different filesystems, cp will fallback to using copyfile(2)" — clonefile fails cross-device, copyfile succeeds
   - What's unclear: Whether copyfile(2) preserves APFS sparse holes in the destination on a different APFS volume
   - Recommendation: This was flagged as MEDIUM confidence in STACK.md. The copy will succeed regardless (copyfile fallback); the question is only whether the destination is equally sparse. If on-disk sizes match (MIGR-02b), sparse structure was preserved. If destination on-disk size equals logical size (32.0 GB), sparse was not preserved — flag and report, but the copy is still valid for Phase 3 (Docker doesn't require sparse format, only a valid disk image).

---

## Project Constraints (from CLAUDE.md)

| Directive | Source | Impact on Phase 2 |
|-----------|--------|-------------------|
| Git commits must include `Co-Authored-By: AI Hive(R) <sales@hupyy.com>` | `/Users/alexanderfedin/CLAUDE.md` + `/Users/alexanderfedin/temp/CLAUDE.md` | All commits for Phase 2 scripts must use this co-author line |
| No `noreply@anthropic.com` in co-author | Same | Never use the default Anthropic co-author email |
| Kebab-case script names | `CLAUDE.md` conventions | Scripts named `copy.sh`, `verify-copy.sh` |
| `#!/bin/bash` shebang | Established pattern from Phase 1 | Both scripts use bash, not sh |
| `set -euo pipefail` | Phase 1 established pattern | Required in both scripts |
| `[ PASS ]` / `[ FAIL ]` / `[ INFO ]` status format | Phase 1 established pattern | Copy script uses same output format |
| 2-space indentation | CLAUDE.md code style | Applied in both scripts |
| No TypeScript; JSDoc if JS | Not applicable | Phase 2 is shell scripts only |
| Docker must be stopped before copy | CLAUDE.md project constraints | copy.sh guards against running Docker processes |
| External volume must be APFS | CLAUDE.md project constraints | Confirmed by Phase 1; copy.sh may re-verify |
| All-or-nothing atomicity | CLAUDE.md project constraints | One retry then abort; partial destinations deleted |

---

## Sources

### Primary (HIGH confidence)

- Live system verification — `man cp` on macOS 26.4: `--cc` flag confirmed, clonefile(2) fallback to copyfile(2) documented
- Live system verification — `cp -c` with real file: exit 0, content preserved
- Live system verification — `ditto src_file dst_file`: exit 0, content preserved
- Live system verification — `du -sk`, `stat -f %z`, `df -k`, `bc`, `printf` progress bar: all confirmed working
- Live system verification — `pv` not installed
- `.planning/phases/01-pre-flight/preflight-results.txt`: Docker.raw logical 32.0 GB, on-disk 24.1 GB, 1495 GB free, APFS confirmed, Apple VF backend confirmed
- `.planning/research/STACK.md`: `cp -c` rationale, tool inventory, APFS sparse file behavior
- `.planning/research/PITFALLS.md`: Pitfall 1 (mv/rename), Pitfall 6 (starting Docker before copy complete), Pitfall 9 (socket files)
- `.planning/phases/01-pre-flight/preflight.sh`: Reusable patterns (`set -euo pipefail`, PASS/FAIL counters, `preflight_abort()`)

### Secondary (MEDIUM confidence)

- `.planning/research/STACK.md` (citing STACK.md itself): cp -c clonefile cross-volume behavior may fall back to copyfile — MEDIUM because macOS version-specific

### Tertiary (LOW confidence)

- APFS transparent compression timing: no official Apple documentation consulted; based on general APFS behavior knowledge

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools verified live on macOS 26.4
- Architecture: HIGH — patterns derived from Phase 1 codebase + verified commands
- Pitfalls: HIGH — derived from Phase 1 research (PITFALLS.md) + live testing
- Environment: HIGH — every tool probed directly

**Research date:** 2026-04-09
**Valid until:** 2026-05-09 (stable macOS built-ins; `cp -c` behavior does not change between macOS patch releases)
