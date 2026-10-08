.pragma library

// Per-workspace display overrides from the widget's `workspaces` setting. The
// setting is keyed by workspace number; each entry may set an `icon` drawn
// instead of the number, a `name` shown in the tooltip, and `alwaysShow` to
// list the workspace even while Hyprland doesn't know about it.

var FIRST_ID = 1
var LAST_ID = 10
var ALWAYS_LISTED = [1, 2, 3, 4, 5]

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function text(value) {
  return typeof value === "string" ? value.trim() : ""
}

// Returns { <id>: { icon, name, alwaysShow } } for valid entries only. Ids
// outside 1–10 and entries that aren't objects are dropped; fields of the
// wrong type fall back to their defaults.
function normalize(setting) {
  var result = {}
  if (!isPlainObject(setting)) return result

  for (var key in setting) {
    if (!/^\d+$/.test(key)) continue
    var id = Number(key)
    if (id < FIRST_ID || id > LAST_ID) continue

    var entry = setting[key]
    if (!isPlainObject(entry)) continue

    result[id] = {
      icon: text(entry.icon),
      name: text(entry.name),
      alwaysShow: entry.alwaysShow === true
    }
  }

  return result
}

// existingIds: ids of the workspaces Hyprland currently knows about.
// Returns the sorted ids to list: 1–5, existing ids in 1–10, and any
// override with `alwaysShow`.
function workspaceIds(existingIds, overrides) {
  var ids = ALWAYS_LISTED.slice()

  function add(id) {
    if (id >= FIRST_ID && id <= LAST_ID && ids.indexOf(id) === -1) ids.push(id)
  }

  for (var i = 0; i < (existingIds ? existingIds.length : 0); i++) add(Number(existingIds[i]))

  for (var key in (overrides || {})) {
    if (overrides[key] && overrides[key].alwaysShow) add(Number(key))
  }

  ids.sort(function(left, right) { return left - right })
  return ids
}
