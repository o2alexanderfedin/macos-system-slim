# Architecture Patterns

**Domain:** Docker Desktop data migration on macOS
**Researched:** 2026-04-09
**Confidence:** HIGH (directly inspected live system)

## Recommended Architecture

The migration is a two-phase operation: copy data to the target location, then redirect Docker Desktop to the new location. The split matters because these two acts have different risks and reversibility.

```
┌─────────────────────────────────────────────────────────────────┐
│  Docker Desktop Process (stopped during migration)              │
└─────────────────────────────────────────────────────────────────┘
         │ reads
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  settings.json                                                  │
│  ~/Library/Group Containers/group.com.docker/settings.json      │
│                                                                 │
│  "dataFolder": "/path/to/vms/0/data"   ◄── migration target    │
│  "diskSizeMiB": 61035                                           │
└─────────────────────────────────────────────────────────────────┘
         │ points to
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  VM Data Directory (dataFolder value)                           │
│  ~/Library/Containers/com.docker.docker/Data/vms/0/data/        │
│                                                                 │
│  Docker.raw   (32 GB logical / 24 GB on-disk, APFS sparse)     │
│    └── Linux ext4 partition inside                              │
│         ├── /var/lib/docker/overlay2/  (layer storage)         │
│         ├── /var/lib/docker/volumes/   (named volumes)          │
│         ├── /var/lib/docker/containers/ (container metadata)   │
│         └── /var/lib/docker/buildkit/  (build cache)           │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  VM Identity Directory (NOT controlled by dataFolder)           │
│  ~/Library/Containers/com.docker.docker/Data/vms/0/             │
│                                                                 │
│  macaddr-0, macaddr-1   (VM MAC addresses — stay put)           │
│  console.sock           (runtime socket — ephemeral)            │
│  00000002.000007cf      (virtio socket — ephemeral)             │
│  log/                   (VM log files — ephemeral)              │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Client Configuration (not migrated, not relevant)              │
│  ~/.docker/                                                     │
│                                                                 │
│  config.json    (auth, context, plugin settings)                │
│  daemon.json    (buildkit GC config)                            │
│  contexts/      (desktop-linux context socket path)             │
│  buildx/        (builder instances, refs, activity)             │
└─────────────────────────────────────────────────────────────────┘
```

## Component Boundaries

| Component | Location | Size | Role | Move? |
|-----------|----------|------|------|-------|
| Docker.raw VM disk | `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` | 32 GB logical / 24 GB on-disk | All container images, named volumes, build cache — everything inside the Linux VM | YES — this is the migration target |
| settings.json | `~/Library/Group Containers/group.com.docker/settings.json` | <1 MB | Docker Desktop configuration; `dataFolder` key tells Docker Desktop where to find the VM disk | UPDATE `dataFolder` key only |
| VM identity files | `~/Library/Containers/com.docker.docker/Data/vms/0/macaddr-{0,1}` | bytes | VM MAC addresses; persist across restarts | NO — stay in place |
| Runtime sockets | `~/Library/Containers/com.docker.docker/Data/*.sock` | 0 bytes | IPC between Docker Desktop processes | NO — ephemeral, recreated on start |
| Client config | `~/.docker/config.json`, `daemon.json`, `contexts/`, `buildx/` | <50 MB | Docker CLI auth, contexts, builder config | NO — already on internal disk; small and unrelated |
| Group container support files | `~/Library/Group Containers/group.com.docker/` (excl. settings.json) | <1 MB | Analytics, CNI config, DHCP leases, feature flags | NO — operational metadata, not user data |

## What dataFolder Controls

`dataFolder` in `settings.json` is the exact path Docker Desktop expects to contain `Docker.raw`. The relationship is:

```
dataFolder = /some/path/data
Docker.raw  = /some/path/data/Docker.raw
```

When Docker Desktop starts, it reads `settings.json`, finds `dataFolder`, and mounts the `Docker.raw` found inside that directory as the Linux VM disk. There is no other discovery mechanism — if `Docker.raw` is not at `<dataFolder>/Docker.raw`, the VM fails to boot.

## Data Flow: How Docker Desktop Finds and Uses Data

```
1. Docker Desktop.app launches
       │
       ▼
2. Reads ~/Library/Group Containers/group.com.docker/settings.json
   └── Extracts: dataFolder, diskSizeMiB, memoryMiB, cpus, ...
       │
       ▼
3. Starts VM (using Apple Virtualization Framework)
   └── Mounts <dataFolder>/Docker.raw as the Linux VM's root disk
       │
       ▼
4. Linux VM boots inside the VM
   └── dockerd starts inside the VM
   └── /var/lib/docker/ is the overlay storage inside Docker.raw
       │
       ▼
5. Docker daemon exposes socket at:
   ~/.docker/run/docker.sock  (desktop-linux context)
   /var/run/docker.sock       (default context, symlinked)
       │
       ▼
6. Docker CLI on macOS connects via socket
   └── All image/container/volume operations hit dockerd inside VM
   └── All data persists inside Docker.raw
```

## Migration Architecture

The correct migration is a manual two-step: copy then redirect. The GUI's built-in "move" fails on cross-device operations because it uses `rename()` which cannot span filesystems.

```
Step 1: Copy Docker.raw to target (Docker must be stopped)
  source: ~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw
  target: /Volumes/Unitek-B/Docker/Docker.raw

Step 2: Update settings.json
  "dataFolder": "/Volumes/Unitek-B/Docker"
  (not /Volumes/Unitek-B/Docker/Docker.raw — the directory, not the file)

Step 3: Start Docker Desktop
  Docker reads new dataFolder, mounts Docker.raw from external volume
  Verify: docker info, docker images, docker ps -a

Step 4: Reclaim internal disk space (only after verification)
  Remove original: ~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw
```

