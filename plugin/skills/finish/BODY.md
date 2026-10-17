# The pull request body

Adapted from Matt Pocock's `pr` skill (see `THIRD_PARTY.md` in the plugin). The body is for
a reviewer who has the diff open: it shows the change's shape, how you know it works, and
how risky it is to land. It starts at the first heading with no preamble, keeps prose brief
and uses the project's own words for things.

```markdown
## Summary

<the smallest visual that shows the change>

## Evidence

- **Before:** <screenshot, output or failing test run>
  **After:** <screenshot, output or passing test run>

## Merge Danger

**Door:** <one-way or two-way>

**Blast radius:** <narrow or wide>

<optional: what could break if the change is wrong>
```

- **Summary.** The smallest view that makes the key point: pseudocode for logic, a call
  tree for control flow, a file tree for a broad refactor, or a diff sketch when the
  surrounding shape already exists. One visual, sometimes two, with the short text it
  supports beside it. Keep the calls, files and boundaries a reviewer needs.
- **Evidence.** A before and an after. A screenshot or recording when the change is visual
  (the media from step 2 go here). Otherwise the exact test that failed and now passes, as
  pseudocode, or the output that changed. "Tests are green" alone is a claim; a before and
  an after is evidence. What couldn't be verified goes here too, said plainly.
- **Merge Danger.** State the call, so the reviewer can disagree with it. You graded your
  own change, so doubt "two-way, narrow" most.
  - **Door.** Two-way when it's cheap to reverse. One-way when it destroys something or
    can't be walked back: a migration, a removed public interface, data written in a new
    format.
  - **Blast radius,** in one word. Wide when the change reaches past its feature: config,
    the repo's persisted state or data layout (nightshift's `~/.nightshift` layout), an
    installer, a CLI's commands or flags, or what a run can reach. Narrow otherwise. The
    merge skill takes a wide one as a reason to ask for a look.

## Under nightshift

The body also carries, from the build:

- the open review findings, a line each, under **Left open:** at the end of Merge Danger;
- the overlap lines, as written with their markers (`<!-- nightshift:after #N -->`,
  `<!-- nightshift:overlaps #N -->`), after Merge Danger;
- last, the closing line, `Closes #<issue>` for the issue the run works, so the merge
  closes it.

Outside nightshift the body ends after Merge Danger: no `Closes` line unless the user names
an issue to close, and no overlap lines or review findings.
