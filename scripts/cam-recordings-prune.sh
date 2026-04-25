#!/bin/bash
# Daily cron: delete cam recording clips older than 3 days.
# Recordings are written by HA's record_front_door / record_deck
# shell_commands on motion alerts; this script keeps the rolling
# 3-day window so the storage doesn't grow unbounded.
#
# Add to crontab:
#   30 5 * * * /path/to/homelab-cluster/scripts/cam-recordings-prune.sh

set -euo pipefail

DIR=/mnt/disk2/cam-recordings
LOGDIR=/home/rob/homelab-cluster/movie-bot-data/sweep-logs
mkdir -p "$LOGDIR"

ts=$(date -u +%Y%m%dT%H%M%SZ)
LOG="$LOGDIR/cam-prune-${ts}.log"

{
  echo "=== $ts cam-recordings-prune ==="
  before=$(find "$DIR" -type f -name '*.mp4' 2>/dev/null | wc -l)
  before_size=$(du -sh "$DIR" 2>/dev/null | cut -f1)
  echo "before: $before files, $before_size"
  find "$DIR" -type f -name '*.mp4' -mtime +3 -print -delete 2>/dev/null | wc -l | xargs -I {} echo "deleted: {} files (>3 days old)"
  # Strip empty directories that aren't the per-cam roots.
  find "$DIR" -mindepth 2 -type d -empty -delete 2>/dev/null
  after=$(find "$DIR" -type f -name '*.mp4' 2>/dev/null | wc -l)
  after_size=$(du -sh "$DIR" 2>/dev/null | cut -f1)
  echo "after: $after files, $after_size"
} > "$LOG" 2>&1

ls -1t "$LOGDIR"/cam-prune-*.log 2>/dev/null | tail -n +15 | xargs -r rm -f
