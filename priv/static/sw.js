const SHELL_CACHE = "ranch-shell-v15";
const DOCS_CACHE = "ranch-docs-v1";
// Photos kept for Barn mode (see barn.js); refreshed while online.
const BARN_MEDIA = "ranch-barn-media-v1";
const SHELL_ASSETS = [
  "/offline.html",
  "/barn.html",
  "/barn.js",
  "/icons/icon-192.png",
  "/assets/css/app.css",
  "/assets/js/app.js",
  "/manifest.json",
  "/pdfjs/pdf.min.mjs",
  "/pdfjs/pdf.worker.min.mjs",
];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(SHELL_CACHE).then((cache) => cache.addAll(SHELL_ASSETS)));
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== SHELL_CACHE && k !== DOCS_CACHE && k !== BARN_MEDIA).map((k) => caches.delete(k)))
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

  // Other uploaded photos (file names never change): whatever's kept on the device
  // first, so Barn mode shows them with no signal; otherwise the network.
  if (url.pathname.startsWith("/uploads/") && event.request.method === "GET") {
    event.respondWith(caches.match(event.request).then((cached) => cached || fetch(event.request)));
    return;
  }

  // Page navigations: network-first. With no connection, Barn mode (or Papers, or
  // Barn mode itself) from the device; LiveView pages need a live connection.
  // Barn Wi-Fi with no internet looks "online" but never answers: after 8 seconds,
  // Barn mode instead of a page that spins forever.
  if (event.request.mode === "navigate") {
    const offline = () =>
      caches.match(event.request, {ignoreSearch: true}).then((hit) => hit || caches.match("/barn.html"))
    const slow = new Promise((resolve) => setTimeout(() => resolve("slow"), 8000))
    event.respondWith(
      Promise.race([fetch(event.request), slow])
        .then((res) => (res === "slow" ? offline() : res))
        .catch(offline)
    );
    return;
  }

  // App shell assets: cache-first, network fallback.
  if (SHELL_ASSETS.includes(url.pathname)) {
    event.respondWith(caches.match(event.request).then((cached) => cached || fetch(event.request)));
  }
});

// Phone notifications (reminders): show them, and open the right page when tapped.
self.addEventListener("push", (event) => {
  let msg = {}
  try { msg = event.data ? event.data.json() : {} } catch (e) { msg = {body: event.data && event.data.text()} }
  event.waitUntil(
    self.registration.showNotification(msg.title || "Gimel Ranch", {
      body: msg.body || "",
      tag: msg.tag,
      // A newer one with the same tag (like "Siri notes to check") still buzzes.
      renotify: !!msg.tag,
      icon: "/icons/icon-192.png",
      badge: "/icons/icon-192.png",
      data: {url: msg.url || "/"},
    })
  )
})

self.addEventListener("notificationclick", (event) => {
  event.notification.close()
  const url = (event.notification.data && event.notification.data.url) || "/"
  event.waitUntil(
    self.clients.matchAll({type: "window", includeUncontrolled: true}).then((wins) => {
      for (const w of wins) {
        if ("focus" in w) { w.navigate(url); return w.focus() }
      }
      return self.clients.openWindow(url)
    })
  )
})
