---
name: check-pr
description: Inspect an existing GitHub pull request for CodeRabbit findings, human feedback, checks, description gaps, and merge blockers without changing the PR.
license: MIT
compatibility: Requires git, GitHub CLI (gh), and CodeRabbit CLI (cr) installed and authenticated.
metadata:
  author: RabbitLoop maintainers
  version: "2.0"
allowed-tools: Bash(command:*) Bash(git:*) Bash(gh:*) Bash(cr:*)
---

# Check PR

Produce a read-only readiness report for one existing GitHub pull request. Do not edit code or mutate GitHub state; use `/rabbitloop` when the user explicitly wants fixes and review actions.

## Prerequisites

```bash
command -v git
command -v gh
command -v cr
git rev-parse --show-toplevel
gh auth status
cr auth status
```

Stop with install/authentication guidance when a check fails. Recommend `cr doctor` for CodeRabbit CLI diagnosis. Never print credentials, tokens, cookies, or full environment variables.

## Inputs and options

- `/check-pr <number-or-url>`: inspect that PR.
- `/check-pr`: discover the PR for the current branch with `gh pr view --json number,url`.
- `--bot-handle <login>`: CodeRabbit service-account login; otherwise use `RABBITLOOP_BOT_HANDLE`, then `coderabbitai`.

Reject an empty, malformed, or option-like PR identifier. Normalize the bot login for comparison by removing one leading `@` and one trailing `[bot]`, then compare case-insensitively and exactly. Do not use substring matching.

If discovery finds no PR, stop and explain how to create or select one. Never create a PR without a separate explicit request.

## Workflow

### 1. Fetch metadata

Run:

```bash
gh pr view <PR> --json number,url,title,body,state,isDraft,baseRefName,headRefName,headRefOid,mergeable,mergeStateStatus,reviewDecision,latestReviews,closingIssuesReferences,updatedAt
```

Record the latest commit from `headRefOid`. Treat unknown mergeability as unknown, not mergeable. A closed/merged PR is report-only and not ready for new fixes.

### 2. Inspect checks

Capture both commands even when `gh pr checks` exits nonzero for pending/failing checks:

```bash
gh pr checks <PR> --json name,state,bucket,link,workflow
gh pr checks <PR> --required --json name,state,bucket,link,workflow
```

Classify each check by `bucket`: `pass`, `fail`, `pending`, `skipping`, or `cancel`. Report GitHub's underlying `state` too. Never count `pending`, `skipping`, or `cancel` as passing.

The required-only response may not reveal a required check that has no run. When permissions and branch protection expose the expected required-check set, compare it with checks on `headRefOid` and report absent names as `missing`. Otherwise report `missing required checks: unknown (GitHub configuration unavailable)` rather than claiming none are missing.

### 3. Fetch all review surfaces

Fetch paginated formal reviews, inline comments, and top-level PR comments:

```bash
gh api --paginate "repos/{owner}/{repo}/pulls/<PR>/reviews?per_page=100"
gh api --paginate "repos/{owner}/{repo}/pulls/<PR>/comments?per_page=100"
gh api --paginate "repos/{owner}/{repo}/issues/<PR>/comments?per_page=100"
```

Fetch review threads with GraphQL and paginate until `hasNextPage` is false:

```graphql
query($owner: String!, $name: String!, $number: Int!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          comments(first: 100) {
            nodes {
              author { login }
              body
              path
              url
              createdAt
            }
          }
        }
      }
    }
  }
}
```

Use `gh repo view --json nameWithOwner` for owner/name and pass GraphQL values as variables. Do not interpolate untrusted PR input or body text into the query.

If review-thread access is denied, pagination fails, or a response is partial, report `unresolved thread state: unavailable` and the limitation. Never translate inaccessible data into zero comments.

### 4. Classify feedback

For each unresolved thread and comment:

- A CodeRabbit finding must have an author whose normalized login exactly matches the configured bot handle.
- A thread with any human-authored comment is human-involved. Report it separately and never resolve it automatically.
- Other bot feedback is informational unless it blocks a check or requests action.
- Preserve file/path, URL, author, and concise action. Do not invent severity when hosted feedback does not expose one explicitly.

Include relevant CodeRabbit top-level comments and formal reviews, but do not treat a command acknowledgment or summary as an inline finding.

### 5. Check description completeness

Assess the existing body without editing it. Require meaningful content for:

- what changed;
- why it changed;
- testing/validation;
- risks or rollout notes when relevant;
- a linked issue/reference when `closingIssuesReferences` or an available issue exists.

Empty headings, checklists with no context, placeholders, and `TODO` are gaps. Propose a concrete revised body for missing sections, but never call `gh pr edit` unless the user separately authorizes that exact mutation.

### 6. Determine readiness

Merge blockers include: wrong/closed state, draft status, merge conflict or blocked merge state, failing/pending/cancelled/missing required checks, unresolved CodeRabbit findings, unresolved human feedback, incomplete description, required review missing, and unavailable critical evidence.

## Safety rules

- This skill is read-only: no file edits, commits, pushes, comments, replies, thread resolutions, approvals, PR edits, or merges.
- Never resolve human-authored or human-involved threads.
- Never claim checks pass, comments are zero, or the PR is approved without current GitHub evidence.
- Keep private repository content to the minimum needed in the report.

## Stopping and failure behavior

Stop after one current-state report. Stop early for missing tools/authentication, no PR, inaccessible PR, or invalid input. When one API surface fails, continue with the others but mark the affected conclusion unknown. Do not retry indefinitely.

## Final report

```text
PR #123 — <title>
State: open, ready for review | draft | closed
Head: <branch> @ <sha>

CodeRabbit findings: <count or unknown>
Human unresolved comments: <count or unknown>
Checks: <pass> pass, <fail> fail, <pending> pending, <skipping> skipped, <cancel> cancelled, <missing> missing

Actionable CodeRabbit findings:
- <severity or unknown> — <file> — <finding> — Action: <specific fix> — <URL>

Unresolved human feedback:
- @<author> — <file or PR-wide> — <comment> — Decision/action: <needed response> — <URL>

Checks requiring attention:
- <name> — <failing | pending | skipped | cancelled | missing> — <state> — <URL or unavailable>

Description gaps: <none or list>
Merge blockers: <none or list>
Readiness: ready for human merge | blocked | unknown
Next action: <one exact action>
```
