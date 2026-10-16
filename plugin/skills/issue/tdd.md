# Test first

Adapted from Matt Pocock's `tdd` skill (see `THIRD_PARTY.md` in the plugin). Build each
ticket that has logic to test as a red → green loop, at the seams the plan's testing
decisions name. The plan's approval is the user's approval of those seams; a test that
needs a seam the plan didn't name is a decision for a `blocked` comment, unless it's
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
