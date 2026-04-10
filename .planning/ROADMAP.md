# Roadmap: Docker Data Migration to External Volume

## Overview

Four phases take Docker Desktop's data from the internal disk to `/Volumes/Unitek-B/Docker/`. Phase 1 confirms the environment is safe to proceed. Phase 2 copies the data without touching the original. Phase 3 redirects Docker to the new location and verifies all data survived. Phase 4 removes the original and hardens the configuration against auto-update and boot-time race conditions.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Pre-flight** - Verify environment is ready and back up settings before touching anything
- [ ] **Phase 2: Data Copy** - Copy Docker.raw to external volume and confirm copy integrity
- [ ] **Phase 3: Cutover and Verification** - Redirect Docker Desktop to new location and verify all data survived
- [ ] **Phase 4: Cleanup and Hardening** - Remove original data and protect against auto-update and login race

## Phase Details

### Phase 1: Pre-flight
**Goal**: The environment is confirmed safe and all preconditions are met before any data is moved
**Depends on**: Nothing (first phase)
**Requirements**: PREFLT-01, PREFLT-02, PREFLT-03, PREFLT-04, PREFLT-05
**Success Criteria** (what must be TRUE):
  1. Docker Desktop and all background processes (menubar agent, Docker VMM) are confirmed not running
  2. External volume `/Volumes/Unitek-B/` is confirmed APFS format with at least 24 GB free
  3. `/Volumes/Unitek-B/Docker/` directory exists and is writable
  4. `settings-store.json` backup exists at a known safe location before any edits
**Plans:** 2 plans

Plans:
- [ ] 01-01-PLAN.md — Create pre-flight and verification scripts
- [ ] 01-02-PLAN.md — Execute pre-flight and user confirmation

### Phase 2: Data Copy
**Goal**: `Docker.raw` is safely duplicated to the external volume with the original left intact
**Depends on**: Phase 1
**Requirements**: MIGR-01, MIGR-02, MIGR-03, MIGR-04
**Success Criteria** (what must be TRUE):
  1. `Docker.raw` copy exists at `/Volumes/Unitek-B/Docker/Docker.raw`
  2. Copy file size matches original file size (verified with `stat -f %z`)
  3. Copy progress was visible during transfer (not a silent operation)
  4. Original `Docker.raw` on internal disk is still present and unmodified
**Plans**: TBD

### Phase 3: Cutover and Verification
**Goal**: Docker Desktop runs from the external volume with all pre-migration images and containers intact
**Depends on**: Phase 2
**Requirements**: CONF-01, CONF-02, VERIF-01, VERIF-02, VERIF-03
**Success Criteria** (what must be TRUE):
  1. `DataFolder` in `settings-store.json` points to `/Volumes/Unitek-B/Docker`
  2. Docker Desktop starts successfully (`docker info` returns no errors)
  3. All pre-migration images appear in `docker images` output
  4. All pre-migration containers appear in `docker ps -a` output
  5. `docker run --rm hello-world` completes successfully
**Plans**: TBD

### Phase 4: Cleanup and Hardening
**Goal**: Internal disk space is reclaimed and configuration prevents auto-update or login races from destroying the migration
**Depends on**: Phase 3
**Requirements**: CLEAN-01, CLEAN-02, CLEAN-03, CLEAN-04
**Success Criteria** (what must be TRUE):
  1. Original `Docker.raw` is deleted from internal disk (only after Phase 3 verification passes)
  2. Internal disk shows reclaimed space (at least ~24 GB freed)
  3. Docker Desktop auto-update is disabled in settings
  4. "Start Docker Desktop when you sign in" is disabled
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Pre-flight | 0/2 | Planned | - |
| 2. Data Copy | 0/? | Not started | - |
| 3. Cutover and Verification | 0/? | Not started | - |
| 4. Cleanup and Hardening | 0/? | Not started | - |
