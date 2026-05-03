# codex-statusline

A colourful, information-dense 4-line status area for [Codex CLI](https://openai.com/codex), built with bash and tmux.

Codex does not currently expose the same native `statusLine` hook that Claude Code does, so this repo provides a small tmux wrapper. The wrapper launches Codex inside tmux and keeps a persistent 4-line status area at the bottom of the terminal.

## Preview

```text
❮■■■|□□□□□□□❯ 86.5k - 33%  ⬇️ 2507.9k ⬆️ 19.9k
GPT-5.5 · medium ∷ ~/project  🌿 main
🟡 5h ▮▮▮▮▮▮▯▯▯▯ 69% ⏱️    0h 19m 50s
🟡 7d ▮▮▮▮▮▮▯▯▯▯ 67% ⏱️ 3d 17h 51m 14s
```

**Line 1 — Context window**
- 10-cell gradient bar (green → yellow → orange → red) with `■`/`□` squares
- `❮`/`❯` brackets colour-matched to the percentage urgency
- Approximate context tokens in use and percentage: `86.5k - 33%`
- Token counts: ⬇️ input / ⬆️ output
- 100k marker (`|`) in the bar, useful as an early context-quality warning

**Line 2 — Session info**
- Active Codex model and reasoning effort, separated from location by `∷`
- Current working directory, truncated to the last 2 components
- 🌿 Git branch with status: `✎N` dirty files · `↑N` ahead · `↓N` behind

**Line 3 — 5-hour rate limit**
- Shown as **remaining** capacity (starts full, drains to empty)
- Emoji health dot: 🟢 > 75% · 🟡 > 50% · 🟠 > 25% · 🔴 > 0% · ⭕ empty
- `▮`/`▯` bar drains green → red as allowance is consumed
- Inline reset countdown with seconds (⏱️ `Nh Nm Ns`)

**Line 4 — 7-day rate limit**
- Same format as line 3, always on its own line for easy scanning
- Reset countdown includes full detail: `Nd Nh Nm Ns`

---

## Requirements

- **Codex CLI**
- `bash`
- `tmux` — used to keep the status area visible while the terminal scrolls
- `jq` — for parsing Codex session JSONL
- `git` — for branch and status info
- macOS-style `stat -f` for latest-session discovery

Install dependencies if needed:

```bash
# macOS
brew install tmux jq

# Ubuntu/Debian
sudo apt install tmux jq
```

---

## Install

**1. Download the scripts**

```bash
mkdir -p ~/.codex

curl -o ~/.codex/codex-statusline.sh \
  https://raw.githubusercontent.com/rgomes87/codex-statusline/main/codex-statusline.sh

curl -o ~/.codex/codex-with-status.sh \
  https://raw.githubusercontent.com/rgomes87/codex-statusline/main/codex-with-status.sh
```

**2. Make them executable**

```bash
chmod +x ~/.codex/codex-statusline.sh ~/.codex/codex-with-status.sh
```

**3. Launch Codex through the wrapper**

```bash
~/.codex/codex-with-status.sh
```

Optional shell alias:

```bash
alias codex-status='~/.codex/codex-with-status.sh'
```

**4. Restart the wrapped session** — the status area appears at the bottom of the terminal.

---

## Customisation

**Colours** — The script emits tmux style segments using 256-colour names such as `colour82`. Change any `c256 82` style call to a different colour number.

**Context bar width** — Change `BAR_WIDTH=10` in `codex-statusline.sh`.

**Refresh interval** — Change `status-interval 2` in `codex-with-status.sh`.

**Session name** — Change `SESSION_NAME="codex-status"` in `codex-with-status.sh`.

**Disable wrapping temporarily** — Set:

```bash
CODEX_STATUS_DISABLE=1 codex
```

---

## How it works

Codex writes session events under `~/.codex/sessions` as JSONL. `codex-statusline.sh` reads the latest session file, extracts the most recent token-count and turn-context events, then prints tmux-formatted status rows.

`codex-with-status.sh` launches Codex inside tmux, configures tmux with `status 4`, and maps each row to:

```text
status-format[0] → codex-statusline.sh --line 1
status-format[1] → codex-statusline.sh --line 2
status-format[2] → codex-statusline.sh --line 3
status-format[3] → codex-statusline.sh --line 4
```

The renderer is read-only. It does not write session data, modify Codex files, or start background processes beyond the tmux session used by the wrapper.

---

## Notes

- This is a Codex/tmux package, not a Claude Code statusline.
- It does not include or modify Claude files.
- Rate-limit values depend on the fields present in Codex session events.
- The scripts intentionally avoid hardcoded user paths and use `$HOME`.

---

## License

MIT
