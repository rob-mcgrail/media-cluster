# DHCP setup

## Current state

- **DHCP server:** Orbi router at `192.168.1.1` (main router does DHCP for the LAN).
- **DNS:** Pi-hole on nagano. Orbi is configured to hand out nagano's LAN IP as the DNS server via its DHCP DNS setting, so LAN clients resolve through Pi-hole.
- **nagano's own IP:** static, configured in `/etc/netplan/50-cloud-init.yaml` (`192.168.1.33/24`, gateway `192.168.1.1`, nameserver `127.0.0.1`). `cloud-init`'s network regen is disabled via `/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg` so the netplan file is stable across reboots.

## Why nagano is on a static IP

Incident on 2026-04-19: `eno1`'s DHCP lease expired on its 24h mark and couldn't renew. The host lost its IP, systemd-resolved fell back to `1.1.1.1`, and Docker's embedded resolver started timing out for every outbound lookup — full LAN outage feel.

Recovery required an external DHCP server because at the time Pi-hole was doing DHCP — which put nagano in the position of being a DHCP client of a server running on itself. Chicken-and-egg: no IP → no outbound → no way to renew.

Static IP on `eno1` removes that failure mode entirely. nagano never asks anyone for a lease.

## Pi-hole DHCP as an alternative

Pi-hole can also run DHCP. The reason to consider it: without Pi-hole issuing leases, the DNS query log can only attribute queries to IP addresses, not hostnames. Pi-hole DHCP gives you per-client attribution in the dashboard.

Trade-off is what bit us above — and there are two more gotchas to know if you ever switch back:

1. **Dual-DHCP races.** If both Pi-hole and Orbi serve DHCP on the same LAN, whichever answers a given `DISCOVER` first wins, and clients get inconsistent config. To switch to Pi-hole DHCP cleanly, turn Orbi DHCP off.

2. **Satellite server-identifier rejection.** At least one Orbi satellite on this network will not accept Pi-hole's DHCPACK because its `server-identifier` is Pi-hole's IP (`192.168.1.33`) rather than the Orbi's (`192.168.1.1`). Symptom: satellite won't come online after a cold boot until Pi-hole DHCP is disabled. Untested mitigation:
   ```
   dhcp-option-force=option:server-identifier,192.168.1.1
   ```
   in a Pi-hole dnsmasq config, plus a MAC reservation for the satellite.

## Switching between the two

**Orbi DHCP (current):** Pi-hole → Settings → DHCP → disable. Orbi admin → LAN Setup → enable DHCP. Make sure Orbi's DHCP DNS option points at `192.168.1.33` so clients still resolve through Pi-hole.

**Pi-hole DHCP:** reverse of the above. Disable Orbi DHCP first to avoid the race, then enable Pi-hole's. Test a satellite cold boot before walking away.
