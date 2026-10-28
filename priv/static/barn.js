// Barn mode engine (see /barn.html and RanchPhxWeb.BarnController).
//
// While online: keeps a copy of everything worth reading at the barn (the snapshot)
// and the photos it shows. Offline: what's added waits here (the outbox) and goes up
// as soon as there's a connection again. Loaded by /barn.html, and by the app itself
// so the copy stays fresh and anything waiting gets sent.
(() => {
  if (window.RanchBarn) return

  const DB = "ranch-barn", MEDIA = "ranch-barn-media-v1"
  const listeners = new Set()
  let dbp = null, syncing = null

  function db() {
    if (!dbp) {
      dbp = new Promise((resolve, reject) => {
        const req = indexedDB.open(DB, 1)
        req.onupgradeneeded = () => {
          const d = req.result
          if (!d.objectStoreNames.contains("kv")) d.createObjectStore("kv")
          if (!d.objectStoreNames.contains("outbox")) d.createObjectStore("outbox", {keyPath: "client_id"})
        }
        req.onsuccess = () => resolve(req.result)
        req.onerror = () => reject(req.error)
      })
    }
    return dbp
  }

  async function tx(store, mode, fn) {
    const d = await db()
    return new Promise((resolve, reject) => {
      const t = d.transaction(store, mode)
      const s = t.objectStore(store)
      let out
      Promise.resolve(fn(s)).then((v) => { out = v })
      t.oncomplete = () => resolve(out)
      t.onerror = () => reject(t.error)
    })
  }

  const req = (r) => new Promise((resolve, reject) => { r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error) })
  const get = (key) => tx("kv", "readonly", (s) => req(s.get(key)))
  const set = (key, v) => tx("kv", "readwrite", (s) => { s.put(v, key) })
  const outbox = () => tx("outbox", "readonly", (s) => req(s.getAll())).then((xs) => (xs || []).sort((a, b) => a.created - b.created))
  const put = (op) => tx("outbox", "readwrite", (s) => { s.put(op) })
  const del = (id) => tx("outbox", "readwrite", (s) => { s.delete(id) })

  const emit = () => listeners.forEach((f) => { try { f() } catch (e) {} })
  const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : Date.now().toString(36) + Math.random().toString(36).slice(2))

  // Anything that isn't our JSON (the sign-in page, Cloudflare's sign-in) means sign in again.
  async function api(path, opts = {}) {
    const res = await fetch(path, {credentials: "same-origin", redirect: "follow", ...opts,
      headers: {accept: "application/json", ...(opts.headers || {})}})
    const type = res.headers.get("content-type") || ""
    if (!type.includes("application/json")) throw new Error("signin")
    const body = await res.json()
    if (!res.ok) throw new Error(body.error || "The ranch app said no (" + res.status + ").")
    return body
  }

  // ── Keeping the copy ──
  async function refresh() {
    const body = await api("/api/barn/snapshot")
    await set("snapshot", body.snapshot)
    await set("meta", {refreshed: Date.now(), can_edit: body.can_edit})
    emit()
    keepPhotos(body.media || []).catch(() => {})
    return body.snapshot
  }

  // Keeps the photos the copy shows; lets go of ones it no longer shows.
  async function keepPhotos(urls) {
    if (!("caches" in window)) return
    const cache = await caches.open(MEDIA)
    const want = new Set(urls)
    for (const r of await cache.keys()) {
      if (!want.has(new URL(r.url).pathname)) await cache.delete(r)
    }
    const missing = []
    for (const u of urls) if (!(await cache.match(u))) missing.push(u)
    let i = 0
    const worker = async () => {
      while (i < missing.length) {
        const u = missing[i++]
        try { const res = await fetch(u, {credentials: "same-origin"}); if (res.ok) await cache.put(u, res) } catch (e) {}
      }
    }
    await Promise.all([worker(), worker(), worker()])
  }

  // ── Adding while offline ──
  async function add(op) {
    const item = {...op, client_id: uuid(), created: Date.now()}
    await put(item)
    emit()
    if (navigator.onLine) sync().catch(() => {})
    return item
  }

  // Sends everything waiting. Photos one at a time, the rest together.
  function sync() {
    if (syncing) return syncing
    syncing = (async () => {
      let sent = 0, failed = 0
      try {
        const items = await outbox()
        for (const p of items.filter((x) => x.kind === "photo")) {
          const form = new FormData()
          for (const [k, v] of Object.entries(p)) if (k !== "blob" && k !== "kind" && v != null) form.append(k, v)
          form.append("file", p.blob, "barn.jpg")
          try {
            await api("/api/barn/photo", {method: "POST", body: form})
            await del(p.client_id); sent++
          } catch (e) {
            if (e.message === "signin") throw e
            await put({...p, error: e.message}); failed++
          }
        }
        const rest = items.filter((x) => x.kind !== "photo")
        if (rest.length) {
          const body = await api("/api/barn/sync", {method: "POST",
            headers: {"content-type": "application/json"}, body: JSON.stringify({ops: rest})})
          for (const r of body.results || []) {
            if (r.ok) { await del(r.client_id); sent++ }
            else { const it = rest.find((x) => x.client_id === r.client_id); if (it) await put({...it, error: r.error}); failed++ }
          }
        }
        await set("lastSync", {at: Date.now(), sent, failed})
        if (sent) await refresh().catch(() => {})
        return {sent, failed}
      } finally {
        syncing = null
        emit()
      }
    })()
    return syncing
  }

  // In the app: keep the copy fresh (at most every 20 minutes) and send anything waiting.
  async function background() {
    if (!navigator.onLine) return
    try {
      if ((await outbox()).length) await sync()
      const meta = await get("meta")
      if (!meta || Date.now() - meta.refreshed > 20 * 60 * 1000) await refresh()
    } catch (e) {}
  }

  window.addEventListener("online", () => { sync().catch(() => {}).finally(() => refresh().catch(() => {})) })

  window.RanchBarn = {
    refresh, sync, add, outbox, background, remove: async (id) => { await del(id); emit() },
    snapshot: () => get("snapshot"), meta: () => get("meta"), lastSync: () => get("lastSync"),
    onChange: (f) => { listeners.add(f); return () => listeners.delete(f) },
  }
})()
