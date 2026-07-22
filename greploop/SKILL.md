---
name: greploop
description: >
  Iteratively improves a PR (GitHub), MR (GitLab), or shelved changelist (Perforce) until Greptile
  gives it a 5/5 confidence score with zero unresolved comments. Triggers Greptile review, fixes all
  actionable comments, and either repeats after pushing/re-shelving or stops after one fix-only pass
  without staging, committing, or pushing. Use when the user wants to improve a PR/MR/CL against
  Greptile's code review standards.
license: MIT
compatibility: Requires git, gh (GitHub CLI) or glab (GitLab CLI) authenticated, and Greptile installed on the repo. For Perforce, requires p4 CLI authenticated.
metadata:
  author: greptileai
  version: "1.4"
allowed-tools: Bash(gh:*) Bash(glab:*) Bash(git:*) Bash(p4:*)
---

# Greploop

Iteratively fix a PR/MR/CL until Greptile gives a perfect review: 5/5 confidence, zero unresolved comments.

## Inputs

- **PR/MR/CL number** (optional): If not provided, detect the PR/MR for the current branch, or the default pending changelist for p4.
- **Mode** (optional): Pass `--no-commit` (or its alias `--fix-only`) to apply one round of fixes and leave changes made by that pass unstaged and uncommitted. In this mode, do not push, re-shelve, or resolve remote review threads. Without either flag, use the full autonomous loop.

Treat `--no-commit` and `--fix-only` as equivalent and set `FIX_ONLY=true` when either is present. This safety guarantee applies to every supported platform. Before editing, record the existing workspace state with `git status --short` or the equivalent Perforce checks. Preserve the existing index, and track every path greploop edits plus whether that path was already dirty.

## Instructions

### 0. Detect platform

First check for Perforce, then fall back to git remote detection:

```bash
# Check for Perforce environment
if p4 info >/dev/null 2>&1; then
  VCS="perforce"
else
  REMOTE_URL=$(git remote get-url origin)
  if echo "$REMOTE_URL" | grep -qi "gitlab"; then
    VCS="gitlab"
  else
    VCS="github"
  fi
fi
```

For self-hosted GitLab instances whose hostname doesn't contain "gitlab", the user can override by passing `--vcs gitlab` as an input. For Perforce, pass `--vcs perforce`.

### 1. Identify the PR/MR/CL

**GitHub:**
```bash
gh pr view --json number,headRefName -q '{number: .number, branch: .headRefName}'
```

**GitLab:**
```bash
glab mr view --output json | jq '{iid: .iid, branch: .source_branch}'
```

Switch to the PR/MR branch if not already on it. In fix-only mode, stop if switching would alter pre-existing changes, and before editing require `git rev-parse HEAD` to equal the remote `HEAD_SHA` fetched in step A.

**Perforce:**
```bash
# List pending changelists for current user/client
p4 changes -s pending -u $P4USER -c $P4CLIENT

# Describe a specific CL
p4 describe -s <CL_NUMBER>
```

Ensure the correct workspace (`p4 client`) is set before proceeding.

Key field differences:
- GitHub: `number`, `headRefName`, `headRefOid`
- GitLab: `iid`, `source_branch`, `sha`
- Perforce: changelist number, `P4CLIENT`, shelved files

### 2. Loop

In the default mode, repeat the following cycle with a **maximum of 5 iterations** to avoid runaway loops. In fix-only mode, perform exactly one pass through steps A-D, then follow the fix-only handoff in step E.

#### A. Trigger Greptile review

For Perforce, before any optional re-shelve, capture the current shelf with `p4 describe -S <CL_NUMBER>` and record the external review ID, latest review version, linked change/shelf identifier, update time, and latest comment ID/time. Treat these as the baseline review identity.

In the default mode, push/shelve the latest changes (if any):

**GitHub/GitLab:**
```bash
git push
```

**Perforce:**
```bash
# Re-shelve to update the shelved files for review
p4 shelve -f -c <CL_NUMBER>
```

Wait for checks to start after push/shelve:

```bash
sleep 5
```

In fix-only mode, skip every push and re-shelve command above. Trigger and inspect the review for the current remote PR/MR head or existing shelved changelist; do not publish local changes, including changes that were already present when greploop started.

**GitHub** — snapshot the latest Greptile check before posting a new trigger comment:

