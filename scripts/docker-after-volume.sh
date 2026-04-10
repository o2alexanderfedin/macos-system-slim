#!/bin/bash
# Docker Desktop volume watcher — start on mount, stop on unmount
# Triggered by launchd on any volume mount/unmount event or periodic interval.
# - Launches Docker if Unitek-B is present and Docker is not running
# - Gracefully stops Docker if Unitek-B disappears and Docker is running

VOLUME="/Volumes/Unitek-B"
DOCKER_RAW="$VOLUME/Docker/Docker.raw"
LOG="/tmp/docker-volume-watcher.log"

echo "$(date): Triggered (mount/unmount event or interval)" >> "$LOG"

# Wait for Thunderbolt/APFS mount to finalize (or unmount to complete)
sleep 3

if [ -d "$VOLUME" ] && [ -f "$DOCKER_RAW" ]; then
    # Volume present — start Docker if not running
    if ! pgrep -qx "Docker Desktop"; then
        echo "$(date): Unitek-B present, launching Docker Desktop" >> "$LOG"
        open -g -b com.docker.docker
    else
        echo "$(date): Docker already running, skipping" >> "$LOG"
    fi
else
    # Volume absent — stop Docker if running
    if pgrep -qx "Docker Desktop"; then
        echo "$(date): Unitek-B gone, stopping Docker Desktop gracefully" >> "$LOG"
        osascript -e 'quit app "Docker Desktop"' 2>/dev/null
        # Wait up to 30 seconds for graceful shutdown
        for i in $(seq 1 30); do
            if ! pgrep -qx "Docker Desktop"; then
                echo "$(date): Docker stopped after ${i}s" >> "$LOG"
                break
            fi
            sleep 1
        done
        # Force kill if still running after 30 seconds
        if pgrep -qx "Docker Desktop"; then
            echo "$(date): Docker did not stop gracefully, force killing" >> "$LOG"
            killall "Docker Desktop" 2>/dev/null
            killall com.docker.backend 2>/dev/null
            killall com.docker.virtualization 2>/dev/null
            killall com.docker.helper 2>/dev/null
            killall com.docker.build 2>/dev/null
        fi
    else
        echo "$(date): Unitek-B not mounted, Docker not running, nothing to do" >> "$LOG"
    fi
fi
