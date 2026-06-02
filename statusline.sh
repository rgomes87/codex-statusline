#!/bin/bash
input=$(cat)

# ── ANSI helpers ────────────────────────────────────────────────────────────
reset='\033[0m'
dim='\033[2m'

# 256-colour foreground / background
c()  { printf '\033[38;5;%sm' "$1"; }
bg() { printf '\033[48;5;%sm' "$1"; }

# Palette
CYAN=$(c 51)
ORANGE=$(c 208)
RED=$(c 196)
GREEN=$(c 82)
GREY=$(c 240)
SILVER=$(c 250)
GOLD=$(c 214)

# ── Visible-length helper (strips ANSI escape codes) ─────────────────────────

# ── Parse all JSON fields in one jq call ─────────────────────────────────────
eval "$(echo "$input" | jq -r '
  "RAW_CWD="        + (.workspace.current_dir // .cwd // "" | @sh),
  "MODEL="          + (.model.display_name // "" | @sh),
  "EFFORT="         + (.effort.level // "" | @sh),
  "PCT_RAW="        + (.context_window.used_percentage // 0 | tostring),
  "MAX_WIN="        + (.context_window.context_window_size // 200000 | tostring),
  "FIVE_H="         + (.rate_limits.five_hour.used_percentage // "" | tostring),
  "SEVEN_D="        + (.rate_limits.seven_day.used_percentage // "" | tostring),
  "FIVE_H_RESET="   + (.rate_limits.five_hour.resets_at // "" | tostring),
  "SEVEN_D_RESET="  + (.rate_limits.seven_day.resets_at // "" | tostring),
  "CACHE_CREATE="   + (.context_window.current_usage.cache_creation_input_tokens // 0 | tostring),
  "CACHE_READ="     + (.context_window.current_usage.cache_read_input_tokens // 0 | tostring),
  "TRANSCRIPT_PATH="+ (.transcript_path // "" | @sh)
' 2>/dev/null)"

# ── Working directory ─────────────────────────────────────────────────────────
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
CWD_SEG=$(printf "$(c 204)${SHORT_CWD}${reset}")

# ── Git branch + status ──────────────────────────────────────────────────────
GIT_BRANCH=$(git --git-dir="$RAW_CWD/.git" --work-tree="$RAW_CWD" branch --show-current 2>/dev/null)
GIT_SEG=""
if [ -n "$GIT_BRANCH" ]; then
  GIT_SEG=$(printf "🌿 $(c 117)${GIT_BRANCH}${reset}")

  # Staged vs unstaged (separate counts, not combined)
  STAGED=$(git --git-dir="$RAW_CWD/.git" --work-tree="$RAW_CWD" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
  UNSTAGED=$(git --git-dir="$RAW_CWD/.git" --work-tree="$RAW_CWD" diff --name-only 2>/dev/null | wc -l | tr -d ' ')
  UNTRACKED=$(git --git-dir="$RAW_CWD/.git" --work-tree="$RAW_CWD" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
  [ "${STAGED:-0}" -gt 0 ]    && GIT_SEG="${GIT_SEG} $(c 82)⊕${STAGED}${reset}"
  [ "${UNSTAGED:-0}" -gt 0 ]  && GIT_SEG="${GIT_SEG} $(c 208)✎${UNSTAGED}${reset}"
  [ "${UNTRACKED:-0}" -gt 0 ] && GIT_SEG="${GIT_SEG} ${GREY}?${UNTRACKED}${reset}"

  # Ahead/behind remote
  UPSTREAM=$(git --git-dir="$RAW_CWD/.git" --work-tree="$RAW_CWD" rev-parse --abbrev-ref "@{u}" 2>/dev/null)
  if [ -n "$UPSTREAM" ]; then
    AHEAD=$(git --git-dir="$RAW_CWD/.git" --work-tree="$RAW_CWD" rev-list --count "@{u}..HEAD" 2>/dev/null)
    BEHIND=$(git --git-dir="$RAW_CWD/.git" --work-tree="$RAW_CWD" rev-list --count "HEAD..@{u}" 2>/dev/null)
    [ "${AHEAD:-0}" -gt 0 ]  && GIT_SEG="${GIT_SEG} $(c 82)↑${AHEAD}${reset}"
    [ "${BEHIND:-0}" -gt 0 ] && GIT_SEG="${GIT_SEG} $(c 196)↓${BEHIND}${reset}"
  fi
fi

# ── Model name ───────────────────────────────────────────────────────────────
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
  EFFORT_LABEL="$(c 196)m${reset}$(c 226)a${reset}$(c 46)x${reset}"
elif [ -n "$EFFORT_COL" ] && [ -n "$EFFORT" ]; then
  EFFORT_LABEL="${EFFORT_COL}${EFFORT}${reset}"
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
  MODEL_COLORED=$(printf "${MODEL_COL}${MODEL}${reset}${GREY} · ${reset}${EFFORT_LABEL}")
else
  MODEL_COLORED=$(printf "${MODEL_COL}${MODEL}${reset}")
fi

# ── Context bar ─────────────────────────────────────────────────────────────
[ -z "$MAX_WIN" ] || [ "$MAX_WIN" -eq 0 ] 2>/dev/null && MAX_WIN=200000
PCT=$(printf '%.0f' "$PCT_RAW")

BAR_WIDTH=10
FILLED=$((PCT * BAR_WIDTH / 100))

# Actual tokens, 100K separator, and autocompact tick — pure bash arithmetic
CTX_TOKS=$(( PCT * MAX_WIN / 100 ))
SEP_CELL=$(( 100000 * BAR_WIDTH / MAX_WIN ))
SHOW_SEP=0
[ "$SEP_CELL" -gt 0 ] && [ "$SEP_CELL" -lt "$BAR_WIDTH" ] && SHOW_SEP=1

AC_THRESH="${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-91}"

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
  # Inject 100K separator before cell SEP_CELL+1
  if [ "$SHOW_SEP" -eq 1 ] && [ "$i" -eq "$((SEP_CELL + 1))" ]; then
    BAR_COLORED="${BAR_COLORED}${SEP_COL}|${reset}"
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
    BAR_COLORED="${BAR_COLORED}${COL}■${reset}"
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
if [ "$CTX_TOKS" -ge 1000 ]; then
  CTX_TOK_FMT="$(( (CTX_TOKS + 500) / 1000 ))k"
else
  CTX_TOK_FMT="$CTX_TOKS"
fi
PCT_COLORED=$(printf "${PCT_COL}${CTX_TOK_FMT} - %d%%${reset}" "$PCT")

# ── Rate limits ──────────────────────────────────────────────────────────────

RATE_STR=""
if [ -n "$FIVE_H" ]; then
  FH_USED=$(printf '%.0f' "$FIVE_H")
  FH_INT=$((100 - FH_USED))
  FH_FILLED=$((FH_INT * 10 / 100))
  case "$FH_FILLED" in
    10) FH_BAR_COL=$(c 46)  ;; 9) FH_BAR_COL=$(c 82)  ;; 8) FH_BAR_COL=$(c 118) ;;
    7)  FH_BAR_COL=$(c 154) ;; 6) FH_BAR_COL=$(c 190) ;; 5) FH_BAR_COL=$(c 226) ;;
    4)  FH_BAR_COL=$(c 220) ;; 3) FH_BAR_COL=$(c 214) ;; 2) FH_BAR_COL=$(c 202) ;;
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
  FH_SEG=$(printf "${FH_ICON} $(c 250)5h${reset} ${FH_BAR} ${FH_COL}${FH_INT}%%${reset}")
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
        print(f'{d}d {h}h {m}m')
    elif h > 0:
        print(f'{h}h {m}m' if m > 0 else f'{h}h')
    else:
        print(f'{m}m {s}s' if m > 0 else f'{s}s')
" 2>/dev/null
}

# Attach 5h reset inline to 5h segment
RATE_STR=""
if [ -n "$FH_SEG" ]; then
  RATE_STR="$FH_SEG"
  if [ -n "$FIVE_H_RESET" ]; then
    R=$(fmt_reset "$FIVE_H_RESET")
    RESET_TIME=$(date -r "$FIVE_H_RESET" '+%H:%M' 2>/dev/null)
    if [ -n "$R" ]; then
      if [ -n "$RESET_TIME" ]; then
        RATE_STR="${RATE_STR} ⏱️ ${MUTED_CYAN}${R}${reset} ${GREY}@ ${RESET_TIME}${reset}"
      else
        RATE_STR="${RATE_STR} ⏱️ ${MUTED_CYAN}${R}${reset}"
      fi
    fi
  fi
fi

# Build 7d segment and attach its reset inline
if [ -n "$SEVEN_D" ]; then
  SD_USED=$(printf '%.0f' "$SEVEN_D")
  SD_INT=$((100 - SD_USED))
  SD_FILLED=$((SD_INT * 10 / 100))
  case "$SD_FILLED" in
    10) SD_BAR_COL=$(c 46)  ;; 9) SD_BAR_COL=$(c 82)  ;; 8) SD_BAR_COL=$(c 118) ;;
    7)  SD_BAR_COL=$(c 154) ;; 6) SD_BAR_COL=$(c 190) ;; 5) SD_BAR_COL=$(c 226) ;;
    4)  SD_BAR_COL=$(c 220) ;; 3) SD_BAR_COL=$(c 214) ;; 2) SD_BAR_COL=$(c 202) ;;
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
  SD_SEG=$(printf "${SD_ICON} $(c 250)7d${reset} ${SD_BAR} ${SD_COL}${SD_INT}%%${reset}")
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
        SD_SEG="${SD_SEG} ⏱️ ${MUTED_CYAN}${R}${reset} ${GREY}@ ${RESET_TIME_7D}${reset}"
      else
        SD_SEG="${SD_SEG} ⏱️ ${MUTED_CYAN}${R}${reset}"
      fi
    fi
  fi
