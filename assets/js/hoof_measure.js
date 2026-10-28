// Hoof angles from a photo (see RanchPhxWeb.HoofLive.Index).
//
// Take or choose a side photo, then tap two points along the ground, two along the
// toe wall and (optionally) two along the front of the pastern. Dots can be dragged
// to fine-tune, with a magnifier under the finger or Pencil. The angles are worked
// out here; the numbers go to the server first, then the marked-up photo as a JPEG.

const STEPS = [
  {key: "ground", color: "#facc15", label: "Ground",
   say: "Tap the ground under the heel, then the ground at the toe."},
  {key: "wall", color: "#22c55e", label: "Toe wall",
   say: "Tap the toe at the hairline, then where the toe meets the ground."},
  {key: "pastern", color: "#38bdf8", label: "Pastern", optional: true,
   say: "Tap the front of the fetlock, then the front of the pastern at the hairline. Or skip."},
]

const FEET = {LF: "Left front", RF: "Right front", LH: "Left hind", RH: "Right hind"}

function angleBetween(a, b) {
  const ux = a[1].x - a[0].x, uy = a[1].y - a[0].y
  const vx = b[1].x - b[0].x, vy = b[1].y - b[0].y
  const lu = Math.hypot(ux, uy), lv = Math.hypot(vx, vy)
  if (!lu || !lv) return null
  const cos = Math.min(1, Math.abs(ux * vx + uy * vy) / (lu * lv))
  return Math.round(Math.acos(cos) * 1800 / Math.PI) / 10
}

function axisText(toe, pastern) {
  if (toe == null || pastern == null) return ""
  const d = Math.round((pastern - toe) * 10) / 10
  if (Math.abs(d) <= 3) return "Hoof and pastern line up"
  return d > 0 ? `Broken back ${d}°` : `Broken forward ${-d}°`
}

const CSS = `
.hm-editor { position: fixed; inset: 0; z-index: 400; background: #111827; display: flex; flex-direction: column; color: #fff; font-family: inherit; }
.hm-bar { display: flex; align-items: center; gap: 10px; padding: max(10px, env(safe-area-inset-top)) 12px 10px; background: #1f2937; }
.hm-step { flex: 1; min-width: 0; font-size: 15px; line-height: 1.35; }
.hm-step b { display: block; font-size: 17px; }
.hm-step i { font-style: normal; font-weight: 800; }
.hm-btn { min-height: 46px; padding: 0 16px; border-radius: 12px; border: 1.5px solid rgba(255,255,255,.25); background: none; color: #fff; font: inherit; font-size: 15px; font-weight: 700; cursor: pointer; }
.hm-btn:disabled { opacity: .4; }
.hm-btn.go { background: #14b8a6; border-color: #14b8a6; color: #042f2e; }
.hm-stage { position: relative; flex: 1; min-height: 0; }
.hm-stage canvas { position: absolute; inset: 0; width: 100%; height: 100%; touch-action: none; }
.hm-foot { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; padding: 10px 12px calc(10px + env(safe-area-inset-bottom)); background: #1f2937; }
.hm-read { flex: 1; min-width: 220px; font-size: 16px; }
.hm-read b { font-size: 22px; }
.hm-read .ax { display: block; font-size: 14px; font-weight: 700; }
.hm-read .ax.ok { color: #4ade80; } .hm-read .ax.check { color: #fbbf24; }
.hm-foot input[type=date] { min-height: 46px; border-radius: 12px; border: 1.5px solid rgba(255,255,255,.25); background: #111827; color: #fff; padding: 0 10px; font: inherit; }
.hm-foot input[type=text] { min-height: 46px; border-radius: 12px; border: 1.5px solid rgba(255,255,255,.25); background: #111827; color: #fff; padding: 0 12px; font: inherit; flex: 1; min-width: 160px; }
`

