## Project

**macOS System Slim**

Scripts and launchd automation to keep a Mac's internal disk lean and dev tools tidy. Docker Desktop data lives on an external APFS volume with automatic start/stop on mount/unmount. Weekly launchd agents clean caches across Docker, Homebrew, npm, pip, Gradle, NuGet, and Chrome. Docker resource usage is capped (RAM, CPU, auto-update, start-at-login).

**Core Value:** Minimize disk and RAM footprint on the internal drive while keeping the dev environment fully functional.

### Constraints

- Docker must be stopped before modifying settings or copying data
- External volume `/Volumes/Unitek-B/` must be mounted before Docker can start
- Settings updates use Python json module (never sed/jq on JSON files)
- All deletions use explicit full paths (no `rm -rf`, no wildcards)
- Fail-fast on any error: `set -euo pipefail` in all scripts

## Git Commits

Always use this co-author line in all git commits:
```
Co-Authored-By: AI Hive(R) <sales@hupyy.com>
```

## Conventions

### Shell Scripts
- Shebang: `#!/bin/bash`
- Error handling: `set -euo pipefail`
- Output format: `[ PASS ]` / `[ FAIL ]` / `[ INFO ]` for status lines
- Constants: UPPER_SNAKE_CASE (`SOURCE`, `DEST`, `PASS`, `FAIL`)
- File names: kebab-case (`copy-docker.sh`, `verify-copy.sh`)
- Indentation: 2 spaces
- Scripts in `.planning/phases/{phase}/` for migration, `scripts/` for automation
- LaunchAgent plists in `launchd/`

### Safety Patterns
- Re-verify before destructive actions (run verification script as pre-deletion gate)
- Dual-metric verification: logical size (`stat -f %z`) + on-disk size (`du -sk`)
- Settings updates: Python json module with readback verification
- Docker lifecycle: `osascript quit` with timeout, then force kill as last resort
- Guards in automation scripts: check volume mounted + Docker running before acting
