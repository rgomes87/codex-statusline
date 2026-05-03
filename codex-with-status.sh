#!/bin/bash
set -euo pipefail

STATUS_SCRIPT="$HOME/.codex/codex-statusline.sh"
SESSION_NAME="codex-status"
STATUS_LEFT_LENGTH=260
CODEX_STATUS_STYLE="fg=#dce7ff,bg=#0b1021"
CODEX_WINDOW_STATUS_STYLE="fg=#6b7488,bg=#0b1021"
CODEX_WINDOW_STATUS_CURRENT_STYLE="fg=#06131f,bg=#5eead4,bold"

should_wrap() {
  if [ "${CODEX_STATUS_DISABLE:-0}" = "1" ]; then
    return 1
  fi

  if [ "$#" -eq 0 ]; then
    return 0
  fi

  case "$1" in
    exec|review|login|logout|mcp|mcp-server|app-server|app|completion|sandbox|debug|apply|cloud|features|help|-h|--help|-V|--version)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

save_tmux_option() {
  tmux show-option -qv "$1" 2>/dev/null || true
}

restore_tmux_option() {
  local option_name="$1"
  local option_value="$2"

  if [ -n "$option_value" ]; then
    tmux set-option "$option_name" "$option_value" >/dev/null 2>&1 || true
  else
    tmux set-option -u "$option_name" >/dev/null 2>&1 || true
  fi
}

save_tmux_format() {
  tmux show-option -qv "status-format[$1]" 2>/dev/null || true
}

restore_tmux_format() {
  local index="$1"
  local value="$2"

  if [ -n "$value" ]; then
    tmux set-option -g "status-format[$index]" "$value" >/dev/null 2>&1 || true
  else
    tmux set-option -gu "status-format[$index]" >/dev/null 2>&1 || true
  fi
}

configure_tmux_status() {
  tmux set-option status 4 >/dev/null
  tmux set-option status-position bottom >/dev/null
  tmux set-option status-interval 2 >/dev/null
  tmux set-option status-justify left >/dev/null
  tmux set-option status-left-length "$STATUS_LEFT_LENGTH" >/dev/null
  tmux set-option status-style "$CODEX_STATUS_STYLE" >/dev/null
  tmux set-option window-status-style "$CODEX_WINDOW_STATUS_STYLE" >/dev/null
  tmux set-option window-status-current-style "$CODEX_WINDOW_STATUS_CURRENT_STYLE" >/dev/null
  tmux set-option window-status-format "" >/dev/null
  tmux set-option window-status-current-format "" >/dev/null
  tmux set-option window-status-separator "" >/dev/null
  tmux set-option status-left "" >/dev/null
  tmux set-option status-right "" >/dev/null
  tmux set-option -g "status-format[0]" "#(bash $STATUS_SCRIPT --line 1)" >/dev/null
  tmux set-option -g "status-format[1]" "#(bash $STATUS_SCRIPT --line 2)" >/dev/null
  tmux set-option -g "status-format[2]" "#(bash $STATUS_SCRIPT --line 3)" >/dev/null
  tmux set-option -g "status-format[3]" "#(bash $STATUS_SCRIPT --line 4)" >/dev/null
}

configure_existing_tmux_session() {
  local target="$1"

  tmux set-option -t "$target" status 4 >/dev/null
  tmux set-option -t "$target" status-position bottom >/dev/null
  tmux set-option -t "$target" status-interval 2 >/dev/null
  tmux set-option -t "$target" status-justify left >/dev/null
  tmux set-option -t "$target" status-left-length "$STATUS_LEFT_LENGTH" >/dev/null
  tmux set-option -t "$target" status-style "$CODEX_STATUS_STYLE" >/dev/null
  tmux set-option -t "$target" window-status-style "$CODEX_WINDOW_STATUS_STYLE" >/dev/null
  tmux set-option -t "$target" window-status-current-style "$CODEX_WINDOW_STATUS_CURRENT_STYLE" >/dev/null
  tmux set-option -t "$target" window-status-format "" >/dev/null
  tmux set-option -t "$target" window-status-current-format "" >/dev/null
  tmux set-option -t "$target" window-status-separator "" >/dev/null
  tmux set-option -t "$target" status-left "" >/dev/null
  tmux set-option -t "$target" status-right "" >/dev/null
  tmux set-option -t "$target" "status-format[0]" "#(bash $STATUS_SCRIPT --line 1)" >/dev/null
  tmux set-option -t "$target" "status-format[1]" "#(bash $STATUS_SCRIPT --line 2)" >/dev/null
  tmux set-option -t "$target" "status-format[2]" "#(bash $STATUS_SCRIPT --line 3)" >/dev/null
  tmux set-option -t "$target" "status-format[3]" "#(bash $STATUS_SCRIPT --line 4)" >/dev/null
}

