#!/data/data/com.termux/files/usr/bin/bash
# ================================================================
# watchdog.sh — Monitor & auto-restart bot kalau crash
# Dijalankan otomatis oleh boot.sh / auto.sh
# ================================================================

BOT_URL="https://raw.githubusercontent.com/zyasfin/po/refs/heads/main/bot.sh"
BOT_SESSION="bot"
CHECK_INTERVAL=300     # cek tiap 5 menit
RESTART_DELAY=5        # tunggu 5 detik sebelum restart
LOG_FILE="$HOME/.rootbot_watchdog.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; DIM='\033[2m'; NC='\033[0m'

restart_count=0

wlog() {
    local color=$1 tag=$2 msg=$3
    local ts=$(date '+%H:%M:%S')
    echo -e "${DIM}[$ts]${NC} ${color}[$tag]${NC} $msg"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$tag] $msg" >> "$LOG_FILE"
}

is_bot_alive() {
    tmux has-session -t "$BOT_SESSION" 2>/dev/null
}

start_bot() {
    tmux kill-session -t "$BOT_SESSION" 2>/dev/null
    sleep 1
    tmux new-session -d -s "$BOT_SESSION" \
        "curl -fsSL '$BOT_URL' | bash -s"
    sleep 3
    is_bot_alive
}

# ── Wake lock ────────────────────────────────────────────────────
if command -v termux-wake-lock &>/dev/null; then
    termux-wake-lock 2>/dev/null &
fi

cleanup() {
    echo ""
    wlog "$YELLOW" "WATCHDOG" "Watchdog dihentikan"
    command -v termux-wake-unlock &>/dev/null && termux-wake-unlock 2>/dev/null
    exit 0
}
trap cleanup SIGINT SIGTERM

# ── Banner ────────────────────────────────────────────────────────
echo -e "${CYAN}"
echo "  ┌──────────────────────────────┐"
echo "  │  🐕 WATCHDOG aktif           │"
echo "  │  Check tiap 5 menit          │"
echo "  │  Ctrl+C untuk stop           │"
echo "  └──────────────────────────────┘"
echo -e "${NC}"
wlog "$CYAN" "WATCHDOG" "Memulai — target session: '$BOT_SESSION'"

# ── Start bot pertama kali ────────────────────────────────────────
if ! is_bot_alive; then
    wlog "$YELLOW" "WATCHDOG" "Bot belum jalan, start sekarang..."
    if start_bot; then
        wlog "$GREEN" "WATCHDOG" "Bot berhasil distart"
    else
        wlog "$RED" "WATCHDOG" "Gagal start bot, akan retry"
    fi
else
    wlog "$GREEN" "WATCHDOG" "Bot sudah jalan di session '$BOT_SESSION'"
fi

# ── Monitor loop ──────────────────────────────────────────────────
while true; do
    sleep $CHECK_INTERVAL

    if ! is_bot_alive; then
        restart_count=$((restart_count + 1))
        wlog "$YELLOW" "WATCHDOG" "⚠ Bot mati! Restart #${restart_count}"
        sleep $RESTART_DELAY

        if start_bot; then
            wlog "$GREEN" "WATCHDOG" "✓ Restart berhasil (#${restart_count})"
        else
            wlog "$RED" "WATCHDOG" "✗ Restart gagal, retry 5 menit lagi"
        fi
    else
        wlog "$GREEN" "WATCHDOG" "Bot OK ✓"
    fi
done
