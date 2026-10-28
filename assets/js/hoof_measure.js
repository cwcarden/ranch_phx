// Hoof measurements from a photo (see RanchPhxWeb.HoofLive.Index).
//
// Side view: tap two points along the ground, two along the toe wall and (optionally)
// two along the front of the pastern; the toe and pastern angles are worked out.
// Sole view: tap the toe, the two heels, the two sides at the widest part and
// (optionally) the frog tip; the foot's balance is worked out.
// Dots can be dragged to fine-tune, with a magnifier under the finger or Pencil.
// The numbers go to the server first, then the marked-up photo as a JPEG.

const VIEWS = {
  side: {
    title: "side",
    steps: [
      {key: "ground", n: 2, color: "#facc15", label: "Ground",
       say: "Tap the ground under the heel, then the ground at the toe.",
       why: "The level the foot stands on. Every angle is measured from it."},
      {key: "wall", n: 2, color: "#22c55e", label: "Toe wall",
       say: "Tap the toe at the hairline, then where the toe meets the ground.",
       why: "The front of the hoof wall. Its angle to the ground is the toe angle."},
      {key: "pastern", n: 2, color: "#38bdf8", label: "Pastern", optional: true,
       say: "Tap the front of the fetlock, then the front of the pastern at the hairline. Or skip.",
       why: "The front of the pastern. It should run parallel to the toe wall (one straight line)."},
    ],
    correct: [
      "Toe angle: usually about 48–55° in front, 50–57° behind. The best angle is the one that matches his pastern.",
      "Hoof-pastern axis: pastern and toe wall make one straight line, within about 3°.",
      "Pairs: left and right within about 2° of each other.",
    ],
  },
  sole: {
    title: "sole",
    steps: [
      {key: "toe", n: 1, color: "#f472b6", label: "Toe",
       say: "Tap the center of the toe, on the outer edge of the wall.",
       why: "The front end of the foot's center line."},
      {key: "heels", n: 2, color: "#facc15", label: "Heels",
       say: "Tap the end of each heel, where the wall turns in (the heel buttresses).",
       why: "The back of the foot. The center line runs from the toe to the middle of the two heels, down the frog."},
      {key: "widest", n: 2, color: "#22c55e", label: "Widest part",
       say: "Tap the outer wall on each side at the widest part of the foot.",
       why: "Straight across at the widest point. It should sit about halfway between toe and heels."},
      {key: "frog", n: 1, color: "#38bdf8", label: "Frog tip", optional: true,
       say: "Tap the point of the frog. Or skip.",
       why: "The frog's tip should sit right on the center line."},
    ],
    correct: [
      "Toe/heel: the widest part about halfway, so close to 50/50.",
      "Sides: the center line splits the widest part into near-equal halves (within about 4%).",
      "Heels: level with each other, square across the center line (within about 3°).",
      "Frog: tip on the center line.",
    ],
  },
}

const TOE_RANGE = {front: [48, 55], hind: [50, 57]}

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

function toeNote(foot, toe) {
  if (toe == null) return null
  const [lo, hi] = TOE_RANGE[foot === "LF" || foot === "RF" ? "front" : "hind"]
  if (toe < lo) return {ok: false, text: `Low for this foot (usual ${lo}–${hi}°)`}
  if (toe > hi) return {ok: false, text: `Steep for this foot (usual ${lo}–${hi}°)`}
  return {ok: true, text: `In the usual range (${lo}–${hi}°)`}
}

const r1 = (n) => Math.round(n * 10) / 10

