# greptile skills

[Agent Skills](https://agentskills.io) for automated code review workflows. Supports GitHub, GitLab, Perforce, and direct local review through the Greptile CLI. Requires `git` plus the relevant provider CLI.

## Skills

| Skill | Description |
|-------|-------------|
| [`check-pr`](check-pr/) | Check a PR/MR/CL for unresolved comments, failing checks, incomplete description. Fix and resolve. |
| [`greploop`](greploop/) | Loop: trigger Greptile review, fix comments, re-review — until 5/5 confidence and zero comments. |
| [`greploop-cli`](greploop-cli/) | Loop: run `greptile review` locally, fix findings, re-review until clean. |

`check-pr` and `greploop` auto-detect the platform (GitHub, GitLab, or Perforce) from the environment.
`greploop-cli` skips hosted PR/MR/CL APIs and uses the local Greptile CLI directly.

## Requirements

| Platform | CLI tool | Install |
|----------|----------|---------|
| GitHub | `gh` | [cli.github.com](https://cli.github.com) |
| GitLab | `glab` | [gitlab.com/gitlab-org/cli](https://gitlab.com/gitlab-org/cli) |
| Perforce | `p4` | [perforce.com/downloads](https://www.perforce.com/downloads/helix-command-line-client-p4) |
| Greptile CLI | `greptile` | Run `greptile login` before using `greploop-cli` |

Authenticate before use: `gh auth login`, `glab auth login`, or configure `P4PORT`/`P4USER`/`P4CLIENT` for Perforce.
For direct CLI review, authenticate with `greptile login`.

## Install

```bash
git clone https://github.com/greptileai/skills.git ~/.claude/skills/greptile
cd ~/.claude/skills
ln -s greptile/check-pr check-pr
ln -s greptile/greploop greploop
ln -s greptile/greploop-cli greploop-cli
```

Or as a submodule:

```bash
git submodule add https://github.com/greptileai/skills.git .skills/greptile
ln -s greptile/check-pr .skills/check-pr
ln -s greptile/greploop .skills/greploop
ln -s greptile/greploop-cli .skills/greploop-cli
```

Claude Code discovers skills by looking for `SKILL.md` files at `~/.claude/skills/<skill-name>/SKILL.md`. Since this is a multi-skill repo, symlinks are needed to expose each sub-skill at the expected depth.

## Usage

Invoke by name in your agent (e.g. `/check-pr 123`, `/greploop`, or `/greploop-cli`). If no PR/MR/CL number is given, `check-pr` and `greploop` auto-detect the PR/MR for the current branch, or the pending changelist for Perforce.

For self-hosted GitLab instances whose hostname doesn't contain "gitlab", pass `--vcs gitlab` explicitly. For Perforce, pass `--vcs perforce` if auto-detection fails.

Use Greptile CLI review directly with:

```bash
/greploop-cli
/greploop-cli --branch main
/greploop-cli --resume
```

## License

MIT
