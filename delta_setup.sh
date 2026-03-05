#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

BASE_PATH="/storage/emulated/0"
DEFAULT_ZIP_NAME="DELTA.zip"

ANDROID_DATA="$BASE_PATH/Android/data"
TMP="$BASE_PATH/__delta_tmp"
DELTA_OUT="$BASE_PATH/Delta"
DOWNLOAD_OUT="$BASE_PATH/Download"
CONF="$BASE_PATH/Download/WinterHub/auto_rejoin.conf"
TTY="/dev/tty"

log(){ echo -e "\n\033[1;32m[+] $*\033[0m"; }
warn(){ echo -e "\n\033[1;31m[!] $*\033[0m"; }

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

usage() {
  echo "Usage:"
  echo "  $0 [-z ZIP_NAME] [-d DEVICE] [-l SHARE_LINK]"
  exit 0
}

# ==========================
# DEPENDENCIES
# ==========================

log "Checking dependencies"

pkg update -y
pkg upgrade -y

pkg install -y \
python \
python-pip \
lua \
unzip \
curl \
wget \
sed \
tmux \
tesseract \
termux-api

pip install --quiet requests

log "Dependencies ready"

# ==========================
# ARGUMENT PARSE
# ==========================

while getopts "d:l:z:h" opt; do
  case $opt in
    d) DEVICE_LABEL="$OPTARG" ;;
    l) SHARE_LINK="$OPTARG" ;;
    z) ZIP_NAME="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

# ==========================
# ZIP PRIORITY
# ==========================

if [ -n "${ZIP_NAME:-}" ]; then
  ZIP="$BASE_PATH/$ZIP_NAME"

elif [ -f "$BASE_PATH/$DEFAULT_ZIP_NAME" ]; then
  ZIP="$BASE_PATH/$DEFAULT_ZIP_NAME"

else
  read_tty "Masukkan nama ZIP: " ZIP_NAME
  ZIP="$BASE_PATH/$ZIP_NAME"
fi

while [ ! -f "$ZIP" ]; do
  warn "ZIP tidak ditemukan: $ZIP"
  read_tty "Masukkan nama ZIP valid: " ZIP_NAME
  ZIP="$BASE_PATH/$ZIP_NAME"
done

log "Using ZIP: $ZIP"

# ==========================
# APPLY ZIP
# ==========================

log "STEP 1/4 APPLY ZIP"

rm -rf "$TMP"
mkdir -p "$TMP"

unzip -q "$ZIP" -d "$TMP"

shopt -s nullglob
for ITEM in "$TMP"/*; do

  NAME="$(basename "$ITEM")"

  case "$NAME" in
    "."|".."|"") continue ;;
  esac

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

log "ZIP applied"

# ==========================
# DEVICE INPUT
# ==========================

if [ -z "${DEVICE_LABEL:-}" ]; then

  read_tty "device_label (contoh L05): " DEVICE_LABEL

  while [ -z "$DEVICE_LABEL" ]; do
    read_tty "device_label tidak boleh kosong: " DEVICE_LABEL
  done

fi

# ==========================
# LINK INPUT
# ==========================

if [ -z "${SHARE_LINK:-}" ]; then
  read_tty "roblox SHARE link: " SHARE_LINK
fi

while ! echo "$SHARE_LINK" | grep -qiE '^https?://'; do
  warn "Link harus http/https"
  read_tty "roblox SHARE link: " SHARE_LINK
done

# ==========================
# RESOLVE LINK
# ==========================

log "Resolving share link"

FINAL_LINK="$(python3 - "$SHARE_LINK" <<'PY'
import sys,requests,time
url=sys.argv[1]
s=requests.Session()
s.headers.update({"User-Agent":"Mozilla/5.0"})
out=None
for _ in range(5):
 try:
  r=s.get(url,timeout=20)
  f=str(r.url)
  if "roblox.com/games/" in f and "privateServerLinkCode=" in f:
   out=f
   break
 except:
  time.sleep(1)
print(out or "")
PY
)"

if [ -z "$FINAL_LINK" ]; then
  warn "Gagal resolve link"
  exit 1
fi

log "Resolved OK"

# ==========================
# WRITE CONFIG
# ==========================

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

log "Config updated"

log "Applying Android performance tweaks"

if command -v su >/dev/null 2>&1; then

su -c '
wm density 120
settings put global window_animation_scale 0
settings put global transition_animation_scale 0
settings put global animator_duration_scale 0
settings put global force_resizable_activities 1
settings put global enable_freeform_support 1
'

log "Android tweaks applied"

else

warn "Root tidak ditemukan, skip android tweaks"

fi
# ==========================
# START BOT (TMUX)
# ==========================

log "Starting BOT tmux session"

tmux kill-session -t bot 2>/dev/null || true

tmux new-session -d -s bot \
"curl -s https://raw.githubusercontent.com/zyasfin/po/refs/heads/main/bot.sh | bash -s -- --device '$DEVICE_LABEL'"

log "BOT started in tmux session"

# ==========================
# RUN WINTER REJOIN
# ==========================

log "Running winter-rejoin.lua"

cd "$DOWNLOAD_OUT"

lua winter-rejoin.lua
