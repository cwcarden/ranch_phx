// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import {HoofMeasure} from "./hoof_measure"
import {installDocViewer, closeDoc} from "./doc_viewer"
import {PhotoMarkup} from "./photo_markup"
import {NotePad} from "./note_pad"

const OFFLINE_DOCS_KEY = "gimelRanchOfflineDocs"
const DOCS_CACHE = "ranch-docs-v1"

// Documents open in our own viewer (see doc_viewer.js): never the bare file.
installDocViewer()

// Barn mode (/barn.html, /barn.js): while the app is open and online, keep the copy for
// the barn fresh and send anything added offline. If the connection drops, offer it.
{
  const s = document.createElement("script")
  s.src = "/barn.js"
  s.onload = () => setTimeout(() => window.RanchBarn && window.RanchBarn.background(), 4000)
  document.head.appendChild(s)

  const offer = () => {
    if (navigator.onLine || document.getElementById("barn-offer")) return
    const a = document.createElement("a")
    a.id = "barn-offer"
    a.href = "/barn.html"
    a.textContent = "No connection · Open Barn mode"
    a.style.cssText = "position:fixed;left:50%;transform:translateX(-50%);bottom:calc(16px + env(safe-area-inset-bottom));z-index:500;background:#b45309;color:#fff;padding:14px 20px;border-radius:14px;font:800 16px -apple-system,system-ui,sans-serif;text-decoration:none;box-shadow:0 6px 20px rgba(0,0,0,.3)"
    document.body.appendChild(a)
  }
  window.addEventListener("offline", offer)
  window.addEventListener("online", () => { const a = document.getElementById("barn-offer"); if (a) a.remove() })
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", offer)
  else offer()
}

// Swap a broken hero photo (cover_photo_url points at a missing/corrupt
// file) for the placeholder icon. Only touches the DOM when loading
// actually fails, rather than always rendering a hidden placeholder next
// to the <img> — a hidden sibling there was interfering with the image's
// paint in some browsers even though it never became visible.
window.handleHeroPhotoError = function (img) {
  img.outerHTML =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="48" height="48" style="color:var(--text3)">' +
    '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/>' +
    '<polyline points="21 15 16 10 5 21"/></svg>'
}

function loadOfflineDocs() {
  try {
    return JSON.parse(localStorage.getItem(OFFLINE_DOCS_KEY) || "[]")
  } catch (e) {
    return []
  }
}

function saveOfflineDocs(docs) {
  localStorage.setItem(OFFLINE_DOCS_KEY, JSON.stringify(docs))
}

// Papers the person took off this device on purpose, so the Papers button doesn't
// put them back. Saving one again clears it.
const OFFLINE_REMOVED_KEY = "gimelRanchOfflineRemoved"
function loadRemoved() {
  try {
    return new Set(JSON.parse(localStorage.getItem(OFFLINE_REMOVED_KEY) || "[]"))
  } catch (e) {
    return new Set()
  }
}
function setRemoved(url, removed) {
  const set = loadRemoved()
  removed ? set.add(url) : set.delete(url)
  localStorage.setItem(OFFLINE_REMOVED_KEY, JSON.stringify([...set]))
}

// One saved paper, from the server's paper_meta. `auto` marks the Papers button's own
// pick (it may swap in a newer one); a paper saved by hand is kept as chosen.
function offlineEntry(meta, animalId, animalName, auto) {
  return {
    id: String(meta.id), animalId: String(animalId), animalName, title: meta.title,
    docType: meta.type, label: meta.label, docDate: meta.date, mime: meta.mime,
    url: meta.url, auto: !!auto, cachedAt: Date.now()
  }
}

async function cacheDoc(url) {
  if (!("caches" in window)) return
  const cache = await caches.open(DOCS_CACHE)
  if (await cache.match(url)) return
  const res = await fetch(url)
  if (res.ok) await cache.put(url, res.clone())
}

async function uncacheDoc(url) {
  if ("caches" in window) await (await caches.open(DOCS_CACHE)).delete(url)
}

