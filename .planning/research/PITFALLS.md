# Domain Pitfalls: Docker Desktop Data Migration to External Volume on macOS

**Domain:** Docker Desktop macOS external volume migration
**Researched:** 2026-04-09
**Confidence:** HIGH (multiple official GitHub issues, Docker docs, community reports)

---

## Critical Pitfalls

Mistakes that cause data loss, bricked Docker installs, or required full resets.

---

### Pitfall 1: Using `rename`/`mv` Across Filesystem Boundaries (Cross-Device Link Error)

**What goes wrong:** Docker Desktop's GUI "change disk image location" button internally uses `rename()` to relocate the VM disk. On macOS, `rename()` cannot cross filesystem boundaries. Attempting to move from the internal APFS volume to an external USB volume via the GUI throws:

```
failed to rename VM disk: rename /Users/<user>/Library/Containers/com.docker.docker/Data/vms/0/data /Volumes/Unitek-B/Docker: cross-device link
```

Similarly, using `mv` on the terminal to move the `vms/0/data` directory directly will fail with the same OS-level error. The GUI may appear to hang indefinitely (the progress spinner spins forever) without reporting the error clearly.

**Why it happens:** macOS `rename()` is an atomic operation within a single filesystem. Across mount points, it is undefined and rejected by the kernel. Docker Desktop's internal move logic relies on this syscall.

**Consequences:** Docker gets stuck in a "restarting" state with no rollback. The data directory is neither at the old nor new location — requiring manual intervention to restore. Users have reported needing a factory reset.

**Prevention:** Never use the Docker Desktop GUI "Browse" button to move data to a different physical volume. Never use `mv` across mount points. Always use `rsync` or `cp -a` to copy data byte-for-byte, then update `settings-store.json` (or `settings.json` for Docker Desktop 4.34 and earlier) manually before starting Docker.

**Detection:** GUI spinner runs indefinitely with no progress. `docker info` hangs. Check Docker Desktop logs at `~/Library/Containers/com.docker.docker/Data/log/host/`.

**Phase:** Pre-migration copy step. Must use `rsync`, not `mv`.

