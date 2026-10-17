---
name: diagnose
description: Diagnose a bug before it's planned: a red check, a minimised repro, ranked hypotheses, a proven cause. Started by the issue skill for a bug with no plan yet and nothing left to ask.
user-invocable: false
model: opus
effort: high
---

# Diagnose a bug

The issue skill sent you here, and its rules (comments, the status label, the issue's type,
overlap, bounds) hold throughout. The phases below are adapted from Matt Pocock's
`diagnosing-bugs` skill (see `THIRD_PARTY.md` in the plugin), for an unattended run: the
user isn't there to re-rank hypotheses or supply a missing artifact, so the plan shows the
first and a `questions` comment asks for the second.

Your output is a proven cause behind a red check, handed to the plan. You diagnose and
stop there: no fix commits, and nothing of yours in the repo's tests; the fix is the
plan's and the build's. Take the phases in order; skip one only when you can say why.

Start by reading the code the issue points at, with the project's vocabulary (a
`GLOSSARY.md` if it has one) and its ADRs in the area. That tells you where the bug could
be; the theory of the cause waits for the check. Done when you can name the code path the
symptom runs through.

**Redact** every secret in the commands, outputs and artifacts you show in comments:
write `<REDACTED>` in its place. Build checks against environment variables, so the
credential stays in the environment, and quote only the lines of a captured artifact that
carry the signal.

## Phase 1: Build a feedback loop

**This is the skill.** A tight pass/fail signal that goes **red** on *this* bug finds the
cause; bisection, hypotheses and instrumentation just consume it, and no amount of reading
code replaces it. Spend most of your effort here, and be creative.

Ways to build one, roughly in this order:

1. A failing test at whatever seam reaches the bug: unit, integration, end to end.
2. A `curl` or HTTP script against a dev server you start.
3. A CLI call on a fixture input, diffed against a known-good snapshot.
4. A headless browser script that asserts on the DOM, console or network.
5. A replay of a captured request, payload or event log through the code path alone.
6. A throwaway harness: a minimal part of the system that calls the buggy path.
7. A property or fuzz loop, for "sometimes wrong output".
8. A bisection harness, when the bug appeared between two known states: automate "check at
   state X" so `git bisect run` can drive it.
9. A differential loop: the same input through two versions or configs, diffed.

Nobody is at a terminal, so the check runs without a person to click or look.

Then **tighten** it: faster (cache setup, narrow the scope), sharper (assert the specific
symptom, not "didn't crash"), more deterministic (pin time, seed randomness, isolate the
file system, freeze the network). A 2-second deterministic check is a debugging superpower;
a 30-second flaky one is barely better than none. For a bug that only shows sometimes, aim
for a higher reproduction rate, not a clean repro: loop the trigger 100 times, add stress,
narrow the timing, until the rate is high enough to debug against.

**Where it lives.** The check is scratch: an untracked directory outside the worktree (from
`mktemp -d`), kept out of the repo's tests and out of every commit. Remove the directory
before you hand on. The plan carries the command and the minimised repro in text, because
the build runs in a fresh session that can't see this directory.

Phase 1 is done when you can name **one command** you've **already run** (the command and
its output, redacted) that is:

- **Red-capable:** it drives the real bug path and asserts the user's exact symptom, so it
  goes red on this bug and green once it's fixed. A check that merely runs without
  erroring can't catch this specific bug.
- **Deterministic:** the same verdict every run (or a pinned, high rate for a flaky bug).
- **Fast:** seconds, not minutes.
- **Unattended:** it runs without a person.

**No red-capable check.** A cause without a red check is a guess, and a plan built on a
guess builds the wrong fix. Post a `questions` comment instead (the skill name in its
header is `diagnose`), then end the run:

- **What you tried:** each way above, and what stopped it, in a line.
- **What you need:** access to whatever environment reproduces it, a redacted captured
  artifact (a log, a HAR, a stack trace, a core dump), or permission to add temporary
  instrumentation there. One line each, the likeliest first.

The user's reply starts the next run, which diagnoses again with what they gave.

## Phase 2: Reproduce and minimise

Run the check and watch it go red. Confirm:

- It fails the way the **user** described, and not a different failure nearby: the wrong
  bug gets the wrong fix.
- It fails on repeated runs, or at a high enough rate.
- You've captured the exact symptom (error, wrong output, timing), so the plan can say what
  "fixed" looks like.

Then **minimise**: cut inputs, callers, config, data and steps one at a time, re-running the
check after each cut, and keep only what's load-bearing. A minimal repro leaves fewer moving
parts to suspect, and becomes the failing test the plan's first ticket writes. Done when
removing any remaining element turns the check green; the next phase starts from a
reproduced, minimised bug.

## Phase 3: Hypothesise

Write 3-5 ranked hypotheses before testing any of them: a single one anchors you on the
first plausible idea. Each is **falsifiable** and states its prediction:

> If <X> is the cause, then <changing Y> makes the bug disappear / <changing Z> makes it worse.

A hypothesis with no prediction is a vibe: sharpen it or drop it.

The list goes in the plan, each hypothesis with its verdict (proven, ruled out), so you
don't wait on the user to re-rank it: they overrule you when they read the plan. Done when
every hypothesis has a prediction.

## Phase 4: Instrument

Each probe maps to one prediction from phase 3 and changes **one variable at a time**.
Prefer a debugger or REPL (one breakpoint beats ten logs), then targeted logs at the
boundaries that tell the hypotheses apart. For a performance regression, logs mislead:
take a baseline measurement (a timing harness, a profiler, a query plan) and bisect
against it.

Tag every debug log with a unique prefix, such as `[DEBUG-a4f2]`, so the cleanup is one
`grep`.

To test a hypothesis you may change the code. Revert every such change when the probe is
done, and `git diff` to confirm it landed back where it started. When you forced a red or
a green by editing code or a fixture, diff against a pristine copy to prove the edit took
before you trust the result.

The cause is **proven** when a probe changed the check's verdict as the hypothesis
predicted. A ruled-out hypothesis tells you something: rank new ones with it. When two
rounds leave none proven, treat it as having no usable check: post the `questions` comment
above with what you ruled out, rather than plan on a guess.

## Clean up, then plan

Before you hand on:

- every `[DEBUG-...]` tag is gone (`grep` the prefix), `git status` shows nothing of yours,
  and the scratch directory is removed;
- the check still goes red on the original, un-minimised scenario (run it once more, before
  the scratch directory goes).

Done when both hold. Then invoke `nightshift:plan`, handing it:

- **the cause**, in a sentence or two, with how you proved it;
- **the red check:** the command, its red output (redacted), and the minimised repro;
- **the ranked hypotheses,** each with its prediction and verdict.

The plan shows all three. Its first ticket turns the minimised repro into a failing test at
a seam where it exercises the real bug path, and the fix makes it pass. A test at a seam too
shallow to replicate the bug (a one-caller test of a many-caller bug) gives false
confidence: when no right seam exists, say so as a finding for the plan, since the
architecture is stopping the bug being locked down.
