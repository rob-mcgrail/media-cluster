import { PANELS as DOTS } from '../config.js';

import { esc, fmtAgo, fmtLease } from '../utils.js';



let root, listEl, titleEl;
let perClient = null;  // null until /api/config resolves

function dots() {
  return Array.from({ length: DOTS }, (_, i) => `<div class="dot" data-p="${i}"></div>`).join('');
}

async function loadConfig() {
  if (perClient !== null) return;
  try {
    const res = await fetch('/api/config');
    const cfg = await res.json();
    perClient = cfg.piholePanel === 'clients';
  } catch {
    perClient = false;
  }
  if (titleEl) titleEl.textContent = perClient ? 'CLIENTS' : 'BLOCKS';
}

async function refreshClients() {
  try {
    const res = await fetch('/api/pihole-clients');
    const items = await res.json();
    if (!items.length) {
      listEl.innerHTML = '<div class="client-empty">No client data yet.</div>';
      return;
    }
    const maxTotal = Math.max(1, ...items.map(x => x.total));
    listEl.innerHTML = items.map(c => {
      const totalPct = Math.round((c.total / maxTotal) * 100);
      const blockedFrac = c.total > 0 ? c.blocked / c.total : 0;
      const blockedWidth = totalPct * blockedFrac;
      const allowedWidth = totalPct - blockedWidth;
      const displayName = c.name && c.name !== c.ip ? c.name.replace(/\.lan$/i, '') : c.ip;
      const ipBadge = (c.name && c.name !== c.ip) ? `<span class="client-ip">${esc(c.ip)}</span>` : '';
      return `
        <div class="client-card">
          <div><span class="client-name">${esc(displayName)}</span>${ipBadge}</div>
          <div class="client-counts">
            <span><span class="allowed">${c.permitted.toLocaleString()}</span> allowed</span>
            <span><span class="blocked">${c.blocked.toLocaleString()}</span> blocked</span>
            <span>${c.blockedPct}% block rate</span>
            <span>last: ${fmtAgo(c.lastSeen)}</span>
            <span>${fmtLease(c.leaseExpiry)}</span>
          </div>
          <div class="client-bar">
            <div class="client-bar-allowed" style="width:${allowedWidth}%"></div>
            <div class="client-bar-blocked" style="width:${blockedWidth}%"></div>
          </div>
        </div>
      `;
    }).join('');
  } catch {
    listEl.innerHTML = '<div class="client-empty">Could not load clients.</div>';
  }
}

async function refreshBlocks() {
  try {
    const res = await fetch('/api/pihole-top-blocked');
    const items = await res.json();
    if (!items.length) {
      listEl.innerHTML = '<div class="client-empty">No blocks in the last 24h.</div>';
      return;
    }
    const maxCount = Math.max(1, ...items.map(x => x.count));
    listEl.innerHTML = items.map(d => {
      const pct = Math.round((d.count / maxCount) * 100);
      return `
        <div class="block-card">
          <div class="block-row">
            <span class="block-domain">${esc(d.domain)}</span>
            <span class="block-count">${d.count.toLocaleString()}</span>
          </div>
          <div class="block-bar"><div class="block-bar-fill" style="width:${pct}%"></div></div>
        </div>
      `;
    }).join('');
  } catch {
    listEl.innerHTML = '<div class="client-empty">Could not load blocks.</div>';
  }
}

async function refresh() {
  await loadConfig();
  return perClient ? refreshClients() : refreshBlocks();
}

function mount() {
  root = document.createElement('div');
  root.className = 'panel panel-pihole scrollable';
  root.id = 'panelPihole';
  root.innerHTML = `
    <div class="spooky-zone">
      <div class="spooky critter spooky-tl">💀</div>
      <div class="spooky critter spooky-tr">🦇</div>
      <div class="spooky critter spooky-bl">🦇</div>
      <div class="spooky critter spooky-br">💀</div>
    </div>
    <div class="panel-inner">
      <div class="critter-zone"><div class="spider critter">🕷️</div></div>
      <div class="section-title-red"><span class="pihole-title">BLOCKS</span> <span class="section-title-sub">last 24h</span></div>
      <div class="client-list"></div>
      <div class="dots">${dots()}</div>
    </div>
  `;
  listEl = root.querySelector('.client-list');
  titleEl = root.querySelector('.pihole-title');
  return root;
}

export default { id: 'pihole', mount, refresh, onShow: refresh };
