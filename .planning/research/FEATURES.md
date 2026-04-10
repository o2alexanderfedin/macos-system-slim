# Feature Landscape: Docker Desktop Data Migration to External Volume

**Domain:** macOS Docker Desktop storage relocation
**Researched:** 2026-04-09
**Context:** Moving Docker Desktop's data store from internal macOS disk to `/Volumes/Unitek-B/Docker/` using the built-in `dataFolder` setting in `settings-store.json`.

---

## Table Stakes

Features that MUST work for the migration to be considered successful. Missing any of these = the migration failed.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Pre-flight: verify Docker Desktop is fully stopped | Docker modifies VM disk files while running; copying a live file risks corruption | Low | Must kill menubar agent too, not just quit GUI |
| Pre-flight: verify external volume is mounted and writable | Migration target must exist before any copy begins | Low | `test -d /Volumes/Unitek-B && test -w /Volumes/Unitek-B` |
| Pre-flight: verify sufficient free space on external volume | `Docker.raw` is ~60 GB; external volume needs headroom | Low | Compare `du -sh` of source against `df -h` of target |
| Copy `Docker.raw` disk image to external volume | This single file holds all images, containers, build cache | Medium | Must use `cp` or `rsync` with `-a` to preserve timestamps; cross-device so no atomic rename possible |
| Update `dataFolder` in `settings-store.json` | Tells Docker Desktop where to look on next start | Low | File: `~/Library/Group Containers/group.com.docker/settings-store.json`; field: `linuxVM.dataFolder` |
| Verify Docker Desktop starts successfully from new location | Migration has no value if Docker won't start | Low | Check Docker Desktop status indicator turns green |
| Verify existing images are visible | User requirement: "Existing images, containers, and volumes migrated (not lost)" | Low | `docker images` should list pre-migration images |
| Verify existing containers are visible | Same requirement | Low | `docker ps -a` should list pre-migration containers |
| Verify Docker functions end-to-end | Basic sanity that the engine works | Low | `docker run --rm hello-world` |
| Confirm internal disk space reclaimed | Core value of the project; original `.raw` file must be removed | Low | Delete original only AFTER successful verification; `rm` or Trash |

---

## Differentiators

Features that improve robustness, reversibility, or operator confidence. Not required for a working migration, but worth having.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Pre-copy checksum / size record | Provides a basis for post-copy integrity check | Low | `ls -lh Docker.raw` and `shasum -a 256 Docker.raw` before and after — note: SHA of a 60 GB file takes ~5 minutes |
| Keep original `Docker.raw` until verification passes | Rollback path if Docker won't start from new location | Low | Do not delete source until all verification steps pass; costs temporary double-disk usage |
| Backup `settings-store.json` before editing | Allows trivial rollback of the config change | Low | `cp settings-store.json settings-store.json.bak` |
| Documented rollback procedure | If migration fails, operator knows exactly how to restore | Low | Steps: stop Docker, restore `.bak` settings file, Docker starts from original location |
| Progress feedback during copy | 60 GB copy takes time (USB speed-dependent); silence looks like hang | Low | Use `rsync -ah --progress` instead of bare `cp` |
| Disk image size check post-copy | Guards against silent truncation during copy | Low | Compare byte-exact size with `stat -f %z` on both files |
| Note on external volume auto-mount | Docker won't start if volume is not mounted at boot | Low | Out of scope per PROJECT.md, but worth a one-line warning in the runbook |

---

## Anti-Features

