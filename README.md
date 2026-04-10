# macOS System Slim

Keep your Mac's internal disk lean and your dev environment tidy. Moves Docker Desktop's data to an external volume, automates Docker lifecycle with mount/unmount events, caps resource usage (RAM, CPU), and runs weekly cleanup of caches, build artifacts, and stale downloads across Docker, Homebrew, npm, pip, Gradle, NuGet, and Chrome.

## What This Does

- Moves `Docker.raw` (~24 GB) from internal disk to an external APFS volume
- Redirects Docker Desktop to use the new location via `DataFolder` setting
- Automatically starts Docker when the external drive is plugged in
- Automatically stops Docker when the drive is ejected
- Weekly cleanup of Docker build cache, system caches, and stale downloads
- Hardens Docker Desktop settings (disables auto-update and start-at-login)

## Requirements

- macOS (tested on macOS 26.4 / Darwin 25.4.0, Apple Silicon)
- Docker Desktop 29.x+
- External APFS-formatted volume with at least 2x your Docker.raw size free
- Python 3 (pre-installed on macOS)

## Quick Start

### 1. Pre-flight

Validates the environment before touching anything:

```bash
bash .planning/phases/01-pre-flight/preflight.sh
```

Checks: Docker stopped, volume is APFS, enough free space, target directory writable, settings backed up.

### 2. Data Copy

Copies Docker.raw preserving APFS sparse structure:

```bash
bash .planning/phases/02-data-copy/copy-docker.sh 2>&1 | tee copy-results.txt
bash .planning/phases/02-data-copy/verify-copy.sh
```

Uses `cp -c` (APFS clonefile) with `ditto` fallback. Shows progress bar. Verifies both logical and on-disk sizes match.

### 3. Cutover

Redirects Docker Desktop to the new location:

```bash
bash .planning/phases/03-cutover-and-verification/cutover.sh 2>&1 | tee cutover-results.txt
bash .planning/phases/03-cutover-and-verification/verify-cutover.sh
```

Updates `DataFolder` via Python json module, starts Docker, polls `docker info` for readiness, verifies images/containers survived.

### 4. Cleanup and Hardening

Deletes the original and locks down settings:

```bash
bash .planning/phases/04-cleanup-and-hardening/cleanup.sh 2>&1 | tee cleanup-results.txt
bash .planning/phases/04-cleanup-and-hardening/harden.sh 2>&1 | tee harden-results.txt
```

Deletes original Docker.raw (only after re-verifying cutover), disables auto-update (`AutoDownloadUpdates`, `DisableUpdate`), disables start-at-login (`AutoStart`).

## Automation

### Volume-Aware Docker Lifecycle

Docker starts automatically when the external volume mounts and stops gracefully when it unmounts.

| File | Location | Purpose |
|------|----------|---------|
| `scripts/docker-after-volume.sh` | `~/bin/` | Start Docker on mount, stop on unmount |
| `launchd/com.user.docker-on-volume.plist` | `~/Library/LaunchAgents/` | Triggers: mount event + 60s poll + login |

Install:

```bash
cp scripts/docker-after-volume.sh ~/bin/
chmod +x ~/bin/docker-after-volume.sh
cp launchd/com.user.docker-on-volume.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.user.docker-on-volume.plist
```

### Weekly Maintenance

Two launchd agents run every Sunday to prevent disk bloat:

| File | Schedule | What it cleans |
|------|----------|---------------|
| `scripts/docker-weekly-prune.sh` | Sunday 3 AM | Docker: containers, images, build cache (7-day filter) |
| `scripts/weekly-disk-cleanup.sh` | Sunday 4 AM | System: npm, pip, Homebrew, Gradle, NuGet, Chrome cache, logs, stale downloads |

Install:

```bash
cp scripts/docker-weekly-prune.sh scripts/weekly-disk-cleanup.sh ~/bin/
chmod +x ~/bin/docker-weekly-prune.sh ~/bin/weekly-disk-cleanup.sh
cp launchd/com.user.docker-weekly-prune.plist launchd/com.user.weekly-disk-cleanup.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.user.docker-weekly-prune.plist
launchctl load ~/Library/LaunchAgents/com.user.weekly-disk-cleanup.plist
```

Both scripts have guards: they skip safely if the volume is unmounted or Docker isn't running.

## Docker Resource Limits

Set during migration to keep the footprint slim:

| Resource | Value |
|----------|-------|
| Memory | 3 GiB |
| CPUs | 2 |
| Auto-update | Disabled |
| Start at login | Disabled |

## Project Structure

```
scripts/                          # Automation scripts (install to ~/bin/)
  docker-after-volume.sh          # Volume mount/unmount Docker lifecycle
  docker-weekly-prune.sh          # Weekly Docker cleanup
  weekly-disk-cleanup.sh          # Weekly system cache cleanup

launchd/                          # LaunchAgent plists (install to ~/Library/LaunchAgents/)
  com.user.docker-on-volume.plist
  com.user.docker-weekly-prune.plist
  com.user.weekly-disk-cleanup.plist

.planning/phases/                 # Migration phase scripts and artifacts
  01-pre-flight/                  # Environment validation
  02-data-copy/                   # Docker.raw copy with verification
  03-cutover-and-verification/    # Settings update, Docker restart, data verification
  04-cleanup-and-hardening/       # Original deletion, settings hardening
```

## Safety Design

Every phase follows a fail-fast, verify-before-act approach:

- **Pre-deletion gate**: `verify-cutover.sh` must pass before any deletion
- **Dual-metric verification**: Both logical size (`stat -f %z`) and on-disk size (`du -sk`) compared
- **No wildcards in rm**: All deletions use explicit full paths
- **Backup retention**: `.bak` files kept for settings rollback
- **Graceful Docker stop**: `osascript quit` with 30s timeout before force kill
- **Idempotent scripts**: All verification scripts can be re-run safely

## Logs

All automation logs to `/tmp/` for easy inspection:

```bash
cat /tmp/docker-volume-watcher.log    # Mount/unmount events
cat /tmp/docker-weekly-prune.log      # Docker cleanup results
cat /tmp/weekly-disk-cleanup.log      # System cleanup results
```

## License

MIT