function isDocSaved(url) {
  return loadOfflineDocs().some((d) => d.url === url)
}

const Hooks = {HoofMeasure, PhotoMarkup, NotePad}

// "Papers" on an animal: saves its current Coggins, health certificate, registration
// and brand inspection on this device, then opens them full screen. Saved copies
// open at the arena with no signal (see /offline.html and sw.js).
Hooks.ShowPapers = {
  mounted() {
    this.el.addEventListener("click", () => this.open())
  },

  async open() {
    const {animalId, animalName} = this.el.dataset
    const papers = JSON.parse(this.el.dataset.papers || "[]")
    const all = JSON.parse(this.el.dataset.all || "[]")
    const label = this.el.querySelector(".btn-label")
    if (label) label.textContent = "Saving…"

    const mine = (d) => String(d.animalId) === String(animalId)
    const byId = new Map(all.map((m) => [String(m.id), m]))
    const current = (d) => {
      const m = byId.get(String(d.id))
      return m && m.url === d.url ? m : null
    }
    const removed = loadRemoved()
    let docs = loadOfflineDocs()

    // Bring this horse's saved papers up to date: drop ones deleted in the app,
    // refresh names and dates on the rest.
    for (const d of docs.filter(mine)) {
      if (!current(d)) await uncacheDoc(d.url).catch(() => {})
    }
    docs = docs
      .filter((d) => !mine(d) || current(d))
      .map((d) => (mine(d) ? {...offlineEntry(current(d), animalId, animalName, d.auto), cachedAt: d.cachedAt} : d))

    // For each kind of paper: what you picked stays. Only a kind with nothing saved
    // (or only an older automatic pick) gets the newest one, unless you removed it.
    for (const p of papers) {
      const saved = docs.filter((d) => mine(d) && d.docType === p.type)
      if (saved.some((d) => d.url === p.url) || saved.some((d) => !d.auto) || removed.has(p.url)) continue
      try {
        await cacheDoc(p.url)
      } catch (e) {
        // No signal: whatever was saved before still opens.
        if (saved.length) continue
      }
      for (const old of saved) await uncacheDoc(old.url).catch(() => {})
      docs = docs.filter((d) => !saved.includes(d))
      docs.push(offlineEntry(p, animalId, animalName, true))
    }

    saveOfflineDocs(docs)
    window.dispatchEvent(new Event("gimel:offline-docs-updated"))
    window.location.href = "/offline.html?animal=" + encodeURIComponent(animalId)
  }
}

// Training sections fold up. Which ones are open is remembered on this device
// (all start closed). Jumping to a section, or tapping one of its buttons, opens it.
Hooks.Sections = {
  mounted() {
    this.key = "ranch:open-sections"
    let open = []
    try { open = JSON.parse(localStorage.getItem(this.key) || "[]") } catch (e) {}
    this.el.querySelectorAll(".tr-sec[id]").forEach((s) => {
      if (open.includes(s.id)) this.js().addClass(s, "open")
    })
    this.el.addEventListener("ranch:sec-toggled", () => setTimeout(() => this.save(), 200))
    this.el.addEventListener("click", (e) => {
      const jump = e.target.closest("a[href^='#']")
      const action = e.target.closest(".tr-sec-actions")
      const sec = jump ? document.querySelector(jump.getAttribute("href")) : action && action.closest(".tr-sec")
      if (sec && sec.classList.contains("tr-sec") && !sec.classList.contains("open")) {
        this.js().addClass(sec, "open")
        setTimeout(() => this.save(), 200)
      }
    })
    // A link straight to a section (e.g. /training/1#log) opens it.
    const target = location.hash && document.querySelector(location.hash)
    if (target && target.classList.contains("tr-sec")) this.js().addClass(target, "open")
  },

  save() {
    const ids = [...this.el.querySelectorAll(".tr-sec.open[id]")].map((s) => s.id)
    try { localStorage.setItem(this.key, JSON.stringify(ids)) } catch (e) {}
  },
}

