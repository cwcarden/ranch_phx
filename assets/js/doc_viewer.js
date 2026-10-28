// One document viewer for the whole app: PDFs (every page, via the vendored PDF.js),
// photos, and anything else (a Word file, say) offered through the share sheet.
// It always opens over the page with a big Done button below the status bar, and it
// never navigates to the bare file: in the Home Screen app that leaves you stuck,
// with no back button.

let pdfjsPromise = null
let task = null
let viewer = null

function loadPdfjs() {
  if (!pdfjsPromise) {
    pdfjsPromise = import("/pdfjs/pdf.min.mjs").then((lib) => {
      lib.GlobalWorkerOptions.workerSrc = "/pdfjs/pdf.worker.min.mjs"
      return lib
    })
  }
  return pdfjsPromise
}

const CSS = `
.dv { position: fixed; inset: 0; z-index: 2000; display: flex; flex-direction: column; background: #111827; }
.dv-bar { display: flex; align-items: center; gap: 10px; padding: max(10px, env(safe-area-inset-top)) 12px 10px; background: var(--surface, #fff); border-bottom: 1px solid var(--border, #e5e7eb); }
.dv-title { flex: 1; min-width: 0; font-size: 16px; font-weight: 700; color: var(--text, #111); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.dv-btn { flex: none; min-height: 46px; padding: 0 16px; border-radius: 12px; border: 1.5px solid var(--border, #e5e7eb); background: var(--surface, #fff); color: var(--text, #111); font: inherit; font-size: 16px; font-weight: 700; cursor: pointer; }
.dv-btn.done { background: var(--brand, #8b5cf6); border-color: var(--brand, #8b5cf6); color: #fff; }
.dv-body { flex: 1; overflow-y: auto; -webkit-overflow-scrolling: touch; padding: 12px 12px calc(16px + env(safe-area-inset-bottom)); }
.dv-body canvas, .dv-body img { display: block; margin: 0 auto 12px; max-width: 100%; background: #fff; border-radius: 4px; box-shadow: 0 4px 20px rgba(0,0,0,.35); }
.dv-msg { color: #e5e7eb; text-align: center; padding: 48px 20px; font-size: 16px; line-height: 1.5; }
.dv-msg button { margin-top: 14px; }
`

function kind(url, mime) {
  if (/^image\//.test(mime || "") || /\.(jpe?g|png|webp|gif|heic)(\?|#|$)/i.test(url)) return "image"
  if (/pdf/.test(mime || "") || /\.pdf(\?|#|$)/i.test(url)) return "pdf"
  return "other"
}

function stopPdf() {
  if (task) { try { task.destroy() } catch (e) {} task = null }
}

export function closeDoc() {
  stopPdf()
  if (viewer) { viewer.remove(); viewer = null }
  document.body.style.overflow = ""
}

// Hands the file to the iPhone/iPad share sheet (Files, Print, Mail, AirDrop…).
async function shareFile(url, title, btn) {
  try {
    const res = await fetch(url)
    const blob = await res.blob()
    const name = decodeURIComponent(url.split("/").pop().split("?")[0]) || "document"
    const file = new File([blob], name, {type: blob.type || "application/octet-stream"})
    if (navigator.canShare && navigator.canShare({files: [file]})) {
      await navigator.share({files: [file], title: title || name})
    } else {
      const a = Object.assign(document.createElement("a"), {href: URL.createObjectURL(blob), download: name})
      document.body.appendChild(a); a.click(); a.remove()
    }
  } catch (e) {
    if (btn && e.name !== "AbortError") btn.textContent = "Couldn't share it"
  }
}

export function openDoc(url, title, mime) {
  if (!document.getElementById("dv-css")) {
    const style = document.createElement("style")
    style.id = "dv-css"
    style.textContent = CSS
    document.head.appendChild(style)
  }
  closeDoc()

  viewer = document.createElement("div")
  viewer.className = "dv"
  viewer.setAttribute("role", "dialog")
  viewer.innerHTML = `
    <div class="dv-bar">
      <span class="dv-title"></span>
      <button class="dv-btn" data-share>Share</button>
      <button class="dv-btn done" data-done>Done</button>
    </div>
    <div class="dv-body"></div>`
  viewer.querySelector(".dv-title").textContent = title || ""
  viewer.querySelector("[data-done]").onclick = closeDoc
  viewer.querySelector("[data-share]").onclick = (e) => shareFile(url, title, e.currentTarget)
  document.body.appendChild(viewer)
  document.body.style.overflow = "hidden"

  const body = viewer.querySelector(".dv-body")
  const k = kind(url, mime)

  if (k === "image") {
    const img = document.createElement("img")
    img.alt = title || ""
    img.onerror = () => cannotShow(body, url, title)
    img.src = url
    body.appendChild(img)
  } else if (k === "pdf") {
    renderPdf(body, url, title)
  } else {
    cannotShow(body, url, title)
  }
}

function cannotShow(body, url, title) {
  body.innerHTML = `<div class="dv-msg">This kind of file can't be shown inside the app.<br>
    Use <b>Share</b> to open it in Files, print it or send it.<br>
    <button class="dv-btn">Share</button></div>`
  body.querySelector("button").onclick = (e) => shareFile(url, title, e.currentTarget)
}

async function renderPdf(body, url, title) {
  body.innerHTML = `<p class="dv-msg">Loading…</p>`
  try {
    const lib = await loadPdfjs()
    // One plain GET: saved (offline) copies don't reliably answer range requests.
    const t = lib.getDocument({url, disableRange: true, disableStream: true})
    task = t
    const pdf = await t.promise
    if (task !== t) return
    body.innerHTML = ""
    const width = Math.min(body.clientWidth - 24, 1100)
    const ratio = window.devicePixelRatio || 1
    for (let i = 1; i <= pdf.numPages; i++) {
      if (task !== t) return
      const page = await pdf.getPage(i)
      const vp = page.getViewport({scale: (width / page.getViewport({scale: 1}).width) * ratio})
      const canvas = document.createElement("canvas")
      canvas.width = vp.width
      canvas.height = vp.height
      canvas.style.width = vp.width / ratio + "px"
      body.appendChild(canvas)
      await page.render({canvasContext: canvas.getContext("2d"), viewport: vp}).promise
    }
  } catch (e) {
    console.error("Couldn't show the PDF", e)
    if (viewer && viewer.contains(body)) cannotShow(body, url, title)
  }
}

// Escape closes; and in the Home Screen app, any plain link to an uploaded file opens
// here instead of leaving the app on the bare file.
export function installDocViewer() {
  window.openPdfViewer = (event, url, title) => {
    if (event) event.preventDefault()
    openDoc(url, title)
  }
  window.closePdfViewer = closeDoc
  window.addEventListener("keydown", (e) => { if (e.key === "Escape" && viewer) closeDoc() })
  document.addEventListener("click", (e) => {
    const a = e.target.closest("a[href]")
    if (!a || e.defaultPrevented || a.hasAttribute("download") || a.target === "_blank") return
    const url = new URL(a.href, location.href)
    if (url.origin === location.origin && url.pathname.startsWith("/uploads/")) {
      e.preventDefault()
      openDoc(url.pathname, a.title || a.textContent.trim())
    }
  })
}
