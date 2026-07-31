---
name: cli-review
description: Review tracked changes in the current Git checkout with CodeRabbit CLI JSONL output and report actionable findings without claiming that a GitHub PR was reviewed.
license: MIT
compatibility: Requires git and CodeRabbit CLI (cr) installed and authenticated.
metadata:
  author: RabbitLoop maintainers
  version: "2.0"
allowed-tools: Bash(command:*) Bash(git:*) Bash(cr:*)
---

# CLI Review

Run a local CodeRabbit review for the current checkout and turn its JSONL stream into a concise report. This skill does not inspect, trigger, or change a GitHub pull request.

## Prerequisites

Check each prerequisite before reviewing:

```bash
command -v git
command -v cr
git rev-parse --show-toplevel
cr auth status
```

If `git` or `cr` is missing, stop and link to the relevant installation guidance. If Git context is missing, stop and say the review must run in a Git working tree. If authentication fails, recommend `cr auth login`; use `cr doctor` when diagnosis is needed. Never print credentials, key values, cookies, or full environment variables.

## Inputs and options

- No option: review current tracked changes with `cr review --agent`.
- `--include-untracked`: add `cr review --include-untracked --agent` only after showing the untracked file list and checking that it contains no likely secrets or generated/vendor trees.
- Any supported `cr review` scope option explicitly supplied by the user, such as `--committed`, `--uncommitted`, `--base`, `--base-commit`, or `--dir`: pass it through unchanged.
- `--auto-narrow <strategy>`: opt into retrying one oversized-scope candidate. The strategy must name an unambiguous candidate, for example `committed`, `uncommitted`, or an exact directory. Without this option, never select a candidate automatically.

Default review scope is current tracked changes. Untracked files are excluded; newly created files normally need staging or explicit `--include-untracked` to be reviewed.

## Workflow

1. Run the prerequisite checks and change to the repository root returned by `git rev-parse --show-toplevel`.
2. Inspect `git status --short` and state the selected scope. Do not stage files merely to make them reviewable.
3. Run exactly one machine-readable review, keeping stdout and stderr distinct:

   ```bash
   cr review --agent
   ```

   Add only user-selected, documented scope flags.
4. Parse stdout one line at a time. Each non-empty line must be one JSON object. Do not wrap the stream in brackets, split on braces, evaluate it as code, or trust fields without checking their type.
5. Dispatch by the top-level `type` field:

   | Type | Handling |
   |---|---|
   | `finding` | Validate `severity` and `fileName`; prefer non-empty `codegenInstructions`, otherwise use `comment`; retain `suggestions` only as supporting detail. |
   | `review_context` | Record the reported scope/context without treating it as a finding or completion signal. |
   | `status` | Record known status text; unknown fields or values are informational, not errors. |
   | `heartbeat` | Reset the local inactivity timer and otherwise ignore it. |
   | `complete` | Mark the stream terminal and report its fields defensively. The documented no-change result is `status: review_skipped`, `findings: 0`, `message: No changes detected`. |
   | `error` | Stop the current attempt and report the safe error message. Handle oversized scope as described below. |

   Ignore unknown event types after recording their names; the format is extensible. A malformed JSON line makes the result incomplete: preserve already parsed findings, report the line number, and do not claim completion.
6. Accept only these documented finding severities, ordered highest first: `critical`, `major`, `minor`, `trivial`, `info`. Preserve an unknown severity as `unknown`; never map it to a documented value or invent a score.
7. For an oversized-scope `error`, inspect optional `candidates` and `candidatesNote` only as opaque, user-facing alternatives because their nested schema is not documented. Do not claim the full diff was reviewed. Present every candidate and either stop for direction or retry the exact candidate selected by `--auto-narrow`.
8. Use `cr review findings` only to replay the previous local review when the user explicitly asks; its output has no documented agent/JSON schema, so do not feed it into this JSONL parser.

## Safety rules

- Review only; do not edit, stage, commit, push, or open/update a PR.
- Never add `--include-untracked` silently.
- Never expose authentication material or dump full environment state.
- Never describe local CLI results as CodeRabbit PR review results.
- Never infer completion after an `error`, malformed line, process interruption, or missing terminal event.

## Stopping and failure behavior

Stop after a terminal `complete`, terminal `error`, authentication/repository failure, malformed stream, or user decision required for scope narrowing. If the command exits unexpectedly, report the exit state and sanitized stderr, recommend `cr doctor` for environment/connectivity failures, and label the review incomplete.

## Final report

```text
CodeRabbit local review
Scope: tracked changes
Result: completed | skipped | incomplete | failed
Findings: 2 (critical 0, major 1, minor 1, trivial 0, info 0, unknown 0)

1. major — src/example.ts
   Fix: <codegenInstructions, or comment when absent>

Review completed: yes
GitHub PR reviewed: no
Next action: <smallest actionable next step>
```