```bash
HEAD_SHA=$(gh pr view <PR_NUMBER> --json headRefOid -q .headRefOid)
LOCAL_HEAD=$(git rev-parse HEAD)
if [ "$LOCAL_HEAD" != "$HEAD_SHA" ]; then
  echo "Local HEAD does not match the reviewed PR head; stop before polling." >&2
  exit 1
fi
CHECK_RUNS=$(gh api "repos/{owner}/{repo}/commits/$HEAD_SHA/check-runs")
PREVIOUS_CHECK_ID=$(echo "$CHECK_RUNS" | jq -r \
  '[.check_runs[] | select(.name | test("greptile"; "i"))] | sort_by(.id) | last | .id // empty')
RUNNING_CHECK_ID=$(echo "$CHECK_RUNS" | jq -r \
  '[.check_runs[] | select(.name | test("greptile"; "i")) | select(.status == "queued" or .status == "in_progress")] | sort_by(.id) | last | .id // empty')
TRIGGERED_REVIEW=false
if [ -z "$RUNNING_CHECK_ID" ]; then
  gh pr comment <PR_NUMBER> --body "@greptile review"
  TRIGGERED_REVIEW=true
fi
TARGET_CHECK_ID="$RUNNING_CHECK_ID"
```

Poll for the running check, or for a check newer than `PREVIOUS_CHECK_ID` when a review was triggered:

```bash
ATTEMPTS=0
MAX_ATTEMPTS=60
POLL_INTERVAL_SECONDS=10
while true; do
  ATTEMPTS=$((ATTEMPTS + 1))
  if [ "$ATTEMPTS" -gt "$MAX_ATTEMPTS" ]; then
    echo "Timed out waiting for the Greptile check run after approximately 10 minutes." >&2
    exit 1
  fi
  CHECK_RUNS=$(gh api "repos/{owner}/{repo}/commits/$HEAD_SHA/check-runs" 2>/dev/null)
  if [ "$TRIGGERED_REVIEW" = "true" ] && [ -z "$TARGET_CHECK_ID" ]; then
    TARGET_CHECK_ID=$(echo "$CHECK_RUNS" | jq -r --argjson previous "${PREVIOUS_CHECK_ID:-0}" \
      '[.check_runs[] | select(.name | test("greptile"; "i")) | select(.id > $previous)] | sort_by(.id) | first | .id // empty')
  fi
  GREPTILE_CHECK=$(echo "$CHECK_RUNS" | jq --arg id "$TARGET_CHECK_ID" \
    '[.check_runs[] | select((.id | tostring) == $id)] | last // empty')
  if [ -z "$GREPTILE_CHECK" ]; then
    echo "Waiting for Greptile check to appear..."
    sleep "$POLL_INTERVAL_SECONDS"
    continue
  fi
  CURRENT_CHECK_ID=$(echo "$GREPTILE_CHECK" | jq -r '.id')
  STATUS=$(echo "$GREPTILE_CHECK" | jq -r '.status // "completed"')
  CONCLUSION=$(echo "$GREPTILE_CHECK" | jq -r '.conclusion // "pending"')
  if [ "$STATUS" = "completed" ]; then
    ACTIVE_REVIEW_ID="$CURRENT_CHECK_ID"
    ACTIVE_REVIEW_STARTED_AT=$(echo "$GREPTILE_CHECK" | jq -r '.started_at // .created_at // empty')
    if [ "$CONCLUSION" = "success" ]; then
      echo "Greptile check passed!"
    else
      echo "Greptile check completed with: $CONCLUSION"
    fi
    break
  fi
  echo "Waiting for Greptile... (status: $STATUS)"
  sleep "$POLL_INTERVAL_SECONDS"
done
```

If polling times out, stop the greploop workflow and report the timeout. Do not continue with stale or missing review results.

**GitLab** — snapshot the latest pipeline for the MR head before posting a trigger comment:

```bash
HEAD_SHA=$(glab mr view <MR_IID> --output json | jq -r '.sha')
LOCAL_HEAD=$(git rev-parse HEAD)
if [ "$LOCAL_HEAD" != "$HEAD_SHA" ]; then
  echo "Local HEAD does not match the reviewed MR head; stop before polling." >&2
  exit 1
fi
PIPELINES=$(glab api "projects/:fullpath/merge_requests/<MR_IID>/pipelines")
PREVIOUS_PIPELINE_ID=$(echo "$PIPELINES" | jq -r --arg sha "$HEAD_SHA" \
  '[.[] | select(.sha == $sha)] | sort_by(.id) | last | .id // empty')
RUNNING_PIPELINE_IDS=$(echo "$PIPELINES" | jq -r --arg sha "$HEAD_SHA" \
  '[.[] | select(.sha == $sha) | select(.status == "running" or .status == "pending")] | sort_by(.id) | reverse | .[].id')
GREPTILE_RUNNING=0
RUNNING_PIPELINE_ID=""
RUNNING_JOB_ID=""
for CANDIDATE_PIPELINE_ID in $RUNNING_PIPELINE_IDS; do
  RUNNING_JOBS=$(glab api "projects/:fullpath/pipelines/$CANDIDATE_PIPELINE_ID/jobs")
  RUNNING_JOB_ID=$(echo "$RUNNING_JOBS" | jq -r \
    '[.[] | select(.name | test("greptile"; "i")) | select(.status == "running" or .status == "pending")] | sort_by(.id) | last | .id // empty')
  if [ -n "$RUNNING_JOB_ID" ]; then
    RUNNING_PIPELINE_ID="$CANDIDATE_PIPELINE_ID"
    GREPTILE_RUNNING=1
    break
  fi
done
TRIGGERED_REVIEW=false
if [ "$GREPTILE_RUNNING" = "0" ]; then
  glab mr note <MR_IID> --message "@greptile review"
  TRIGGERED_REVIEW=true
fi
if [ "$TRIGGERED_REVIEW" = "true" ]; then
  TARGET_PIPELINE_ID=""
  TARGET_JOB_ID=""
else
  TARGET_PIPELINE_ID="$RUNNING_PIPELINE_ID"
  TARGET_JOB_ID="$RUNNING_JOB_ID"
fi
```

**Perforce** — Perforce does not have native check runs. In the default mode, after re-shelving, poll the external review tool until it reports a strictly newer review version tied to the updated shelf; pin that version as `ACTIVE_REVIEW_ID`/`ACTIVE_REVIEW_VERSION`. In fix-only mode, do not re-shelve or trigger the webhook: use the existing review only when its pinned version is tied to the captured shelf, otherwise stop.

Then poll for the Greptile pipeline job to complete (see [GitLab API reference](references/gitlab-api.md)):

```bash
ATTEMPTS=0
MAX_ATTEMPTS=60
POLL_INTERVAL_SECONDS=10
while true; do
  ATTEMPTS=$((ATTEMPTS + 1))
  if [ "$ATTEMPTS" -gt "$MAX_ATTEMPTS" ]; then
    echo "Timed out waiting for the Greptile pipeline job after approximately 10 minutes." >&2
    exit 1
  fi
  PIPELINES=$(glab api "projects/:fullpath/merge_requests/<MR_IID>/pipelines")
  if [ "$TRIGGERED_REVIEW" = "true" ] && [ -z "$TARGET_PIPELINE_ID" ]; then
    CANDIDATE_PIPELINE_IDS=$(echo "$PIPELINES" | jq -r --arg sha "$HEAD_SHA" --argjson previous "${PREVIOUS_PIPELINE_ID:-0}" \
      '[.[] | select(.sha == $sha) | select(.id > $previous)] | sort_by(.id) | .[].id')
    for CANDIDATE_PIPELINE_ID in $CANDIDATE_PIPELINE_IDS; do
      CANDIDATE_JOBS=$(glab api "projects/:fullpath/pipelines/$CANDIDATE_PIPELINE_ID/jobs")
      CANDIDATE_JOB_ID=$(echo "$CANDIDATE_JOBS" | jq -r \
        '[.[] | select(.name | test("greptile"; "i"))] | sort_by(.id) | first | .id // empty')
      if [ -n "$CANDIDATE_JOB_ID" ]; then
        TARGET_PIPELINE_ID="$CANDIDATE_PIPELINE_ID"
        TARGET_JOB_ID="$CANDIDATE_JOB_ID"
        break
      fi
    done
  fi
  PIPELINE_ID="$TARGET_PIPELINE_ID"
  if [ -z "$PIPELINE_ID" ]; then
    echo "Waiting for Greptile pipeline to appear..."
    sleep "$POLL_INTERVAL_SECONDS"
    continue
  fi
  JOBS=$(glab api "projects/:fullpath/pipelines/$PIPELINE_ID/jobs")
  GREPTILE_JOB=$(echo "$JOBS" | jq --arg id "$TARGET_JOB_ID" \
    '[.[] | select((.id | tostring) == $id)] | last // empty')
  if [ -z "$GREPTILE_JOB" ]; then
    echo "Waiting for Greptile job to appear..."
    sleep "$POLL_INTERVAL_SECONDS"
    continue
  fi
  JOB_STATUS=$(echo "$GREPTILE_JOB" | jq -r '.status')
  if [ "$JOB_STATUS" = "success" ] || [ "$JOB_STATUS" = "failed" ] || [ "$JOB_STATUS" = "canceled" ]; then
    ACTIVE_REVIEW_ID="$TARGET_JOB_ID"
    ACTIVE_PIPELINE_ID="$PIPELINE_ID"
    ACTIVE_REVIEW_STARTED_AT=$(echo "$PIPELINES" | jq -r --arg id "$PIPELINE_ID" \
      '.[] | select((.id | tostring) == $id) | .created_at // empty')
    echo "Greptile job completed with: $JOB_STATUS"
    break
  fi
  echo "Waiting for Greptile... (status: $JOB_STATUS)"
  sleep "$POLL_INTERVAL_SECONDS"
done
```