// Photo compare: drag anywhere across the photos (finger or Pencil) to move the divider.
Hooks.CompareSlider = {
  mounted() {
    const range = this.el.querySelector(".cmp-range")
    const set = (pct) => {
      pct = Math.max(0, Math.min(100, pct))
      this.el.style.setProperty("--pos", pct + "%")
      if (range) range.value = pct
    }
    const at = (e) => {
      const r = this.el.getBoundingClientRect()
      set(((e.clientX - r.left) / r.width) * 100)
    }
    this.el.addEventListener("pointerdown", (e) => {
      this.el.setPointerCapture(e.pointerId)
      this.dragging = true
      at(e)
    })
    this.el.addEventListener("pointermove", (e) => { if (this.dragging) at(e) })
    const stop = () => { this.dragging = false }
    this.el.addEventListener("pointerup", stop)
    this.el.addEventListener("pointercancel", stop)
  },
}

// Saved/error notices fade away on their own after a few seconds (or tap to close).
Hooks.Toast = {
  mounted() { this.arm() },
  updated() { this.arm() },
  arm() {
    clearTimeout(this.t)
    this.t = setTimeout(() => this.el.click(), 4000)
  },
  destroyed() { clearTimeout(this.t) },
}

// ── Native-feeling gestures (phone and iPad) ──
// Swipe in from the left edge to go back: uses the page's own back link when there
// is one (‹ Animals, ‹ Training), otherwise the browser history. Only in the
// home-screen app; in Safari itself the browser's own back swipe does this.
;(() => {
  const standalone = window.navigator.standalone || window.matchMedia("(display-mode: standalone)").matches
  if (!standalone) return
  let start = null, arrow = null
  const backLink = () => document.querySelector(".back-btn, .tr-back")
  const sheetOpen = () => document.querySelector(".hm-editor, .pm-editor, .cmp-view, .show.open, .act-sheet[style*='flex'], .dlg-wrap, .lightbox")
  document.addEventListener("touchstart", (e) => {
    const t = e.touches[0]
    if (e.touches.length !== 1 || t.clientX > 24 || sheetOpen()) return
    if (!backLink() && history.length < 2) return
    start = {x: t.clientX, y: t.clientY}
    arrow = arrow || Object.assign(document.body.appendChild(document.createElement("div")), {className: "edge-back", textContent: "‹"})
  }, {passive: true})
  document.addEventListener("touchmove", (e) => {
    if (!start) return
    const t = e.touches[0], dx = t.clientX - start.x, dy = Math.abs(t.clientY - start.y)
    if (dy > 60 && dy > dx) { start = null; arrow.style.opacity = 0; return }
    const p = Math.min(dx / 100, 1)
    arrow.style.opacity = p
    arrow.style.transform = `translateX(${-50 + p * 70}px)`
  }, {passive: true})
  document.addEventListener("touchend", (e) => {
    if (!start) return
    const dx = e.changedTouches[0].clientX - start.x
    start = null
    arrow.style.opacity = 0
    arrow.style.transform = "translateX(-50px)"
    if (dx > 100) {
      const link = backLink()
      if (link) link.click(); else history.back()
    }
  }, {passive: true})
})()

// Swipe a sheet down by its top edge to close it (the ⋯ actions, the More tabs, forms).
;(() => {
  let drag = null
  const closer = (sheet) =>
    sheet.querySelector(".act-row.cancel, .dlg-header .btn-icon, [aria-label='Close']") ||
    document.querySelector(".more-sheet-backdrop.open, #actions-backdrop")
  document.addEventListener("touchstart", (e) => {
    const grip = e.target.closest(".act-handle, .act-title, .more-sheet-handle, .dlg-header")
    if (!grip || e.touches.length !== 1) return
    const sheet = grip.closest(".act-sheet, .more-sheet, .dlg")
    if (!sheet) return
    drag = {sheet, y: e.touches[0].clientY, dy: 0}
    sheet.style.transition = "none"
  }, {passive: true})
  document.addEventListener("touchmove", (e) => {
    if (!drag) return
    drag.dy = Math.max(0, e.touches[0].clientY - drag.y)
    drag.sheet.style.transform = `translateY(${drag.dy}px)`
  }, {passive: true})
  document.addEventListener("touchend", () => {
    if (!drag) return
    const {sheet, dy} = drag
    drag = null
    sheet.style.transition = "transform .18s ease-out"
    if (dy > 110) {
      const c = closer(sheet)
      sheet.style.transform = "translateY(100%)"
      setTimeout(() => { if (c) c.click(); sheet.style.transform = ""; sheet.style.transition = "" }, 160)
    } else {
      sheet.style.transform = ""
    }
  }, {passive: true})
})()

