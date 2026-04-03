---
name: greploop
description: >
  Iteratively improves a PR (GitHub) or MR (GitLab) until Greptile gives it a 5/5 confidence
  score with zero unresolved comments. Triggers Greptile review, fixes all actionable comments,
  pushes, re-triggers review, and repeats. Use when the user wants to fully optimize a PR/MR
  against Greptile's code review standards.
license: MIT
compatibility: Requires git, gh (GitHub CLI) or glab (GitLab CLI) authenticated, and Greptile installed on the repo.
metadata:
  author: greptileai
  version: "1.1"
allowed-tools: Bash(gh:*) Bash(glab:*) Bash(git:*)
---

# Greploop

Iteratively fix a PR/MR until Greptile gives a perfect review: 5/5 confidence, zero unresolved comments.

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

**GitHub:**
```bash
gh pr view --json number,headRefName -q '{number: .number, branch: .headRefName}'
```

**GitLab:**
```bash
glab mr view --output json | jq '{iid: .iid, branch: .source_branch}'
```

Switch to the PR/MR branch if not already on it.

Key field differences:
- GitHub: `number`, `headRefName`, `headRefOid`
- GitLab: `iid`, `source_branch`, `sha`

### 2. Loop

Repeat the following cycle. **Max 5 iterations** to avoid runaway loops.

#### A. Trigger Greptile review

Push the latest changes (if any):

```bash
git push
```

Wait for checks to start after push:

```bash
sleep 5
```

**GitHub** — check if Greptile is already running before posting a new trigger comment:

```bash
GREPTILE_STATE=$(gh pr checks <PR_NUMBER> --json name,state | jq -r '.[] | select(.name | test("greptile"; "i")) | .state')
```

If Greptile is **not** already running (`PENDING` or `IN_PROGRESS`), request a fresh review:

```bash
if [ "$GREPTILE_STATE" != "PENDING" ] && [ "$GREPTILE_STATE" != "IN_PROGRESS" ]; then
  gh pr comment <PR_NUMBER> --body "@greptile review"
fi
```

Then poll for the Greptile check run to complete:

```bash
HEAD_SHA=$(gh pr view <PR_NUMBER> --json headRefOid -q .headRefOid)

while true; do
  GREPTILE_CHECK=$(gh api "repos/{owner}/{repo}/commits/$HEAD_SHA/check-runs" \
    --jq '.check_runs[] | select(.name | test("greptile"; "i"))' 2>/dev/null)
  
  if [ -z "$GREPTILE_CHECK" ]; then
    echo "Waiting for Greptile check to appear..."
    sleep 5
    continue
  fi
  
  STATUS=$(echo "$GREPTILE_CHECK" | jq -r '.status // "completed"')
  CONCLUSION=$(echo "$GREPTILE_CHECK" | jq -r '.conclusion // "pending"')
  
  if [ "$STATUS" = "completed" ]; then
    if [ "$CONCLUSION" = "success" ]; then
      echo "Greptile check passed!"
    else
      echo "Greptile check completed with: $CONCLUSION"
    fi
    break
  fi
  
  echo "Waiting for Greptile... (status: $STATUS)"
  sleep 10
done
```

**GitLab** — check if Greptile is already running before posting a trigger comment:

```bash
PIPELINES=$(glab api "projects/:fullpath/merge_requests/<MR_IID>/pipelines")
GREPTILE_RUNNING=$(echo "$PIPELINES" | jq '[.[] | select(.status == "running" or .status == "pending")] | length')
```

If no pipeline is running, post a trigger comment:

```bash
if [ "$GREPTILE_RUNNING" = "0" ]; then
  glab mr note <MR_IID> --message "@greptile review"
fi
```

Then poll for the Greptile pipeline job to complete (see [GitLab API reference](references/gitlab-api.md)):

```bash
HEAD_SHA=$(glab mr view <MR_IID> --output json | jq -r '.sha')

while true; do
  PIPELINES=$(glab api "projects/:fullpath/merge_requests/<MR_IID>/pipelines")
  # Find the most recent pipeline for this SHA
  PIPELINE_ID=$(echo "$PIPELINES" | jq -r --arg sha "$HEAD_SHA" \
    '[.[] | select(.sha == $sha)] | sort_by(.id) | last | .id // empty')

  if [ -z "$PIPELINE_ID" ]; then
    echo "Waiting for Greptile pipeline to appear..."
    sleep 5
    continue
  fi

  JOBS=$(glab api "projects/:fullpath/pipelines/$PIPELINE_ID/jobs")
  GREPTILE_JOB=$(echo "$JOBS" | jq '.[] | select(.name | test("greptile"; "i"))')

  if [ -z "$GREPTILE_JOB" ]; then
    echo "Waiting for Greptile job to appear..."
    sleep 5
    continue
  fi

  JOB_STATUS=$(echo "$GREPTILE_JOB" | jq -r '.status')

  if [ "$JOB_STATUS" = "success" ] || [ "$JOB_STATUS" = "failed" ] || [ "$JOB_STATUS" = "canceled" ]; then
    echo "Greptile job completed with: $JOB_STATUS"
    break
  fi

  echo "Waiting for Greptile... (status: $JOB_STATUS)"
  sleep 10
done
```

