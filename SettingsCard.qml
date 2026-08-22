// Panorama's compact preferences view. Overlay.qml owns persistence and
// behavior; this component only renders controls and emits user choices.
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string screenMode: "focused"
  property string screenOutput: ""
  property string dimLevel: "normal"
  property string labelMode: "icon-title"
  property var outputOptions: []

  signal screenModeChosen(string value)
  signal screenOutputChosen(string value)
  signal dimLevelChosen(string value)
  signal labelModeChosen(string value)
  signal done()

  implicitHeight: cardColumn.implicitHeight + Style.spacing.panelPadding * 2
  height: implicitHeight
  focus: true
  Keys.onEscapePressed: root.done()

  BorderSurface {
    anchors.fill: parent
    color: Color.menu.background
    borderSpec: Border.localOrSurfaceSpec("menu", "border", Color.menu.border,
      Color.menu.border, Style.normalBorderWidth)
    radius: Style.cornerRadius

    MouseArea { anchors.fill: parent }

    Column {
      id: cardColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.panelPadding
      spacing: Style.spacing.panelGap

      Text {
        text: "Panorama settings"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      Text {
        width: parent.width
        text: "Changes are saved immediately in Omarchy's shell configuration."
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Dropdown {
        width: parent.width
        label: "Overview display"
        value: root.screenMode
        options: [
          { value: "focused", label: "Focused display" },
          { value: "output", label: "Specific display" }
        ]
        onChanged: function(value) { root.screenModeChosen(value) }
      }

      Dropdown {
        visible: root.screenMode === "output"
        width: parent.width
        label: "Display output"
        value: root.screenOutput
        options: root.outputOptions
        onChanged: function(value) { root.screenOutputChosen(value) }
      }

      Dropdown {
        width: parent.width
        label: "Background dimming"
        value: root.dimLevel
        options: [
          { value: "light", label: "Light" },
          { value: "normal", label: "Normal" },
          { value: "dark", label: "Dark" }
        ]
        onChanged: function(value) { root.dimLevelChosen(value) }
      }

      Dropdown {
        width: parent.width
        label: "Window labels"
        value: root.labelMode
        options: [
          { value: "icon-title", label: "Icon and title" },
          { value: "title", label: "Title only" },
          { value: "hidden", label: "Hidden" }
        ]
        onChanged: function(value) { root.labelModeChosen(value) }
      }

      Button {
        anchors.right: parent.right
        text: "Done"
        bordered: true
        focusable: true
        onClicked: root.done()
      }
    }
  }
}
