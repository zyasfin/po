#!/data/data/com.termux/files/usr/bin/bash
set -e

# ==========================
# CONFIG
# ==========================
BASE_PATH="/storage/emulated/0"
DEFAULT_ZIP_NAME="DELTA.zip"

ANDROID_DATA="$BASE_PATH/Android/data"
TMP="$BASE_PATH/__delta_tmp"
DELTA_OUT="$BASE_PATH/Delta"
DOWNLOAD_OUT="$BASE_PATH/Download"
CONF="$BASE_PATH/Download/WinterHub/auto_rejoin.conf"
TTY="/dev/tty"

# ==========================
# COLORS & STYLES
# ==========================
R='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
RED='\033[0;31m'
BGREEN='\033[1;32m'
BRED='\033[1;31m'
BYELLOW='\033[1;33m'
BCYAN='\033[1;36m'
BWHITE='\033[1;37m'

# ==========================
# LOG FUNCTIONS
# ==========================

_bar() {
  echo -e "${DIM}${CYAN}  ─────────────────────────────────────────────${R}"
}

_header() {
  echo ""
  echo -e "${BCYAN}${BOLD}"
  echo "  ╔═══════════════════════════════════════════╗"
  echo "  ║         DELTA SETUP  •  WinterHub          ║"
  echo "  ╚═══════════════════════════════════════════╝"
  echo -e "${R}"
}

log() {
  echo -e "\n${BCYAN}  ◆${R}${BOLD} $*${R}"
}

warn() {
  echo -e "\n${BYELLOW}  ▲ ${BOLD}WARNING${R}${YELLOW}  $*${R}"
}

ok() {
  echo -e "  ${BGREEN}✔${R}${GREEN}  $*${R}"
}

err() {
  echo -e "\n  ${BRED}✘ ${BOLD}ERROR${R}${RED}  $*${R}"
}

step() {
  local num="$1"
  local total="$2"
  local title="$3"
  echo ""
  _bar
  echo -e "  ${BWHITE}${BOLD}STEP ${num}/${total}${R}  ${BCYAN}${title}${R}"
  _bar
}

info() {
  echo -e "  ${DIM}${WHITE}->  $*${R}"
}

prompt_label() {
  echo -e "\n  ${BYELLOW}?${R}${BOLD}  $*${R}"
}

# ==========================
# READ TTY
# ==========================
read_tty() {
  local prompt="$1"
  local __var="$2"
  local val=""
  prompt_label "$prompt"
  printf "  ${BCYAN}> ${R}"
  if [ -r "$TTY" ]; then
    IFS= read -r val <"$TTY" || true
  else
    IFS= read -r val || true
  fi
  val="$(echo "$val" | tr -d '\r' | xargs)"
  printf -v "$__var" "%s" "$val"
}
echo ""
echo "======================================"
echo "        TWEAK PERFORMANCE SETUP       "
echo "======================================"
echo ""

log() {
    echo "[*] $1"
}

ok() {
    echo "[✓] $1"
}

log "Initializing tweak environment..."

sleep 1

log "Applying UI & animation performance tweaks..."

su -c '
wm density 120
settings put global window_animation_scale 0
settings put global transition_animation_scale 0
settings put global animator_duration_scale 0
settings put global force_resizable_activities 1
settings put global enable_freeform_support 1
'

ok "UI animation tweaks applied"

sleep 1

log "Applying GPU & rendering optimizations..."

su -c '
settings put global debug.hwui.renderer skiagl
settings put global debug.hwui.disable_vsync false
settings put global debug.hwui.force_dark 0
settings put global debug.hwui.use_buffer_age true
'

ok "GPU rendering optimized"

sleep 1

log "Applying system performance tweaks..."

su -c '
settings put global activity_manager_constants max_cached_processes=1024
settings put global app_standby_enabled 0
settings put global adaptive_battery_management_enabled 0
settings put global cached_apps_freezer enabled
'

ok "System performance tuned"

sleep 1

log "Applying display & responsiveness tweaks..."

su -c '
settings put system pointer_speed 7
settings put system min_refresh_rate 90
settings put system peak_refresh_rate 120
'

ok "Display responsiveness improved"

sleep 1

log "Finalizing configuration..."

sleep 1

