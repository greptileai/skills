# greptile skills

[Agent Skills](https://agentskills.io) for automated PR review workflows. Supports GitHub and GitLab. Requires `git` + `gh` CLI (GitHub) or `glab` CLI (GitLab).

## Skills

| Skill | Description |
|-------|-------------|
| [`check-pr`](check-pr/) | Check a PR/MR for unresolved comments, failing checks, incomplete description. Fix and resolve. |
| [`greploop`](greploop/) | Loop: trigger Greptile review, fix comments, re-review — until 5/5 confidence and zero comments. |

Both skills auto-detect the platform (GitHub or GitLab) from the git remote URL.

## Requirements

| Platform | CLI tool | Install |
|----------|----------|---------|
| GitHub | `gh` | [cli.github.com](https://cli.github.com) |
| GitLab | `glab` | [gitlab.com/gitlab-org/cli](https://gitlab.com/gitlab-org/cli) |

Authenticate before use: `gh auth login` or `glab auth login`.

## Install

```bash
git clone https://github.com/greptileai/skills.git ~/.claude/skills/greptile
cd ~/.claude/skills
ln -s greptile/check-pr check-pr
ln -s greptile/greploop greploop
```

Or as a submodule:

```bash
git submodule add https://github.com/greptileai/skills.git .skills/greptile
ln -s greptile/check-pr .skills/check-pr
ln -s greptile/greploop .skills/greploop
```

Claude Code discovers skills by looking for `SKILL.md` files at `~/.claude/skills/<skill-name>/SKILL.md`. Since this is a multi-skill repo, symlinks are needed to expose each sub-skill at the expected depth.

## Usage

Invoke by name in your agent (e.g. `/check-pr 123` or `/greploop`). If no PR/MR number is given, both skills auto-detect the PR/MR for the current branch.

For self-hosted GitLab instances whose hostname doesn't contain "gitlab", pass `--vcs gitlab` explicitly.

## License

MIT
