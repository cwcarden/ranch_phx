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

