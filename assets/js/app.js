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

const OFFLINE_DOCS_KEY = "gimelRanchOfflineDocs"
const DOCS_CACHE = "ranch-docs-v1"

// Installed as a standalone PWA, there's no browser chrome (no back button,
// no address bar) — navigating straight to a PDF traps the user there with
// no way back. An <iframe> avoids that but iOS Safari's embedded PDF
// renderer only shows page one, so instead render every page ourselves
// (via PDF.js, vendored locally so it still works offline) onto stacked
// canvases inside our own scrollable, closeable overlay.
let pdfjsLibPromise = null
function loadPdfjs() {
  if (!pdfjsLibPromise) {
    pdfjsLibPromise = import("/pdfjs/pdf.min.mjs").then((lib) => {
      lib.GlobalWorkerOptions.workerSrc = "/pdfjs/pdf.worker.min.mjs"
      return lib
    })
  }
  return pdfjsLibPromise
}

// Each getDocument() call spins up a dedicated Worker that stays alive
// until destroyed — track the current one so opening another document
// (or closing this one) frees it instead of leaking workers indefinitely.
let currentPdfDoc = null

async function renderPdfPages(container, url) {
  container.innerHTML = '<p style="color:#fff;text-align:center;padding:40px">Loading…</p>'
  try {
    if (currentPdfDoc) {
      currentPdfDoc.destroy()
      currentPdfDoc = null
    }
    const pdfjsLib = await loadPdfjs()
    // Loading from a fully-cached (often offline) copy, not streaming over a
    // real connection — disable PDF.js's range/streaming fetch strategy so
    // it just does one plain GET. The Cache API doesn't reliably serve
    // partial/range responses from a whole cached Response (inconsistent in
    // Safari especially), which caused intermittent render failures.
    const pdf = await pdfjsLib.getDocument({url, disableRange: true, disableStream: true}).promise
    currentPdfDoc = pdf
    container.innerHTML = ""
    const width = container.clientWidth || window.innerWidth

    for (let i = 1; i <= pdf.numPages; i++) {
      const page = await pdf.getPage(i)
      const viewport = page.getViewport({scale: width / page.getViewport({scale: 1}).width})
      const canvas = document.createElement("canvas")
      canvas.width = viewport.width
      canvas.height = viewport.height
      canvas.style.cssText = "display:block;margin:0 auto 12px;max-width:100%"
      container.appendChild(canvas)
      await page.render({canvasContext: canvas.getContext("2d"), viewport}).promise
    }
  } catch (e) {
    console.error("Failed to render PDF", e)
    container.innerHTML = `<p style="color:#fff;text-align:center;padding:40px">
      Couldn't render this document. <a href="${url}" style="color:#a78bfa">Open it directly</a> instead.
    </p>`
  }
}

window.openPdfViewer = function (event, url, title) {
  event.preventDefault()
  const container = document.getElementById("pdf-viewer-pages")
  const overlay = document.getElementById("pdf-viewer-overlay")
  const titleEl = document.getElementById("pdf-viewer-title")
  if (!container || !overlay) return
  if (titleEl) titleEl.textContent = title || ""
  overlay.style.display = "flex"
  renderPdfPages(container, url)
}

window.closePdfViewer = function () {
  const container = document.getElementById("pdf-viewer-pages")
  const overlay = document.getElementById("pdf-viewer-overlay")
  if (!container || !overlay) return
  overlay.style.display = "none"
  container.innerHTML = ""
  if (currentPdfDoc) {
    currentPdfDoc.destroy()
    currentPdfDoc = null
  }
}

window.addEventListener("keydown", (e) => {
  if (e.key === "Escape") window.closePdfViewer()
})

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

function isDocSaved(url) {
  return loadOfflineDocs().some((d) => d.url === url)
}

const Hooks = {}

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
    const {url, title, docType, animalName, animalId, docId} = this.el.dataset

    if (isDocSaved(url)) {
      saveOfflineDocs(loadOfflineDocs().filter((d) => d.url !== url))
      if ("caches" in window) {
        const cache = await caches.open(DOCS_CACHE)
        await cache.delete(url)
      }
      this.updateLabel()
      return
    }

    this.el.textContent = "Saving…"
    try {
      const res = await fetch(url)
      if ("caches" in window) {
        const cache = await caches.open(DOCS_CACHE)
        await cache.put(url, res.clone())
      }
      const docs = loadOfflineDocs()
      docs.push({id: docId, animalId, animalName, title, docType, url, cachedAt: Date.now()})
      saveOfflineDocs(docs)
    } catch (e) {
      console.error("Failed to save document offline", e)
    }
    this.updateLabel()
  },
}

Hooks.SaveAllOffline = {
  mounted() {
    this.el.addEventListener("click", () => this.saveAll())
  },

  async saveAll() {
    const docs = JSON.parse(this.el.dataset.docs || "[]")
    this.el.textContent = `Saving 0/${docs.length}…`
    let done = 0

    for (const doc of docs) {
      if (!isDocSaved(doc.url)) {
        try {
          const res = await fetch(doc.url)
          if ("caches" in window) {
            const cache = await caches.open(DOCS_CACHE)
            await cache.put(doc.url, res.clone())
          }
          const existing = loadOfflineDocs()
          existing.push({...doc, cachedAt: Date.now()})
          saveOfflineDocs(existing)
        } catch (e) {
          console.error("Failed to save document offline", doc.url, e)
        }
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
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// Light/dark switch in the top bar.
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

