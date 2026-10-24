.pragma library

// Light Table — helpers shared by the bar widget and its panel.

function normalize(raw, home) {
  var path = String(raw === undefined || raw === null ? "" : raw).trim()
  if (path === "") return ""
  // Paths arrive from file managers and terminals wearing quotes, or pasted as
  // file:// URLs; strip both before touching the rest.
  if (path.length > 1) path = path.replace(/^['"]+|['"]+$/g, "")
  if (path.indexOf("file://") === 0) {
    try { path = decodeURIComponent(path.slice(7)) } catch (e) { path = path.slice(7) }
  }
  if (path === "~") return home
  if (path.slice(0, 2) === "~/" && home) path = home + path.slice(1)
  while (path.length > 1 && path.charAt(path.length - 1) === "/") path = path.slice(0, -1)
  return path
}

function baseName(path) {
  var parts = String(path || "").split("/")
  return parts.length ? parts[parts.length - 1] : ""
}

function tilde(path, home) {
  var value = String(path || "")
  if (home && (value === home || value.indexOf(home + "/") === 0)) return "~" + value.slice(home.length)
  return value
}

// Settings arrive as plain JS values, but a JSON array read back out of
// shell.json can reach QML as a QVariantList that fails `instanceof Array` and
// `Object.prototype.toString` alike — so read anything list-shaped by length
// instead of by type. A single string is accepted too (a hand-edited entry).
function asList(value) {
  if (value === undefined || value === null) return null
  if (typeof value === "string") return value === "" ? [] : [value]
  if (value.length === undefined) return null
  var out = []
  for (var i = 0; i < value.length; i++) out.push(value[i])
  return out
}

function folderList(settings, home) {
  var raw = settings ? settings.folders : undefined
  var values = asList(raw)
  var list = []
  if (values !== null) {
    for (var i = 0; i < values.length; i++) {
      var folder = normalize(values[i], home)
      if (folder !== "" && list.indexOf(folder) === -1) list.push(folder)
    }
  }
  // No key at all means "first run": show ~/Pictures rather than an empty bar.
  if (values === null && home) list.push(home + "/Pictures")
  return list
}

function withFolder(list, folder) {
  var out = []
  for (var i = 0; i < list.length; i++) if (list[i] !== folder) out.push(list[i])
  out.push(folder)
  return out
}

function withoutFolder(list, folder) {
  var out = []
  for (var i = 0; i < list.length; i++) if (list[i] !== folder) out.push(list[i])
  return out
}

// rows: path, preview, name, mtime, cached
function parseRows(text) {
  var rows = []
  var lines = String(text === undefined || text === null ? "" : text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line) continue
    var columns = line.split("\t")
    if (columns.length < 5) continue
    rows.push({
      path: columns[0],
      preview: columns[1],
      name: columns[2],
      mtime: Number(columns[3]) || 0,
      cached: columns[4] === "1"
    })
  }
  return rows
}

function missingPreviews(rows) {
  var missing = 0
  for (var i = 0; i < rows.length; i++) if (!rows[i].cached) missing++
  return missing
}

function extensionOf(path) {
  var name = baseName(path)
  var dot = name.lastIndexOf(".")
  if (dot <= 0) return ""
  return name.slice(dot + 1).toUpperCase()
}

function countLabel(count) {
  return String(count) + (count === 1 ? " photo" : " photos")
}

function metaLine(count, folderCount, warming) {
  var parts = [countLabel(count).toUpperCase()]
  parts.push(String(folderCount) + (folderCount === 1 ? " FOLDER" : " FOLDERS"))
  if (warming) parts.push("BUILDING PREVIEWS")
  return parts.join("  ·  ")
}

function glyphFor(path) {
  var ext = extensionOf(path)
  if (ext === "") return "\uF1C5"
  return ext.length > 4 ? ext.slice(0, 4) : ext
}
