# Project Research Summary

**Project:** Docker Desktop data migration to external volume (macOS)
**Domain:** macOS system administration — Docker Desktop storage relocation
**Researched:** 2026-04-09
**Confidence:** HIGH

## Executive Summary

This project is a one-time migration of Docker Desktop's VM disk image (`Docker.raw`) from an internal macOS APFS volume to an external APFS USB volume (`/Volumes/Unitek-B/Docker/`). The migration has two independent sub-problems: physically copying the disk image and redirecting Docker Desktop to the new location. Research consistently identifies a single correct approach: stop Docker completely, copy `Docker.raw` using `cp` or `rsync` (not `mv`, not the GUI), then update `DataFolder` in `settings-store.json` before restarting Docker. All other approaches — using the Docker Desktop GUI, symlinking directories, using `mv` — are documented to fail.

The Docker Desktop GUI's "change disk image location" feature is broken for cross-device (external volume) moves and has been broken since at least Docker Desktop 4.18, remaining unfixed through version 4.45. It internally uses `rename()`, which the macOS kernel rejects across filesystem boundaries with a cross-device link error. The settings file naming also changed in Docker Desktop 4.35: the authoritative file is now `settings-store.json`, not `settings.json`. Since the installed version is 29.3.1, only `settings-store.json` matters.

The primary ongoing risks after migration are: Docker Desktop auto-updates silently reinitializing data from scratch if the external volume is not mounted at update time, and Docker Desktop failing to start at login due to a race between Docker's launch agent and the USB volume mount. Both require explicit operational procedures: disable auto-update immediately after migration, and disable "Start Docker Desktop when you sign in."

## Key Findings

### Recommended Stack

No third-party software is required. Every tool in the migration is a macOS built-in or an already-installed Docker CLI command.

- `cp -c` (macOS built-in): Copy `Docker.raw` preserving APFS sparse-file structure
- `ditto` (macOS built-in): Fallback copy if `cp -c` fails
- `python3 -c` (macOS built-in): Read and patch `settings-store.json`
- `docker info` / `docker images` / `docker run`: Post-migration verification
- `launchctl` / `killall`: Stop Docker Desktop completely before migration

### Expected Features

**Table stakes:**
- Pre-flight: Docker Desktop fully stopped (including menubar agent)
- Pre-flight: External volume mounted, writable, APFS format, sufficient free space
- Copy `Docker.raw` to external volume without data loss
- Update `DataFolder` in `settings-store.json` only
- Verify Docker starts successfully from new location
- Reclaim internal disk space by removing original `Docker.raw` — only after verification

**Differentiators:**
- Keep original `Docker.raw` until verification passes
- Backup `settings-store.json` before editing
- Use copy command with visible progress output
- Post-copy size verification with `stat -f %z`
- Disable Docker Desktop auto-update as part of the procedure
- Disable "Start Docker Desktop when you sign in"

**Anti-features (do NOT do):**
- SHA256 checksum of `Docker.raw` (5+ minutes for 32 GB; size comparison is sufficient)
- Auto-mount scripting (out of scope)
- Using Docker Desktop GUI to move data
- Using `mv` across filesystem boundaries
- Symlinking the Group Containers directory

### Architecture

Docker Desktop's storage is a single file (`Docker.raw`) whose location is controlled by one key (`DataFolder`) in one settings file (`settings-store.json`). The migration changes exactly two things: where the file lives on disk and the value of that key.

**Components:**
1. `Docker.raw` — 32 GB logical, ~24 GB on-disk (APFS sparse); contains all Docker data inside a Linux ext4 partition
2. `settings-store.json` (`DataFolder` key) — `~/Library/Group Containers/group.com.docker/settings-store.json`; value must be the directory path, not the file
3. Verification suite — `docker info`, `docker images`, `docker ps -a`, `docker run --rm hello-world`

### Critical Pitfalls

1. **GUI/mv cross-device failure** — Both use `rename()` which fails EXDEV across filesystems
2. **Wrong settings file** — Docker Desktop 4.35+ uses `settings-store.json`, not `settings.json`
3. **Auto-update data wipe** — Multiple versions re-initialized data from scratch on upgrade
4. **Premature original deletion** — If Docker fails from new location with no original, all data is lost
5. **Docker VMM backend** — Incorrectly prepends `/host_mnt` to external volume paths; must use Apple Virtualization Framework

## Roadmap Implications

### Phase 1: Pre-flight Verification
Confirm APFS format, free space, virtualization backend, Docker stopped; create target directory; backup settings.

### Phase 2: Data Copy
Copy `Docker.raw` using `cp -c` or `rsync --sparse`; verify size match before proceeding.

### Phase 3: Settings Update and Verification
Update `DataFolder` in `settings-store.json`; start Docker; verify images, containers, smoke test.

### Phase 4: Cleanup and Operational Hardening
Delete original; reclaim internal space; disable auto-update and start-at-login.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Confirmed by live system inspection; all tools are macOS built-ins |
| Features | HIGH | Derived from official Docker docs and first-party GitHub issues |
| Architecture | HIGH | `DataFolder` key and file paths confirmed by direct inspection |
| Pitfalls | HIGH | Each critical pitfall backed by Docker's own issue tracker |

### Gaps to Address

- `cp -c` clonefile across APFS volumes: may not be near-instant cross-device; only affects duration
- `diskSizeMiB` discrepancy: `settings-store.json` shows 32768; `settings.json` shows 61035
- Docker VMM status in v29.3.1: verify current backend before migrating

## Sources

**Primary:** Live system inspection; GitHub docker/for-mac #7310, #6803, #6215, #6291, #7480, #7319; Docker Desktop docs.
**Secondary:** Docker Desktop Settings documentation; Docker community forums.

---
*Research completed: 2026-04-09*
*Ready for roadmap: yes*