// Notifications page: works out whether this device can get notifications, and turns
// them on or off (asks permission, then subscribes with the app's key).
Hooks.PushSetup = {
  async mounted() {
    this.el.addEventListener("click", (e) => {
      const b = e.target.closest("[data-push]")
      if (b) b.dataset.push === "on" ? this.turnOn(b) : this.turnOff(b)
    })
    this.report()
  },

  async report() {
    const ios = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
    const standalone = window.navigator.standalone || window.matchMedia("(display-mode: standalone)").matches
    // iPhone and iPad: only the Home Screen app can have notifications. In a Safari
    // tab they always look blocked, so say how to fix that instead.
    if (ios && !standalone) return this.pushEvent("push_status", {state: "needs_home_screen"})
    if (!("serviceWorker" in navigator) || !("PushManager" in window) || !("Notification" in window)) {
      return this.pushEvent("push_status", {state: "unsupported"})
    }
    if (Notification.permission === "denied") return this.pushEvent("push_status", {state: "denied"})
    const reg = await navigator.serviceWorker.ready
    const sub = await reg.pushManager.getSubscription()
    this.pushEvent("push_status", sub ? {state: "on", endpoint: sub.endpoint} : {state: "off"})
  },

  async turnOn(btn) {
    btn.disabled = true
    try {
      const perm = await Notification.requestPermission()
      if (perm !== "granted") return this.pushEvent("push_status", {state: perm === "denied" ? "denied" : "off"})
      const reg = await navigator.serviceWorker.ready
      const key = this.el.dataset.key.replace(/-/g, "+").replace(/_/g, "/")
      const raw = Uint8Array.from(atob(key + "=".repeat((4 - key.length % 4) % 4)), (c) => c.charCodeAt(0))
      const sub = await reg.pushManager.subscribe({userVisibleOnly: true, applicationServerKey: raw})
      const device = /iPad/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1) ? "iPad"
        : /iPhone/.test(navigator.userAgent) ? "iPhone" : /Mac/.test(navigator.userAgent) ? "Mac" : "Computer"
      this.pushEvent("push_subscribed", {...sub.toJSON(), device})
    } catch (e) {
      btn.disabled = false
      alert("Couldn't turn on notifications: " + e.message)
    }
  },

  async turnOff(btn) {
    btn.disabled = true
    const reg = await navigator.serviceWorker.ready
    const sub = await reg.pushManager.getSubscription()
    if (sub) {
      const endpoint = sub.endpoint
      await sub.unsubscribe()
      this.pushEvent("push_unsubscribed", {endpoint})
    } else {
      this.pushEvent("push_status", {state: "off"})
    }
  },
}

Hooks.SaveOffline = {
  mounted() {
    this.updateLabel()
    this.el.addEventListener("click", () => this.toggle())
    this.refreshHandler = () => this.updateLabel()
    window.addEventListener("gimel:offline-docs-updated", this.refreshHandler)
  },

  updated() {
    this.updateLabel()
  },

  destroyed() {
    window.removeEventListener("gimel:offline-docs-updated", this.refreshHandler)
  },

  updateLabel() {
    const saved = isDocSaved(this.el.dataset.url)
    this.el.textContent = saved ? "✓ Offline" : "Save Offline"
    this.el.classList.toggle("is-offline-saved", saved)
  },

  async toggle() {
    const {url, animalName, animalId} = this.el.dataset
    const meta = JSON.parse(this.el.dataset.meta || "{}")

    if (isDocSaved(url)) {
      saveOfflineDocs(loadOfflineDocs().filter((d) => d.url !== url))
      setRemoved(url, true)
      await uncacheDoc(url).catch(() => {})
      this.updateLabel()
      window.dispatchEvent(new Event("gimel:offline-docs-updated"))
      return
    }

    this.el.textContent = "Saving…"
    try {
      await cacheDoc(url)
      saveOfflineDocs([...loadOfflineDocs().filter((d) => d.url !== url), offlineEntry(meta, animalId, animalName, false)])
      setRemoved(url, false)
    } catch (e) {
      console.error("Failed to save document offline", e)
    }
    this.updateLabel()
    window.dispatchEvent(new Event("gimel:offline-docs-updated"))
  },
}

