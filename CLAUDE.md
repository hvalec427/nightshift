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
  The whole suite takes over 10 minutes, past the Bash tool's timeout: when it moves to the
  background, wait on it in the same turn.
- `shellcheck -S warning nightshift install.sh scripts/*.sh scripts/fake/*` — CI's exact file
  list (`.github/workflows/check.yml`).
- `bash scripts/commit-lint.sh --title "<subject>"` checks a commit or pull request title.

## Conventions

- nightshift runs on macOS (launchd, BSD `date`, bash 3.2), and CI runs its tests there: use
  BSD-compatible flags, no GNU-only ones.
- Skills are prose in `plugin/skills/<name>/SKILL.md` with frontmatter (`name`,
  `description`, `user-invocable: false`, `model`, `effort`) that `scripts/test-skills.sh` checks.
- Tests drive nightshift through the fakes in `scripts/fake/` (`gh`, `claude`, `curl`); the
  README's Tests section says how, and names the one exception.

## Pointers

- README: Tests (how a test reads), Releases (versioning from commit types), Config,
  Status labels.