// Balance of the sole from its landmarks (image pixels). Null until the toe, heels
// and widest part are all in.
function soleNumbers(pts) {
  if (pts.toe.length < 1 || pts.heels.length < 2 || pts.widest.length < 2) return null
  const T = pts.toe[0], [H1, H2] = pts.heels, [W1, W2] = pts.widest
  const Hm = {x: (H1.x + H2.x) / 2, y: (H1.y + H2.y) / 2}
  const v = {x: T.x - Hm.x, y: T.y - Hm.y}, L = Math.hypot(v.x, v.y)
  const w = {x: W2.x - W1.x, y: W2.y - W1.y}, W = Math.hypot(w.x, w.y)
  if (L < 5 || W < 5) return null
  // Where the widest line crosses the center line: Hm + t·v = W1 + s·w.
  const den = v.x * w.y - v.y * w.x
  if (Math.abs(den) < 1e-6) return null
  const t = ((W1.x - Hm.x) * w.y - (W1.y - Hm.y) * w.x) / den
  const sP = ((W1.x - Hm.x) * v.y - (W1.y - Hm.y) * v.x) / den
  const X = {x: Hm.x + t * v.x, y: Hm.y + t * v.y}
  const u = {x: v.x / L, y: v.y / L}, n = {x: -u.y, y: u.x}
  const h = {x: H2.x - H1.x, y: H2.y - H1.y}, hl = Math.hypot(h.x, h.y)
  const heels = hl ? Math.acos(Math.min(1, Math.abs(h.x * n.x + h.y * n.y) / hl)) * 180 / Math.PI : null
  const F = pts.frog[0]
  const frog = F ? Math.abs((F.x - Hm.x) * n.x + (F.y - Hm.y) * n.y) / W * 100 : null
  const side = Math.min(1, Math.max(0, sP))
  return {
    toeShare: r1(Math.min(100, Math.max(0, (1 - t) * 100))),
    sides: r1(Math.max(side, 1 - side) * 100),
    heels: heels == null ? null : r1(heels),
    frog: frog == null ? null : r1(frog),
    ratio: Math.round(W / L * 100) / 100,
    X, Hm,
  }
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
.hm-help { position: absolute; inset: 0; z-index: 5; overflow-y: auto; background: rgba(17,24,39,.96); padding: 18px 18px calc(18px + env(safe-area-inset-bottom)); font-size: 16px; line-height: 1.45; }
.hm-help h3 { margin: 0 0 10px; font-size: 19px; }
.hm-help h4 { margin: 18px 0 6px; font-size: 13px; text-transform: uppercase; letter-spacing: .06em; color: #94a3b8; }
.hm-help ol { margin: 0; padding-left: 0; list-style: none; display: grid; gap: 10px; }
.hm-help ol li { display: grid; grid-template-columns: 16px 1fr; gap: 10px; align-items: start; }
.hm-help ol li i { width: 16px; height: 16px; border-radius: 50%; margin-top: 3px; border: 2px solid #fff; }
.hm-help ol li small { display: block; color: #cbd5e1; font-size: 14px; }
.hm-help ul { margin: 0; padding-left: 20px; color: #e2e8f0; display: grid; gap: 6px; }
.hm-help .hm-btn { margin-top: 18px; }
.hm-help svg { display: block; max-width: 320px; margin: 4px 0 6px; }
.hm-q { width: 46px; padding: 0; font-size: 20px; }
.hm-read .ln { display: block; font-size: 14px; font-weight: 700; }
.hm-read .ln.ok { color: #4ade80; } .hm-read .ln.check { color: #fbbf24; }
.hm-foot input[type=text] { min-height: 46px; border-radius: 12px; border: 1.5px solid rgba(255,255,255,.25); background: #111827; color: #fff; padding: 0 12px; font: inherit; flex: 1; min-width: 160px; }
`

// Small sketches for the helper: where the dots go.
const SIDE_SVG = `<svg viewBox="0 0 300 150" aria-hidden="true">
  <path d="M120 20 L150 20 L178 64 L240 128 L96 128 L104 74 Z" fill="#334155" stroke="#94a3b8" stroke-width="2"/>
  <line x1="40" y1="128" x2="270" y2="128" stroke="#facc15" stroke-width="3"/>
  <line x1="178" y1="64" x2="240" y2="128" stroke="#22c55e" stroke-width="3"/>
  <line x1="150" y1="20" x2="178" y2="64" stroke="#38bdf8" stroke-width="3"/>
  <circle cx="100" cy="128" r="6" fill="#facc15"/><circle cx="240" cy="128" r="6" fill="#facc15"/>
  <circle cx="178" cy="64" r="6" fill="#22c55e"/><circle cx="236" cy="124" r="6" fill="#22c55e"/>
  <circle cx="150" cy="20" r="6" fill="#38bdf8"/><circle cx="176" cy="60" r="6" fill="#38bdf8"/>
  <text x="196" y="96" fill="#fff" font-size="14" font-weight="700">toe angle</text>
</svg>`

const SOLE_SVG = `<svg viewBox="0 0 300 200" aria-hidden="true">
  <path d="M150 12 C222 12 252 80 246 128 C242 160 222 182 206 186 L184 160 C172 150 128 150 116 160 L94 186 C78 182 58 160 54 128 C48 80 78 12 150 12 Z" fill="#334155" stroke="#94a3b8" stroke-width="2"/>
  <path d="M150 70 L176 160 L124 160 Z" fill="#475569"/>
  <line x1="150" y1="12" x2="150" y2="178" stroke="#f472b6" stroke-width="3" stroke-dasharray="8 6"/>
  <line x1="58" y1="104" x2="242" y2="104" stroke="#22c55e" stroke-width="3"/>
  <line x1="98" y1="178" x2="202" y2="178" stroke="#facc15" stroke-width="3"/>
  <circle cx="150" cy="14" r="6" fill="#f472b6"/>
  <circle cx="98" cy="178" r="6" fill="#facc15"/><circle cx="202" cy="178" r="6" fill="#facc15"/>
  <circle cx="58" cy="104" r="6" fill="#22c55e"/><circle cx="242" cy="104" r="6" fill="#22c55e"/>
  <circle cx="150" cy="72" r="6" fill="#38bdf8"/>
</svg>`

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
    this.mode = picker && VIEWS[picker.dataset.view] ? picker.dataset.view : "side"
    this.def = VIEWS[this.mode]
    this.steps = this.def.steps
    this.points = Object.fromEntries(this.steps.map((st) => [st.key, []]))
    this.skipped = false
    this.drag = null
    const optional = this.steps.find((st) => st.optional)

    const today = new Date()
    const iso = new Date(today.getTime() - today.getTimezoneOffset() * 60000).toISOString().slice(0, 10)

    const ed = document.createElement("div")
    ed.className = "hm-editor"
    ed.innerHTML = `
      <div class="hm-bar">
        <div class="hm-step"><b>${FEET[this.foot] || this.foot}${this.mode === "sole" ? " · sole" : ""}</b><span data-say></span></div>
        <button class="hm-btn hm-q" data-help aria-label="What are these lines?">?</button>
        <button class="hm-btn" data-undo>Undo</button>
        <button class="hm-btn" data-cancel>Cancel</button>
      </div>
      <div class="hm-stage"><canvas></canvas><div class="hm-help" data-helppanel hidden></div></div>
      <div class="hm-foot">
        <div class="hm-read" data-read></div>
        <input type="date" data-date value="${iso}" max="${iso}" aria-label="Date measured">
        <input type="text" data-note placeholder="Note (optional), e.g. 4 weeks since trim" maxlength="200">
        <button class="hm-btn" data-skip>Skip ${optional ? optional.label.toLowerCase() : ""}</button>
        <button class="hm-btn go" data-save disabled>Save</button>
      </div>`
    document.body.appendChild(ed)
    document.body.style.overflow = "hidden"
    this.ed = ed
    this.canvas = ed.querySelector("canvas")
    this.ctx = this.canvas.getContext("2d")

    ed.querySelector("[data-cancel]").onclick = () => this.close()
    ed.querySelector("[data-undo]").onclick = () => this.undo()
    ed.querySelector("[data-help]").onclick = () => this.toggleHelp()
    ed.querySelector("[data-skip]").onclick = () => {
      this.skipped = true
      if (optional) this.points[optional.key] = []
      this.refresh()
    }
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

    // First time with a view on this device: show the helper so the lines make sense.
    try {
      const k = "ranch:hoof-help-" + this.mode
      if (!localStorage.getItem(k)) { localStorage.setItem(k, "1"); this.toggleHelp(true) }
    } catch (e) {}
  },

  // What each line is for, and what "correct" looks like.
  toggleHelp(show) {
    const panel = this.ed.querySelector("[data-helppanel]")
    const open = show === undefined ? panel.hidden : show
    if (open) {
      const steps = this.steps.map((st) =>
        `<li><i style="background:${st.color}"></i><div><b>${st.label}${st.optional ? " (optional)" : ""}</b> · ${st.say}<small>${st.why}</small></div></li>`).join("")
      panel.innerHTML = `
        <h3>${this.mode === "sole" ? "Bottom of the foot" : "Side of the foot"}: what the lines are</h3>
        ${this.mode === "sole" ? SOLE_SVG : SIDE_SVG}
        <ol>${steps}</ol>
        <h4>What's correct</h4>
        <ul>${this.def.correct.map((c) => `<li>${c}</li>`).join("")}</ul>
        <h4>Photo tips</h4>
        <ul>${this.mode === "sole"
          ? "<li>Pick the foot up, clean the sole and frog, and shoot straight down at the sole so the whole foot fills the photo.</li><li>Hold the camera square to the bottom of the foot, not tilted toward the toe or heel.</li>"
          : "<li>Stand him square on flat ground. Camera on the ground, level, square to the side of the hoof.</li>"}</ul>
        <button class="hm-btn go" data-closehelp>Got it</button>`
      panel.querySelector("[data-closehelp]").onclick = () => this.toggleHelp(false)
    }
    panel.hidden = !open
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
    for (const st of this.steps) {
      if (st.optional && this.skipped) continue
      if (this.points[st.key].length < st.n) return st
    }
    return null
  },

  say(text) {
    if (this.ed) this.ed.querySelector("[data-say]").innerHTML = text
  },

  angles() {
    if (this.mode !== "side") return {toe: null, pastern: null}
    const g = this.points.ground, w = this.points.wall, p = this.points.pastern
    const toe = g.length === 2 && w.length === 2 ? angleBetween(g, w) : null
    const pastern = g.length === 2 && p.length === 2 ? angleBetween(g, p) : null
    return {toe, pastern}
  },

  sole() {
    return this.mode === "sole" ? soleNumbers(this.points) : null
  },

  ready() {
    if (this.mode === "sole") return !!this.sole()
    const {toe} = this.angles()
    return toe != null && toe > 0 && toe < 90
  },

  refresh() {
    const st = this.step()
    const n = st ? this.points[st.key].length : 0
    if (st) {
      this.say(`<i style="color:${st.color}">${st.label}${st.n > 1 && n ? " · 2nd dot" : ""}:</i> ${st.say}`)
    } else {
      this.say("Drag any dot to fine-tune, then Save.")
    }
    const line = (ok, text) => `<span class="ln ${ok ? "ok" : "check"}">${text}</span>`
    const read = this.ed.querySelector("[data-read]")
    if (this.mode === "sole") {
      const m = this.sole()
      read.innerHTML = !m ? "Balance shows here." :
        `Toe <b>${m.toeShare}%</b> · Heel <b>${r1(100 - m.toeShare)}%</b>` +
        line(Math.abs(m.toeShare - 50) <= 5, Math.abs(m.toeShare - 50) <= 5 ? "Widest part near the middle" : "Widest part off the middle") +
        line(m.sides - 50 <= 4, `Sides ${m.sides}/${r1(100 - m.sides)}`) +
        line(m.heels <= 3, m.heels <= 3 ? "Heels even" : `Heels ${m.heels}° off square`) +
        (m.frog == null ? "" : line(m.frog <= 4, m.frog <= 4 ? "Frog centered" : `Frog ${m.frog}% off center`))
    } else {
      const {toe, pastern} = this.angles()
      const ax = axisText(toe, pastern)
      const tn = toeNote(this.foot, toe)
      read.innerHTML = toe == null
        ? "Toe angle shows here."
        : `Toe <b>${toe}°</b>${pastern != null ? ` · Pastern <b>${pastern}°</b>` : ""}` +
          (tn ? line(tn.ok, tn.text) : "") + (ax ? line(ax.startsWith("Hoof"), ax) : "")
    }
    const opt = this.steps.find((x) => x.optional)
    const skip = this.ed.querySelector("[data-skip]")
    skip.style.display = !opt || this.skipped || this.points[opt.key].length === opt.n || this.step() !== opt ? "none" : ""
    this.ed.querySelector("[data-save]").disabled = !this.ready()
    this.draw()
  },

  undo() {
    for (const st of [...this.steps].reverse()) {
      if (st.optional && this.skipped && this.points[st.key].length === 0) { this.skipped = false; return this.refresh() }
      if (this.points[st.key].length) { this.points[st.key].pop(); return this.refresh() }
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
    if (this.mode === "sole") return this.paintSole(c, map, k)
    const {toe, pastern} = this.angles()
    for (const s of this.steps) {
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

  // A line with a dark outline so it shows on any photo; `ext` runs it past its ends.
  stroke(c, a, b, color, k, ext = 0, dash = null) {
    const dx = b.x - a.x, dy = b.y - a.y
    const p = {x: a.x - dx * ext, y: a.y - dy * ext}, q = {x: b.x + dx * ext, y: b.y + dy * ext}
    c.lineCap = "round"
    c.setLineDash([])
    c.strokeStyle = "rgba(0,0,0,.55)"; c.lineWidth = 6 * k
    c.beginPath(); c.moveTo(p.x, p.y); c.lineTo(q.x, q.y); c.stroke()
    if (dash) c.setLineDash(dash.map((d) => d * k))
    c.strokeStyle = color; c.lineWidth = 3 * k
    c.beginPath(); c.moveTo(p.x, p.y); c.lineTo(q.x, q.y); c.stroke()
    c.setLineDash([])
  },

  dot(c, p, color, k) {
    c.fillStyle = color; c.strokeStyle = "#fff"; c.lineWidth = 2.5 * k
    c.beginPath(); c.arc(p.x, p.y, 8 * k, 0, Math.PI * 2); c.fill(); c.stroke()
  },

  paintSole(c, map, k) {
    const P = this.points, col = Object.fromEntries(this.steps.map((st) => [st.key, st.color]))
    const m = soleNumbers(P)
    const toe = P.toe.map(map), heels = P.heels.map(map), widest = P.widest.map(map), frog = P.frog.map(map)
    if (heels.length === 2) this.stroke(c, heels[0], heels[1], col.heels, k)
    if (widest.length === 2) this.stroke(c, widest[0], widest[1], col.widest, k)
    if (toe.length && heels.length === 2) {
      const hm = {x: (heels[0].x + heels[1].x) / 2, y: (heels[0].y + heels[1].y) / 2}
      this.stroke(c, hm, toe[0], col.toe, k, 0.04, [10, 7])
      c.fillStyle = "#fff"; c.beginPath(); c.arc(hm.x, hm.y, 4 * k, 0, Math.PI * 2); c.fill()
    }
    if (m) {
      const X = map(m.X)
      c.strokeStyle = "#fff"; c.lineWidth = 2.5 * k
      c.beginPath(); c.arc(X.x, X.y, 10 * k, 0, Math.PI * 2); c.stroke()
      const T = toe[0], H = map(m.Hm)
      this.tag(c, `Toe ${m.toeShare}%`, (T.x + X.x) / 2 + 12 * k, (T.y + X.y) / 2, col.toe, k)
      this.tag(c, `Heel ${r1(100 - m.toeShare)}%`, (H.x + X.x) / 2 + 12 * k, (H.y + X.y) / 2, col.heels, k)
      this.tag(c, `${m.sides}/${r1(100 - m.sides)}`, widest[1].x + 12 * k, widest[1].y, col.widest, k)
    }
    for (const [key, pts] of [["toe", toe], ["heels", heels], ["widest", widest], ["frog", frog]])
      for (const p of pts) this.dot(c, p, col[key], k)
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
    for (const s of current ? [] : this.steps) {
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
    if (!this.ready()) return
    const {toe, pastern} = this.angles()
    const sole = this.sole()
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
    const points = Object.fromEntries(this.steps.map((st) => [st.key, this.points[st.key].map(round)]))
    points.width = this.img.naturalWidth
    points.height = this.img.naturalHeight
    const data = {
      view: this.mode,
      foot: this.foot,
      toe, pastern,
      date: this.ed.querySelector("[data-date]").value,
      note: this.ed.querySelector("[data-note]").value,
      points,
    }
    if (sole) Object.assign(data, {toe_share: sole.toeShare, sides: sole.sides, heels: sole.heels, frog: sole.frog, ratio: sole.ratio})

    out.toBlob((blob) => {
      const file = new File([blob], `hoof-${this.foot}-${this.mode}.jpg`, {type: "image/jpeg"})
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
