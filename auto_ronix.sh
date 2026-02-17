#!/data/data/com.termux/files/usr/bin/bash
set -e

STORAGE="/storage/emulated/0"
ANDROID_DATA="$STORAGE/Android/data"
ZIP="$STORAGE/RONIX.zip"
TMP="$STORAGE/__delta_tmp"

DELTA_OUT="$STORAGE/RonixExploit"
DOWNLOAD_OUT="$STORAGE/Download"
CONF="$STORAGE/Download/WinterHub/auto_rejoin.conf"

TTY="/dev/tty"
LOGF="/data/data/com.termux/files/usr/tmp/auto_install.log"

log(){ echo -e "\n[+] $*"; }
warn(){ echo -e "\n[!] $*"; }

read_tty() {
  # usage: read_tty "Prompt: " VAR
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
  # usage: run "title" command...
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
    echo "---- LAST LOG (tail 60) ----"
    tail -n 60 "$LOGF" || true
    return $rc
  fi
}

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
    # sesuai request kamu: replace total Download
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

# storage permission (aman kalau sudah pernah)
termux-setup-storage || true

# install deps pakai progress spinner
run "pkg update" pkg update -y
run "install python + lua + sqlite + termux-api + sed" pkg install -y python lua53 sqlite termux-api sed
run "pip install requests" python3 -m pip install -U requests

DEVICE_LABEL=""
SHARE_LINK=""

read_tty "device_label (contoh: L05): " DEVICE_LABEL
while [ -z "$DEVICE_LABEL" ]; do
  read_tty "device_label tidak boleh kosong, isi lagi: " DEVICE_LABEL
done

read_tty "roblox SHARE link (https://www.roblox.com/share?...): " SHARE_LINK
while ! echo "$SHARE_LINK" | grep -qiE '^https?://'; do
  warn "Harus URL http/https. Input kamu: '$SHARE_LINK'"
  read_tty "roblox SHARE link: " SHARE_LINK
done

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