**Source:** [GitHub issue #7310](https://github.com/docker/for-mac/issues/7310), [GitHub issue #6803](https://github.com/docker/for-mac/issues/6803)

---

### Pitfall 2: Wrong Settings File Name (settings.json vs settings-store.json)

**What goes wrong:** The project context references `settings.json`. Docker Desktop renamed this file to `settings-store.json` in version 4.35. Editing the wrong file (or a stale `settings.json`) leaves the actual settings unchanged, so Docker silently ignores the `dataFolder` change and starts from the original location. The user believes migration succeeded but Docker is still reading from internal disk.

**Why it happens:** Docker Desktop 4.35+ stores all persistent settings in `settings-store.json`. The old `settings.json` may still exist but is no longer authoritative. Many online guides (including well-ranked ones) were written before this rename and still reference `settings.json`.

**Consequences:** The internal disk is not freed. The external volume appears to be working (Docker starts fine) but is actually unused. Space on the internal drive is never reclaimed.

**Prevention:**
- Docker Desktop v29.3.1 (the installed version) is well past 4.35, so the authoritative file is `~/Library/Group Containers/group.com.docker/settings-store.json`.
- Verify by running: `cat ~/Library/Group\ Containers/group.com.docker/settings-store.json | python3 -m json.tool | grep -i datafolder`
- Always confirm the `dataFolder` change is present in the file Docker actually reads before starting Docker.

**Detection:** Docker starts successfully but `docker info | grep "Docker Root Dir"` still shows the internal path. Disk usage on internal drive is unchanged after migration.

**Phase:** Settings update step. Verify which file is authoritative for the installed version before editing anything.

**Source:** [Docker forum thread](https://forums.docker.com/t/docker-desktop-application-is-not-starting-on-my-mac/137880/18), [GitHub issue #7503](https://github.com/docker/for-mac/issues/7503)

---

### Pitfall 3: Docker Desktop Auto-Update Destroys External Volume Configuration

**What goes wrong:** Docker Desktop auto-updates have a documented history of wiping or ignoring custom `dataFolder` configurations. Specifically:
- Version 4.3.2 upgrade destroyed all Docker data on external volumes: the upgrade process did not follow the symlink, removed existing directories, and re-created a fresh 64GB `Docker.raw` on the local volume.
- Version 4.31.0 upgrade removed all containers, images, and volumes for users with default and custom configurations alike.
- Multiple earlier versions (1.13.0, 2.1.0, 3.4, 4.18.0) had similar patterns.

**Why it happens:** The Docker Desktop upgrade process does not validate custom storage configurations before reinitializing. It checks whether the data directory exists at the expected path; if the symlink is stale or the external volume is not yet mounted at upgrade time, it treats the config as missing and re-creates defaults locally.

**Consequences:** Complete data loss of all images, containers, and volumes. The 60GB `Docker.raw` on the external volume becomes orphaned (not deleted, but Docker no longer references it).

**Prevention:**
1. Disable Docker Desktop auto-update before performing the migration: Settings > Software Updates > uncheck "Automatically check for updates".
2. Before any Docker Desktop upgrade after migration, manually verify the external volume is mounted and the `dataFolder` path exists.
3. Keep a backup of `settings-store.json` in version control or a separate location.
4. Document the current Docker Desktop version in the project so deliberate upgrades are a conscious decision.

**Detection:** After an upgrade, `docker images` returns empty. `docker info` shows the internal path. The external volume still has the old `Docker.raw` but Docker is not using it.

**Phase:** Ongoing maintenance. Auto-update must be disabled as part of the migration procedure.

**Source:** [GitHub issue #6215](https://github.com/docker/for-mac/issues/6215), [GitHub issue #7319](https://github.com/docker/for-mac/issues/7319), [GitHub issue #5754](https://github.com/docker/for-mac/issues/5754)

---

### Pitfall 4: External Volume Filesystem Format Incompatibility

**What goes wrong:** Docker Desktop requires the external volume hosting `dataFolder` to be formatted as APFS. Volumes formatted as exFAT, FAT32, HFS+ (Mac OS Extended), or NTFS cause Docker to fail at startup. The error is not always clearly reported — Docker may silently fail to start, or start but immediately crash.

**Why it happens:** Docker's VM disk image (`Docker.raw`) uses ext4 internally. The outer container file requires a host filesystem that supports POSIX permissions, sparse files, and large file sizes. exFAT and FAT32 do not support permissions or sparse files. HFS+ has case-insensitivity issues. APFS supports all required characteristics.

**Consequences:** Docker Desktop fails to start after migration. The `Docker.raw` file may be created on the external volume but Docker crashes immediately after.

**Prevention:**
- Verify the target volume format before starting: `diskutil info /Volumes/Unitek-B | grep "Type (Bundle)"`
- The result must show `apfs`. If it shows anything else, reformat to APFS before proceeding.
- Note: reformatting destroys all existing data on the volume — confirm the Unitek-B volume is genuinely empty before the migration.

**Detection:** Docker fails to start after migration. `diskutil info` on the volume shows a non-APFS type. Docker logs show filesystem permission errors.

**Phase:** Pre-flight check. Must be verified before copying any data.

**Source:** [Docker forum thread - disk image location not working](https://forums.docker.com/t/macos-disk-image-location-not-working/136587), [GitHub issue #6291](https://github.com/docker/for-mac/issues/6291)

---

### Pitfall 5: Docker VMM Incompatibility with External USB Volumes

**What goes wrong:** Docker Desktop v4.35+ introduced Docker VMM as a new virtualization backend (replacing QEMU). Docker VMM has a documented bug where bind mounts to external USB volumes fail because it incorrectly prepends `/host_mnt` to external volume paths:

```
bind source path does not exist: /host_mnt/Volumes/Unitek-B/sourcefolder
```

This affects not just `dataFolder` but also any container bind mounts to paths on external volumes.

**Why it happens:** Docker VMM's path translation logic does not correctly handle macOS mount points outside the primary drive. It was designed for local paths under `/Users` and does not generalize to external volumes.

**Consequences:** Containers that mount paths on the external volume (e.g., development bind mounts) fail to start. The Docker daemon itself may run, but containers needing external paths are broken.

**Prevention:**
- Check Docker Desktop settings: Settings > General > Virtual Machine Options.
- If Docker VMM is selected, switch to Apple Virtualization Framework for full external volume compatibility.
- Do not use Docker VMM until this issue is resolved upstream (it remained open through Docker Desktop 4.37.2 at minimum).

**Detection:** Container start fails with `bind source path does not exist` error containing `/host_mnt`. Running `docker info | grep "Docker VMM"` in the daemon info.

**Phase:** Post-migration verification. Test a container with a bind mount to the external volume before declaring success.

**Source:** [GitHub issue #7480](https://github.com/docker/for-mac/issues/7480)

---

## Moderate Pitfalls

Mistakes that cause significant trouble but are recoverable without data loss.

---

### Pitfall 6: Starting Docker Before the Copy is Complete

**What goes wrong:** If Docker Desktop is started while `Docker.raw` is still being copied to the external volume (e.g., the rsync is still running, or the copy was interrupted), Docker will open a partially-written disk image. This causes the VM to crash at mount time, and Docker attempts to repair or re-initialize the image, potentially truncating it.

**Why it happens:** `Docker.raw` is a raw disk image file. Docker mounts it as a block device. Partial images fail mount with a corrupt superblock error. Docker's error recovery path re-creates the file from scratch rather than aborting.

**Consequences:** The partial `Docker.raw` is overwritten with an empty image. The original on the internal drive (if not yet deleted) is unaffected, but the user must restart the copy.

**Prevention:**
- Do not start Docker Desktop until the copy is verified complete.
- After `rsync`, verify the file size matches: `du -sh /Volumes/Unitek-B/Docker/` vs `du -sh ~/Library/Containers/com.docker.docker/Data/vms/0/data/`
- Use `rsync --checksum` or verify with `md5` on the `Docker.raw` file specifically before proceeding.

**Detection:** Docker starts and initializes fresh images. `docker images` is empty after starting from the external volume.

**Phase:** Copy verification step. Must be explicit in the procedure.

---

### Pitfall 7: Not Keeping the Original Data Until Verification is Complete

**What goes wrong:** Users delete the original `vms/0/data/` directory from the internal drive immediately after the copy, before confirming Docker works correctly from the external volume. If Docker fails to start from the external location (for any of the reasons above), there is no fallback.

**Why it happens:** The goal is freeing internal disk space, so deleting the original feels like the final step. But it should be the last step after full verification.

**Consequences:** If migration fails and the original is deleted, all Docker images and containers are permanently lost. Recovery requires a factory reset and re-pulling all images.

**Prevention:**
1. Complete the copy to external volume.
2. Update `settings-store.json` to point to external volume.
3. Start Docker and verify: `docker info`, `docker images`, `docker ps -a`, run a test container.
4. Only after all verification passes, delete the original internal data directory.

**Detection:** Migration failure with no original to fall back to.

**Phase:** Post-migration verification must precede internal disk cleanup.

---

### Pitfall 8: External Volume Not Mounted When Docker Starts (Boot-Time Failure)

**What goes wrong:** After migration, Docker Desktop is configured to start at login. The Unitek-B USB volume may not be mounted by the time Docker Desktop launches at login. Docker attempts to access `dataFolder` at `/Volumes/Unitek-B/Docker/`, finds it missing, and either fails to start silently or (in some versions) re-initializes a fresh data directory at the default internal location.

**Why it happens:** macOS mounts external USB volumes asynchronously during login. Docker Desktop's launchd agent starts quickly and may race ahead of the volume mount. There is no built-in mechanism in Docker Desktop to wait for external volumes.

**Consequences:** Docker appears to start but shows no images or containers. In worst case, Docker re-creates a new empty `Docker.raw` internally and any work done in containers is lost.

**Prevention:**
- Disable "Start Docker Desktop when you sign in" in Docker Desktop settings.
- Adopt the habit of: plug in Unitek-B, verify it mounts, then start Docker Desktop manually.
- Verify the volume is mounted before every Docker Desktop launch: `ls /Volumes/Unitek-B/Docker/Docker.raw` must succeed.
- Document this dependency explicitly in the project so it is not forgotten over time.

**Detection:** Docker starts but `docker images` is empty. Check whether `/Volumes/Unitek-B/` is visible in Finder before starting Docker.

**Phase:** Post-migration operational procedure. Must be documented as an ongoing constraint.

---

## Minor Pitfalls

Issues that create friction but are easily corrected.

---

### Pitfall 9: Copying Socket Files or Lock Files During Migration

**What goes wrong:** The `vms/0/data/` directory may contain Unix socket files (`.sock`), lock files, and log files that are specific to the running Docker instance. Copying these to the external volume and starting Docker against them causes startup errors because the sockets reference the old process tree.

**Prevention:** Use `rsync` with exclusions:
```bash
rsync -avz --progress \
  --exclude='*.sock' \
  --exclude='*.lock' \
  --exclude='*.log' \
  /path/to/source/ /Volumes/Unitek-B/Docker/
```

**Detection:** Docker fails to start with `connection refused` on a socket path, or log output shows stale socket cleanup errors.

**Phase:** Copy step. Rsync flags must be set correctly.

---

### Pitfall 10: I/O Performance Degradation on USB vs Internal NVMe

**What goes wrong:** Docker image builds, container startup times, and `docker pull` operations are noticeably slower when the `Docker.raw` disk image resides on a USB 3 external drive compared to internal NVMe. The performance difference is significant for I/O-intensive workloads (e.g., large builds, database containers).

**Why it happens:** USB 3 has significantly lower random I/O performance than internal NVMe, and Docker's VM performs many small random reads and writes to the disk image during normal operation.

**Consequences:** Not a data-loss risk, but a workflow degradation. Builds that took 2 minutes internally may take 5+ minutes from USB.

**Prevention:** This is an accepted tradeoff for this project (freeing internal disk space is the goal). Document the performance expectation so it is not treated as a bug post-migration. If build performance becomes unacceptable, the mitigation is to move time-sensitive builds to internal storage temporarily.

**Detection:** Subjective slowness in `docker build`, `docker pull`, container start times.

**Phase:** Acceptance criteria. Note the tradeoff explicitly.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Pre-flight checks | Filesystem format (exFAT/HFS+) | Run `diskutil info /Volumes/Unitek-B` and verify APFS before anything else |
| Pre-flight checks | Virtualization backend | Check Settings > General and confirm Apple Virtualization Framework, not Docker VMM |
| Settings file edit | Wrong file name | Confirm `settings-store.json` is the authoritative file for Docker Desktop v29.3.1 |
| Data copy | Using `mv` or GUI move | Only use `rsync` with socket/lock/log exclusions |
| Data copy | Incomplete copy | Verify byte counts and `Docker.raw` size match before proceeding |
| Post-copy verification | Starting Docker too early | Explicitly verify copy completeness first |
| Post-copy verification | Deleting original too early | Keep original until `docker images` and container smoke test pass |
| Post-migration operations | Auto-update wiping config | Disable auto-update immediately after migration succeeds |
| Post-migration operations | Startup race condition | Disable "Start at login", mount volume manually before launching Docker |
| Ongoing maintenance | Future Docker Desktop upgrades | Always verify external volume is mounted and `settings-store.json` is intact before upgrading |

---

## Sources

- [GitHub docker/for-mac #7310 — cross-device link error on external volume](https://github.com/docker/for-mac/issues/7310)
- [GitHub docker/for-mac #6803 — Docker hangs on disk image location change to external volume](https://github.com/docker/for-mac/issues/6803)
- [GitHub docker/for-mac #6215 — upgrade 4.3.2 destroyed external volume image data](https://github.com/docker/for-mac/issues/6215)
- [GitHub docker/for-mac #6291 — Docker Desktop does not start with dataFolder on external SSD](https://github.com/docker/for-mac/issues/6291)
- [GitHub docker/for-mac #7480 — Docker VMM cannot bind to external USB volumes](https://github.com/docker/for-mac/issues/7480)
- [GitHub docker/for-mac #7319 — 4.31.0 upgrade removed all containers, images, volumes](https://github.com/docker/for-mac/issues/7319)
- [Docker Desktop FAQs for Mac](https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/)
- [Docker Desktop VMM documentation](https://docs.docker.com/desktop/features/vmm/)
- [Medium: How to Move Docker Data to External Drive on macOS](https://medium.com/@felipebelluco/how-to-move-docker-data-to-an-external-drive-on-macos-3ca2c35771a3)
- [Docker forum: macOS Disk image location not working](https://forums.docker.com/t/macos-disk-image-location-not-working/136587)
- [Docker forum: Unable to change Disk Image Location to HDD](https://forums.docker.com/t/unable-to-change-disk-image-location-setting-to-hdd/135590)