Hooks.SaveAllOffline = {
  mounted() {
    this.el.addEventListener("click", () => this.saveAll())
  },

  async saveAll() {
    const docs = JSON.parse(this.el.dataset.docs || "[]")
    const {animalId, animalName} = this.el.dataset
    this.el.textContent = `Saving 0/${docs.length}…`
    let done = 0

    for (const meta of docs) {
      try {
        await cacheDoc(meta.url)
        saveOfflineDocs([...loadOfflineDocs().filter((d) => d.url !== meta.url), offlineEntry(meta, animalId, animalName, false)])
        setRemoved(meta.url, false)
      } catch (e) {
        console.error("Failed to save document offline", meta.url, e)
      }
      done += 1
      this.el.textContent = `Saving ${done}/${docs.length}…`
    }

    this.el.textContent = "✓ All Saved Offline"
    window.dispatchEvent(new CustomEvent("gimel:offline-docs-updated"))
  },
}

// TrAIner answers as a swipeable deck of cards. Opens on the newest card, and jumps to
// the newest again whenever a new answer (or the "checking his log" card) arrives.
Hooks.CoachDeck = {
  mounted() {
    this.track = () => this.el.querySelector(".tr-deck-track")
    this.cards = () => Array.from(this.el.querySelectorAll(".tr-qa"))
    this.index = () => {
      const t = this.track()
      return t && t.clientWidth ? Math.round(t.scrollLeft / (t.clientWidth - 24)) : 0
    }
    this.go = (i, smooth) => {
      // Each card is the track's width less its 18px side padding, plus a 12px gap.
      const t = this.track(), n = this.cards().length
      if (t && n) t.scrollTo({left: Math.max(0, Math.min(n - 1, i)) * (t.clientWidth - 24), behavior: smooth ? "smooth" : "auto"})
    }
    this.sync = () => {
      const n = this.cards().length
      const i = Math.max(0, Math.min(n - 1, this.index()))
      // The track is as tall as the card being read, not the longest card.
      const card = this.cards()[i]
      if (card) this.track().style.height = `${card.offsetHeight + 8}px`
      this.el.querySelectorAll(".tr-deck-dots i").forEach((d, j) => d.classList.toggle("on", j === i))
      const count = this.el.querySelector("[data-deck=count]")
      if (count) count.textContent = `${i + 1} of ${n}`
      const prev = this.el.querySelector("[data-deck=prev]")
      const next = this.el.querySelector("[data-deck=next]")
      if (prev) prev.disabled = i === 0
      if (next) next.disabled = i === n - 1
    }
    this.onScroll = () => { cancelAnimationFrame(this.raf); this.raf = requestAnimationFrame(this.sync) }
    this.onClick = e => {
      const dir = e.target.closest("[data-deck]")?.dataset.deck
      if (dir === "prev") this.go(this.index() - 1, true)
      if (dir === "next") this.go(this.index() + 1, true)
    }
    this.el.addEventListener("click", this.onClick)
    this.track().addEventListener("scroll", this.onScroll, {passive: true})
    this.sig = () => this.cards().map(c => c.id).join(",")
    this.seen = this.sig()
    this.go(this.cards().length - 1, false)
    this.sync()
  },
  updated() {
    this.track().removeEventListener("scroll", this.onScroll)
    this.track().addEventListener("scroll", this.onScroll, {passive: true})
    // A new answer, or a different conversation opened: show its newest card.
    if (this.sig() !== this.seen) { this.seen = this.sig(); this.go(this.cards().length - 1, true) }
    this.sync()
  },
  destroyed() { this.el.removeEventListener("click", this.onClick) },
}

