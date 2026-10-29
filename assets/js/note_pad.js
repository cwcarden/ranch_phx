// Handwritten note pages (see RanchPhxWeb.NotesLive.Index).
//
// A ruled page you write on with the Apple Pencil (or a finger). Once the Pencil has
// touched the page, fingers scroll instead of drawing, so a resting hand leaves no
// marks. Pens, a highlighter, an eraser that takes out whole strokes, undo and redo.
// The strokes are saved with the page, so it can be opened and written on again.

const W = 1200, H = 1600, TOP = 150, GAP = 56, MARGIN = 110
const PENS = [
  {key: "black", color: "#111827", label: "Black"},
  {key: "blue", color: "#1d4ed8", label: "Blue"},
  {key: "red", color: "#dc2626", label: "Red"},
  {key: "green", color: "#15803d", label: "Green"},
  {key: "hi", color: "#facc15", label: "Highlighter", hi: true},
]

const CSS = `
.np-editor { position: fixed; inset: 0; z-index: 420; background: #e5e7eb; display: flex; flex-direction: column; }
.np-bar { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; padding: 10px 12px; background: #fff; border-bottom: 1px solid #d1d5db; color: #111827; }
.np-bar input, .np-bar select { min-height: 44px; border-radius: 10px; border: 1.5px solid #d1d5db; background: #f9fafb; padding: 0 10px; font: inherit; font-size: 16px; color: #111827; }
.np-bar input[type=text] { flex: 1; min-width: 140px; }
.np-btn { min-height: 44px; padding: 0 14px; border-radius: 10px; border: 1.5px solid #d1d5db; background: #fff; color: #111827; font: inherit; font-size: 15px; font-weight: 700; cursor: pointer; }
.np-btn.go { background: #0f766e; border-color: #0f766e; color: #fff; }
.np-btn:disabled { opacity: .45; }
.np-tools { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; padding: 8px 12px; background: #f9fafb; border-bottom: 1px solid #d1d5db; }
.np-pen { width: 44px; height: 44px; border-radius: 50%; border: 3px solid transparent; cursor: pointer; padding: 0; display: inline-flex; align-items: center; justify-content: center; background: #fff; }
.np-pen i { width: 24px; height: 24px; border-radius: 50%; display: block; }
.np-pen.on { border-color: #0f766e; }
.np-sep { width: 1px; height: 30px; background: #d1d5db; margin: 0 4px; }
.np-hint { font-size: 13px; color: #6b7280; margin-left: auto; }
.np-stage { flex: 1; overflow-y: auto; -webkit-overflow-scrolling: touch; padding: 14px 0 40px; }
.np-stage canvas { display: block; margin: 0 auto; background: #fff; box-shadow: 0 2px 14px rgba(0,0,0,.18); border-radius: 4px; touch-action: none; }
.np-stage.pencil canvas { touch-action: pan-y; }
.np-msg { padding: 8px 12px; color: #b91c1c; font-weight: 700; background: #fff; }
`

// The page's ruled lines and margin.
function paper(c, s) {
  c.fillStyle = "#fffdf7"
  c.fillRect(0, 0, W * s, H * s)
  c.strokeStyle = "#bfdbfe"
  c.lineWidth = Math.max(1, 1.5 * s)
  for (let y = TOP; y < H - 40; y += GAP) { c.beginPath(); c.moveTo(0, y * s); c.lineTo(W * s, y * s); c.stroke() }
  c.strokeStyle = "#fecaca"
  c.beginPath(); c.moveTo(MARGIN * s, 0); c.lineTo(MARGIN * s, H * s); c.stroke()
}

// One stroke: pens get width from Pencil pressure; the highlighter is one even,
// see-through band.
function drawStroke(c, st, s, from = 1) {
  const p = st.pts
  c.lineCap = "round"; c.lineJoin = "round"
  if (st.hi) {
    c.save(); c.globalAlpha = 0.35; c.strokeStyle = st.color; c.lineWidth = st.w * s
    c.beginPath(); c.moveTo(p[0][0] * s, p[0][1] * s)
    for (let i = 1; i < p.length; i++) c.lineTo(p[i][0] * s, p[i][1] * s)
    c.stroke(); c.restore()
    return
  }
  c.strokeStyle = st.color; c.fillStyle = st.color
  if (p.length === 1) { c.beginPath(); c.arc(p[0][0] * s, p[0][1] * s, st.w * s / 2, 0, Math.PI * 2); c.fill(); return }
  for (let i = Math.max(1, from); i < p.length; i++) {
    const a = p[i - 1], b = p[i]
    c.lineWidth = st.w * s * (0.55 + 0.9 * ((a[2] + b[2]) / 2))
    c.beginPath(); c.moveTo(a[0] * s, a[1] * s); c.lineTo(b[0] * s, b[1] * s); c.stroke()
  }
}

