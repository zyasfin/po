#!/data/data/com.termux/files/usr/bin/bash
set -e

STORAGE="/storage/emulated/0"
ANDROID_DATA="$STORAGE/Android/data"
ZIP="$STORAGE/LTRGF.zip"
TMP="$STORAGE/__delta_tmp"

DELTA_OUT="$STORAGE/Delta"
DOWNLOAD_OUT="$STORAGE/Download"
CONF="$STORAGE/Download/WinterHub/auto_rejoin.conf"

log(){ echo -e "\n[+] $*"; }
warn(){ echo -e "\n[!] $*"; }

###############################################################################
log "STEP 1/4: APPLY ZIP (PACKAGE + Delta + Download)"

[ -f "$ZIP" ] || { echo "ZIP not found: $ZIP"; exit 1; }

rm -rf "$TMP"
mkdir -p "$TMP"
unzip -q "$ZIP" -d "$TMP"

shopt -s nullglob
for ITEM in "$TMP"/*; do
  NAME="$(basename "$ITEM")"

  if [ "$NAME" = "Delta" ]; then
    log "Replace Delta"
    rm -rf "$DELTA_OUT"
    mv "$ITEM" "$DELTA_OUT"

  elif [ "$NAME" = "Download" ]; then
    log "Replace Download"
    rm -rf "$DOWNLOAD_OUT"
    mv "$ITEM" "$DOWNLOAD_OUT"

  else
    log "Replace package: $NAME"
    rm -rf "$ANDROID_DATA/$NAME"
    mv "$ITEM" "$ANDROID_DATA/$NAME"
  fi
done

rm -rf "$TMP"
log "ZIP applied OK"

###############################################################################
log "STEP 2/4: ANDROID TWEAKS (root optional)"

if command -v su >/dev/null 2>&1; then
  su -c '
    wm density 192 &&
    settings put global window_animation_scale 0 &&
    settings put global transition_animation_scale 0 &&
    settings put global animator_duration_scale 0 &&
    settings put global force_resizable_activities 1 &&
    settings put global enable_freeform_support 1
  ' || warn "Root tweak skipped"
else
  warn "su not found, skip tweaks"
fi

###############################################################################
log "STEP 3/4: PYTHON RESOLVE ROBLOX SHARE LINK"

termux-setup-storage || true
pkg install -y python lua53 sqlite termux-api sed >/dev/null 2>&1 || true
pip install -U requests >/dev/null 2>&1 || true

read -r -p "device_label (contoh: L05): " DEVICE_LABEL
while [ -z "$DEVICE_LABEL" ]; do
  read -r -p "device_label tidak boleh kosong, isi lagi: " DEVICE_LABEL
done

read -r -p "roblox SHARE link: " SHARE_LINK
while [ -z "$SHARE_LINK" ]; do
  read -r -p "SHARE link tidak boleh kosong, isi lagi: " SHARE_LINK
done

log "Resolving link via Python..."

FINAL_LINK="$(python3 - <<'PY'
import re, sys, requests

url = sys.argv[1]
IOS_UA = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 "
    "Mobile/15E148 Safari/604.1"
)

s = requests.Session()
s.headers.update({"User-Agent": IOS_UA})

r = s.get(url, allow_redirects=True, timeout=25)
final = str(r.url)

if "roblox.com/games/" in final and "privateServerLinkCode=" in final:
    print(final)
    sys.exit(0)

html = r.text or ""
m = re.search(r"https://www\.roblox\.com/games/\d+[^\"'\s]*privateServerLinkCode=[A-Za-z0-9]+", html)
if m:
    print(m.group(0))
    sys.exit(0)

print("")
PY
" "$SHARE_LINK")"

if [ -z "$FINAL_LINK" ]; then
  echo "[!] GAGAL resolve link via Python"
  exit 1
fi

log "Resolved link:"
echo "$FINAL_LINK"

###############################################################################
log "WRITE CONFIG: auto_rejoin.conf"

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

log "Config OK"

###############################################################################
log "STEP 4/4: RUN winter-rejoin.lua"

cd /sdcard/Download
lua winter-rejoin.lua </dev/null

log "ALL DONE ✅"
