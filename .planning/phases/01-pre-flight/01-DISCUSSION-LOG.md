# Phase 1: Pre-flight - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-09
**Phase:** 01-pre-flight
**Areas discussed:** Stop procedure, Backup strategy, Validation depth
**User guidance:** "Reasonably choose towards safety and precision and completeness"

---

## Stop Procedure

| Option | Description | Selected |
|--------|-------------|----------|
| Full kill (Recommended) | Quit app + killall Docker processes + verify with pgrep — safest | ✓ |
| Quit app only | Just quit Docker Desktop from menu/CLI — simpler but background agents may linger | |
| You decide | Claude picks the safest approach | |

**User's choice:** Full kill (Recommended)
**Notes:** User selected all recommended options guided by safety/completeness preference.

### Stop Verification

| Option | Description | Selected |
|--------|-------------|----------|
| Verify + block (Recommended) | Check pgrep for any Docker process and refuse to proceed if any found | ✓ |
| Verify + warn | Check but only warn, let user decide whether to continue | |
| You decide | Claude picks based on safety preference | |

**User's choice:** Verify + block (Recommended)

---

## Backup Strategy

### Backup Location

| Option | Description | Selected |
|--------|-------------|----------|
| Same dir .bak (Recommended) | settings-store.json.bak in ~/Library/Group Containers/group.com.docker/ | ✓ |
| Project dir | Copy to .planning/ — tracked in git | |
| Both locations | Backup to both same dir and .planning/ for redundancy | |

**User's choice:** Same dir .bak (Recommended)

### Backup Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, both files (Recommended) | Back up both settings-store.json and settings.json — belt and suspenders | ✓ |
| Only settings-store.json | Research says only settings-store.json matters for v29.3.1 | |
| You decide | Claude picks based on completeness preference | |

**User's choice:** Yes, both files (Recommended)

---

## Validation Depth

### Thoroughness

| Option | Description | Selected |
|--------|-------------|----------|
| Full validation (Recommended) | All 5 requirements + verify Apple VF backend + resolve diskSizeMiB discrepancy + check actual Docker.raw size | ✓ |
| Requirements only | Just the 5 stated requirements — skip research gap items | |
| You decide | Claude picks | |

**User's choice:** Full validation (Recommended)

### Fail Mode

| Option | Description | Selected |
|--------|-------------|----------|
| Hard stop (Recommended) | Abort entire migration — fix the issue first, then re-run pre-flight | ✓ |
| Warn and continue | Log the failure, let user decide whether to proceed | |
| You decide | Claude picks | |

**User's choice:** Hard stop (Recommended)

### Volume Check

| Option | Description | Selected |
|--------|-------------|----------|
| diskutil info (Recommended) | Run diskutil info /Volumes/Unitek-B and parse filesystem type — authoritative | ✓ |
| df -T check | Simpler but less reliable filesystem detection | |
| You decide | Claude picks | |

**User's choice:** diskutil info (Recommended)

### Space Check

| Option | Description | Selected |
|--------|-------------|----------|
| 2x Docker.raw (Recommended) | At least double the actual size — accounts for growth during copy + future use | ✓ |
| 1.5x Docker.raw | 50% headroom — reasonable margin | |
| Just enough | Only require actual Docker.raw size + small buffer | |

**User's choice:** 2x Docker.raw (Recommended)

---

## Claude's Discretion

- Exact order of pre-flight checks (optimize for fail-fast)
- Specific pgrep patterns for Docker processes
- How to present pre-flight results to user

## Deferred Ideas

None — discussion stayed within phase scope
