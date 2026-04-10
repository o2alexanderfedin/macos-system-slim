---
phase: 3
slug: cutover-and-verification
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-10
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash scripts with inline assertions + docker CLI verification |
| **Config file** | none — shell scripts self-validate |
| **Quick run command** | `bash -n .planning/phases/03-cutover-and-verification/*.sh && echo "Syntax OK"` |
| **Full suite command** | `bash .planning/phases/03-cutover-and-verification/verify-cutover.sh` |
| **Estimated runtime** | ~10 seconds (verification only, not Docker startup) |

---

## Sampling Rate

- **After every task commit:** Run `bash -n .planning/phases/03-cutover-and-verification/*.sh && echo "Syntax OK"`
- **After every plan wave:** Run `bash .planning/phases/03-cutover-and-verification/verify-cutover.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | CONF-01 | script validation | `bash -n cutover.sh && test -x cutover.sh` | ❌ W0 | ⬜ pending |
| 03-01-02 | 01 | 1 | VERIF-01, VERIF-02, VERIF-03 | script validation | `bash -n verify-cutover.sh && test -x verify-cutover.sh` | ❌ W0 | ⬜ pending |
| 03-02-01 | 02 | 2 | CONF-01, CONF-02 | execution + verification | `grep "CONF-01.*PASS" cutover-results.txt` | ❌ W0 | ⬜ pending |
| 03-02-02 | 02 | 2 | VERIF-01, VERIF-02, VERIF-03 | human checkpoint | exempt (checkpoint:human-verify) | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements.* Shell scripts are self-contained. Docker CLI commands are the test infrastructure. Same approach as Phase 1 and 2.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Docker Desktop visible in menubar after start | CONF-02 | GUI element observation | Open Finder, check menubar for whale icon after startup |
| Known-broken Compose group acceptable | N/A | User decision D-09 | If Compose group fails, confirm this is the pre-existing issue, not migration-related |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
