#!/data/data/com.termux/files/usr/bin/bash
set -e

###############################################################################
# ARGUMENT + DEFAULT
###############################################################################

DEFAULT_ZIP="/storage/emulated/0/DELTA.zip"
DEFAULT_DEVICE=""
DEFAULT_LINK=""

DEVICE_LABEL=""
SHARE_LINK=""
ZIP="$DEFAULT_ZIP"

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --device) DEVICE_LABEL="$2"; shift ;;
    --zip) ZIP="$2"; shift ;;
    --link) SHARE_LINK="$2"; shift ;;
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

###############################################################################
# UI BATTERY PROGRESS
###############################################################################

battery() {
  p=$1
  filled=$((p/5))
  empty=$((20-filled))
  printf "\r["
  for ((i=0;i<filled;i++)); do printf "█"; done
  for ((i=0;i<empty;i++)); do printf " "; done
  printf "] %d%%" "$p"
}

step() {
  percent=$1
  msg="$2"
  battery "$percent"
  sleep 0.3
  echo -e "\n⚡ $msg"
}

###############################################################################
# HELPER
###############################################################################

log(){ echo -e "\n[+] $*"; }
warn(){ echo -e "\n[!] $*"; }

read_tty() {
  local prompt="$1"
  local __var="$2"
  local val=""
  if [ -r "$TTY" ]; then
    IFS= read -r -p "$prompt" val <"$TTY" || true
  else
    IFS= read -r -p "$prompt" val || true
  fi
  val="$(echo "$val" | tr -d '\r' | xargs)"
  printf -v "$__var" "%s" "$val"
}

run_progress() {
  local title="$1"
  local est="$2"
  shift 2
  mkdir -p "$(dirname "$LOGF")"
  : > "$LOGF"
  ("$@") >>"$LOGF" 2>&1 &
  local pid=$!
  local elapsed=0
  local pos=0
  local dir=1
  local BAR_W=18
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local fi=0
  printf "\n"
  while kill -0 "$pid" 2>/dev/null; do
    local bar=""
    for ((col=0; col<BAR_W; col++)); do
      if [ $col -eq $pos ]; then bar+="▓"; else bar+="░"; fi
    done
    local sp="${frames[$((fi % ${#frames[@]}))]}"
    fi=$((fi+1))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))
    printf "\r  %s [%s] %02d:%02d  %-30s" "$sp" "$bar" "$mins" "$secs" "$title"
    pos=$((pos + dir))
    if [ $pos -ge $((BAR_W-1)) ]; then dir=-1; fi
    if [ $pos -le 0 ];            then dir=1;  fi
    elapsed=$((elapsed+1))
    sleep 0.18
  done
  wait "$pid"
  local rc=$?
  if [ $rc -eq 0 ]; then
    printf "\r  ✅ %-50s  %02d:%02d\n" "$title" "$((elapsed/60))" "$((elapsed%60))"
  else
    printf "\r  ❌ %-50s\n" "$title"
    tail -n 60 "$LOGF" || true
    return $rc
  fi
}

clear
echo "AUTO INSTALLER PRO MODE"
sleep 1

###############################################################################
# STEP 0 — BUKA APP (background, selagi install jalan)
###############################################################################

step 2 "Opening required apps"

# Buka Termux:Boot — perlu dibuka sekali agar permission boot aktif
am start -n com.termux.boot/.TermuxBootActivity > /dev/null 2>&1 || \
am start -a android.intent.action.MAIN -p com.termux.boot > /dev/null 2>&1 || \
monkey -p com.termux.boot -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 || \
warn "Termux:Boot tidak ditemukan — install dari F-Droid lalu jalankan sekali manual"

sleep 2

# Buka com.rootbot kalau ada
am start -n com.rootbot/.MainActivity > /dev/null 2>&1 || \
am start -a android.intent.action.MAIN -p com.rootbot > /dev/null 2>&1 || true

sleep 1

###############################################################################
# STEP 1 — DEPENDENCY + BOT + WATCHDOG + BOOT
###############################################################################

step 5 "Installing dependencies"
pkg update -y > /dev/null 2>&1
# tesseract dihapus — bot versi ini tidak pakai OCR
pkg install -y tmux termux-api python lua53 sqlite sed unzip curl > /dev/null 2>&1

