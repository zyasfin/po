#!/data/data/com.termux/files/usr/bin/bash
# ================================================================
# RootBot - Termux Script
# Usage: bash bot.sh --device "Nama Device"
#        atau: tmux new-session -d -s bot "bash bot.sh --device 'HP Kantor'"
# ================================================================

# ── KONFIGURASI - EDIT BAGIAN INI ────────────────────────────────

API_URL="https://montanaweb.xyz/keyproxy/api/v1/241ba761-e303-4805-a299-bbc5cd5f9b4d/submit"
LAST_KEY_URL="https://montanaweb.xyz/keyproxy/api/v1/241ba761-e303-4805-a299-bbc5cd5f9b4d/last-key"
KEEPALIVE_URL="https://montanaweb.xyz/keyproxy/dashboard.php"
KEEPALIVE_INTERVAL=300   # ping keepalive tiap 5 menit

# Target package yang di-kill setelah dapat key
TARGET_PACKAGES=(
    "com.target.package1"    # ganti dengan package name app target
    "com.target.package2"    # tambah/hapus sesuai kebutuhan
)

# Lokasi file license yang ditulis setelah dapat key
# Format: "package_index:path" - index sesuai TARGET_PACKAGES di atas
LICENSE_TARGETS=(
    "0:/data/data/com.target.package1/files/license.key"
    "0:/data/data/com.target.package1/cache/auth.dat"
    "1:/data/data/com.target.package2/files/license.key"
)

# ── JANGAN EDIT DI BAWAH INI ─────────────────────────────────────

DEVICE_NAME=""
LAST_CLIP=""
LAST_POPUP_TIME=0
POLL_INTERVAL=2          # cek clipboard tiap 2 detik normal
LONG_POLL_INTERVAL=900   # 15 menit setelah dapat popup (900 detik)
NO_POPUP_COUNT=0
NO_POPUP_THRESHOLD=1     # setelah 1x dapat popup, naikkan interval
CURRENT_INTERVAL=$POLL_INTERVAL
LAST_KEY=""

# ── Colors ────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
NC='\033[0m'

# ── Parse arguments ───────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --device|-d)
            DEVICE_NAME="$2"
            shift 2
            ;;
        --device=*)
            DEVICE_NAME="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -z "$DEVICE_NAME" ]]; then
    echo -e "${RED}ERROR: Device name wajib diisi!${NC}"
    echo -e "Usage: bash bot.sh --device \"Nama Device\""
    echo -e "       tmux new-session -d -s bot \"bash bot.sh --device 'HP Kantor'\""
    exit 1
fi

# ── Logging ───────────────────────────────────────────────────────
log() {
    local level=$1
    local msg=$2
    local time=$(date '+%H:%M:%S')
    case $level in
        INFO)  echo -e "${DIM}[$time]${NC} ${WHITE}$msg${NC}" ;;
        OK)    echo -e "${DIM}[$time]${NC} ${GREEN}OK${NC} $msg" ;;
        WARN)  echo -e "${DIM}[$time]${NC} ${YELLOW}WARN${NC} $msg" ;;
        ERROR) echo -e "${DIM}[$time]${NC} ${RED}ERROR${NC} $msg" ;;
        KEY)   echo -e "${DIM}[$time]${NC} ${CYAN}KEY${NC} $msg" ;;
    esac
}

# ── Get clipboard ─────────────────────────────────────────────────
get_clipboard() {
    termux-clipboard-get 2>/dev/null || echo ""
}

