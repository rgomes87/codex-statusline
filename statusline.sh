#!/bin/bash
input=$(cat)

# ── ANSI helpers ────────────────────────────────────────────────────────────
reset='\033[0m'
bold='\033[1m'
dim='\033[2m'

# 256-colour foreground
c()  { printf '\033[38;5;%sm' "$1"; }
# 256-colour background
bg() { printf '\033[48;5;%sm' "$1"; }

# Palette
CYAN=$(c 51)
MAGENTA=$(c 213)
WHITE=$(c 255)
YELLOW=$(c 220)
ORANGE=$(c 208)
RED=$(c 196)
GREEN=$(c 82)
BLUE=$(c 75)
GREY=$(c 240)
SILVER=$(c 250)
GOLD=$(c 214)
PURPLE=$(c 135)

# ── Visible-length helper (strips ANSI escape codes) ─────────────────────────

# ── Working directory ─────────────────────────────────────────────────────────
RAW_CWD=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
# Fall back to shell cwd if JSON gave us nothing
[ -z "$RAW_CWD" ] && RAW_CWD=$(pwd)

# Replace $HOME prefix with ~
SHORT_CWD="${RAW_CWD/#$HOME/~}"

# Truncate to last 2 path components if more than 2 deep (after ~ substitution)
# Count components by stripping leading ~ or /
_stripped="${SHORT_CWD#\~}"   # remove leading ~
_stripped="${_stripped#/}"    # remove leading /
_count=$(echo "$_stripped" | awk -F'/' '{print NF}')
if [ "$_count" -gt 2 ]; then
  _last2=$(echo "$_stripped" | awk -F'/' '{print $(NF-1)"/"$NF}')
  SHORT_CWD="…/${_last2}"
fi

# Directory: warm pink/rose — visually distinct from branch
CWD_SEG=$(printf "${bold}$(c 204)${SHORT_CWD}${reset}")

# ── Git branch + status ──────────────────────────────────────────────────────
GIT_BRANCH=$(git --git-dir="$RAW_CWD/.git" --work-tree="$RAW_CWD" branch --show-current 2>/dev/null)
GIT_SEG=""
if [ -n "$GIT_BRANCH" ]; then
  GIT_SEG=$(printf "🌿 ${bold}$(c 117)${GIT_BRANCH}${reset}")

  # Dirty: count staged + unstaged changed files (not untracked)
  DIRTY=$(git --git-dir="$RAW_CWD/.git" --work-tree="$RAW_CWD" status --porcelain 2>/dev/null | grep -c '^[^?]')
  if [ "$DIRTY" -gt 0 ]; then
    GIT_SEG="${GIT_SEG} ${bold}$(c 208)✎${DIRTY}${reset}"
  fi

  # Ahead/behind remote
  UPSTREAM=$(git --git-dir="$RAW_CWD/.git" --work-tree="$RAW_CWD" rev-parse --abbrev-ref "@{u}" 2>/dev/null)
  if [ -n "$UPSTREAM" ]; then
    AHEAD=$(git --git-dir="$RAW_CWD/.git" --work-tree="$RAW_CWD" rev-list --count "@{u}..HEAD" 2>/dev/null)
    BEHIND=$(git --git-dir="$RAW_CWD/.git" --work-tree="$RAW_CWD" rev-list --count "HEAD..@{u}" 2>/dev/null)
    [ "${AHEAD:-0}" -gt 0 ]  && GIT_SEG="${GIT_SEG} ${bold}$(c 82)↑${AHEAD}${reset}"
    [ "${BEHIND:-0}" -gt 0 ] && GIT_SEG="${GIT_SEG} ${bold}$(c 196)↓${BEHIND}${reset}"
  fi
fi

# ── Model name ───────────────────────────────────────────────────────────────
MODEL=$(echo "$input" | jq -r '.model.display_name')
EFFORT=$(echo "$input" | jq -r '.effort.level // empty' 2>/dev/null)
[ -z "$EFFORT" ] && EFFORT=$(jq -r '.effortLevel // empty' ~/.claude/settings.json 2>/dev/null)

