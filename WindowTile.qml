// One window in the overview: a live preview above an icon-and-title label.
//
// The tile is positioned and sized by Overlay.qml's layout, so it never picks
// its own place on screen. Within the box it is given it centres a preview at
// the window's true aspect ratio and reserves a theme-sized strip underneath
// for the label — the same height the layout function subtracts.
//
// Capture is best-effort: if the compositor gives no handle for a client, the
// preview stays empty and the app id plus "Preview unavailable" is shown
// instead, so the window is still selectable.
//
// Selection is presented, not owned: the tile reports hover and clicks through
// signals and renders whatever `selected` it is handed back.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons

Item {
  id: root

  // The Hyprland toplevel this tile represents.
  required property var toplevel
  // Set by the overlay; drives the accent outline and the slight scale-up.
  property bool selected: false
  // False while closing, which stops the live capture from running on a
  // surface nobody can see.
  property bool overlayOpen: false
  // In all-workspaces scope the label is prefixed with the workspace name.
  property bool showWorkspace: false
  // Omarchy's app library, when the host provided one; used for icon lookup.
  property var appLibrary: null
  // Measured by the overlay from the active theme's title font and icon size.
  required property real labelHeight

  // Emitted on click: asks the overlay to activate this window.
  signal chosen()
  // Emitted on hover: asks the overlay to move the selection here.
  signal hovered()

  readonly property var ipc: toplevel && toplevel.lastIpcObject ? toplevel.lastIpcObject : ({})
  readonly property var reportedSize: ipc.size || [16, 10]
  readonly property string appId: toplevel && toplevel.wayland ? String(toplevel.wayland.appId || "") : ""
  readonly property string appIconSource: resolveAppIcon()
  readonly property string displayTitle: {
    if (!toplevel) return "Window"
    var title = toplevel.title || appId || "Window"
    if (!showWorkspace || !toplevel.workspace) return title
    return "Workspace " + toplevel.workspace.name + "  ·  " + title
  }
  // Prefer the real captured frame's shape, fall back to what Hyprland
  // reported, then to a plausible landscape ratio for a window that has
  // neither yet.
  readonly property real sourceAspect: {
    if (preview.hasContent && preview.sourceSize.height > 0)
      return preview.sourceSize.width / preview.sourceSize.height
    if (reportedSize && reportedSize.length >= 2 && reportedSize[1] > 0)
      return reportedSize[0] / reportedSize[1]
    return 1.6
  }
  // Fit the preview inside the allotted box minus the label strip, keeping
  // the aspect ratio. The layout already sized the box to suit, so this
  // normally only absorbs rounding.
  readonly property real availableWidth: Math.max(1, width)
  readonly property real availableHeight: Math.max(1, height - labelHeight)
  readonly property real previewWidth: Math.min(availableWidth, availableHeight * sourceAspect)
  readonly property real previewHeight: previewWidth / sourceAspect

  // Map the Wayland app id to an icon path via the desktop-entry index,
  // matching on either the entry id or its StartupWMClass. Returns "" when
  // nothing matches and no themed icon exists, which hides the icon.
  function resolveAppIcon() {
    var wanted = appId.toLowerCase()
    if (!wanted) return ""
    var entries = DesktopEntries.applications.values || []
    for (var i = 0; i < entries.length; ++i) {
      var entry = entries[i]
      if (!entry) continue
      var id = String(entry.id || "").replace(/\.desktop$/i, "").toLowerCase()
      var startupClass = String(entry.startupClass || "").toLowerCase()
      if (id === wanted || startupClass === wanted) {
        var icon = String(entry.icon || "")
        if (!icon) return ""
        return appLibrary ? appLibrary.iconSource(icon) : Quickshell.iconPath(icon, true)
      }
    }
    // Many applications use their icon-theme name directly as app_id.
    return Quickshell.iconPath(appId, true)
  }

  // Preview plus label, centred in the box the layout assigned. The scale-up
  // is deliberately small: enough to read as a lift, not enough to overlap a
  // neighbouring tile across the layout gap.
  Item {
    id: content
    width: root.previewWidth
    height: root.previewHeight + root.labelHeight
    anchors.centerIn: parent
    scale: root.selected ? 1.025 : 1

    Behavior on scale {
      NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }

    Item {
      id: frame
      width: parent.width
      height: root.previewHeight
      anchors.top: parent.top
      clip: true

      // Backing plate and outline. The theme's focus border is used when
      // selected, widened to at least 2px so the accent reads at thumbnail
      // size, and the preview is inset by the same amount so the border is
      // never painted over.
      Rectangle {
        anchors.fill: parent
        color: Color.background
        radius: Style.cornerRadius
        border.width: root.selected ? Math.max(2, Style.focusBorderWidth) : Style.normalBorderWidth
        border.color: root.selected ? Color.accent : Style.normalBorderColor
      }

      // Live capture through Hyprland's toplevel-export protocol. `live` is
      // gated on the overview being open and a capture handle existing, so no
      // frames are pulled while the overlay is closed. The cursor is omitted
      // and the capture is constrained to the drawn size rather than the
      // window's full resolution.
      ScreencopyView {
        id: preview
        anchors.fill: parent
        anchors.margins: root.selected ? Math.max(2, Style.focusBorderWidth) : Style.normalBorderWidth
        captureSource: root.toplevel ? root.toplevel.wayland : null
        live: root.overlayOpen && captureSource !== null
        paintCursor: false
        constraintSize: Qt.size(frame.width, frame.height)
      }

      // Fallback for clients that expose no capture handle. Shown until the
      // first frame arrives, so it also covers the moment before capture
      // starts.
      Column {
        visible: !preview.hasContent
        anchors.centerIn: parent
        width: Math.max(1, parent.width - 24)
        spacing: 5

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          text: root.toplevel && root.toplevel.wayland ? root.toplevel.wayland.appId : "Window"
          textFormat: Text.PlainText
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Preview unavailable"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }
    }

    // Label strip: optional app icon plus the title, sized to its content and
    // centred, so the title elides from the middle rather than pushing the
    // icon off the tile.
    Row {
      id: labelRow
      width: Math.min(parent.width, (appIcon.visible ? appIcon.width + spacing : 0) + titleLabel.implicitWidth)
      height: Math.max(appIcon.visible ? appIcon.height : 0, titleLabel.implicitHeight)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: frame.bottom
      anchors.topMargin: 9
      spacing: Style.space(6)

      Image {
        id: appIcon
        // Icon lookups can resolve to a path that fails to load; collapse the
        // icon to zero width in that case so the title stays centred.
        visible: root.appIconSource.length > 0 && status !== Image.Error
        width: visible ? Style.font.iconLarge : 0
        height: width
        anchors.verticalCenter: parent.verticalCenter
        source: root.appIconSource
        sourceSize.width: width * Screen.devicePixelRatio
        sourceSize.height: height * Screen.devicePixelRatio
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
      }

      Text {
        id: titleLabel
        width: Math.max(1, labelRow.width - (appIcon.visible ? appIcon.width + labelRow.spacing : 0))
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideMiddle
        horizontalAlignment: Text.AlignHCenter
        text: root.displayTitle
        textFormat: Text.PlainText
        color: root.selected ? Color.accent : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.title
      }
    }

    // Covers the preview and the label. Hover only moves the selection; the
    // overlay decides what that means.
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hovered()
      onClicked: root.chosen()
    }
  }
}
