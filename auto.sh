#!/data/data/com.termux/files/usr/bin/bash
set -e

###############################################################################
# ARGUMENT + DEFAULT
###############################################################################

DEVICE_LABEL=""
SHARE_LINK=""
ZIP="/storage/emulated/0/DELTA.zip"

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --device) DEVICE_LABEL="$2"; shift ;;
    --zip)    ZIP="$2";          shift ;;
    --link)   SHARE_LINK="$2";   shift ;;
  esac
  shift
done

###############################################################################
# PATH CONFIG
###############################################################################

STORAGE="/storage/emulated/0"
ANDROID_DATA="$STORAGE/Android/data"
TMP="$STORAGE/__delta_tmp"
DELTA_OUT="$STORAGE/Delta"
DOWNLOAD_OUT="$STORAGE/Download"
CONF="$STORAGE/Download/WinterHub/auto_rejoin.conf"
TTY="/dev/tty"
LOGF="/data/data/com.termux/files/usr/tmp/auto_install.log"

BOT_URL="https://raw.githubusercontent.com/zyasfin/po/refs/heads/main/bot.sh"
WATCHDOG_URL="https://raw.githubusercontent.com/zyasfin/po/refs/heads/main/watchdog.sh"
BOOT_URL="https://raw.githubusercontent.com/zyasfin/po/refs/heads/main/boot.sh"

SCRIPT_START=$(date +%s)

###############################################################################
# COLORS
###############################################################################

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'

###############################################################################
# TIMESTAMP + LOG HELPERS
###############################################################################

ts() { date '+%H:%M:%S'; }

elapsed() {
  local now=$(date +%s)
  local diff=$(( now - SCRIPT_START ))
  printf "%02d:%02d" $(( diff/60 )) $(( diff%60 ))
}

tlog() {
  # tlog COLOR TAG message
  local color=$1 tag=$2; shift 2
  echo -e "${DIM}[$(ts)][+$(elapsed)]${NC} ${color}[${tag}]${NC} $*"
}

log()  { tlog "$GREEN"  "OK"   "$*"; }
warn() { tlog "$YELLOW" "WARN" "$*"; }
info() { tlog "$CYAN"   "INFO" "$*"; }
err()  { tlog "$RED"    "ERR"  "$*"; }

###############################################################################
# UI — BATTERY PROGRESS BAR
###############################################################################

battery() {
  local p=$1 filled=$((p/5)) empty=$((20-p/5))
  printf "\r${DIM}[$(ts)][+$(elapsed)]${NC} "
  printf "["
  for ((i=0;i<filled;i++)); do printf "█"; done
  for ((i=0;i<empty;i++));  do printf "░"; done
  printf "] ${BOLD}%d%%${NC}" "$p"
}

step() {
  local percent=$1 msg=$2
  battery "$percent"
  sleep 0.3
  echo -e "\n${CYAN}⚡ $msg${NC}"
}

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

# Download file — curl dulu, fallback wget
fetch() {
  local url="$1" out="$2"
  curl -fsSL "$url" -o "$out" 2>/dev/null || wget -qO "$out" "$url"
}

# Download ke stdout — curl dulu, fallback wget
fetch_pipe() {
  curl -fsSL "$1" 2>/dev/null || wget -qO- "$1"
}

###############################################################################
# START
###############################################################################

clear
echo -e "${BOLD}AUTO INSTALLER PRO MODE${NC}"
echo -e "${DIM}Started: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
sleep 1

###############################################################################
# STEP 0 — BUKA APP
###############################################################################

step 2 "Opening required apps"

info "Membuka Termux:Boot..."
am start -n com.termux.boot/com.termux.boot.TermuxBootActivity > /dev/null 2>&1 || \
am start -n com.termux.boot/.TermuxBootActivity                > /dev/null 2>&1 || \
am start -a android.intent.action.MAIN \
         -c android.intent.category.LAUNCHER \
         -p com.termux.boot                                    > /dev/null 2>&1 || \
monkey -p com.termux.boot 1                                    > /dev/null 2>&1 && \
log "Termux:Boot dibuka" || warn "Termux:Boot tidak ditemukan — install dari F-Droid"

sleep 2

info "Membuka com.rootbot..."
am start -n com.rootbot/.MainActivity                          > /dev/null 2>&1 || \
am start -a android.intent.action.MAIN -p com.rootbot          > /dev/null 2>&1 || true
log "com.rootbot launch dikirim"

sleep 1

###############################################################################
# STEP 1 — DEPENDENCIES
###############################################################################

step 5 "Installing dependencies"
info "pkg update..."
pkg update -y > /dev/null 2>&1
info "pkg install tmux termux-api python lua53 sqlite sed unzip wget..."
pkg install -y tmux termux-api python lua53 sqlite sed unzip wget > /dev/null 2>&1
info "pkg install curl (opsional, fallback wget)..."
pkg install -y curl > /dev/null 2>&1 && log "curl OK" || warn "curl gagal, pakai wget"

###############################################################################
# STEP 2 — DEVICE NAME
###############################################################################

step 10 "Saving device name"

if [ -z "$DEVICE_LABEL" ]; then
  read_tty "device_label (contoh: L05): " DEVICE_LABEL
