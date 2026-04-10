# Phase 3: Cutover and Verification - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-10
**Phase:** 03-cutover-and-verification
**Areas discussed:** Settings update strategy, Docker start & wait approach, Pre-migration inventory capture, Rollback procedure

---

## Settings update strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Python json module | Parse JSON properly, update DataFolder key, write back. Python pre-installed on macOS. Also update settings.json for consistency. | ✓ |
| jq (if available) | Clean one-liner but jq may not be installed. Needs fallback. | |
| sed in-place | Find/replace value. Fragile with JSON, risks breaking formatting. | |

**User's choice:** Python json module (Recommended)
**Notes:** Safest approach for JSON manipulation. Updates both settings files.

---

## Docker start & wait approach

| Option | Description | Selected |
|--------|-------------|----------|
| open -a + polling docker info | Start Docker, poll docker info every 5s with 120s timeout. Docker info returns 0 when ready. | ✓ |
| open -a + polling docker ps | Start Docker, poll docker ps. Less comprehensive than docker info. | |
| Launch and fixed wait | Sleep for fixed duration, check once. Wastes time or may be insufficient. | |

**User's choice:** open -a + polling docker info (Recommended)
**Notes:** Simple, reliable, works on all macOS versions.

---

## Pre-migration inventory capture

| Option | Description | Selected |
|--------|-------------|----------|
| Start Docker from OLD location briefly | Start from internal disk, capture baseline, stop, then cutover. True pre-migration inventory. | |
| Capture during cutover | Start from NEW location, capture. No baseline for comparison. | |
| Skip inventory comparison | Trust copy, just verify Docker starts + hello-world. | |

**User's choice:** Custom — explained that there's a Compose group that's already broken (reason for migration). Failures of that group are expected and acceptable.
**Notes:** No pre-migration baseline needed. Verify images/containers exist (count > 0) and hello-world runs. Don't flag known-broken Compose group as migration failure.

---

## Rollback procedure

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-rollback on failure | If docker info fails after 120s: auto-restore .bak files. | |
| Manual rollback instructions | Print instructions for user to restore manually. | |
| No rollback — investigate first | Stop and diagnose. Don't auto-restore. .bak files are insurance. | ✓ |

**User's choice:** No rollback — investigate first
**Notes:** User prefers understanding failures over blindly reverting. Diagnostic info should be provided on failure.

---

## Claude's Discretion

- Script structure (single vs split)
- Python one-liner syntax
- Whether to save image/container lists to file
- Verification result formatting

## Deferred Ideas

None — discussion stayed within phase scope
