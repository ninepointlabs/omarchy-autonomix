// Pure helpers for the Autonomix plugin. No QML types in here so the logic
// can be tested with node (tests/model.test.cjs).
//
// Process boundary: the only program this plugin starts is autonomix-cli from
// a fixed absolute path, with argv built here from validated values and the
// session environment replaced by processEnvironment().

var CLI_CANDIDATES = ["/usr/bin/autonomix-cli", "/usr/local/bin/autonomix-cli"]
var TRUSTED_PATH = "/usr/bin:/bin"
var STATUSES = ["update_available", "not_installed", "up_to_date", "unchecked", "unmanaged", "failed"]

// Seconds before a job is stopped. Installs wait on a polkit password
// dialog and a package download, so they get the longest.
var JOB_DEADLINES = { list: 30, check: 180, add: 60, remove: 30, update: 900, install: 900 }

function processEnvironment(home, token) {
  var env = { PATH: TRUSTED_PATH, LC_ALL: "C.UTF-8" }
  if (validPath(home) !== "") env.HOME = home
  // Raises the GitHub API limit from 60 to 5000 requests an hour.
  if (/^[A-Za-z0-9_]{20,255}$/.test(String(token || ""))) env.GITHUB_TOKEN = token
  return env
}

function validPath(path) {
  var text = String(path || "")
  if (text.charAt(0) !== "/" || /[\x00-\x1f\x7f]/.test(text) || /(^|\/)\.\.?(\/|$)/.test(text)) return ""
  return text
}

function trustedCli(path) {
  var text = String(path || "")
  return CLI_CANDIDATES.indexOf(text) >= 0 ? text : ""
}

var OWNER_REPO = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})\/[A-Za-z0-9._-]{1,100}$/

