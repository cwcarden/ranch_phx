// Draw on a photo with the Apple Pencil or a finger (see the animal page's photo viewer):
// markings in white, scars and injuries in red, brands in blue. Pencil pressure makes
// the line thicker. Saved as a new photo; the original stays as it was.

const PENS = [
  {key: "white", color: "#ffffff", label: "Markings"},
  {key: "red", color: "#ef4444", label: "Scar / injury"},
  {key: "blue", color: "#3b82f6", label: "Brand"},
  {key: "yellow", color: "#facc15", label: "Note"},
]

const CSS = `
.pm-editor { position: fixed; inset: 0; z-index: 450; background: #0b0f17; display: flex; flex-direction: column; color: #fff; }
.pm-bar { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; padding: max(10px, env(safe-area-inset-top)) 12px 10px; background: #111827; }
.pm-pens { display: flex; gap: 6px; flex-wrap: wrap; flex: 1; }
.pm-pen { display: inline-flex; align-items: center; gap: 6px; min-height: 44px; padding: 0 12px; border-radius: 22px; border: 1.5px solid rgba(255,255,255,.25); background: none; color: #fff; font: inherit; font-size: 14px; font-weight: 700; cursor: pointer; }
.pm-pen i { width: 16px; height: 16px; border-radius: 50%; border: 2px solid rgba(255,255,255,.6); }
.pm-pen.on { background: rgba(255,255,255,.14); border-color: #fff; }
.pm-btn { min-height: 44px; padding: 0 16px; border-radius: 12px; border: 1.5px solid rgba(255,255,255,.25); background: none; color: #fff; font: inherit; font-weight: 700; cursor: pointer; }
.pm-btn:disabled { opacity: .4; }
.pm-btn.go { background: #8b5cf6; border-color: #8b5cf6; }
.pm-stage { position: relative; flex: 1; min-height: 0; }
.pm-stage canvas { position: absolute; inset: 0; width: 100%; height: 100%; touch-action: none; }
.pm-foot { display: flex; gap: 8px; padding: 10px 12px calc(10px + env(safe-area-inset-bottom)); background: #111827; }
.pm-foot input { flex: 1; min-width: 0; min-height: 46px; border-radius: 12px; border: 1.5px solid rgba(255,255,255,.25); background: #0b0f17; color: #fff; padding: 0 12px; font: inherit; }
.pm-hint { font-size: 13px; color: #cbd5e1; padding: 0 12px 8px; background: #111827; }
`

