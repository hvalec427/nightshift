# nightshift

A CLI and a Claude Code plugin that work GitHub issues labelled `agent` unattended: questions,
a plan, the build, a pull request, talking to the user only through the issue.

## Map

- `nightshift` — the CLI, one POSIX `sh` script. Its header comment lists the commands and the
  state layout under `~/.nightshift`; read it there rather than here.
- `plugin/` — the Claude Code plugin: `plugin/skills/` (a skill per stage of an issue),
  `plugin/agents/` (the subagents the skills start), `plugin/hooks/` (the SessionStart hook)
  and `plugin/instructions.md` (every run's defaults).
- `scripts/` — the tests (`scripts/test-*.sh`, helpers in `scripts/test-lib.sh`), the fakes in
  `scripts/fake/`, `scripts/commit-lint.sh` and the release scripts (`scripts/release.sh`).
- `install.sh` — the installer, the command and the plugin at a release.

## Checking a change

- `bash scripts/test.sh` runs every test, `bash scripts/test.sh review runs` just
  `scripts/test-review.sh` and `scripts/test-runs.sh`. Run it with `bash`: it isn't executable.
  The files run in parallel and the whole suite takes about 3 minutes. While working, run
  the files for what you changed. Where the whole suite runs is the `full_suite` option in
  `.nightshift/config`: unset (this repo), CI runs it, so don't run it locally; `local`, run it
  once before the pull request; `nothing`, nightshift runs no whole suite.
- `shellcheck -S warning nightshift install.sh scripts/*.sh scripts/fake/*` — CI's exact file
  list (`.github/workflows/check.yml`).
- `bash scripts/commit-lint.sh --title "<subject>"` checks a commit or pull request title.

## Conventions

- nightshift runs on macOS (launchd, BSD `date`, bash 3.2), and CI runs its tests there: use
  BSD-compatible flags, no GNU-only ones.
- Skills are prose in `plugin/skills/<name>/SKILL.md` with frontmatter (`name`,
  `description`, `user-invocable: false`, `model`, `effort`) that `scripts/test-skills.sh` checks.
- A test file passes alone, in any order and in any split across machines (the files are
  shuffled and sharded): tests that rely on each other live in one file, nothing relies on
  another file.
- Tests drive nightshift through the fakes in `scripts/fake/` (`gh`, `claude`, `curl`); the
  Tests section of `docs/development.md` says how, and names the one exception.

## Pointers

- `docs/development.md`: Tests (how a test reads), Releases (versioning from commit types).
- `docs/config.md`: the config keys; `docs/working-an-issue.md`: Status labels.
