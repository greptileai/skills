# Greptile

[Greptile](https://greptile.com) is an AI code review agent for GitHub and GitLab that automatically reviews pull requests. This plugin gives Claude Code and Codex two ways to work with it:

- the **Greptile MCP server**, for reading and resolving review results, and for searching your organization's knowledge base and coding patterns
- the **Greptile CLI**, for dispatching a review of your working branch before a pull request exists

They are two ends of one pipeline. The CLI dispatches reviews; the MCP server reads them back — both the ones the CLI dispatched (`source: "headless"`) and the ones Greptile ran on your pull requests (`source: "pr"`).

## Install

Claude Code:

```
/plugin marketplace add greptileai/skills
/plugin install greptile@greptile-plugin
```

Codex:

```
codex plugin marketplace add greptileai/skills
codex plugin add greptile@greptile-plugin
```

## Setup

Nothing to install and no API key to create. Both surfaces sign in over OAuth at [auth.greptile.com](https://auth.greptile.com).

**MCP server.** Authenticate **greptile** from the `/mcp` menu in Claude Code, or connect it from the plugin settings in Codex. Your agent stores and refreshes the tokens.

**CLI.** Run `/greptile:login` in Claude Code, or ask Codex to sign in with the plugin's `login` skill. The CLI ships with the plugin, so there is no npm or Homebrew install to do, but it is a Node program and needs Node 22 or later.

The two sign-ins are separate: same Greptile account, same OAuth provider, but the CLI keeps its own credentials in `~/.greptile/auth.json` while your agent keeps the MCP tokens in its own store. Use whichever surface you need; you only have to sign in to that one.

## Skills

- **review** (`/greptile:review` in Claude Code) — Review the current branch against its base. Accepts a base branch and free-text instructions ("focus on the auth changes").
- **login** (`/greptile:login` in Claude Code) — Sign the CLI in to your Greptile account.

For more Greptile skills, such as `greploop`, run `greptile skills install` or see the [repository README](../../README.md).

## Tools

### Account and repositories
- `get_me` - Identify your account and available organizations
- `list_repositories` - Discover accessible repositories and identifiers for the other tools

### Pull requests
- `list_merge_requests` / `list_pull_requests` - List PRs, filtered by repository, branch, author, or state
- `get_merge_request` - Detailed PR info, including stored addressed flags and commits since the latest review comment
- `list_merge_request_comments` - All comments on a PR, with Greptile comments identified by `isGreptileComment`

### Code reviews
- `list_code_reviews` - List code reviews, filtered by repository or status
- `get_code_review` - Full review body, status, summary citations, and review metadata
- `trigger_code_review` - Start a Greptile review on a pull request (GitHub and GitLab)
- `search_greptile_comments` - Search Greptile's review comments across every review, on pull requests and on headless CLI runs alike

### Knowledge base
- `list_knowledge_bases` - Repositories your organization has knowledge base data for
- `list_knowledge_base_documents` - Document paths in a repository's published knowledge base
- `get_knowledge_base_document` - Markdown body of a single knowledge base document
- `search_knowledge_base` - Substring search across one repository's knowledge base

### Custom context
- `list_custom_context` - Your organization's coding patterns and rules
- `get_custom_context` - Details for one entry and linked comment references
- `search_custom_context` - Search entries by content
- `create_custom_context` - Create a new entry, either a custom instruction (the default) or a pattern

### Analytics
- `get_analytics_overview` - Summary metrics and period changes, chart series, and repository, contributor, and pull request rankings
- `list_analytics_findings` - Findings with severity and security totals and trends, filterable by team, repository, author, severity, or status
- `list_analytics_filter_options` - The teams, repositories, and authors available to you as analytics filters

## Bundled CLI

`scripts/greptile.mjs` is the Greptile CLI, vendored from the published npm package
`greptile` (its `dist/greptile.js`, renamed only so Node reads it as ESM without a
sibling `package.json`). `scripts/greptile.version` records which release it is, and
CI verifies the file byte-for-byte against that version's npm tarball, so the copy
running here is the same one npm serves.

Because the CLI ships with the plugin, it updates with the plugin — not through
`greptile update`, `npm`, or `brew`. Any separate `greptile` you have installed is
untouched and unused by the plugin, though both share your login at
`~/.greptile/auth.json`.

## Network access

The plugin registers no hooks. What it contacts:

- `api.greptile.com` — the MCP server, the CLI's API, and CLI telemetry
  (below).
- `auth.greptile.com` — OAuth sign-in, for both surfaces.
- `app.greptile.com` — link targets printed in review output.
- `127.0.0.1` — a loopback listener the CLI opens to receive the OAuth
  callback during `login`, closed as soon as the redirect arrives.

### Telemetry

The bundled CLI reports anonymous usage events to `/v1/telemetry` on the same
host as its API. The events are lifecycle signals — `cli_first_run`,
`cli_login_started`, `cli_login_failed`, `cli_onboarding_started`,
`cli_skill_installed`, `cli_skill_updated`, `cli_review_blocked`,
`cli_update_completed` — carrying your install method, OS, architecture,
whether the run was interactive, and which agent surface it ran under. Nothing
else: no code, no repository or branch names, no file paths, no review content.
Event-specific fields are fixed values: `method`, `exit_code`, `reason`, the
version strings on an update, and the name of the Greptile-authored skill on
the two skill events.

When invoked without a TTY, as it is inside an agent, the CLI cannot ask for
telemetry consent. It falls back to **anonymous mode**: a random `cli:<uuid>`
stored in `telemetry.json`, no account token attached, and no profile built on
the other end. If you have separately opted in from a standalone `greptile` on
the same machine, that decision carries over here and events are sent under
your account instead.

To turn it off, any one of these is enough:

```sh
export GREPTILE_TELEMETRY_DISABLED=1   # or DO_NOT_TRACK=1
greptile settings set telemetry false  # standalone CLI
node "<plugin-root>/scripts/greptile.mjs" settings set telemetry false  # bundled CLI
```

`CI=1` also disables it, and a CLI pointed at a self-hosted Greptile sends no
telemetry at all.

### Downloads

One thing here fetches software, and this is it. When a review summary
contains a Mermaid diagram, the CLI renders it with
`mmdr`, a small standalone binary fetched on first use from
[github.com/1jehuang/mermaid-rs-renderer](https://github.com/1jehuang/mermaid-rs-renderer)
into `~/.cache/greptile/bin/`. The archive is checked against a SHA-256 pinned
per platform inside the bundle and is deleted rather than run if the hash does
not match; the download announces itself on stderr, and failing to get it
degrades the diagram to a link instead of failing the review. Setting
`GREPTILE_NO_AUTO_INSTALL=1` skips it. **The `review` skill sets that
variable**, so the plugin does not download it — the code path
is reachable only if you invoke the bundled CLI yourself without it.

## Packaging for the OpenAI directory

The OpenAI directory takes a ZIP of the plugin. From the repository root, package a committed revision, including the bundled CLI, without repository-only files:

```sh
git archive --format=zip --output=/tmp/greptile-plugin.zip HEAD:plugins/greptile -- .codex-plugin/plugin.json .mcp.json assets scripts skills README.md
```

`.codex-plugin/chatgpt-app-submission.json` holds the tool justifications and
test cases for the submission form.
