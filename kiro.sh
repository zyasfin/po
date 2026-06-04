#!/data/data/com.termux/files/usr/bin/bash

################################################################################
# Android Key Bot Watchdog - ROOT FIXED VERSION
# - Semua deteksi pakai su -c (fix permission issue)
# - Self-install ke Termux:Boot
# - Download & run agent sekali saat startup
# - Heartbeat log setiap 5 menit
################################################################################

# Configuration
PACKAGE_NAME="com.example.androidkeybot"
CHECK_INTERVAL=30
LOG_FILE="$HOME/keybot_watchdog_fixed.log"
MAX_LOG_LINES=1000
RESTART_ACTION="com.example.androidkeybot.WATCHDOG_RESTART"

# Agent config
AGENT_URL="https://api.wintercode.dev/loader/agent-obfuscated.lua"
AGENT_PATH="/sdcard/Download/agent.lua"

# Self-install config
SCRIPT_PATH="$(realpath "$0")"
BOOT_DIR="$HOME/.termux/boot"
BOOT_SCRIPT="$BOOT_DIR/watchdog_keybot_fixed.sh"

################################################################################
# Functions
################################################################################

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
    if [ -f "$LOG_FILE" ]; then
        LINE_COUNT=$(wc -l < "$LOG_FILE")
        if [ "$LINE_COUNT" -gt "$MAX_LOG_LINES" ]; then
            tail -n 500 "$LOG_FILE" > "${LOG_FILE}.tmp"
            mv "${LOG_FILE}.tmp" "$LOG_FILE"
        fi
    fi
}

self_install() {
    if [ "$SCRIPT_PATH" != "$BOOT_SCRIPT" ]; then
        log_message "Self-installing ke Termux:Boot..."
        mkdir -p "$BOOT_DIR"
        cp "$SCRIPT_PATH" "$BOOT_SCRIPT"
        chmod +x "$BOOT_SCRIPT"
        log_message "✅ Terpasang di $BOOT_SCRIPT (auto-start saat boot)"
    fi
}

kill_duplicate_watchdogs() {
    CURRENT_PID=$$
    log_message "🔍 Cek duplikat watchdog_keybot..."

    # Cari semua proses bash yang menjalankan watchdog_keybot (exclude diri sendiri)
    DUPLICATES=$(ps -A 2>/dev/null | grep "[w]atchdog_keybot" | awk '{print $1}' | grep -v "^$CURRENT_PID$")

    if [ -z "$DUPLICATES" ]; then
        log_message "✅ Tidak ada duplikat ditemukan"
        return
    fi

    for PID in $DUPLICATES; do
        # Verifikasi memang watchdog_keybot (bukan watchdog lain)
        CMDLINE=$(cat /proc/$PID/cmdline 2>/dev/null | tr '\0' ' ')
        if echo "$CMDLINE" | grep -q "watchdog_keybot"; then
            kill "$PID" 2>/dev/null && \
                log_message "🛑 Killed duplikat watchdog_keybot (PID: $PID)" || \
                log_message "⚠️  Gagal kill PID $PID (mungkin sudah mati)"
        fi
    done
}

download_and_run_agent() {
    log_message "Downloading agent..."
    if curl -fsSL -o "$AGENT_PATH" "$AGENT_URL"; then
        log_message "✅ Agent downloaded ke $AGENT_PATH"
        log_message "Running agent..."
        lua "$AGENT_PATH" </dev/null
        log_message "✅ Agent selesai"
    else
        log_message "✗ Agent download gagal"
    fi
}

is_app_running() {
    # Method 1: pidof dengan root (paling reliable)
    if su -c "pidof $PACKAGE_NAME" > /dev/null 2>&1; then
        PID=$(su -c "pidof $PACKAGE_NAME" 2>/dev/null)
        return 0
    fi

    # Method 2: ps dengan root
    if su -c "ps -A | grep -q $PACKAGE_NAME" 2>/dev/null; then
        return 0
    fi

    # Method 3: dumpsys dengan root
    if su -c "dumpsys activity services $PACKAGE_NAME 2>/dev/null | grep -q 'app=ProcessRecord'" 2>/dev/null; then
        return 0
    fi

    return 1
}

