pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "MonitorLayout.js" as MonitorLayout
import "WorkspaceOverrides.js" as WorkspaceOverrides

BarWidget {
  id: root
  moduleName: "io.github.tbradshaw.workspaces-multidisplay"

  readonly property string activeGlyph: "\uDB85\uDCFB"
  readonly property string otherMonitorGlyph: "\uDB85\uDCFC"
  readonly property real dimmedLineOpacity: 0.35
  readonly property real activePillAlpha: 0.22

  readonly property var overrides: WorkspaceOverrides.normalize(root.setting("workspaces", {}))

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
    var existing = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) existing.push(values[i].id)
    return WorkspaceOverrides.workspaceIds(existing, root.overrides)
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function dispatch(expression) {
    return "hyprctl dispatch " + Util.shellQuote(expression)
  }

  // Sends a workspace to the next monitor in Hyprland's ID order. A visible
  // workspace stays visible and takes focus with it. Hyprland only does that
  // itself when the workspace leaves the focused monitor, so otherwise focus
  // it explicitly after the move. A hidden workspace stays hidden.
  function cycleWorkspaceMonitor(id) {
    if (!root.bar) return
    var workspace = root.workspaceById(id)
    if (!workspace || !workspace.monitor) return

    var monitors = []
    var values = Hyprland.monitors.values
    for (var i = 0; i < values.length; i++) monitors.push({ id: values[i].id, name: values[i].name })
    var currentName = String(workspace.monitor.name || "")
    var target = MonitorLayout.nextMonitorName(monitors, currentName)
    if (target === "") return

    var selector = JSON.stringify(String(id))
    var command = root.dispatch("hl.dsp.workspace.move({ workspace = " + selector + ", monitor = " + JSON.stringify(target) + " })")

    var visible = root.visibleWorkspaceIds.indexOf(id) !== -1
    var focused = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    if (visible && currentName !== focused) command += " && " + root.dispatch("hl.dsp.focus({ workspace = " + selector + " })")

    root.bar.run(command)
  }

  function tooltipFor(id, name, monitorName, placement) {
    var text = "Workspace " + id
    if (name !== "") text += " · " + name
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
        readonly property var overrideEntry: root.overrides[modelData] || null
        readonly property string icon: overrideEntry ? overrideEntry.icon : ""
        readonly property string workspaceName: overrideEntry ? overrideEntry.name : ""

        implicitWidth: button.implicitWidth
        implicitHeight: button.implicitHeight

        // A workspace with its own icon keeps it while visible, so a pill
        // behind it takes the place of the square glyphs: filled on this
        // bar's monitor, outlined on another. It sits inside the monitor line
        // and, like the line, is a sibling so the button's opacity doesn't
        // compound with it.
        Rectangle {
          readonly property real alongInset: Style.space(1)
          readonly property real crossInset: Style.space(6)
          readonly property real maxLength: Style.space(18)

          visible: cell.icon !== "" && cell.visibleAnywhere
          anchors.centerIn: parent
          width: root.vertical ? cell.width - crossInset * 2 : Math.min(maxLength, cell.width - alongInset * 2)
          height: root.vertical ? Math.min(maxLength, cell.height - alongInset * 2) : cell.height - crossInset * 2
          radius: Style.space(4)
          color: cell.activeHere ? Qt.alpha(button.foreground, root.activePillAlpha) : "transparent"
          border.width: cell.visibleElsewhere ? Math.max(1, Style.space(1)) : 0
          border.color: button.foreground
        }

        WidgetButton {
          id: button
          anchors.fill: parent
          bar: root.bar
          text: cell.icon !== "" ? cell.icon
            : cell.activeHere ? root.activeGlyph
            : (cell.visibleElsewhere ? root.otherMonitorGlyph
              : (cell.modelData === 10 ? "0" : String(cell.modelData)))
          opacity: cell.occupied || cell.visibleAnywhere ? 1 : 0.5
          horizontalMargin: 6
          verticalPadding: 6
          fixedWidth: root.vertical ? root.barSize : Style.space(20)
          fixedHeight: root.barSize
          tooltipText: root.tooltipFor(cell.modelData, cell.workspaceName, cell.monitorName, cell.placement)
          onPressed: function(mouseButton) {
            if (mouseButton === Qt.RightButton) root.cycleWorkspaceMonitor(cell.modelData)
            else root.focusWorkspace(cell.modelData)
          }
          // Nerd Font icons paint wider than their monospace advance, which the
          // stock label centres off-axis; OpticalGlyph centres the painted ink.
          labelVisible: false

          TextMetrics {
            id: inkMetrics
            font.family: button.fontFamily
            font.pixelSize: Math.max(1, Math.round(button.fontSize))
            text: button.text
          }

          FontMetrics {
            id: lineMetrics
            font: inkMetrics.font
          }

          OpticalGlyph {
            // Text centres on the font's line box; shift so the painted ink
            // is vertically centred instead.
            readonly property real inkCenterY: lineMetrics.ascent + inkMetrics.tightBoundingRect.y + inkMetrics.tightBoundingRect.height / 2
            width: parent.width
            height: parent.height
            y: Math.round((lineMetrics.ascent + lineMetrics.descent) / 2 - inkCenterY)
            text: button.text
            fontFamily: button.fontFamily
            fontSize: button.fontSize
            color: button.foreground
          }
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
          color: button.foreground
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
