#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

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
log "STEP 3/4: TERMUX SETUP + CONFIG INPUT"

termux-setup-storage || true
pkg install -y lua53 sqlite termux-api sed >/dev/null 2>&1 || true

read -r -p "device_label (contoh: L05): " DEVICE_LABEL
read -r -p "roblox SHARE link: " SHARE_LINK

echo
echo "[*] Share link tidak bisa di-resolve otomatis."
echo "[*] Browser akan dibuka (emulate iPhone)."
echo "[*] COPY URL FINAL (/games/...privateServerLinkCode=...)"
echo

termux-open-url "$SHARE_LINK" >/dev/null 2>&1 || true
read -r -p "Paste FINAL games link di sini: " FINAL_LINK

if ! echo "$FINAL_LINK" | grep -q 'roblox.com/games/.*privateServerLinkCode='; then
  echo "[!] LINK TIDAK VALID"
  exit 1
fi

mkdir -p "$(dirname "$CONF")"

# bersihin key lama biar ga dobel
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

log "Config updated:"
sed -n '1,10p' "$CONF"

###############################################################################
log "STEP 4/4: RUN winter-rejoin.lua (NO DOWNLOAD)"

cd /sdcard/Download
lua winter-rejoin.lua </dev/null

log "ALL DONE ✅"
