# RabbitLoop

RabbitLoop is a GitHub-first set of [Agent Skills](https://agentskills.io) for CodeRabbit review workflows. It can review local changes with the CodeRabbit CLI, inspect an existing pull request without changing it, or run a bounded fix/re-review loop that stops when the pull request is ready for human merge or needs a human decision.

## Scope

RabbitLoop supports GitHub pull requests through `gh` and local checkout reviews through `cr` (the `coderabbit` alias). It does not support GitLab, Perforce, merging, force-pushing, bypassing branch protection, dismissing checks, or resolving human review threads.

## Requirements

- `git`
- [GitHub CLI](https://cli.github.com/) (`gh`), authenticated for the repository
- [CodeRabbit CLI](https://docs.coderabbit.ai/cli) (`cr`), authenticated with an account that can run reviews
- An existing GitHub pull request for `/check-pr` and `/rabbitloop`

```bash
gh auth login
cr auth login
gh auth status
cr auth status
```

Use `cr doctor` when installation, authentication, repository detection, or backend connectivity needs diagnosis.

### Headless authentication

CI and other non-interactive environments require a CodeRabbit Agentic API key and an assigned seat. Store the key in the environment's secret manager, expose it as `CODERABBIT_API_KEY`, and never print it.

```bash
cr auth login --api-key "$CODERABBIT_API_KEY"
cr auth status --agent
cr review --api-key "$CODERABBIT_API_KEY" --agent
```

Regular user API keys are not accepted for headless CLI authentication. Do not commit the key or place a real value in shell history, logs, examples, or agent prompts.

## Installation

### Claude Code

Clone the repository, then copy each skill file into its named Claude Code directory. This layout needs no symlinks.

```bash
git clone https://github.com/Hassan220022/coderabbit-loop.git ~/.local/share/rabbitloop
mkdir -p ~/.claude/skills/check-pr ~/.claude/skills/cli-review ~/.claude/skills/rabbitloop
cp -f ~/.local/share/rabbitloop/check-pr/SKILL.md ~/.claude/skills/check-pr/SKILL.md
cp -f ~/.local/share/rabbitloop/cli-review/SKILL.md ~/.claude/skills/cli-review/SKILL.md
cp -f ~/.local/share/rabbitloop/rabbitloop/SKILL.md ~/.claude/skills/rabbitloop/SKILL.md
```

Update without changing the discovery depth:

```bash
git -C ~/.local/share/rabbitloop pull --ff-only
cp -f ~/.local/share/rabbitloop/check-pr/SKILL.md ~/.claude/skills/check-pr/SKILL.md
cp -f ~/.local/share/rabbitloop/cli-review/SKILL.md ~/.claude/skills/cli-review/SKILL.md
cp -f ~/.local/share/rabbitloop/rabbitloop/SKILL.md ~/.claude/skills/rabbitloop/SKILL.md
```

### Other Agent Skills-compatible agents

Copy `check-pr/`, `cli-review/`, and `rabbitloop/` into the agent's configured skills directory so each `SKILL.md` is at `<skills-dir>/<skill-name>/SKILL.md`. Agents that recursively discover skills may use this repository root directly.

## Quick start

Start read-only, then authorize mutations only when you want them:

```text
/cli-review
/check-pr <PR-number-or-URL>
/rabbitloop <PR-number-or-URL> --dry-run
/rabbitloop <PR-number-or-URL> --push --pr-actions
```

Replace `<PR-number-or-URL>` with a GitHub PR number such as `42`, or its full URL.

The final command authorizes normal pushes plus CodeRabbit resolve/approve requests after every readiness gate passes. It still cannot force-push or merge.

## Skills

| Skill | Invocation | Purpose |
|---|---|---|
| `cli-review` | `/cli-review` | Review current tracked local changes with `cr review --agent` and report JSONL findings. |
| `check-pr` | `/check-pr <PR-number-or-URL>` | Read an existing GitHub PR, checks, review threads, and description; make no changes. |
| `rabbitloop` | `/rabbitloop <PR-number-or-URL>` | Fix eligible CodeRabbit findings through a bounded, authorization-aware PR loop. |

`/check-pr` and `/rabbitloop` accept a PR number or URL. If omitted, they use the PR associated with the current branch. They never create a PR.

`/cli-review` reviews tracked changes by default. Stage a newly created file or explicitly include untracked files when it should be reviewed.

## Configuration

```bash
export RABBITLOOP_BOT_HANDLE="coderabbitai"
export RABBITLOOP_MAX_POLL_SECONDS="900"
```

`RABBITLOOP_BOT_HANDLE` is the CodeRabbit GitHub service-account login, without `@`; the default is `coderabbitai`. Set it when an installation uses another account. `RABBITLOOP_MAX_POLL_SECONDS` bounds each wait for hosted review activity; the default is 900 seconds.

RabbitLoop uses only CodeRabbit's documented top-level PR commands:

```text
@coderabbitai review
@coderabbitai full review
@coderabbitai resolve
@coderabbitai approve
```

See the official [review command reference](https://docs.coderabbit.ai/reference/review-commands) and [CLI reference](https://docs.coderabbit.ai/cli/reference). A configured service-account handle replaces `coderabbitai` in these commands.

Common loop options:

```text
/rabbitloop <PR-number-or-URL> --dry-run
/rabbitloop <PR-number-or-URL> --max-iterations 3 --fix-severity critical,major
/rabbitloop <PR-number-or-URL> --allow-minor --push
/rabbitloop <PR-number-or-URL> --full-review-first --no-resolve --no-approve
```

`--dry-run` performs discovery and reporting only: no review command, file edit, commit, push, reply, resolution, approval request, or PR-description update.

The complete, versioned local CLI and hosted PR command inventory is in the [CodeRabbit command reference](docs/coderabbit-command-reference.md).

## Safety

- Default fixes are limited to validated `critical` and `major` CodeRabbit findings.
- Local CLI review and hosted PR review are reported as separate workflows.
- Push requires `--push` or interactive confirmation; resolve/approve actions require `--pr-actions`.
- Human comments, PR descriptions, branch protection, existing commits, and merges are never changed automatically.
- CodeRabbit exposes no hosted completion API. RabbitLoop uses bounded polling and requires a current-head formal review or, for an observed clean-review path, the correlated finished reply, successful current-head CodeRabbit commit status, and updated no-findings summary; any signal alone is insufficient.
- Approval is reported only when GitHub shows an actual CodeRabbit approval; `@coderabbitai approve` is only an attempt and depends on repository configuration.

## Stopping conditions

RabbitLoop stops when the PR has no unresolved actionable eligible findings, required checks pass, and its description is complete; or when it reaches the iteration/time limit, a human decision or authorization is needed, validation cannot be repaired safely, review state cannot be verified, or the user cancels. It never merges the PR.

## Troubleshooting

| Problem | Action |
|---|---|
| `gh` missing | Install [GitHub CLI](https://cli.github.com/) and run `gh auth login`. |
| `cr` missing | Install the [CodeRabbit CLI](https://docs.coderabbit.ai/cli) and run `cr auth login`. |
| Authentication fails | Run `gh auth status`, `cr auth status`, then `cr doctor`; do not paste tokens into chat. |
| No PR found | Push the branch and create a PR explicitly, then pass its number or URL. RabbitLoop will not create one. |
| Review times out | Check the PR and CodeRabbit configuration, then retry explicitly; no completion is inferred from acknowledgment, partial evidence, or silence. |
| Review is skipped or rate-limited | Wait for the reported allowance window, then trigger one documented review command after confirming no review is already running. Neither state counts as completion. |
| Automatic reviews are paused | Use `@coderabbitai review` for one review, or `@coderabbitai resume` to resume automatic reviews. A paused status is not completion. |
| Checks fail or remain pending | Open the links from `gh pr checks`; fix failures or wait for pending checks before resolving or approving. |
| Approval is not confirmed | Enable CodeRabbit `reviews.request_changes_workflow` if approval is desired; a successful command reply alone is not approval. |

## Validation

Repository tests require Ruby 3.2+ and [Pandoc](https://pandoc.org/) for GFM-aware link, heading-fragment, and fenced-code parsing.

Run the repository contract test on every change:

```bash
ruby tests/test_repository.rb
```

Run the authenticated live CLI matrix when `cr` is installed and network access is available:

```bash
ruby tests/test_cli_live.rb
```

The live test verifies the installed command tree, authentication JSON, `cr doctor`, valid/invalid configuration handling, and the exact clean-review JSONL event sequence without submitting code for review.

## Migration and license

The old `/greploop` command is replaced by `/rabbitloop`; no compatibility alias remains.

The fork now lives at `Hassan220022/coderabbit-loop`; RabbitLoop remains the product and skill name.

Released under the [MIT License](LICENSE). The original copyright notice is preserved in the license as required attribution.
