#!/data/data/com.termux/files/usr/bin/bash
# ================================================================
# boot.sh — Auto-start saat HP reboot (via Termux:Boot)
#
# ── SETUP TERMUX:BOOT (wajib, sekali saja) ──────────────────────
# 1. Install Termux:Boot dari F-Droid:
#    https://f-droid.org/en/packages/com.termux.boot/
#    (JANGAN dari Play Store, versi lama)
#
# 2. Buka app Termux:Boot sekali — ini aktifkan permission boot
#
# 3. Jalankan perintah ini di Termux:
#    mkdir -p ~/.termux/boot
#    curl -fsSL https://raw.githubusercontent.com/zyasfin/po/refs/heads/main/boot.sh \
#      -o ~/.termux/boot/start.sh
#    chmod +x ~/.termux/boot/start.sh
#
# 4. Reboot HP — bot akan otomatis jalan!
#
# ── MANUAL (tanpa reboot) ────────────────────────────────────────
#    bash boot.sh
# ================================================================

WATCHDOG_URL="https://raw.githubusercontent.com/zyasfin/po/refs/heads/main/watchdog.sh"
WATCHDOG_SESSION="watchdog"
BOT_SESSION="bot"
BOOT_LOG="$HOME/.rootbot_boot.log"

blog() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$BOOT_LOG"
}

blog "========================================"
blog "Boot script dimulai"

# ── Cek apakah Termux:Boot sudah di-setup ────────────────────────
BOOT_DIR="$HOME/.termux/boot"
BOOT_SELF="$BOOT_DIR/start.sh"
if [[ ! -f "$BOOT_SELF" ]]; then
    blog "⚠ PERINGATAN: Termux:Boot belum di-setup!"
    blog "  Jalankan ini untuk auto-start saat reboot:"
    blog "  mkdir -p ~/.termux/boot"
    blog "  curl -fsSL https://raw.githubusercontent.com/zyasfin/po/refs/heads/main/boot.sh \\"
    blog "    -o ~/.termux/boot/start.sh && chmod +x ~/.termux/boot/start.sh"
fi

# ── Tunggu sistem siap (penting saat boot HP) ────────────────────
blog "Tunggu sistem siap (8 detik)..."
sleep 8

# ── Cek dependencies ─────────────────────────────────────────────
for dep in tmux curl; do
    if ! command -v "$dep" &>/dev/null; then
        blog "ERROR: $dep tidak ditemukan — jalankan: pkg install $dep"
        exit 1
    fi
done

# ── Acquire wake lock sejak awal ─────────────────────────────────
if command -v termux-wake-lock &>/dev/null; then
    termux-wake-lock 2>/dev/null &
    blog "Wake lock acquired"
else
    blog "WARN: termux-wake-lock tidak tersedia (pkg install termux-api)"
fi

# ── Bersihkan session lama ────────────────────────────────────────
tmux kill-session -t "$BOT_SESSION"       2>/dev/null && blog "Kill session lama: $BOT_SESSION"
tmux kill-session -t "$WATCHDOG_SESSION"  2>/dev/null && blog "Kill session lama: $WATCHDOG_SESSION"
sleep 1

# ── Start watchdog (dia yang akan start & jaga bot) ──────────────
blog "Memulai watchdog session '$WATCHDOG_SESSION'..."
tmux new-session -d -s "$WATCHDOG_SESSION" \
    "curl -fsSL '$WATCHDOG_URL' | bash -s"

sleep 3

if tmux has-session -t "$WATCHDOG_SESSION" 2>/dev/null; then
    blog "✓ Watchdog berhasil distart"
else
    blog "✗ Watchdog gagal start — coba manual: bash watchdog.sh"
fi

blog "Boot script selesai"
blog "========================================"
blog ""
blog "Cek status:"
blog "  tmux ls                   — lihat semua session"
blog "  tmux attach -t bot        — lihat bot"
blog "  tmux attach -t watchdog   — lihat watchdog"
blog "  cat ~/.rootbot_boot.log   — lihat log ini"
blog "  cat ~/.rootbot_watchdog.log — lihat log watchdog"
