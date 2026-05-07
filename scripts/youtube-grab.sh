#!/usr/bin/env bash
# Download a YouTube video and place it in the kids' YouTube folder
# with a Jellyfin-compatible <movie> NFO sidecar. Triggers a Jellyfin
# library refresh on success.
#
# Layout: <OUT_DIR>/<Channel>/<Title> [<id>].mp4
#         + <Title> [<id>].nfo + <Title> [<id>].jpg
# One level of nesting (channel folder), then videos flat inside it.
# No Show/Season hierarchy — NFO uses <movie> schema so each video
# surfaces as a top-level item in the Jellyfin library, just organised
# on disk by channel.
#
# Usage:
#   youtube-grab.sh <youtube-url> [--job-id <id>]
#
# Environment (with sensible fallbacks for host CLI use):
#   OUT_DIR             output root. Default: $DATA_ROOT/media/kids/youtube,
#                       reading DATA_ROOT from <repo>/.env when present.
#   JELLYFIN_URL        e.g. http://jellyfin:8096 (post-grab refresh; optional)
#   JELLYFIN_API_KEY    Jellyfin API key (optional; refresh skipped if absent)
#   JOB_STATUS_DIR      if set, write a JSON status record here at exit
#                       under <id>.json (paired with --job-id)
#
# Stdout: a JSON line summarising the result. Stderr: yt-dlp progress.

set -euo pipefail

URL=""
JOB_ID=""
while [ $# -gt 0 ]; do
    case "$1" in
        --job-id) JOB_ID="${2:-}"; shift 2 ;;
        --) shift; URL="${1:-}"; break ;;
        -*) echo "unknown flag: $1" >&2; exit 2 ;;
        *) URL="$1"; shift ;;
    esac
done

if [ -z "$URL" ]; then
    echo '{"ok":false,"error":"usage: youtube-grab.sh <url> [--job-id <id>]"}' >&2
    exit 2
fi

# --- Resolve OUT_DIR + Jellyfin creds. Env vars win; otherwise look for
# the repo's .env / .api_keys when running on the host.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || true)"
if [ -z "${OUT_DIR:-}" ] && [ -f "$REPO_ROOT/.env" ]; then
    DATA_ROOT="$(grep '^DATA_ROOT=' "$REPO_ROOT/.env" | cut -d= -f2 || true)"
    [ -n "$DATA_ROOT" ] && OUT_DIR="$DATA_ROOT/media/kids/youtube"
fi
if [ -z "${JELLYFIN_URL:-}" ] || [ -z "${JELLYFIN_API_KEY:-}" ]; then
    [ -f "$REPO_ROOT/.api_keys" ] && source "$REPO_ROOT/.api_keys" || true
fi
: "${OUT_DIR:?OUT_DIR not set and could not be inferred}"
mkdir -p "$OUT_DIR"

# yt-dlp needs a JS runtime to solve YouTube's challenges. It ships
# bundled support for deno; for bun/node we fetch the EJS solver
# components from github on first run (cached locally afterward).
# Auto-detect what's installed, prefer deno (no remote-components fetch).
YTDL_JS_FLAGS=()
if command -v deno >/dev/null 2>&1; then
    : # deno is yt-dlp's default — nothing to add
elif command -v bun >/dev/null 2>&1; then
    YTDL_JS_FLAGS=(--js-runtimes "bun:$(command -v bun)" --remote-components ejs:github)
elif command -v node >/dev/null 2>&1; then
    YTDL_JS_FLAGS=(--js-runtimes "node:$(command -v node)" --remote-components ejs:github)
fi

emit_result() {
    local payload="$1"
    echo "$payload"
    if [ -n "$JOB_ID" ] && [ -n "${JOB_STATUS_DIR:-}" ]; then
        mkdir -p "$JOB_STATUS_DIR"
        printf '%s' "$payload" > "$JOB_STATUS_DIR/$JOB_ID.json"
    fi
}

emit_error() {
    emit_result "$(python3 -c '
import json, sys, time
print(json.dumps({"ok": False, "error": sys.argv[1], "url": sys.argv[2], "completed_at": int(time.time())}))
' "$1" "$URL")"
    exit 1
}

# --- 1) Probe metadata
META_JSON="$(yt-dlp "${YTDL_JS_FLAGS[@]}" --no-playlist --dump-single-json "$URL" 2>/dev/null || true)"
if [ -z "$META_JSON" ]; then
    emit_error "yt-dlp could not resolve URL"
fi

VIDEO_ID="$(echo "$META_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')"
TITLE="$(echo "$META_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("title",""))')"
CHANNEL="$(echo "$META_JSON" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("channel") or d.get("uploader") or d.get("channel_id") or "Unknown")')"

