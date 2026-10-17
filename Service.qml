import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// One instance per shell: the tracked apps as autonomix-cli reports them.
// The bar widget and panel on every monitor read this, and all changes go
// through the CLI, which owns ~/.autonomix/config.json.
//
// Jobs run one at a time. `list` is local and cheap (pacman -Q per app), so
// it runs after every change; `check` costs one GitHub request per app and
// only runs on the check interval or when asked.
Item {
  id: root

  property var shell: null
  property var settings: ({})
  property bool active: true

  readonly property var processEnvironment: Model.processEnvironment(
    Quickshell.env("HOME"), Quickshell.env("GITHUB_TOKEN") || Quickshell.env("GH_TOKEN"))

  property string cli: ""
  property bool cliMissing: false
  // From the `--version` probe that finds the CLI; shown on the About page.
  property string cliVersion: ""

  property var apps: []
  property bool loaded: false
  property string lastError: ""
  property string actionStatus: ""
  property int revision: 0

  // What is running now ({ op, target, label }) and what is waiting.
  property var current: null
  property var queue: []

  readonly property bool busy: current !== null
  readonly property bool checking: current !== null && current.op === "check"
  readonly property int updateCount: Model.updateCount(apps)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property int checkIntervalMs: Math.max(30, Number(setting("checkIntervalMin", 360)) || 360) * 60 * 1000

  // True while `repo` is being updated, installed or removed (or waiting to).
  function isBusyWith(repo) {
    if (current && current.target === repo) return true
    for (var i = 0; i < queue.length; i++) if (queue[i].target === repo) return true
    return false
  }

  // ------------------------------------------------------------- Actions --

  function list() { enqueue("list", "", "") }
  function check() { enqueue("check", "", "Checking GitHub for updates…") }
  function updateAll() { enqueue("update", "", "Updating " + updateCount + (updateCount === 1 ? " app…" : " apps…")) }

  function update(app) { if (app) enqueue("update", app.repo, "Updating " + app.name + "…") }
  function install(app) { if (app) enqueue("install", app.repo, "Installing " + app.name + "…") }
  function remove(app) { if (app) enqueue("remove", app.repo, "") }

  // Returns false (with lastError set) when `text` isn't a GitHub repo.
  function add(text) {
    var url = Model.normalizeRepo(text)
    if (url === "") {
      lastError = "Enter owner/repo or a github.com URL"
      return false
    }
    lastError = ""
    enqueue("add", url, "Adding " + url.substring("https://github.com/".length) + "…")
    return true
  }

  function openRelease(app) {
    if (!app) return
    Qt.openUrlExternally(app.releaseUrl !== "" ? app.releaseUrl : app.url)
  }

  // ---------------------------------------------------------------- Jobs --

  function enqueue(op, target, label) {
    var job = { op: op, target: target, label: label }
    for (var i = 0; i < queue.length; i++)
      if (queue[i].op === op && queue[i].target === target) return
    if (current && current.op === op && current.target === target && op !== "list") return
    queue = queue.concat([job])
    if (current === null) next()
  }

  function next() {
    if (queue.length === 0) return
    if (cli === "") { resolveCli(); return }
    var job = queue[0]
    queue = queue.slice(1)

    var argv = Model.cliCommand(cli, job.op, job.target)
    if (argv.length === 0) {
      lastError = "Refused to run autonomix-cli with an unexpected argument"
      next()
      return
    }
    current = job
    if (job.label !== "") actionStatus = job.label
    if (!cliJob.start(argv, Model.JOB_DEADLINES[job.op])) {
      current = null
      lastError = "Could not start autonomix-cli"
    }
  }

  CliJob {
    id: cliJob
    jobEnvironment: root.processEnvironment
    onJobFinished: function(exitCode, stdoutText, stderrText) {
      root.finish(exitCode, stdoutText, stderrText)
    }
  }

  function finish(exitCode, stdoutText, stderrText) {
    var job = current
    current = null
    actionStatus = ""

    if (exitCode === 127) {
      lastError = "Could not run " + cli
    } else if (exitCode === 124) {
      lastError = "autonomix-cli took too long and was stopped"
    } else {
      var parsed = Model.parseOutput(stdoutText)
      if (!parsed.ok) {
        lastError = parsed.error !== "" ? parsed.error : Model.conciseError(stderrText)
      } else {
        apply(job, parsed, exitCode)
      }
    }

    // Anything that changed what's installed or tracked is followed by a
    // fresh local listing, so every row reflects the system as it is now.
    if (job && job.op !== "list" && job.op !== "check") enqueue("list", "", "")
    next()
  }

  function apply(job, parsed, exitCode) {
    lastError = ""
    if (job.op === "list" || job.op === "check") {
      apps = Model.sortApps(parsed.apps)
      loaded = true
      revision += 1
      if (exitCode !== 0) lastError = "Some apps could not be checked"
      return
    }

    var failed = []
    for (var i = 0; i < parsed.apps.length; i++)
      if (parsed.apps[i].error !== "") failed.push(parsed.apps[i].name + ": " + parsed.apps[i].error)
    if (failed.length > 0) {
      lastError = Model.cleanText(failed.join("; "), 200)
    } else if (job.op === "add" && parsed.apps.length > 0) {
      flash("Tracking " + parsed.apps[0].name)
    } else if (job.op === "remove") {
      flash("Stopped tracking " + parsed.removed)
    } else if (job.op === "update" || job.op === "install") {
      var done = parsed.apps.filter(function(a) { return a.updated })
      if (done.length === 1) flash((job.op === "install" ? "Installed " : "Updated ") + done[0].name + " to " + done[0].latest)
      else if (done.length > 1) flash("Updated " + done.length + " apps")
      else flash("Nothing to update")
    }
  }

  function flash(text) {
    actionStatus = text
    statusTimer.restart()
  }

  Timer {
    id: statusTimer
    interval: 3000
    repeat: false
    onTriggered: if (root.current === null) root.actionStatus = ""
  }

  // ---------------------------------------------------------- Find the CLI --

  property int _candidate: 0

  function resolveCli() {
    if (cliProbe.running) return
    _candidate = 0
    probeNext()
  }

  function probeNext() {
    if (_candidate >= Model.CLI_CANDIDATES.length) {
      cliMissing = true
      lastError = "autonomix-cli is not installed (looked in " + Model.CLI_CANDIDATES.join(", ") + ")"
      queue = []
      return
    }
    cliProbe.start([Model.CLI_CANDIDATES[_candidate], "--version"], 10)
  }

  CliJob {
    id: cliProbe
    jobEnvironment: root.processEnvironment
    onJobFinished: function(exitCode, stdoutText) {
      if (exitCode !== 0) { root._candidate++; root.probeNext(); return }
      root.cli = Model.trustedCli(Model.CLI_CANDIDATES[root._candidate])
      root.cliVersion = Model.cliVersion(stdoutText)
      root.cliMissing = false
      root.next()
    }
  }

  // ------------------------------------------------------------ Schedule --

  function startUp() {
    if (loaded) return
    list()
  }

  Component.onCompleted: if (active) startUp()
  onActiveChanged: if (active) startUp()

  // After the first listing, check GitHub if anything is stale.
  onLoadedChanged: if (loaded && Model.needsCheck(apps, checkIntervalMs, Date.now())) check()

  Timer {
    interval: root.checkIntervalMs
    repeat: true
    running: root.active && root.loaded
    onTriggered: root.check()
  }
}
