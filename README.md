# nightshift

A machine that works your GitHub issues with Claude Code. Label an issue `agent`;
nightshift asks you what it needs to know on the issue, posts a plan (a spec and
its tickets), builds the tickets in order once you say **go**, and opens a pull
request. You only ever reply on the issue.

It runs on a machine of yours (your Mac, a Mac mini, a macOS VM), polling GitHub,
so nothing is added to your repos and no admin rights are needed. In a React
Native repo, with [rn-agent](https://github.com/hvalec427/rn-agent) installed,
each change is checked on a simulator of its own and the pull request gets
screenshots and a recording.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/hvalec427/nightshift/master/install.sh | sh -s -- --service
```

It installs the `nightshift` command (`~/.nightshift/bin`) and its Claude Code
plugin, and with `--service` runs `nightshift watch` in the background whenever
you're logged in (a LaunchAgent, through `nightshift start`). Leave out
`--service` to run it by hand. Run it again to update; a running service is
restarted on the new version.

Then:

1. `claude setup-token`, and save the token it prints to `~/.nightshift/token`
   (`chmod 600`): a year of unattended runs on your Claude subscription.
2. `gh auth login` (gh 2.99 or newer, for screenshots in pull requests).
3. For each repo: a clone of it on the machine, then
   `nightshift add <owner/repo> <path to the clone>`. That also creates its
   `agent` label.

## Working an issue

| You | nightshift |
|---|---|
| Open an issue, add the `agent` label | Reads it and the code; asks its questions in one comment (each with its recommended answer), or goes straight to the plan |
| Reply | More questions, or a plan: the spec and its tickets, in [Matt Pocock's](https://github.com/mattpocock/skills) to-spec and to-tickets format |
| Reply **go** (or what to change) | Builds the tickets in order, a progress comment per ticket, then opens the pull request and links it |
| Comment on the issue after that | Makes the change on the same branch and pushes it |
| Remove the label | Stops it |

Each issue gets its own worktree (in the repo's clone, `.claude/worktrees/issue-<n>`,
branch `nightshift/issue-<n>`) and one Claude session that every run continues, so
it remembers the whole conversation. Once the pull request is open, the worktree is
removed; the branch stays.

Its comments start with **🤖 nightshift** and carry a hidden `<!-- nightshift -->`
marker, which is how it tells them from yours: it runs as your GitHub account, so
on GitHub they're yours. It only acts on the label when you added it, and only on
comments from you (`allowed_users` below).

```sh
nightshift status                   # the service, the issues it knows, what each is doing, and for how long
nightshift start                    # run the service: nightshift watch, in the background whenever you're logged in
nightshift stop                     # stop the service, and the runs in flight, until nightshift start
nightshift stop <owner/repo>#<n>    # stop one
nightshift logs -f                  # what the watcher does: a line per poll
nightshift logs <owner/repo>#<n> -f # an issue's runs: its tool calls and messages, as they happen
```

Without `-f`, `logs` prints the whole log. They live in `~/.nightshift`:
`watch.log` (kept to its last few thousand lines) and
`issues/<owner>_<repo>_<n>/log`.

## Config

`~/.nightshift/config`, written by `nightshift add`:

```
repo hvalec427/nightshift /Users/me/dev/nightshift
allowed_users=hvalec427
max_parallel=2
interval=30
permission_mode=auto
```

- `allowed_users`: whose labels and comments count (default: your gh account).
- `max_parallel`: issues worked at once (each may run a simulator).
- `interval`: seconds between polls.
- `permission_mode`: Claude Code's permission mode for runs. Commands that reach
  GitHub (`gh`, `git`) and signalbox and boop are always allowed.

## A dedicated machine

A Mac mini, or a macOS VM on Apple silicon (Tart, UTM): iOS simulators need macOS,
so a Linux VM only works for non-mobile repos. Set it up to stay logged in:
automatic login, `sudo pmset -a sleep 0`, Xcode selected
(`sudo xcode-select -s /Applications/Xcode.app`), then the install above. For a
separate identity, log `gh` in as a second GitHub account (invite it to your repos;
in an organisation, an admin adds it).

## Finishing by hand

The plugin's `finish` skill works in any Claude Code session too: in a
`claude --worktree <name>` session, say **finish** and it commits, pushes, opens
the pull request (with screenshots and a recording when the app is running there)
and removes the worktree.
