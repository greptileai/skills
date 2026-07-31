# RabbitLoop migration record

- **Date:** 2026-07-31
- **Repository:** `Hassan220022/rabitloop`
- **Goal:** Make the repository CodeRabbit-native while preserving safe local-review, PR-readiness, and bounded fix/re-review workflows.
- **Changed:** [`README.md`](../README.md), [`check-pr/SKILL.md`](../check-pr/SKILL.md), [`cli-review/SKILL.md`](../cli-review/SKILL.md), and [`rabbitloop/SKILL.md`](../rabbitloop/SKILL.md); removed obsolete cross-platform references and the old skill directory.
- **Architecture:** Remains an instruction-only Agent Skills repository. No runtime scripts, parser package, test framework, or new dependency was added.
- **External interfaces:** Git, GitHub CLI, CodeRabbit CLI, GitHub REST/GraphQL, and documented top-level CodeRabbit PR commands only.
- **Safety decisions:** GitHub-only; read-only `/check-pr`; severity-gated fixes; explicit push/PR-action authorization; bounded exponential polling; no inferred review completion, thread state, required-check state, or approval.
- **Validation:** Parsed all skill frontmatter; checked skill names against directory names; resolved local and external Markdown links; syntax-checked Bash fences; ran `git diff --check`; searched for stale branding, unsupported command names, secrets, and machine-local paths.
- **Known limits:** CodeRabbit documents no hosted PR completion API, normal-success JSONL event schemas beyond finding fields, canonical bot handle discovery, or guaranteed approval result. Live external PR mutation was not tested.
- **Follow-up:** Run `/rabbitloop <PR> --dry-run` against a disposable GitHub PR before authorizing push or PR actions.

The durable knowledge-base sync could not run because neither the configured Obsidian MCP nor a local Obsidian CLI was available in this session.
