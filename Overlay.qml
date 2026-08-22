import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Commons

Item {
  id: root

  // Omarchy injects these properties into plugin entry points.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell
  property var manifest
  property var pluginRegistry

  property bool opened: false
  property bool allWorkspaces: false
  property int selectedIndex: 0
  property var pendingActivation: null
  readonly property var workspace: Hyprland.focusedWorkspace
  readonly property var targetScreen: {
    var screens = Quickshell.screens || []
    var monitor = Hyprland.focusedMonitor
    for (var i = 0; i < screens.length; ++i) {
      if (monitor && screens[i].name === monitor.name) return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }
  readonly property var windows: allWorkspaces
    ? Hyprland.toplevels.values
    : (workspace ? workspace.toplevels.values : [])
  readonly property int count: windows ? windows.length : 0

  function clampSelection() {
    if (count === 0) selectedIndex = 0
    else selectedIndex = Math.max(0, Math.min(selectedIndex, count - 1))
  }

  function open(payloadJson) {
    var rawPayload = String(payloadJson || "")
    var scope = rawPayload
    try {
      var payload = JSON.parse(rawPayload || "{}")
      scope = String(payload.scope || "")
    } catch (e) {}
    allWorkspaces = scope === "all"
    Hyprland.refreshToplevels()
    selectedIndex = 0
    opened = true
    Qt.callLater(function() {
      console.log("Panorama opened:", root.allWorkspaces ? "all workspaces" : "current workspace", root.count, "windows")
      var active = ToplevelManager.activeToplevel
      for (var i = 0; i < root.count; ++i) {
        if (root.windows[i].wayland === active || root.windows[i].activated) {
          root.selectedIndex = i
          break
        }
      }
      keyArea.forceActiveFocus()
    })
  }

  function close() {
    opened = false
  }

  function dismiss() {
    opened = false
  }

  function focusWindow(index) {
    if (index < 0 || index >= count) return
    var target = windows[index]
    pendingActivation = target
    dismiss()
    if (target.workspace && (!Hyprland.focusedWorkspace
        || target.workspace.id !== Hyprland.focusedWorkspace.id)) {
      if (Hyprland.usingLua)
        Hyprland.dispatch("hl.dsp.focus({ workspace = " + target.workspace.id + " })")
      else
        Hyprland.dispatch("workspace " + target.workspace.id)
      activationDelay.restart()
    } else {
      activatePendingWindow()
    }
  }

  function activatePendingWindow() {
    var target = pendingActivation
    pendingActivation = null
    if (target && target.wayland) target.wayland.activate()
  }

  Timer {
    id: activationDelay
    interval: 90
    repeat: false
    onTriggered: root.activatePendingWindow()
  }

  function moveSelection(dx, dy, layout) {
    if (count === 0 || !layout || !layout[selectedIndex]) return
    var current = layout[selectedIndex]
    var cx = current.x + current.width / 2
    var cy = current.y + current.height / 2
    var best = -1
    var bestScore = Number.MAX_VALUE
    for (var i = 0; i < layout.length; ++i) {
      if (i === selectedIndex) continue
      var candidate = layout[i]
      var vx = candidate.x + candidate.width / 2 - cx
      var vy = candidate.y + candidate.height / 2 - cy
      var forward = vx * dx + vy * dy
      if (forward <= 1) continue
      var sideways = Math.abs(vx * dy - vy * dx)
      var score = forward + sideways * 1.8
      if (score < bestScore) {
        bestScore = score
        best = i
      }
    }
    if (best >= 0) selectedIndex = best
  }

  function windowGeometry(window) {
    var ipc = window && window.lastIpcObject ? window.lastIpcObject : ({})
    var size = ipc.size || [16, 10]
    var at = ipc.at || [0, 0]
    var width = size && size.length >= 2 ? Math.max(80, Number(size[0]) || 800) : 800
    var height = size && size.length >= 2 ? Math.max(60, Number(size[1]) || 500) : 500
    return {
      x: at && at.length >= 2 ? Number(at[0]) || 0 : 0,
      y: at && at.length >= 2 ? Number(at[1]) || 0 : 0,
      width: width,
      height: height
    }
  }

  function spatialLayout(items, areaWidth, areaHeight, gap) {
    var total = items ? items.length : 0
    if (total === 0) return []

    var source = []
    var minX = Number.MAX_VALUE
    var minY = Number.MAX_VALUE
    var maxX = -Number.MAX_VALUE
    var maxY = -Number.MAX_VALUE
    var sourceArea = 0
    for (var i = 0; i < total; ++i) {
      var geometry = windowGeometry(items[i])
      source.push(geometry)
      minX = Math.min(minX, geometry.x)
      minY = Math.min(minY, geometry.y)
      maxX = Math.max(maxX, geometry.x + geometry.width)
      maxY = Math.max(maxY, geometry.y + geometry.height)
      sourceArea += geometry.width * geometry.height
    }

    var desktopWidth = Math.max(1, maxX - minX)
    var desktopHeight = Math.max(1, maxY - minY)
    var scale = Math.sqrt(areaWidth * areaHeight * 0.58 / Math.max(1, sourceArea))

    for (var attempt = 0; attempt < 9; ++attempt) {
      var result = []
      for (var n = 0; n < total; ++n) {
        var original = source[n]
        var width = original.width * scale
        var previewHeight = original.height * scale
        var minScale = Math.max(130 / Math.max(1, width), 78 / Math.max(1, previewHeight), 1)
        width *= minScale
        previewHeight *= minScale
        var maxScale = Math.min(areaWidth * 0.58 / width, (areaHeight - 34) * 0.62 / previewHeight, 1)
        width *= maxScale
        previewHeight *= maxScale

        var normalizedX = (original.x + original.width / 2 - minX) / desktopWidth
        var normalizedY = (original.y + original.height / 2 - minY) / desktopHeight
        var preferredX = normalizedX * areaWidth - width / 2
        var preferredY = normalizedY * areaHeight - (previewHeight + 34) / 2
        result.push({
          x: Math.max(0, Math.min(areaWidth - width, preferredX)),
          y: Math.max(0, Math.min(areaHeight - previewHeight - 34, preferredY)),
          width: width,
          height: previewHeight + 34,
          preferredX: preferredX,
          preferredY: preferredY
        })
      }

      // Relax overlaps while softly pulling every thumbnail toward its real
      // desktop position. A shared scale preserves relative window area.
      for (var iteration = 0; iteration < 180; ++iteration) {
        for (var p = 0; p < total; ++p) {
          result[p].x += (result[p].preferredX - result[p].x) * 0.008
          result[p].y += (result[p].preferredY - result[p].y) * 0.008
        }
        for (var a = 0; a < total; ++a) {
          for (var b = a + 1; b < total; ++b) {
            var first = result[a]
            var second = result[b]
            var overlapX = Math.min(first.x + first.width + gap, second.x + second.width + gap)
              - Math.max(first.x, second.x)
            var overlapY = Math.min(first.y + first.height + gap, second.y + second.height + gap)
              - Math.max(first.y, second.y)
            if (overlapX <= 0 || overlapY <= 0) continue
            var firstCx = first.x + first.width / 2
            var firstCy = first.y + first.height / 2
            var secondCx = second.x + second.width / 2
            var secondCy = second.y + second.height / 2
            if (overlapX < overlapY) {
              var pushX = overlapX / 2 + 0.5
              var directionX = firstCx === secondCx ? ((a + b) % 2 ? -1 : 1) : (firstCx < secondCx ? -1 : 1)
              first.x += pushX * directionX
              second.x -= pushX * directionX
            } else {
              var pushY = overlapY / 2 + 0.5
              var directionY = firstCy === secondCy ? ((a + b) % 2 ? -1 : 1) : (firstCy < secondCy ? -1 : 1)
              first.y += pushY * directionY
              second.y -= pushY * directionY
            }
          }
        }
        for (var c = 0; c < total; ++c) {
          result[c].x = Math.max(0, Math.min(areaWidth - result[c].width, result[c].x))
          result[c].y = Math.max(0, Math.min(areaHeight - result[c].height, result[c].y))
        }
      }

      var collides = false
      for (var left = 0; left < total && !collides; ++left) {
        for (var right = left + 1; right < total; ++right) {
          if (result[left].x < result[right].x + result[right].width + gap
              && result[left].x + result[left].width + gap > result[right].x
              && result[left].y < result[right].y + result[right].height + gap
              && result[left].y + result[left].height + gap > result[right].y) {
            collides = true
            break
          }
        }
      }
      if (!collides || attempt === 8) return result
      scale *= 0.88
    }
    return []
  }

  function balancedLayout(items, areaWidth, areaHeight, gap, columns) {
    var total = items ? items.length : 0
    if (total === 0) return []

    var geometries = []
    var areas = []
    for (var i = 0; i < total; ++i) {
      var geometry = windowGeometry(items[i])
      geometries.push(geometry)
      areas.push(geometry.width * geometry.height)
    }
    var sortedAreas = areas.slice().sort(function(a, b) { return a - b })
    var medianArea = sortedAreas[Math.floor(sortedAreas.length / 2)] || 1
    var weights = []
    for (var w = 0; w < total; ++w) {
      // Preserve meaningful size differences without letting one maximized
      // window crush every smaller utility window.
      var weight = Math.pow(areas[w] / medianArea, 0.24)
      weights.push(Math.max(0.68, Math.min(1.38, weight)))
    }

    var rows = Math.max(1, Math.ceil(total / columns))
    var rowSlotHeight = (areaHeight - gap * (rows - 1)) / rows
    var result = []
    var index = 0
    for (var row = 0; row < rows; ++row) {
      var remaining = total - index
      var rowCount = Math.min(columns, remaining)
      if (row === 0 && rows > 1 && remaining - rowCount === 1 && rowCount > 2)
        rowCount--

      var weightedAspectSum = 0
      var maxWeight = 0
      for (var a = 0; a < rowCount; ++a) {
        var itemIndex = index + a
        var item = geometries[itemIndex]
        weightedAspectSum += (item.width / item.height) * weights[itemIndex]
        maxWeight = Math.max(maxWeight, weights[itemIndex])
      }
      var baseHeight = Math.min(
        (rowSlotHeight - 34) / Math.max(0.1, maxWeight),
        (areaWidth - gap * (rowCount - 1)) / Math.max(0.1, weightedAspectSum)
      )
      baseHeight = Math.max(82, baseHeight)

      var rowWidth = gap * (rowCount - 1)
      for (var b = 0; b < rowCount; ++b) {
        var widthIndex = index + b
        rowWidth += baseHeight * weights[widthIndex]
          * geometries[widthIndex].width / geometries[widthIndex].height
      }
      var x = (areaWidth - rowWidth) / 2
      for (var col = 0; col < rowCount; ++col) {
        var currentIndex = index + col
        var current = geometries[currentIndex]
        var previewHeight = baseHeight * weights[currentIndex]
        var tileWidth = previewHeight * current.width / current.height
        var y = row * (rowSlotHeight + gap) + (rowSlotHeight - previewHeight - 34) / 2
        result.push({ x: x, y: y, width: tileWidth, height: previewHeight + 34 })
        x += tileWidth + gap
      }
      index += rowCount
    }
    return result
  }

  onCountChanged: clampSelection()

  // Mission Control is a desktop-wide mode. Secondary outputs remain free of
  // thumbnails for now, but dim together with the interactive focused output.
  Variants {
    model: root.opened ? Quickshell.screens : []

    delegate: PanelWindow {
      required property var modelData
      screen: modelData
      visible: modelData !== root.targetScreen
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "io.github.aastrand.panorama.backdrop"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Rectangle {
        anchors.fill: parent
        color: Color.menu.scrim
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }
  }

  PanelWindow {
    id: panel
    screen: root.targetScreen
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "io.github.aastrand.panorama"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      id: keyArea
      anchors.fill: parent
      focus: true

      readonly property real outerMargin: Math.max(36, Math.min(width, height) * 0.07)
      readonly property real gap: 24
      readonly property real usableWidth: Math.max(1, width - outerMargin * 2)
      readonly property real usableHeight: Math.max(1, height - outerMargin * 2 - 46)
      readonly property real targetRatio: usableWidth / usableHeight
      readonly property int columns: root.count < 2 ? 1 : Math.max(1, Math.ceil(Math.sqrt(root.count * targetRatio)))
      readonly property int rows: Math.max(1, Math.ceil(root.count / columns))
      readonly property var layout: root.balancedLayout(root.windows, usableWidth, usableHeight, gap, columns)

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.dismiss()
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.focusWindow(root.selectedIndex)
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
          root.moveSelection(-1, 0, layout)
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
          root.moveSelection(1, 0, layout)
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
          root.moveSelection(0, -1, layout)
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
          root.moveSelection(0, 1, layout)
        } else {
          return
        }
        event.accepted = true
      }

      Text {
        visible: root.count === 0
        anchors.centerIn: parent
        text: "No windows on this workspace"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
      }

      Item {
        width: keyArea.usableWidth
        height: keyArea.usableHeight
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        Repeater {
          model: root.windows

          WindowTile {
            required property int index
            required property var modelData

            readonly property var placement: keyArea.layout[index] || ({ x: 0, y: 0, width: 1, height: 1 })
            x: placement.x
            y: placement.y
            width: placement.width
            height: placement.height
            toplevel: modelData
            selected: index === root.selectedIndex
            overlayOpen: root.opened
            showWorkspace: root.allWorkspaces
            appLibrary: root.shell && root.shell.appLibrary ? root.shell.appLibrary : null
            onHovered: root.selectedIndex = index
            onChosen: root.focusWindow(index)
          }
        }
      }

      Text {
        visible: root.count > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        text: (root.allWorkspaces ? "All workspaces" : "Current workspace")
          + "  ·  ←↑→↓ / hjkl to select  ·  Enter to open  ·  Esc to close"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
      }
    }
  }
}
