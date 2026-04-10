#!/bin/bash
# Weekly Docker housekeeping — prune, build cache cleanup, stale image removal
# Only runs if Unitek-B is mounted and Docker is running.
# Scheduled via launchd (weekly interval).

VOLUME="/Volumes/Unitek-B"
LOG="/tmp/docker-weekly-prune.log"

echo "$(date): Housekeeping triggered" >> "$LOG"

# Guard: volume must be mounted
if [ ! -d "$VOLUME" ]; then
    echo "$(date): Unitek-B not mounted, skipping" >> "$LOG"
    exit 0
fi

# Guard: Docker must be running
if ! docker info >/dev/null 2>&1; then
    echo "$(date): Docker not running, skipping" >> "$LOG"
    exit 0
fi

# Capture before state
BEFORE=$(docker system df 2>/dev/null)
echo "$(date): Before cleanup:" >> "$LOG"
echo "$BEFORE" >> "$LOG"

# 1. Prune stopped containers, dangling images, unused networks
#    --filter "until=168h" keeps items used in the last 7 days
echo "$(date): Step 1 — system prune" >> "$LOG"
docker system prune -f --filter "until=168h" >> "$LOG" 2>&1

# 2. Prune build cache older than 7 days
echo "$(date): Step 2 — build cache prune" >> "$LOG"
docker builder prune -f --filter "until=168h" >> "$LOG" 2>&1

# 3. Remove dangling images (untagged, no container references)
echo "$(date): Step 3 — dangling image removal" >> "$LOG"
docker image prune -f >> "$LOG" 2>&1

# Capture after state
AFTER=$(docker system df 2>/dev/null)
echo "$(date): After cleanup:" >> "$LOG"
echo "$AFTER" >> "$LOG"
echo "$(date): Housekeeping complete" >> "$LOG"
