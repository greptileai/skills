---
name: review
description: Review the current working branch with the Greptile CLI bundled with this plugin, optionally against a given base branch or with focus instructions. No pull request is needed.
argument-hint: "[base branch] [what to focus on]"
metadata:
  internal: true
allowed-tools: Bash(node ${CLAUDE_PLUGIN_ROOT}/scripts/greptile.mjs:*) mcp__plugin_greptile_greptile__get_code_review mcp__plugin_greptile_greptile__list_code_reviews
---

Run a Greptile review on the current branch, against its base branch. Keep the
working directory in the repository being reviewed.

```sh
GREPTILE_NO_AUTO_INSTALL=1 GREPTILE_NO_UPDATE_CHECK=1 node "${CLAUDE_PLUGIN_ROOT}/scripts/greptile.mjs" review --agent
```

Claude Code fills in `${CLAUDE_PLUGIN_ROOT}`. Anywhere else (Codex), replace
it with the plugin root: the absolute path two folders above the directory
containing this `SKILL.md`. Do not use a separately installed `greptile`.

Build the rest of the command from what the user asked for, including any
arguments:

- A branch they want to review against becomes `--branch <BRANCH>`.
- Anything else is what they want the reviewer to focus on. Pass it as
  `--instructions '<their words>'` using **single** quotes, so the reviewer
  receives their exact text. Replace each `'` in their text with `'\''` and
  change nothing else. Never use double quotes: `$` and backticks are live
  inside them.

Always pass `--agent`: it prints plain text meant for agents and never prompts
or opens a browser. `GREPTILE_NO_AUTO_INSTALL=1` stops the CLI downloading the
Mermaid renderer, and `GREPTILE_NO_UPDATE_CHECK=1` stops standalone update
notices; the bundled CLI updates with the plugin.

Reviews often take longer than two minutes. Give the shell call a 600000 ms
timeout, or keep polling a running session rather than starting a second
review.

If the run reports that no one is signed in, tell the user to sign in with
this plugin's `login` skill (`/greptile:login` in Claude Code) and stop there.
Do not start a browser sign-in as a side effect of a review.

The review is stored on the user's Greptile account, so the Greptile MCP tools
`list_code_reviews` and `get_code_review` can read it back with
`source: "headless"`. Summarize the findings and offer to fix them, using
`get_code_review` for more detail on any finding. If the command fails, report
the failure and the next action rather than presenting it as a successful
review.
