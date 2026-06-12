---
name: review-branch
description: >
  Reviews the current local Git branch with Greptile CLI before opening a PR or MR. Compares committed
  branch changes against a base branch, reports Greptile findings from the terminal, optionally fixes
  actionable issues, and can rerun the CLI review. Use when the user wants a fast pre-PR Greptile
  review without creating or triggering a PR/MR review comment, check run, dashboard review, or greploop.
license: MIT
compatibility: Requires git and Greptile CLI installed and authenticated with `greptile login`.
metadata:
  author: greptileai
  version: "1.0"
allowed-tools: Bash(git:*) Bash(greptile:*)
---

# Review Branch

Run Greptile CLI against the current local branch before opening a PR/MR. This skill is for committed branch diffs only: Greptile CLI ignores uncommitted changes.

## Inputs

- **Base branch** (optional): If not provided, use the repository default branch when it can be inferred, otherwise ask the user.
- **Output format** (optional): `agent` by default. Use `json` when another tool needs to parse the result.
- **Loop mode** (optional): If requested, fix actionable findings and rerun Greptile CLI until no actionable findings remain or the user chooses to stop.

## Instructions

### 0. Confirm prerequisites

Run from the repository root or move there first:

```bash
git rev-parse --show-toplevel
greptile --version
greptile whoami
```

If `greptile whoami` fails, ask the user to authenticate with:

```bash
greptile login
```

Do not use PR/MR review triggers for this workflow. In particular, do not post `@greptile review`, do not trigger Greptile through GitHub/GitLab comments, and do not use dashboard or app-based review flows.

### 1. Determine review scope

Identify the current branch and working tree state:

```bash
git branch --show-current
git status --short
```

If there are uncommitted changes, tell the user that Greptile CLI will ignore them. Ask whether they want to commit first, or continue with only committed branch changes in scope.

Choose the base branch:

```bash
git symbolic-ref --quiet --short refs/remotes/origin/HEAD
```

If `origin/HEAD` is unavailable, try `main` or `master`. If the intended base branch is still unclear, ask the user.

Verify there are committed changes to review:

```bash
git diff --stat <BASE>...HEAD
git rev-list --count <BASE>..HEAD
```

If there are zero commits against the base branch, stop and report that Greptile CLI has nothing to review.

### 2. Run Greptile CLI

For agent-readable text:

```bash
greptile review -b <BASE> --agent --no-color
```

For machine-readable output:

```bash
greptile review -b <BASE> --json --no-color
```

To resume the latest unfinished review:

```bash
greptile review --resume --agent --no-color
```

If the user wants inline code context:

```bash
greptile review -b <BASE> --diff --context=25 --agent --no-color
```

### 3. Categorize findings

Classify each finding before changing code:

| Category | Meaning |
|---|---|
| **Actionable** | Correctness, security, maintainability, test, or requirement issue that should be fixed |
| **Needs decision** | Plausible issue, but depends on product intent, API contract, or team tradeoff |
| **Not actionable** | False positive, already addressed, outside the reviewed diff, or only a style preference |

Report the categories clearly. Do not present a clean Greptile result as covering uncommitted local changes.

### 4. Fix findings if requested

If the user asks to fix findings:

1. Read the surrounding code and relevant project instructions.
2. Make the smallest code change that addresses the actionable issue.
3. Run focused validation that matches the changed surface.
4. Commit only if the user explicitly asks you to commit.

If the user requested loop mode, rerun Greptile only after the fixes are committed with explicit user approval. If the user does not approve a commit, stop after local validation and report that Greptile was not rerun because the fixes remain uncommitted.

After the fixes are committed, rerun:

```bash
greptile review -b <BASE> --agent --no-color
```

Stop when there are no actionable findings, the remaining findings need user/product decision, or the user asks to stop.

### 5. Prepare for PR/MR creation

When the branch is ready, summarize the review result and ask before creating or pushing a PR/MR. This skill does not create PRs/MRs by itself; hand off to the user's normal PR/MR creation workflow when explicitly requested.

## Output format

```text
Review Branch complete.
Base: main
Branch: feature/example
Greptile command: greptile review -b main --agent --no-color
Actionable findings: 0
Needs decision: 1
Not actionable: 2
Validation: npm test -- auth.test.ts
Next: ready for PR creation when requested
```

If not complete:

```text
Review Branch stopped.
Base: main
Branch: feature/example
Actionable findings remaining: 2
Reason: product decision needed before changing API behavior
```

## Reference

For exact Greptile CLI flags and examples, see [Greptile CLI Reference](references/greptile-cli.md).
