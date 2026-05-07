FROM oven/bun:1

# yt-dlp + ffmpeg + python3 are needed by scripts/youtube-grab.sh, which
# the dashboard's /api/youtube-grab endpoint spawns. Pin nothing — yt-dlp
# breaks against YouTube every few weeks; rebuild the image to refresh.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl ffmpeg python3 python3-pip \
    && pip3 install --break-system-packages --no-cache-dir yt-dlp \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile 2>/dev/null || bun install
COPY . .
EXPOSE 8000
CMD ["bun", "run", "server.ts"]
