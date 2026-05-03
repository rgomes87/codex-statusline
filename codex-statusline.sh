#!/bin/bash
set -euo pipefail

reset_style='#[default]'
bold_style='bold'

GREY="#585f6d"
SILVER="#bcbcbc"
CYAN="#00ffff"
BLUE="#5fafff"
MAGENTA="#ff87ff"
PINK="#ff5faf"
MUTED_CYAN="#5fafaf"

BAR_WIDTH=10

c256() {
  printf 'colour%s' "$1"
}

style() {
  printf '#[%s]' "$1"
}

segment() {
  local style_spec="$1"
  local text="$2"
  style "$style_spec"
  printf '%s' "$text"
  printf '%s' "$reset_style"
}

latest_session_file() {
  find "$HOME/.codex/sessions" -type f -name '*.jsonl' -print0 2>/dev/null |
    xargs -0 stat -f '%m %N' 2>/dev/null |
    sort -nr |
    head -n 1 |
    cut -d' ' -f2-
}

clamp_pct() {
  local pct="${1:-0}"
  pct="${pct%.*}"
  if ! [[ "$pct" =~ ^-?[0-9]+$ ]]; then
    pct=0
  fi
  [ "$pct" -lt 0 ] && pct=0
  [ "$pct" -gt 100 ] && pct=100
  printf '%s' "$pct"
}

fmt_tok() {
  local n="${1:-0}"
  if ! [[ "$n" =~ ^[0-9]+$ ]]; then
    n=0
  fi
  if [ "$n" -ge 1000 ]; then
    awk -v value="$n" 'BEGIN { printf "%.1fk", value / 1000 }'
  else
    printf '%s' "$n"
  fi
}

fmt_reset() {
  local ts="${1:-}"
  local now diff days hours mins secs
  [ -n "$ts" ] || return 1
  [[ "$ts" =~ ^[0-9]+$ ]] || return 1

  now="$(date +%s)"
  diff=$((ts - now))
  [ "$diff" -gt 0 ] || return 1

  days=$((diff / 86400))
  hours=$(((diff % 86400) / 3600))
  mins=$(((diff % 3600) / 60))
  secs=$((diff % 60))
  if [ "$days" -gt 0 ]; then
    printf '%dd %dh %dm %ds' "$days" "$hours" "$mins" "$secs"
  else
    printf '   %dh %dm %ds' "$hours" "$mins" "$secs"
  fi
}

format_model() {
  local model="${1:-Codex}"
  case "$model" in
    gpt-5.5) printf 'GPT-5.5' ;;
    gpt-5.4) printf 'GPT-5.4' ;;
    gpt-5.4-mini) printf 'GPT-5.4 MINI' ;;
    gpt-5.4-nano) printf 'GPT-5.4 NANO' ;;
    gpt-5.4-pro) printf 'GPT-5.4 PRO' ;;
    gpt-5.3-codex) printf 'GPT-5.3 CODEX' ;;
    gpt-5.2) printf 'GPT-5.2' ;;
    gpt-5) printf 'GPT-5' ;;
    *) printf '%s' "$model" | tr '[:lower:]' '[:upper:]' ;;
  esac
}

format_cwd() {
  local raw_cwd="${1:-$PWD}"
  local short_cwd stripped count last_two

  short_cwd="${raw_cwd/#$HOME/~}"
  stripped="${short_cwd#\~}"
  stripped="${stripped#/}"
  count="$(printf '%s\n' "$stripped" | awk -F'/' '{print NF}')"
  if [ "$count" -gt 2 ]; then
    last_two="$(printf '%s\n' "$stripped" | awk -F'/' '{print $(NF-1) "/" $NF}')"
    short_cwd="…/${last_two}"
  fi
  printf '%s' "$short_cwd"
}

filled_context_color() {
  case "$1" in
    1) printf '%s' "$(c256 46)" ;;
    2) printf '%s' "$(c256 82)" ;;
    3) printf '%s' "$(c256 118)" ;;
    4) printf '%s' "$(c256 154)" ;;
    5) printf '%s' "$(c256 190)" ;;
    6) printf '%s' "$(c256 226)" ;;
    7) printf '%s' "$(c256 220)" ;;
    8) printf '%s' "$(c256 214)" ;;
    9) printf '%s' "$(c256 202)" ;;
    10) printf '%s' "$(c256 196)" ;;
    *) printf '%s' "$(c256 46)" ;;
  esac
}

