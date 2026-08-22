import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons

Item {
  id: root

  required property var toplevel
  property bool selected: false
  property bool overlayOpen: false
  property bool showWorkspace: false
  property var appLibrary: null
  signal chosen()
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
  readonly property real sourceAspect: {
    if (preview.hasContent && preview.sourceSize.height > 0)
      return preview.sourceSize.width / preview.sourceSize.height
    if (reportedSize && reportedSize.length >= 2 && reportedSize[1] > 0)
      return reportedSize[0] / reportedSize[1]
    return 1.6
  }
  readonly property real availableWidth: Math.max(1, width)
  readonly property real availableHeight: Math.max(1, height - 34)
  readonly property real previewWidth: Math.min(availableWidth, availableHeight * sourceAspect)
  readonly property real previewHeight: previewWidth / sourceAspect

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

  Item {
    id: content
    width: root.previewWidth
    height: root.previewHeight + 34
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

      Rectangle {
        anchors.fill: parent
        color: Color.background
        radius: Style.cornerRadius
        border.width: root.selected ? Math.max(2, Style.focusBorderWidth) : Style.normalBorderWidth
        border.color: root.selected ? Color.accent : Style.normalBorderColor
      }

      ScreencopyView {
        id: preview
        anchors.fill: parent
        anchors.margins: root.selected ? Math.max(2, Style.focusBorderWidth) : Style.normalBorderWidth
        captureSource: root.toplevel ? root.toplevel.wayland : null
        live: root.overlayOpen && captureSource !== null
        paintCursor: false
        constraintSize: Qt.size(frame.width, frame.height)
      }

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
        color: root.selected ? Color.accent : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.title
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hovered()
      onClicked: root.chosen()
    }
  }
}
