# Technology Stack

**Project:** Docker Desktop data migration to external volume (macOS)
**Researched:** 2026-04-09
**Docker Desktop version:** 29.3.1 (settings version 36)

---

## Recommended Approach: settings-store.json + Manual Copy

The migration has two independent sub-problems: (1) telling Docker Desktop where its disk image lives, and (2) physically moving that disk image. Each has a right tool.

### Sub-problem 1: Telling Docker Desktop the new location

**Use:** Direct edit of `settings-store.json` (primary) and `settings.json` (secondary — kept in sync automatically).

**Why:** Docker Desktop stores its data path in two files:

- `~/Library/Group Containers/group.com.docker/settings-store.json` — the canonical store (keys are PascalCase: `DataFolder`, `DiskSizeMiB`)
- `~/Library/Group Containers/group.com.docker/settings.json` — a legacy/companion file (keys are camelCase: `dataFolder`, `diskSizeMiB`)

The key `DataFolder` in `settings-store.json` is what Docker Desktop reads on launch to locate the Linux VM disk image. Changing this to `/Volumes/Unitek-B/Docker/` before starting Docker will cause Docker Desktop to look there for `Docker.raw`.

**Confidence:** HIGH — confirmed by live inspection of the running system. The current value is:
```json
"DataFolder": "/Users/alexanderfedin/Library/Containers/com.docker.docker/Data/vms/0/data"
```

**Why NOT the GUI:** Docker Desktop's Settings → Resources → Disk image location UI uses `rename()` under the hood, which fails with EXDEV (cross-device link error) when source and destination are on different filesystems. This is a documented kernel limitation — `rename()` cannot cross device boundaries. The GUI move has been broken for external volumes since at least Docker Desktop 4.18 and remains broken through 4.45 (no fix in release notes). Confirmed broken in GitHub issues #6803, #6797, #7310.

**Why NOT symlink on the Group Containers directory:** Moving `~/Library/Group Containers/group.com.docker/` to the external drive and symlinking it back is fragile. macOS security policies (TCC, sandbox entitlements) can break when the Group Container directory is behind a symlink pointing to an external volume, and Docker Desktop's own socket and daemon files live there too. Several users report Docker hanging on startup with this approach.

### Sub-problem 2: Moving the Docker.raw disk image

**Use:** `cp` with progress, not `rsync`, not `mv`.

The target file is `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`. Current size: **32 GB on disk** (disk allocation shows `DiskSizeMiB: 32768` in settings-store.json; settings.json shows the old limit of 61035 but the actual file is 32 GB). The external volume `/Volumes/Unitek-B` is APFS with 1.5 TB free — plenty of space.

**Why `cp` not `rsync`:** `rsync` by default skips sparse file optimization and can expand a sparse `.raw` file to its full allocated size. A 32 GB sparse file that is only 10% utilized can balloon to 32 GB on disk with naive rsync. Use `cp` which preserves sparse file structure on APFS-to-APFS copies (both source internal SSD and Unitek-B are APFS).

**Why `cp` not `mv`:** `mv` between devices falls back to copy+delete. That fallback does not preserve sparse files reliably. Use explicit `cp` to control behavior, then verify before deleting.

**Preferred command:**
```bash
cp -c ~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw \
       /Volumes/Unitek-B/Docker/Docker.raw
```

The `-c` flag on macOS (clonefile) performs a copy-on-write clone if the filesystem supports it. Since both source (internal APFS) and destination (APFS on Unitek-B) are APFS, this may be a near-instant metadata operation. If clonefile fails (cross-device APFS does not support cross-volume clones), macOS falls back to a standard byte copy. The command still works — it just takes longer.

**Alternative if `-c` fails:** Use `ditto` which is macOS-native, preserves extended attributes, and handles large files reliably:
```bash
ditto ~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw \
      /Volumes/Unitek-B/Docker/Docker.raw
```

**Confidence:** HIGH for the approach; MEDIUM for `-c` clone optimization (depends on APFS cross-device behavior which varies by macOS version).

---

## Full Tool Inventory

