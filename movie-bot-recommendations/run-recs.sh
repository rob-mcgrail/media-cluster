#!/bin/bash
# Cron job: weekly film recommendations based on the user's thoughts + prior rec feedback.
# Add to crontab: 0 6 * * 0 /path/to/homelab-cluster/movie-bot-recommendations/run-recs.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$REPO_ROOT/movie-bot-data"
PROMPT="$SCRIPT_DIR/recs-prompt.txt"
LOGDIR="$DATA_DIR/completed-recs-runs"
LOCKFILE="$DATA_DIR/.recs.lock"

if [ -f "$LOCKFILE" ] && kill -0 "$(cat "$LOCKFILE")" 2>/dev/null; then
    exit 0
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

CLAUDE="$(command -v claude 2>/dev/null || echo "$HOME/.local/bin/claude")"
mkdir -p "$LOGDIR"

ts=$(date -u +%Y%m%dT%H%M%SZ)
cd "$REPO_ROOT" && "$CLAUDE" --dangerously-skip-permissions -p "$(cat "$PROMPT")" \
    > "$LOGDIR/${ts}.md" 2>&1

# Retain last 20 runs, prune older
ls -1t "$LOGDIR"/*.md 2>/dev/null | tail -n +21 | xargs -r rm -f