# Effort label colour — matches /effort UI colours:
#   low    → yellow/amber  (c 220)
#   medium → green         (c 82)
#   high   → periwinkle    (c 105)
#   xhigh  → purple/violet (c 141)
#   max    → per-character rainbow
case "$EFFORT" in
  low)    EFFORT_COL=$(c 220)  ;;
  medium) EFFORT_COL=$(c 82)   ;;
  high)   EFFORT_COL=$(c 105)  ;;
  xhigh)  EFFORT_COL=$(c 141)  ;;
  max)    EFFORT_COL=""       ;;
  *)      EFFORT_COL=$SILVER  ;;
esac

if [ "$EFFORT" = "max" ]; then
  EFFORT_LABEL="${bold}$(c 196)m${reset}${bold}$(c 226)a${reset}${bold}$(c 46)x${reset}"
elif [ -n "$EFFORT_COL" ] && [ -n "$EFFORT" ]; then
  EFFORT_LABEL="${bold}${EFFORT_COL}${EFFORT}${reset}"
else
  EFFORT_LABEL=""
fi

# Model colour: Haiku → green, Sonnet → cyan, Opus → red
case "$MODEL" in
  *[Hh]aiku*)  MODEL_COL=$GREEN ;;
  *[Ss]onnet*) MODEL_COL=$ORANGE ;;
  *[Oo]pus*)   MODEL_COL=$RED   ;;
  *)            MODEL_COL=$CYAN  ;;
esac

if [ -n "$EFFORT" ]; then
  MODEL_COLORED=$(printf "${bold}${MODEL_COL}${MODEL}${reset}${GREY} · ${reset}${EFFORT_LABEL}")
else
  MODEL_COLORED=$(printf "${bold}${MODEL_COL}${MODEL}${reset}")
fi

# ── Token reads (needed before context bar) ──────────────────────────────────
TOT_IN=$(echo "$input"  | jq -r '.context_window.total_input_tokens  // 0')
TOT_OUT=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')

fmt_tok() {
  python3 -c "
n=float('$1')
print(f'{int(round(n/1000))}k' if n >= 1000 else str(int(n)))
" 2>/dev/null || echo "$1"
}

# ── Context bar ─────────────────────────────────────────────────────────────
PCT_RAW=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
PCT=$(printf '%.0f' "$PCT_RAW")

BAR_WIDTH=10
FILLED=$((PCT * BAR_WIDTH / 100))

# Max window: try JSON field first, fall back to 200K (all current Claude models)
MAX_WIN=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
[ -z "$MAX_WIN" ] || [ "$MAX_WIN" -eq 0 ] 2>/dev/null && MAX_WIN=200000

# Actual context tokens in use (used % × window size)
CTX_TOKS=$(python3 -c "print($PCT_RAW * $MAX_WIN / 100)" 2>/dev/null || echo 0)

# 100K separator: cell boundary index (separator appears after this cell)
SEP_CELL=$(python3 -c "print(int(100000 / $MAX_WIN * $BAR_WIDTH))" 2>/dev/null || echo 5)
SHOW_SEP=0
[ "$SEP_CELL" -gt 0 ] && [ "$SEP_CELL" -lt "$BAR_WIDTH" ] && SHOW_SEP=1

# Separator color: white when under 100K, amber once past
if [ "$CTX_TOKS" -ge 100000 ]; then
  SEP_COL=$(c 208)
else
  SEP_COL=$(c 255)
fi

# Smooth 10-step green→red gradient — one unique colour per cell:
#   cell  1  →  0–10%   pure green      (c 46,  #00ff00)
#   cell  2  → 10–20%   yellow-green    (c 82,  #5fff00)
#   cell  3  → 20–30%   chartreuse      (c 118, #87ff00)
#   cell  4  → 30–40%   light lime      (c 154, #afff00)
#   cell  5  → 40–50%   yellow-lime     (c 190, #d7ff00)
#   cell  6  → 50–60%   pure yellow     (c 226, #ffff00)
#   cell  7  → 60–70%   gold            (c 220, #ffd700)
#   cell  8  → 70–80%   amber           (c 214, #ffaf00)
#   cell  9  → 80–90%   orange-red      (c 202, #ff5f00)  ← almost red
#   cell 10  → 90–100%  pure red        (c 196, #ff0000)  ← complete red
BAR_COLORED=""
for i in $(seq 1 $BAR_WIDTH); do
  # Inject 100K separator before cell SEP_CELL+1 (i.e., after cell SEP_CELL)
  if [ "$SHOW_SEP" -eq 1 ] && [ "$i" -eq "$((SEP_CELL + 1))" ]; then
    BAR_COLORED="${BAR_COLORED}${bold}${SEP_COL}|${reset}"
  fi
  if [ "$i" -le "$FILLED" ]; then
    case "$i" in
      1)  COL=$(c 46)  ;;
      2)  COL=$(c 82)  ;;
      3)  COL=$(c 118) ;;
      4)  COL=$(c 154) ;;
      5)  COL=$(c 190) ;;
      6)  COL=$(c 226) ;;
      7)  COL=$(c 220) ;;
      8)  COL=$(c 214) ;;
      9)  COL=$(c 202) ;;
      10) COL=$(c 196) ;;
    esac
    BAR_COLORED="${BAR_COLORED}${COL}${bold}■${reset}"
  else
    BAR_COLORED="${BAR_COLORED}${GREY}□${reset}"
  fi
