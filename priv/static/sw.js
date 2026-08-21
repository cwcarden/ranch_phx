const SHELL_CACHE = "ranch-shell-v1";
const DOCS_CACHE = "ranch-docs-v1";
const SHELL_ASSETS = ["/offline.html", "/assets/css/app.css", "/assets/js/app.js", "/manifest.json"];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(SHELL_CACHE).then((cache) => cache.addAll(SHELL_ASSETS)));
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== SHELL_CACHE && k !== DOCS_CACHE).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  // Saved document PDFs: cache-first. Never auto-caches — only serves what was
  // explicitly saved via the "Save Offline" button (see app.js SaveOffline hook).
  if (url.pathname.startsWith("/uploads/") && url.pathname.includes("/documents/")) {
    event.respondWith(caches.match(event.request).then((cached) => cached || fetch(event.request)));
    return;
  }

  // Page navigations: network-first, falling back to the offline shell when
  // there's no connection (LiveView pages need a live socket, so they can't
  // render usefully offline anyway).
  if (event.request.mode === "navigate") {
    event.respondWith(fetch(event.request).catch(() => caches.match("/offline.html")));
    return;
  }

  // App shell assets: cache-first, network fallback.
  if (SHELL_ASSETS.includes(url.pathname)) {
    event.respondWith(caches.match(event.request).then((cached) => cached || fetch(event.request)));
  }
});
