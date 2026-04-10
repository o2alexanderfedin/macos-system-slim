# Requirements: Docker Data Migration

**Defined:** 2026-04-09
**Core Value:** Docker data lives on the external volume so the internal disk is no longer constrained by Docker storage.

## v1 Requirements

Requirements for migration completion. Each maps to roadmap phases.

### Pre-flight Validation

- [x] **PREFLT-01**: Docker Desktop is verified fully stopped (including menubar agent and background processes)
- [x] **PREFLT-02**: External volume `/Volumes/Unitek-B/` is verified as APFS format
- [x] **PREFLT-03**: External volume has sufficient free space for Docker.raw (~24 GB on-disk)
- [x] **PREFLT-04**: `settings-store.json` is backed up before any modifications
- [x] **PREFLT-05**: Target directory `/Volumes/Unitek-B/Docker/` is created and writable

### Data Migration

- [x] **MIGR-01**: `Docker.raw` is copied from internal disk to `/Volumes/Unitek-B/Docker/` preserving APFS sparse structure
- [x] **MIGR-02**: Copy size is verified to match original (file size comparison)
- [x] **MIGR-03**: Copy progress is visible during transfer
- [x] **MIGR-04**: Fallback copy method (ditto) is available if `cp -c` fails

### Configuration Update

- [x] **CONF-01**: `DataFolder` key in `settings-store.json` is updated to `/Volumes/Unitek-B/Docker`
- [x] **CONF-02**: Docker Desktop starts successfully from the new location

### Verification

- [x] **VERIF-01**: All pre-existing Docker images are present after migration (`docker images`)
- [x] **VERIF-02**: All pre-existing containers are present after migration (`docker ps -a`)
- [x] **VERIF-03**: Smoke test container runs successfully (`docker run --rm hello-world`)

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
| PREFLT-01 | Phase 1: Pre-flight | Complete |
| PREFLT-02 | Phase 1: Pre-flight | Complete |
| PREFLT-03 | Phase 1: Pre-flight | Complete |
| PREFLT-04 | Phase 1: Pre-flight | Complete |
| PREFLT-05 | Phase 1: Pre-flight | Complete |
| MIGR-01 | Phase 2: Data Copy | Complete |
| MIGR-02 | Phase 2: Data Copy | Complete |
| MIGR-03 | Phase 2: Data Copy | Complete |
| MIGR-04 | Phase 2: Data Copy | Complete |
| CONF-01 | Phase 3: Cutover and Verification | Complete |
| CONF-02 | Phase 3: Cutover and Verification | Complete |
| VERIF-01 | Phase 3: Cutover and Verification | Complete |
| VERIF-02 | Phase 3: Cutover and Verification | Complete |
| VERIF-03 | Phase 3: Cutover and Verification | Complete |
| CLEAN-01 | Phase 4: Cleanup and Hardening | Pending |
| CLEAN-02 | Phase 4: Cleanup and Hardening | Pending |
| CLEAN-03 | Phase 4: Cleanup and Hardening | Pending |
| CLEAN-04 | Phase 4: Cleanup and Hardening | Pending |

**Coverage:**
- v1 requirements: 18 total
- Mapped to phases: 18
- Unmapped: 0

---
*Requirements defined: 2026-04-09*
*Last updated: 2026-04-09 after roadmap creation*
