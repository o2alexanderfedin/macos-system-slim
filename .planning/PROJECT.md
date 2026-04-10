# Docker Data Migration to External Volume

## What This Is

A configuration project to move Docker Desktop's entire data store (images, containers, volumes, build cache) from the default macOS internal disk to an external volume at `/Volumes/Unitek-B/Docker/`. This frees up space on the primary drive while preserving all existing Docker data.

## Core Value

Docker data lives on the external volume so the internal disk is no longer constrained by Docker storage.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Docker Desktop data folder relocated to `/Volumes/Unitek-B/Docker/`
- [ ] Existing Docker images, containers, and volumes migrated (not lost)
- [ ] Docker Desktop starts and functions correctly from the new location
- [ ] Internal disk space reclaimed after migration
- [ ] Process is documented for repeatability

### Out of Scope

- Docker Compose project changes — only moving the data store location
- Kubernetes configuration — not currently enabled
- Docker networking changes — keeping existing network config
- Automated mount scripts — assumes `/Volumes/Unitek-B/` is already mounted

## Context

- **Platform:** macOS Darwin 25.4.0
- **Docker Desktop:** v29.3.1 (desktop-linux context)
- **Current data location:** `/Users/alexanderfedin/Library/Containers/com.docker.docker/Data/vms/0/data`
- **Current disk allocation:** ~60GB (`diskSizeMiB: 61035`)
- **Target location:** `/Volumes/Unitek-B/Docker/`
- **Target volume:** External USB volume (Unitek-B), already mounted and empty
- **Docker Desktop settings file:** `~/Library/Group Containers/group.com.docker/settings.json`
- **Approach:** Change `dataFolder` in Docker Desktop settings.json (built-in feature)
- **Data preservation:** Migrate existing data via copy before switching

## Constraints

- **Docker must be stopped:** Cannot change dataFolder while Docker Desktop is running
- **External volume availability:** Docker won't start if `/Volumes/Unitek-B/` is not mounted
- **File system compatibility:** External volume must support the Docker VM disk image format
- **Atomicity:** Migration should be all-or-nothing to avoid partial state

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use `dataFolder` setting over symlink | Built-in Docker Desktop feature, cleaner than symlink hacks | — Pending |
| Migrate data instead of fresh start | User wants to preserve existing images and containers | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? -> Move to Out of Scope with reason
2. Requirements validated? -> Move to Validated with phase reference
3. New requirements emerged? -> Add to Active
4. Decisions to log? -> Add to Key Decisions
5. "What This Is" still accurate? -> Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-09 after initialization*
