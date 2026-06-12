# Greptile CLI Reference

Use this reference when exact Greptile CLI flag behavior matters.

Source: https://www.greptile.com/docs/code-review/greptile-cli

## Setup

```bash
npm i -g greptile
greptile --version
greptile login
greptile whoami
greptile logout
```

## Review commands

```bash
greptile review
greptile review -b main
greptile review --resume
greptile review --diff
greptile review --diff --context=25
```

By default, Greptile compares the current branch against the repository default branch, usually `main`, and reviews unmerged committed branch changes. Uncommitted changes are ignored.

## Output formats

```bash
greptile review --json
greptile review --agent
greptile review --text
```

`--agent` is an alias for `--text`. Plain text is also used automatically when output is piped.

## Reopen reviews

```bash
greptile review show
greptile review show REVIEW_ID
```

## Useful flags

| Flag | Purpose |
|---|---|
| `-b, --branch=<BRANCH>` | Base branch to compare against |
| `--resume` | Continue the latest unfinished review |
| `--diff` | Show findings inline with relevant code |
| `--context=<LINES>` | Lines of surrounding code for inline findings. Default: 15 |
| `--json` | Print machine-readable output |
| `--text, --agent` | Print plain text for agent workflows |
| `--width=<COLUMNS>` | Set output width |
| `--no-color` | Disable colored output |
