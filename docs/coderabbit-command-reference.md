# CodeRabbit command reference

Verified on 2026-07-31 against CodeRabbit CLI `0.7.1`, the installed command help, and the official [CLI reference](https://docs.coderabbit.ai/cli/reference). `cr` and `coderabbit` are identical aliases.

The review flags and JSONL event names below are documented current behavior. The version pin records the exact surface exercised by [`tests/test_cli_live.rb`](../tests/test_cli_live.rb) and the sanitized observed [`0.7.1` JSONL fixture](../tests/fixtures/cr-0.7.1-review.jsonl); it is not a claim that those behaviors differ from the official reference.

## Local CLI commands

| Command | Options | Behavior |
|---|---|---|
| `cr` / `cr review` | `--agent`, `--light`, `--show-prompts`, `--committed`, `--uncommitted`, `--include-untracked`, `--config <files...>`, `--base <branch>`, `--base-commit <commit>`, `--dir <path>`, `--api-key <key>` | Review local Git changes. Tracked changes are the default scope. |
| `cr review findings` | `--dir <path>` | Replay stored findings for the current review context without a new review. Output has no documented JSON mode. |
| `cr auth login` | `--agent`, `--self-hosted`, `--api-key <key>` | Authenticate through browser OAuth, self-hosted CodeRabbit, or an Agentic API key. These modes are alternatives. |
| `cr auth logout` | `--agent` | Clear local authentication. |
| `cr auth status` | `--agent` | Show authentication status; agent mode emits JSON. |
| `cr auth org` | `--agent` | Select the default browser-auth organization. Not available for self-hosted or API-key auth. |
| `cr stats` | `--rebuild` | Show local review-history statistics; rebuild rescans stored history. |
| `cr update` | none | Check for and install the latest CLI version. This mutates the installed binary. |
| `cr feedback <message...>` | `--agent` | Send review feedback to CodeRabbit. Present in CLI `0.7.1`; absent from the current published command table, so use installed help as the version-specific contract. |
| `cr config validate [file]` | optional file path | Validate YAML syntax and settings against the current official schema. Without a path, checks `.coderabbit.yaml`, then `.coderabbit.yml` at the Git root. |
| `cr doctor` | none | Check runtime, storage, authentication, repository state, update policy, backend, and WebSocket connectivity. |
| `cr skills` | none | Preview verified first-party skill installs/updates and ask once before writing. Non-interactive runs do not write. |
| `cr help [command]` | command name | Show command help. Every command also accepts `--help`. |

### Review scope rules

- `cr review --committed` reviews only committed changes.
- `cr review --uncommitted` reviews staged changes and tracked edits.
- `cr review --include-untracked` adds non-ignored untracked files and may be combined with `--uncommitted`, but not `--committed`.
- `--committed` and `--uncommitted` are mutually exclusive.
- New files enter the default tracked scope after `git add`; no commit is required.
- `cr --agent` is shorthand for `cr review --agent`.

Agent output is JSONL with `finding`, `review_context`, `status`, `heartbeat`, `complete`, and `error` events. Finding severities are exactly `critical`, `major`, `minor`, `trivial`, and `info`. See [`cli-review`](../cli-review/SKILL.md) for defensive parsing rules.

### Commands not executed automatically

RabbitLoop may inspect help for every command, but it does not automatically run commands that change authentication, organization, installed software, global skills, or send feedback: `cr auth login`, `cr auth logout`, `cr auth org`, `cr update`, `cr skills`, and `cr feedback`. They require a separate explicit request.

## Hosted PR commands

These commands come from the official [review command reference](https://docs.coderabbit.ai/reference/review-commands). Replace `coderabbitai` only when the installation uses a different documented service-account handle.

| Command | Location | Behavior / guard |
|---|---|---|
| `@coderabbitai review` | New PR comment | Incremental review of new changes; consumes one review allowance only when the review runs. |
| `@coderabbitai full review` | New PR comment | Complete review from scratch; consumes one review allowance only when the review runs. |
| `@coderabbitai pause` | PR comment | Pause automatic reviews for this PR. |
| `@coderabbitai resume` | PR comment | Resume automatic reviews. |
| `@coderabbitai ignore` | PR description | Permanently disable automatic review until removed from the description. |
| `@coderabbitai summary` | PR description | Placeholder replaced by the high-level summary. The reference page's summary table calls this a PR comment, but its detailed section explicitly says it is a description placeholder; RabbitLoop follows the detailed section. |
| `@coderabbitai generate docstrings` | PR comment | Generate docstrings when the finishing-touch setting is enabled. |
| `@coderabbitai generate unit tests` | PR comment | Generate unit tests when the finishing-touch setting is enabled. |
| `@coderabbitai autofix` | PR comment | Apply unresolved finding fixes to the current branch. Aliases: `auto-fix`, `auto fix`. |
| `@coderabbitai autofix stacked pr` | PR comment | Apply fixes on a new branch and open a stacked PR. |
| `@coderabbitai resolve merge conflict` | PR comment | Resolve eligible merge conflicts and commit a merge result; may decline security-critical or incompatible changes. |
| `@coderabbitai generate sequence diagram` | PR comment | Generate a sequence diagram for the PR. |
| `@coderabbitai approve` | New top-level PR comment | Resolve CodeRabbit threads, then attempt approval. Approval requires `reviews.request_changes_workflow`. |
| `@coderabbitai resolve` | New top-level PR comment | Resolve all CodeRabbit comments; use only after verifying every finding. |
| `@coderabbitai configuration` | PR comment | Display the resolved configuration and its sources. |
| `@coderabbitai generate configuration` | PR comment | Create a PR containing the resolved configuration, or display the existing file. |
| `@coderabbitai emit path instructions` | PR comment | Open a PR with recent path-instruction suggestions. Alias: `emit path-instructions`. |
| `@coderabbitai help` | PR comment | Show CodeRabbit's current hosted command reference. |

RabbitLoop's autonomous loop intentionally uses only `review`, `full review`, `resolve`, and `approve`. The other commands have broader side effects or different purposes and require an explicit user request.

### Hosted completion evidence

CodeRabbit documents the commands but no hosted completion API. Live GitHub verification on 2026-07-31 showed that a clean incremental review may update the CodeRabbit commit status and summary and return `Review finished.` without creating a formal review object. RabbitLoop accepts that path only when the unchanged requested head is covered by all three newer artifacts: the first unambiguous finished command-result comment, a successful CodeRabbit status on that exact commit, and an updated no-findings summary whose commit range ends at the requested head. See the sanitized [hosted clean-review fixture](../tests/fixtures/hosted-clean-review.json).

No single artifact is sufficient. Acknowledgment, a pending status, a rate-limit summary, comment activity, silence, or a quiet period remains non-terminal.

## Sources

- [CLI overview](https://docs.coderabbit.ai/cli)
- [CLI command reference](https://docs.coderabbit.ai/cli/reference)
- [Headless CLI integration](https://docs.coderabbit.ai/cli/headless-cli-integration)
- [CodeRabbit Skills](https://docs.coderabbit.ai/cli/skills)
- [PR review commands](https://docs.coderabbit.ai/reference/review-commands)
- [Resolve merge conflicts](https://docs.coderabbit.ai/finishing-touches/resolve-merge-conflict)