context_bar() {
  local pct max_window ctx_toks sep_cell show_sep sep_col filled i col display
  pct="$(clamp_pct "${1:-0}")"
  max_window="${2:-0}"
  ctx_toks="${3:-0}"
  if ! [[ "$max_window" =~ ^[0-9]+$ ]] || [ "$max_window" -eq 0 ]; then
    max_window=200000
  fi
  if ! [[ "$ctx_toks" =~ ^[0-9]+$ ]]; then
    ctx_toks=0
  fi

  sep_cell="$(awk -v max="$max_window" -v width="$BAR_WIDTH" 'BEGIN { printf "%d", 100000 / max * width }' 2>/dev/null || printf '5')"
  show_sep=0
  [ "$sep_cell" -gt 0 ] && [ "$sep_cell" -lt "$BAR_WIDTH" ] && show_sep=1
  if [ "$ctx_toks" -ge 100000 ]; then
    sep_col="$(c256 208)"
  else
    sep_col="$(c256 255)"
  fi

  filled=$((pct * BAR_WIDTH / 100))

  segment "fg=$(filled_context_color "$filled"),$bold_style" "❮"
  for i in $(seq 1 "$BAR_WIDTH"); do
    if [ "$show_sep" -eq 1 ] && [ "$i" -eq "$((sep_cell + 1))" ]; then
      segment "fg=$sep_col,$bold_style" "|"
    fi
    if [ "$i" -le "$filled" ]; then
      col="$(filled_context_color "$i")"
      segment "fg=$col,$bold_style" "■"
    else
      segment "fg=$(c256 240)" "□"
    fi
  done
  segment "fg=$(filled_context_color "$filled"),$bold_style" "❯"
  printf ' '
  display="$(printf '%s - %d%%' "$(fmt_tok "$ctx_toks")" "$pct")"
  segment "fg=$(filled_context_color "$filled"),$bold_style" "$display"
}

effort_label() {
  local effort="${1:-}"
  case "$effort" in
    low) segment "fg=$(c256 220),$bold_style" "low" ;;
    medium) segment "fg=$(c256 82),$bold_style" "medium" ;;
    high) segment "fg=$(c256 105),$bold_style" "high" ;;
    xhigh) segment "fg=$(c256 141),$bold_style" "xhigh" ;;
    max)
      segment "fg=$(c256 196),$bold_style" "m"
      segment "fg=$(c256 226),$bold_style" "a"
      segment "fg=$(c256 46),$bold_style" "x"
      ;;
    "") return 1 ;;
    *) segment "fg=$SILVER,$bold_style" "$effort" ;;
  esac
}

git_segment() {
  local raw_cwd="${1:-$PWD}"
  local branch dirty upstream ahead behind
  branch="$(git -C "$raw_cwd" branch --show-current 2>/dev/null || true)"
  [ -n "$branch" ] || return 0

  printf '🌿 '
  segment "fg=$(c256 117),$bold_style" "$branch"

  dirty="$(git -C "$raw_cwd" status --porcelain 2>/dev/null | grep -c '^[^?]' || true)"
  if [ "${dirty:-0}" -gt 0 ]; then
    printf ' '
    segment "fg=$(c256 208),$bold_style" "✎${dirty}"
  fi

  upstream="$(git -C "$raw_cwd" rev-parse --abbrev-ref '@{u}' 2>/dev/null || true)"
  if [ -n "$upstream" ]; then
    ahead="$(git -C "$raw_cwd" rev-list --count '@{u}..HEAD' 2>/dev/null || printf '0')"
    behind="$(git -C "$raw_cwd" rev-list --count 'HEAD..@{u}' 2>/dev/null || printf '0')"
    if [ "${ahead:-0}" -gt 0 ]; then
      printf ' '
      segment "fg=$(c256 82),$bold_style" "↑${ahead}"
    fi
    if [ "${behind:-0}" -gt 0 ]; then
      printf ' '
      segment "fg=$(c256 196),$bold_style" "↓${behind}"
    fi
  fi
}

rate_color_for_fill() {
  case "$1" in
    10) printf '%s' "$(c256 46)" ;;
    9) printf '%s' "$(c256 82)" ;;
    8) printf '%s' "$(c256 118)" ;;
    7) printf '%s' "$(c256 154)" ;;
    6) printf '%s' "$(c256 190)" ;;
    5) printf '%s' "$(c256 226)" ;;
    4) printf '%s' "$(c256 220)" ;;
    3) printf '%s' "$(c256 214)" ;;
    2) printf '%s' "$(c256 202)" ;;
    *) printf '%s' "$(c256 196)" ;;
  esac
}

rate_symbol() {
  local remaining="$1"
  if [ "$remaining" -gt 75 ]; then
    printf '🟢'
  elif [ "$remaining" -gt 50 ]; then
    printf '🟡'
  elif [ "$remaining" -gt 25 ]; then
    printf '🟠'
  elif [ "$remaining" -gt 0 ]; then
    printf '🔴'
  else
    printf '⭕'
  fi
}

