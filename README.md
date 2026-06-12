# greptile skills

[Agent Skills](https://agentskills.io) for automated Greptile review workflows. Supports local branch reviews with Greptile CLI, plus GitHub, GitLab, and Perforce review workflows.

## Skills

| Skill | Description |
|-------|-------------|
| [`check-pr`](check-pr/) | Check a PR/MR/CL for unresolved comments, failing checks, incomplete description. Fix and resolve. |
| [`greploop`](greploop/) | Loop: trigger Greptile review, fix comments, re-review — until 5/5 confidence and zero comments. |
| [`review-branch`](review-branch/) | Review the current committed branch diff with Greptile CLI before opening a PR/MR. |

`check-pr` and `greploop` auto-detect the platform (GitHub, GitLab, or Perforce) from the environment. `review-branch` uses Greptile CLI for local Git branch reviews before a PR/MR exists.

## Requirements

| Platform | CLI tool | Install |
|----------|----------|---------|
| GitHub | `gh` | [cli.github.com](https://cli.github.com) |
| GitLab | `glab` | [gitlab.com/gitlab-org/cli](https://gitlab.com/gitlab-org/cli) |
| Perforce | `p4` | [perforce.com/downloads](https://www.perforce.com/downloads/helix-command-line-client-p4) |
| Local branch review | `git` + `greptile` | [Greptile CLI](https://www.greptile.com/docs/code-review/greptile-cli) |

Authenticate before use: `gh auth login`, `glab auth login`, configure `P4PORT`/`P4USER`/`P4CLIENT` for Perforce, or run `greptile login` for Greptile CLI.

## Install

```bash
git clone https://github.com/greptileai/skills.git ~/.claude/skills/greptile
cd ~/.claude/skills
ln -s greptile/check-pr check-pr
ln -s greptile/greploop greploop
ln -s greptile/review-branch review-branch
```

Or as a submodule:

```bash
git submodule add https://github.com/greptileai/skills.git .skills/greptile
ln -s greptile/check-pr .skills/check-pr
ln -s greptile/greploop .skills/greploop
ln -s greptile/review-branch .skills/review-branch
```

Claude Code discovers skills by looking for `SKILL.md` files at `~/.claude/skills/<skill-name>/SKILL.md`. Since this is a multi-skill repo, symlinks are needed to expose each sub-skill at the expected depth.

## Usage

Invoke by name in your agent (e.g. `/check-pr 123`, `/greploop`, or `/review-branch main`). If no PR/MR/CL number is given, `check-pr` and `greploop` auto-detect the PR/MR for the current branch, or the pending changelist for Perforce. `review-branch` reviews the current local Git branch against a base branch with Greptile CLI.

For self-hosted GitLab instances whose hostname doesn't contain "gitlab", pass `--vcs gitlab` explicitly. For Perforce, pass `--vcs perforce` if auto-detection fails.

## License

MIT
