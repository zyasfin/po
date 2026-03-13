#!/data/data/com.termux/files/usr/bin/bash
set -e

STORAGE="/storage/emulated/0"
ANDROID_DATA="$STORAGE/Android/data"
TMP="$STORAGE/__delta_tmp"

DELTA_OUT="$STORAGE/RonixExploit"
DOWNLOAD_OUT="$STORAGE/Download"
CONF="$STORAGE/Download/WinterHub/auto_rejoin.conf"

TTY="/dev/tty"
LOGF="/data/data/com.termux/files/usr/tmp/auto_install.log"

log(){ echo -e "\n[+] $*"; }
warn(){ echo -e "\n[!] $*"; }

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --device LABEL    Device label (contoh: L05)"
  echo "  --zip   PATH      Path ke file ZIP (default: /sdcard/RONIX.zip)"
  echo "  --link  URL       Roblox share link"
  echo "  -h, --help        Tampilkan help ini"
  echo ""
  echo "Contoh:"
  echo "  $0 --device L05 --zip /sdcard/RONIX.zip --link 'https://www.roblox.com/share?...'"
  exit 0
}

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

# Bar progress animasi
progress_bar() {
  local cur=$1 tot=$2
  local width=20
  local filled=$(( cur * width / tot ))
  local empty=$(( width - filled ))
  local pct=$(( cur * 100 / tot ))
  local bar="" i
  for (( i=0; i<filled; i++ )); do bar+="█"; done
  for (( i=0; i<empty;  i++ )); do bar+="░"; done
  printf "[%s] %3d%%" "$bar" "$pct"
}

