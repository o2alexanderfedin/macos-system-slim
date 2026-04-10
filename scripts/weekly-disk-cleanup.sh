#!/bin/bash
# Weekly disk cleanup — caches, incomplete downloads, logs
# Safe operations only. Never touches toolchains, SDKs, tools, or Claude data.
# Scheduled via launchd (weekly interval).

LOG="/tmp/weekly-disk-cleanup.log"

echo "$(date): Disk cleanup triggered" >> "$LOG"

# Capture before state
BEFORE=$(df -h / | tail -1 | awk '{print $4}')
echo "$(date): Disk available before: ${BEFORE}" >> "$LOG"

# 1. Incomplete Chrome downloads (dead .crdownload files)
echo "$(date): Step 1 — removing incomplete Chrome downloads" >> "$LOG"
find ~/Downloads -name "*.crdownload" -type f -mtime +1 -print -delete >> "$LOG" 2>&1

# 2. npm cache
echo "$(date): Step 2 — clearing npm cache" >> "$LOG"
npm cache clean --force >> "$LOG" 2>&1

# 3. Homebrew cache
echo "$(date): Step 3 — cleaning Homebrew cache" >> "$LOG"
brew cleanup --prune=7 >> "$LOG" 2>&1

# 4. Gradle caches older than 30 days
echo "$(date): Step 4 — pruning old Gradle caches" >> "$LOG"
find ~/.gradle/caches -type f -atime +30 -delete 2>/dev/null
find ~/.gradle/caches -type d -empty -delete 2>/dev/null
echo "  Gradle caches pruned (files unused for 30+ days)" >> "$LOG"

# 5. General cache (~/.cache) — files older than 30 days
echo "$(date): Step 5 — pruning ~/.cache (30+ days)" >> "$LOG"
find ~/.cache -type f -atime +30 -delete 2>/dev/null
find ~/.cache -type d -empty -delete 2>/dev/null
echo "  ~/.cache pruned" >> "$LOG"

# 6. NuGet cache — packages older than 30 days
echo "$(date): Step 6 — pruning NuGet cache (30+ days)" >> "$LOG"
find ~/.nuget/packages -type d -maxdepth 2 -atime +30 -exec rm -rf {} + 2>/dev/null
echo "  NuGet cache pruned" >> "$LOG"

# 7. System logs older than 7 days
echo "$(date): Step 7 — removing old logs" >> "$LOG"
find ~/Library/Logs -type f -mtime +7 -delete 2>/dev/null
find ~/Library/Logs -type d -empty -delete 2>/dev/null
echo "  ~/Library/Logs pruned (7+ days)" >> "$LOG"

# 8. System caches — old entries only (30+ days, safe subset)
echo "$(date): Step 8 — pruning ~/Library/Caches (30+ days)" >> "$LOG"
find ~/Library/Caches -type f -atime +30 -not -path "*/com.apple.*" -delete 2>/dev/null
find ~/Library/Caches -type d -empty -delete 2>/dev/null
echo "  ~/Library/Caches pruned (skipping Apple system caches)" >> "$LOG"

# 9. Chrome browser cache (all profiles — auto-rebuilds on next visit)
echo "$(date): Step 9 — clearing Chrome cache" >> "$LOG"
find ~/Library/Caches/Google/Chrome -type d \( -name "Cache" -o -name "Code Cache" -o -name "GPUCache" -o -name "GrShaderCache" \) -exec rm -rf {} + 2>/dev/null
echo "  Chrome cache cleared" >> "$LOG"

# 10. pip cache
echo "$(date): Step 10 — clearing pip cache" >> "$LOG"
python3 -m pip cache purge >> "$LOG" 2>&1

# 11. Cargo registry cache (downloaded sources — re-downloaded on build)
echo "$(date): Step 11 — pruning Cargo registry cache" >> "$LOG"
rm -rf ~/.cargo/registry/cache ~/.cargo/registry/src 2>/dev/null
echo "  Cargo registry cache cleared" >> "$LOG"

# 12. NuGet http-cache and local share cache
echo "$(date): Step 12 — clearing NuGet caches" >> "$LOG"
rm -rf ~/.local/share/NuGet/http-cache 2>/dev/null
find ~/.nuget/packages -type d -maxdepth 2 -atime +30 -exec rm -rf {} + 2>/dev/null
echo "  NuGet caches cleared" >> "$LOG"

# 13. Old DMG/PKG installers in Downloads (older than 7 days)
echo "$(date): Step 13 — removing old installers from Downloads" >> "$LOG"
find ~/Downloads -type f \( -name "*.dmg" -o -name "*.pkg" \) -mtime +7 -print -delete >> "$LOG" 2>&1

# Capture after state
AFTER=$(df -h / | tail -1 | awk '{print $4}')
echo "$(date): Disk available after: ${AFTER}" >> "$LOG"
echo "$(date): Cleanup complete (${BEFORE} -> ${AFTER})" >> "$LOG"
