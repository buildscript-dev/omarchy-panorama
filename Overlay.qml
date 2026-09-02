// Panorama — the plugin's `overlay` entry point, named by manifest.json.
//
// Host contract (see shell.qml in omarchy-shell). The host owns this file's
// lifecycle and speaks exactly three things to it:
//
//   open(payloadJson)  called on every `summon`; the argument is the raw final
//                      CLI argument, so it may be JSON ({"scope":"all"}) or a
//                      bare word (all / current). Both forms are accepted.
//   close()            called on `hide`.
//   opened             read back by the host to decide what `toggle` does.
//
// The host also injects `omarchyPath`, `shell`, `manifest` and `pluginRegistry`
// after loading, and — because manifest.json does not set `keepLoaded` — it
// keeps this component instantiated only while the overview is open. Every
// summon therefore starts from a freshly constructed, default-valued root.
//
// Two layer-shell surfaces are used, both on the overlay layer:
//
//   io.github.aastrand.panorama           the focused monitor, thumbnails plus
//                                         exclusive keyboard focus
//   io.github.aastrand.panorama.backdrop  every other monitor, dimming only
//
// The optional blur layer rule in the README matches both namespaces.
//
// Colours, fonts and spacing come from the qs.Commons `Color` and `Style`
// singletons, so the overview inherits the active Omarchy theme rather than
// hardcoding any palette.
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

  // Part of the host contract: the shell reads `opened` to implement toggle.
  property bool opened: false
  property bool settingsOpen: false
  // Scope chosen by the payload: every workspace, or just the focused one.
  property bool allWorkspaces: false
  // Index into `windows` of the highlighted tile.
  property int selectedIndex: 0
  // Window awaiting activation across a workspace switch; see focusWindow().
  property var pendingActivation: null
  property int pendingWorkspaceId: -1
  // Snapshot where the request came from before an overlay on another output
  // can affect compositor focus. "Current workspace" always means this one.
  property var sourceWorkspace: null
  property string invocationScreenName: ""
  property string targetScreenName: ""
  property real motionProgress: 1

  // Persisted inline on this plugin's entry in Omarchy's shell.json.
  property var preferences: ({
    overviewScreen: "focused",
    overviewOutput: "",
    dimLevel: "normal",
    windowLabels: "icon-title",
    motionEnabled: true,
    motionDuration: 360
  })

  // The monitor that shows the thumbnails and takes keyboard focus. It is
  // resolved once at open from the payload, with the invocation
  // screen as a safe fallback when an output is disconnected.
  readonly property var targetScreen: {
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; ++i) {
      if (screens[i].name === targetScreenName) return screens[i]
    }
    for (var j = 0; j < screens.length; ++j) {
      if (screens[j].name === invocationScreenName) return screens[j]
    }
    return screens.length > 0 ? screens[0] : null
  }
  // Quickshell's global toplevel model can also contain foreign handles for
  // unmapped application helpers (for example tray and background windows).
  // They have no live Hyprland client to activate or export, so keep only
  // mapped clients with a workspace. This also prevents their placeholder
  // geometry and failed capture from appearing in the all-workspaces view.
  readonly property var windows: {
    var candidates = allWorkspaces
      ? Hyprland.toplevels.values
      : (sourceWorkspace ? sourceWorkspace.toplevels.values : [])
    if (!candidates) return []
    return candidates.filter(function(toplevel) {
      if (!toplevel || !toplevel.workspace) return false
      var ipc = toplevel.lastIpcObject || ({})
      return ipc.mapped === true
    })
  }
  readonly property int count: windows ? windows.length : 0
  readonly property real tileLabelHeight: preferences.windowLabels === "hidden"
    ? 0 : 9 + Math.max(Style.font.iconLarge, titleFontMetrics.height)
  readonly property color scrimColor: {
    var multiplier = preferences.dimLevel === "light" ? 0.6
      : (preferences.dimLevel === "dark" ? 1.45 : 1.0)
    return Qt.rgba(Color.menu.scrim.r, Color.menu.scrim.g, Color.menu.scrim.b,
      Math.min(0.92, Color.menu.scrim.a * multiplier))
  }
  readonly property var screenOptions: {
    var out = []
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; ++i)
      out.push({ value: String(screens[i].name), label: String(screens[i].name) })
    return out
  }

  FontMetrics {
    id: titleFontMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.title
  }

  // Windows can close while the overview is up, so keep the selection inside
  // the model rather than letting it dangle past the end.
  function clampSelection() {
    if (count === 0) selectedIndex = 0
    else selectedIndex = Math.max(0, Math.min(selectedIndex, count - 1))
  }

  function oneOf(value, allowed, fallback) {
    value = String(value || "")
    return allowed.indexOf(value) >= 0 ? value : fallback
  }

  function pluginEntry() {
    var entries = shell && shell.shellConfig && Array.isArray(shell.shellConfig.plugins)
      ? shell.shellConfig.plugins : []
    var pluginId = manifest && manifest.id ? String(manifest.id) : ""
    for (var i = 0; i < entries.length; ++i) {
      if (entries[i] && String(entries[i].id || "") === pluginId) return entries[i]
    }
    return ({})
  }

  function loadPreferences() {
    var entry = pluginEntry()
    preferences = {
      overviewScreen: oneOf(entry.overviewScreen, ["focused", "output"], "focused"),
      overviewOutput: String(entry.overviewOutput || ""),
      dimLevel: oneOf(entry.dimLevel, ["light", "normal", "dark"], "normal"),
      windowLabels: oneOf(entry.windowLabels,
        ["icon-title", "title", "hidden"], "icon-title"),
      motionEnabled: entry.motionEnabled === undefined ? true : entry.motionEnabled === true,
      motionDuration: Math.max(0, Number(entry.motionDuration === undefined ? 360 : entry.motionDuration) || 0)
    }
  }

  function savePreference(name, value) {
    var next = Object.assign({}, preferences)
    next[name] = value
    preferences = next

    if (!shell || typeof shell.updateEntryInline !== "function"
        || !manifest || !manifest.id) return
    var entry = pluginEntry()
    var persisted = ({})
    for (var key in entry) if (key !== "id") persisted[key] = entry[key]
    persisted[name] = value
    shell.updateEntryInline(manifest.id, persisted)
  }

  function resolveTargetScreenName(selection) {
    selection = String(selection || preferences.overviewScreen || "focused")
    if (selection === "focused") return invocationScreenName
    if (selection === "output")
      return String(preferences.overviewOutput || invocationScreenName)
    // A normal overview payload may temporarily name an output directly.
    return selection
  }

  function refreshTargetScreen() {
    targetScreenName = resolveTargetScreenName(preferences.overviewScreen)
  }

  // Host entry point. Called once per summon, before this instance has ever
  // been shown. The payload is accepted in either form the CLI can produce:
  // a JSON object with a `scope` key, or a bare scope word.
  function open(payloadJson) {
    var rawPayload = String(payloadJson || "")
    var scope = rawPayload
    var view = "overview"
    var screenSelection = ""
    try {
      var payload = JSON.parse(rawPayload || "{}")
      scope = String(payload.scope || "")
      view = String(payload.view || "overview")
      screenSelection = String(payload.screen || "")
    } catch (e) {}
    loadPreferences()
    Hyprland.refreshMonitors()
    sourceWorkspace = Hyprland.focusedWorkspace
    invocationScreenName = Hyprland.focusedMonitor
      ? String(Hyprland.focusedMonitor.name || "") : ""
    targetScreenName = resolveTargetScreenName(screenSelection)
    allWorkspaces = scope === "all"
    settingsOpen = view === "settings"
    // The cached toplevel list can be stale after windows opened or closed
    // since the last shell interaction, and it feeds both layout and count.
    Hyprland.refreshToplevels()
    selectedIndex = 0
    motionProgress = preferences.motionEnabled ? 0 : 1
    opened = true
    // Deferred: the toplevel refresh and the Repeater both need to settle
    // before the active window can be located and focus can be taken.
    Qt.callLater(function() {
      console.log("Panorama opened:", root.allWorkspaces ? "all workspaces" : "current workspace", root.count, "windows")
      var active = ToplevelManager.activeToplevel
      for (var i = 0; i < root.count; ++i) {
        if (root.windows[i].wayland === active || root.windows[i].activated) {
          root.selectedIndex = i
          break
        }
      }
      if (root.settingsOpen) settingsCard.forceActiveFocus()
      else keyArea.forceActiveFocus()
      if (!root.settingsOpen && root.preferences.motionEnabled) entranceDelay.restart()
    })
  }

  // Host entry point, called on `hide` / `toggle`. Kept separate from
  // dismiss() because the host owns this name; the two happen to do the same
  // thing, and hiding the surfaces is enough — the host unloads the component.
  function close() {
    opened = false
  }

  // Internal close, used by Esc, background clicks, and window activation.
  function dismiss(unloadFromHost) {
    opened = false
    if (unloadFromHost !== false && shell && typeof shell.hide === "function"
        && manifest && manifest.id)
      shell.hide(manifest.id)
  }

  // Activate the window at `index`, switching workspaces first when it lives
  // elsewhere. The overview is dismissed immediately so the target is not
  // raised behind a fading overlay.
  function focusWindow(index) {
    if (index < 0 || index >= count) return
    var target = windows[index]
    pendingActivation = target
    pendingWorkspaceId = target.workspace ? target.workspace.id : -1
    // Keep the component alive until the pending activation has completed.
    dismiss(false)
    if (target.workspace && (!Hyprland.focusedWorkspace
        || target.workspace.id !== Hyprland.focusedWorkspace.id)) {
      // Omarchy 4 configures Hyprland in Lua; fall back to the classic
      // dispatcher syntax for plain hyprland.conf setups.
      if (Hyprland.usingLua)
        Hyprland.dispatch("hl.dsp.focus({ workspace = " + target.workspace.id + " })")
      else
        Hyprland.dispatch("workspace " + target.workspace.id)
      // Activating during the workspace switch loses the request. Poll the
      // compositor state as a fallback in case no focus-change signal arrives.
      activationDelay.attemptsRemaining = 80
      activationDelay.restart()
    } else {
      activatePendingWindow()
    }
  }

  // Second half of focusWindow(): raise the stashed window. Safe to call with
  // nothing pending, and cleared first so a cancelled switch cannot replay.
  function activatePendingWindow() {
    var target = pendingActivation
    pendingActivation = null
    pendingWorkspaceId = -1
    activationDelay.stop()
    if (target && target.wayland) target.wayland.activate()
    dismiss()
  }

  function activateWhenWorkspaceReady() {
    if (!pendingActivation) {
      activationDelay.stop()
      return
    }
    var focused = Hyprland.focusedWorkspace
    if (pendingWorkspaceId < 0 || (focused && focused.id === pendingWorkspaceId)) {
      activatePendingWindow()
      return
    }
    activationDelay.attemptsRemaining--
    if (activationDelay.attemptsRemaining <= 0) {
      activationDelay.stop()
      pendingActivation = null
      pendingWorkspaceId = -1
      dismiss()
    }
  }

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { root.activateWhenWorkspaceReady() }
  }

  // Bound the wait at two seconds so a failed dispatch cannot leave stale state.
  Timer {
    id: activationDelay
    property int attemptsRemaining: 0
    interval: 25
    repeat: true
    onTriggered: root.activateWhenWorkspaceReady()
  }

  // Spatial selection: pick the nearest tile ahead in direction (dx, dy)
  // while staying closest to that axis, so arrow keys follow what the eye
  // sees rather than model order. Operates on laid-out rectangles, which is
  // why the caller passes its computed `layout` in.
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
      // Distance along the requested direction; anything level with or behind
      // the current tile is not a candidate.
      var forward = vx * dx + vy * dy
      if (forward <= 1) continue
      // Perpendicular offset, weighted up so a near-straight neighbour wins
      // over a closer one far off to the side.
      var sideways = Math.abs(vx * dy - vy * dx)
      var score = forward + sideways * 1.8
      if (score < bestScore) {
        bestScore = score
        best = i
      }
    }
    if (best >= 0) selectedIndex = best
  }

  // Real desktop geometry for a toplevel, from the last Hyprland IPC snapshot.
  // Everything is defended with fallbacks: `lastIpcObject` may be missing for a
  // window that appeared between refreshes, and layout must not divide by zero.
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

  function easeOutMotion(value) {
    var t = Math.max(0, Math.min(1, value))
    var inv = 1 - t
    return 1 - inv * inv * inv
  }

  function tileMotion(index) {
    return motionProgress
  }

  function targetHyprMonitor() {
    var monitors = Hyprland.monitors && Hyprland.monitors.values ? Hyprland.monitors.values : []
    for (var i = 0; i < monitors.length; ++i)
      if (String(monitors[i].name || "") === targetScreenName) return monitors[i]
    return Hyprland.focusedMonitor
  }

  function sourcePlacement(window, areaWidth, areaHeight) {
    var geometry = windowGeometry(window)
    var monitor = targetHyprMonitor()
    var x = geometry.x - (monitor ? Number(monitor.x || 0) : 0)
    var y = geometry.y - (monitor ? Number(monitor.y || 0) : 0)
    if (x >= areaWidth) x = areaWidth - Math.min(geometry.width, 80)
    else if (x + geometry.width <= 0) x = -geometry.width + Math.min(geometry.width, 80)
    if (y >= areaHeight) y = areaHeight - Math.min(geometry.height, 80)
    else if (y + geometry.height <= 0) y = -geometry.height + Math.min(geometry.height, 80)
    return { x: x, y: y, width: geometry.width, height: geometry.height }
  }

  Timer {
    id: entranceDelay
    interval: 80
    repeat: false
    onTriggered: entranceAnimation.restart()
  }

  NumberAnimation {
    id: entranceAnimation
    target: root
    property: "motionProgress"
    from: 0
    to: 1
    duration: root.preferences.motionDuration
    easing.type: Easing.Linear
  }

  // The layout the overview uses: a centred grid of rows in model order.
  // Every tile keeps its true aspect ratio, and a damped area weight lets
  // bigger windows claim more room without squeezing the rest out.
  //
  // Returns one { x, y, width, height } per item, positioned inside a
  // (areaWidth x areaHeight) box; `height` includes the theme-sized label strip.
  function balancedLayout(items, areaWidth, areaHeight, gap, columns) {
    var total = items ? items.length : 0
    if (total === 0) return []

    // Each row needs its label strip in addition to its preview. Increase the
    // column count when necessary so those strips and the gaps fit.
    var labelHeight = root.tileLabelHeight
    var maxRows = Math.max(1, Math.floor((areaHeight + gap) / (labelHeight + gap)))
    columns = Math.max(columns, Math.ceil(total / maxRows))
    var rows = Math.max(1, Math.ceil(total / columns))
    // At extreme counts, shrink spacing before it alone exceeds either axis.
    var horizontalGap = columns > 1 ? areaWidth / (columns - 1) : gap
    var verticalGap = rows > 1 ? Math.max(0, areaHeight - rows * labelHeight) / (rows - 1) : gap
    var layoutGap = Math.max(0, Math.min(gap, horizontalGap, verticalGap))

    var geometries = []
    var areas = []
    for (var i = 0; i < total; ++i) {
      var geometry = windowGeometry(items[i])
      geometries.push(geometry)
      areas.push(geometry.width * geometry.height)
    }
    // Median rather than mean: one maximized window should not redefine
    // "normal size" for every other tile.
    var sortedAreas = areas.slice().sort(function(a, b) { return a - b })
    var medianArea = sortedAreas[Math.floor(sortedAreas.length / 2)] || 1
    var weights = []
    for (var w = 0; w < total; ++w) {
      // Preserve meaningful size differences without letting one maximized
      // window crush every smaller utility window.
      var weight = Math.pow(areas[w] / medianArea, 0.24)
      weights.push(Math.max(0.68, Math.min(1.38, weight)))
    }

    var rowSlotHeight = (areaHeight - layoutGap * (rows - 1)) / rows
    var result = []
    var index = 0
    for (var row = 0; row < rows; ++row) {
      var remaining = total - index
      var rowCount = Math.min(columns, remaining)
      // Borrow one tile from the first row rather than leaving a lone window
      // stranded on the last one.
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
      // The unweighted preview height for this row: whichever of the row's
      // height budget and its total width budget binds first. Do not impose a
      // minimum here: it would override the fit constraint on crowded outputs.
      var baseHeight = Math.max(0, Math.min(
        (rowSlotHeight - labelHeight) / Math.max(0.1, maxWeight),
        (areaWidth - layoutGap * (rowCount - 1)) / Math.max(0.1, weightedAspectSum)
      ))

      // Measure the row so it can be centred horizontally.
      var rowWidth = layoutGap * (rowCount - 1)
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
        var y = row * (rowSlotHeight + layoutGap) + (rowSlotHeight - previewHeight - labelHeight) / 2
        result.push({ x: x, y: y, width: tileWidth, height: previewHeight + labelHeight })
        x += tileWidth + layoutGap
      }
      index += rowCount
    }
    return result
  }

  onCountChanged: clampSelection()

  // Mission Control is a desktop-wide mode. Secondary outputs remain free of
  // thumbnails for now, but dim together with the interactive focused output.
  // These backdrops take no keyboard focus, so Esc keeps working, and they use
  // the `.backdrop` namespace the README's blur rule also matches.
  Variants {
    model: root.opened ? Quickshell.screens : []

    delegate: PanelWindow {
      required property var modelData
      screen: modelData
      // The focused monitor is covered by the interactive panel below.
      visible: modelData !== root.targetScreen
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "io.github.aastrand.panorama.backdrop"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Rectangle {
        anchors.fill: parent
        color: root.scrimColor
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }
  }

  // The interactive surface: dimming, thumbnails, key handling. Exclusive
  // keyboard focus is what lets hjkl and Esc reach the overview instead of
  // the window underneath, and it is dropped as soon as the overview closes.
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
      color: root.scrimColor
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    // Owns both the key handling and the geometry the layout is computed in.
    Item {
      id: keyArea
      anchors.fill: parent
      focus: true
      visible: !root.settingsOpen

      // Layout inputs. 46 reserves room for the hint line at the bottom, and
      // `columns` picks a grid roughly matching the screen's aspect ratio so
      // rows stay full rather than tall and narrow.
      readonly property real outerMargin: Math.max(36, Math.min(width, height) * 0.07)
      readonly property real gap: 24
      readonly property real usableWidth: Math.max(1, width - outerMargin * 2)
      readonly property real usableHeight: Math.max(1, height - outerMargin * 2 - 46)
      readonly property real targetRatio: usableWidth / usableHeight
      readonly property int columns: root.count < 2 ? 1 : Math.max(1, Math.ceil(Math.sqrt(root.count * targetRatio)))
      readonly property int rows: Math.max(1, Math.ceil(root.count / columns))
      readonly property var layout: root.balancedLayout(root.windows, usableWidth, usableHeight, gap, columns)

      // BeforeItem so plain letters reach this handler rather than any focused
      // child. Unhandled keys return early and stay unaccepted.
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
        text: root.allWorkspaces ? "No open windows" : "No windows on this workspace"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
      }

      Item {
        width: keyArea.usableWidth
        height: keyArea.usableHeight
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        // One tile per window, positioned from the shared layout by index.
        Repeater {
          model: root.windows

          WindowTile {
            required property int index
            required property var modelData

            // The layout is recomputed on resize and on model changes; a tile
            // can briefly outlive its entry, so fall back to a harmless box.
            readonly property var placement: keyArea.layout[index] || ({ x: 0, y: 0, width: 1, height: 1 })
            readonly property var source: root.sourcePlacement(modelData, keyArea.width, keyArea.height)
            readonly property real motion: root.easeOutMotion(root.tileMotion(index))
            readonly property real areaX: (keyArea.width - keyArea.usableWidth) / 2
            readonly property real areaY: (keyArea.height - keyArea.usableHeight) / 2
            x: (source.x - areaX) + (placement.x - (source.x - areaX)) * motion
            y: (source.y - areaY) + (placement.y - (source.y - areaY)) * motion
            width: placement.width
            height: placement.height
            opacity: 0.55 + 0.45 * motion
            transformOrigin: Item.Center
            scale: 0.94 + 0.06 * motion
            toplevel: modelData
            selected: index === root.selectedIndex
            overlayOpen: root.opened
            showWorkspace: root.allWorkspaces
            appLibrary: root.shell && root.shell.appLibrary ? root.shell.appLibrary : null
            labelHeight: root.tileLabelHeight
            labelMode: root.preferences.windowLabels
            onHovered: {
              if (root.motionProgress >= 1) root.selectedIndex = index
            }
            onChosen: root.focusWindow(index)
          }
        }
      }

      // Scope indicator and key hints, in the margin reserved by usableHeight.
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

    SettingsCard {
      id: settingsCard
      visible: root.settingsOpen
      anchors.centerIn: parent
      width: Math.min(560, Math.max(320, panel.width - 48))
      screenMode: root.preferences.overviewScreen
      screenOutput: root.preferences.overviewOutput
      dimLevel: root.preferences.dimLevel
      labelMode: root.preferences.windowLabels
      motionEnabled: root.preferences.motionEnabled
      outputOptions: root.screenOptions

      onScreenModeChosen: function(value) {
        root.savePreference("overviewScreen", value)
        root.refreshTargetScreen()
      }
      onScreenOutputChosen: function(value) {
        root.savePreference("overviewOutput", value)
        root.refreshTargetScreen()
      }
      onDimLevelChosen: function(value) { root.savePreference("dimLevel", value) }
      onLabelModeChosen: function(value) { root.savePreference("windowLabels", value) }
      onMotionEnabledChosen: function(value) { root.savePreference("motionEnabled", value) }
      onDone: root.dismiss()
    }
  }
}