# ── Cek apakah string adalah URL ─────────────────────────────────
is_url() {
    [[ "$1" =~ ^https?:// ]]
}

# ── Hit API dapat key ─────────────────────────────────────────────
fetch_key() {
    local link="$1"
    local response

    response=$(curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "User-Agent: RootBot-Termux/1.0" \
        --connect-timeout 10 \
        --max-time 30 \
        -d "{\"link\":\"$link\",\"device\":\"$DEVICE_NAME\",\"device_id\":\"${DEVICE_NAME}_termux\"}" \
        2>/dev/null)

    if [[ -z "$response" ]]; then
        log ERROR "No response from API"
        return 1
    fi

    # Parse key dari JSON response
    local key
    key=$(echo "$response" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)
    local status
    status=$(echo "$response" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

    if [[ "$status" == "success" && -n "$key" ]]; then
        LAST_KEY="$key"
        log KEY "Key didapat: $key"
        return 0
    else
        log ERROR "API gagal: $response"
        return 1
    fi
}

# ── Tulis file license ────────────────────────────────────────────
write_license() {
    local key="$1"
    local written=0

    for target in "${LICENSE_TARGETS[@]}"; do
        local path="${target#*:}"
        local dir
        dir=$(dirname "$path")

        # Buat direktori kalau belum ada
        su -c "mkdir -p '$dir' 2>/dev/null"

        # Tulis key ke file license
        if su -c "echo '$key' > '$path' && chmod 644 '$path'"; then
            log OK "License ditulis: $path"
            written=$((written + 1))
        else
            log WARN "Gagal tulis: $path"
        fi
    done

    return $written
}

# ── Kill target packages ──────────────────────────────────────────
kill_packages() {
    for pkg in "${TARGET_PACKAGES[@]}"; do
        if su -c "am force-stop '$pkg' 2>/dev/null"; then
            log OK "Kill: $pkg"
        else
            log WARN "Gagal kill: $pkg"
        fi
        sleep 0.5
    done
}

# ── Keepalive ping ────────────────────────────────────────────────
keepalive() {
    curl -s "$KEEPALIVE_URL" \
        -H "User-Agent: RootBot-Keepalive/1.0" \
        --connect-timeout 5 \
        --max-time 10 \
        -o /dev/null 2>/dev/null
    log INFO "Keepalive ping sent"
}

# ── Background keepalive loop ─────────────────────────────────────
start_keepalive_loop() {
    while true; do
        sleep $KEEPALIVE_INTERVAL
        keepalive
    done &
    KEEPALIVE_PID=$!
    log INFO "Keepalive loop started (PID: $KEEPALIVE_PID)"
}

# ── Handle link baru dari clipboard ──────────────────────────────
handle_new_link() {
    local link="$1"
    log INFO "Link baru: $link"

    # Hit API
    if fetch_key "$link"; then
        # Tulis license ke semua target
        write_license "$LAST_KEY"

        # Kill semua package target
        sleep 1
        kill_packages

        # Catat waktu dapat popup terakhir
        LAST_POPUP_TIME=$(date +%s)
        NO_POPUP_COUNT=$((NO_POPUP_COUNT + 1))

        # Setelah dapat popup, naikkan interval jadi 15 menit
        CURRENT_INTERVAL=$LONG_POLL_INTERVAL
        log INFO "Interval dinaikkan ke ${LONG_POLL_INTERVAL}s (15 menit)"
        log OK "Selesai! Menunggu ${LONG_POLL_INTERVAL}s sebelum cek lagi..."
    else
        log ERROR "Gagal dapat key, akan retry di loop berikutnya"
    fi
}

# ── Cleanup on exit ───────────────────────────────────────────────
cleanup() {
    log WARN "Bot dihentikan"
    [[ -n "$KEEPALIVE_PID" ]] && kill "$KEEPALIVE_PID" 2>/dev/null
    exit 0
}
trap cleanup SIGINT SIGTERM

# ── Main ──────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        RootBot Termux          ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════╝${NC}"
    echo ""
    log INFO "Device  : $DEVICE_NAME"
    log INFO "API     : $API_URL"
    log INFO "Targets : ${#TARGET_PACKAGES[@]} package, ${#LICENSE_TARGETS[@]} lokasi"
    echo ""

    # Cek dependencies
    if ! command -v termux-clipboard-get &>/dev/null; then
        log ERROR "termux-clipboard-get tidak ditemukan!"
        log ERROR "Jalankan: pkg install termux-api"
        exit 1
    fi

    if ! command -v curl &>/dev/null; then
        log ERROR "curl tidak ditemukan!"
        log ERROR "Jalankan: pkg install curl"
        exit 1
    fi

    # Cek root
    if ! su -c "echo ok" &>/dev/null; then
        log ERROR "Root tidak tersedia! Grant izin di Magisk."
        exit 1
    fi

    log OK "Semua dependency OK"
    log INFO "Memulai clipboard listener..."
    echo ""

    # Init clipboard baseline
    LAST_CLIP=$(get_clipboard)

    # Start keepalive di background
    start_keepalive_loop

    # Main loop
    while true; do
        sleep $CURRENT_INTERVAL

        local current_clip
        current_clip=$(get_clipboard)

        # Skip kalau clipboard kosong atau sama
        if [[ -z "$current_clip" || "$current_clip" == "$LAST_CLIP" ]]; then
            continue
        fi

        # Ada perubahan di clipboard
        LAST_CLIP="$current_clip"

        # Cek apakah isinya URL
        if is_url "$current_clip"; then
            handle_new_link "$current_clip"
        fi

        # Reset interval ke normal kalau sudah lama tidak ada popup
        local now=$(date +%s)
        local elapsed=$((now - LAST_POPUP_TIME))
        if [[ $CURRENT_INTERVAL -eq $LONG_POLL_INTERVAL && $elapsed -gt $LONG_POLL_INTERVAL ]]; then
            CURRENT_INTERVAL=$POLL_INTERVAL
            log INFO "Interval kembali normal (${POLL_INTERVAL}s)"
        fi
    done
}

main
