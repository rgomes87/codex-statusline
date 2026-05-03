# Codex Statusline

Standalone tmux statusline for Codex CLI, inspired by a Claude Code statusline.

This repository is intentionally small and does not replace or override any existing
repository. It packages only the Codex-owned statusline scripts:

- `codex-statusline.sh` renders the status rows from Codex session JSONL data.
- `codex-with-status.sh` launches Codex inside tmux with a persistent four-line
  status area.

The statusline shows:

- context window usage with token count and percentage
- total input and output tokens
- model and reasoning effort
- current directory and git branch state
- 5h and 7d Codex rate limit remaining bars with reset countdowns

Claude files are not included and are not modified by this repo.
