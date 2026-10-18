# Commands

```sh
nightshift status                   # the service, the issues in progress, what each is doing and in which skill (or why it stopped), for how long, a running one's heartbeat (its latest step and last activity), what it spent so far, its context size, and merge order
nightshift status --all             # the done ones too: when their pull request merged, or the issue closed
nightshift top                      # at least 8 windows, one per issue in progress, tiled to fit the terminal: its status and the end of its log, redrawn every second until `q`; with more issues than fit, `j`/`k`, the arrows, Space and PgDn/PgUp scroll the grid by rows of windows (piped: one frame, the first)
nightshift start                    # run the service: nightshift watch, in the background whenever you're logged in
nightshift stop                     # stop the service, and the runs in flight (they resume when it starts again), until nightshift start
nightshift stop <owner/repo>#<n>    # stop one (it stays stopped until you comment)
nightshift logs -f                  # every issue, as it happens: picked up, runs started and done, skills, comments, PRs
nightshift logs <owner/repo>#<n> -f # the same for one issue
nightshift logs -f -vv              # more: -v Claude's messages, -vv its tool calls, -vvv everything
nightshift doctor                   # what this machine is missing, and how to get it
nightshift sub-issue --title <t> --body-file <f> [--after <n>]…  # (in a run only) create a sub-issue of the run's issue, blocked by the issues it goes after; prints its URL
nightshift --version                # the version that runs
```

`logs` shows a level and the ones above it, with or without an issue:

| Level | Flag | Adds |
|---|---|---|
| `runs` (default) | | issues picked up (or ignored, waiting, stopped), runs started and done (with how long they took, the models they used and their context at the end), each skill a run invokes, each comment nightshift posts and its stage, pull requests |
| `messages` | `-v` | Claude's text |
| `tools` | `-vv` | tool calls and failed tool results |
| `all` | `-vvv` | thinking, every tool result, and the polls with nothing new |

`-l <level>` (or `--level`) names the level instead. Without `-f`, `logs` prints
the whole log. The logs live in `~/.nightshift`: `watch.log` (every issue's
lines, kept to its last 20,000) and each issue's full history in
`issues/<owner>_<repo>_<n>/log`.
