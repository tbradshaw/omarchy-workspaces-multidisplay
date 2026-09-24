pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "MonitorLayout.js" as MonitorLayout

BarWidget {
  id: root
  moduleName: "io.github.tbradshaw.workspaces-multidisplay"

  readonly property string activeGlyph: "\uDB85\uDCFB"
  readonly property string otherMonitorGlyph: "\uDB85\uDCFC"
  readonly property real dimmedLineOpacity: 0.35

  // Every monitor has its own bar, so each instance marks the workspace shown
  // on its own monitor rather than the one that currently has focus.
  readonly property var barWindow: root.QsWindow ? root.QsWindow.window : null
  readonly property var barMonitor: barWindow && barWindow.screen ? Hyprland.monitorFor(barWindow.screen) : null
  readonly property string barPosition: root.bar && root.bar.position ? String(root.bar.position) : "top"

  readonly property int thisMonitorWorkspaceId: {
    if (barMonitor && barMonitor.activeWorkspace) return barMonitor.activeWorkspace.id
    if (Hyprland.focusedWorkspace) return Hyprland.focusedWorkspace.id
    return 0
  }

  readonly property var visibleWorkspaceIds: {
    var ids = []
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++) {
      var active = monitors[i].activeWorkspace
      if (active) ids.push(active.id)
    }
    return ids
  }

  readonly property var placements: {
    var geometries = []
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++) {
      var monitor = monitors[i]
      var ipc = monitor.lastIpcObject || {}
      geometries.push(MonitorLayout.logicalGeometry({
        name: monitor.name,
        x: monitor.x,
        y: monitor.y,
        width: monitor.width,
        height: monitor.height,
        scale: monitor.scale,
        transform: ipc.transform
      }))
    }
    return MonitorLayout.placements(geometries, root.barPosition)
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      // Quickshell 0.3.1 updates a moved workspace's monitor but leaves each
      // monitor's activeWorkspace stale until the monitor model is refreshed.
      if (event.name === "moveworkspacev2") Hyprland.refreshMonitors()
    }
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function tooltipFor(id, monitorName, placement) {
    var text = "Workspace " + id
    if (monitorName === "") return text
    text += " · " + monitorName
    if (placement && placement.label) text += " (" + placement.label + ")"
    return text
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      Item {
        id: cell

        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool activeHere: root.thisMonitorWorkspaceId === modelData
        readonly property bool visibleAnywhere: activeHere || root.visibleWorkspaceIds.indexOf(modelData) !== -1
        readonly property bool visibleElsewhere: visibleAnywhere && !activeHere
        readonly property string monitorName: workspace !== null && workspace.monitor ? String(workspace.monitor.name || "") : ""
        readonly property var placement: monitorName !== "" ? (root.placements[monitorName] || null) : null

        implicitWidth: button.implicitWidth
        implicitHeight: button.implicitHeight

        WidgetButton {
          id: button
          anchors.fill: parent
          bar: root.bar
          text: cell.activeHere ? root.activeGlyph
            : (cell.visibleElsewhere ? root.otherMonitorGlyph
              : (cell.modelData === 10 ? "0" : String(cell.modelData)))
          opacity: cell.occupied || cell.visibleAnywhere ? 1 : 0.5
          horizontalMargin: 6
          verticalPadding: 6
          fixedWidth: root.vertical ? root.barSize : Style.space(20)
          fixedHeight: root.barSize
          tooltipText: root.tooltipFor(cell.modelData, cell.monitorName, cell.placement)
          onPressed: function() { root.focusWorkspace(cell.modelData) }
        }

        // Monitor assignment line. A sibling of the button rather than a child
        // so the button's opacity does not compound with the line's own.
        Rectangle {
          readonly property string edge: cell.placement ? cell.placement.edge : ""
          readonly property string segment: cell.placement ? cell.placement.segment : "full"
          readonly property bool alongWidth: edge === "top" || edge === "bottom"
          readonly property real thickness: Math.max(1, Style.space(2))
          readonly property real inset: Style.space(2)
          readonly property real span: Math.max(0, (alongWidth ? cell.width : cell.height) - inset * 2)
          readonly property real length: segment === "full" ? span : span / 2
          readonly property real offset: segment === "end" ? span - length
            : (segment === "middle" ? (span - length) / 2 : 0)

          visible: edge !== ""
          color: Color.accent
          radius: thickness / 2
          opacity: cell.visibleAnywhere ? 1 : root.dimmedLineOpacity
          width: alongWidth ? length : thickness
          height: alongWidth ? thickness : length
          x: alongWidth ? inset + offset : (edge === "left" ? inset : cell.width - thickness - inset)
          y: alongWidth ? (edge === "top" ? inset : cell.height - thickness - inset) : inset + offset

          Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
          }
        }
      }
    }
  }
}