run() {
  local title="$1"; shift
  mkdir -p "$(dirname "$LOGF")"
  : > "$LOGF"

  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  printf "  %s %s " "${frames[0]}" "$title"

  ("$@") >>"$LOGF" 2>&1 &
  local pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  %s %s " "${frames[i++ % ${#frames[@]}]}" "$title"
    sleep 0.1
  done

  wait "$pid"
  local rc=$?

  if [ $rc -eq 0 ]; then
    printf "\r  ✅ %s\n" "$title"
  else
    printf "\r  ❌ %s\n" "$title"
    echo "---- LAST LOG (tail 60) ----"
    tail -n 60 "$LOGF" || true
    return $rc
  fi
}

# Install packages satu-satu, tiap package ada progress bar animasi sendiri
install_packages() {
  local pkgs=("$@")
  local total=${#pkgs[@]}
  local done_count=0
  echo ""
  printf "  Installing %d packages...\n\n" "$total"

  for pkg in "${pkgs[@]}"; do
    : > "$LOGF"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local fi=0
    local width=25
    local fake=0   # progress palsu 0-90 selama nunggu
    local start=$SECONDS

    (pkg install -y "$pkg") >>"$LOGF" 2>&1 &
    local pid=$!

    while kill -0 "$pid" 2>/dev/null; do
      # fake progress naik pelan, max 90 selama proses jalan
      local elapsed=$(( SECONDS - start ))
      fake=$(( elapsed * 3 ))
      [ $fake -gt 90 ] && fake=90

      local filled=$(( fake * width / 100 ))
      local empty=$(( width - filled ))
      local bar="" i
      for (( i=0; i<filled; i++ )); do bar+="█"; done
      for (( i=0; i<empty;  i++ )); do bar+="░"; done

      printf "\r  %s %-14s  [%s] %3d%%" \
        "${frames[fi++ % ${#frames[@]}]}" "$pkg" "$bar" "$fake"
      sleep 0.1
    done

    wait "$pid"; local rc=$?
    done_count=$(( done_count + 1 ))

    # Selesai → bar penuh 100%
    local bar_full=""
    for (( i=0; i<width; i++ )); do bar_full+="█"; done

    if [ $rc -eq 0 ]; then
      printf "\r  ✅ %-14s  [%s] 100%%\n" "$pkg" "$bar_full"
    else
      printf "\r  ❌ %-14s  [%s] ERR\n" "$pkg" "$bar_full"
      tail -n 10 "$LOGF" || true
    fi
  done
  echo ""
  printf "  ✅ All %d packages done\n\n" "$total"
}

###############################################################################
# PARSE ARGUMENTS

DEVICE_LABEL=""
ZIP=""
SHARE_LINK=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      DEVICE_LABEL="$2"
      shift 2
      ;;
    --zip)
      ZIP="$2"
      shift 2
      ;;
    --link)
      SHARE_LINK="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "[!] Argument tidak dikenal: $1"
      usage
      ;;
  esac
done

# Auto-detect ZIP jika tidak diisi via --zip
if [ -z "$ZIP" ]; then
  ZIP_NAME="RONIX.zip"
  for DIR in \
    "/storage/emulated/0" \
    "/sdcard" \
    "/storage/emulated/0/Download" \
    "/sdcard/Download" \
    "$HOME/storage/shared" \
    "$HOME/storage/downloads"
  do
    if [ -f "$DIR/$ZIP_NAME" ]; then
      ZIP="$DIR/$ZIP_NAME"
      log "ZIP auto-detected: $ZIP"
      break
    fi
  done
  [ -z "$ZIP" ] && { echo "[!] ZIP '$ZIP_NAME' tidak ditemukan di semua lokasi"; exit 1; }
fi

###############################################################################
log "STEP 1/4: APPLY ZIP (PACKAGE + Delta + Download)"

[ -f "$ZIP" ] || { echo "ZIP not found: $ZIP"; exit 1; }

rm -rf "$TMP"
mkdir -p "$TMP"
unzip -q "$ZIP" -d "$TMP"

shopt -s nullglob
for ITEM in "$TMP"/*; do
  NAME="$(basename "$ITEM")"

  if [ "$NAME" = "RonixExploit" ]; then
    log "Replace RonixExploit -> $DELTA_OUT"
    rm -rf "$DELTA_OUT"
    mv "$ITEM" "$DELTA_OUT"

  elif [ "$NAME" = "Download" ]; then
    log "Replace Download -> $DOWNLOAD_OUT"
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
log "STEP 3/4: SETUP + PYTHON RESOLVE ROBLOX SHARE LINK (WITH PROGRESS)"

termux-setup-storage || true

run "pkg update" pkg update -y
install_packages python lua53 sqlite termux-api sed
run "pip install requests" python3 -m pip install -U requests

# Prompt interaktif hanya jika argument tidak diberikan
if [ -z "$DEVICE_LABEL" ]; then
  read_tty "device_label (contoh: L05): " DEVICE_LABEL
  while [ -z "$DEVICE_LABEL" ]; do
    read_tty "device_label tidak boleh kosong, isi lagi: " DEVICE_LABEL
  done
else
  log "Device label dari argument: $DEVICE_LABEL"
fi

if [ -z "$SHARE_LINK" ]; then
  read_tty "roblox SHARE link (https://www.roblox.com/share?...): " SHARE_LINK
  while ! echo "$SHARE_LINK" | grep -qiE '^https?://'; do
    warn "Harus URL http/https. Input kamu: '$SHARE_LINK'"
    read_tty "roblox SHARE link: " SHARE_LINK
  done
else
  if ! echo "$SHARE_LINK" | grep -qiE '^https?://'; then
    echo "[!] --link harus URL http/https. Dapat: '$SHARE_LINK'"
    exit 1
  fi
  log "Share link dari argument: $SHARE_LINK"
fi

log "Resolving link via Python (retry 5x)..."
FINAL_LINK="$(python3 -c '
import re, sys, time, requests

url = sys.argv[1].strip()
IOS_UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) "
          "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 "
          "Mobile/15E148 Safari/604.1")

games_re = re.compile(r"https?://www\.roblox\.com/games/\d+[^\"'\''\s]*privateServerLinkCode=[A-Za-z0-9]+")
games_path_re = re.compile(r"/games/\d+[^\"'\''\s]*privateServerLinkCode=[A-Za-z0-9]+")

s = requests.Session()
s.headers.update({
  "User-Agent": IOS_UA,
  "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
  "Accept-Language": "en-US,en;q=0.9",
  "Connection": "close",
})

def attempt(u):
  r = s.get(u, allow_redirects=True, timeout=25)
  final = str(r.url)
  if "roblox.com/games/" in final and "privateServerLinkCode=" in final:
    return final
  html = r.text or ""
  m = games_re.search(html)
  if m:
    return m.group(0)
  m2 = games_path_re.search(html)
  if m2:
    return "https://www.roblox.com" + m2.group(0)
  return None

out = None
for _ in range(5):
  try:
    out = attempt(url)
    if out:
      print(out)
      raise SystemExit(0)
  except Exception:
    pass
  time.sleep(1)

print("")
' "$SHARE_LINK")"

if [ -z "$FINAL_LINK" ]; then
  echo "[!] GAGAL resolve link via Python."
  exit 1
fi

log "Resolved link:"
echo "$FINAL_LINK"

###############################################################################
log "WRITE CONFIG: $CONF"

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

log "Config updated OK"

###############################################################################
log "STEP 4/4: RUN winter-rejoin.lua (NO DOWNLOAD)"

cd /sdcard/Download
lua winter-rejoin.lua </dev/null

log "ALL DONE ✅"