rate_line() {
  local label="$1"
  local used="${2:-}"
  local reset_at="${3:-}"
  local used_pct remaining filled col i countdown

  [ -n "$used" ] || return 0
  used_pct="$(clamp_pct "$used")"
  remaining=$((100 - used_pct))
  filled=$((remaining * BAR_WIDTH / 100))
  col="$(rate_color_for_fill "$filled")"

  printf '%s' "$(rate_symbol "$remaining")"
  printf ' '
  segment "fg=$(c256 250),$bold_style" "$label"
  printf ' '
  for i in $(seq 1 "$BAR_WIDTH"); do
    if [ "$i" -le "$filled" ]; then
      segment "fg=$col" "▮"
    else
      segment "fg=$(c256 240)" "▯"
    fi
  done
  printf ' '
  segment "fg=$col,$bold_style" "${remaining}%"

  countdown="$(fmt_reset "$reset_at" 2>/dev/null || true)"
  if [ -n "$countdown" ]; then
    printf ' '
    printf ' ⏱️ '
    segment "fg=$MUTED_CYAN,$bold_style" "$countdown"
  fi
}

session_file="$(latest_session_file)"
[ -n "${session_file:-}" ] || exit 0
[ -f "$session_file" ] || exit 0

snapshot="$(tail -n 600 "$session_file" 2>/dev/null || true)"
[ -n "$snapshot" ] || exit 0

token_line="$(
  printf '%s\n' "$snapshot" |
    jq -rc 'select(.type == "event_msg" and .payload.type == "token_count" and .payload.info != null)' 2>/dev/null |
    tail -n 1
)"
turn_line="$(
  printf '%s\n' "$snapshot" |
    jq -rc 'select(.type == "turn_context" and .payload != null)' 2>/dev/null |
    tail -n 1
)"

[ -n "${token_line:-}" ] || exit 0

raw_cwd="$(printf '%s' "${turn_line:-}" | jq -r '.payload.cwd // ""' 2>/dev/null)"
[ -n "$raw_cwd" ] || raw_cwd="$PWD"
model_slug="$(printf '%s' "${turn_line:-}" | jq -r '.payload.model // "codex"' 2>/dev/null)"
effort="$(printf '%s' "${turn_line:-}" | jq -r '.payload.effort // ""' 2>/dev/null)"

ctx_tokens="$(printf '%s' "$token_line" | jq -r '.payload.info.last_token_usage.total_tokens // 0' 2>/dev/null)"
ctx_window="$(printf '%s' "$token_line" | jq -r '.payload.info.model_context_window // 0' 2>/dev/null)"
ctx_pct=0
if [ "${ctx_window:-0}" -gt 0 ] && [ "${ctx_tokens:-0}" -ge 0 ]; then
  ctx_pct=$(((ctx_tokens * 100 + ctx_window / 2) / ctx_window))
fi
ctx_pct="$(clamp_pct "$ctx_pct")"

total_input_tokens="$(printf '%s' "$token_line" | jq -r '.payload.info.total_token_usage.input_tokens // 0' 2>/dev/null)"
total_output_tokens="$(printf '%s' "$token_line" | jq -r '.payload.info.total_token_usage.output_tokens // 0' 2>/dev/null)"
five_hour="$(printf '%s' "$token_line" | jq -r '.payload.rate_limits.primary.used_percent // empty' 2>/dev/null)"
seven_day="$(printf '%s' "$token_line" | jq -r '.payload.rate_limits.secondary.used_percent // empty' 2>/dev/null)"
five_hour_resets_at="$(printf '%s' "$token_line" | jq -r '.payload.rate_limits.primary.resets_at // empty' 2>/dev/null)"
seven_day_resets_at="$(printf '%s' "$token_line" | jq -r '.payload.rate_limits.secondary.resets_at // empty' 2>/dev/null)"

line1() {
  context_bar "$ctx_pct" "$ctx_window" "$ctx_tokens"
  if [ "${total_input_tokens:-0}" -gt 0 ] || [ "${total_output_tokens:-0}" -gt 0 ]; then
    printf '  '
    printf '⬇️ '
    segment "fg=$BLUE,$bold_style" "$(fmt_tok "$total_input_tokens")"
    printf ' '
    printf '⬆️ '
    segment "fg=$MAGENTA,$bold_style" "$(fmt_tok "$total_output_tokens")"
  fi
}

line2() {
  segment "fg=$CYAN,$bold_style" "$(format_model "$model_slug")"
  if [ -n "$effort" ]; then
    segment "fg=$GREY" " · "
    effort_label "$effort" || true
  fi
  printf ' '
  segment "fg=$(c256 238)" "∷"
  printf ' '
  segment "fg=$PINK,$bold_style" "$(format_cwd "$raw_cwd")"
  if git -C "$raw_cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '  '
    git_segment "$raw_cwd"
  fi
}

line3() {
  rate_line "5h" "$five_hour" "$five_hour_resets_at"
}

line4() {
  rate_line "7d" "$seven_day" "$seven_day_resets_at"
}

case "${1:---all}" in
  --line)
    case "${2:-}" in
      1) line1 ;;
      2) line2 ;;
      3) line3 ;;
      4) line4 ;;
      *) exit 2 ;;
    esac
    ;;
  --line=1) line1 ;;
  --line=2) line2 ;;
  --line=3) line3 ;;
  --line=4) line4 ;;
  --all)
    line1
    printf '\n'
    line2
    printf '\n'
    line3
    printf '\n'
    line4
    ;;
  *) exit 2 ;;
esac
