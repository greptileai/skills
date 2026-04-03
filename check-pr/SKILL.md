---
name: check-pr
description: >
  Checks a GitHub or GitLab pull request (or merge request) for unresolved review comments,
  failing status checks, and incomplete PR descriptions. Waits for pending checks to complete,
  categorizes issues as actionable or informational, and optionally fixes and resolves them.
  Use when the user wants to check a PR/MR, address review feedback, or prepare a PR for merge.
license: MIT
compatibility: Requires git and gh (GitHub CLI) or glab (GitLab CLI) installed and authenticated.
metadata:
  author: greptileai
  version: "1.1"
allowed-tools: Bash(gh:*) Bash(glab:*) Bash(git:*)
---

# Check PR

Analyze a pull request (GitHub) or merge request (GitLab) for review comments, status checks, and description completeness, then help address any issues found.

## Inputs

- **PR/MR number** (optional): If not provided, detect the PR/MR for the current branch.

## Instructions

### 0. Detect platform

Inspect the git remote URL to determine whether this is a GitHub or GitLab repository:

```bash
REMOTE_URL=$(git remote get-url origin)
if echo "$REMOTE_URL" | grep -qi "gitlab"; then
  VCS="gitlab"
else
  VCS="github"
fi
```

For self-hosted GitLab instances whose hostname doesn't contain "gitlab", the user can override by passing `--vcs gitlab` as an input.

### 1. Identify the PR/MR

If a number was provided, use it. Otherwise, detect it:

**GitHub:**
```bash
gh pr view --json number -q .number
```

**GitLab:**
```bash
glab mr view --output json | jq '.iid'
```

Key field differences between platforms:
- GitHub: `number`, `headRefName`, `headRefOid`
- GitLab: `iid`, `source_branch`, `sha`

### 2. Fetch PR/MR details

**GitHub:**
```bash
gh pr view <PR_NUMBER> --json title,body,state,reviews,comments,headRefName,statusCheckRollup
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments
```

**GitLab:**
```bash
glab mr view <MR_IID> --output json
# Fetch discussions (inline diff comments are type "DiffNote"; general comments have null type)
glab api "projects/:fullpath/merge_requests/<MR_IID>/discussions"
```

For GitLab, paginate discussions if needed (add `?per_page=100&page=N`).

### 3. Wait for pending checks

Before analyzing, ensure all status checks have completed. If any checks are `PENDING` or `IN_PROGRESS` (GitHub) / `running` or `pending` (GitLab), poll every 30 seconds until all checks reach a terminal state.

**GitHub:** poll `statusCheckRollup` from `gh pr view`.

**GitLab:**
```bash
glab api "projects/:fullpath/merge_requests/<MR_IID>/pipelines"
```
Pipeline statuses: `running`, `pending`, `success`, `failed`, `canceled`, `skipped`. Poll until no pipeline has `running` or `pending` status.

### 4. Analyze the PR/MR

Once all checks are complete, evaluate these areas:

#### A. Status Checks

- Are all CI checks passing?
- If any are failing, identify which ones and the failure reason.

#### B. PR/MR Description

- Is the description complete and follows team conventions?
- Are all required sections filled in?
- Are there TODOs or placeholders that need updating?

#### C. Review Comments

- Inline code review comments that need addressing
- Look for bot review comments (e.g. from `greptile-apps[bot]` on GitHub, or the Greptile bot user on GitLab, linters, etc.)
- Human reviewer comments

#### D. General Comments

- Discussion comments on the PR/MR
- Bot comments (deploy previews, etc.) — usually informational

### 5. Categorize issues

For each issue found, categorize as:

| Category | Meaning |
|---|---|
| **Actionable** | Code changes, test improvements, or fixes needed |
| **Informational** | Verification notes, questions, or FYIs that don't require changes |
| **Already addressed** | Issues that appear to be resolved by subsequent commits |

### 6. Report findings

Present a summary table:

| Area | Issue | Status | Action Needed |
|------|-------|--------|---------------|
| Status Checks | CI build failing | Failing | Fix type error in `src/api.ts` |
| Review | "Add null check" — @reviewer | Actionable | Add guard clause |
| Description | TODO placeholder in test plan | Actionable | Fill in test plan |
| Review | "Looks good" — @teammate | Informational | None |

### 7. Fix issues (if requested)

If there are actionable items:

1. Switch to the PR/MR's branch if not already on it.
2. Ask the user if they want to fix the issues.
3. If yes, make the fixes, commit, and push.

### 8. Resolve review threads

After addressing comments, resolve the corresponding review threads.

**GitHub** — fetch unresolved thread IDs (paginate if needed — see [the GraphQL reference](references/graphql-queries.md)):

```bash
gh api graphql -f query='
query($cursor: String) {
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUMBER) {
      reviewThreads(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          comments(first: 1) {
            nodes { body path }
          }
        }
      }
    }
  }
}'
```

If `hasNextPage` is true, repeat with `-f cursor=ENDCURSOR` to get remaining threads.

Then resolve threads that have been addressed or are informational:

```bash
gh api graphql -f query='
mutation {
  resolveReviewThread(input: {threadId: "THREAD_ID"}) {
    thread { isResolved }
  }
}'
```

Batch multiple resolutions into a single mutation using aliases (`t1`, `t2`, etc.).

**GitLab** — fetch unresolved discussions (see [the GitLab API reference](references/gitlab-api.md)):

```bash
glab api "projects/:fullpath/merge_requests/<MR_IID>/discussions?per_page=100"
```

Filter for discussions where `"resolved": false`. Collect each discussion's `id`.

Resolve each discussion individually (GitLab has no batch resolution):

```bash
glab api --method PUT \
  "projects/:fullpath/merge_requests/<MR_IID>/discussions/<DISCUSSION_ID>" \
  --field resolved=true
```

Repeat for each unresolved discussion ID.

### 9. Multiple PRs/MRs

If checking a chain of PRs/MRs, process them sequentially.

## Output format

Summarize:
- PR/MR title and current state
- Platform detected (GitHub / GitLab)
- Status checks summary (passing/failing/pending)
- Total issues found
- Actionable items with descriptions
- Items that can be ignored with reasons
- Recommended next steps
