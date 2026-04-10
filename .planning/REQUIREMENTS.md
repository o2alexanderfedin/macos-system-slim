# Requirements: Docker Data Migration

**Defined:** 2026-04-09
**Core Value:** Docker data lives on the external volume so the internal disk is no longer constrained by Docker storage.

## v1 Requirements

Requirements for migration completion. Each maps to roadmap phases.

### Pre-flight Validation

- [ ] **PREFLT-01**: Docker Desktop is verified fully stopped (including menubar agent and background processes)
- [ ] **PREFLT-02**: External volume `/Volumes/Unitek-B/` is verified as APFS format
- [ ] **PREFLT-03**: External volume has sufficient free space for Docker.raw (~24 GB on-disk)
- [ ] **PREFLT-04**: `settings-store.json` is backed up before any modifications
- [ ] **PREFLT-05**: Target directory `/Volumes/Unitek-B/Docker/` is created and writable

### Data Migration

- [ ] **MIGR-01**: `Docker.raw` is copied from internal disk to `/Volumes/Unitek-B/Docker/` preserving APFS sparse structure
- [ ] **MIGR-02**: Copy size is verified to match original (file size comparison)
- [ ] **MIGR-03**: Copy progress is visible during transfer
- [ ] **MIGR-04**: Fallback copy method (ditto) is available if `cp -c` fails

### Configuration Update

- [ ] **CONF-01**: `DataFolder` key in `settings-store.json` is updated to `/Volumes/Unitek-B/Docker`
- [ ] **CONF-02**: Docker Desktop starts successfully from the new location

### Verification

- [ ] **VERIF-01**: All pre-existing Docker images are present after migration (`docker images`)
- [ ] **VERIF-02**: All pre-existing containers are present after migration (`docker ps -a`)
- [ ] **VERIF-03**: Smoke test container runs successfully (`docker run --rm hello-world`)

### Cleanup and Hardening

- [ ] **CLEAN-01**: Original `Docker.raw` is deleted from internal disk (only after verification passes)
- [ ] **CLEAN-02**: Internal disk space is confirmed reclaimed
- [ ] **CLEAN-03**: Docker Desktop auto-update is disabled to prevent config wipe
- [ ] **CLEAN-04**: Docker Desktop "Start at login" is disabled to prevent boot-time race with USB mount

## v2 Requirements

Deferred to future. Tracked but not in current roadmap.

### Automation

- **AUTO-01**: Auto-mount script for `/Volumes/Unitek-B/` at login
- **AUTO-02**: Rollback script to revert migration if needed
- **AUTO-03**: Monitoring for Docker.raw disk usage growth

## Out of Scope

| Feature | Reason |
|---------|--------|
| SHA256 checksum verification | 5+ minutes for 32 GB; size comparison sufficient for one-time migration |
| Docker Compose project changes | Only moving data store, not changing project configs |
| Kubernetes configuration | Not currently enabled |
| Auto-mount scripting | Assumes volume is already mounted; automation deferred to v2 |
| Docker networking changes | Keeping existing network configuration |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| PREFLT-01 | Phase 1 | Pending |
| PREFLT-02 | Phase 1 | Pending |
| PREFLT-03 | Phase 1 | Pending |
| PREFLT-04 | Phase 1 | Pending |
| PREFLT-05 | Phase 1 | Pending |
| MIGR-01 | Phase 2 | Pending |
| MIGR-02 | Phase 2 | Pending |
| MIGR-03 | Phase 2 | Pending |
| MIGR-04 | Phase 2 | Pending |
| CONF-01 | Phase 3 | Pending |
| CONF-02 | Phase 3 | Pending |
| VERIF-01 | Phase 3 | Pending |
| VERIF-02 | Phase 3 | Pending |
| VERIF-03 | Phase 3 | Pending |
| CLEAN-01 | Phase 4 | Pending |
| CLEAN-02 | Phase 4 | Pending |
| CLEAN-03 | Phase 4 | Pending |
| CLEAN-04 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 18 total
- Mapped to phases: 18
- Unmapped: 0

---
*Requirements defined: 2026-04-09*
*Last updated: 2026-04-09 after initial definition*
