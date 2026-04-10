# Phase 2: Data Copy - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-10
**Phase:** 02-data-copy
**Areas discussed:** Copy method & sparse handling, Progress visibility, Integrity verification, Failure & rollback behavior

---

## Copy method & sparse handling

| Option | Description | Selected |
|--------|-------------|----------|
| cp -c first, ditto fallback | cp -c attempts APFS clone cross-volume preserving sparse. Falls back to ditto if cp -c fails. Matches MIGR-01 + MIGR-04. | ✓ |
| rsync with sparse flag | rsync --sparse --progress. Handles progress natively but may not preserve APFS-specific sparse metadata. | |
| ditto only | Apple's ditto preserves all metadata and resource forks. Reliable but no built-in progress indicator. | |

**User's choice:** cp -c first, ditto fallback (Recommended)
**Notes:** Matches both MIGR-01 (sparse-preserving copy) and MIGR-04 (fallback method). Both tools preserve APFS sparse structure.

---

## Progress visibility

| Option | Description | Selected |
|--------|-------------|----------|
| Background du polling | Start cp -c in background, poll destination file size with du every 5 seconds, show percentage bar. Works with both cp -c and ditto. | ✓ |
| pv pipe | Pipe through pv for byte-level progress. Breaks APFS clone semantics (cp -c can't pipe). | |
| Periodic stat check | Check file size with stat -f %z periodically. May show logical size rather than on-disk. | |

**User's choice:** Background du polling (Recommended)
**Notes:** Simple approach that works with both primary and fallback copy methods. No extra tools needed.

---

## Integrity verification

| Option | Description | Selected |
|--------|-------------|----------|
| Size + sparse metadata | Compare both logical size (stat -f %z) AND on-disk size (du -sk). Catches truncation and sparse inflation. Seconds, not minutes. | ✓ |
| Size only | Compare logical file size only. Simplest. Matches MIGR-02 exactly. | |
| Size + head/tail byte check | Size plus first/last 1MB comparison. Adds ~2 seconds. | |

**User's choice:** Size + sparse metadata (Recommended)
**Notes:** Dual-check approach (logical + on-disk) gives high confidence without the SHA256 time cost.

---

## Failure & rollback behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Delete partial + abort | On any failure: delete partial, abort. No retries. Pure hard-stop philosophy. | |
| Delete partial + retry once | On first failure: delete partial, retry once. On second failure: abort. Handles transient I/O. | ✓ |
| Keep partial + abort | Leave partial file for debugging. User must manually clean up. | |

**User's choice:** Delete partial + retry once
**Notes:** Slight relaxation of Phase 1's pure hard-stop approach — allows one retry for transient I/O errors while remaining conservative.

---

## Claude's Discretion

- Script structure (single vs split)
- Progress bar formatting
- Polling interval tuning
- Pre-copy disk space re-check

## Deferred Ideas

None — discussion stayed within phase scope