fi

# ── Autocompact marker ────────────────────────────────────────────────────────
AC_REM=$((AC_THRESH - PCT))
if   [ "$AC_REM" -le 0  ]; then AC_COL=$(c 196)
elif [ "$AC_REM" -le 10 ]; then AC_COL=$(c 196)
elif [ "$AC_REM" -le 25 ]; then AC_COL=$(c 220)
else                             AC_COL=$(c 82)
fi
if [ "$AC_REM" -le 0 ]; then
  AC_SEG=$(printf "$(c 51)⚡${reset}${AC_COL}now${reset}")
else
  AC_SEG=$(printf "$(c 51)⚡${reset}${AC_COL}${AC_REM}%%${reset}")
fi

# ── Transcript analysis: tools, compact count, session stats ─────────────────
TOOLS_SEG=""
STATS_SEG=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  _TRES=$(python3 -c "
import json, time, re, sys
from calendar import timegm

R = '\033[0m'
B = '\033[1m'
D = '\033[2m'
def c(n): return f'\033[38;5;{n}m'

def short_name(name):
    if name.startswith('mcp__'):
        parts = name.split('__')
        return parts[-1] if parts[-1] else name
    return name

def tool_color(name):
    if name.startswith('mcp__'): return c(213)
    if name in ('Read','Write','Edit','NotebookEdit'): return c(75)
    if name == 'Bash': return c(202)
    if name in ('WebFetch','WebSearch'): return c(51)
    if name in ('Agent','Plan','Explore','EnterPlanMode','ExitPlanMode',
                'TaskCreate','TaskUpdate','TaskGet','TaskList','TaskOutput','TaskStop'): return c(135)
    return c(250)

try:
    with open('$TRANSCRIPT_PATH') as f:
        lines = [json.loads(l) for l in f if l.strip()]

    # --- Compact count ---
    compact_count = sum(1 for e in lines
                        if e.get('type') == 'system' and e.get('subtype') == 'compact_boundary')

    # --- Tool tracking ---
    uses = {}
    completed = set()
    for item in lines:
        if item.get('type') == 'assistant':
            msg = item.get('message', {})
            content = msg.get('content', [])
            if isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get('type') == 'tool_use':
                        uses[block['id']] = block.get('name', '?')
        elif item.get('type') == 'user':
            msg = item.get('message', {})
            content = msg.get('content', [])
            if isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get('type') == 'tool_result':
                        completed.add(block.get('tool_use_id', ''))

    running = [name for tid, name in uses.items() if tid not in completed]
    done_recent = [uses[tid] for tid in reversed(list(uses.keys())) if tid in completed][:5]

    # Build tool timestamps map: tool_use_id -> (start_ts, end_ts)
    tool_start = {}  # tool_use_id -> timestamp of assistant message containing tool_use
    tool_end   = {}  # tool_use_id -> timestamp of user message containing tool_result
    for item in lines:
        ts_str = item.get('timestamp', '')
        ts = None
        if ts_str:
            m = re.match(r'(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})', ts_str)
            if m:
                g = [int(x) for x in m.groups()]
                ts = timegm((g[0],g[1],g[2],g[3],g[4],g[5],0,0,0))
        if item.get('type') == 'assistant' and ts:
            msg = item.get('message', {})
            for block in (msg.get('content') or []):
                if isinstance(block, dict) and block.get('type') == 'tool_use':
                    tool_start[block['id']] = ts
        elif item.get('type') == 'user' and ts:
            msg = item.get('message', {})
            for block in (msg.get('content') or []):
                if isinstance(block, dict) and block.get('type') == 'tool_result':
                    tool_end[block.get('tool_use_id','')] = ts

    tool_parts = []
    for name in running:
        col = tool_color(name)
        tool_parts.append(f'{c(208)}{B}◐{R} {B}{col}{short_name(name)}{R}')

    done_counts = {}
    done_elapsed = {}  # name -> most recent elapsed seconds
    for name in done_recent:
        done_counts[name] = done_counts.get(name, 0) + 1
    # Find elapsed for the most recent occurrence of each tool
    for tid in reversed(list(uses.keys())):
        if tid in completed:
            name = uses[tid]
            if name not in done_elapsed and tid in tool_start and tid in tool_end:
                done_elapsed[name] = tool_end[tid] - tool_start[tid]

    for name, n in done_counts.items():
        col = tool_color(name)
        suffix = f' {D}×{n}{R}' if n > 1 else ''
        elapsed = done_elapsed.get(name)
        if elapsed is not None and elapsed >= 1:
            elapsed_str = f' {D}{elapsed}s{R}'
        else:
            elapsed_str = ''
        tool_parts.append(f'{c(82)}✓{R} {D}{col}{short_name(name)}{R}{suffix}{elapsed_str}')

    tools_line = '  '.join(tool_parts)

    # --- Session stats ---
    turns = sum(1 for e in lines if e.get('type') == 'assistant')

    timestamps = []
    for e in lines:
        ts_str = e.get('timestamp', '')
        if ts_str:
            m = re.match(r'(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})', ts_str)
            if m:
                g = [int(x) for x in m.groups()]
                timestamps.append(timegm((g[0], g[1], g[2], g[3], g[4], g[5], 0, 0, 0)))

    stats_line = ''
    if turns > 0 and timestamps:
        elapsed = max(0, int(time.time()) - min(timestamps))
        h  = elapsed // 3600
        mi = (elapsed % 3600) // 60
        sr = elapsed % 60
        if h > 0:
            dur = f'{h}h {mi}m' if mi > 0 else f'{h}h'
        else:
            dur = f'{mi}m {sr}s' if mi > 0 else f'{sr}s'
        sep_d      = f'{D} · {R}'
        stats_line = f'🗒  {c(75)}{turns}{R}{sep_d}⏳{c(73)}{dur}{R}'

    print(compact_count)
    print(stats_line)
    print(tools_line)

except Exception:
    print(0)
    print('')
    print('')
" 2>/dev/null)
  COMPACT_NUM=$(printf "%s" "$_TRES" | sed -n '1p')
  STATS_SEG=$(printf "%s" "$_TRES" | sed -n '2p')
  TOOLS_SEG=$(printf "%s" "$_TRES" | sed -n '3p')
fi

COMPACT_SEG=""
if [ -n "$COMPACT_NUM" ] && [ "$COMPACT_NUM" -gt 0 ] 2>/dev/null; then
  COMPACT_SEG=$(printf "🗜  $(c 214)${COMPACT_NUM}${reset}")
fi

# ── Prompt cache ─────────────────────────────────────────────────────────────
CACHE_SEG=""
if [ "${CACHE_CREATE:-0}" -gt 0 ] || [ "${CACHE_READ:-0}" -gt 0 ]; then
  CACHE_SEG=$(python3 -c "
R = '\033[0m'
B = '\033[1m'
D = '\033[2m'
def c(n): return f'\033[38;5;{n}m'

create = int('${CACHE_CREATE:-0}')
read   = int('${CACHE_READ:-0}')

def fmt(n):
    return f'{round(n/1000)}k' if n >= 1000 else str(n)

total = create + read
hit = round(read / total * 100) if total > 0 else 0

if hit >= 80:   hit_col = c(82)
elif hit >= 50: hit_col = c(220)
else:           hit_col = c(196)

sep        = f'{D} · {R}'
read_seg   = f'📖 {c(82)}read {fmt(read)}{R}'
create_seg = f'✏️ {c(75)}wrote {fmt(create)}{R}'
hit_seg    = f'🎯 {hit_col}hit {hit}%{R}'

print(sep.join([read_seg, create_seg, hit_seg]))
" 2>/dev/null)
fi

# ── Config context (line 7) ──────────────────────────────────────────────────
# CLAUDE.md files: walk from cwd up to $HOME
CLAUDEMD_COUNT=0
_dir="$RAW_CWD"
while true; do
  [ -f "$_dir/CLAUDE.md" ] && CLAUDEMD_COUNT=$(( CLAUDEMD_COUNT + 1 ))
  [ "$_dir" = "$HOME" ] && break
  _parent="${_dir%/*}"
  [ "$_parent" = "$_dir" ] && break
  _dir="$_parent"
done

# Hooks, MCPs, rules — from settings.json
_SDATA=$(python3 -c "
import json, os
try:
    with open(os.path.expanduser('~/.claude/settings.json')) as f:
        s = json.load(f)
    # Hooks
    hooks = sum(len(g.get('hooks',[])) for ev in s.get('hooks',{}).values() for g in ev)
    # MCPs: try mcpServers first, fall back to counting unique mcp__ prefixes in allow list
    mcp = len(s.get('mcpServers', {}))
    if mcp == 0:
        prefixes = {r.split('__')[1] for r in s.get('permissions',{}).get('allow',[])
                    if r.startswith('mcp__') and len(r.split('__')) >= 2}
        mcp = len(prefixes)
    rules = len(s.get('permissions',{}).get('allow',[]))
    voice = str(s.get('voice',{}).get('enabled', False)).lower()
    print(hooks, mcp, rules, voice)
except:
    print(0, 0, 0, 'false')
" 2>/dev/null)
HOOK_COUNT=$(echo "$_SDATA" | awk '{print $1}')
MCP_COUNT=$(echo  "$_SDATA" | awk '{print $2}')
RULE_COUNT=$(echo "$_SDATA" | awk '{print $3}')
VOICE_ON=$(echo   "$_SDATA" | awk '{print $4}')

_s7=$(printf "${GREY} · ${reset}")
_MIC_SEG=""
[ "$VOICE_ON" = "true" ] && _MIC_SEG="${_s7}🎙"
CTX7="$(c 204)📋 ${CLAUDEMD_COUNT}${reset}${_s7}$(c 75)🔌 ${MCP_COUNT}${reset}${_s7}$(c 214)🪝 ${HOOK_COUNT}${reset}${_s7}$(c 250)⚙️  ${RULE_COUNT}${reset}${_MIC_SEG}"

# ── Separators ───────────────────────────────────────────────────────────────
SEP=$(printf "${GREY} │ ${reset}")
# Chevron-style separator used between model·effort and location on line 2
SEP2=$(printf " $(c 238)∷${reset} ")

# ── Assemble line bodies (no labels) ─────────────────────────────────────────
# Line 1 — active tools (only when present)
LINE1="${TOOLS_SEG}"

# Line 2 — context bar · compact count · autocompact marker
LINE2="${PCT_COL}❮${reset}${BAR_COLORED}${PCT_COL}❯${reset} ${PCT_COLORED}"
LINE2="${LINE2}  ${AC_SEG}"
[ -n "$COMPACT_SEG" ] && LINE2="${LINE2}  ${COMPACT_SEG}"

# Line 3 — model · effort  ⟫  directory  ⎇ branch
LOC_SEG="${CWD_SEG}"
[ -n "$GIT_SEG" ] && LOC_SEG="${LOC_SEG}  ${GIT_SEG}"
LINE3="${MODEL_COLORED}${SEP2}${LOC_SEG}"

# Line 4 — 5h rate limit
LINE4="${RATE_STR}"

# Line 5 — 7d rate limit
LINE5="${SD_SEG}"

# Line 6 — prompt cache + session stats
LINE6="${CACHE_SEG}"
if [ -n "$STATS_SEG" ] && [ -n "$LINE6" ]; then
  LINE6="${LINE6}$(printf "${GREY} · ${reset}")${STATS_SEG}"
elif [ -n "$STATS_SEG" ]; then
  LINE6="${STATS_SEG}"
fi

# Line 7 — config context: voice · claude.md · mcp · hooks · rules
LINE7="${CTX7}"

# Line 8 — hint
LINE8="$(printf "${dim}$(c 242)/statusline-help${reset}")"

# Build output — only emit lines that have content
OUT=""
for L in "$LINE1" "$LINE2" "$LINE3" "$LINE4" "$LINE5" "$LINE6" "$LINE7" "$LINE8"; do
  [ -n "$L" ] && OUT="${OUT}${L}\n"
done
printf "%b" "$OUT"