Things to deliberately NOT do.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Use the Docker Desktop GUI "Browse" button to change disk image location | Documented to hang indefinitely on cross-device moves (issues #6803, #6797, #7310); Docker then reverts settings on restart | Edit `settings-store.json` directly after stopping Docker |
| Use `mv` to move `Docker.raw` across volumes | `mv` across filesystems = copy + delete; if interrupted, leaves partial file with no source; also the "cross-device link" error Docker's GUI hits | Use `rsync -a` or `cp -c`; keep source until verified |
| Move the entire `~/Library/Group Containers/group.com.docker/` directory via symlink | Creates symlink loops and home-directory detection failures in Docker Desktop (issue #6668) | Only change the `dataFolder` value; leave the settings directory in place |
| Use symlink from original data path to external volume | Symlink hacks are fragile when Docker is updated or when the volume is unavailable; Docker may create new files at the link target unexpectedly | Use the official `dataFolder` setting; Docker is designed to respect it |
| Delete original `Docker.raw` before verifying the new location works | Unrecoverable data loss if Docker fails to start from the new path | Keep original until `docker run --rm hello-world` succeeds |
| Change `diskSizeMiB` at the same time as `dataFolder` | Changing multiple settings at once makes failures harder to diagnose | Only change `dataFolder`; leave `diskSizeMiB` at current value (61035) |
| Copy while Docker is running | Docker holds the `.raw` file open; copying a live VM disk image produces a corrupt copy | Hard stop Docker Desktop (including menubar agent) before copying |

---

## Feature Dependencies

```
1. Docker Desktop fully stopped
   └─> 2. External volume mounted + writable + sufficient space
         └─> 3. Copy Docker.raw to external volume
               └─> 4. Verify copy integrity (size / checksum)
                     └─> 5. Update dataFolder in settings-store.json
                           └─> 6. Start Docker Desktop
                                 └─> 7. Verify images visible (docker images)
                                 └─> 7. Verify containers visible (docker ps -a)
                                 └─> 7. Verify engine works (docker run --rm hello-world)
                                       └─> 8. Delete original Docker.raw
                                             └─> 9. Confirm internal disk space reclaimed
```

Backup steps (differentiators) sit between steps 2 and 3:
- `cp settings-store.json settings-store.json.bak` — before step 5
- Record source file size/hash — before step 3, compare after step 3

---

## MVP Recommendation

The minimum viable migration requires exactly the table stakes features above and nothing else. Given the project scope (single operator, one-time migration, external volume already mounted), the following differentiators are worth adding at minimal cost:

**Add to MVP:**
- Keep original `Docker.raw` until verification passes (zero extra work, just don't delete early)
- Backup `settings-store.json` before editing (one `cp` command)
- Use `rsync -ah --progress` instead of `cp` (same cost, gives progress visibility on a 60 GB copy)

**Defer:**
- SHA256 checksum of `Docker.raw` (5+ minutes for 60 GB; size comparison is adequate for a local copy)
- Auto-mount scripting (explicitly out of scope per PROJECT.md)

---

## Known Reliability Issues (inform phase research flags)

These are documented Docker Desktop bugs relevant to this migration. They inform which steps need extra care.

| Issue | Severity | Mitigation |
|-------|----------|------------|
| GUI "Browse" hangs on cross-device move | High | Do not use GUI; edit `settings-store.json` directly |
| `settings-store.json` path may differ by Docker Desktop version | Medium | Current versions use `settings-store.json`; older docs reference `settings.json` — verify actual filename before editing |
| Docker reverts `dataFolder` to default if the new path is missing on start | Medium | Ensure external volume is mounted before starting Docker Desktop |
| USB drive performance is substantially slower than NVMe | Low | Acceptable for this use case (development workstation, not CI); pull times will be slower |
| Socket failures reported after relocation in some versions | Low | If Docker starts but CLI can't connect, check `~/.docker/run/docker.sock` and restart Docker Desktop |

---

## Sources

- [Docker Desktop Settings documentation](https://docs.docker.com/desktop/settings-and-maintenance/settings/) — MEDIUM confidence (official docs)
- [Docker Desktop Backup and Restore](https://docs.docker.com/desktop/settings-and-maintenance/backup-and-restore/) — HIGH confidence (official docs)
- [macOS FAQs — Docker disk image storage](https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/) — HIGH confidence (official docs)
- [GitHub issue #6803: Docker hangs on external volume disk image location change](https://github.com/docker/for-mac/issues/6803) — HIGH confidence (first-party issue tracker)
- [GitHub issue #7310: cross-device link error on external volume relocation](https://github.com/docker/for-mac/issues/7310) — HIGH confidence (first-party issue tracker)
- [GitHub issue #6797: Disk image location change fails](https://github.com/docker/for-mac/issues/6797) — HIGH confidence (first-party issue tracker)
- [GitHub issue #6668: Docker fails with home directory on external drive](https://github.com/docker/for-mac/issues/6668) — HIGH confidence (first-party issue tracker)
- [DEV.to: Move Docker data to external drive on macOS](https://dev.to/felipebelluco/how-to-move-docker-data-to-an-external-drive-on-macos-4h79) — LOW confidence (community article)
- [Docker Enterprise admin configuration — dataFolder setting](https://docker-docs.uclv.cu/desktop/enterprise/admin/configure/mac-admin/) — MEDIUM confidence (mirrored official docs, older version)
- [OneUptime: Moving Docker storage to external drive](https://oneuptime.com/blog/post/2026-02-08-how-to-move-dockers-storage-location-to-an-external-drive/view) — LOW confidence (third-party blog)
