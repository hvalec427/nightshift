---
name: tdd
description: Test-first guidance, a red → green loop at the plan's testing seams. Loaded by the ticket subagent, and by the build skill for a one-ticket plan, before it builds.
user-invocable: false
model: sonnet
effort: high
---

# Test first

The red → green loop, and what makes it produce tests worth keeping. Every section applies
on every cycle: read them before the loop, and again when a test feels off. Adapted from
Matt Pocock's `tdd` skill (see `THIRD_PARTY.md` in the plugin).

## What a good test is

It verifies behaviour through a public interface, whatever the implementation does: the
code can change entirely and the test still holds. It reads like a specification ("user can
check out with a valid cart"), uses the public API only, and has one logical assertion.
[tests.md](tests.md) has examples and [mocking.md](mocking.md) says when to mock.

## Mocks

Mock at system boundaries: external APIs, time and randomness, sometimes the database or
the file system. Your own modules run for real. At a boundary, prefer an interface that's
easy to fake: dependencies passed in, one function per external operation rather than one
generic fetcher. See [mocking.md](mocking.md).

## Seams: where tests go

A **seam** is the public boundary you test at: where you observe behaviour without reaching
inside. Tests live at seams.

**Test only at the plan's seams.** The plan's testing decisions name them, and its approval
is the user's approval of them. Before the first test, write down the seams under test,
from the plan. A test that needs a seam the plan didn't name is a decision for a `blocked`
comment (a `BLOCKED:` reply, for a subagent), unless it's clearly inside one that was.
Effort then lands on the critical paths and the complex logic, not on every edge case.

## Anti-patterns

- **Implementation-coupled:** mocks internal collaborators, tests private functions, or
  verifies through a side channel (querying the database instead of using the interface).
  The tell: it breaks on a refactor that didn't change behaviour.
- **Tautological:** the assertion recomputes the expected value the way the code does
  (`expect(add(a, b)).toBe(a + b)`), so it passes by construction and can never disagree
  with the code. Take expected values from an independent source: a known literal, a
  worked example, the spec.
- **Horizontal slicing:** all the tests first, then all the code. Tests written in bulk
  verify imagined behaviour: the shape of things, not what a caller does, and they commit
  you to a test structure before you understand the implementation. Work in **vertical
  slices**: one test, one implementation, repeat. The first is a **tracer bullet** that
  proves one path end to end, and each next test responds to what the last taught you.

## Rules of the loop

- **Red before green.** Write the failing test first and see it go **red**, then only
  enough code to pass it.
- **One slice at a time.** One seam, one test, one minimal implementation per cycle; the
  next test comes from what this one taught.
- **Refactoring belongs to the review stage** (the `nightshift:review` skill), outside the
  red → green cycle.
- **A repo without tests at that seam:** check the ticket the way the repo is checked (build,
  typecheck, lint, a scratch run, the running app), and say so in the summary or `progress`
  comment.

Done when the ticket's behaviour has a test that went red and is green, at a seam the plan
named, or the repo's own check passes where the repo has no test at that seam.
