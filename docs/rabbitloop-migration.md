# RabbitLoop migration record

- **Date:** 2026-07-31
- **Repository:** `Hassan220022/coderabbit-loop`
- **Repository rename:** The fork moved from `Hassan220022/rabitloop` to `Hassan220022/coderabbit-loop`; RabbitLoop remains the product and skill name.
- **Goal:** Make the repository CodeRabbit-native while preserving safe local-review, PR-readiness, and bounded fix/re-review workflows.
- **Changed:** [`README.md`](../README.md), [`check-pr/SKILL.md`](../check-pr/SKILL.md), [`cli-review/SKILL.md`](../cli-review/SKILL.md), and [`rabbitloop/SKILL.md`](../rabbitloop/SKILL.md); removed obsolete cross-platform references and the old skill directory.
- **Architecture:** Remains an instruction-only Agent Skills repository. Validation scripts require Ruby and Pandoc, but no product runtime, parser package, test framework, or project dependency was added.
- **External interfaces:** Git, GitHub CLI, CodeRabbit CLI, GitHub REST/GraphQL, and documented top-level CodeRabbit PR commands only.
- **Safety decisions:** GitHub-only; read-only `/check-pr`; severity-gated fixes; explicit push/PR-action authorization; bounded exponential polling; no completion from partial evidence, silence, thread state, required-check state, or command-only approval.
- **Validation:** Parsed all skill frontmatter; checked skill names against directory names; resolved local and external Markdown links; syntax-checked Bash fences; ran `git diff --check`; searched for stale branding, unsupported command names, secrets, and machine-local paths.
- **Known limits:** CodeRabbit documents no hosted PR completion API, normal-success JSONL event schemas beyond finding fields, canonical bot handle discovery, or guaranteed approval result. RabbitLoop therefore requires either a submitted review on the requested head or the complete correlated clean-review evidence set. Hosted clean-review, rate-limit, resolve, and approval-command behavior were tested on the fork PR; approval was not confirmed because `reviews.request_changes_workflow` is disabled.
- **Follow-up:** Run `/rabbitloop <PR> --dry-run` against a disposable GitHub PR before authorizing push or PR actions.

The durable knowledge-base note was synced through an external Obsidian MCP without storing credentials or adding an in-repository integration.