export const NotePad = {
  mounted() {
    this.el.addEventListener("ranch:note-open", (e) => this.open(e.detail || {}))
    this.handleEvent("note-saved", () => this.close())
    this.handleEvent("note-failed", ({message}) => this.failed(message))
    this.onResize = () => this.layout()
  },

  destroyed() { this.close() },

  async open(opts) {
    if (!document.getElementById("np-css")) {
      const st = document.createElement("style"); st.id = "np-css"; st.textContent = CSS; document.head.appendChild(st)
    }
    this.noteId = opts.id || null
    this.strokes = []
    this.redo = []
    this.pen = PENS[0]
    this.bold = false
    this.erasing = false
    this.current = null
    this.pencilSeen = false
    let topics = []
    try { topics = JSON.parse(this.el.dataset.topics || "[]") } catch (e) {}
    const today = new Date(), iso = new Date(today.getTime() - today.getTimezoneOffset() * 60000).toISOString().slice(0, 10)
    const esc = (s) => String(s || "").replace(/[&<>"]/g, (ch) => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"}[ch]))

    const ed = document.createElement("div")
    ed.className = "np-editor"
    ed.innerHTML = `
      <div class="np-bar">
        <button class="np-btn" data-cancel>Cancel</button>
        <input type="date" data-date value="${esc(opts.date || iso)}" max="${iso}" aria-label="Date">
        <select data-topic aria-label="Topic">${topics.map(([v, l]) => `<option value="${esc(v)}" ${v === (opts.topic || "general") ? "selected" : ""}>${esc(l)}</option>`).join("")}</select>
        <input type="text" data-title maxlength="120" placeholder="Title (optional)" value="${esc(opts.title)}">
        <button class="np-btn go" data-save>Save</button>
      </div>
      <div class="np-tools">
        ${PENS.map((p) => `<button class="np-pen" data-pen="${p.key}" aria-label="${p.label}"><i style="background:${p.color}${p.hi ? ";opacity:.6;border-radius:4px" : ""}"></i></button>`).join("")}
        <span class="np-sep"></span>
        <button class="np-btn" data-bold>Fine</button>
        <button class="np-btn" data-eraser>Eraser</button>
        <button class="np-btn" data-undo>Undo</button>
        <button class="np-btn" data-redo>Redo</button>
        <span class="np-hint" data-hint>Write with the Pencil. Fingers scroll once the Pencil's been used.</span>
      </div>
      <div class="np-msg" data-msg hidden></div>
      <div class="np-stage"><canvas></canvas></div>`
    document.body.appendChild(ed)
    document.body.style.overflow = "hidden"
    this.ed = ed
    this.stage = ed.querySelector(".np-stage")
    this.canvas = ed.querySelector("canvas")
    this.ctx = this.canvas.getContext("2d")

    ed.querySelector("[data-cancel]").onclick = () => {
      if (this.strokes.length && this.dirty && !confirm("Leave without saving this page?")) return
      this.close()
    }
    ed.querySelector("[data-save]").onclick = () => this.save()
    ed.querySelectorAll("[data-pen]").forEach((b) => b.onclick = () => { this.pen = PENS.find((p) => p.key === b.dataset.pen); this.erasing = false; this.tools() })
    ed.querySelector("[data-bold]").onclick = () => { this.bold = !this.bold; this.tools() }
    ed.querySelector("[data-eraser]").onclick = () => { this.erasing = !this.erasing; this.tools() }
    ed.querySelector("[data-undo]").onclick = () => { const s = this.strokes.pop(); if (s) { this.redo.push(s); this.dirty = true; this.paint() } this.tools() }
    ed.querySelector("[data-redo]").onclick = () => { const s = this.redo.pop(); if (s) { this.strokes.push(s); this.dirty = true; this.paint() } this.tools() }

    this.canvas.addEventListener("pointerdown", (e) => this.down(e))
    this.canvas.addEventListener("pointermove", (e) => this.move(e))
    this.canvas.addEventListener("pointerup", (e) => this.up(e))
    this.canvas.addEventListener("pointercancel", (e) => this.up(e))
    window.addEventListener("resize", this.onResize)
    this.layout()
    this.tools()

    // Writing on a saved page: bring its strokes back.
    if (opts.strokes_url) {
      try {
        const data = await fetch(opts.strokes_url, {credentials: "same-origin"}).then((r) => r.json())
        if (Array.isArray(data.strokes)) this.strokes = data.strokes.filter((s) => s && Array.isArray(s.pts) && s.pts.length)
      } catch (e) { this.failed("Couldn't open the saved strokes; you can still write on a fresh page.") }
      this.paint()
    }
  },

  close() {
    if (!this.ed) return
    window.removeEventListener("resize", this.onResize)
    this.ed.remove()
    this.ed = null
    document.body.style.overflow = ""
  },

  tools() {
    if (!this.ed) return
    this.ed.querySelectorAll("[data-pen]").forEach((b) => b.classList.toggle("on", !this.erasing && b.dataset.pen === this.pen.key))
    this.ed.querySelector("[data-bold]").textContent = this.bold ? "Bold" : "Fine"
    const er = this.ed.querySelector("[data-eraser]")
    er.classList.toggle("go", this.erasing)
    this.ed.querySelector("[data-undo]").disabled = this.strokes.length === 0
    this.ed.querySelector("[data-redo]").disabled = this.redo.length === 0
    this.stage.classList.toggle("pencil", this.pencilSeen)
  },

  layout() {
    if (!this.ed) return
    const avail = Math.min(this.stage.clientWidth - 24, 1100)
    this.s = avail / W
    const dpr = window.devicePixelRatio || 1
    this.dpr = dpr
    this.canvas.style.width = W * this.s + "px"
    this.canvas.style.height = H * this.s + "px"
    this.canvas.width = Math.round(W * this.s * dpr)
    this.canvas.height = Math.round(H * this.s * dpr)
    this.paint()
  },

  paint() {
    const c = this.ctx
    c.setTransform(this.dpr, 0, 0, this.dpr, 0, 0)
    paper(c, this.s)
    for (const st of this.strokes) drawStroke(c, st, this.s)
    if (this.current) drawStroke(c, this.current, this.s)
  },

  pt(e) {
    const r = this.canvas.getBoundingClientRect()
    const p = e.pointerType === "pen" && e.pressure > 0 ? e.pressure : 0.5
    return [Math.round((e.clientX - r.left) / this.s * 10) / 10, Math.round((e.clientY - r.top) / this.s * 10) / 10, Math.round(p * 100) / 100]
  },

  down(e) {
    if (e.pointerType === "pen" && !this.pencilSeen) { this.pencilSeen = true; this.tools() }
    // With the Pencil in use, a finger or palm scrolls instead of drawing.
    if (e.pointerType === "touch" && this.pencilSeen) return
    e.preventDefault()
    this.canvas.setPointerCapture(e.pointerId)
    this.activeId = e.pointerId
    if (this.erasing) { this.eraseAt(this.pt(e)); return }
    const hi = !!this.pen.hi
    this.current = {color: this.pen.color, hi, w: hi ? 26 : (this.bold ? 7 : 4), pts: [this.pt(e)]}
    this.redo = []
    this.paint()
  },

  move(e) {
    if (e.pointerId !== this.activeId) return
    e.preventDefault()
    const events = e.getCoalescedEvents ? e.getCoalescedEvents() : [e]
    if (this.erasing) { for (const ev of events) this.eraseAt(this.pt(ev)); return }
    if (!this.current) return
    const from = this.current.pts.length
    for (const ev of events) this.current.pts.push(this.pt(ev))
    // Pens draw just the new bit; the see-through highlighter needs the whole band.
    if (this.current.hi) this.paint()
    else { this.ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0); drawStroke(this.ctx, this.current, this.s, from) }
  },

  up(e) {
    if (e.pointerId !== this.activeId) return
    this.activeId = null
    if (this.current) { this.strokes.push(this.current); this.current = null; this.dirty = true }
    this.paint()
    this.tools()
  },

  // Takes out any stroke that passes under the eraser.
  eraseAt([x, y]) {
    const r = 16
    const before = this.strokes.length
    this.strokes = this.strokes.filter((st) => !st.pts.some((p) => Math.abs(p[0] - x) < r && Math.abs(p[1] - y) < r))
    if (this.strokes.length !== before) { this.dirty = true; this.paint(); this.tools() }
  },

  failed(message) {
    if (!this.ed) return
    const m = this.ed.querySelector("[data-msg]")
    m.textContent = message || "Couldn't save. Tap Save to try again."
    m.hidden = false
    const b = this.ed.querySelector("[data-save]")
    b.disabled = false; b.textContent = "Save"
  },

  save() {
    if (!this.strokes.length) { this.failed("Write something first."); return }
    const btn = this.ed.querySelector("[data-save]")
    btn.disabled = true; btn.textContent = "Saving…"
    this.ed.querySelector("[data-msg]").hidden = true

    // The page as a picture, full size, for viewing, reports and the AI to read.
    const out = document.createElement("canvas")
    out.width = W; out.height = H
    const c = out.getContext("2d")
    paper(c, 1)
    for (const st of this.strokes) drawStroke(c, st, 1)
    const meta = {
      id: this.noteId,
      date: this.ed.querySelector("[data-date]").value,
      topic: this.ed.querySelector("[data-topic]").value,
      title: this.ed.querySelector("[data-title]").value,
    }
    const strokes = new File([JSON.stringify({v: 1, w: W, h: H, strokes: this.strokes})], "strokes.json", {type: "application/json"})
    out.toBlob((blob) => {
      const page = new File([blob], "page.png", {type: "image/png"})
      this.pushEvent("note_meta", meta, (reply) => {
        if (reply && reply.ok) this.upload("page", [page, strokes])
        else this.failed(reply && reply.error)
      })
    }, "image/png")
  },
}