#### B. Fetch Greptile review results

Greptile may surface its score in two places — check **both**:

**GitHub:**

**1. PR description (body):**
```bash
gh pr view <PR_NUMBER> --json body -q '.body'
```

**2. PR reviews:**
```bash
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/reviews
```

Look for the most recent entry from `greptile-apps[bot]` or `greptile-apps-staging[bot]`.

**GitLab:**

**1. MR description (body):**
```bash
glab mr view <MR_IID> --output json | jq -r '.description'
```

**2. MR notes (comments):**
```bash
glab api "projects/:fullpath/merge_requests/<MR_IID>/notes"
```

Filter for notes from the Greptile bot user (check the `author.username` field — the exact username may vary per installation; verify on first run).

For both platforms, parse the text for:
- **Confidence score**: a pattern like `3/5` or `5/5` (or `Confidence: 3/5`).
- **Comment count**: Number of inline review comments noted in the summary.

Use whichever source has the **most recent** score.

Also fetch all unresolved inline comments:

**GitHub:**
```bash
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments
```

**GitLab:**
```bash
glab api "projects/:fullpath/merge_requests/<MR_IID>/discussions"
```

Filter to `DiffNote` type discussions (`notes[0].type == "DiffNote"`) from Greptile that are on the latest commit and not yet resolved (`"resolved": false`).

#### C. Check exit conditions

Stop the loop if **any** of these are true:

- Confidence score is **5/5** AND there are **zero unresolved comments**
- Max iterations reached (report current state)

#### D. Fix actionable comments

For each unresolved Greptile comment:

1. Read the file and understand the comment in context.
2. Determine if it's actionable (code change needed) or informational.
3. If actionable, make the fix.
4. If informational or a false positive, note it but still resolve the thread.

#### E. Resolve threads

**GitHub** — fetch unresolved review threads and resolve all that have been addressed (see [GraphQL reference](references/graphql-queries.md)):

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
            nodes { body path author { login } }
          }
        }
      }
    }
  }
}'
```

Resolve addressed threads:

```bash
gh api graphql -f query='
mutation {
  t1: resolveReviewThread(input: {threadId: "ID1"}) { thread { isResolved } }
  t2: resolveReviewThread(input: {threadId: "ID2"}) { thread { isResolved } }
}'
```

**GitLab** — fetch unresolved discussions and resolve each one (see [GitLab API reference](references/gitlab-api.md)):

```bash
glab api "projects/:fullpath/merge_requests/<MR_IID>/discussions?per_page=100"
```

Filter for `"resolved": false` discussions. Then resolve each by its `id`:

```bash
glab api --method PUT \
  "projects/:fullpath/merge_requests/<MR_IID>/discussions/<DISCUSSION_ID>" \
  --field resolved=true
```

Repeat for each unresolved discussion ID. (GitLab has no batch resolution — loop through each one.)

#### F. Commit and push

```bash
git add -A
git commit -m "address greptile review feedback (greploop iteration N)"
git push
```

Wait for checks to start after push:

```bash
sleep 5
```

Then go back to step **A**.

### 3. Report

After exiting the loop, summarize:

| Field              | Value      |
| ------------------ | ---------- |
| Platform           | GitHub / GitLab |
| Iterations         | N          |
| Final confidence   | X/5        |
| Comments resolved  | N          |
| Remaining comments | N (if any) |

If the loop exited due to max iterations, list any remaining unresolved comments and suggest next steps.

## Output format

```
Greploop complete.
  Platform:      GitHub
  Iterations:    2
  Confidence:    5/5
  Resolved:      7 comments
  Remaining:     0
```

If not fully resolved:

```
Greploop stopped after 5 iterations.
  Platform:      GitLab
  Confidence:    4/5
  Resolved:      12 comments
  Remaining:     2

Remaining issues:
  - src/auth.ts:45 — "Consider rate limiting this endpoint"
  - src/db.ts:112 — "Missing index on user_id column"
```