## Dependency: APFS on Target Volume

Both source (internal SSD) and target (`/Volumes/Unitek-B/`) are APFS volumes. This is significant:

- Docker.raw is an APFS sparse file: 32 GB logical, 24 GB actual on-disk blocks
- `cp` on macOS preserves APFS sparse files (copies only allocated blocks — fast)
- `rsync` does NOT preserve sparse files by default — it would expand to the full 32 GB logical size
- Correct copy command: `cp` (uses APFS clonefile semantics) or `rsync --sparse`

The target volume (`/Volumes/Unitek-B/`) is confirmed APFS, so sparse file support is available.

## Suggested Migration Order

Dependencies flow strictly top-to-bottom:

```
1. Verify prerequisites
   - Docker Desktop stopped (required — cannot copy open raw disk safely)
   - /Volumes/Unitek-B/ mounted and has >32 GB free
   - Target directory /Volumes/Unitek-B/Docker/ exists and is empty

2. Copy Docker.raw to target
   - Duration: proportional to 24 GB on-disk data
   - Risk: interruption leaves partial file (safe to retry from scratch)
   - No changes to settings yet — fully reversible at this point

3. Verify copy integrity
   - File size matches source
   - (Optional) shasum check for confidence

4. Update settings.json
   - Change dataFolder value only
   - Keep all other settings unchanged
   - Risk: if Docker fails to start, revert this line and restart

5. Start Docker Desktop and verify
   - docker info confirms storage is working
   - docker images shows expected images
   - docker ps -a shows expected containers

6. Remove original Docker.raw from internal disk
   - Only after successful verification
   - Point of no return: frees internal disk space
```

## Risks by Component

| Component | Risk | Mitigation |
|-----------|------|------------|
| Docker.raw copy | Partial copy if interrupted | Verify size before proceeding; delete partial and retry |
| settings.json edit | Typo in path leaves Docker unbootable | Keep original value in a comment or backup file before editing |
| External volume unmounted | Docker fails to start, cannot pull images | This is a permanent operational dependency; document it |
| Sparse file copy with rsync | Expands 32 GB logical → 32 GB actual, filling volume unexpectedly | Use `cp` or `rsync --sparse` explicitly |
| macaddr files | Changing these breaks VM identity | Do not touch — they stay in vms/0/, not in dataFolder |

## Anti-Patterns to Avoid

### Anti-Pattern 1: Using the Docker Desktop GUI to relocate to external volume
**What goes wrong:** Docker Desktop uses `rename()` syscall internally, which fails with "cross-device link" error when source and target are on different filesystems. The GUI then reverts the setting.
**Instead:** Stop Docker, copy Docker.raw manually, edit settings.json directly.

### Anti-Pattern 2: Moving the entire vms/0/ directory
**What goes wrong:** This moves the macaddr files and log directories unnecessarily, and moves runtime sockets that Docker doesn't expect to be absent during startup.
**Instead:** Move only the `data/` subdirectory (i.e., the dataFolder contents), which is just Docker.raw.

### Anti-Pattern 3: Using rsync without --sparse
**What goes wrong:** rsync reads the full 32 GB logical extent of Docker.raw and writes it all, even though only 24 GB is actually used. This takes longer and uses 8 GB more space than necessary.
**Instead:** Use `cp` (which uses APFS clonefile) or `rsync --sparse`.

### Anti-Pattern 4: Deleting original before verifying new location works
**What goes wrong:** If Docker Desktop fails to start from the new location, you have no fallback.
**Instead:** Verify Docker fully operational from new location before removing original.

### Anti-Pattern 5: Symlinking instead of updating settings.json
**What goes wrong:** Symlinks into external volumes create fragile dependency chains; Docker may follow symlinks differently in some contexts; VS Code Docker extension and other tools may not traverse symlinks correctly.
**Instead:** Update `dataFolder` in settings.json — this is the documented, intended mechanism.

## Scalability Considerations

This is a one-time migration, not an ongoing scaling concern. However:

| Concern | Now | If Docker.raw grows to max (61 GB) |
|---------|-----|-------------------------------------|
| Copy time | ~10-20 min for 24 GB at USB speeds | ~25-50 min |
| External volume dependency | Always required | Always required |
| Docker startup time | Minimal impact | Minimal impact |

## Sources

- Live system inspection: `~/Library/Containers/com.docker.docker/Data/`, `~/Library/Group Containers/group.com.docker/settings.json`, `/Volumes/Unitek-B/` — HIGH confidence
- Docker Desktop FAQ (official): https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/ — MEDIUM confidence (does not cover migration detail)
- Docker Desktop Settings docs: https://docs.docker.com/desktop/settings-and-maintenance/settings/ — MEDIUM confidence (covers disk image location UI)
- GitHub issue docker/for-mac#7310 (cross-device link error): https://github.com/docker/for-mac/issues/7310 — HIGH confidence for understanding why GUI fails
- GitHub issue docker/for-mac#6803 (external volume hang): https://github.com/docker/for-mac/issues/6803 — HIGH confidence for understanding GUI limitations
- Docker community forum (manual settings.json edit confirmed working): https://forums.docker.com/t/unable-to-move-the-disk-image-location/140531 — MEDIUM confidence
