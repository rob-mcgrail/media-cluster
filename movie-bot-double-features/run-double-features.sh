#!/bin/bash
# Cron job: nightly double-feature suggestions from the Jellyfin Films library.
# Safe to run daily — the bot no-ops when >=6 active (non-dismissed) suggestions
# are already in movie-bot-data/double-features/.
# Add to crontab: 0 3 * * * /path/to/homelab-cluster/movie-bot-double-features/run-double-features.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$REPO_ROOT/movie-bot-data"
PROMPT="$SCRIPT_DIR/double-features-prompt.txt"
LOGDIR="$DATA_DIR/completed-double-feature-runs"
LOCKFILE="$DATA_DIR/.double-features.lock"

if [ -f "$LOCKFILE" ] && kill -0 "$(cat "$LOCKFILE")" 2>/dev/null; then
    exit 0
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

CLAUDE="$(command -v claude 2>/dev/null || echo "$HOME/.local/bin/claude")"
mkdir -p "$LOGDIR" "$DATA_DIR/double-features" "$DATA_DIR/dismissed-double-features"

ts=$(date -u +%Y%m%dT%H%M%SZ)
cd "$REPO_ROOT" && "$CLAUDE" --dangerously-skip-permissions -p "$(cat "$PROMPT")" \
    > "$LOGDIR/${ts}.md" 2>&1

# Retain last 20 run reports
ls -1t "$LOGDIR"/*.md 2>/dev/null | tail -n +21 | xargs -r rm -f
