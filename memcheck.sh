#!/data/data/com.termux/files/usr/bin/bash
# non-Termux: #!/usr/bin/env bash
LC_ALL=C

INTERVAL="${1:-1}"

# ── ANSI Colors ──────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"

BG_BLACK="\033[40m"
FG_WHITE="\033[97m"
FG_GRAY="\033[90m"
FG_CYAN="\033[96m"
FG_GREEN="\033[92m"
FG_YELLOW="\033[93m"
FG_RED="\033[91m"
FG_BLUE="\033[94m"
FG_MAGENTA="\033[95m"

# ── Box drawing chars ─────────────────────────────────────
TL="╔"; TR="╗"; BL="╚"; BR="╝"
HL="═"; VL="║"
ML="╠"; MR="╣"
TT="╦"; BT="╩"; CT="╬"

# ── Config ────────────────────────────────────────────────
BAR_WIDTH=20
TOTAL_WIDTH=52   # inner width

# ── CPU sampling ─────────────────────────────────────────
read_cpu_stat() {
  awk '/^cpu /{
    u=$2;n=$3;s=$4;i=$5;w=$6;r=$7;si=$8;st=$9
    print u+n+s+i+w+r+si+st, i
    exit
  }' /proc/stat
}
read -r PREV_TOTAL PREV_IDLE <<<"$(read_cpu_stat)"

get_cpu_pct() {
  read -r CT CI <<<"$(read_cpu_stat)"
  DT=$((CT - PREV_TOTAL)); DI=$((CI - PREV_IDLE))
  PREV_TOTAL="$CT"; PREV_IDLE="$CI"
  [ "$DT" -le 0 ] && echo "0.0" && return
  awk -v dt="$DT" -v di="$DI" 'BEGIN{printf "%.1f",((dt-di)/dt)*100}'
}

# ── RAM ──────────────────────────────────────────────────
get_mem() {
  awk '
    /MemTotal:/     {t=$2}
    /MemFree:/      {f=$2}
    /Buffers:/      {b=$2}
    /^Cached:/      {c=$2}
    /SReclaimable:/ {sr=$2}
    /Shmem:/        {sh=$2}
    END{
      u=t-f-b-c-sr+sh; if(u<0)u=0
      printf "%.1f %.1f %.1f", u/1048576, t/1048576, (t>0)?u/t*100:0
    }
  ' /proc/meminfo
}

# ── Storage ──────────────────────────────────────────────
get_storage() {
  local mp="/"
  for p in /data /sdcard /storage/emulated/0; do
    df "$p" &>/dev/null && mp="$p" && break
  done
  df -k "$mp" 2>/dev/null | awk 'NR==2{
    printf "%.1f %.1f %.1f", $3/1048576, $2/1048576, ($2>0)?$3/$2*100:0
  }'
}

# ── Progress bar ─────────────────────────────────────────
make_bar() {
  local pct="$1" width="$2"
  local filled=$(awk -v p="$pct" -v w="$width" 'BEGIN{printf "%d", p/100*w}')
  local empty=$((width - filled))
  local bar=""

  # Color based on pct
  local color
  if   awk -v p="$pct" 'BEGIN{exit !(p<50)}'; then color="$FG_GREEN"
  elif awk -v p="$pct" 'BEGIN{exit !(p<80)}'; then color="$FG_YELLOW"
  else color="$FG_RED"
  fi

  bar+="${color}"
  for ((i=0; i<filled; i++)); do bar+="█"; done
  bar+="${DIM}${FG_GRAY}"
  for ((i=0; i<empty; i++));  do bar+="░"; done
  bar+="${RESET}"
  echo -e "$bar"
}

# ── Print a full-width horizontal divider ─────────────────
print_div() {
  echo -e "${FG_CYAN}${ML}$(printf '═%.0s' $(seq 1 $TOTAL_WIDTH))${MR}${RESET}"
}

print_top() {
  echo -e "${FG_CYAN}${TL}$(printf '═%.0s' $(seq 1 $TOTAL_WIDTH))${TR}${RESET}"
}

print_bot() {
  echo -e "${FG_CYAN}${BL}$(printf '═%.0s' $(seq 1 $TOTAL_WIDTH))${BR}${RESET}"
}

print_row() {
  # pad content to TOTAL_WIDTH
  local content="$1"
  local visible
  visible=$(echo -e "$content" | sed 's/\x1B\[[0-9;]*[mK]//g')
  local vlen=${#visible}
  local pad=$((TOTAL_WIDTH - vlen))
  printf "${FG_CYAN}${VL}${RESET} "
  echo -ne "$content"
  printf "%*s" "$((pad - 1))" ""
  echo -e " ${FG_CYAN}${VL}${RESET}"
}

# ── Uptime ────────────────────────────────────────────────
get_uptime() {
  awk '{
    s=int($1); h=int(s/3600); m=int((s%3600)/60); sc=s%60
    printf "%02dh %02dm %02ds", h, m, sc
  }' /proc/uptime
}

# ── Hide cursor ───────────────────────────────────────────
tput civis 2>/dev/null
trap 'tput cnorm 2>/dev/null; exit' INT TERM

# ── Main loop ─────────────────────────────────────────────
while true; do
  CPU_PCT="$(get_cpu_pct)"
  read -r MEM_U MEM_T MEM_P <<<"$(get_mem)"
  read -r STG_U STG_T STG_P <<<"$(get_storage)"
  UPTIME="$(get_uptime)"
  TIME_NOW="$(date '+%H:%M:%S')"

  # Color per resource
  cpu_color="$FG_CYAN"
  mem_color="$FG_MAGENTA"
  stg_color="$FG_BLUE"

  clear
  echo ""
  print_top

  # Title
  print_row "${BOLD}${FG_WHITE}  ⚡ SYSTEM MONITOR${RESET}${FG_GRAY}                        ${FG_WHITE}${TIME_NOW}${RESET}"
  print_row "${FG_GRAY}  Uptime: ${FG_WHITE}${UPTIME}${RESET}"

  print_div

  # CPU
  CPU_BAR="$(make_bar "$CPU_PCT" $BAR_WIDTH)"
  print_row "${cpu_color}${BOLD}  CPU   ${RESET}  ${CPU_BAR}  ${BOLD}${CPU_PCT}%${RESET}"

  # RAM
  MEM_BAR="$(make_bar "$MEM_P" $BAR_WIDTH)"
  print_row "${mem_color}${BOLD}  RAM   ${RESET}  ${MEM_BAR}  ${BOLD}${MEM_U}/${MEM_T} GB${RESET}"

  # Storage
  STG_BAR="$(make_bar "$STG_P" $BAR_WIDTH)"
  print_row "${stg_color}${BOLD}  DISK  ${RESET}  ${STG_BAR}  ${BOLD}${STG_U}/${STG_T} GB${RESET}"

  print_div

  # Footer
  print_row "${FG_GRAY}  Refresh: ${FG_WHITE}${INTERVAL}s${FG_GRAY}   Press ${FG_WHITE}Ctrl+C${FG_GRAY} to exit${RESET}"

  print_bot
  echo ""

  sleep "$INTERVAL"
done
