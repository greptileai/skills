# greptile skills

[Agent Skills](https://agentskills.io) for automated PR review workflows. Requires `git` + `gh` CLI.

## Skills

| Skill | Description |
|-------|-------------|
| [`check-pr`](check-pr/) | Check a PR for unresolved comments, failing checks, incomplete description. Fix and resolve. |
| [`greploop`](greploop/) | Loop: trigger Greptile review, fix comments, re-review — until 5/5 confidence and zero comments. |

## Install

```bash
git clone https://github.com/greptileai/skills.git ~/.claude/skills/greptile
```

Or as a submodule:

```bash
git submodule add https://github.com/greptileai/skills.git .skills/greptile
```

Skills are auto-discovered from the directory. Each subfolder with a `SKILL.md` is a skill.

## Usage

Invoke by name in your agent (e.g. `/check-pr 123` or `/greploop`). If no PR number is given, both skills auto-detect the PR for the current branch.

## License

MIT
