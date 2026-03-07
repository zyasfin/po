#!/bin/bash

SRC="/storage/emulated/0/FIXTRADE.txt"

DESTINATIONS=(
  "/storage/emulated/0/Delta/Autoexecute/FIXTRADE.txt"
  "/storage/emulated/0/Android/data/com.roblox.clienu/files/gloop/external/Autoexecute/FIXTRADE.txt"
  "/storage/emulated/0/Android/data/com.roblox.clienv/files/gloop/external/Autoexecute/FIXTRADE.txt"
  "/storage/emulated/0/Android/data/com.roblox.clienw/files/gloop/external/Autoexecute/FIXTRADE.txt"
  "/storage/emulated/0/Android/data/com.roblox.clienx/files/gloop/external/Autoexecute/FIXTRADE.txt"
  "/storage/emulated/0/Android/data/com.roblox.clieny/files/gloop/external/Autoexecute/FIXTRADE.txt"
)

if [ ! -f "$SRC" ]; then
  echo "[ERROR] Source file not found: $SRC"
  exit 1
fi

for DEST in "${DESTINATIONS[@]}"; do
  DIR=$(dirname "$DEST")
  mkdir -p "$DIR" && cp "$SRC" "$DEST" \
    && echo "[OK] Copied to $DEST" \
    || echo "[FAIL] Failed to copy to $DEST"
done
