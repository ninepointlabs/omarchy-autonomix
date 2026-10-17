import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The panel's About page: who made Autonomix, its version and license, where
// to get help, and what it does with your data. Panel.qml swaps it in for the
// app list (info button in the header, or the `about` IPC call).
Column {
  id: root

  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property string version: ""
  property string licenseText: ""
  property string cliVersion: ""
  property bool showLicense: false
  property string notice: ""

  signal backRequested()

  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string quickshellVersion: Model.probedVersion(function(a, b) { return Quickshell.hasVersion(a, b) }, 0)
  readonly property string qtVersion: Model.probedVersion(function(a, b) { return Quickshell.hasQtVersion(a, b) }, 6)
  readonly property string details: Model.aboutDetails(root.version, root.quickshellVersion, root.qtVersion, root.cliVersion,
    (Quickshell.env("XDG_CURRENT_DESKTOP") || "unknown desktop") + ", " + Qt.platform.pluginName)
  readonly property real labelWidth: Style.space(72)

  function copy(text, what) {
    Quickshell.clipboardText = text
    root.notice = what + " copied"
    noticeTimer.restart()
  }

  spacing: Style.space(10)
  onVisibleChanged: if (!visible) { root.showLicense = false; root.notice = "" }

  Timer { id: noticeTimer; interval: 2500; onTriggered: root.notice = "" }

  component AboutLabel: Text {
    width: root.labelWidth
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  component AboutValue: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.Wrap
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(heading.implicitHeight, backButton.implicitHeight)

    Row {
      id: heading
      anchors.left: parent.left
      anchors.right: backButton.left
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(12)

      OpticalGlyph {
        id: appIcon
        width: Style.space(40)
        height: width
        anchors.verticalCenter: parent.verticalCenter
        text: "󰏗"
        fontFamily: root.fontFamily
        fontSize: Style.space(30)
        color: root.accent
      }

      Column {
        width: parent.width - appIcon.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          textFormat: Text.PlainText
          text: Model.ABOUT.name
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }
        AboutValue { width: parent.width; text: Model.ABOUT.tagline }
        Text {
          objectName: "aboutVersion"
          textFormat: Text.PlainText
          text: "Version " + (root.version || "unknown")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    PanelActionButton {
      id: backButton
      objectName: "aboutBack"
      anchors.right: parent.right
      anchors.top: parent.top
      iconText: "󰅖"
      tooltipText: "Back (Esc)"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.backRequested()
    }
  }

  PanelSeparator { foreground: root.foreground }

  Grid {
    id: facts
    width: parent.width
    columns: 2
    columnSpacing: Style.space(10)
    rowSpacing: Style.space(8)
    readonly property real valueWidth: width - root.labelWidth - columnSpacing

    AboutLabel { text: "Made by" }
    AboutValue { width: facts.valueWidth; text: Model.ABOUT.organization }

    AboutLabel { text: "Created" }
    AboutValue { width: facts.valueWidth; text: Model.ABOUT.created }

    AboutLabel { text: "License" }
    Row {
      width: facts.valueWidth
      spacing: Style.space(6)
      AboutValue {
        anchors.verticalCenter: parent.verticalCenter
        text: Model.ABOUT.license + ", " + Model.ABOUT.copyright
      }
      Button {
        objectName: "aboutLicense"
        text: root.showLicense ? "Hide" : "Read it"
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        onClicked: root.showLicense = !root.showLicense
      }
    }

    AboutLabel { text: "Support" }
    Column {
      width: facts.valueWidth
      spacing: Style.space(4)
      AboutValue { text: Model.ABOUT.supportEmail }
      Flow {
        width: parent.width
        spacing: Style.space(6)
        Button {
          text: "Email"
          tooltipText: "Opens your mail app with the version details filled in"
          bordered: true
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          onClicked: Qt.openUrlExternally(Model.supportMailto(root.version, root.details))
        }
        Button {
          text: "Copy"
          bordered: true
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          onClicked: root.copy(Model.ABOUT.supportEmail, "Address")
        }
        Button {
          text: "Copy version details"
          bordered: true
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          onClicked: root.copy(root.details, "Version details")
        }
      }
    }

    AboutLabel { text: "Privacy" }
    Text {
      objectName: "aboutPrivacy"
      width: facts.valueWidth
      textFormat: Text.PlainText
      text: Model.PRIVACY
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
    }

    AboutLabel { text: "Built with" }
    Text {
      objectName: "aboutBuiltWith"
      width: facts.valueWidth
      textFormat: Text.PlainText
      text: Model.builtWith(root.quickshellVersion, root.qtVersion, root.cliVersion)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
    }
  }

  Text {
    width: parent.width
    visible: root.notice !== ""
    textFormat: Text.PlainText
    text: root.notice
    color: root.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    objectName: "aboutLicenseText"
    width: parent.width
    visible: root.showLicense
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    text: Model.reflowLicense(root.licenseText) || "LICENSE could not be read from the plugin folder."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
