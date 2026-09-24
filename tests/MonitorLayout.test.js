"use strict"

const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

// MonitorLayout.js is a QML JavaScript library. Drop its `.pragma library`
// line and evaluate it in a sandbox to reach its top-level functions.
function loadLayout() {
  const source = fs.readFileSync(path.join(__dirname, "..", "MonitorLayout.js"), "utf8")
    .replace(/^\.pragma library\s*$/m, "")
  const context = {}
  vm.createContext(context)
  vm.runInContext(source, context)
  return context
}

const layout = loadLayout()
const plain = (value) => JSON.parse(JSON.stringify(value))
const mon = (name, x, y, width = 3840, height = 2160) => ({ name, x, y, width, height })

test("single monitor has no placements", () => {
  assert.deepEqual(plain(layout.placements([mon("DP-1", 0, 0)], "top")), {})
})

test("no monitors has no placements", () => {
  assert.deepEqual(plain(layout.placements([], "top")), {})
  assert.deepEqual(plain(layout.placements(null, "top")), {})
})

test("mirrored monitors are one place", () => {
  assert.deepEqual(plain(layout.placements([mon("A", 0, 0), mon("B", 0, 0)], "top")), {})
})

test("stacked monitors use full overline and underline on a horizontal bar", () => {
  const result = plain(layout.placements([mon("DP-2", 0, 0), mon("DP-3", 0, 2160)], "top"))
  assert.deepEqual(result, {
    "DP-2": { edge: "top", segment: "full", label: "top" },
    "DP-3": { edge: "bottom", segment: "full", label: "bottom" }
  })
})

test("stacked placements do not depend on horizontal bar position", () => {
  const monitors = [mon("DP-2", 0, 0), mon("DP-3", 0, 2160)]
  assert.deepEqual(plain(layout.placements(monitors, "bottom")), plain(layout.placements(monitors, "top")))
})

test("side-by-side monitors use half segments on the inner edge", () => {
  const monitors = [mon("L", 0, 0), mon("R", 3840, 0)]
  assert.deepEqual(plain(layout.placements(monitors, "top")), {
    L: { edge: "bottom", segment: "start", label: "left" },
    R: { edge: "bottom", segment: "end", label: "right" }
  })
  assert.deepEqual(plain(layout.placements(monitors, "bottom")), {
    L: { edge: "top", segment: "start", label: "left" },
    R: { edge: "top", segment: "end", label: "right" }
  })
})

test("side-by-side monitors with a vertical offset but overlapping rows stay one row", () => {
  const result = plain(layout.placements([mon("L", 0, 0, 2560, 1440), mon("R", 2560, 400)], "top"))
  assert.equal(result.L.edge, "bottom")
  assert.equal(result.R.edge, "bottom")
  assert.equal(result.L.segment, "start")
  assert.equal(result.R.segment, "end")
})

test("2x2 grid uses corners", () => {
  const result = plain(layout.placements([
    mon("TL", 0, 0), mon("TR", 3840, 0), mon("BL", 0, 2160), mon("BR", 3840, 2160)
  ], "top"))
  assert.deepEqual(result, {
    TL: { edge: "top", segment: "start", label: "top left" },
    TR: { edge: "top", segment: "end", label: "top right" },
    BL: { edge: "bottom", segment: "start", label: "bottom left" },
    BR: { edge: "bottom", segment: "end", label: "bottom right" }
  })
})

test("vertical bars swap axes for stacked monitors", () => {
  const monitors = [mon("T", 0, 0), mon("B", 0, 2160)]
  assert.deepEqual(plain(layout.placements(monitors, "left")), {
    T: { edge: "right", segment: "start", label: "top" },
    B: { edge: "right", segment: "end", label: "bottom" }
  })
  assert.deepEqual(plain(layout.placements(monitors, "right")), {
    T: { edge: "left", segment: "start", label: "top" },
    B: { edge: "left", segment: "end", label: "bottom" }
  })
})

test("vertical bars use full side lines for side-by-side monitors", () => {
  assert.deepEqual(plain(layout.placements([mon("L", 0, 0), mon("R", 3840, 0)], "left")), {
    L: { edge: "left", segment: "full", label: "left" },
    R: { edge: "right", segment: "full", label: "right" }
  })
})

test("three monitors in a row use start, middle, and end segments", () => {
  const result = plain(layout.placements([mon("A", 0, 0), mon("B", 3840, 0), mon("C", 7680, 0)], "top"))
  assert.deepEqual(result, {
    A: { edge: "bottom", segment: "start", label: "left" },
    B: { edge: "bottom", segment: "middle", label: "center" },
    C: { edge: "bottom", segment: "end", label: "right" }
  })
})

test("monitor order does not change placements", () => {
  const a = plain(layout.placements([mon("DP-2", 0, 0), mon("DP-3", 0, 2160)], "top"))
  const b = plain(layout.placements([mon("DP-3", 0, 2160), mon("DP-2", 0, 0)], "top"))
  assert.deepEqual(a, b)
})

test("unnamed monitors are ignored", () => {
  assert.deepEqual(plain(layout.placements([mon("", 0, 0), mon("DP-1", 0, 2160)], "top")), {})
})

test("logical geometry applies scale and rotation", () => {
  assert.deepEqual(plain(layout.logicalGeometry({ name: "A", x: 10, y: 20, width: 3840, height: 2160, scale: 2 })), {
    name: "A", x: 10, y: 20, width: 1920, height: 1080
  })
  assert.deepEqual(plain(layout.logicalGeometry({ name: "A", x: 0, y: 0, width: 3840, height: 2160, scale: 1, transform: 1 })), {
    name: "A", x: 0, y: 0, width: 2160, height: 3840
  })
  assert.deepEqual(plain(layout.logicalGeometry({ name: "A", width: 100, height: 50, scale: 0 })), {
    name: "A", x: 0, y: 0, width: 100, height: 50
  })
})

test("scaled stacked monitors are still stacked", () => {
  const top = layout.logicalGeometry({ name: "T", x: 0, y: 0, width: 3840, height: 2160, scale: 2 })
  const bottom = layout.logicalGeometry({ name: "B", x: 0, y: 1080, width: 3840, height: 2160, scale: 2 })
  const result = plain(layout.placements([top, bottom], "top"))
  assert.equal(result.T.edge, "top")
  assert.equal(result.B.edge, "bottom")
})