sanitise() {
    python3 -c '
import re, sys
t = sys.argv[1]
t = re.sub(r"[/\\<>:|?*\"\n\r\t]+", "", t).strip()
t = re.sub(r"\s+", " ", t)
print(t[:120])
' "$1"
}
SAFE_TITLE="$(sanitise "$TITLE")"
SAFE_CHANNEL="$(sanitise "$CHANNEL")"

CHANNEL_DIR="$OUT_DIR/$SAFE_CHANNEL"
mkdir -p "$CHANNEL_DIR"

BASE="${SAFE_TITLE} [${VIDEO_ID}]"
VIDEO_PATH="$CHANNEL_DIR/${BASE}.mp4"
INFO_PATH="$CHANNEL_DIR/${BASE}.info.json"
NFO_PATH="$CHANNEL_DIR/${BASE}.nfo"
THUMB_PATH="$CHANNEL_DIR/${BASE}.jpg"

if [ -f "$VIDEO_PATH" ]; then
    emit_result "$(python3 -c '
import json, sys, time, os
print(json.dumps({
  "ok": True, "already_present": True,
  "title": sys.argv[1], "channel": sys.argv[2], "video": sys.argv[3],
  "size": os.path.getsize(sys.argv[3]) if os.path.exists(sys.argv[3]) else 0,
  "url": sys.argv[4], "completed_at": int(time.time())
}))
' "$TITLE" "$CHANNEL" "$VIDEO_PATH" "$URL")"
    exit 0
fi

# --- 2) Download (capped at 1080p — kids content)
yt-dlp "${YTDL_JS_FLAGS[@]}" \
    --no-playlist \
    -f "bestvideo[height<=1080]+bestaudio/best[height<=1080]/best" \
    --merge-output-format mp4 \
    --write-info-json \
    --write-thumbnail \
    --convert-thumbnails jpg \
    -o "$CHANNEL_DIR/${BASE}.%(ext)s" \
    "$URL" >&2 || emit_error "yt-dlp download failed"

if [ ! -f "$VIDEO_PATH" ]; then
    emit_error "expected $VIDEO_PATH after download but file missing"
fi

# --- 3) Convert info.json → Jellyfin <movie> NFO
if [ -f "$INFO_PATH" ]; then
    python3 - "$INFO_PATH" "$NFO_PATH" "$THUMB_PATH" <<'PYEOF'
import json, sys, html, datetime, os
info_path, nfo_path, thumb_path = sys.argv[1], sys.argv[2], sys.argv[3]
m = json.load(open(info_path))

def x(s):
    return html.escape("" if s is None else str(s), quote=False)

upload = m.get("upload_date") or ""
aired = f"{upload[:4]}-{upload[4:6]}-{upload[6:8]}" if len(upload) == 8 else ""
runtime_m = int((m.get("duration") or 0) // 60)

lines = [
    '<?xml version="1.0" encoding="utf-8" standalone="yes"?>',
    "<movie>",
    f"  <title>{x(m.get('title'))}</title>",
    f"  <plot>{x(m.get('description'))}</plot>",
]
if upload[:4]:
    lines.append(f"  <year>{x(upload[:4])}</year>")
if aired:
    lines.append(f"  <premiered>{x(aired)}</premiered>")
    lines.append(f"  <releasedate>{x(aired)}</releasedate>")
if runtime_m:
    lines.append(f"  <runtime>{runtime_m}</runtime>")
lines.append(f"  <studio>{x(m.get('uploader') or m.get('channel'))}</studio>")
lines.append(f"  <dateadded>{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</dateadded>")
lines.append(f'  <uniqueid type="youtube" default="true">{x(m.get("id"))}</uniqueid>')
if os.path.exists(thumb_path):
    lines.append(f"  <thumb aspect=\"poster\">{os.path.basename(thumb_path)}</thumb>")
for tag in (m.get("tags") or [])[:30]:
    lines.append(f"  <tag>{x(tag)}</tag>")
lines.append("</movie>")
open(nfo_path, "w").write("\n".join(lines) + "\n")
PYEOF
fi

# --- 4) Trigger Jellyfin library refresh (best-effort; non-fatal)
if [ -n "${JELLYFIN_API_KEY:-}" ] && [ -n "${JELLYFIN_URL:-}" ]; then
    curl -s -X POST -H "X-MediaBrowser-Token: $JELLYFIN_API_KEY" \
        "$JELLYFIN_URL/Library/Refresh" >/dev/null || true
fi

emit_result "$(python3 -c '
import json, sys, os, time
print(json.dumps({
  "ok": True,
  "title": sys.argv[1],
  "channel": sys.argv[2],
  "video": sys.argv[3],
  "nfo": sys.argv[4],
  "size": os.path.getsize(sys.argv[3]) if os.path.exists(sys.argv[3]) else 0,
  "url": sys.argv[5],
  "completed_at": int(time.time())
}))
' "$TITLE" "$CHANNEL" "$VIDEO_PATH" "$NFO_PATH" "$URL")"