// Session timer: tap to start, tap to stop, and the minutes box fills itself in. The start
// time is kept on the phone, so it keeps counting through a locked screen or a reload.
// Saving the form while it's running stops it and uses the time so far.
Hooks.SessionTimer = {
  mounted() {
    this.key = this.el.dataset.key
    this.label = this.el.querySelector("[data-timer-label]")
    this.form = this.el.closest("form")
    this.onClick = () => (this.started() ? this.stop() : this.start())
    this.onSubmit = () => { if (this.started()) this.stop() }
    this.el.addEventListener("click", this.onClick)
    // Capture phase, so the minutes are in place before LiveView reads the form.
    this.form?.addEventListener("submit", this.onSubmit, true)
    this.render()
    this.tick = setInterval(() => this.render(), 1000)
  },
  destroyed() {
    clearInterval(this.tick)
    this.form?.removeEventListener("submit", this.onSubmit, true)
  },
  started() {
    try { return Number(localStorage.getItem(this.key)) || null } catch (_) { return this.memory || null }
  },
  start() {
    const now = Date.now()
    this.memory = now
    try { localStorage.setItem(this.key, String(now)) } catch (_) {}
    this.render()
  },
  stop() {
    const began = this.started()
    this.memory = null
    try { localStorage.removeItem(this.key) } catch (_) {}
    if (began) {
      const minutes = Math.max(1, Math.round((Date.now() - began) / 60000))
      const input = this.form?.querySelector("input[name='session[minutes_typed]']")
      if (input) {
        input.value = String(minutes)
        input.dispatchEvent(new Event("input", {bubbles: true}))
      }
      this.label.textContent = `Timed ${minutes} min · start again`
      this.el.classList.remove("running")
      return
    }
    this.render()
  },
  render() {
    const began = this.started()
    this.el.classList.toggle("running", !!began)
    if (!began) {
      if (!this.label.textContent.startsWith("Timed")) this.label.textContent = "Start a timer"
      return
    }
    const s = Math.floor((Date.now() - began) / 1000)
    const mm = String(Math.floor(s / 60)).padStart(2, "0")
    const ss = String(s % 60).padStart(2, "0")
    this.label.textContent = `${mm}:${ss} · tap to stop`
  },
}

// Scan vet paperwork: photos are shrunk on the phone first (a 12 MP iPhone photo, HEIC
// included, becomes a ~1 MB JPEG the AI can read), PDFs go up as they are.
Hooks.ScanPick = {
  mounted() {
    this.input = () => this.el.querySelector("[data-scan-input]")
    this.onChange = async () => {
      const file = this.input()?.files?.[0]
      if (!file) return
      try {
        const ready = file.type === "application/pdf" ? file : await shrinkImage(file, 2000, 0.85)
        this.upload("scan", [ready])
      } catch (_) {
        this.upload("scan", [file])
      }
      this.input().value = ""
    }
    this.el.addEventListener("change", this.onChange)
  },
  destroyed() { this.el.removeEventListener("change", this.onChange) },
}