// Turns what was typed into the add field ("owner/repo" or a GitHub URL,
// with or without a /releases suffix) into "https://github.com/owner/repo",
// or "" when it isn't one.
function normalizeRepo(text) {
  var value = String(text || "").trim()
  value = value.replace(/^https?:\/\//i, "").replace(/^www\./i, "")
  if (/^github\.com\//i.test(value)) {
    var parts = value.substring("github.com/".length).split(/[/?#]/)
    value = parts.length >= 2 ? parts[0] + "/" + parts[1] : ""
  }
  value = value.replace(/\.git$/i, "")
  if (!OWNER_REPO.test(value) || /(^|\/)\.\.?$/.test(value)) return ""
  return "https://github.com/" + value
}

// argv for one CLI operation. `target` is an app's "owner/repo" (for update,
// install and remove) or a normalized repo URL (for add). Returns [] when a
// value doesn't validate, so nothing runs.
function cliCommand(cli, op, target) {
  var bin = trustedCli(cli)
  if (bin === "" || JOB_DEADLINES[op] === undefined) return []
  var args = [bin, op, "--json"]
  if (op === "list" || op === "check") return target ? [] : args
  if (op === "update" && !target) return args
  if (op === "add") return normalizeRepo(target) === target ? args.concat([target]) : []
  return OWNER_REPO.test(String(target || "")) ? args.concat([target]) : []
}

function cleanText(value, max) {
  var text = String(value === undefined || value === null ? "" : value)
  text = text.replace(/[\x00-\x1f\x7f]+/g, " ").replace(/\s+/g, " ").trim()
  var limit = max || 120
  return text.length > limit ? text.substring(0, limit - 1) + "…" : text
}

function cleanApp(raw) {
  if (!raw || typeof raw !== "object") return null
  var repo = String(raw.repo || "")
  if (!OWNER_REPO.test(repo)) return null
  var releaseUrl = String(raw.release_url || "")
  if (releaseUrl.indexOf("https://github.com/" + repo + "/") !== 0) releaseUrl = ""
  return {
    name: cleanText(raw.name, 60) || repo,
    repo: repo,
    url: "https://github.com/" + repo,
    status: STATUSES.indexOf(raw.status) >= 0 ? raw.status : "failed",
    installed: cleanText(raw.installed, 40),
    installedType: cleanText(raw.installed_type, 16),
    latest: cleanText(raw.latest, 40),
    releaseUrl: releaseUrl,
    lastChecked: cleanText(raw.last_checked, 40),
    updated: raw.updated === true,
    error: cleanText(raw.error, 200)
  }
}

// Parses --json output. `apps` is always an array: the list for list, check
// and update, one app for add and install, none for remove.
function parseOutput(text) {
  var data
  try {
    data = JSON.parse(String(text || ""))
  } catch (e) {
    return { ok: false, apps: [], error: "Needs autonomix-cli 0.4 or newer (no JSON output)" }
  }
  if (data && !Array.isArray(data) && typeof data === "object" && typeof data.error === "string")
    return { ok: false, apps: [], error: cleanText(data.error, 200) }
  if (data && typeof data === "object" && typeof data.removed === "string")
    return { ok: true, apps: [], removed: cleanText(data.removed, 60), error: "" }

  var raw = Array.isArray(data) ? data : [data]
  var apps = []
  for (var i = 0; i < raw.length; i++) {
    var app = cleanApp(raw[i])
    if (app) apps.push(app)
  }
  return { ok: true, apps: apps, error: "" }
}

function conciseError(text, fallback) {
  var lines = String(text || "").split("\n")
  for (var i = lines.length - 1; i >= 0; i--) {
    var line = cleanText(lines[i], 160)
    if (line !== "") return line
  }
  return fallback || "autonomix-cli failed"
}

function rank(status) {
  var order = { update_available: 0, failed: 1, not_installed: 2, unchecked: 3, up_to_date: 4, unmanaged: 5 }
  return order[status] === undefined ? 9 : order[status]
}

function sortApps(apps) {
  return apps.slice().sort(function(a, b) {
    return rank(a.status) - rank(b.status) || a.name.toLowerCase().localeCompare(b.name.toLowerCase())
  })
}

function updateCount(apps) {
  var n = 0
  for (var i = 0; i < apps.length; i++) if (apps[i].status === "update_available") n++
  return n
}

// One line under the app name in the panel.
function subtitle(app) {
  switch (app.status) {
  case "update_available": return app.installed + " → " + app.latest
  case "up_to_date": return "Up to date · " + app.installed
  case "not_installed": return app.latest !== "" ? "Not installed · " + app.latest + " available" : "Not installed"
  case "unchecked": return app.installed + " · not checked yet"
  case "unmanaged": return "Installed outside the package manager" + (app.installedType ? " (" + app.installedType + ")" : "")
  case "failed": return app.error !== "" ? app.error : "Check failed"
  }
  return ""
}

// The action a row offers, or "" for none.
function actionFor(app) {
  if (app.status === "update_available") return "update"
  if (app.status === "not_installed" && app.latest !== "") return "install"
  return ""
}

// True when any app hasn't been checked within maxAgeMs.
function needsCheck(apps, maxAgeMs, nowMs) {
  for (var i = 0; i < apps.length; i++) {
    var t = Date.parse(apps[i].lastChecked)
    if (isNaN(t) || nowMs - t > maxAgeMs) return true
  }
  return false
}

// ---------------------------------------------------------------------------
// About (AboutView.qml). The version is read from manifest.json and the
// license text from LICENSE at run time; these are the facts that live
// nowhere else.
// ---------------------------------------------------------------------------

var ABOUT = {
  name: "Autonomix",
  tagline: "Apps installed from GitHub releases, in the Omarchy bar. Powered by autonomix-cli.",
  organization: "Nine Point Labs",
  supportEmail: "help@ninepointlabs.com",
  created: "October 2026", // first commit: 2026-10-14
  license: "MIT License",
  copyright: "© 2026 Nine Point Labs" // as written in LICENSE
}

// Must stay true to the code: the widget's only process is autonomix-cli
// (CLI_CANDIDATES, cliCommand above), its only links are GitHub release pages
// (cleanApp) and the support mailto, and autonomix-cli's own network use is
// described in its About (pkg/about in ninepointlabs/autonomix-cli).
var PRIVACY = "No account and no telemetry. The widget makes no network requests itself: the only program "
  + "it runs is autonomix-cli, which talks only to GitHub. It asks api.github.com for the latest release of "
  + "each tracked app when it checks for updates (at startup if the last check is stale, then on the check "
  + "interval, or when you ask for a check) and when you add, update or install an app, and it downloads the "
  + "package from the app's github.com release when you install or update. Installing runs your package "
  + "manager through pkexec, so you see the polkit password dialog. If GITHUB_TOKEN or GH_TOKEN is set, it is "
  + "passed to autonomix-cli and sent only to api.github.com. Your tracked apps are kept in "
  + "~/.autonomix/config.json by autonomix-cli, and the widget's settings in ~/.config/omarchy/shell.json. "
  + "Release pages and the Email button open in your own browser or mail app."

// "0.1.0" from manifest.json's text, or "" if it cannot be read.
function manifestVersion(text) {
  var parsed
  try { parsed = JSON.parse(String(text || "")) } catch (e) { return "" }
  var version = parsed && typeof parsed.version === "string" ? parsed.version : ""
  return /^[0-9A-Za-z.+-]{1,32}$/.test(version) ? version : ""
}

// "0.4.2" from `autonomix-cli --version`, or "".
function cliVersion(text) {
  var m = /([0-9]+\.[0-9]+(?:\.[0-9]+)?(?:[-+][0-9A-Za-z.]{1,24})?)/.exec(String(text || "").split("\n")[0])
  return m ? m[1] : ""
}

// Highest minor version `has(major, minor)` accepts, as "major.minor"
// (Quickshell.hasVersion / hasQtVersion only answer yes or no), or "".
function probedVersion(has, major) {
  if (typeof has !== "function" || !has(major, 0)) return ""
  var minor = 0
  while (minor < 99 && has(major, minor + 1)) minor++
  return major + "." + minor
}

// One paragraph per line, so the license wraps to the panel width.
function reflowLicense(text) {
  var paragraphs = String(text || "").replace(/\r/g, "").split(/\n\s*\n/)
  var out = []
  for (var i = 0; i < paragraphs.length; i++) {
    var p = paragraphs[i].replace(/\s+/g, " ").trim()
    if (p !== "") out.push(p)
  }
  return out.join("\n\n")
}

function builtWith(quickshell, qt, cli) {
  var built = []
  built.push("Quickshell " + (quickshell || "?"))
  built.push("Qt " + (qt || "?"))
  built.push("autonomix-cli " + (cli || "not found"))
  return built.join(", ")
}

// Version details for a support email.
function aboutDetails(version, quickshell, qt, cli, desktop) {
  return ABOUT.name + " " + (version || "unknown version") + "\n"
    + builtWith(quickshell, qt, cli) + "\n"
    + (desktop || "unknown desktop")
}

function supportMailto(version, details) {
  return "mailto:" + ABOUT.supportEmail + "?subject=" + encodeURIComponent(ABOUT.name + " " + (version || ""))
    + "&body=" + encodeURIComponent("\n\n--\n" + details)
}
