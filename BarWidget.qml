import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Light Table — a bar widget that watches folders of photos and turns the
// newest ones into thumbnails you click to open in your default viewer.
//
// Scanning and preview building live in bin/scan.sh, with its cache and index
// under ~/.cache/psamoluk.light-table: a rescan costs one `find`, a preview is
// decoded once per (path, size, mtime), and anything ImageMagick cannot read
// keeps its original path so the panel shows a file-type glyph instead of an
// empty tile.
//
// The foldering itself is the widget's inline shell.json entry
// (`folders: [...]`, `sort`, `limit`); the panel is a pure view over the state
// held here and calls back through the injected hostWidget.
BarWidget {
  id: root
  moduleName: "psamoluk.light-table"

  readonly property string icon: "\uF030" // nf-fa-camera
  readonly property string home: Quickshell.env("HOME") || ""

  // Shared with the panel.
  property var images: []
  property bool scanning: false
  property bool warming: false
  property bool pendingRescan: false
  property int lastWarmMissing: -1

  // Plain state, refreshed from settings rather than bound: the shell can hand
  // `settings` over more than once during start-up, and a binding that is
  // invalidated before its first evaluation reads back as undefined inside the
  // very functions that need it.
  property var folders: []
  readonly property string sortMode: (settings && settings.sort === "name") ? "name" : "newest"
  // Subfolders on by default: a folder of shoots that only ever shows its top
  // level is useless to the person this is for.
  readonly property bool subfolders: !settings || settings.subfolders !== false
  readonly property int limit: (settings && Number(settings.limit) > 0) ? Number(settings.limit) : 600
  readonly property string cacheDir: home + "/.cache/psamoluk.light-table"
  readonly property int count: images.length
  readonly property string scriptPath: decodeURIComponent(String(Qt.resolvedUrl("bin/scan.sh")).replace("file://", ""))

  // ---------------------------------------------------------------------------
  // Shell.json entry
  // ---------------------------------------------------------------------------
  function entryFields() {
    var out = { id: moduleName }
    if (settings) for (var key in settings) if (key !== "id") out[key] = settings[key]
    return out
  }

  function persist(fields) {
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") return
    var entry = entryFields()
    for (var field in fields) entry[field] = fields[field]
    bar.shell.updateEntryInline(moduleName, entry)
  }

  function addFolder(path) {
    var folder = Model.normalize(path, home)
    if (folder === "") return
    lastWarmMissing = -1
    persist({ folders: Model.withFolder(folders, folder) })
  }

  function removeFolder(path) {
    lastWarmMissing = -1
    persist({ folders: Model.withoutFolder(folders, path) })
  }

  function setSort(mode) {
    lastWarmMissing = -1
    persist({ sort: mode === "name" ? "name" : "newest" })
  }

  function setSubfolders(value) {
    lastWarmMissing = -1
    persist({ subfolders: value === true })
  }

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------
  function refreshFolders() {
    folders = Model.folderList(settings, home)
  }

  function scanCommand(mode) {
    var command = [scriptPath, mode, cacheDir, String(limit), sortMode, subfolders ? "6" : "1"]
    return command.concat(folders)
  }

  function rescan() {
    if (!folders || folders.length === 0) { images = []; return }
    if (scanning) { pendingRescan = true; return }
    scanning = true
    scanProc.command = scanCommand("list")
    scanProc.running = true
  }

  function startWarm() {
    if (warming || !folders || folders.length === 0) return
    warming = true
    warmProc.command = scanCommand("warm")
    warmProc.running = true
  }

  Process {
    id: scanProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.images = Model.parseRows(String(text || ""))
        root.scanning = false
        var missing = Model.missingPreviews(root.images)
        // One warm pass per distinct shortfall: a file ImageMagick cannot
        // decode keeps `cached` at 0 forever, and re-warming it on every scan
        // would burn the disk for nothing.
        if (missing > 0 && missing !== root.lastWarmMissing && !root.warming) {
          root.lastWarmMissing = missing
          Qt.callLater(root.startWarm)
        }
      }
    }
    onExited: {
      root.scanning = false
      if (root.pendingRescan) {
        root.pendingRescan = false
        Qt.callLater(root.rescan)
      }
    }
  }

  Process {
    id: warmProc
    onExited: {
      root.warming = false
      Qt.callLater(root.rescan)
    }
  }

  // ---------------------------------------------------------------------------
  // Watching — inotifywait on the folders, debounced into one rescan per burst
  // ---------------------------------------------------------------------------
  function watchCommand() {
    var command = ["inotifywait", "-mq"]
    if (subfolders) command.push("-r")
    command = command.concat([
      "-e", "create", "-e", "delete", "-e", "moved_to", "-e", "moved_from", "-e", "close_write",
      "--format", "%f"])
    return command.concat(folders)
  }

  function beginWatch() {
    if (folders.length === 0) return
    if (watchProc.running) {
      watchProc.running = false
      watchRestart.restart()
      return
    }
    watchProc.command = watchCommand()
    watchProc.running = true
  }

  function restartWatch() {
    watchProc.running = false
    watchRestart.restart()
  }

  Process {
    id: watchProc
    stdout: SplitParser {
      onRead: function(line) { scanDebounce.restart() }
    }
    // inotifywait exits when a watched folder disappears (renamed, unmounted);
    // come back once the settings settle rather than spin.
    onExited: {
      if (root.folders.length > 0) watchRetry.restart()
    }
  }

  Timer {
    id: watchRestart
    interval: 200
    repeat: false
    onTriggered: root.beginWatch()
  }

  Timer {
    id: watchRetry
    interval: 5000
    repeat: false
    onTriggered: root.beginWatch()
  }

  Timer {
    id: scanDebounce
    interval: 400
    repeat: false
    onTriggered: root.rescan()
  }

  // Safety net for anything inotify misses (a folder on a network mount, a
  // watcher that died quietly).
  Timer {
    id: safetyScan
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.rescan()
  }

  // A warm pass writes previews as it goes; refresh the list every so often so
  // they appear while it works instead of all at once at the end.
  Timer {
    id: warmRefresh
    interval: 15000
    repeat: true
    running: root.warming
    onTriggered: if (root.warming) root.rescan()
  }

  // ---------------------------------------------------------------------------
  // Opening
  // ---------------------------------------------------------------------------
  readonly property string openerPath: decodeURIComponent(String(Qt.resolvedUrl("bin/open.sh")).replace("file://", ""))

  function openImage(path) {
    if (!path) return
    openProc.command = [openerPath, path]
    openProc.running = true
    close()
  }

  function openFolder(path) {
    if (!path) return
    openProc.command = [openerPath, path]
    openProc.running = true
  }

  Process { id: openProc }

  // ---------------------------------------------------------------------------
  // Panel wiring (the contract the bar's popout coordinator expects)
  // ---------------------------------------------------------------------------
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: {
    lastWarmMissing = -1
    refreshFolders()
    injectPanel()
    rescan()
    restartWatch()
  }

  Component.onCompleted: {
    refreshFolders()
    rescan()
    beginWatch()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Row {
    id: row
    spacing: 0

    BarIconButton {
      id: button
      bar: root.bar
      text: root.icon
      slotSize: Style.bar.statusSlot
      tooltipText: root.count > 0
        ? Model.countLabel(root.count) + " · " + root.folders.length + (root.folders.length === 1 ? " folder" : " folders")
        : "Light Table"
      onPressed: function(b) { root.togglePanel() }
    }

    Text {
      visible: root.count > 0
      anchors.verticalCenter: parent.verticalCenter
      text: String(root.count)
      color: root.bar ? root.bar.barForeground : Color.foreground
      opacity: 0.7
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