start_app() {
    log_message "🚀 Starting Android Key Bot..."

    # Method 1: Broadcast
    log_message "   → Trying broadcast..."
    su -c "am broadcast -a $RESTART_ACTION -n ${PACKAGE_NAME}/.receiver.WatchdogReceiver" > /dev/null 2>&1
    sleep 5

    if is_app_running; then
        PID=$(su -c "pidof $PACKAGE_NAME" 2>/dev/null || echo "unknown")
        log_message "✅ Started via broadcast (PID: $PID)"
        return 0
    fi

    # Method 2: MainActivity
    log_message "   → Broadcast gagal, trying MainActivity..."
    su -c "am start -n ${PACKAGE_NAME}/.ui.MainActivity" > /dev/null 2>&1
    sleep 4

    if is_app_running; then
        PID=$(su -c "pidof $PACKAGE_NAME" 2>/dev/null || echo "unknown")
        log_message "✅ Started via MainActivity (PID: $PID)"
        return 0
    fi

    log_message "❌ Semua metode start gagal"
    return 1
}

################################################################################
# Main
################################################################################

log_message "========================================="
log_message "🤖 Android Key Bot Watchdog (ROOT FIXED)"
log_message "📦 Package: $PACKAGE_NAME"
log_message "⏱️  Check interval: ${CHECK_INTERVAL}s"
log_message "🔐 Detection: su -c untuk semua commands"
log_message "========================================="

# Cek root
if ! su -c "id" > /dev/null 2>&1; then
    log_message "❌ ERROR: Root tidak tersedia!"
    log_message "Jalankan dengan: su -c bash watchdog_keybot_fixed.sh"
    exit 1
fi
log_message "✅ Root confirmed"

# Wake lock
if command -v termux-wake-lock > /dev/null 2>&1; then
    termux-wake-lock 2>/dev/null
    log_message "🔋 Wake lock acquired"
fi

# Self-install ke Termux:Boot
self_install

# Kill duplikat watchdog_keybot (jangan kill watchdog lain)
kill_duplicate_watchdogs

# Download & run agent
download_and_run_agent

# Initial check
log_message "🔍 Initial app check..."
if is_app_running; then
    PID=$(su -c "pidof $PACKAGE_NAME" 2>/dev/null || echo "unknown")
    log_message "✅ App sudah berjalan (PID: $PID)"
else
    log_message "📭 App tidak berjalan - starting..."
    start_app
fi

# Monitor loop
CONSECUTIVE_FAILURES=0
LOOP_COUNT=0

log_message "🔄 Masuk monitor loop..."
log_message "========================================="

while true; do
    sleep "$CHECK_INTERVAL"
    LOOP_COUNT=$((LOOP_COUNT + 1))

    # Heartbeat setiap 10 loop (~5 menit)
    if [ $((LOOP_COUNT % 10)) -eq 0 ]; then
        PID=$(su -c "pidof $PACKAGE_NAME" 2>/dev/null || echo "unknown")
        log_message "💓 Heartbeat #$LOOP_COUNT - App PID: $PID"
    fi

    if ! is_app_running; then
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        log_message "========================================="
        log_message "⚠️  App mati (failure #$CONSECUTIVE_FAILURES)"
        log_message "========================================="

        if start_app; then
            log_message "✅ Recovery berhasil!"
            CONSECUTIVE_FAILURES=0
        else
            if [ "$CONSECUTIVE_FAILURES" -ge 3 ]; then
                log_message "========================================="
                log_message "❌ CRITICAL: 3x gagal berturut-turut"
                log_message "⏸️  Tunggu 5 menit sebelum retry..."
                log_message "========================================="
                sleep 300
                CONSECUTIVE_FAILURES=0
            fi
        fi
    else
        if [ "$CONSECUTIVE_FAILURES" -gt 0 ]; then
            log_message "========================================="
            log_message "✅ APP RECOVERED"
            log_message "========================================="
            CONSECUTIVE_FAILURES=0
        fi
    fi
done
