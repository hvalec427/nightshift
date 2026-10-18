# nightshift

A machine that works your GitHub issues with Claude Code. Label an issue `agent`;
nightshift asks you what it needs to know on the issue, posts a plan (a spec and
its tickets), builds the tickets in order once you say **go** (or right away, when
the plan has no open choices), and opens a pull request. You only ever reply on the issue.

It runs on a machine of yours (your Mac, a Mac mini, a macOS VM), polling GitHub,
so nothing is added to your repos and no admin rights are needed. A repo's runs
load the Claude Code plugins its `.nightshift/config` names, and follow its own instructions on
how to check and show a change, so a pull request can come with screenshots and
a recording (see [Plugins](docs/config.md#plugins)).

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/hvalec427/nightshift/master/install.sh | sh -s -- --service
```

It installs the latest release, the `nightshift` command and its Claude Code plugin;
`--service` runs `nightshift watch` in the background whenever you're logged in. A release
install updates itself with each new release. More, and what it needs, in [docs/install.md](docs/install.md).

Then:

1. `claude setup-token`, and save the token it prints to `~/.nightshift/token`
   (`chmod 600`).
2. `gh auth login` (gh 2.99 or newer).
3. For each repo: a clone of it on the machine, then
   `nightshift add <owner/repo> <path to the clone>`, and commit the
   `.nightshift/config` and `.nightshift/CONTEXT.md` it leaves in the clone.

## How it works

1. Label an issue `agent` (and a [type](docs/working-an-issue.md#issue-types) label).
2. nightshift picks its [size](docs/working-an-issue.md#sizes) and asks its questions in a
   comment; you reply. A small issue goes straight to the build; a large one is split into
   sub-issues, each its own pull request.
3. It posts a plan: a spec and its tickets.
4. You reply **go** (or what to change); it builds the tickets and has the change reviewed.
5. It opens a pull request that closes the issue.
6. Once the checks pass and nothing needs your decision, it merges it (unless the repo has
   `auto_merge=false`).

The whole flow, the labels and the rest in [docs/working-an-issue.md](docs/working-an-issue.md).

## Commands

```sh
nightshift status                   # the issues in progress and what each is doing
nightshift top                      # a live dashboard of them
nightshift start                    # run the service in the background
nightshift stop                     # stop the service, and the runs in flight
nightshift logs -f                  # every issue, as it happens
nightshift doctor                   # what this machine is missing, and how to get it
nightshift --version                # the version that runs
```

## Docs

- [Install](docs/install.md): installing and updating, what it needs, a dedicated machine.
- [Working an issue](docs/working-an-issue.md): the flow, sessions and worktrees, skills,
  issue types, status labels, overlapping pull requests, finishing by hand.
- [Commands](docs/commands.md): every command, the log levels and where the logs live.
- [Config](docs/config.md): config keys, permissions and isolation, instructions, plugins,
  models.
- [Development](docs/development.md): tests and releases.

## Credits

How nightshift asks, specs, tickets, tests and reviews (the plugin's `questions`, `plan`,
`build` and `review` skills) is adapted from
[Matt Pocock's skills](https://github.com/mattpocock/skills) (MIT): see
[plugin/THIRD_PARTY.md](plugin/THIRD_PARTY.md). They ship in the plugin, so a run
doesn't depend on which skills the machine has.
