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
// no way back. Open documents in an in-page viewer instead.
window.openPdfViewer = function (event, url, title) {
  event.preventDefault()
  const frame = document.getElementById("pdf-viewer-frame")
  const overlay = document.getElementById("pdf-viewer-overlay")
  const titleEl = document.getElementById("pdf-viewer-title")
  if (!frame || !overlay) return
  frame.src = url
  if (titleEl) titleEl.textContent = title || ""
  overlay.style.display = "flex"
}

window.closePdfViewer = function () {
  const frame = document.getElementById("pdf-viewer-frame")
  const overlay = document.getElementById("pdf-viewer-overlay")
  if (!frame || !overlay) return
  overlay.style.display = "none"
  frame.src = "about:blank"
}

window.addEventListener("keydown", (e) => {
  if (e.key === "Escape") window.closePdfViewer()
})

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
  params: {_csrf_token: csrfToken},
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

