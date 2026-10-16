---
name: build
description: Build an issue's approved plan, ticket by ticket and test-first, then open its pull request with the finish skill. Started by the issue skill when the user approved the plan.
user-invocable: false
---

# Build an issue

The issue skill sent you here, and its rules (comments, the status label, the issue's type,
overlap, bounds) hold throughout. The test-first guidance below is adapted from Matt
Pocock's `tdd` skill (see `THIRD_PARTY.md` in the plugin).

`nightshift label building`, then build the tickets in order, in this worktree:

- Each ticket test-first where it has logic to test (**test first**, below), checked the
  way the repo is checked: in a React Native app, on its own simulator with the run-app
  skill; elsewhere with the project's build, typecheck, lint and tests.
- Commit each ticket on its own, in the repo's and the user's commit style, and post a
  short `progress` comment: what the ticket delivered and how it was checked.
- A ticket that can't be finished (a decision the plan didn't cover, a broken
  dependency): a `blocked` comment saying what's needed, and end the run.
- After the last ticket, check the **overlap** (in the issue skill) again, since other
  work may have started or merged since the plan, and invoke the `nightshift:finish`
  skill to open the pull request, with the overlap lines in its body. Then a `done`
  comment with its link and what's in it. The watcher removes the worktree after this
  run.

## Test first

Build each ticket that has logic to test as a red → green loop, at the seams the plan's
testing decisions name. The plan's approval is the user's approval of those seams; a test
that needs a seam the plan didn't name is a decision for a `blocked` comment, unless it's
clearly inside one that was.

## A good test

It verifies behaviour through a public interface, not implementation details: the code
can change entirely and the test still holds. It reads like a specification ("user can
check out with a valid cart"), uses the public API only, and has one logical assertion.

Anti-patterns:

- **Implementation-coupled:** mocks internal collaborators, tests private functions, or
  verifies through a side channel (querying the database instead of using the interface).
  The tell: it breaks on a refactor that didn't change behaviour.
- **Tautological:** the expected value is recomputed the way the code computes it, so it
  passes by construction. Expected values come from an independent source: a known
  literal, a worked example, the spec.
- **Horizontal:** all the tests first, then all the code. Tests written ahead verify
  imagined behaviour.

## Mocks

Only at system boundaries: external APIs, time and randomness, sometimes the database or
the file system. Never your own modules. At a boundary, prefer an interface that's easy to
fake: dependencies passed in, one function per external operation rather than one generic
fetcher.

## The loop

- **Red before green.** Write one failing test, see it fail, then only enough code to pass
  it. No speculative features.
- **One slice at a time.** One seam, one test, one minimal implementation per cycle; let
  each cycle inform the next.
- **Refactor after,** with the tests green, not inside the loop.
- A repo without tests at that seam: check the ticket the way the repo is checked (build,
  typecheck, lint, a scratch run, the simulator), and say so in the `progress` comment.
