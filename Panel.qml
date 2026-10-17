import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "ninepointlabs.autonomix"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var sharedService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property var service: sharedService || localService

  function pushSettings() { if (service) service.settings = settings }
  onSettingsChanged: pushSettings()
  onServiceChanged: pushSettings()
  Component.onCompleted: pushSettings()

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  readonly property int revision: service ? service.revision : 0
  readonly property var apps: service && revision >= 0 ? service.apps : []
  readonly property int updateCount: service ? service.updateCount : 0
  readonly property bool busy: service ? service.busy : false
  readonly property bool checking: service ? service.checking : false
  readonly property string lastError: service ? service.lastError : ""
  readonly property string actionStatus: service ? service.actionStatus : ""
  readonly property string statusText: lastError !== "" ? lastError : actionStatus
  readonly property bool statusIsError: lastError !== ""

  // The repo whose remove button was clicked once and is waiting for a
  // second click to confirm.
  property string confirmRemove: ""

  readonly property string selfRepo: "ninepointlabs/autonomix-cli"

  // The About page replaces the app list inside the same panel. Its files
  // (manifest.json for the version, LICENSE) are read only once it is shown.
  property bool showAbout: false
  property bool aboutLoaded: false
  readonly property string pluginDir: {
    var text = String(Qt.resolvedUrl("."))
    if (text.indexOf("file://") === 0) text = decodeURIComponent(text.substring(7))
    return text.length > 1 && text.charAt(text.length - 1) === "/" ? text.substring(0, text.length - 1) : text
  }

  function setAbout(on) {
    showAbout = !!on
    if (showAbout) { aboutLoaded = true; panelFlick.contentY = 0 }
  }

  function showAboutPage() {
    setAbout(true)
    if (!opened) open()
  }

  FileView { id: manifestFile; path: root.aboutLoaded ? root.pluginDir + "/manifest.json" : ""; printErrors: false }
  FileView { id: licenseFile; path: root.aboutLoaded ? root.pluginDir + "/LICENSE" : ""; printErrors: false }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function submitAdd() {
    if (!service) return
    if (service.add(addField.text)) addField.text = ""
  }

  function requestRemove(app) {
    if (confirmRemove === app.repo) {
      confirmRemove = ""
      if (service) service.remove(app)
      return
    }
    confirmRemove = app.repo
    confirmTimer.restart()
  }

  implicitWidth: 1
  implicitHeight: 1

  onOpenedChanged: {
    if (!opened) { confirmRemove = ""; showAbout = false; return }
    if (service) service.list()
  }

  Timer {
    id: confirmTimer
    interval: 3000
    onTriggered: root.confirmRemove = ""
  }

  Service {
    id: localService
    active: false
  }
  Timer {
    interval: 2500
    running: root.bar !== null && root.sharedService === null && !localService.active
    onTriggered: if (root.sharedService === null) localService.active = true
  }
  onSharedServiceChanged: if (sharedService !== null && localService.active) localService.active = false

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: root.showAbout ? keyCatcher : addField
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(panelFlick.contentHeight + Style.space(24), Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: addField.activeFocus
      // Esc steps back out of About before it closes the panel.
      onCloseRequested: root.showAbout ? root.setAbout(false) : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

    Flickable {
      id: panelFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: root.showAbout ? aboutView.implicitHeight : mainColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    AboutView {
      id: aboutView
      objectName: "aboutView"
      visible: root.showAbout
      width: panelFlick.width
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      version: Model.manifestVersion(manifestFile.loaded ? manifestFile.text() : "")
      licenseText: licenseFile.loaded ? licenseFile.text() : ""
      cliVersion: root.service ? root.service.cliVersion : ""
      onBackRequested: root.setAbout(false)
    }

    Column {
      id: mainColumn
      visible: !root.showAbout
      width: panelFlick.width
      spacing: Style.space(10)

      // Header: title, status line, check button.
      Item {
        width: parent.width
        implicitHeight: Math.max(titleColumn.implicitHeight, checkButton.implicitHeight)

        Column {
          id: titleColumn
          anchors.left: parent.left
          anchors.right: aboutButton.left
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            text: "AUTONOMIX"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.statusText !== "" ? root.statusText
              : root.updateCount === 0 ? "Everything is up to date"
              : root.updateCount + (root.updateCount === 1 ? " update available" : " updates available")
            color: root.statusIsError ? Color.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }
        }

        PanelActionButton {
          id: aboutButton
          objectName: "aboutButton"
          anchors.right: checkButton.left
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰋽"
          tooltipText: "About Autonomix"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.setAbout(true)
        }

        PanelActionButton {
          id: checkButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰑐"
          tooltipText: "Check GitHub for updates"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: !root.checking
          opacity: root.checking ? 0.5 : 1
          onClicked: if (root.service) root.service.check()
        }
      }

      Button {
        visible: root.updateCount > 1
        width: parent.width
        text: "Update all (" + root.updateCount + ")"
        bordered: true
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        enabled: !root.busy
        onClicked: if (root.service) root.service.updateAll()
      }

      TextField {
        id: addField
        width: parent.width
        placeholderText: "Track a repo: owner/repo or GitHub URL"
        foreground: root.foreground
        accent: root.accent
        Keys.onReturnPressed: root.submitAdd()
        Keys.onEnterPressed: root.submitAdd()
        Keys.onEscapePressed: function(event) {
          if (addField.text !== "") { addField.text = ""; event.accepted = true }
          else root.close()
        }
      }

      PanelSeparator { foreground: root.foreground }

      Text {
        visible: root.apps.length === 0
        width: parent.width
        textFormat: Text.PlainText
        text: root.service && root.service.loaded ? "No apps tracked yet. Add a GitHub repo above." : "Loading…"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
      }

      Repeater {
        model: root.apps

        Rectangle {
          id: appRow
          required property var modelData
          readonly property string action: Model.actionFor(modelData)
          readonly property bool working: root.service ? root.service.isBusyWith(modelData.repo) : false
          readonly property bool removable: modelData.repo !== root.selfRepo

          width: parent.width
          height: rowLayout.implicitHeight + Style.space(10)
          radius: Style.cornerRadius
          color: rowMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.service) root.service.openRelease(appRow.modelData)
          }

          RowLayout {
            id: rowLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(4)
            spacing: Style.space(8)

            Column {
              Layout.fillWidth: true
              spacing: Style.space(1)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: appRow.modelData.name
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: Model.subtitle(appRow.modelData)
                color: appRow.modelData.status === "update_available" ? root.accent
                  : appRow.modelData.status === "failed" ? Color.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            Button {
              visible: appRow.action !== "" || appRow.working
              text: appRow.working ? "Working…" : (appRow.action === "update" ? "Update" : "Install")
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              enabled: !appRow.working
              onClicked: {
                if (!root.service) return
                if (appRow.action === "update") root.service.update(appRow.modelData)
                else root.service.install(appRow.modelData)
              }
            }

            PanelActionButton {
              visible: appRow.removable
              enabled: !appRow.working
              iconText: root.confirmRemove === appRow.modelData.repo ? "󰄬" : "󰆴"
              tooltipText: root.confirmRemove === appRow.modelData.repo
                ? "Click again to stop tracking (doesn't uninstall)"
                : "Stop tracking " + appRow.modelData.name
              foreground: root.confirmRemove === appRow.modelData.repo ? Color.urgent : root.dim
              fontFamily: root.fontFamily
              onClicked: root.requestRemove(appRow.modelData)
            }
          }
        }
      }
    }
    }
    }
  }
}
