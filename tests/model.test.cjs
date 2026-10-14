#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.join(__dirname, "..");
const m = {};
vm.createContext(m);
vm.runInContext(fs.readFileSync(path.join(root, "Model.js"), "utf8"), m);
const plain = (v) => JSON.parse(JSON.stringify(v));

// normalizeRepo: what can be typed into the add field.
const repo = "https://github.com/ninepointlabs/repokase";
for (const input of [
  "ninepointlabs/repokase",
  " ninepointlabs/repokase ",
  "github.com/ninepointlabs/repokase",
  "https://github.com/ninepointlabs/repokase",
  "https://www.github.com/ninepointlabs/repokase/",
  "https://github.com/ninepointlabs/repokase/releases/tag/v1.0",
  "https://github.com/ninepointlabs/repokase.git",
  "http://github.com/ninepointlabs/repokase?tab=readme",
]) assert.equal(m.normalizeRepo(input), repo, input);
for (const input of [
  "", "repokase", "a/b/c", "--json/x", "-x/y", "owner/..", "owner/.",
  "https://gitlab.com/a/b", "github.com/a", "own er/repo", "owner/re po",
  "owner/repo;rm -rf ~", "owner/repo\nx",
]) assert.equal(m.normalizeRepo(input), "", JSON.stringify(input));

// cliCommand: argv only from a trusted binary and validated targets.
const cli = "/usr/bin/autonomix-cli";
assert.deepEqual(plain(m.cliCommand(cli, "list")), [cli, "list", "--json"]);
assert.deepEqual(plain(m.cliCommand(cli, "check")), [cli, "check", "--json"]);
assert.deepEqual(plain(m.cliCommand(cli, "update")), [cli, "update", "--json"]);
assert.deepEqual(plain(m.cliCommand(cli, "update", "a/b")), [cli, "update", "--json", "a/b"]);
assert.deepEqual(plain(m.cliCommand(cli, "install", "a/b")), [cli, "install", "--json", "a/b"]);
assert.deepEqual(plain(m.cliCommand(cli, "remove", "a/b")), [cli, "remove", "--json", "a/b"]);
assert.deepEqual(plain(m.cliCommand(cli, "add", repo)), [cli, "add", "--json", repo]);
assert.deepEqual(plain(m.cliCommand("/tmp/autonomix-cli", "list")), []);
assert.deepEqual(plain(m.cliCommand(cli, "rm")), []);
assert.deepEqual(plain(m.cliCommand(cli, "list", "a/b")), []);
assert.deepEqual(plain(m.cliCommand(cli, "remove", "")), []);
assert.deepEqual(plain(m.cliCommand(cli, "remove", "--yes")), []);
assert.deepEqual(plain(m.cliCommand(cli, "install", "-y/x")), []);
assert.deepEqual(plain(m.cliCommand(cli, "add", "ninepointlabs/repokase")), []); // must be normalized first

// processEnvironment: fixed PATH, HOME passed through, token only if sane.
assert.deepEqual(plain(m.processEnvironment("/home/tim", "")), { PATH: "/usr/bin:/bin", LC_ALL: "C.UTF-8", HOME: "/home/tim" });
assert.equal(m.processEnvironment("/home/tim", "ghp_" + "a".repeat(36)).GITHUB_TOKEN, "ghp_" + "a".repeat(36));
assert.equal(m.processEnvironment("/home/tim", "bad token").GITHUB_TOKEN, undefined);
assert.equal(m.processEnvironment("relative", "").HOME, undefined);

// parseOutput: the shapes autonomix-cli --json prints.
const listJson = JSON.stringify([
  { name: "Repokase", repo: "ninepointlabs/repokase", repo_url: repo, status: "update_available",
    installed: "0.2.1-1", installed_type: "pacman", latest: "v0.2.2",
    release_url: repo + "/releases/tag/v0.2.2", last_checked: "2026-10-14T12:00:00-05:00" },
  { name: "Glow", repo: "charmbracelet/glow", repo_url: "https://github.com/charmbracelet/glow",
    status: "not_installed", installed: "", installed_type: "", latest: "v3.0.0",
    release_url: "https://evil.example/glow", last_checked: "" },
  { name: "Broken", repo: "not a repo", status: "up_to_date" },
  { name: "Weird\u001b[31m", repo: "a/b", status: "exploded" },
]);
const list = m.parseOutput(listJson);
assert.equal(list.ok, true);
assert.equal(list.apps.length, 3);
assert.equal(list.apps[0].installedType, "pacman");
assert.equal(list.apps[0].releaseUrl, repo + "/releases/tag/v0.2.2");
assert.equal(list.apps[1].releaseUrl, "", "release URLs must point at the app's own repo");
assert.equal(list.apps[2].status, "failed", "unknown statuses are treated as failures");
assert.equal(list.apps[2].name, "Weird [31m");
assert.equal(m.updateCount(list.apps), 1);

const one = m.parseOutput(JSON.stringify({ name: "Glow", repo: "charmbracelet/glow", status: "not_installed", latest: "v3.0.0" }));
assert.equal(one.ok, true);
assert.equal(one.apps.length, 1);

const removed = m.parseOutput('{"removed": "Glow", "repo_url": "https://github.com/charmbracelet/glow"}');
assert.equal(removed.ok, true);
assert.equal(removed.removed, "Glow");
assert.equal(removed.apps.length, 0);

const err = m.parseOutput('{"error": "no tracked app matches \\"x\\""}');
assert.equal(err.ok, false);
assert.equal(err.error, 'no tracked app matches "x"');

const old = m.parseOutput("Unknown command: list\n\nUsage: ...");
assert.equal(old.ok, false);
assert.match(old.error, /0\.4 or newer/);

const updated = m.parseOutput(JSON.stringify([{ name: "Repokase", repo: "ninepointlabs/repokase", status: "up_to_date", updated: true },
  { name: "Rune", repo: "ninepointlabs/rune", status: "update_available", error: "exit status 1" }]));
assert.equal(updated.apps[0].updated, true);
assert.equal(updated.apps[1].error, "exit status 1");

// Ordering, labels, actions.
const sorted = m.sortApps([
  { name: "zed", status: "up_to_date" }, { name: "Alpha", status: "up_to_date" },
  { name: "new", status: "not_installed" }, { name: "upd", status: "update_available" },
]);
assert.deepEqual(sorted.map((a) => a.name), ["upd", "new", "Alpha", "zed"]);

assert.equal(m.subtitle(list.apps[0]), "0.2.1-1 → v0.2.2");
assert.equal(m.subtitle(list.apps[1]), "Not installed · v3.0.0 available");
assert.equal(m.actionFor(list.apps[0]), "update");
assert.equal(m.actionFor(list.apps[1]), "install");
assert.equal(m.actionFor({ status: "unmanaged", latest: "v1" }), "");
assert.equal(m.actionFor({ status: "not_installed", latest: "" }), "");

// needsCheck: stale or never-checked apps trigger a GitHub check.
const now = Date.parse("2026-10-14T18:00:00Z");
const hour = 3600 * 1000;
assert.equal(m.needsCheck([{ lastChecked: "2026-10-14T17:30:00Z" }], 6 * hour, now), false);
assert.equal(m.needsCheck([{ lastChecked: "2026-10-14T10:00:00Z" }], 6 * hour, now), true);
assert.equal(m.needsCheck([{ lastChecked: "" }], 6 * hour, now), true);
assert.equal(m.needsCheck([], 6 * hour, now), false);

assert.equal(m.conciseError("line one\nlast line\n\n"), "last line");
assert.equal(m.conciseError(""), "autonomix-cli failed");

console.log("model tests passed");
