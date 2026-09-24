.pragma library

// Maps monitor geometry to where each monitor's assignment line sits inside a
// workspace cell. Each cell is treated as a miniature of the monitor layout:
// the edge of the cell that runs along the bar encodes the monitor's position
// across the bar, and the half of that edge encodes its position along the
// bar. Lines therefore never sit on the short edges between adjacent cells.

var EPSILON = 1

// Hyprland reports width and height in physical pixels and x/y in the logical
// layout space. Odd transforms rotate the output by 90 or 270 degrees.
function logicalGeometry(monitor) {
  var scale = Number(monitor.scale) > 0 ? Number(monitor.scale) : 1
  var width = (Number(monitor.width) || 0) / scale
  var height = (Number(monitor.height) || 0) / scale
  if (Number(monitor.transform) % 2 === 1) {
    var swap = width
    width = height
    height = swap
  }
  return {
    name: String(monitor.name || ""),
    x: Number(monitor.x) || 0,
    y: Number(monitor.y) || 0,
    width: width,
    height: height
  }
}

// An axis is split when at least two monitors occupy disjoint ranges on it.
// Mirrored or overlapping outputs therefore do not count as separate places.
function axisSplit(monitors, start, size) {
  for (var i = 0; i < monitors.length; i++) {
    for (var j = 0; j < monitors.length; j++) {
      if (i === j) continue
      if (monitors[i][start] + monitors[i][size] <= monitors[j][start] + EPSILON) return true
    }
  }
  return false
}

function bucket(value, low, high) {
  var mid = (low + high) / 2
  if (value < mid - EPSILON) return "start"
  if (value > mid + EPSILON) return "end"
  return "middle"
}

function axisLabel(value, startLabel, middleLabel, endLabel) {
  if (value === "start") return startLabel
  if (value === "end") return endLabel
  return middleLabel
}

function isVerticalBar(barPosition) {
  return barPosition === "left" || barPosition === "right"
}

// The edge that faces away from the screen edge the bar is attached to.
function innerEdge(barPosition) {
  if (barPosition === "bottom") return "top"
  if (barPosition === "left") return "right"
  if (barPosition === "right") return "left"
  return "bottom"
}

// monitors: [{ name, x, y, width, height }] in logical coordinates.
// barPosition: "top" | "bottom" | "left" | "right".
// Returns { <monitor name>: { edge, segment, label } } where edge is one of
// "top" | "bottom" | "left" | "right" and segment is one of
// "full" | "start" | "middle" | "end" along that edge. Returns an empty object
// when the layout has only one distinct place, since there is nothing to
// distinguish.
function placements(monitors, barPosition) {
  var list = []
  for (var i = 0; i < (monitors ? monitors.length : 0); i++) {
    var m = monitors[i]
    if (m && m.name) list.push(m)
  }

  var splitX = axisSplit(list, "x", "width")
  var splitY = axisSplit(list, "y", "height")
  var result = {}
  if (!splitX && !splitY) return result

  var minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity
  for (var c = 0; c < list.length; c++) {
    var cx = list[c].x + list[c].width / 2
    var cy = list[c].y + list[c].height / 2
    minX = Math.min(minX, cx)
    maxX = Math.max(maxX, cx)
    minY = Math.min(minY, cy)
    maxY = Math.max(maxY, cy)
  }

  var vertical = isVerticalBar(barPosition)
  var inner = innerEdge(barPosition)

  for (var k = 0; k < list.length; k++) {
    var mon = list[k]
    var bx = splitX ? bucket(mon.x + mon.width / 2, minX, maxX) : ""
    var by = splitY ? bucket(mon.y + mon.height / 2, minY, maxY) : ""

    var edge
    var segment
    if (vertical) {
      edge = bx === "start" ? "left" : (bx === "end" ? "right" : inner)
      segment = splitY ? by : "full"
    } else {
      edge = by === "start" ? "top" : (by === "end" ? "bottom" : inner)
      segment = splitX ? bx : "full"
    }

    var parts = []
    if (splitY) parts.push(axisLabel(by, "top", "middle", "bottom"))
    if (splitX) parts.push(axisLabel(bx, "left", "center", "right"))
    var label = parts.join(" ")
    if (label === "middle center") label = "center"

    result[mon.name] = { edge: edge, segment: segment, label: label }
  }

  return result
}
