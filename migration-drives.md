# Migrating to a new drive

Everything goes through `DATA_ROOT` in `.env`, so switching drives is a one-line change.

## Steps

1. Mount the new drive:
   ```sh
   sudo mkdir -p /mnt/newdrive/data
   sudo mount /dev/sdX1 /mnt/newdrive
   ```

2. Stop the stack:
   ```sh
   docker compose down
   ```

3. Copy data preserving permissions and hardlinks:
   ```sh
   sudo rsync -avHP /srv/data/ /mnt/newdrive/data/
   ```
   `-H` is important — Sonarr/Radarr use hardlinks from torrents to media, so without it you'll double your disk usage.

4. Update `.env`:
   ```
   DATA_ROOT=/mnt/newdrive/data
   ```

5. Start the stack:
   ```sh
   docker compose up -d
   ```

## What doesn't change

- Container paths (`/data/media`, `/data/torrents`) are the same — only the host mount moves.
- Config (`./config`) stays on the boot drive. Databases, API keys, settings are untouched.
- Nothing to reconfigure inside Sonarr, Radarr, Jellyfin, Bazarr, or qBittorrent.

## After migration

- Verify services are healthy: `docker ps`
- Spot-check a file: `ls "$DATA_ROOT/media/tv"`
- Once confirmed, optionally add the new mount to `/etc/fstab` for persistence across reboots.
- Remove old data when satisfied: `sudo rm -rf /srv/data`

## Making the mount persist (fstab)

USB drives won't auto-mount to the right path after a reboot. Add an fstab entry so it mounts consistently.

1. Find the drive's UUID (stable across reboots, unlike `/dev/sdX` which can change):
   ```sh
   sudo blkid /dev/sdX1
   ```

2. Add a line to `/etc/fstab`:
   ```
   UUID=xxxx-xxxx-xxxx  /mnt/newdrive  ext4  defaults,nofail  0  2
   ```
   - `nofail` — system boots normally even if the drive isn't plugged in. Without this, a missing USB drive will hang the boot.
   - Change `ext4` to match the filesystem (check `blkid` output for `TYPE=`).

3. Test without rebooting:
   ```sh
   sudo mount -a
   df -h /mnt/newdrive
   ```

4. If the drive isn't plugged in at boot, the stack will start with missing volumes. The containers will restart in a loop until the drive is mounted and `docker compose up -d` is run again.