restore_tmux_status() {
  restore_tmux_option status "$TMUX_OLD_STATUS"
  restore_tmux_option status-position "$TMUX_OLD_STATUS_POSITION"
  restore_tmux_option status-interval "$TMUX_OLD_STATUS_INTERVAL"
  restore_tmux_option status-justify "$TMUX_OLD_STATUS_JUSTIFY"
  restore_tmux_option status-left-length "$TMUX_OLD_STATUS_LEFT_LENGTH"
  restore_tmux_option status-style "$TMUX_OLD_STATUS_STYLE"
  restore_tmux_option window-status-style "$TMUX_OLD_WINDOW_STATUS_STYLE"
  restore_tmux_option window-status-current-style "$TMUX_OLD_WINDOW_STATUS_CURRENT_STYLE"
  restore_tmux_option window-status-format "$TMUX_OLD_WINDOW_STATUS_FORMAT"
  restore_tmux_option window-status-current-format "$TMUX_OLD_WINDOW_STATUS_CURRENT_FORMAT"
  restore_tmux_option window-status-separator "$TMUX_OLD_WINDOW_STATUS_SEPARATOR"
  restore_tmux_option status-left "$TMUX_OLD_STATUS_LEFT"
  restore_tmux_option status-right "$TMUX_OLD_STATUS_RIGHT"
  restore_tmux_format 0 "$TMUX_OLD_STATUS_FORMAT_0"
  restore_tmux_format 1 "$TMUX_OLD_STATUS_FORMAT_1"
  restore_tmux_format 2 "$TMUX_OLD_STATUS_FORMAT_2"
  restore_tmux_format 3 "$TMUX_OLD_STATUS_FORMAT_3"
}

REAL_CODEX="$(command -v codex)"
[ -n "$REAL_CODEX" ] || {
  echo "codex binary not found" >&2
  exit 127
}

if ! should_wrap "$@"; then
  exec "$REAL_CODEX" "$@"
fi

if ! command -v tmux >/dev/null 2>&1; then
  exec "$REAL_CODEX" "$@"
fi

if [ -n "${TMUX:-}" ]; then
  TMUX_OLD_STATUS="$(save_tmux_option status)"
  TMUX_OLD_STATUS_POSITION="$(save_tmux_option status-position)"
  TMUX_OLD_STATUS_INTERVAL="$(save_tmux_option status-interval)"
  TMUX_OLD_STATUS_JUSTIFY="$(save_tmux_option status-justify)"
  TMUX_OLD_STATUS_LEFT_LENGTH="$(save_tmux_option status-left-length)"
  TMUX_OLD_STATUS_STYLE="$(save_tmux_option status-style)"
  TMUX_OLD_WINDOW_STATUS_STYLE="$(save_tmux_option window-status-style)"
  TMUX_OLD_WINDOW_STATUS_CURRENT_STYLE="$(save_tmux_option window-status-current-style)"
  TMUX_OLD_WINDOW_STATUS_FORMAT="$(save_tmux_option window-status-format)"
  TMUX_OLD_WINDOW_STATUS_CURRENT_FORMAT="$(save_tmux_option window-status-current-format)"
  TMUX_OLD_WINDOW_STATUS_SEPARATOR="$(save_tmux_option window-status-separator)"
  TMUX_OLD_STATUS_LEFT="$(save_tmux_option status-left)"
  TMUX_OLD_STATUS_RIGHT="$(save_tmux_option status-right)"
  TMUX_OLD_STATUS_FORMAT_0="$(save_tmux_format 0)"
  TMUX_OLD_STATUS_FORMAT_1="$(save_tmux_format 1)"
  TMUX_OLD_STATUS_FORMAT_2="$(save_tmux_format 2)"
  TMUX_OLD_STATUS_FORMAT_3="$(save_tmux_format 3)"

  configure_tmux_status
  trap restore_tmux_status EXIT
  "$REAL_CODEX" "$@"
  exit $?
fi

if [ "${CODEX_STATUS_INNER:-0}" = "1" ]; then
  configure_tmux_status
  exec "$REAL_CODEX" "$@"
fi

tmux_cmd="$(printf '%q ' bash "$0" "$@")"
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  configure_existing_tmux_session "$SESSION_NAME"
  exec tmux attach-session -t "$SESSION_NAME"
fi

exec tmux new-session -A -s "$SESSION_NAME" "CODEX_STATUS_INNER=1 $tmux_cmd"