done

# Percentage colour tracks the last filled cell's gradient colour
case "$FILLED" in
  0)  PCT_COL=$(c 46)  ;;
  1)  PCT_COL=$(c 46)  ;;
  2)  PCT_COL=$(c 82)  ;;
  3)  PCT_COL=$(c 118) ;;
  4)  PCT_COL=$(c 154) ;;
  5)  PCT_COL=$(c 190) ;;
  6)  PCT_COL=$(c 226) ;;
  7)  PCT_COL=$(c 220) ;;
  8)  PCT_COL=$(c 214) ;;
  9)  PCT_COL=$(c 202) ;;
  10) PCT_COL=$(c 196) ;;
  *)  PCT_COL=$(c 46)  ;;
esac
CTX_TOK_FMT=$(fmt_tok "$CTX_TOKS")
PCT_COLORED=$(printf "${bold}${PCT_COL}${CTX_TOK_FMT} - %d%%${reset}" "$PCT")

# ── Rate limits ──────────────────────────────────────────────────────────────
FIVE_H=$(echo "$input"  | jq -r '.rate_limits.five_hour.used_percentage  // empty')
SEVEN_D=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage  // empty')

# Mini bar helper: draws a 10-cell filled/empty bar
rate_bar() {
  local pct="$1"
  local width=10
  local filled=$((pct * width / 100))
  local bar=""
  local col
  if   [ "$pct" -lt 50 ]; then col=$(c 82)    # green
  elif [ "$pct" -lt 75 ]; then col=$(c 220)   # yellow
  else                          col=$(c 208)   # amber/orange
  fi
  for i in $(seq 1 $width); do
    if [ "$i" -le "$filled" ]; then
      bar="${bar}${col}▪${reset}"
    else
      bar="${bar}${GREY}·${reset}"
    fi
  done
  printf "%s" "$bar"
}

RATE_STR=""
if [ -n "$FIVE_H" ]; then
  FH_USED=$(printf '%.0f' "$FIVE_H")
  FH_INT=$((100 - FH_USED))
  FH_FILLED=$((FH_INT * 10 / 100))
  # Inverted gradient: cell 1=red (danger) … cell 10=green (healthy)
  # Uniform colour across all filled cells; 10-step gradient keyed to fill level
  case "$FH_FILLED" in
    10) FH_BAR_COL=$(c 46)  ;;
    9)  FH_BAR_COL=$(c 82)  ;;
    8)  FH_BAR_COL=$(c 118) ;;
    7)  FH_BAR_COL=$(c 154) ;;
    6)  FH_BAR_COL=$(c 190) ;;
    5)  FH_BAR_COL=$(c 226) ;;
    4)  FH_BAR_COL=$(c 220) ;;
    3)  FH_BAR_COL=$(c 214) ;;
    2)  FH_BAR_COL=$(c 202) ;;
    *)  FH_BAR_COL=$(c 196) ;;
  esac
  FH_BAR=""
  for _i in $(seq 1 10); do
    if [ "$_i" -le "$FH_FILLED" ]; then
      FH_BAR="${FH_BAR}${FH_BAR_COL}▮${reset}"
    else
      FH_BAR="${FH_BAR}${GREY}▯${reset}"
    fi
  done
  # Icon/label colour tracks last filled cell
  case "$FH_FILLED" in
    0)  FH_COL=$(c 196) ;;
    1)  FH_COL=$(c 196) ;;
    2)  FH_COL=$(c 202) ;;
    3)  FH_COL=$(c 208) ;;
    4)  FH_COL=$(c 214) ;;
    5)  FH_COL=$(c 220) ;;
    6)  FH_COL=$(c 226) ;;
    7)  FH_COL=$(c 190) ;;
    8)  FH_COL=$(c 154) ;;
    9)  FH_COL=$(c 82)  ;;
    10) FH_COL=$(c 46)  ;;
    *)  FH_COL=$(c 46)  ;;
  esac
  if   [ "$FH_INT" -gt 75 ]; then FH_SYM="🟢"
  elif [ "$FH_INT" -gt 50 ]; then FH_SYM="🟡"
  elif [ "$FH_INT" -gt 25 ]; then FH_SYM="🟠"
  elif [ "$FH_INT" -gt 0  ]; then FH_SYM="🔴"
  else                             FH_SYM="⭕"
  fi
  FH_ICON="$FH_SYM"
  FH_SEG=$(printf "${FH_ICON} ${bold}$(c 250)5h${reset} ${FH_BAR} ${bold}${FH_COL}${FH_INT}%%${reset}")
