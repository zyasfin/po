#!/data/data/com.termux/files/usr/bin/bash
###############################################################################
# SETUP SCRIPT — Termux
###############################################################################
set -euo pipefail

# Colors & styles
GREEN='\033[0;32m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

LOGF="/data/data/com.termux/files/home/.setup/setup.log"
START_TS=$(date +%s)
TTY=/dev/tty

info()  { printf "  ${DIM}[INFO]${NC}  %s\n" "$*"; }
warn()  { printf "  ${RED}[WARN]${NC}  %s\n" "$*"; }
log()   { printf "  ${GREEN}[OK]${NC}    %s\n" "$*"; }
step()  { printf "\n  ${GREEN}[%02d]${NC} %s\n" "$1" "$2"; }
ts()    { date '+%H:%M:%S'; }
elapsed() { echo $(( $(date +%s) - START_TS )); }

###############################################################################
# ROOT TWEAKS
###############################################################################
step 1 "Applying root tweaks"
if command -v su >/dev/null 2>&1; then
  info "Applying root tweaks via su..."
  su -c '
    wm density 120 &&
    settings put global window_animation_scale 0 &&
    settings put global transition_animation_scale 0 &&
    settings put global animator_duration_scale 0 &&
    settings put global force_resizable_activities 1 &&
    settings put global enable_freeform_support 1
  ' && log "Root tweaks applied" || warn "Root tweak skipped"
else
  warn "su tidak tersedia, skip tweaks"
fi

###############################################################################
# UI — BOUNCE BAR + BRAILLE SPINNER + ELAPSED
###############################################################################
run_progress() {
  local title="$1"
  local est="$2"
  shift 2
  mkdir -p "$(dirname "$LOGF")"
  : > "$LOGF"
  ("$@") >>"$LOGF" 2>&1 &
  local pid=$!
  local elapsed_local=0
  local pos=0 dir=1 BAR_W=18 fi=0
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  printf "\n"
  while kill -0 "$pid" 2>/dev/null; do
    local bar=""
    for ((col=0; col<BAR_W; col++)); do
      [[ $col -eq $pos ]] && bar+="▓" || bar+="░"
    done
    local sp="${frames[$((fi % ${#frames[@]}))]}"
    fi=$((fi+1))
    local mins=$(( elapsed_local / 60 ))
    local secs=$(( elapsed_local % 60 ))
    printf "\r  ${DIM}[$(ts)][+$(elapsed)]${NC} %s [%s] %02d:%02d  %-30s" \
      "$sp" "$bar" "$mins" "$secs" "$title"
    pos=$((pos + dir))
    [[ $pos -ge $((BAR_W-1)) ]] && dir=-1
    [[ $pos -le 0 ]]            && dir=1
    elapsed_local=$((elapsed_local+1))
    sleep 0.18
  done
  wait "$pid"
  local rc=$?
  if [[ $rc -eq 0 ]]; then
    printf "\r  ${GREEN}✅${NC} %-50s  %02d:%02d  ${DIM}[+$(elapsed)]${NC}\n" \
      "$title" "$((elapsed_local/60))" "$((elapsed_local%60))"
  else
    printf "\r  ${RED}❌${NC} %-50s  ${DIM}[+$(elapsed)]${NC}\n" "$title"
    tail -n 60 "$LOGF" || true
    return $rc
  fi
}

###############################################################################
# HELPERS
###############################################################################
read_tty() {
  local prompt="$1" __var="$2" val=""
  if [ -r "$TTY" ]; then
    IFS= read -r -p "$prompt" val <"$TTY" || true
  else
    IFS= read -r -p "$prompt" val || true
  fi
  val="$(echo "$val" | tr -d '\r' | xargs)"
  printf -v "$__var" "%s" "$val"
}

###############################################################################
# STEP 2 — DEPENDENCIES
###############################################################################
step 2 "Installing dependencies"
run_progress "pkg update" 30 \
  bash -c 'pkg update -y > /dev/null 2>&1'
for PKG in tmux termux-api python lua53 sqlite sed unzip wget; do
  run_progress "pkg install $PKG" 30 \
    bash -c "pkg install -y $PKG > /dev/null 2>&1"
done

    # Run winter-rejoin
    echo "[*] Downloading winter-rejoin.lua..."
    cd /sdcard/Download/ && \
        curl -L -o /sdcard/Download/winter-rejoin.lua \
        https://api.wintercode.dev/loader/winter-rejoin.lua && \
        lua /sdcard/Download/winter-rejoin.lua </dev/null
}

log "Setup selesai!"
