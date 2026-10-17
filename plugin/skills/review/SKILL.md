---
name: review
description: Review an issue's built change before its pull request opens, with a Spec and a Standards subagent, then fix what's real in one pass. Started by the build skill after the last ticket, before the finish skill.
user-invocable: false
model: sonnet
effort: high
---

# Review the change

The build skill sent you here after the last ticket, before the `nightshift:finish`
skill, and the issue skill's rules hold throughout. Adapted from Matt Pocock's
`code-review` skill (see `THIRD_PARTY.md` in the plugin).

You built the change, so you're the one who can't see what it misses. Two fresh subagents,
without this session's context, review it instead, one per axis: **Spec** (does it do what
the approved plan asked) and **Standards** (does it follow the repo's conventions). A
change that follows every standard but does the wrong thing, or the other way round, can't
hide behind the other axis, so the axes stay separate. Then you sort what they found,
once.

## 1. Pin the change

`git fetch origin`; the default branch is `origin/` plus
`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`. The change is
`git diff <default branch>...HEAD` (three dots: against the merge-base), its commits
`git log --oneline <default branch>..HEAD`. Done when both commands run. An empty diff has
nothing to review: say so when you report, and go on.

## 2. Gather what they review against

- **The plan:** the latest `plan` comment on the issue (`<!-- nightshift:plan -->`), in
  full, plus any reply of the user's after it that changed it.
- **The standards:** every file in the repo that says how code here is written:
  `CLAUDE.md` files, `CONTRIBUTING.md`, `CODING_STANDARDS.md`, a README's section on
  development or tests, and the commit and pull request conventions and the `CLAUDE.md`
  rules you were given for this session (paste those in: a subagent doesn't see them).

Done when the plan is in hand and every such file is on the list, `CODING_STANDARDS.md` and
`CONTRIBUTING.md` included when they exist.

## 3. Start both reviewers

Start both subagents in one message, so they run in parallel, in the foreground
(`run_in_background: false`): Spec as `nightshift:spec-review`, Standards as
`nightshift:standards-review`, each without a `model`, so it runs on the model its agent
sets. Each prompt stands alone: this worktree's path, the diff and log commands, what it
reviews against, and its brief below. Tell each it only reads (no edits, commits, comments
or new issues). Each finding gives `file:line`, quotes the hunk (and the plan or standard
it's measured against), and says whether it's a hard miss or a judgement call. Under 400
words each.

### Spec

Give it the plan. Its brief:

- each ticket's acceptance criteria: met, partial, or missing;
- what the diff does that the plan didn't ask for;
- what looks implemented but wrong: the plan says one thing, the code does another;
- the tests: a test the plan or a ticket asked for that isn't there, a path the change
  adds (a branch, an error case, a flag) that no test runs, and a test at a seam the plan's
  testing decisions didn't name.

### Standards

Give it the standards files and the conventions you pasted, plus the smell baseline from
[SMELLS.md](SMELLS.md), read and pasted in full (the subagent has no other access to it).
The repo's documented standards win: where they endorse something a smell would flag, it
isn't one. A smell is always a judgement call ("possible Feature Envy"), never a hard miss.
Tooling already enforces its own rules, so the subagent leaves those out. Its brief: where
the diff breaks a documented standard (citing the file and the rule), a `CLAUDE.md` change
in the diff, checked against those rules (nothing to say when there's none), the baseline
smells it spots (the ticket loop doesn't refactor, so this is where refactoring is found),
and leftovers: debug output, commented-out code, TODOs, stray files, a scratch script.

Done when both reports are back.

## 4. Sort the findings

Take every finding from both reports and put each in one of three, per axis:

- **Fix:** it's real, and the plan already decides how it should be.
- **Dismissed:** it's wrong, or the plan settled it on purpose, or it's outside this
  issue. Note the reason in a line: the user reads it to judge whether to trust it.
- **Open:** it's real, but fixing it is the user's call (behaviour, scope, a trade-off
  the plan didn't cover). It goes in the pull request as left open, and the pull request
  opens all the same.

Done when every finding sits in one list.

## 5. One fix pass

Fix everything under **Fix** (refactorings the smells call for included), run the checks
for what the fixes touched, as a ticket does (the build skill then runs the whole suite
once after this, only under the local line, or the default line in a repo with no CI, and
never under the nothing line), and commit the fixes on their own (`fix: address review
findings`, or the type that fits, in the repo's and the user's commit style), apart from
any ticket's commit.
That's one review and one fix pass, whatever the fixes touch. A fix that breaks the checks
and can't be put right quickly is undone and moves to **Open**.

Done when the checks pass and the fixes are committed.

## 6. Hand back

Keep the three lists, each finding a line with its axis, and go back to the build skill,
which reports them. Count per axis and name each axis's worst finding; the axes stay
unranked against each other.
