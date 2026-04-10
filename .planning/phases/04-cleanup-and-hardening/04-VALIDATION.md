---
phase: 4
slug: cleanup-and-hardening
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-10
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash scripts with inline assertions + settings file inspection |
| **Config file** | none — shell scripts self-validate |
| **Quick run command** | `bash -n .planning/phases/04-cleanup-and-hardening/*.sh && echo "Syntax OK"` |
| **Full suite command** | `bash .planning/phases/04-cleanup-and-hardening/verify-cleanup.sh` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash -n .planning/phases/04-cleanup-and-hardening/*.sh && echo "Syntax OK"`
- **After every plan wave:** Run `bash .planning/phases/04-cleanup-and-hardening/verify-cleanup.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | CLEAN-01, CLEAN-02, CLEAN-03, CLEAN-04 | script validation | `bash -n cleanup.sh && test -x cleanup.sh` | ❌ W0 | ⬜ pending |
| 04-01-02 | 01 | 1 | CLEAN-01, CLEAN-02, CLEAN-03, CLEAN-04 | script validation | `bash -n verify-cleanup.sh && test -x verify-cleanup.sh` | ❌ W0 | ⬜ pending |
| 04-02-01 | 02 | 2 | CLEAN-01, CLEAN-02, CLEAN-03, CLEAN-04 | execution + verification | `grep -c "PASS" cleanup-results.txt \| xargs test 4 -le` | ❌ W0 | ⬜ pending |
| 04-02-02 | 02 | 2 | All | human checkpoint | exempt (checkpoint:human-verify) | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements.* Same approach as Phases 1-3.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Docker Desktop settings UI reflects disabled auto-update | CLEAN-03 | GUI element observation | Open Docker Desktop → Settings → General → verify auto-update unchecked |
| Docker Desktop does not start on login after reboot | CLEAN-04 | Requires system reboot to confirm | Reboot Mac, verify Docker does not auto-start |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
