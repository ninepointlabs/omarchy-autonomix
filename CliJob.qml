import QtQuick
import Quickshell.Io

// One autonomix-cli run at a time. argv comes from Model.cliCommand (a fixed
// absolute path plus validated arguments), and the session environment is
// replaced by `jobEnvironment`. jobFinished fires exactly once per start,
// including when the binary could not be started (127) or ran past its
// deadline (124).
Process {
  id: job

  property var jobEnvironment: ({})
  signal jobFinished(int exitCode, string stdoutText, string stderrText)

  property bool _started: false
  property bool _settled: true
  property bool _timedOut: false
  property string _out: ""
  property string _err: ""

  running: false
  command: []
  clearEnvironment: true
  environment: jobEnvironment
  workingDirectory: "/"
  stdout: StdioCollector { id: jobStdout; waitForEnd: true; onStreamFinished: job._out = text }
  stderr: StdioCollector { id: jobStderr; waitForEnd: true; onStreamFinished: job._err = text }

  function start(argv, deadlineSec) {
    if (running || !argv || argv.length === 0) return false
    _started = false
    _settled = false
    _timedOut = false
    _out = ""
    _err = ""
    command = argv
    deadline.interval = Math.max(1, deadlineSec || 60) * 1000
    running = true
    deadline.restart()
    return true
  }

  function settle(exitCode) {
    if (_settled) return
    _settled = true
    deadline.stop()
    jobFinished(_timedOut ? 124 : exitCode, String(jobStdout.text || _out || ""), String(jobStderr.text || _err || ""))
  }

  onStarted: _started = true
  onExited: function(exitCode) { settle(exitCode) }

  // A binary that is not on disk never starts, so `running` falls back to
  // false without an exit. A job stopped at its deadline settles here too, in
  // case no exit is reported for the killed process.
  onRunningChanged: {
    if (running || _settled) return
    if (!_started || _timedOut) settle(127)
  }

  // Process has no default property, so the timer is held in a property.
  property Timer deadline: Timer {
    repeat: false
    onTriggered: {
      if (!job.running) return
      job._timedOut = true
      job.running = false
    }
  }
}
