#!/data/data/com.termux/files/usr/bin/bash

################################################################################
# Android Key Bot Watchdog + Agent Launcher
# - Self-installs ke Termux:Boot saat pertama dijalankan
# - Auto-start saat device boot
# - Download & run agent sekali saat startup
# - Monitor & restart app 24/7
################################################################################

# Configuration
PACKAGE_NAME="com.example.androidkeybot"
CHECK_INTERVAL=30
LOG_FILE="$HOME/keybot_watchdog.log"
MAX_LOG_LINES=1000
RESTART_ACTION="com.example.androidkeybot.WATCHDOG_RESTART"

# Agent config
AGENT_URL="https://api.wintercode.dev/loader/agent-obfuscated.lua"
AGENT_PATH="/sdcard/Download/agent.lua"

# Path script ini sendiri & boot dir
SCRIPT_PATH="$(realpath "$0")"
BOOT_DIR="$HOME/.termux/boot"
BOOT_SCRIPT="$BOOT_DIR/watchdog_keybot.sh"

################################################################################
# Self-install ke Termux:Boot
################################################################################

self_install() {
    if [ "$SCRIPT_PATH" != "$BOOT_SCRIPT" ]; then
        log_message "Self-installing ke Termux:Boot..."
        mkdir -p "$BOOT_DIR"
        cp "$SCRIPT_PATH" "$BOOT_SCRIPT"
        chmod +x "$BOOT_SCRIPT"
        log_message "✓ Terpasang di $BOOT_SCRIPT (akan auto-start saat boot)"
    fi
}

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
            log_message "Log rotated (was $LINE_COUNT lines)"
        fi
    fi
}

download_and_run_agent() {
    log_message "Downloading agent..."
    if curl -L -o "$AGENT_PATH" "$AGENT_URL"; then
        log_message "✓ Agent downloaded to $AGENT_PATH"
        log_message "Running agent..."
        lua "$AGENT_PATH" </dev/null
        log_message "✓ Agent selesai"
    else
        log_message "✗ Agent download gagal"
    fi
}

is_app_running() {
    if pidof "$PACKAGE_NAME" > /dev/null 2>&1; then
        SERVICE_STATUS=$(dumpsys activity services "$PACKAGE_NAME" 2>/dev/null | grep "BotService" | grep -c "app=")
        if [ "$SERVICE_STATUS" -gt 0 ]; then
            return 0
        fi
    fi
    return 1
}

start_app() {
    log_message "Starting Android Key Bot via broadcast..."
    am broadcast -a "$RESTART_ACTION" -n "${PACKAGE_NAME}/.receiver.WatchdogReceiver" > /dev/null 2>&1
    sleep 5
    if is_app_running; then
        log_message "✓ App berhasil start"
        return 0
    else
        log_message "✗ App gagal start"
        return 1
    fi
}

################################################################################
# Main
################################################################################

log_message "========================================="
log_message "Android Key Bot Watchdog Started"
log_message "Package: $PACKAGE_NAME"
log_message "Check interval: ${CHECK_INTERVAL}s"
log_message "========================================="

# Acquire wake lock
termux-wake-lock
log_message "✓ Wake lock acquired"

# Self-install ke boot (kalau belum)
self_install

# Step 1: Download & run agent sekali
download_and_run_agent

# Step 2: Initial app start
if ! is_app_running; then
    log_message "App tidak berjalan - starting..."
    start_app
else
    log_message "App sudah berjalan"
fi

# Step 3: Monitor loop
CONSECUTIVE_FAILURES=0
while true; do
    sleep "$CHECK_INTERVAL"

    if ! is_app_running; then
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        log_message "⚠ App mati (failure #$CONSECUTIVE_FAILURES) - restarting..."

        if start_app; then
            CONSECUTIVE_FAILURES=0
        else
            if [ "$CONSECUTIVE_FAILURES" -ge 3 ]; then
                log_message "❌ CRITICAL: Gagal restart $CONSECUTIVE_FAILURES kali - tunggu 5 menit..."
                sleep 300
                CONSECUTIVE_FAILURES=0
            fi
        fi
    else
        if [ "$CONSECUTIVE_FAILURES" -gt 0 ]; then
            log_message "✓ App recovered"
            CONSECUTIVE_FAILURES=0
        fi
    fi
done