fi

# ── Reset countdowns ─────────────────────────────────────────────────────────
MUTED_CYAN=$(c 73)

fmt_reset() {
  local ts="$1"
  python3 -c "
import time
diff = int($ts) - int(time.time())
if diff > 0:
    d = diff // 86400
    h = (diff % 86400) // 3600
    m = (diff % 3600) // 60
    s = diff % 60
    if d > 0:
        print(f'{d}d {h}h {m}m {s}s')
    else:
        print(f'   {h}h {m}m {s}s')
" 2>/dev/null
}

# Attach 5h reset inline to 5h segment
FIVE_H_RESET=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
RATE_STR=""
if [ -n "$FH_SEG" ]; then
  RATE_STR="$FH_SEG"
  if [ -n "$FIVE_H_RESET" ]; then
    R=$(fmt_reset "$FIVE_H_RESET")
    RESET_TIME=$(date -r "$FIVE_H_RESET" '+%H:%M' 2>/dev/null)
    if [ -n "$R" ]; then
      if [ -n "$RESET_TIME" ]; then
        RATE_STR="${RATE_STR} ⏱️${bold}${MUTED_CYAN}${R}${reset} ${GREY}@ ${RESET_TIME}${reset}"
      else
        RATE_STR="${RATE_STR} ⏱️${bold}${MUTED_CYAN}${R}${reset}"
      fi
    fi
  fi
fi