fi

CONFIG_FILE="$HOME/.rootbot_config"
echo "DEVICE_NAME=$DEVICE_LABEL" > "$CONFIG_FILE"
log "Device name '$DEVICE_LABEL' disimpan ke $CONFIG_FILE"

###############################################################################
# STEP 3 — SETUP TERMUX:BOOT
###############################################################################

step 15 "Setting up Termux:Boot"

BOOT_DIR="$HOME/.termux/boot"
mkdir -p "$BOOT_DIR"
info "Download boot.sh -> $BOOT_DIR/start.sh"
fetch "$BOOT_URL" "$BOOT_DIR/start.sh"
chmod +x "$BOOT_DIR/start.sh"
log "boot.sh terpasang — auto-start aktif saat reboot"

###############################################################################
# STEP 4 — LAUNCH WATCHDOG + BOT
###############################################################################

step 20 "Launching watchdog + bot"

info "Kill session lama..."
tmux kill-session -t watchdog 2>/dev/null && info "killed: watchdog" || true
tmux kill-session -t bot      2>/dev/null && info "killed: bot"      || true
sleep 1

info "Start tmux session 'watchdog'..."
tmux new-session -d -s watchdog \
  "curl -fsSL '$WATCHDOG_URL' | bash -s || wget -qO- '$WATCHDOG_URL' | bash -s"
log "Watchdog jalan — bot akan distart otomatis oleh watchdog"

###############################################################################
# STEP 5 — APPLY ZIP
###############################################################################

step 35 "Applying ZIP package"

[ -f "$ZIP" ] || { err "ZIP not found: $ZIP"; exit 1; }
info "Unzip $ZIP -> $TMP"
rm -rf "$TMP"
mkdir -p "$TMP"
unzip -q "$ZIP" -d "$TMP"

shopt -s nullglob
for ITEM in "$TMP"/*; do
  NAME="$(basename "$ITEM")"
  if   [ "$NAME" = "Delta" ];    then rm -rf "$DELTA_OUT";              mv "$ITEM" "$DELTA_OUT"
  elif [ "$NAME" = "Download" ]; then rm -rf "$DOWNLOAD_OUT";           mv "$ITEM" "$DOWNLOAD_OUT"
  else                                rm -rf "$ANDROID_DATA/$NAME";     mv "$ITEM" "$ANDROID_DATA/$NAME"
  fi
  info "Installed: $NAME"
done
rm -rf "$TMP"
log "ZIP applied"

###############################################################################
# STEP 6 — ANDROID TWEAK
###############################################################################

step 50 "Applying Android tweaks"

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
# STEP 7 — RESOLVE LINK
###############################################################################

step 60 "Preparing Python resolve"

termux-setup-storage || true
run_progress "pip install requests" 30 python3 -m pip install -U requests

if [ -z "$SHARE_LINK" ]; then
  read_tty "roblox SHARE link: " SHARE_LINK
fi
info "Resolving: $SHARE_LINK"

step 70 "Resolving Roblox link"

FINAL_LINK="$(python3 - <<PYEOF
import re, sys, time, requests
url = "$SHARE_LINK"
IOS_UA=("Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) "
"AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 "
"Mobile/15E148 Safari/604.1")
s=requests.Session()
s.headers.update({"User-Agent":IOS_UA})
for _ in range(5):
  try:
    r=s.get(url,allow_redirects=True,timeout=20)
    if "privateServerLinkCode=" in r.url:
      print(r.url);break
  except: time.sleep(1)
PYEOF
)"

[ -z "$FINAL_LINK" ] && { err "Resolve failed"; exit 1; }
log "Resolved: $FINAL_LINK"

###############################################################################
# STEP 8 — WRITE CONFIG
###############################################################################

step 85 "Writing config"

mkdir -p "$(dirname "$CONF")"
info "Menulis ke $CONF"

sed -i \
  -e '/^shared_links_count=/d' \
  -e '/^shared_link_1=/d' \
  -e '/^shared_link_1_name=/d' \
  -e '/^device_label=/d' \
  "$CONF" 2>/dev/null || true

{
  echo "shared_links_count=1"
  echo "shared_link_1=$FINAL_LINK"
  echo "shared_link_1_name="
  echo "device_label=$DEVICE_LABEL"
} >> "$CONF"
log "Config ditulis"

###############################################################################
# STEP 9 — WINTER EXECUTE
###############################################################################

step 95 "Running winter-rejoin.lua"

info "cd /sdcard/Download && lua winter-rejoin.lua"
cd /sdcard/Download
lua winter-rejoin.lua </dev/null

###############################################################################
# DONE
###############################################################################

step 100 "ALL DONE ✅"

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e " ${GREEN}✓${NC} Total waktu  : $(elapsed)"
echo -e " ${GREEN}✓${NC} Device       : $DEVICE_LABEL"
echo -e " ${GREEN}✓${NC} Bot          : tmux attach -t bot"
echo -e " ${GREEN}✓${NC} Watchdog     : tmux attach -t watchdog"
echo -e " ${GREEN}✓${NC} Auto-reboot  : Termux:Boot ✓"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
