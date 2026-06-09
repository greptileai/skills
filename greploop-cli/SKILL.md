---
name: greploop-cli
description: >
  Iteratively reviews and fixes local code using the installed Greptile CLI directly. Runs
  `greptile review` against the current branch/base branch, checks CLI availability, login state,
  and repository access, fixes actionable findings, re-runs the CLI review, and repeats until the
  code is clean. Use when the user wants Greptile review without GitHub, GitLab, or Perforce PR/MR/CL
  abstractions.
license: MIT
compatibility: Requires git and an authenticated Greptile CLI (`greptile`) with access to review the repository.
metadata:
  author: greptileai
  version: "1.0"
allowed-tools: Bash(greptile:*) Bash(git:*) Bash(jq:*) Bash(rg:*)
---

# Greploop CLI

Review local code directly with the Greptile CLI, fix actionable findings, and repeat until clean.

Do not use GitHub, GitLab, or Perforce APIs in this skill.

## Inputs

- `-b <branch>` or `--branch <branch>` (optional): base branch passed to `greptile review`.
- `--resume` (optional): continue the latest unfinished CLI review for this repository on the first pass.
- `--max-iterations <N>` (optional): override the default cap of 5.

## Instructions

### 0. Preflight

Run these checks before editing code:

```bash
greptile --help
greptile whoami
```

`greptile whoami` can exit successfully while logged out. Treat output containing `not signed in`
case-insensitively as unauthenticated and stop with: run `greptile login`.

Verify this is a git repository and capture the review target:

```bash
git rev-parse --show-toplevel
git rev-parse --abbrev-ref HEAD
git status --short
git remote -v
```

If a base branch was supplied, verify it exists locally or as a remote ref before passing it to
Greptile. If it does not exist, stop and ask the user for a valid base branch.

### 1. Loop

Repeat the following cycle. **Max 5 iterations** unless `--max-iterations <N>` was provided.

#### A. Run Greptile review

The first review command is also the repository access check. Build the command from the inputs:

```bash
greptile review --agent --no-color --diff --context=15
greptile review --branch=<BASE_BRANCH> --agent --no-color --diff --context=15
greptile review --resume --agent --no-color --diff --context=15
```

Use `--resume` only when requested, and usually only on the first pass. After code changes, run a
fresh review without `--resume` unless the CLI explicitly reports that resuming is required.

If the review exits nonzero, stop before editing. Classify common failures from stderr/stdout:

- `not signed in`: ask the user to run `greptile login`.
- Access, permission, repository not found, or repository not configured errors: report that the CLI
  session cannot review this repo yet and include the exact Greptile message.
- Invalid base branch errors: report the branch that failed and ask for a valid base.
- Any other CLI error: report the command and exact output.

#### B. Collect findings

Prefer the `--agent --no-color --diff --context=15` output because it is directly usable for code
fixes. If the output is ambiguous or a structured list would help, prefer showing the completed
review as JSON when a review ID is available:

```bash
greptile review show <REVIEW_ID> --json --no-color
```

Only use `greptile review show` with an explicit review ID when the previous output exposed one.
Avoid interactive selection prompts. Use `greptile review --json --no-color` only when intentionally
running a fresh review in JSON mode.

Parse:

- confidence score, if present;
- all findings with file, line/range, severity, and body;
- whether the CLI reports no findings or a clean review.

Track findings while working:

| Field | Meaning |
| --- | --- |
| Source | CLI output or `greptile review show` output |
| Location | File path and line/range if available |
| Body | Greptile's actionable text |
| Status | fixed, resolved-no-change, false-positive, or remaining |

#### C. Check exit conditions

Stop the loop if **any** of these are true:

- Greptile reports confidence **5/5** and no findings remain.
- Greptile reports no findings or a clean review and does not expose a confidence score.
- Max iterations reached.

#### D. Fix actionable findings

For each Greptile finding:

1. Read the relevant file and surrounding code before editing.
2. Determine whether the finding is actionable, informational, or a false positive.
3. If actionable, make the smallest scoped code change that addresses it.
4. If informational or a false positive, record why no code change was made.
5. Do not revert pre-existing user changes; work with them if they overlap.

#### E. Verify locally

Run focused verification when the touched code has obvious tests, typechecks, linters, or build
steps. Prefer commands already defined by the repo. If no verification is obvious, record
`Verification: not run` in the final report.

#### F. Re-review

For the CLI provider, do not commit, push, or create branches unless the user explicitly asks.
After fixes and local verification, re-run `greptile review` with the same base branch arguments.
Use `--resume` only when the CLI explicitly requires it after the first pass.

### 2. Report

After exiting the loop, summarize:

```text
Greploop complete.
  Provider:      Greptile CLI
  Target:        <current branch> against <base branch or repository default>
  Iterations:    <N>
  Confidence:    <X/5 or unavailable>
  Fixed:         <N findings>
  Remaining:     0
  Verification:  <commands run, or "not run">
```

If incomplete:

```text
Greploop stopped after <N> iterations.
  Provider:      Greptile CLI
  Target:        <current branch> against <base branch or repository default>
  Confidence:    <X/5 or unavailable>
  Fixed:         <N findings>
  Remaining:     <N>

Remaining issues:
  - <file>:<line> - <summary>
```