export const PhotoMarkup = {
  mounted() {
    this.el.addEventListener("ranch:markup", (e) => this.open(e.detail.url))
    this.handleEvent("markup-saved", () => this.close())
    this.onResize = () => this.layout()
  },

  destroyed() { this.close() },

  open(url) {
    if (!url) return
    if (!document.getElementById("pm-css")) {
      const style = document.createElement("style")
      style.id = "pm-css"
      style.textContent = CSS
      document.head.appendChild(style)
    }
    this.strokes = []
    this.pen = PENS[0]
    this.current = null

    const ed = document.createElement("div")
    ed.className = "pm-editor"
    ed.innerHTML = `
      <div class="pm-bar">
        <div class="pm-pens">${PENS.map((p) =>
          `<button class="pm-pen" data-pen="${p.key}"><i style="background:${p.color}"></i>${p.label}</button>`).join("")}</div>
        <button class="pm-btn" data-undo>Undo</button>
        <button class="pm-btn" data-cancel>Cancel</button>
      </div>
      <div class="pm-hint">Draw on the photo with the Pencil or a finger. The original photo is kept.</div>
      <div class="pm-stage"><canvas></canvas></div>
      <div class="pm-foot">
        <input type="text" data-caption maxlength="120" placeholder="What is this? e.g. Left side markings">
        <button class="pm-btn go" data-save disabled>Save</button>
      </div>`
    document.body.appendChild(ed)
    document.body.style.overflow = "hidden"
    this.ed = ed
    this.canvas = ed.querySelector("canvas")
    this.ctx = this.canvas.getContext("2d")

    ed.querySelectorAll("[data-pen]").forEach((b) => {
      b.onclick = () => { this.pen = PENS.find((p) => p.key === b.dataset.pen); this.paintPens() }
    })
    ed.querySelector("[data-undo]").onclick = () => { this.strokes.pop(); this.refresh() }
    ed.querySelector("[data-cancel]").onclick = () => this.close()
    ed.querySelector("[data-save]").onclick = () => this.save()
    this.canvas.addEventListener("pointerdown", (e) => this.down(e))
    this.canvas.addEventListener("pointermove", (e) => this.move(e))
    this.canvas.addEventListener("pointerup", (e) => this.up(e))
    this.canvas.addEventListener("pointercancel", (e) => this.up(e))
    window.addEventListener("resize", this.onResize)
    this.paintPens()

    this.img = new Image()
    this.img.onload = () => { this.layout(); this.refresh() }
    this.img.src = url
  },

  close() {
    if (!this.ed) return
    window.removeEventListener("resize", this.onResize)
    this.ed.remove()
    this.ed = null
    document.body.style.overflow = ""
  },

  paintPens() {
    this.ed.querySelectorAll("[data-pen]").forEach((b) => b.classList.toggle("on", b.dataset.pen === this.pen.key))
  },

  layout() {
    if (!this.ed || !this.img.naturalWidth) return
    const r = this.canvas.getBoundingClientRect()
    const dpr = window.devicePixelRatio || 1
    this.canvas.width = Math.round(r.width * dpr)
    this.canvas.height = Math.round(r.height * dpr)
    this.dpr = dpr
    const s = Math.min(r.width / this.img.naturalWidth, r.height / this.img.naturalHeight)
    this.view = {s, ox: (r.width - this.img.naturalWidth * s) / 2, oy: (r.height - this.img.naturalHeight * s) / 2}
    this.refresh()
  },

  refresh() {
    if (!this.view) return
    const c = this.ctx
    c.setTransform(this.dpr, 0, 0, this.dpr, 0, 0)
    c.clearRect(0, 0, this.canvas.width, this.canvas.height)
    c.drawImage(this.img, this.view.ox, this.view.oy, this.img.naturalWidth * this.view.s, this.img.naturalHeight * this.view.s)
    this.paintStrokes(c, (p) => ({x: this.view.ox + p.x * this.view.s, y: this.view.oy + p.y * this.view.s}), this.view.s)
    this.ed.querySelector("[data-save]").disabled = this.strokes.length === 0
  },

  // Each stroke is points in image pixels, with a width per point from Pencil pressure.
  paintStrokes(c, map, scale) {
    for (const st of this.strokes) {
      const pts = st.points.map((p) => ({...map(p), w: p.w * scale}))
      c.lineCap = "round"
      c.lineJoin = "round"
      c.strokeStyle = st.color
      c.globalAlpha = st.key === "yellow" ? 0.55 : 1
      if (pts.length === 1) {
        c.fillStyle = st.color
        c.beginPath(); c.arc(pts[0].x, pts[0].y, pts[0].w / 2, 0, Math.PI * 2); c.fill()
      }
      for (let i = 1; i < pts.length; i++) {
        c.lineWidth = (pts[i - 1].w + pts[i].w) / 2
        c.beginPath(); c.moveTo(pts[i - 1].x, pts[i - 1].y); c.lineTo(pts[i].x, pts[i].y); c.stroke()
      }
      c.globalAlpha = 1
    }
  },

  point(e) {
    const r = this.canvas.getBoundingClientRect()
    const x = (e.clientX - r.left - this.view.ox) / this.view.s
    const y = (e.clientY - r.top - this.view.oy) / this.view.s
    // Line width in image pixels: about 6 screen pixels, thicker with Pencil pressure.
    const base = (this.pen.key === "yellow" ? 18 : 6) / this.view.s
    const pressure = e.pointerType === "pen" && e.pressure > 0 ? 0.5 + e.pressure : 1
    return {x, y, w: base * pressure}
  },

  down(e) {
    if (!this.view) return
    e.preventDefault()
    this.canvas.setPointerCapture(e.pointerId)
    this.current = {key: this.pen.key, color: this.pen.color, points: [this.point(e)], id: e.pointerId}
    this.strokes.push(this.current)
    this.refresh()
  },

  move(e) {
    if (!this.current || e.pointerId !== this.current.id) return
    e.preventDefault()
    const events = e.getCoalescedEvents ? e.getCoalescedEvents() : [e]
    for (const ev of events) this.current.points.push(this.point(ev))
    this.refresh()
  },

  up(e) {
    if (this.current && e.pointerId === this.current.id) this.current = null
  },

  save() {
    if (this.strokes.length === 0) return
    const btn = this.ed.querySelector("[data-save]")
    btn.disabled = true
    btn.textContent = "Saving…"
    const scale = Math.min(1, 2000 / Math.max(this.img.naturalWidth, this.img.naturalHeight))
    const out = document.createElement("canvas")
    out.width = Math.round(this.img.naturalWidth * scale)
    out.height = Math.round(this.img.naturalHeight * scale)
    const c = out.getContext("2d")
    c.drawImage(this.img, 0, 0, out.width, out.height)
    this.paintStrokes(c, (p) => ({x: p.x * scale, y: p.y * scale}), scale)
    const caption = this.ed.querySelector("[data-caption]").value.trim()

    out.toBlob((blob) => {
      const file = new File([blob], "markup.jpg", {type: "image/jpeg"})
      this.pushEvent("markup_meta", {caption}, () => this.upload("markup", [file]))
    }, "image/jpeg", 0.88)
  },
}
