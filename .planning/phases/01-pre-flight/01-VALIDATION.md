---
phase: 1
slug: pre-flight
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-09
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell commands (bash verification scripts) |
| **Config file** | none — all checks are inline shell commands |
| **Quick run command** | `bash .planning/phases/01-pre-flight/verify-preflight.sh` |
| **Full suite command** | `bash .planning/phases/01-pre-flight/verify-preflight.sh --full` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick verify
- **After every plan wave:** Run full suite
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01 | 01 | 1 | PREFLT-01 | shell | `pgrep -i docker \|\| echo "PASS"` | n/a | pending |
| 01-02 | 01 | 1 | PREFLT-02 | shell | `diskutil info /Volumes/Unitek-B \| grep "APFS"` | n/a | pending |
| 01-03 | 01 | 1 | PREFLT-03 | shell | `df -g /Volumes/Unitek-B \| awk 'NR==2{print $4}'` | n/a | pending |
| 01-04 | 01 | 1 | PREFLT-04 | shell | `test -f settings-store.json.bak && echo PASS` | n/a | pending |
| 01-05 | 01 | 1 | PREFLT-05 | shell | `test -w /Volumes/Unitek-B/Docker/ && echo PASS` | n/a | pending |

*Status: pending*

---

## Wave 0 Requirements

- Existing infrastructure covers all phase requirements (all checks are macOS built-in commands).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Docker Desktop UI closed | PREFLT-01 | GUI state not scriptable | Visually confirm Docker icon not in menubar |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
