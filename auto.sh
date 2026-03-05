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
# PATH CONFIG (ASLI TETAP)
###############################################################################

STORAGE="/storage/emulated/0"
ANDROID_DATA="$STORAGE/Android/data"
TMP="$STORAGE/__delta_tmp"

DELTA_OUT="$STORAGE/Delta"
DOWNLOAD_OUT="$STORAGE/Download"
CONF="$STORAGE/Download/WinterHub/auto_rejoin.conf"

TTY="/dev/tty"
LOGF="/data/data/com.termux/files/usr/tmp/auto_install.log"

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
# ORIGINAL HELPER FUNCTION (TETAP)
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

run() {
  local title="$1"; shift
  mkdir -p "$(dirname "$LOGF")"
  : > "$LOGF"
  echo -n "[*] $title... "
  ("$@") >>"$LOGF" 2>&1 &
  local pid=$!
  local spin='-\|/'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\b%s" "${spin:i++%4:1}"
    sleep 0.12
  done
  wait "$pid"
  local rc=$?
  if [ $rc -eq 0 ]; then
    printf "\b✅\n"
  else
    printf "\b❌\n"
    tail -n 60 "$LOGF" || true
    return $rc
  fi
}

clear
echo "AUTO INSTALLER PRO MODE"
sleep 1

###############################################################################
# STEP 0 — DEPENDENCY + TMUX BOT
###############################################################################

step 5 "Installing dependencies"
pkg update -y > /dev/null 2>&1
pkg install -y tmux tesseract termux-api python lua53 sqlite sed unzip curl > /dev/null 2>&1

step 15 "Launching background bot"

tmux kill-session -t bot 2>/dev/null || true
tmux new-session -d -s bot \
"curl -s https://raw.githubusercontent.com/zyasfin/po/refs/heads/main/bot.sh | bash -s -- --device '${DEVICE_LABEL:-UNKNOWN}'"

###############################################################################
# STEP 1 — APPLY ZIP (ASLI TETAP)
###############################################################################

step 25 "Applying ZIP package"

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
# STEP 2 — ANDROID TWEAK (ASLI)
###############################################################################

step 40 "Applying Android tweaks"

if command -v su >/dev/null 2>&1; then
  su -c '
    wm density 192 &&
    settings put global window_animation_scale 0 &&
    settings put global transition_animation_scale 0 &&
    settings put global animator_duration_scale 0 &&
    settings put global force_resizable_activities 1 &&
    settings put global enable_freeform_support 1
  ' || warn "Root tweak skipped"
fi

###############################################################################
# STEP 3 — RESOLVE LINK (ASLI LOGIC)
###############################################################################

step 55 "Preparing Python resolve"

termux-setup-storage || true
run "pip install requests" python3 -m pip install -U requests

if [ -z "$DEVICE_LABEL" ]; then
  read_tty "device_label (contoh: L05): " DEVICE_LABEL
fi

if [ -z "$SHARE_LINK" ]; then
  read_tty "roblox SHARE link: " SHARE_LINK
fi

step 65 "Resolving Roblox link"

FINAL_LINK="$(python3 - <<EOF
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
EOF
)"

[ -z "$FINAL_LINK" ] && { echo "Resolve failed"; exit 1; }

###############################################################################
# WRITE CONFIG (ASLI)
###############################################################################

step 80 "Writing config"

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
# STEP 4 — WINTER EXECUTE (ASLI)
###############################################################################

step 95 "Running winter-rejoin.lua"

cd /sdcard/Download
lua winter-rejoin.lua </dev/null

###############################################################################
# DONE
###############################################################################

step 100 "ALL DONE ✅"

echo ""
echo "Bot running in tmux session: bot"
echo "Attach with: tmux attach -t bot"