function shrinkImage(file, maxSide, quality) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      const scale = Math.min(1, maxSide / Math.max(img.naturalWidth, img.naturalHeight))
      const canvas = document.createElement("canvas")
      canvas.width = Math.round(img.naturalWidth * scale)
      canvas.height = Math.round(img.naturalHeight * scale)
      canvas.getContext("2d").drawImage(img, 0, 0, canvas.width, canvas.height)
      URL.revokeObjectURL(url)
      canvas.toBlob(blob => {
        if (!blob) return reject(new Error("no blob"))
        const name = (file.name || "scan").replace(/\.[^.]+$/, "") + ".jpg"
        resolve(new File([blob], name, {type: "image/jpeg"}))
      }, "image/jpeg", quality)
    }
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error("can't read image")) }
    img.src = url
  })
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken, tz_offset: new Date().getTimezoneOffset()},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
// Moving to another page inside the app (no full reload) closes an open document.
window.addEventListener("phx:page-loading-start", info => {
  topbar.show(300)
  if (info.detail && info.detail.kind === "redirect") { try { closeDoc() } catch (e) {} }
})
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// Light/dark switch in the top bar.
// Share text (iOS share sheet: Messages, Mail…), or copy it where sharing isn't offered:
// JS.dispatch("ranch:share", detail: {from: "#id", title: "…"}).
window.addEventListener("ranch:share", async e => {
  const src = document.querySelector(e.detail.from)
  if (!src) return
  const text = src.innerText.trim()
  const btn = e.target
  try {
    if (navigator.share) {
      await navigator.share({title: e.detail.title || "", text})
      return
    }
    await navigator.clipboard.writeText(text)
    const label = btn.innerHTML
    btn.textContent = "Copied"
    setTimeout(() => btn.innerHTML = label, 1500)
  } catch (err) {
    // Share sheet closed without sending: nothing to do.
  }
})

// Copy a field's text (Siri setup page): JS.dispatch("ranch:copy", detail: {from: "#id"}).
window.addEventListener("ranch:copy", e => {
  const src = document.querySelector(e.detail.from)
  const btn = e.target
  if (!src) return
  const text = src.value || src.textContent.trim()
  const done = () => { const t = btn.textContent; btn.textContent = "Copied"; setTimeout(() => btn.textContent = t, 1500) }
  if (navigator.clipboard) {
    navigator.clipboard.writeText(text).then(done, () => { src.select && src.select(); document.execCommand("copy"); done() })
  } else { src.select && src.select(); document.execCommand("copy"); done() }
})

window.addEventListener("ranch:toggle-theme", () => {
  const next = document.documentElement.getAttribute("data-theme") === "dark" ? "light" : "dark"
  document.documentElement.setAttribute("data-theme", next)
  try { localStorage.setItem("phx:theme", next) } catch (_) {}
})

// Keep pages alive on iPhone. Safari (and the home-screen app) can bring back a page
// from memory with its live connection gone, so taps do nothing until the app is
// closed. Reload a page restored that way, reconnect when the app comes back to the
// front, and show a small note while the connection is down.
const isLivePage = () => !!document.querySelector("[data-phx-session]")

window.addEventListener("pageshow", e => {
  if (e.persisted && isLivePage()) window.location.reload()
})

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState !== "visible" || !isLivePage() || liveSocket.isConnected()) return
  liveSocket.connect()
  setTimeout(() => {
    if (!liveSocket.isConnected() && navigator.onLine !== false) window.location.reload()
  }, 4000)
})

let downSince = null
const note = document.createElement("button")
note.type = "button"
note.textContent = "Reconnecting… tap to reload"
note.setAttribute("style", "position:fixed;left:50%;transform:translateX(-50%);top:calc(60px + env(safe-area-inset-top));z-index:1000;display:none;padding:10px 16px;border-radius:20px;border:none;background:#111827;color:#fff;font:600 14px -apple-system,system-ui,sans-serif;box-shadow:0 6px 20px rgba(0,0,0,.25)")
note.addEventListener("click", () => window.location.reload())
if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", () => document.body.appendChild(note))
else document.body.appendChild(note)
setInterval(() => {
  if (!isLivePage() || document.visibilityState !== "visible" || liveSocket.isConnected()) {
    downSince = null
    note.style.display = "none"
    return
  }
  downSince = downSince || Date.now()
  if (Date.now() - downSince > 2500) {
    note.textContent = navigator.onLine === false ? "No signal. Will reconnect." : "Reconnecting… tap to reload"
    note.style.display = "block"
  }
}, 1000)

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}


// Tapping anywhere outside an open ⋯ menu closes it.
document.addEventListener("click", (e) => {
  document.querySelectorAll("details.more-menu[open]").forEach((d) => { if (!d.contains(e.target)) d.open = false })
})