| Tool | Purpose | Why This One |
|------|---------|--------------|
| `cp -c` (macOS built-in) | Copy Docker.raw to external volume | APFS-aware, sparse-file-safe, available without install |
| `ditto` (macOS built-in) | Fallback copy if cp -c fails | Preserves xattrs, macOS-native, reliable on large files |
| `python3 -c` / `jq` | Read and patch settings-store.json | JSON mutation; python3 ships with macOS, jq is optional |
| `docker context ls` | Verify Docker context after migration | Confirms Docker is using the right backend |
| `docker run hello-world` | Smoke test post-migration | Validates images and daemon both work |
| `docker info` | Inspect daemon data root from inside Docker | Shows effective data location from daemon perspective |
| `launchctl` / `killall` | Stop Docker Desktop before changes | Required — cannot change DataFolder while Docker is running |

### No additional software required

Every tool in the migration is a macOS built-in or a Docker CLI command already installed. No Homebrew packages, no Python libraries, no third-party utilities.

---

## File Paths Reference

| File | Path | Purpose |
|------|------|---------|
| Canonical settings | `~/Library/Group Containers/group.com.docker/settings-store.json` | `DataFolder` key controls where Docker looks for its VM disk |
| Legacy settings | `~/Library/Group Containers/group.com.docker/settings.json` | Companion file; also has `dataFolder` (camelCase); update both |
| VM disk image | `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` | The 32 GB file containing all Docker images, containers, volumes |
| Target directory | `/Volumes/Unitek-B/Docker/` | Must exist and be writable before migration |

---

## What NOT to Do

### Do NOT use the GUI to change Disk image location to an external volume
The UI performs a `rename()` syscall which fails EXDEV across devices. Docker Desktop then silently reverts to the old path. The bug is open and unfixed through at least Docker Desktop 4.45 (August 2025).
**Confidence:** HIGH — multiple GitHub issues confirm this; release notes show no fix.

### Do NOT symlink the entire Group Containers directory
Moving `~/Library/Group Containers/group.com.docker/` to the external drive and replacing it with a symlink puts Docker's socket files, daemon configuration, and analytics data all behind a symlink to a volume that may not be mounted. Docker Desktop hangs on startup when the volume is absent.

### Do NOT use rsync without sparse-file flags
Naive `rsync` expands Docker.raw from its actual used size to its full 32 GB allocated size. If Docker.raw is sparse and only 8 GB is actually written, rsync writes 32 GB.

### Do NOT move Docker.raw while Docker Desktop is running
The Linux VM holds Docker.raw open with an exclusive lock. Copying while running will produce a corrupt destination file.

### Do NOT use Finder to move Docker.raw
Docker's own FAQ explicitly warns against this: "Do not move the file directly in Finder as this can cause Docker Desktop to lose track of the file." Use Terminal commands only.

---

## External Volume Compatibility Note

`/Volumes/Unitek-B` is an APFS volume (confirmed by `diskutil info`). Docker.raw is a raw disk image format that Docker's Linux VM mounts directly. APFS on an external USB drive is fully compatible with Docker.raw storage. The VM does not care about the host filesystem — it opens Docker.raw as a block device via the virtualization framework.

**Confidence:** HIGH — Docker.raw is just a file; the host filesystem only needs to support large files (APFS does, >4 GB files are fine) and basic POSIX file operations.

---

## Sources

- Docker Desktop Settings documentation: https://docs.docker.com/desktop/settings-and-maintenance/settings/
- Docker for Mac FAQ (Finder warning): https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/
- GitHub issue #7310 (cross-device link error on external volume): https://github.com/docker/for-mac/issues/7310
- GitHub issue #6803 (Docker hangs on external volume location change): https://github.com/docker/for-mac/issues/6803
- Docker Desktop release notes (4.36–4.45, no external drive fix found): https://docs.docker.com/desktop/release-notes/
- Yrol's blog — Docker.raw symlink approach (symlink only the .raw file): https://www.yrol.blog/posts/moving-docker-data-to-an-external-drive-on-macos
- Dev.to guide — group.com.docker symlink approach: https://dev.to/felipebelluco/how-to-move-docker-data-to-an-external-drive-on-macos-4h79
- Live system inspection (settings-store.json, Docker.raw, diskutil info) — HIGH confidence baseline
