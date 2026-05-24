// ClawTabs app-shell service worker.
//
// Purpose: keep the app launchable when the network or the local gateway is
// briefly unavailable (Android Doze, cellular handoffs, screen-wake). Without
// this, every cold start was a hard network requirement, which is why
// Android-Chrome PWAs felt much flakier than iOS-Safari PWAs.
//
// Strategy:
//   - precache the app shell on install (HTML, JS, CSS, manifest, icons)
//   - stale-while-revalidate for same-origin shell assets: serve cache
//     immediately if we have it, fetch in background, update cache for next
//     load. Falls back to network when cache is empty.
//   - never intercept the WebSocket, the gateway control plane, or
//     openclaw-cli-images / assistant-media URLs. Those stay live-only.
//   - bump SHELL_CACHE_VERSION whenever the shell changes shape; old caches
//     are pruned on activate.

const SHELL_CACHE_VERSION = "clawtabs-shell-v2";
const APP_BASE = (() => {
  // Service worker scope is /clawtabs/ — strip the trailing slash for join.
  try { return new URL(self.registration.scope).pathname.replace(/\/+$/, ""); }
  catch { return "/clawtabs"; }
})();

const SHELL_ASSETS = [
  `${APP_BASE}/`,
  `${APP_BASE}/index.html`,
  `${APP_BASE}/app.js`,
  `${APP_BASE}/theme.css`,
  `${APP_BASE}/manifest.json`,
  `${APP_BASE}/favicon-32.png`,
  `${APP_BASE}/icon-192.png`,
  `${APP_BASE}/icon-512.png`,
];

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(SHELL_CACHE_VERSION);
    // Precache best-effort: a single 404 shouldn't break installation.
    await Promise.allSettled(SHELL_ASSETS.map((u) => cache.add(u)));
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    // Drop any older cache versions so the install always lands clean.
    const keys = await caches.keys();
    await Promise.all(keys.filter((k) => k !== SHELL_CACHE_VERSION).map((k) => caches.delete(k)));
    await self.clients.claim();
  })());
});

// Pass-through paths that must always hit network (never serve from cache).
function isPassThrough(url) {
  if (url.pathname.startsWith("/__openclaw__/")) return true;        // gateway WS / media
  if (url.pathname.startsWith("/api/")) return true;                  // any API
  if (url.pathname.includes("/openclaw-cli-images/")) return true;    // user attachments
  if (url.pathname.includes("/assistant-media")) return true;         // model-attached media
  return false;
}

function isShellAsset(url, request) {
  if (request.method !== "GET") return false;
  if (url.origin !== self.location.origin) return false;
  const p = url.pathname;
  if (p === APP_BASE || p === `${APP_BASE}/` || p === `${APP_BASE}/index.html`) return true;
  if (p.endsWith(".js") || p.endsWith(".css") || p.endsWith(".svg")
      || p.endsWith(".png") || p.endsWith(".webp") || p.endsWith(".ico")
      || p.endsWith("/manifest.json")) {
    return p.startsWith(`${APP_BASE}/`);
  }
  return false;
}

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;
  let url;
  try { url = new URL(req.url); } catch { return; }
  if (isPassThrough(url)) return;
  if (!isShellAsset(url, req)) return;

  event.respondWith((async () => {
    const cache = await caches.open(SHELL_CACHE_VERSION);
    const cached = await cache.match(req, { ignoreSearch: true });
    // Stale-while-revalidate: respond from cache immediately, refresh in bg.
    const networkFetch = fetch(req).then((resp) => {
      if (resp && resp.ok && resp.type === "basic") {
        cache.put(req, resp.clone()).catch(() => {});
      }
      return resp;
    }).catch(() => null);

    if (cached) {
      event.waitUntil(networkFetch);
      return cached;
    }
    const fresh = await networkFetch;
    if (fresh) return fresh;
    const anyCache = await caches.match(req, { ignoreSearch: true });
    if (anyCache) return anyCache;
    return new Response("ClawTabs is offline and this asset isn't cached yet.",
      { status: 503, statusText: "Offline" });
  })());
});

self.addEventListener("message", (event) => {
  if (event.data === "SKIP_WAITING") self.skipWaiting();
});