echo ""
echo "======================================"
echo "        DELTA SETUP COMPLETED         "
echo "======================================"
echo ""
echo "[✓] All tweaks successfully applied"
echo "[✓] System should feel smoother & faster"
echo ""

# ==========================
# USAGE
# ==========================
usage() {
  echo ""
  echo -e "  ${BWHITE}Usage:${R}"
  echo -e "  ${CYAN}$0${R} ${DIM}[-z ZIP_NAME] [-d DEVICE] [-l SHARE_LINK]${R}"
  echo ""
  echo -e "  ${BWHITE}Priority:${R}"
  echo -e "  ${DIM}Argument ${WHITE}>${R}${DIM} Default (DELTA.zip) ${WHITE}>${R}${DIM} Prompt${R}"
  echo ""
  exit 0
}

# ==========================
# ENTRY
# ==========================
clear
_header

# ==========================
# PARSE FLAGS
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
# ZIP PRIORITY SYSTEM
# ==========================

if [ -n "$ZIP_NAME" ]; then
  ZIP="$BASE_PATH/$ZIP_NAME"
elif [ -f "$BASE_PATH/$DEFAULT_ZIP_NAME" ]; then
  ZIP="$BASE_PATH/$DEFAULT_ZIP_NAME"
else
  read_tty "Masukkan nama file ZIP (contoh: DELTA.zip):" ZIP_NAME
  ZIP="$BASE_PATH/$ZIP_NAME"
fi

while [ ! -f "$ZIP" ]; do
  warn "File tidak ditemukan: ${BOLD}$ZIP${R}"
  read_tty "Masukkan nama file ZIP yang valid:" ZIP_NAME
  ZIP="$BASE_PATH/$ZIP_NAME"
done

info "ZIP  ->  ${BOLD}$ZIP${R}"

# ==========================
# APPLY ZIP
# ==========================
step 1 4 "APPLY ZIP"

rm -rf "$TMP"
mkdir -p "$TMP"
info "Extracting archive..."
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
ok "ZIP applied successfully"

# ==========================
# DEVICE PRIORITY
# ==========================
step 2 4 "DEVICE LABEL"

if [ -z "$DEVICE_LABEL" ]; then
  read_tty "device_label (contoh: L05):" DEVICE_LABEL
  while [ -z "$DEVICE_LABEL" ]; do
    warn "device_label tidak boleh kosong"
    read_tty "device_label (contoh: L05):" DEVICE_LABEL
  done
fi

ok "Device label  ->  ${BOLD}$DEVICE_LABEL${R}"

# ==========================
# LINK PRIORITY
# ==========================
step 3 4 "ROBLOX SHARE LINK"

if [ -z "$SHARE_LINK" ]; then
  read_tty "roblox SHARE link:" SHARE_LINK
fi

while ! echo "$SHARE_LINK" | grep -qiE '^https?://'; do
  warn "Link harus diawali ${BOLD}http://${R}${YELLOW} atau ${BOLD}https://${R}"
  read_tty "roblox SHARE link:" SHARE_LINK
done

# ==========================
# RESOLVE LINK (PYTHON)
# ==========================
info "Resolving link..."

FINAL_LINK="$(python3 - "$SHARE_LINK" <<'PYCODE'
import sys, requests, time
url=sys.argv[1]
s=requests.Session()
s.headers.update({"User-Agent":"Mozilla/5.0"})
out=None
for _ in range(5):
  try:
    r=s.get(url,timeout=20)
    final=str(r.url)
    if "roblox.com/games/" in final and "privateServerLinkCode=" in final:
      out=final
      break
  except:
    time.sleep(1)
print(out or "")
PYCODE
)"

if [ -z "$FINAL_LINK" ]; then
  err "Gagal resolve link."
  exit 1
fi

ok "Link resolved"

# ==========================
# WRITE CONFIG
# ==========================
step 4 4 "WRITE CONFIG"

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

ok "Config updated  ->  ${DIM}$CONF${R}"

# ==========================
# RUN LUA
# ==========================
echo ""
_bar
echo -e "  ${BCYAN}${BOLD}  Launching winter-rejoin.lua ...${R}"
_bar
echo ""

cd "$DOWNLOAD_OUT"
lua winter-rejoin.lua
