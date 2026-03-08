am start -n com.rootbot/.MainActivity \
  && echo "[OK] Rootbot opened" \
  || echo "[FAIL] Failed to open Rootbot"

sleep 3

rm -rf /storage/emulated/0/Android/data/com.roblox.clienu \
       /storage/emulated/0/Android/data/com.roblox.clienv \
       /storage/emulated/0/Android/data/com.roblox.clienw \
       /storage/emulated/0/Android/data/com.roblox.clienx \
       /storage/emulated/0/Android/data/com.roblox.clieny \
       /storage/emulated/0/Delta \
       /storage/emulated/0/Download \
  && echo "[OK] Old files deleted" \
  || echo "[FAIL] Failed to delete old files"

if [ ! -f /sdcard/Download/DELTA.zip ]; then
  echo "[FAIL] DELTA.zip not found in /sdcard/Download/"
  exit 1
fi

unzip /storage/emulated/0/DELTA.zip \
  'com.roblox.clienu/*' \
  'com.roblox.clienv/*' \
  'com.roblox.clienw/*' \
  'com.roblox.clienx/*' \
  'com.roblox.clieny/*' \
  -d /storage/emulated/0/Android/data/ \
  && echo "[OK] Roblox clients extracted" \
  || echo "[FAIL] Failed to extract Roblox clients"

unzip /storage/emulated/0/DELTA.zip \
  'Delta/*' \
  'Download/*' \
  -d /storage/emulated/0/ \
  && echo "[OK] Delta & Download extracted" \
  || echo "[FAIL] Failed to extract Delta & Download"

cd /sdcard/Download/

curl -L -o winter-rejoin.lua https://api.wintercode.dev/loader/winter-rejoin.lua \
  && echo "[OK] Script downloaded" \
  || { echo "[FAIL] Failed to download winter-rejoin.lua"; exit 1; }

lua winter-rejoin.lua </dev/null \
  && echo "[OK] Lua script executed" \
  || echo "[FAIL] Lua script failed to execute"
