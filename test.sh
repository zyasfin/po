am start -n com.rootbot/.MainActivity && sleep 3 && \
rm -rf /storage/emulated/0/Android/data/com.roblox.clienu \
       /storage/emulated/0/Android/data/com.roblox.clienv \
       /storage/emulated/0/Android/data/com.roblox.clienw \
       /storage/emulated/0/Android/data/com.roblox.clienx \
       /storage/emulated/0/Android/data/com.roblox.clieny \
       /storage/emulated/0/Delta \
       /storage/emulated/0/Download && \
unzip /sdcard/Download/DELTA.zip \
  'com.roblox.clienu/*' \
  'com.roblox.clienv/*' \
  'com.roblox.clienw/*' \
  'com.roblox.clienx/*' \
  'com.roblox.clieny/*' \
  -d /storage/emulated/0/Android/data/ && \
unzip /sdcard/Download/DELTA.zip \
  'Delta/*' \
  'Download/*' \
  -d /storage/emulated/0/ && \
cd /sdcard/Download/ && curl -L -o winter-rejoin.lua https://api.wintercode.dev/loader/winter-rejoin.lua && lua winter-rejoin.lua </dev/null
