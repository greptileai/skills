---
name: cli-review
description: >
  Runs a Greptile CLI review for the current local branch, signing the CLI in when needed, then
  summarizes the findings for the user. Uses the CLI bundled with the Greptile plugin when present,
  otherwise a standalone `greptile`. Use when the user wants Greptile feedback before opening a PR,
  outside a hosted PR review flow, or directly from a local checkout.
license: MIT
metadata:
  author: greptileai
  version: "1.1"
allowed-tools: Bash(git:*) Bash(greptile:*) Bash(command:*) Bash(curl:*) Bash(npm:*) Bash(node ${CLAUDE_PLUGIN_ROOT}/scripts/greptile.mjs:*) mcp__plugin_greptile_greptile__get_code_review mcp__plugin_greptile_greptile__list_code_reviews
---

# CLI Review

Run a Greptile review from the local checkout and summarize the findings.

## Instructions

### 1. Confirm repository context

Start from the current repository root:

```bash
git rev-parse --show-toplevel
```

If the command fails, tell the user that the Greptile CLI review must be run from a git repository. Keep the working directory in the repository being reviewed for every command below.

### 2. Choose the CLI

Use the first of these that applies, and call the chosen command `<greptile>` in the steps below.

1. **Claude Code plugin.** If `${CLAUDE_PLUGIN_ROOT}/scripts/greptile.mjs` is an existing file, the plugin root is `${CLAUDE_PLUGIN_ROOT}`.
2. **Other plugin installs (Codex).** The plugin root is two folders above the directory containing this `SKILL.md`. Use it if `<plugin-root>/scripts/greptile.mjs` and `<plugin-root>/scripts/greptile.version` both exist.
3. **Standalone CLI.** Otherwise check `command -v greptile`.

For a bundled CLI, `<greptile>` is the following command, with the plugin root's absolute path in place of `${CLAUDE_PLUGIN_ROOT}` if Claude Code did not substitute it:

```bash
GREPTILE_NO_AUTO_INSTALL=1 GREPTILE_NO_UPDATE_CHECK=1 node "${CLAUDE_PLUGIN_ROOT}/scripts/greptile.mjs"
```

The bundled CLI updates with the plugin, so the variables suppress standalone update notices and the Mermaid renderer download. It needs Node 22 or later. Do not use a separately installed `greptile` when a bundled one exists.

For a standalone CLI, `<greptile>` is `greptile`. If no CLI is available, do not install one automatically. Ask the user for permission, then show the recommended install command:

```bash
npm i -g greptile
```

If npm is unavailable, offer the shell installer fallback:

```bash
curl -fsSL "https://greptile.com/cli/install" | sh
```

After installation, re-run `command -v greptile`.

### 3. Ensure authentication

Check the signed-in account:

```bash
<greptile> whoami
```

If the CLI reports that authentication is missing, tell the user a browser window will open for sign-in at `auth.greptile.com`, then run:

```bash
<greptile> login
```

Allow up to ten minutes for the browser round-trip; give the shell call a 600000 ms timeout, or keep polling a running session until it finishes. The CLI keeps its credentials in `~/.greptile/auth.json`, shared by the bundled and standalone CLIs. The Greptile MCP server authenticates separately, through the agent's own MCP settings; signing in to one does not sign in to the other.

### 4. Run the review

```bash
<greptile> review --agent
```

Always pass `--agent`: it prints plain text meant for agents and never prompts or opens a browser. If the user names a base branch, append `--branch <branch>`. Pass any focus instructions with `--instructions '<their words>'`. Single-quote both values so that `$`, backticks, and command substitutions in user text are passed literally; replace each `'` in their text with `'\''`.

The review covers committed changes only. Reviews can take longer than two minutes. If the shell tool returns a running session, keep polling it rather than starting a second review.

If the command fails, report the failing command and the next action the user needs to take, rather than presenting it as a successful review.

### 5. Summarize results

Report:

- Review status
- Number of findings
- Highest severity findings first
- Files that need edits
- Suggested next command or fix path

Keep the summary concise and focused on actionable findings, then offer to fix them. The review is stored on the user's Greptile account; when the Greptile MCP server is connected, `list_code_reviews` and `get_code_review` with `source: "headless"` return more detail on each finding.
