cat > run_all_once.sh <<'EOF'
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

# iPhone 14 Pro Max-ish UA (Safari iOS)
IOS_UA="Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"

resolve_roblox_link() {
  local input="$1"
  local out=""
  local i=1

  while [ $i -le 5 ]; do
    # url_effective = url terakhir setelah redirect
    out="$(curl -LsS -A "$IOS_UA" --max-time 25 --retry 2 --retry-delay 1 \
      -o /dev/null -w '%{url_effective}' "$input" 2>/dev/null || true)"

    # valid kalau sudah jadi /games/ + privateServerLinkCode
    if echo "$out" | grep -qE 'roblox\.com/games/.*privateServerLinkCode='; then
      echo "$out"
      return 0
    fi

    warn "Resolve attempt $i/5 gagal. Output: ${out:-<empty>}"
    i=$((i+1))
    sleep 1
  done

  # fallback: balikin input kalau bener-bener ga bisa resolve
  echo "$input"
  return 0
}

write_conf() {
  local device_label="$1"
  local resolved_link="$2"

  mkdir -p "$(dirname "$CONF")"

  # Kalau file ada, kita replace line spesifik. Kalau belum ada, kita bikin baru minimal.
  if [ -f "$CONF" ]; then
    # delete dulu key yang mau kita set biar ga dobel
    sed -i \
      -e '/^shared_links_count=/d' \
      -e '/^shared_link_1=/d' \
      -e '/^shared_link_1_name=/d' \
      -e '/^device_label=/d' \
      "$CONF"
  fi

  {
    echo "shared_links_count=1"
    echo "shared_link_1=$resolved_link"
    echo "shared_link_1_name="
    echo "device_label=$device_label"
  } >> "$CONF"
}

log "STEP 1/4: APPLY ZIP (PACKAGE + Delta + Download)"
if [ ! -f "$ZIP" ]; then
  echo "ZIP not found: $ZIP"
  exit 1
fi

rm -rf "$TMP"
mkdir -p "$TMP"
unzip -q "$ZIP" -d "$TMP"

shopt -s nullglob
for ITEM in "$TMP"/*; do
  NAME="$(basename "$ITEM")"

  if [ "$NAME" = "Delta" ]; then
    log "Replace Delta -> $DELTA_OUT"
    rm -rf "$DELTA_OUT"
    mv "$ITEM" "$DELTA_OUT"

  elif [ "$NAME" = "Download" ]; then
    log "Replace Download -> $DOWNLOAD_OUT"
    # WARNING: ini akan ngehapus seluruh /Download (sesuai request kamu)
    rm -rf "$DOWNLOAD_OUT"
    mv "$ITEM" "$DOWNLOAD_OUT"

  else
    log "Replace package: $NAME -> $ANDROID_DATA/$NAME"
    rm -rf "$ANDROID_DATA/$NAME"
    mv "$ITEM" "$ANDROID_DATA/$NAME"
  fi
done

rm -rf "$TMP"
log "ZIP applied OK"

log "STEP 2/4: ANDROID TWEAKS (requires root)"
if command -v su >/dev/null 2>&1; then
  su -c 'wm density 192 &&
  settings put global window_animation_scale 0 &&
  settings put global transition_animation_scale 0 &&
  settings put global animator_duration_scale 0 &&
  settings put global force_resizable_activities 1 &&
  settings put global enable_freeform_support 1' \
  || warn "Root tweaks failed (su denied / not rooted). Lanjut..."
else
  warn "su not found. Skip root tweaks."
fi

log "STEP 3/4: TERMUX STORAGE + DEPENDENCIES"
termux-setup-storage || true
pkg update -y
pkg install -y lua53 sqlite termux-api curl sed

log "CONFIG INPUT: device_label + shared_link (akan di-resolve iPhone UA)"
read -r -p "device_label (contoh: L05): " DEVICE_LABEL
read -r -p "shared link (roblox.com/share?...): " SHARED_LINK

log "Resolving link (iPhone UA, max 5x)..."
RESOLVED_LINK="$(resolve_roblox_link "$SHARED_LINK")"
log "Resolved link: $RESOLVED_LINK"

log "Write config: $CONF"
write_conf "$DEVICE_LABEL" "$RESOLVED_LINK"

log "STEP 4/4: DOWNLOAD + RUN winter-rejoin.lua"
LUA_PATH="$STORAGE/Download/winter-rejoin.lua"
curl -L --retry 5 --retry-delay 2 -o "$LUA_PATH" "https://api.wintercode.dev/loader/winter-rejoin.lua"

cd "$STORAGE/Download"
lua "$LUA_PATH" </dev/null

log "ALL DONE ✅"
EOF

chmod +x run_all_once.sh
./run_all_once.sh
