---
name: review
description: Review an issue's built change before its pull request opens, with two fresh subagents (Spec: does it do what the approved plan asked; Standards: does it follow the repo's conventions), then fix what's real in one pass. Started by the build skill after the last ticket, before the finish skill.
user-invocable: false
---

# Review the change

The build skill sent you here after the last ticket, before the `nightshift:finish`
skill, and the issue skill's rules hold throughout. Adapted from Matt Pocock's
`code-review` skill (see `THIRD_PARTY.md` in the plugin). You built
the change, so you're the one who can't see what it misses: two subagents that start
without this session's context look at it instead, one per axis, so a change that follows
every standard but does the wrong thing (or the other way round) can't hide behind the
other axis. Then you go through what they found, once.

## 1. Pin the change

`git fetch origin`; the default branch is `origin/` plus
`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`. The change is
`git diff <default branch>...HEAD` (three dots: against the merge-base), its commits
`git log --oneline <default branch>..HEAD`. An empty diff has nothing to review: say so
when you report, and go on.

## 2. Gather what they review against

- **The plan:** the latest `plan` comment on the issue (`<!-- nightshift:plan -->`), in
  full, plus any reply of the user's after it that changed it.
- **The standards:** every file in the repo that says how code here is written:
  `CLAUDE.md` files, `CONTRIBUTING.md`, `CODING_STANDARDS.md`, a README's section on
  development or tests, and the commit and pull request conventions and the `CLAUDE.md`
  rules you were given for this session (paste those in: a subagent doesn't see them).

## 3. Start both reviewers

Start both subagents in one message, so they run in parallel, in the foreground
(`run_in_background: false`), with the general-purpose type. Each prompt stands alone:
this worktree's path, the diff and log commands, what it reviews against, and its brief
below. Tell each it only reads: no edits, commits, comments or new issues. Each finding
gives `file:line`, quotes the hunk (and the plan or standard it's measured against), and
says whether it's a hard miss or a judgement call. Under 400 words each.

### Spec

Give it the plan. Its brief:

- each ticket's acceptance criteria: met, partial, or missing;
- what the diff does that the plan didn't ask for;
- what looks implemented but wrong: the plan says one thing, the code does another;
- the tests: a test the plan or a ticket asked for that isn't there, and a path the change
  adds (a branch, an error case, a flag) that no test runs.

### Standards

Give it the standards files and the conventions you pasted, plus this smell baseline, in
full. The repo's documented standards win: where they endorse something a smell would
flag, it isn't one. A smell is always a judgement call ("possible Feature Envy"), never a
hard miss. Skip what tooling already enforces. Its brief: where the diff breaks a
documented standard (citing the file and the rule), a `CLAUDE.md` change in the diff,
checked against those rules (nothing to say when there's none), the baseline smells it
spots, and leftovers: debug output, commented-out code, TODOs, stray files, a scratch
script.

- **Mysterious Name:** a name that doesn't say what it does or holds → rename it.
- **Duplicated Code:** the same logic in more than one hunk or file → one shared shape.
- **Feature Envy:** a function that works on another module's data more than its own →
  move it to the data.
- **Data Clumps:** the same few values always passed together → one type for them.
- **Primitive Obsession:** a string or number standing in for a concept with rules →
  its own small type.
- **Repeated Switches:** the same `case`/`if` cascade in several places → one map both
  use.
- **Shotgun Surgery:** one logical change spread over many files → gather it.
- **Divergent Change:** one file edited for several unrelated reasons → split it.
- **Speculative Generality:** parameters, hooks or layers no requirement needs → inline
  them back.
- **Message Chains:** long `a.b().c().d()` walks the caller shouldn't know → one method.
- **Middle Man:** a function that only passes the call on → call the target.
- **Refused Bequest:** an implementation that ignores most of what it inherits →
  composition instead.

## 4. Sort the findings

Go through every finding from both, and put each in one of three:

- **Fix:** it's real, and the plan already decides how it should be.
- **Dismissed:** it's wrong, or the plan settled it on purpose, or it's outside this
  issue. Note the reason in a line: the user reads it to judge whether to trust it.
- **Open:** it's real, but fixing it is the user's call (behaviour, scope, a trade-off
  the plan didn't cover). It goes in the pull request as left open; it isn't a reason to
  block, since the pull request is still worth opening.

## 5. One fix pass

Fix everything under **Fix**, run the checks the tickets ran, and commit the fixes on
their own (`fix: address review findings`, or the type that fits, in the repo's and the
user's commit style), not folded into a ticket's commit. That's one review and one fix
pass: no second review, whatever the fixes touch. A fix that breaks the checks and can't
be put right quickly is undone and moves to **Open**.

## 6. Hand back

Keep the three lists, each finding a line with its axis, and go back to the build skill,
which reports them.