If polling times out, stop the greploop workflow and report the timeout. Do not continue with stale or missing review results.

#### B. Fetch Greptile review results

Greptile may surface its score in several places — check **all** of the relevant sources. For GitHub and GitLab, filter every source to the current head and `ACTIVE_REVIEW_STARTED_AT`. PR/MR descriptions and general comments/notes are supplemental: use them only when they name the active review/head or a filtered, head-bound review/diff comment from the same review window corroborates them. For Perforce, the full loop requires results on the newer pinned version and after the baseline timestamp; fix-only accepts only the captured version/comments proven to match the unchanged shelf. If freshness cannot be established, stop instead of applying stale feedback.

**GitHub:**

**1. PR description (body):**
```bash
gh pr view <PR_NUMBER> --json body,updatedAt | jq -r --arg since "$ACTIVE_REVIEW_STARTED_AT" \
  'select(.updatedAt >= $since) | .body'
```

**2. General PR comments (issue comments):**
```bash
gh api --paginate "repos/{owner}/{repo}/issues/<PR_NUMBER>/comments?per_page=100" | jq \
  --arg since "$ACTIVE_REVIEW_STARTED_AT" '[.[] | select((.user.login // "") | test("greptile"; "i")) | select(.updated_at >= $since)]'
```

Filter for Greptile-authored comments and use the body from the most recently updated comment (`updated_at`), not the most recently created comment. Greptile may edit the same general PR comment on each review cycle; parse the current body, including the "Prompt to fix all with AI" section, before deciding there are no remaining issues.

**3. PR reviews:**
```bash
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/reviews | jq --arg sha "$HEAD_SHA" --arg since "$ACTIVE_REVIEW_STARTED_AT" \
  '[.[] | select((.user.login // "") | test("greptile"; "i")) | select(.commit_id == $sha) | select((.submitted_at // "") >= $since)]'
```

Look for the most recent entry from `greptile-apps[bot]` or `greptile-apps-staging[bot]`.

**GitLab:**

**1. MR description (body):**
```bash
glab mr view <MR_IID> --output json | jq -r --arg since "$ACTIVE_REVIEW_STARTED_AT" \
  'select(.updated_at >= $since) | .description'
```

**2. MR notes (comments):**
```bash
glab api --paginate "projects/:fullpath/merge_requests/<MR_IID>/notes?per_page=100" | jq -s --arg since "$ACTIVE_REVIEW_STARTED_AT" \
  'add | [.[] | select((.author.username // "") | test("greptile"; "i")) | select((.updated_at // .created_at // "") >= $since)]'
```

Filter for notes from the Greptile bot user (check the `author.username` field — the exact username may vary per installation; verify on first run).

**Perforce:**

**1. CL description:**
```bash
p4 describe -s <CL_NUMBER>
```
Check the description field for a Greptile-appended score block.

**2. CL comments / review notes:**
If your installation uses a review tool such as Helix Swarm, fetch comments via its API.

Example (Swarm API):
GET /api/v11/comments?topic=reviews/<REVIEW_ID>

Response fields of interest typically include:
- user (author username)
- body (comment text)
- flags/state indicating whether the comment is resolved

