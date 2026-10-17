---
name: questions
description: Ask the user, in one questions comment, the decisions an issue and its code don't settle. Started by the issue skill for an issue with no plan and open decisions.
user-invocable: false
model: opus
effort: high
---

# Ask about an issue

The issue skill sent you here, and its rules (comments, the status label, the issue's type,
overlap, bounds) hold throughout. The guidance below is adapted from Matt Pocock's
`grilling` skill (see `THIRD_PARTY.md` in the plugin), for an issue: every round is one
`questions` comment, and the user's reply starts the next run.

Interview the user **relentlessly** through the issue, until you reach a shared
understanding. Map the issue as a **design tree**: every decision branches into the
decisions that hang off it. The **frontier** is every decision whose prerequisites are
already settled: the questions you can ask now without guessing at answers you haven't
heard yet.

1. **Read** the issue and the code. Done when you can name each decision the work turns on.
2. **Sort** the decisions. Facts are yours: look up what the code, the tools or the docs
   can tell you (a wide search goes to a subagent, in the foreground) and settle it
   yourself, so the user is never asked a fact. Decisions are the user's (behaviour, scope,
   UX, trade-offs), and you ask the ones that change what gets built and settle the rest.
   Done when every decision is a fact you found, one you settle, or a user's decision.
3. **Find the frontier.** The user's decisions whose prerequisites are settled. A question
   whose answer depends on another question still open in this round belongs to a later
   round. Done when each question in it stands alone.
4. **Ask the whole frontier** in one `questions` comment, in the format below, then end the
   run. Done when the comment is posted.

The comment:

- **Numbered, each with a recommendation.** Word each question so "yes" accepts your
  recommended answer, and give lettered options where there are several, with what each
  costs in the same line.
- **Short.** Straight to question 1. One line per question or option; a fact goes in only
  when the answer turns on it.
- **Settled myself.** Say what you decided, so the user can overrule it in the same reply:
  the three that matter most, a line each, and any others in a collapsed `<details>` block.

```
1. **<decision>?** I recommend **a**.
   - a. <option>: <what it costs>.
   - b. <option>: <what it costs>.
2. **<decision>?** <recommendation>. Yes?

Settled myself: <decision>; <decision>.

Reply e.g. "1 a, 2 yes".
```

Each reply reshapes the tree: settled decisions push the frontier outward and unblock the
questions that depended on them. Recompute the frontier and ask the next round while it
has questions. When the frontier is empty, every branch has been visited and nothing is
left silently assumed: the issue is ready for its plan.
