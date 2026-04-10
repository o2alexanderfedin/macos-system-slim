---
phase: 2
slug: data-copy
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-10
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash scripts with inline assertions (no test framework — system admin task) |
| **Config file** | none — shell scripts self-validate |
| **Quick run command** | `bash -n .planning/phases/02-data-copy/*.sh && echo "Syntax OK"` |
| **Full suite command** | `bash .planning/phases/02-data-copy/verify-copy.sh` |
| **Estimated runtime** | ~5 seconds (verification only, not the copy itself) |

---

## Sampling Rate

- **After every task commit:** Run `bash -n .planning/phases/02-data-copy/*.sh && echo "Syntax OK"`
- **After every plan wave:** Run `bash .planning/phases/02-data-copy/verify-copy.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | MIGR-01, MIGR-03, MIGR-04 | script validation | `bash -n .planning/phases/02-data-copy/copy-docker.sh && test -x .planning/phases/02-data-copy/copy-docker.sh` | ❌ W0 | ⬜ pending |
| 02-01-02 | 01 | 1 | MIGR-02 | script validation | `bash -n .planning/phases/02-data-copy/verify-copy.sh && test -x .planning/phases/02-data-copy/verify-copy.sh` | ❌ W0 | ⬜ pending |
| 02-02-01 | 02 | 2 | MIGR-01, MIGR-02, MIGR-03 | execution + verification | `grep -c "PASS" .planning/phases/02-data-copy/copy-results.txt \| xargs test 3 -le` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements.* Shell scripts are self-contained — no test framework installation needed. Validation uses bash syntax checking and output pattern matching (same approach as Phase 1).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Copy progress visible during transfer | MIGR-03 | Progress bar is a runtime UX element — can only be observed during the actual multi-minute copy | Run copy-docker.sh and visually confirm percentage updates appear every ~5 seconds |
| Original file unmodified | MIGR-04 | Requires comparing pre/post state of source file | After copy, verify source file stat output matches pre-copy snapshot |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