Filter to comments authored by the Greptile bot:
- Prefer exact username match if known
- Otherwise, use a heuristic where the author name contains "greptile" (case-insensitive)

For all platforms, parse the text for:
- **Confidence score**: a pattern like `3/5` or `5/5` (or `Confidence: 3/5`).
- **Comment count**: Number of inline review comments noted in the summary.

From the filtered candidates, use the **most recently updated** score. If no source passes its freshness filters, stop.

Also fetch all unresolved inline comments:

**GitHub:**
```bash
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments | jq --arg sha "$HEAD_SHA" --arg since "$ACTIVE_REVIEW_STARTED_AT" \
  '[.[] | select((.user.login // "") | test("greptile"; "i")) | select(.commit_id == $sha) | select((.updated_at // .created_at // "") >= $since)]'
```

Also carry forward actionable items from a corroborated Greptile general PR comment, especially the "Prompt to fix all with AI" section, even if the inline comment endpoint returns zero unresolved comments.

**GitLab:**
```bash
glab api --paginate "projects/:fullpath/merge_requests/<MR_IID>/discussions?per_page=100" | jq -s --arg sha "$HEAD_SHA" --arg since "$ACTIVE_REVIEW_STARTED_AT" \
  'add | [.[] | select(.notes[0].type == "DiffNote") | select((.notes[0].author.username // "") | test("greptile"; "i")) | select(.notes[0].position.head_sha == $sha) | select((.notes[0].updated_at // .notes[0].created_at // "") >= $since) | select((if has("resolved") then .resolved else .notes[0].resolved end) != true)]'
```

Filter to `DiffNote` type discussions (`notes[0].type == "DiffNote"`) from Greptile that are on the latest commit and not yet resolved. GitLab documents `notes[0].resolved`; the fallback also accepts installations that expose discussion-level `resolved`.

**Perforce:**
If using Swarm:

# Fetch inline diff comments for the review associated with the CL
GET /api/v11/comments?topic=reviews/<REVIEW_ID>

Filter to comments from the Greptile bot user that have not been marked as resolved/addressed.

#### C. Check exit conditions

Stop the loop if **any** of these are true:

- Confidence score is **5/5** AND there are **zero unresolved comments**
- Max iterations reached (report current state)

#### D. Fix actionable comments

For each unresolved Greptile comment:

Immediately before editing, re-fetch the remote head and require it, the reviewed `HEAD_SHA`, and `git rev-parse HEAD` to still match. Stop without editing if the PR/MR advanced during polling.

1. Read the file and understand the comment in context.
2. Determine if it's actionable (code change needed) or informational.
3. If actionable, make the fix.
4. If informational or a false positive, note it. Resolve the thread only in the default mode.

#### E. Stop in fix-only mode

If `FIX_ONLY=true`:

1. Do not resolve or otherwise modify remote review threads. The local fixes are not visible remotely yet.
2. Do not stage, unstage, commit, push, or re-shelve any changes; preserve the existing index state.
3. Report every path greploop edited and mark any overlap with the baseline dirty-path set; do not infer attribution from final `git status` alone.
4. Stop after this first pass and hand the modified workspace back to the user's commit/publish workflow.

Only continue to steps F-G in the default mode.

#### F. Resolve threads

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

#### G. Commit and push / re-shelve

**GitHub/GitLab:**
```bash
git add -A
git commit -m "address greptile review feedback (greploop iteration N)"
git push
```

**Perforce:**
```bash
# Stage changes back into the CL and re-shelve for the next review round
p4 shelve -f -c <CL_NUMBER>
```

Wait for checks to start after push/shelve:

```bash
sleep 5
```

Then go back to step **A**.

### 3. Report

After exiting the loop, summarize:

| Field              | Value      |
| ------------------ | ---------- |
| Platform           | GitHub / GitLab / Perforce |
| Iterations         | N          |
| Final confidence   | X/5        |
| Comments resolved  | N          |
| Remaining comments | N (if any) |

If the loop exited due to max iterations, list any remaining unresolved comments and suggest next steps.

## Output format

Report the fields above in a compact status block. For fix-only mode, label the score as pre-fix, report addressed comments and every edited path, state that remote threads and the index are unchanged, and hand off selective staging and publishing to the user. If the full loop stops before completion, list every remaining issue with its path and line. Include the changelist number for Perforce.
