# Install

```sh
curl -fsSL https://raw.githubusercontent.com/hvalec427/nightshift/master/install.sh | sh -s -- --service
```

It installs the latest release: the `nightshift` command (`~/.nightshift/bin`)
and its Claude Code plugin (also copied to `~/.nightshift/plugin`, for runs),
both at that release's tag, and with `--service` runs `nightshift watch` in the
background whenever you're logged in (a LaunchAgent, through `nightshift start`).
Leave out `--service` to run it by hand. Run it again to update to the latest
release; a running service is restarted on the new version. It ends with
`nightshift doctor` (below), and only starts the service once nothing required
is missing.

A release install updates itself: the watch installs each new release when
nothing is running. To update by hand instead, set `auto_update=false` in the
[config](config.md#config). `--auto-update` (`… | sh -s -- --service --auto-update`) still
works: it sets `auto_update=true` there, which is the default.

To test what's on `master` instead, add `--master` (`… | sh -s -- --master`);
run from a clone (`./install.sh`), it installs the clone's files.
`nightshift --version` says which one runs: `0.2.0` for a release,
`master (<commit>)`, or `dev (<commit>)` from a clone.

Then:

1. `claude setup-token`, and save the token it prints to `~/.nightshift/token`
   (`chmod 600`): a year of unattended runs on your Claude subscription.
2. `gh auth login` (gh 2.99 or newer, for screenshots in pull requests).
3. For each repo: a clone of it on the machine, then
   `nightshift add <owner/repo> <path to the clone>`.
   That also creates its `agent` label (not with `all_issues=true`, see
   [Config](config.md#config)) and the status labels, and leaves
   `.nightshift/config` (the defaults, commented) and `.nightshift/CONTEXT.md`
   (a stub for the project's glossary) in the clone, where they're missing and
   uncommitted: commit them to the repo's default branch. `add` takes no
   options; they live in the repo's `.nightshift/` (see [Config](config.md#config)).
   The project's own rules go in its `.nightshift/instructions/` (see [Instructions](config.md#instructions)).
   nightshift merges the repo's pull requests itself; to merge them yourself,
   or to load plugins in its runs, put `auto_merge=false` or `plugins=…` in the
   repo's `.nightshift/config`.

## What it needs

`nightshift doctor` checks all of it on this machine, starting with the
nightshift version that runs (and, on a release, whether a newer one is out):
what's installed and its version, gh's login, a Claude token, nightshift's
plugin, and each watched repo's clone and `agent` label (none needed with
`all_issues=true`; with a hint when GitHub keeps merged branches there), then a line for each plugin its `.nightshift/config` names:
`ok`, or `missing` with how to install it (`claude plugin install <name>`) or
enable it (`claude plugin enable <id>`). It says what's missing and how to get it, and
fails when something required is; `nightshift start` won't start the service until
nothing is.

Always:

| Tool | For | Minimum |
|---|---|---|
| git | worktrees and branches | 2.31 |
| [gh](https://cli.github.com), logged in | issues, labels and pull requests (with screenshots attached) | 2.99 |
| [Claude Code](https://claude.com/claude-code) (`claude`), with a token in `~/.nightshift/token` (or logged in) | the runs | 2.1.286 (the version its run flags were checked on) |
| jq | reading GitHub's and Claude's JSON, and the logs | 1.6 |

What a repo's runs need beyond that comes with the plugins its `.nightshift/config` names
(see [Plugins](config.md#plugins)).

## A dedicated machine

A Mac mini, or a macOS VM on Apple silicon (Tart, UTM): iOS simulators need macOS,
so a Linux VM only works for non-mobile repos. Set it up to stay logged in:
automatic login, `sudo pmset -a sleep 0`, and what your repos' tools need (for
iOS, Xcode), then the install above. For a
separate identity, log `gh` in as a second GitHub account (invite it to your repos;
in an organisation, an admin adds it).