step 10 "Saving device name"

if [ -z "$DEVICE_LABEL" ]; then
  read_tty "device_label (contoh: L05): " DEVICE_LABEL
fi

CONFIG_FILE="$HOME/.rootbot_config"
echo "DEVICE_NAME=$DEVICE_LABEL" > "$CONFIG_FILE"
log "Device name disimpan ke $CONFIG_FILE"

step 15 "Setting up Termux:Boot"

BOOT_DIR="$HOME/.termux/boot"
mkdir -p "$BOOT_DIR"
curl -fsSL "$BOOT_URL" -o "$BOOT_DIR/start.sh"
chmod +x "$BOOT_DIR/start.sh"
log "boot.sh terpasang di $BOOT_DIR/start.sh (auto-start saat reboot)"

step 20 "Launching watchdog + bot"

# Kill session lama kalau ada
tmux kill-session -t watchdog 2>/dev/null || true
tmux kill-session -t bot      2>/dev/null || true
sleep 1

# Watchdog yang akan start & jaga bot secara otomatis
tmux new-session -d -s watchdog \
  "curl -fsSL '$WATCHDOG_URL' | bash -s"

log "Watchdog jalan di tmux session 'watchdog'"
log "Bot akan distart otomatis oleh watchdog"

###############################################################################
# STEP 1 — APPLY ZIP
###############################################################################

step 35 "Applying ZIP package"

[ -f "$ZIP" ] || { echo "ZIP not found: $ZIP"; exit 1; }

rm -rf "$TMP"
mkdir -p "$TMP"
unzip -q "$ZIP" -d "$TMP"

shopt -s nullglob
for ITEM in "$TMP"/*; do
  NAME="$(basename "$ITEM")"

  if [ "$NAME" = "Delta" ]; then
    rm -rf "$DELTA_OUT"
    mv "$ITEM" "$DELTA_OUT"

  elif [ "$NAME" = "Download" ]; then
    rm -rf "$DOWNLOAD_OUT"
    mv "$ITEM" "$DOWNLOAD_OUT"

  else
    rm -rf "$ANDROID_DATA/$NAME"
    mv "$ITEM" "$ANDROID_DATA/$NAME"
  fi
done

rm -rf "$TMP"

###############################################################################
# STEP 2 — ANDROID TWEAK
###############################################################################

step 50 "Applying Android tweaks"

if command -v su >/dev/null 2>&1; then
  su -c '
    wm density 120 &&
    settings put global window_animation_scale 0 &&
    settings put global transition_animation_scale 0 &&
    settings put global animator_duration_scale 0 &&
    settings put global force_resizable_activities 1 &&
    settings put global enable_freeform_support 1
  ' || warn "Root tweak skipped"
fi

###############################################################################
# STEP 3 — RESOLVE LINK
###############################################################################

step 60 "Preparing Python resolve"

termux-setup-storage || true
run_progress "pip install requests" 30 python3 -m pip install -U requests

if [ -z "$SHARE_LINK" ]; then
  read_tty "roblox SHARE link: " SHARE_LINK
fi

step 70 "Resolving Roblox link"

FINAL_LINK="$(python3 - <<PYEOF
import re, sys, time, requests
url = "$SHARE_LINK"
IOS_UA=("Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) "
"AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 "
"Mobile/15E148 Safari/604.1")
games_re=re.compile(r"https?://www\.roblox\.com/games/\d+[^\"'\s]*privateServerLinkCode=[A-Za-z0-9]+")
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

[ -z "$FINAL_LINK" ] && { echo "Resolve failed"; exit 1; }

###############################################################################
# WRITE CONFIG
###############################################################################

step 85 "Writing config"

mkdir -p "$(dirname "$CONF")"

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

###############################################################################
# STEP 4 — WINTER EXECUTE
###############################################################################

step 95 "Running winter-rejoin.lua"

cd /sdcard/Download
lua winter-rejoin.lua </dev/null

###############################################################################
# DONE
###############################################################################

step 100 "ALL DONE ✅"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Bot     → tmux attach -t bot"
echo " Watchdog→ tmux attach -t watchdog"
echo " Reboot  → auto-start via Termux:Boot ✓"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
