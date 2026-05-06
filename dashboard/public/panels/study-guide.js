import { PANELS as DOTS } from '../config.js';

let root, contentEl;
let loaded = false;

function dots() {
  return Array.from({ length: DOTS }, (_, i) => `<div class="dot" data-p="${i}"></div>`).join('');
}

async function load() {
  if (loaded) return;
  try {
    // Cache-bust so edits to the markdown show up without a hard reload.
    const res = await fetch(`/study-guide.md?t=${Date.now()}`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const md = await res.text();
    contentEl.innerHTML = marked.parse(md);
    loaded = true;
  } catch (e) {
    contentEl.innerHTML = `<div class="study-error">Couldn't load study-guide.md: ${e.message}</div>`;
  }
}

function mount() {
  root = document.createElement('div');
  root.className = 'panel panel-study scrollable';
  root.id = 'panelStudy';
  root.innerHTML = `
    <div class="panel-inner">
      <div class="section-title-study">SIGNUP STUDY GUIDE</div>
      <div class="study-content" id="studyContent">
        <div class="study-loading">Loading…</div>
      </div>
      <div class="dots">${dots()}</div>
    </div>
  `;
  contentEl = root.querySelector('#studyContent');
  return root;
}

function onShow() {
  load();
}

function refresh() {
  loaded = false;
  load();
}

export default { id: 'study', mount, onShow, refresh };
