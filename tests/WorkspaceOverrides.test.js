"use strict"

const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

function loadOverrides() {
  const source = fs.readFileSync(path.join(__dirname, "..", "WorkspaceOverrides.js"), "utf8")
    .replace(/^\.pragma library\s*$/m, "")
  const context = {}
  vm.createContext(context)
  vm.runInContext(source, context)
  return context
}

const overrides = loadOverrides()
const plain = (value) => JSON.parse(JSON.stringify(value))

test("missing or malformed settings have no overrides", () => {
  for (const value of [undefined, null, "", 9, [], ["x"]]) {
    assert.deepEqual(plain(overrides.normalize(value)), {})
  }
})

test("entries are normalised with defaults", () => {
  const result = plain(overrides.normalize({
    "9": { icon: " 󰚩 ", name: "Automation", alwaysShow: true },
    "10": { icon: "󰣙" }
  }))
  assert.deepEqual(result, {
    "9": { icon: "󰚩", name: "Automation", alwaysShow: true },
    "10": { icon: "󰣙", name: "", alwaysShow: false }
  })
})

test("ids outside 1–10 and non-numeric keys are ignored", () => {
  const result = plain(overrides.normalize({
    "0": { icon: "a" }, "11": { icon: "b" }, "-1": { icon: "c" }, "1.5": { icon: "d" }, "x": { icon: "e" }
  }))
  assert.deepEqual(result, {})
})

test("non-object entries and wrong-typed fields are ignored", () => {
  const result = plain(overrides.normalize({
    "3": "󰚩",
    "4": { icon: 7, name: ["x"], alwaysShow: "true" },
    "5": { icon: "   ", name: "" }
  }))
  assert.deepEqual(result, {
    "4": { icon: "", name: "", alwaysShow: false },
    "5": { icon: "", name: "", alwaysShow: false }
  })
})

test("workspace ids always include 1–5 and existing workspaces", () => {
  assert.deepEqual(plain(overrides.workspaceIds([7, 2, 12, -98], {})), [1, 2, 3, 4, 5, 7])
  assert.deepEqual(plain(overrides.workspaceIds(null, null)), [1, 2, 3, 4, 5])
})

test("only alwaysShow overrides add empty workspaces", () => {
  const normalized = overrides.normalize({
    "9": { icon: "󰚩", alwaysShow: true },
    "10": { icon: "󰣙", alwaysShow: true },
    "8": { icon: "x" }
  })
  assert.deepEqual(plain(overrides.workspaceIds([6], normalized)), [1, 2, 3, 4, 5, 6, 9, 10])
  assert.deepEqual(plain(overrides.workspaceIds([10], normalized)), [1, 2, 3, 4, 5, 9, 10])
})