# Build 7d segment and attach its reset inline
SEVEN_D_RESET=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
if [ -n "$SEVEN_D" ]; then
  SD_USED=$(printf '%.0f' "$SEVEN_D")
  SD_INT=$((100 - SD_USED))
  SD_FILLED=$((SD_INT * 10 / 100))
  # Inverted gradient: cell 1=red (danger) … cell 10=green (healthy)
  # Uniform colour across all filled cells; 10-step gradient keyed to fill level
  case "$SD_FILLED" in
    10) SD_BAR_COL=$(c 46)  ;;
    9)  SD_BAR_COL=$(c 82)  ;;
    8)  SD_BAR_COL=$(c 118) ;;
    7)  SD_BAR_COL=$(c 154) ;;
    6)  SD_BAR_COL=$(c 190) ;;
    5)  SD_BAR_COL=$(c 226) ;;
    4)  SD_BAR_COL=$(c 220) ;;
    3)  SD_BAR_COL=$(c 214) ;;
    2)  SD_BAR_COL=$(c 202) ;;
    *)  SD_BAR_COL=$(c 196) ;;
  esac
  SD_BAR=""
  for _i in $(seq 1 10); do
    if [ "$_i" -le "$SD_FILLED" ]; then
      SD_BAR="${SD_BAR}${SD_BAR_COL}▮${reset}"
    else
      SD_BAR="${SD_BAR}${GREY}▯${reset}"
    fi
  done
  # Icon/label colour tracks last filled cell
  case "$SD_FILLED" in
    0)  SD_COL=$(c 196) ;;
    1)  SD_COL=$(c 196) ;;
    2)  SD_COL=$(c 202) ;;
    3)  SD_COL=$(c 208) ;;
    4)  SD_COL=$(c 214) ;;
    5)  SD_COL=$(c 220) ;;
    6)  SD_COL=$(c 226) ;;
    7)  SD_COL=$(c 190) ;;
    8)  SD_COL=$(c 154) ;;
    9)  SD_COL=$(c 82)  ;;
    10) SD_COL=$(c 46)  ;;
    *)  SD_COL=$(c 46)  ;;
  esac
  if   [ "$SD_INT" -gt 75 ]; then SD_SYM="🟢"
  elif [ "$SD_INT" -gt 50 ]; then SD_SYM="🟡"
  elif [ "$SD_INT" -gt 25 ]; then SD_SYM="🟠"
  elif [ "$SD_INT" -gt 0  ]; then SD_SYM="🔴"
  else                             SD_SYM="⭕"
  fi
  SD_ICON="$SD_SYM"
  SD_SEG=$(printf "${SD_ICON} ${bold}$(c 250)7d${reset} ${SD_BAR} ${bold}${SD_COL}${SD_INT}%%${reset}")
  if [ -n "$SEVEN_D_RESET" ]; then
    R=$(fmt_reset "$SEVEN_D_RESET")
    RESET_TIME_7D=$(python3 -c "
import time, datetime
ts = int($SEVEN_D_RESET)
reset_date = datetime.date.fromtimestamp(ts)
today = datetime.date.today()
delta = (reset_date - today).days
if delta == 0:
    label = 'today'
elif delta == 1:
    label = 'tomorrow'
else:
    label = reset_date.strftime('%a')
print(datetime.datetime.fromtimestamp(ts).strftime('%H:%M') + ' ' + label)
" 2>/dev/null)
    if [ -n "$R" ]; then
      if [ -n "$RESET_TIME_7D" ]; then
        SD_SEG="${SD_SEG} ⏱️${bold}${MUTED_CYAN}${R}${reset} ${GREY}@ ${RESET_TIME_7D}${reset}"
      else
        SD_SEG="${SD_SEG} ⏱️${bold}${MUTED_CYAN}${R}${reset}"
      fi
    fi
  fi
fi

# ── Token counts ─────────────────────────────────────────────────────────────
TOK_SEG=""
if [ "$TOT_IN" -gt 0 ] || [ "$TOT_OUT" -gt 0 ]; then
  IN_FMT=$(fmt_tok "$TOT_IN")
  OUT_FMT=$(fmt_tok "$TOT_OUT")
  # ⬇ in / ⬆ out as directional icons to distinguish at a glance
  TOK_SEG=$(printf "⬇️ ${bold}${BLUE}${IN_FMT}${reset} ⬆️ ${bold}${MAGENTA}${OUT_FMT}${reset}")
fi

# ── Separators ───────────────────────────────────────────────────────────────
SEP=$(printf "${GREY} │ ${reset}")
# Chevron-style separator used between model·effort and location on line 2
SEP2=$(printf " $(c 238)∷${reset} ")

# ── Assemble line bodies (no labels) ─────────────────────────────────────────
# Line 1 — context bar + token counts
# Bracket colour reflects current effort bucket (matches bar + percentage)
LINE1="${bold}${PCT_COL}❮${reset}${BAR_COLORED}${bold}${PCT_COL}❯${reset} ${PCT_COLORED}"
[ -n "$TOK_SEG" ] && LINE1="${LINE1}  ${TOK_SEG}"

# Line 2 — model · effort  ⟫  directory  ⎇ branch
LOC_SEG="${CWD_SEG}"
[ -n "$GIT_SEG" ] && LOC_SEG="${LOC_SEG}  ${GIT_SEG}"
LINE2="${MODEL_COLORED}${SEP2}${LOC_SEG}"

# Line 3 — 5h rate limit
LINE3="${RATE_STR}"

# Line 4 — 7d rate limit
LINE4="${SD_SEG}"

if [ -n "$LINE3" ] && [ -n "$LINE4" ]; then
  printf "%b\n%b\n%b\n%b\n" "$LINE1" "$LINE2" "$LINE3" "$LINE4"
elif [ -n "$LINE3" ]; then
  printf "%b\n%b\n%b\n" "$LINE1" "$LINE2" "$LINE3"
else
  printf "%b\n%b\n" "$LINE1" "$LINE2"
fi
