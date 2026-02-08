#!/data/data/com.termux/files/usr/bin/bash
set -e

STORAGE="/storage/emulated/0"
TTY="/dev/tty"
LOGF="/data/data/com.termux/files/usr/tmp/auto_tools.log"

TOOLS_URL="http://103.121.122.205:8080/s/S8gC7cmfegDJFfm/download"
TOOLS_ZIP="$STORAGE/TOOLS.zip"
EXTRACT_DIR="$STORAGE"

CONF="$STORAGE/Download/WinterHub/auto_rejoin.conf"

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
    echo "---- LAST LOG (tail 80) ----"
    tail -n 80 "$LOGF" || true
    return $rc
  fi
}

download_tools_zip() {
  rm -f "$TOOLS_ZIP"

  # Prefer python requests (paling stabil di Termux)
  if command -v python3 >/dev/null 2>&1; then
    run "Download TOOLS.zip (python)" python3 - <<PY
import sys, requests
url = "${TOOLS_URL}"
out = "${TOOLS_ZIP}"
r = requests.get(url, stream=True, timeout=60)
r.raise_for_status()
with open(out, "wb") as f:
  for chunk in r.iter_content(chunk_size=1024*256):
    if chunk:
      f.write(chunk)
print("saved:", out)
PY
    return 0
  fi

  # fallback curl / wget
  if command -v curl >/dev/null 2>&1; then
    run "Download TOOLS.zip (curl)" curl -L --fail -o "$TOOLS_ZIP" "$TOOLS_URL"
    return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    run "Download TOOLS.zip (wget)" wget -O "$TOOLS_ZIP" "$TOOLS_URL"
    return 0
  fi

  echo "[!] Tidak ada python3/curl/wget untuk download."
  return 1
}

install_apk_one() {
  local apk="$1"
  local name="$(basename "$apk")"

  # root path (paling mulus)
  if command -v su >/dev/null 2>&1; then
    echo "[*] Install (root) $name"
    if su -c "pm install -r \"$apk\"" >/dev/null 2>&1; then
      echo "    ✅ OK: $name"
      return 0
    else
      echo "    ❌ FAIL (root pm install): $name"
      return 1
    fi
  fi

  # non-root: coba pm langsung
  echo "[*] Install (pm) $name"
  if pm install -r "$apk" >/dev/null 2>&1; then
    echo "    ✅ OK: $name"
    return 0
  fi

  # fallback: buka installer UI
  warn "pm install ditolak. Buka installer untuk $name (tap Install manual)."
  termux-open "$apk" >/dev/null 2>&1 || true
  read_tty "Kalau sudah selesai install $name, ketik ENTER untuk lanjut..." _DUMMY
  return 0
}

###############################################################################
log "STEP 0: TERMUX SETUP (deps + permissions)"
termux-setup-storage || true
run "pkg update" pkg update -y
run "install deps (python/unzip/lua/sqlite/termux-api/sed)" pkg install -y python unzip lua53 sqlite termux-api sed
run "pip install requests" python3 -m pip install -U requests

###############################################################################
log "STEP 1: DOWNLOAD TOOLS.zip"
download_tools_zip
[ -f "$TOOLS_ZIP" ] || { echo "[!] TOOLS.zip tidak ada: $TOOLS_ZIP"; exit 1; }
log "Downloaded: $TOOLS_ZIP"

###############################################################################
log "STEP 2: EXTRACT TOOLS.zip to $EXTRACT_DIR"
run "Extract TOOLS.zip" unzip -o "$TOOLS_ZIP" -d "$EXTRACT_DIR"

###############################################################################
log "STEP 3: INSTALL APK nomercy1..5 (log per APK)"

# cari apk nomercy1..5 di hasil extract (di mana pun)
FOUND=0
for i in 1 2 3 4 5; do
  apk="$(find "$EXTRACT_DIR" -maxdepth 6 -type f -iname "nomercy${i}*.apk" | head -n 1 || true)"
  if [ -z "$apk" ]; then
    warn "nomercy${i}.apk tidak ketemu di hasil extract"
    continue
  fi
  FOUND=1
  install_apk_one "$apk" || true
done

if [ "$FOUND" -eq 0 ]; then
  warn "Tidak menemukan APK nomercy1..5 sama sekali."
fi

###############################################################################
log "STEP 4: INPUT + PYTHON RESOLVE ROBLOX SHARE LINK + WRITE CONF"

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
s.headers.update({"User-Agent": IOS_UA, "Accept":"text/html,*/*", "Connection":"close"})
def attempt(u):
  r = s.get(u, allow_redirects=True, timeout=25)
  final = str(r.url)
  if "roblox.com/games/" in final and "privateServerLinkCode=" in final:
    return final
  html = r.text or ""
  m = games_re.search(html)
  if m: return m.group(0)
  m2 = games_path_re.search(html)
  if m2: return "https://www.roblox.com" + m2.group(0)
  return None

out=None
for _ in range(5):
  try:
    out = attempt(url)
    if out:
      print(out); sys.exit(0)
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

log "Write config: $CONF"
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
log "STEP 5: RUN WINTER"
cd /sdcard/Download
lua winter-rejoin.lua </dev/null

log "ALL DONE ✅"
