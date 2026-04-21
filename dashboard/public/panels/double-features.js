import { PANELS as DOTS } from '../config.js';
import { esc } from '../utils.js';

let root, listEl;
let cached = null;

function dots() {
  return Array.from({ length: DOTS }, (_, i) => `<div class="dot" data-p="${i}"></div>`).join('');
}

async function dismiss(id, btn) {
  btn.disabled = true;
  btn.textContent = 'Dismissing…';
  try {
    const res = await fetch(`/api/double-features/${encodeURIComponent(id)}/dismiss`, { method: 'POST' });
    if (!res.ok) throw new Error();
    await refresh();
  } catch {
    btn.textContent = 'Failed';
    setTimeout(() => { btn.textContent = 'Dismiss'; btn.disabled = false; }, 2000);
  }
}

function render() {
  if (!cached) { listEl.innerHTML = ''; return; }
  if (!cached.length) {
    listEl.innerHTML = '<div class="df-empty">No double features queued. The bot adds new ones when this panel drops below 6.</div>';
    return;
  }
  listEl.innerHTML = cached.map(d => `
    <div class="df-item" data-id="${esc(d.id)}">
      <div class="df-pair">
        <span class="df-film">${esc(d.filmA)}</span>
        <span class="df-plus">+</span>
        <span class="df-film">${esc(d.filmB)}</span>
      </div>
      <div class="df-reason">${esc(d.reason)}</div>
      <div class="df-actions">
        <button class="df-btn dismiss">Dismiss</button>
      </div>
    </div>
  `).join('');
  listEl.querySelectorAll('.df-item').forEach(card => {
    const btn = card.querySelector('.dismiss');
    btn.addEventListener('click', () => dismiss(card.dataset.id, btn));
  });
}

async function refresh() {
  try {
    const res = await fetch('/api/double-features');
    cached = await res.json();
    render();
  } catch {
    cached = [];
    listEl.innerHTML = '<div class="df-empty">Could not load double features.</div>';
  }
}

function mount() {
  root = document.createElement('div');
  root.className = 'panel panel-double-features scrollable';
  root.id = 'panelDoubleFeatures';
  root.innerHTML = `
    <div class="panel-inner">
      <div class="critter-zone"><div class="otter critter">🦦</div></div>
      <div class="section-title-df">DOUBLE FEATURES</div>
      <div class="df-list"></div>
      <div class="dots">${dots()}</div>
    </div>
  `;
  listEl = root.querySelector('.df-list');
  return root;
}

export default { id: 'double-features', mount, refresh, onShow: refresh };
