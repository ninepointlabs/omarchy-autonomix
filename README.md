# Autonomix for Omarchy

A bar widget for apps you install from GitHub releases. It shows how many of your tracked apps have updates waiting, and its panel lets you track new repos and install or update apps without opening a terminal. Think of it as a little pit crew for everything that isn't in the Arch repos.

The plugin is a frontend for [autonomix-cli](https://github.com/ninepointlabs/autonomix-cli), which does the real work: it keeps the list of tracked repos in `~/.autonomix/config.json`, checks GitHub for releases, and installs the right package for your system. The CLI, its TUI and this widget all share that list.

## What it does

- **Bar:** a package icon, plus the number of available updates. Click to open the panel, middle-click to check GitHub now.
- **Panel:**
  - lists tracked apps with installed and latest versions, updates first
  - **Update** or **Install** per app, and **Update all** when more than one is waiting
  - track a repo by typing `owner/repo` or pasting a GitHub URL
  - click an app to open its release page
  - the trash icon (click twice) stops tracking an app; it doesn't uninstall anything
  - the 󰋽 button next to the refresh button shows **About**: the version, license (readable in place), Nine Point Labs, the versions it's built with (including your autonomix-cli), what the widget does with your data, and the support address, [help@ninepointlabs.com](mailto:help@ninepointlabs.com), with *Email*, *Copy* and *Copy version details* buttons. <kbd>Esc</kbd> or the close button goes back to the list
- **Checks:** GitHub is checked on startup when the last check is stale, and then every six hours (configurable). Opening the panel only re-reads what's installed locally, which costs nothing.

Installs need root, so autonomix-cli runs the package manager through `pkexec` and you get Omarchy's polkit password dialog.

## Requirements

- autonomix-cli **0.4 or newer** (it needs the `--json` commands), installed at `/usr/bin/autonomix-cli` or `/usr/local/bin/autonomix-cli`
- Omarchy with the Quickshell-based shell

## Install

```bash
git clone https://github.com/ninepointlabs/omarchy-autonomix ~/Projects/omarchy-autonomix
~/Projects/omarchy-autonomix/install.sh
omarchy plugin enable ninepointlabs.autonomix
```

## Settings

| Setting | Default | |
|---|---|---|
| `checkIntervalMin` | `360` | Minutes between GitHub checks (30–1440) |
| `showCount` | `true` | Show the update count next to the icon |

Each check costs one GitHub API request per tracked app. Without a token GitHub allows 60 an hour; if `GITHUB_TOKEN` or `GH_TOKEN` is set in the shell's environment, the widget passes it on and the limit goes up to 5000.

## IPC

```bash
omarchy-shell ninepointlabs.autonomix toggle   # also open, close, isOpen
omarchy-shell ninepointlabs.autonomix check    # check GitHub now
omarchy-shell ninepointlabs.autonomix about    # open the panel on its About page
```

## How it runs things

The only program the plugin starts is autonomix-cli, from one of the two fixed paths above, with a cleared environment (`PATH=/usr/bin:/bin`, `HOME`, and the GitHub token if set). Repo names are validated before they go anywhere near argv, output is parsed as JSON and sanitized before it's displayed, and release links only open if they point at the app's own GitHub repo. Every run has a deadline.

## Development

```bash
node tests/model.test.cjs   # includes the About facts, checked against manifest.json, LICENSE and the first commit
omarchy plugin validate "$PWD"
```

## License

MIT
