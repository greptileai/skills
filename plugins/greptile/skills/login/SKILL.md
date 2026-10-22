---
name: login
description: Sign the Greptile CLI bundled with this plugin in to the user's Greptile account through browser OAuth. Use when the user wants to authenticate the Greptile CLI.
metadata:
  internal: true
allowed-tools: Bash(node ${CLAUDE_PLUGIN_ROOT}/scripts/greptile.mjs:*)
---

Sign the bundled Greptile CLI in to the user's account. Tell the user a
browser window will open and that they need to finish signing in there, then
run:

```sh
GREPTILE_NO_UPDATE_CHECK=1 node "${CLAUDE_PLUGIN_ROOT}/scripts/greptile.mjs" login
```

Claude Code fills in `${CLAUDE_PLUGIN_ROOT}`. Anywhere else (Codex), replace
it with the plugin root: the absolute path two folders above the directory
containing this `SKILL.md`. Do not use a separately installed `greptile`.

Allow up to ten minutes for the browser round-trip: give the shell call a
600000 ms timeout, or keep polling a running session until login finishes.

This opens `auth.greptile.com` and saves CLI credentials in
`~/.greptile/auth.json`. The plugin's Greptile MCP server authenticates
separately, through the agent's own MCP settings (`/mcp` in Claude Code, the
plugin settings in Codex), and keeps its own tokens. Signing in to one does
not sign in to the other. If the user wanted MCP tools rather than the CLI,
point them there instead.
