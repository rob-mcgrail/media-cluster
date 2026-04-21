// Live binding — app.js sets this before any panel mounts, based on the
// dynamic panel list after filtering against /api/config.
export let PANELS = 6;
export function setPanels(n) { PANELS = n; }
