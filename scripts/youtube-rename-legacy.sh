#!/usr/bin/env bash
# One-shot migration: rename Tube Archivist's legacy UC<channel-id>
# folders to human-readable channel names, and rename files inside
# from <video-id>.{mp4,nfo,jpg} to <Title> [<video-id>].<ext> — the
# same layout the new youtube-grab.sh produces.
#
# Reads channel/title from the existing per-video .nfo files (TA wrote
# <studio>Channel</studio> and <title>Title</title>). No network calls.
#
# Dry-run by default. Pass --apply to actually rename.
#
# Usage:
#   scripts/youtube-rename-legacy.sh           # dry-run
#   scripts/youtube-rename-legacy.sh --apply   # do it

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_ROOT="$(grep '^DATA_ROOT=' "$REPO_ROOT/.env" | cut -d= -f2)"
ROOT="$DATA_ROOT/media/kids/youtube"

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

if [ "$APPLY" = "0" ]; then
    echo "DRY RUN — pass --apply to actually rename. Root: $ROOT"
    echo
fi

[ -d "$ROOT" ] || { echo "no $ROOT" >&2; exit 1; }

extract_xml_field() {
    # $1 = nfo file, $2 = field name (e.g. "studio")
    python3 -c '
import sys, re
try:
    with open(sys.argv[1], encoding="utf-8") as f: doc = f.read()
except Exception:
    sys.exit(0)
m = re.search(rf"<{sys.argv[2]}>(.*?)</{sys.argv[2]}>", doc, re.S)
if m:
    import html
    print(html.unescape(m.group(1)).strip())
' "$1" "$2"
}

sanitise() {
    python3 -c '
import re, sys
t = sys.argv[1]
t = re.sub(r"[/\\<>:|?*\"\n\r\t]+", "", t).strip()
t = re.sub(r"\s+", " ", t)
print(t[:120])
' "$1"
}

# --- Phase 1: rename channel folders ---
echo "== Phase 1: rename channel folders =="
shopt -s nullglob
for dir in "$ROOT"/UC*; do
    [ -d "$dir" ] || continue
    base="$(basename "$dir")"
    first_nfo="$(find "$dir" -maxdepth 1 -name '*.nfo' | head -1)"
    if [ -z "$first_nfo" ]; then
        echo "  skip $base (no NFOs to read channel name from)"
        continue
    fi
    channel="$(extract_xml_field "$first_nfo" "studio")"
    if [ -z "$channel" ]; then
        echo "  skip $base (no <studio> in NFO)"
        continue
    fi
    safe="$(sanitise "$channel")"
    new="$ROOT/$safe"
    if [ "$dir" = "$new" ]; then
        echo "  $base → already named $safe"
        continue
    fi
    if [ -e "$new" ]; then
        echo "  COLLISION $base → $safe (target exists, leaving $base alone)"
        continue
    fi
    if [ "$APPLY" = "1" ]; then
        mv "$dir" "$new"
        echo "  $base → $safe"
    else
        echo "  $base → $safe"
    fi
done

# --- Phase 2: rename files inside each channel folder ---
echo
echo "== Phase 2: rename files inside each channel folder =="
for dir in "$ROOT"/*/; do
    [ -d "$dir" ] || continue
    for nfo in "$dir"*.nfo; do
        [ -e "$nfo" ] || continue
        stem="$(basename "$nfo" .nfo)"
        # Skip files already in the new "<Title> [<id>]" format
        case "$stem" in *\ \[*\]) continue ;; esac
        title="$(extract_xml_field "$nfo" "title")"
        if [ -z "$title" ]; then
            echo "  skip $stem (no <title>)"
            continue
        fi
        safe_title="$(sanitise "$title")"
        new_stem="$safe_title [$stem]"
        if [ "$APPLY" = "1" ]; then
            for ext in mp4 nfo jpg info.json webp; do
                src="$dir$stem.$ext"
                dst="$dir$new_stem.$ext"
                [ -e "$src" ] && mv "$src" "$dst"
            done
            echo "  $(basename "$dir")/$stem.* → $new_stem.*"
        else
            echo "  $(basename "$dir")/$stem.* → $new_stem.*"
        fi
    done
done

echo
[ "$APPLY" = "1" ] && echo "Done." || echo "Dry run complete. Re-run with --apply."