export const HoofMeasure = {
  mounted() {
    this.el.querySelectorAll("[data-hoof-photo]").forEach((input) =>
      input.addEventListener("change", () => {
        const file = input.files && input.files[0]
        input.value = ""
        if (file) this.open(file)
      })
    )
    this.handleEvent("hoof-saved", () => this.close())
    this.handleEvent("hoof-failed", ({message}) => this.saveFailed(message))
    this.onResize = () => this.layout()
  },

  destroyed() {
    clearTimeout(this.saveTimer)
    this.close()
  },

  open(file) {
    if (!document.getElementById("hm-css")) {
      const style = document.createElement("style")
      style.id = "hm-css"
      style.textContent = CSS
      document.head.appendChild(style)
    }

    const picker = document.getElementById("foot-picker")
    this.foot = (picker && picker.dataset.foot) || "LF"
    this.points = {ground: [], wall: [], pastern: []}
    this.skipped = false
    this.drag = null

    const today = new Date()
    const iso = new Date(today.getTime() - today.getTimezoneOffset() * 60000).toISOString().slice(0, 10)

    const ed = document.createElement("div")
    ed.className = "hm-editor"
    ed.innerHTML = `
      <div class="hm-bar">
        <div class="hm-step"><b>${FEET[this.foot] || this.foot}</b><span data-say></span></div>
        <button class="hm-btn" data-undo>Undo</button>
        <button class="hm-btn" data-cancel>Cancel</button>
      </div>
      <div class="hm-stage"><canvas></canvas></div>
      <div class="hm-foot">
        <div class="hm-read" data-read></div>
        <input type="date" data-date value="${iso}" max="${iso}" aria-label="Date measured">
        <input type="text" data-note placeholder="Note (optional), e.g. 4 weeks since trim" maxlength="200">
        <button class="hm-btn" data-skip>Skip pastern</button>
        <button class="hm-btn go" data-save disabled>Save</button>
      </div>`
    document.body.appendChild(ed)
    document.body.style.overflow = "hidden"
    this.ed = ed
    this.canvas = ed.querySelector("canvas")
    this.ctx = this.canvas.getContext("2d")

    ed.querySelector("[data-cancel]").onclick = () => this.close()
    ed.querySelector("[data-undo]").onclick = () => this.undo()
    ed.querySelector("[data-skip]").onclick = () => { this.skipped = true; this.points.pastern = []; this.refresh() }
    ed.querySelector("[data-save]").onclick = () => this.save()

    this.canvas.addEventListener("pointerdown", (e) => this.down(e))
    this.canvas.addEventListener("pointermove", (e) => this.move(e))
    this.canvas.addEventListener("pointerup", (e) => this.up(e))
    this.canvas.addEventListener("pointercancel", (e) => this.up(e))
    this.canvas.addEventListener("pointerleave", () => { if (this.hover) { this.hover = null; this.draw() } })
    window.addEventListener("resize", this.onResize)

    this.img = new Image()
    this.img.onload = () => { this.layout(); this.refresh() }
    this.img.onerror = () => { this.say("Couldn't open that photo. Try another.") }
    this.url = URL.createObjectURL(file)
    this.img.src = this.url
  },

  close() {
    clearTimeout(this.saveTimer)
    if (!this.ed) return
    window.removeEventListener("resize", this.onResize)
    this.ed.remove()
    this.ed = null
    document.body.style.overflow = ""
    if (this.url) URL.revokeObjectURL(this.url)
  },

  step() {
    for (const s of STEPS) {
      if (s.optional && this.skipped) continue
      if (this.points[s.key].length < 2) return s
    }
    return null
  },

  say(text) {
    if (this.ed) this.ed.querySelector("[data-say]").innerHTML = text
  },

  angles() {
    const g = this.points.ground, w = this.points.wall, p = this.points.pastern
    const toe = g.length === 2 && w.length === 2 ? angleBetween(g, w) : null
    const pastern = g.length === 2 && p.length === 2 ? angleBetween(g, p) : null
    return {toe, pastern}
  },

  refresh() {
    const s = this.step()
    const n = s ? this.points[s.key].length : 0
    if (s) {
      this.say(`<i style="color:${s.color}">${s.label}${n ? " · 2nd dot" : ""}:</i> ${s.say}`)
    } else {
      this.say("Drag any dot to fine-tune, then Save.")
    }
    const {toe, pastern} = this.angles()
    const ax = axisText(toe, pastern)
    const ok = ax.startsWith("Hoof")
    this.ed.querySelector("[data-read]").innerHTML = toe == null
      ? "Toe angle shows here."
      : `Toe <b>${toe}°</b>${pastern != null ? ` · Pastern <b>${pastern}°</b>` : ""}` +
        (ax ? `<span class="ax ${ok ? "ok" : "check"}">${ax}</span>` : "")
    const skip = this.ed.querySelector("[data-skip]")
    skip.style.display = this.skipped || this.points.pastern.length === 2 ? "none" : ""
    this.ed.querySelector("[data-save]").disabled = toe == null || toe <= 0 || toe >= 90
    this.draw()
  },

  undo() {
    for (const key of ["pastern", "wall", "ground"]) {
      if (key === "pastern" && this.skipped && this.points.pastern.length === 0) { this.skipped = false; return this.refresh() }
      if (this.points[key].length) { this.points[key].pop(); return this.refresh() }
    }
  },

  // ── Drawing ──
  layout() {
    if (!this.ed || !this.img.naturalWidth) return
    const r = this.canvas.getBoundingClientRect()
    const dpr = window.devicePixelRatio || 1
    this.canvas.width = Math.round(r.width * dpr)
    this.canvas.height = Math.round(r.height * dpr)
    this.dpr = dpr
    const s = Math.min(r.width / this.img.naturalWidth, r.height / this.img.naturalHeight)
    this.view = {s, ox: (r.width - this.img.naturalWidth * s) / 2, oy: (r.height - this.img.naturalHeight * s) / 2}
    this.draw()
  },

  toScreen(p) { return {x: this.view.ox + p.x * this.view.s, y: this.view.oy + p.y * this.view.s} },
  toImage(x, y) {
    const p = {x: (x - this.view.ox) / this.view.s, y: (y - this.view.oy) / this.view.s}
    p.x = Math.max(0, Math.min(this.img.naturalWidth, p.x))
    p.y = Math.max(0, Math.min(this.img.naturalHeight, p.y))
    return p
  },

  draw() {
    if (!this.view) return
    const c = this.ctx, dpr = this.dpr
    c.setTransform(dpr, 0, 0, dpr, 0, 0)
    c.clearRect(0, 0, this.canvas.width, this.canvas.height)
    c.drawImage(this.img, this.view.ox, this.view.oy, this.img.naturalWidth * this.view.s, this.img.naturalHeight * this.view.s)
    this.paintMarks(c, (p) => this.toScreen(p), 1)
    if (this.drag && this.drag.at) this.loupe(c, this.drag.at)
    else if (this.hover) this.hoverMark(c, this.hover)
  },

  // Apple Pencil hovering above the screen (Pencil Pro or 2nd gen on newer iPads):
  // show where a dot would land, and the magnifier, before the tip touches.
  hoverMark(c, at) {
    const s = this.step()
    const color = s ? s.color : "#fff"
    c.strokeStyle = "rgba(0,0,0,.6)"; c.lineWidth = 4
    c.beginPath(); c.arc(at.x, at.y, 9, 0, Math.PI * 2); c.stroke()
    c.strokeStyle = color; c.lineWidth = 2
    c.beginPath(); c.arc(at.x, at.y, 9, 0, Math.PI * 2); c.stroke()
    c.beginPath(); c.moveTo(at.x - 16, at.y); c.lineTo(at.x - 5, at.y); c.moveTo(at.x + 5, at.y); c.lineTo(at.x + 16, at.y)
    c.moveTo(at.x, at.y - 16); c.lineTo(at.x, at.y - 5); c.moveTo(at.x, at.y + 5); c.lineTo(at.x, at.y + 16); c.stroke()
    this.loupe(c, at)
  },

  // Lines, dots and the angle labels, in whatever space `map` turns points into.
  paintMarks(c, map, k) {
    const {toe, pastern} = this.angles()
    for (const s of STEPS) {
      const pts = this.points[s.key].map(map)
      c.lineCap = "round"
      if (pts.length === 2) {
        // Extend each line past its dots so it's easy to see along the hoof.
        const dx = pts[1].x - pts[0].x, dy = pts[1].y - pts[0].y
        const ext = s.key === "ground" ? 0.6 : 0.25
        c.strokeStyle = "rgba(0,0,0,.55)"
        c.lineWidth = 6 * k
        c.beginPath(); c.moveTo(pts[0].x - dx * ext, pts[0].y - dy * ext); c.lineTo(pts[1].x + dx * ext, pts[1].y + dy * ext); c.stroke()
        c.strokeStyle = s.color
        c.lineWidth = 3 * k
        c.beginPath(); c.moveTo(pts[0].x - dx * ext, pts[0].y - dy * ext); c.lineTo(pts[1].x + dx * ext, pts[1].y + dy * ext); c.stroke()
        const label = s.key === "wall" ? toe : s.key === "pastern" ? pastern : null
        if (label != null) this.tag(c, `${label}°`, (pts[0].x + pts[1].x) / 2 + 14 * k, (pts[0].y + pts[1].y) / 2, s.color, k)
      }
      for (const p of pts) {
        c.fillStyle = s.color
        c.strokeStyle = "#fff"
        c.lineWidth = 2.5 * k
        c.beginPath(); c.arc(p.x, p.y, 8 * k, 0, Math.PI * 2); c.fill(); c.stroke()
      }
    }
  },

  tag(c, text, x, y, color, k) {
    c.font = `800 ${18 * k}px -apple-system, system-ui, sans-serif`
    const w = c.measureText(text).width + 14 * k, h = 28 * k
    c.fillStyle = "rgba(0,0,0,.7)"
    c.beginPath(); c.roundRect ? c.roundRect(x, y - h / 2, w, h, 8 * k) : c.rect(x, y - h / 2, w, h); c.fill()
    c.fillStyle = color
    c.textBaseline = "middle"
    c.fillText(text, x + 7 * k, y)
  },

  // A magnified circle above the finger, so the dot can be placed exactly.
  loupe(c, at) {
    const R = 64, Z = 2.5
    const r = this.canvas.getBoundingClientRect()
    let cx = at.x, cy = at.y - 110
    if (cy - R < 0) cy = at.y + 110
    cx = Math.max(R + 4, Math.min(r.width - R - 4, cx))
    c.save()
    c.beginPath(); c.arc(cx, cy, R, 0, Math.PI * 2); c.closePath()
    c.fillStyle = "#000"; c.fill()
    c.clip()
    const ip = this.toImage(at.x, at.y)
    const s = this.view.s * Z
    c.drawImage(this.img, cx - ip.x * s, cy - ip.y * s, this.img.naturalWidth * s, this.img.naturalHeight * s)
    this.paintMarks(c, (p) => ({x: cx + (p.x - ip.x) * s, y: cy + (p.y - ip.y) * s}), 1)
    c.restore()
    c.strokeStyle = "#fff"; c.lineWidth = 3
    c.beginPath(); c.arc(cx, cy, R, 0, Math.PI * 2); c.stroke()
    c.strokeStyle = "rgba(255,255,255,.9)"; c.lineWidth = 1
    c.beginPath(); c.moveTo(cx - 12, cy); c.lineTo(cx + 12, cy); c.moveTo(cx, cy - 12); c.lineTo(cx, cy + 12); c.stroke()
  },

  // ── Touch, Pencil and mouse ──
  pos(e) {
    const r = this.canvas.getBoundingClientRect()
    return {x: e.clientX - r.left, y: e.clientY - r.top}
  },

  down(e) {
    if (!this.view) return
    this.hover = null
    e.preventDefault()
    const at = this.pos(e)
    const current = this.step()
    let best = null, bestD = e.pointerType === "pen" ? 22 : 34
    // While a line still needs dots, a tap adds one (the wall's second dot often sits
    // right on the ground's toe dot). Once every line is in, a touch grabs the nearest dot.
    for (const s of current ? [] : STEPS) {
      this.points[s.key].forEach((p, i) => {
        const q = this.toScreen(p)
        const d = Math.hypot(q.x - at.x, q.y - at.y)
        if (d < bestD) { best = {key: s.key, i}; bestD = d }
      })
    }
    if (!best) {
      const s = current
      if (!s) return
      this.points[s.key].push(this.toImage(at.x, at.y))
      best = {key: s.key, i: this.points[s.key].length - 1}
    }
    this.drag = {...best, at, id: e.pointerId}
    this.canvas.setPointerCapture(e.pointerId)
    this.refresh()
  },

  move(e) {
    if (!this.drag && e.pointerType === "pen" && e.buttons === 0 && this.view) {
      this.hover = this.pos(e)
      this.draw()
      return
    }
    if (!this.drag || e.pointerId !== this.drag.id) return
    e.preventDefault()
    const at = this.pos(e)
    this.drag.at = at
    this.points[this.drag.key][this.drag.i] = this.toImage(at.x, at.y)
    this.refresh()
  },

  up(e) {
    if (!this.drag || e.pointerId !== this.drag.id) return
    this.drag = null
    this.refresh()
  },

  // ── Saving ──
  // Puts the Save button back and says why, so it never sits on "Saving…".
  saveFailed(message) {
    clearTimeout(this.saveTimer)
    if (!this.ed) return
    const btn = this.ed.querySelector("[data-save]")
    btn.disabled = false
    btn.textContent = "Save"
    this.say(message || "Couldn't save that. Tap Save to try again.")
  },

  save() {
    const {toe, pastern} = this.angles()
    if (toe == null) return
    const btn = this.ed.querySelector("[data-save]")
    btn.disabled = true
    btn.textContent = "Saving…"
    clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => this.saveFailed("That's taking too long. Check the connection and tap Save again."), 30000)

    // The photo with the lines on it, at most 1600 px across.
    const scale = Math.min(1, 1600 / Math.max(this.img.naturalWidth, this.img.naturalHeight))
    const out = document.createElement("canvas")
    out.width = Math.round(this.img.naturalWidth * scale)
    out.height = Math.round(this.img.naturalHeight * scale)
    const c = out.getContext("2d")
    c.drawImage(this.img, 0, 0, out.width, out.height)
    this.paintMarks(c, (p) => ({x: p.x * scale, y: p.y * scale}), Math.max(1, out.width / 900))

    const round = (p) => ({x: Math.round(p.x), y: Math.round(p.y)})
    const data = {
      foot: this.foot,
      toe, pastern,
      date: this.ed.querySelector("[data-date]").value,
      note: this.ed.querySelector("[data-note]").value,
      points: {
        ground: this.points.ground.map(round),
        wall: this.points.wall.map(round),
        pastern: this.points.pastern.map(round),
        width: this.img.naturalWidth, height: this.img.naturalHeight,
      },
    }

    out.toBlob((blob) => {
      const file = new File([blob], `hoof-${this.foot}.jpg`, {type: "image/jpeg"})
      this.pushEvent("hoof_measured", data, (reply) => {
        if (reply && reply.ok) {
          this.upload("hoof", [file])
        } else {
          this.saveFailed("Couldn't save that. Check the lines and try again.")
        }
      })
    }, "image/jpeg", 0.86)
  },
}
