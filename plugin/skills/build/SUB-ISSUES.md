# Sub-issues

One sub-issue per ticket, made with `gh issue create --parent <issue> --title … --body …`
where gh supports `--parent` (`gh issue create --help` lists it), so the user can follow
the build in GitHub's UI.

- **Title** it `T1: <ticket title>`, so it can be found again. **Body:** the ticket's text,
  its blockers and acceptance criteria as the plan has them, and `Part of #<issue>`.
- **No `agent` label,** and no other: the watcher works issues labelled `agent`, and a
  sub-issue is not one to work.
- **Without `--parent`,** create the issue, then attach it through the REST API:
  `gh api repos/{owner}/{repo}/issues/<issue>/sub_issues -f sub_issue_id=<id>`. The id is
  the new issue's `id` field (`gh api repos/{owner}/{repo}/issues/<n> --jq .id`), not its
  number.
- **Reuse before creating.** A resumed or fresh build reuses the sub-issues already under
  the issue, found by title: `gh issue view <issue> --json subIssues`, or `gh api
  repos/{owner}/{repo}/issues/<issue>/sub_issues`. It creates only the tickets with none,
  so each ticket has exactly one.
- A change the user's reply made to a ticket goes in its sub-issue's body too, so the
  sub-issue and the plan agree.

Done when `gh issue view <issue> --json subIssues` lists one sub-issue per ticket. Keep
each one's number for its brief and for the pull request body.
