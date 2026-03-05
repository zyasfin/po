#!/data/data/com.termux/files/usr/bin/bash
# set -e DIHAPUS — diganti manual error trap per-section biar script gak mati tiba-tiba
# tapi tetap exit on unhandled critical error lewat trap ERR

trap 'echo -e "\n\n💥 FATAL ERROR di baris $LINENO — exit code $?" >&2' ERR

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
# SMART ZIP PATH RESOLUTION (FIX BUG --zip DELTA.zip not found)
# Urutan resolve:
#   1. Path as-is (absolute atau relative dari CWD)
#   2. /storage/emulated/0/<nama file>
#   3. /sdcard/<nama file>
###############################################################################

resolve_zip() {
  local input="$1"
  local basename_zip
  basename_zip="$(basename "$input")"

  # Candidate paths
  local candidates=(
    "$input"
    "/storage/emulated/0/$basename_zip"
    "/sdcard/$basename_zip"
    "/storage/emulated/0/Download/$basename_zip"
    "$HOME/$basename_zip"
  )

  for candidate in "${candidates[@]}"; do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  # Tidak ketemu di mana-mana
  echo ""
  return 1
}

RESOLVED_ZIP="$(resolve_zip "$ZIP")" || true

if [ -z "$RESOLVED_ZIP" ]; then
  echo -e "\n❌ ZIP tidak ditemukan! Sudah dicari di:"
  echo "   • $ZIP"
  echo "   • /storage/emulated/0/$(basename "$ZIP")"
  echo "   • /sdcard/$(basename "$ZIP")"
  echo "   • /storage/emulated/0/Download/$(basename "$ZIP")"
  exit 1
fi

ZIP="$RESOLVED_ZIP"

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

###############################################################################
# DYNAMIC PROGRESS — animasi "masih jalan" dengan bounce bar + elapsed timer
# Dipanggil: run_progress "judul" <detik_estimasi> command args...
# Semua function asli TETAP, ini function TAMBAHAN
###############################################################################

run_progress() {
  local title="$1"
  local est="$2"   # estimasi detik (untuk scaling bounce, boleh 0)
  shift 2

  mkdir -p "$(dirname "$LOGF")"
  : > "$LOGF"

  # Jalankan command di background
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
    # Bounce block
    local bar=""
    for ((col=0; col<BAR_W; col++)); do
      if [ $col -eq $pos ]; then
        bar+="▓"
      else
        bar+="░"
      fi
    done

    # Spinner frame
    local sp="${frames[$((fi % ${#frames[@]}))]}"
    fi=$((fi+1))

    # Elapsed
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))
    printf "\r  %s [%s] %02d:%02d  %-30s" "$sp" "$bar" "$mins" "$secs" "$title"

    # Bounce direction
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
echo "📦 ZIP: $ZIP"
sleep 1

###############################################################################
# STEP 0 — DEPENDENCY + TMUX BOT
###############################################################################

step 5 "Installing dependencies"
run_progress "pkg update + install deps" 30 \
  bash -c 'pkg update -y && pkg install -y tmux tesseract termux-api python lua53 sqlite sed unzip curl'

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

run_progress "Extracting ZIP" 15 unzip -q "$ZIP" -d "$TMP"

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
run_progress "pip install requests" 20 python3 -m pip install -U requests

if [ -z "$DEVICE_LABEL" ]; then
  read_tty "device_label (contoh: L05): " DEVICE_LABEL
fi

if [ -z "$SHARE_LINK" ]; then
  read_tty "roblox SHARE link: " SHARE_LINK
fi

step 65 "Resolving Roblox link"

FINAL_LINK="$(SHARE_LINK="$SHARE_LINK" python3 - <<'PYEOF'
import re, sys, time, requests, os
url = os.environ["SHARE_LINK"]
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
# WRITE CONFIG (ASLI)
###############################################################################

step 80 "Writing config"

mkdir -p "$(dirname "$CONF")"
touch "$CONF"

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
