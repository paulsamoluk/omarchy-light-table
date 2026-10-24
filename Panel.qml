import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Light Table — thumbnails of the newest photos in the folders this widget
// watches. State and the actual work (scanning, previews, xdg-open) belong to
// BarWidget.qml; this panel is the view and calls back through `hostWidget`.
Panel {
  id: root
  moduleName: "psamoluk.light-table"
  ipcTarget: "psamoluk.light-table"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var host: hostWidget
  readonly property var barIdentity: hostWidget || root
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property var items: host ? (host.images || []) : []
  readonly property var folders: host ? (host.folders || []) : []
  readonly property int count: items.length

  property int cursorIndex: 0
  property string notice: ""
  property string pendingPath: ""

  readonly property int columns: Math.max(3, Math.floor(grid.width / Style.space(108)))

  function moveCursor(dx, dy) {
    if (count === 0) return
    var next = cursorIndex
    if (dx !== 0) next = cursorIndex + dx
    else if (dy !== 0) next = cursorIndex + dy * columns
    if (next < 0 || next >= count) return
    cursorIndex = next
    grid.positionViewAtIndex(next, GridView.Contain)
  }

  function activateCursor() {
    if (count === 0) return
    openAt(cursorIndex)
  }

  function openAt(index) {
    if (index < 0 || index >= count) return
    var item = items[index]
    if (!item) return
    if (host && host.openImage) host.openImage(item.path)
  }

  function openFolder(path) {
    if (!path) return
    if (host && host.openFolder) host.openFolder(path)
  }

  function removeFolder(path) {
    notice = ""
    if (host && host.removeFolder) host.removeFolder(path)
  }

  function toggleSort() {
    if (!host || !host.setSort) return
    host.setSort(host.sortMode === "name" ? "newest" : "name")
  }

  function submitDraft() {
    var path = Model.normalize(pathField.text, home)
    if (path === "") {
      notice = "Type a folder path first."
      return
    }
    pendingPath = path
    probeProc.command = ["/usr/bin/test", "-d", path]
    probeProc.running = true
  }

  function toggleSubfolders() {
    if (!host || !host.setSubfolders) return
    host.setSubfolders(host.subfolders !== true)
  }

  function focusPathField() {
    notice = ""
    pathField.forceActiveFocus()
  }

  onOpenedChanged: {
    if (!opened) return
    cursorIndex = 0
    pathField.text = ""
    notice = ""
    if (host && host.rescan) host.rescan()
  }

  Process {
    id: probeProc
    onExited: function(code) {
      if (code !== 0) {
        root.notice = "Not a folder: " + Model.tilde(root.pendingPath, root.home)
        return
      }
      if (host && host.addFolder) host.addFolder(root.pendingPath)
      pathField.text = ""
      root.notice = ""
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: pathField.activeFocus
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onReturnRequested: root.activateCursor()
      onTextKey: function(text) {
        if (text === "/" || text === "a" || text === "A") root.focusPathField()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          iconComponent: heroGlyph
          title: "Light Table"
          meta: Model.metaLine(root.count, root.folders.length, host ? host.warming === true : false)
          detail: ""
          foreground: root.barForeground
          fontFamily: root.fontFamily
        }

        // --------------------------- watched folders ---------------------------
        Column {
          id: folderSection
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            implicitHeight: Math.max(foldersHeader.implicitHeight, subfolderToggle.implicitHeight)

            PanelSectionHeader {
              id: foldersHeader
              text: "WATCHED FOLDERS"
              foreground: root.barForeground
              fontFamily: root.fontFamily
            }

            Row {
              id: subfolderToggle
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Include subfolders"
                color: Util.alpha(root.barForeground, 0.7)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              ToggleSwitch {
                anchors.verticalCenter: parent.verticalCenter
                checked: host ? host.subfolders === true : true
                onToggled: root.toggleSubfolders()
              }
            }
          }

          Flow {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.folders

              delegate: Row {
                required property var modelData
                spacing: 0

                Button {
                  text: Model.tilde(modelData, root.home)
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  foreground: root.barForeground
                  bordered: true
                  tooltipText: "Open " + modelData
                  onClicked: root.openFolder(modelData)
                }

                PanelActionButton {
                  iconText: "\uF00D"
                  foreground: root.barForeground
                  fontSize: Style.font.caption
                  tooltipText: "Stop watching this folder"
                  onClicked: root.removeFolder(modelData)
                }
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: pathField
              width: parent.width - addButton.width - parent.spacing
              height: Style.space(30)
              foreground: root.barForeground
              selectByMouse: true
              placeholderText: "/run/media/… or ~/Pictures/shoot"
              onAccepted: root.submitDraft()
              onTextEdited: if (root.notice !== "") root.notice = ""
              Keys.onEscapePressed: keyCatcher.forceActiveFocus()
            }

            Button {
              id: addButton
              text: "Add folder"
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              foreground: root.barForeground
              bordered: true
              onClicked: root.submitDraft()
            }
          }

          Text {
            width: parent.width
            visible: root.notice !== ""
            text: root.notice
            color: root.barForeground
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // -------------------------------- photos --------------------------------
        Column {
          id: photoSection
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            implicitHeight: Math.max(sectionHeader.implicitHeight, sortButton.implicitHeight)

            PanelSectionHeader {
              id: sectionHeader
              text: host && host.sortMode === "name" ? "BY NAME" : "NEWEST FIRST"
              foreground: root.barForeground
              fontFamily: root.fontFamily
            }

            Button {
              id: sortButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: host && host.sortMode === "name" ? "Newest first" : "By name"
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              foreground: root.barForeground
              bordered: true
              onClicked: root.toggleSort()
            }
          }

          GridView {
            id: grid
            // Inset from the card edges: without it the outer columns sit flush
            // against the border while the inner gaps get 6px, and the last
            // tile looks clipped.
            x: Style.space(5)
            width: parent.width - Style.space(10)
            height: Style.space(296)
            visible: root.count > 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            cellWidth: Math.floor(width / root.columns)
            cellHeight: cellWidth + Style.space(18)
            model: root.items

            delegate: Item {
              id: cell
              required property var modelData
              required property int index

              width: grid.cellWidth
              height: grid.cellHeight

              readonly property bool selected: index === root.cursorIndex

              Rectangle {
                id: frame
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(3)
                height: width
                radius: Style.cornerRadius
                color: Util.alpha(root.barForeground, 0.06)
                border.width: cell.selected ? Math.max(1, Style.space(2)) : 1
                border.color: cell.selected ? Color.accent : Util.alpha(root.barForeground, 0.16)
                clip: true

                Image {
                  id: thumbnail
                  anchors.fill: parent
                  source: cell.modelData && cell.modelData.preview ? Util.fileUrl(cell.modelData.preview) : ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: true
                  smooth: true
                  visible: status === Image.Ready
                }

                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(2)
                  visible: thumbnail.status !== Image.Ready

                  OpticalGlyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\uF03E"
                    fontFamily: root.fontFamily
                    fontSize: Style.font.title
                    color: Util.alpha(root.barForeground, 0.55)
                  }

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Model.glyphFor(cell.modelData ? cell.modelData.path : "")
                    color: Util.alpha(root.barForeground, 0.45)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: Math.round(parent.height / 3)
                  visible: mouse.containsMouse || cell.selected
                  gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Util.alpha(Color.background, 0.75) }
                  }
                }

                MouseArea {
                  id: mouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.cursorIndex = index
                    root.openAt(index)
                  }
                }
              }

              Text {
                id: caption
                anchors.top: frame.bottom
                anchors.topMargin: Style.space(2)
                width: frame.width
                x: Style.space(3)
                text: cell.modelData ? cell.modelData.name : ""
                color: cell.selected ? root.barForeground : Util.alpha(root.barForeground, 0.72)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignHCenter
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(180)
            visible: root.count === 0
            radius: Style.cornerRadius
            color: Util.alpha(root.barForeground, 0.04)

            Column {
              anchors.centerIn: parent
              spacing: Style.space(6)

              OpticalGlyph {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "\uF03E"
                fontFamily: root.fontFamily
                fontSize: Style.font.display
                color: Util.alpha(root.barForeground, 0.5)
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: host && host.scanning === true ? "Looking for photos…" : "No photos in these folders yet"
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.space(340)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: (host && host.subfolders === false)
                  ? "No photos at the top level. Turn on “Include subfolders” if your shots live in folders inside this one."
                  : "Add a folder above — anything that lands there, including RAW files, shows up here as a thumbnail."
                color: Util.alpha(root.barForeground, 0.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Click a photo to open it  ·  arrows move  ·  Enter opens  ·  Esc closes"
          color: Util.alpha(root.barForeground, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  Component {
    id: heroGlyph

    // A bare OpticalGlyph has no implicit size (its Text is centred inside a
    // zero-width item), so PanelHero anchors it at the content edge and the
    // glyph paints half outside it — jammed against the card border and the
    // title. Measure the glyph advance and give the hero a real box to centre
    // in, plus a little air on each side.
    Item {
      implicitWidth: heroGlyphMetrics.advanceWidth + Style.space(12)
      implicitHeight: Math.round(Style.font.display * 1.35)

      TextMetrics {
        id: heroGlyphMetrics
        font.family: root.fontFamily
        font.pixelSize: Math.round(Style.font.display)
        text: "\uF030"
      }

      OpticalGlyph {
        anchors.centerIn: parent
        text: "\uF030"
        fontFamily: root.fontFamily
        fontSize: Style.font.display
        color: root.barForeground
      }
    }
  }
}
