#!/usr/bin/env python3
"""tracker-watch — alert on private-tracker signup opportunities.

Two complementary signals:
  1. /r/OpenSignups posts (Reddit JSON, no auth) — community-curated, fast
  2. Direct GETs of each tracker's homepage — content-hash diff, belt-and-
     suspenders for cases the subreddit misses

Alerts via the dashboard's /api/event push endpoint (mobile push notifications).
State is persisted to /state/seen.json so post-IDs and content hashes
survive container restarts.
"""

import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

UA = "homelab-tracker-watch/1.0 (cron poller; +mailto:rob@hauntdigital.co.nz)"

STATE_PATH = Path("/state/seen.json")
DASHBOARD_URL = os.environ.get("DASHBOARD_URL", "http://dashboard:8000")
PUSH_TOKEN = os.environ.get("PUSH_EVENT_TOKEN", "")
INTERVAL_MIN = int(os.environ.get("WATCH_INTERVAL_MIN", "15"))

# Reddit watchlist. Match regex is applied (case-insensitive) to title +
# selftext. Full names only — abbreviations (kg, ptp, mtv, cg) are too
# short and trigger on unrelated posts.
WATCHLIST = [
    {"name": "Cinemageddon",     "match": re.compile(r"cinemageddon", re.I)},
    {"name": "Karagarga",        "match": re.compile(r"karagarga", re.I)},
    {"name": "MoreThanTV",       "match": re.compile(r"morethantv|more\s*than\s*tv", re.I)},
    {"name": "PassThePopcorn",   "match": re.compile(r"passthepopcorn|pass\s*the\s*popcorn", re.I)},
]

# Direct polls. Homepage rather than /signup.php — the closed-message
# usually lives on the index, and the signup endpoint often 302s or 403s
# when closed (which would just produce noise).
DIRECT_POLLS = [
    {"name": "Cinemageddon", "url": "https://cinemageddon.net/",  "key": "cg_hash"},
    {"name": "Karagarga",    "url": "https://karagarga.in/",      "key": "kg_hash"},
]

# Reddit posts older than this are ignored (in case the subreddit goes
# quiet and we restart with stale state — don't fire alerts on
# month-old posts).
REDDIT_MAX_AGE_S = 7 * 86400


def log(msg):
    print(msg, flush=True)


def load_state():
    if STATE_PATH.exists():
        try:
            return json.loads(STATE_PATH.read_text())
        except json.JSONDecodeError:
            log("[state] corrupt, starting fresh")
    return {"reddit_ids": [], "cg_hash": "", "kg_hash": ""}


def save_state(state):
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    state["reddit_ids"] = state["reddit_ids"][-500:]
    STATE_PATH.write_text(json.dumps(state, indent=2))


def fetch(url, timeout=20):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.read()


def push(title, body, url, tag):
    if not PUSH_TOKEN:
        log(f"[push-skip] no token: {title} | {body}")
        return
    payload = json.dumps({"title": title, "body": body, "url": url, "tag": tag}).encode()
    req = urllib.request.Request(
        f"{DASHBOARD_URL}/api/event",
        data=payload,
        headers={"Content-Type": "application/json", "X-Push-Token": PUSH_TOKEN},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            if r.status != 200:
                log(f"[push-fail] HTTP {r.status} for {title}")
    except urllib.error.URLError as e:
        log(f"[push-fail] {title}: {e}")


def normalize(html_bytes):
    """Strip volatile content (scripts, styles, digits) so the hash is
    stable across counter ticks and one-time CSRF tokens."""
    s = html_bytes.decode("utf-8", errors="replace")
    s = re.sub(r"<script\b[^>]*>.*?</script>", "", s, flags=re.S | re.I)
    s = re.sub(r"<style\b[^>]*>.*?</style>", "", s, flags=re.S | re.I)
    s = re.sub(r"<!--.*?-->", "", s, flags=re.S)
    s = re.sub(r"\d+", "", s)
    s = re.sub(r"\s+", " ", s).strip().lower()
    return s


def check_reddit(state):
    try:
        status, body = fetch("https://www.reddit.com/r/OpenSignups/new.json?limit=50")
    except Exception as e:
        log(f"[reddit] fetch failed: {e}")
        return
    if status != 200:
        log(f"[reddit] HTTP {status}")
        return
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        log("[reddit] bad JSON")
        return

    seen = set(state["reddit_ids"])
    cutoff = time.time() - REDDIT_MAX_AGE_S
    posts = data.get("data", {}).get("children", [])
    hits = 0
    for child in posts:
        p = child.get("data", {})
        pid = p.get("id")
        if not pid or pid in seen:
            continue
        if p.get("created_utc", 0) < cutoff:
            # Mark as seen so we don't keep re-evaluating
            state["reddit_ids"].append(pid)
            continue
        title = p.get("title", "") or ""
        text = p.get("selftext", "") or ""
        haystack = f"{title}\n{text}"
        for t in WATCHLIST:
            if t["match"].search(haystack):
                permalink = p.get("permalink", "")
                full_url = f"https://www.reddit.com{permalink}" if permalink else ""
                log(f"[reddit-hit] {t['name']}: {title}")
                push(
                    title=f"{t['name']} signup spotted",
                    body=title[:140],
                    url=full_url,
                    tag=f"tracker-{t['name'].lower()}",
                )
                hits += 1
                break
        state["reddit_ids"].append(pid)
    log(f"[reddit] checked {len(posts)} posts, {hits} hit(s)")


def check_direct(state):
    for t in DIRECT_POLLS:
        try:
            status, body = fetch(t["url"])
        except Exception as e:
            log(f"[direct] {t['name']}: {e}")
            continue
        if status != 200:
            log(f"[direct] {t['name']} HTTP {status}")
            continue
        h = hashlib.sha256(normalize(body).encode()).hexdigest()
        prev = state.get(t["key"], "")
        if not prev:
            state[t["key"]] = h
            log(f"[direct-init] {t['name']} hash={h[:12]}")
            continue
        if h != prev:
            log(f"[direct-change] {t['name']} {prev[:12]} -> {h[:12]}")
            push(
                title=f"{t['name']} page changed",
                body="Homepage content shifted — possible signup window. Check the site.",
                url=t["url"],
                tag=f"tracker-direct-{t['name'].lower()}",
            )
            state[t["key"]] = h
        else:
            log(f"[direct] {t['name']} unchanged")


def tick():
    state = load_state()
    check_reddit(state)
    check_direct(state)
    save_state(state)


def main():
    once = "--once" in sys.argv
    log(f"[start] interval={INTERVAL_MIN}min trackers={[t['name'] for t in WATCHLIST]}")
    while True:
        try:
            tick()
        except Exception as e:
            log(f"[tick-fail] {e}")
        if once:
            return
        time.sleep(INTERVAL_MIN * 60)


if __name__ == "__main__":
    main()
