#!/data/data/com.termux/files/usr/bin/bash
# ================================================================
# RootBot - Termux Script
# Usage  : bash bot.sh --device "Nama Device"
# Tmux   : tmux new-session -d -s bot "bash bot.sh --device 'HP Kantor'"
# ================================================================

# ════════════════════════════════════════════════════════════════
# KONFIGURASI - EDIT BAGIAN INI
# ════════════════════════════════════════════════════════════════

API_URL="https://montanaweb.xyz/keyproxy/api/v1/241ba761-e303-4805-a299-bbc5cd5f9b4d/submit"
KEEPALIVE_URL="https://montanaweb.xyz/keyproxy/dashboard.php"
KEEPALIVE_INTERVAL=300      # ping keepalive tiap 5 menit (detik)

# Package yang di-kill setelah dapat key (tambah/hapus sesuai kebutuhan)
TARGET_PACKAGES=(
    "com.roblox.clienu"
    "com.roblox.clienv"
    "com.roblox.clienw"
    "com.roblox.clienx"
    "com.roblox.clieny"
)

# Lokasi file license yang ditulis setelah dapat key
# Semua path ini akan diisi key yang sama
LICENSE_PATHS=(
    "/storage/emulated/0/Delta/Internals/Cache/license"
    "/storage/emulated/0/Android/data/com.roblox.clienu/files/gloop/external/Internals/Cache/license"
    "/storage/emulated/0/Android/data/com.roblox.clienv/files/gloop/external/Internals/Cache/license"
    "/storage/emulated/0/Android/data/com.roblox.clienw/files/gloop/external/Internals/Cache/license"
    "/storage/emulated/0/Android/data/com.roblox.clienx/files/gloop/external/Internals/Cache/license"
    "/storage/emulated/0/Android/data/com.roblox.clieny/files/gloop/external/Internals/Cache/license"   
)

# ════════════════════════════════════════════════════════════════
# JANGAN EDIT DI BAWAH INI
# ════════════════════════════════════════════════════════════════

POLL_INTERVAL=2             # cek clipboard tiap 2 detik (normal)
LONG_POLL_INTERVAL=900      # 15 menit setelah dapat popup
CURRENT_INTERVAL=$POLL_INTERVAL
LAST_CLIP=""
LAST_POPUP_TIME=0
KEEPALIVE_PID=""
DEVICE_NAME=""

# Colors
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
        --device|-d)   DEVICE_NAME="$2"; shift 2 ;;
        --device=*)    DEVICE_NAME="${1#*=}"; shift ;;
        *)             shift ;;
    esac
done

if [[ -z "$DEVICE_NAME" ]]; then
    echo -e "${RED}ERROR: Device name wajib!${NC}"
    echo ""
    echo "Usage:"
    echo "  bash bot.sh --device \"Nama Device\""
    echo "  tmux new-session -d -s bot \"bash bot.sh --device 'HP Kantor'\""
    exit 1
fi

# ── Logging ───────────────────────────────────────────────────────
log() {
    local level=$1 msg=$2
    local time=$(date '+%H:%M:%S')
    case $level in
        INFO)  echo -e "${DIM}[$time]${NC} $msg" ;;
        OK)    echo -e "${DIM}[$time]${NC} ${GREEN}[OK]${NC} $msg" ;;
        WARN)  echo -e "${DIM}[$time]${NC} ${YELLOW}[WARN]${NC} $msg" ;;
        ERROR) echo -e "${DIM}[$time]${NC} ${RED}[ERROR]${NC} $msg" ;;
        KEY)   echo -e "${DIM}[$time]${NC} ${CYAN}[KEY]${NC} $msg" ;;
    esac
}

# ── Cek URL ───────────────────────────────────────────────────────
is_url() {
    [[ "$1" =~ ^https?:// ]]
}

# ── Get clipboard ─────────────────────────────────────────────────
get_clipboard() {
    termux-clipboard-get 2>/dev/null || echo ""
}

# ── Hit API ───────────────────────────────────────────────────────
fetch_key() {
    local link="$1"
    local response

    log INFO "Menghubungi API... (bisa 40-60 detik)"
    response=$(curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "User-Agent: RootBot-Termux/1.0" \
        --connect-timeout 15 \
        --max-time 90 \
        -d "{\"link\":\"$link\",\"device\":\"$DEVICE_NAME\",\"device_id\":\"${DEVICE_NAME}_termux\"}" \
        2>/dev/null)

    if [[ -z "$response" ]]; then
        log ERROR "Tidak ada response dari API"
        return 1
    fi

    local key status
    key=$(echo "$response"    | grep -o '"key":"[^"]*"'    | cut -d'"' -f4)
    status=$(echo "$response" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

    if [[ "$status" == "success" && -n "$key" ]]; then
        log KEY "Key: $key"
        echo "$key"
        return 0
    else
        log ERROR "API error: $response"
        return 1
    fi
}

# ── Tulis license ke semua path ───────────────────────────────────
write_all_licenses() {
    local key="$1"
    log INFO "Menulis license ke ${#LICENSE_PATHS[@]} lokasi..."

    for path in "${LICENSE_PATHS[@]}"; do
        local dir
        dir=$(dirname "$path")
        su -c "mkdir -p '$dir' && echo '$key' > '$path' && chmod 644 '$path'" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            log OK "License -> $path"
        else
            log WARN "Gagal tulis -> $path"
        fi
    done
}

# ── Kill semua package ────────────────────────────────────────────
kill_all_packages() {
    log INFO "Kill ${#TARGET_PACKAGES[@]} package..."

    for pkg in "${TARGET_PACKAGES[@]}"; do
        su -c "am force-stop '$pkg'" 2>/dev/null
        log OK "Kill -> $pkg"
        sleep 0.3
    done
}

# ── Handle link baru ──────────────────────────────────────────────
handle_link() {
    local link="$1"
    log INFO "Link: $link"

    # Fetch key dari API
    local key
    key=$(fetch_key "$link")
    if [[ -z "$key" ]]; then
        log ERROR "Gagal dapat key, skip"
        return 1
    fi

    # Tulis ke semua path license
    write_all_licenses "$key"

    # Kill semua package
    sleep 1
    kill_all_packages

    # Set interval ke 15 menit
    LAST_POPUP_TIME=$(date +%s)
    CURRENT_INTERVAL=$LONG_POLL_INTERVAL
    log OK "Selesai! Interval -> 15 menit"
    log INFO "─────────────────────────────────"
}

# ── Keepalive loop (background) ───────────────────────────────────
keepalive_loop() {
    while true; do
        sleep $KEEPALIVE_INTERVAL
        curl -s "$KEEPALIVE_URL" \
            -H "User-Agent: RootBot-Keepalive/1.0" \
            --connect-timeout 5 --max-time 10 \
            -o /dev/null 2>/dev/null
        log INFO "Keepalive ping OK"
    done
}

# ── Cleanup ───────────────────────────────────────────────────────
cleanup() {
    echo ""
    log WARN "Bot dihentikan"
    [[ -n "$KEEPALIVE_PID" ]] && kill "$KEEPALIVE_PID" 2>/dev/null
    exit 0
}
trap cleanup SIGINT SIGTERM

# ── Main ──────────────────────────────────────────────────────────
main() {
    clear
    echo -e "${CYAN}"
    echo "  ██████╗  ██████╗  ████████╗"
    echo "  ██╔══██╗██╔═══██╗ ╚══██╔══╝"
    echo "  ██████╔╝██║   ██║    ██║   "
    echo "  ██╔══██╗██║   ██║    ██║   "
    echo "  ██║  ██║╚██████╔╝    ██║   "
    echo "  ╚═╝  ╚═╝ ╚═════╝     ╚═╝  "
    echo -e "${NC}"
    echo -e " Device  : ${WHITE}$DEVICE_NAME${NC}"
    echo -e " Packages: ${WHITE}${#TARGET_PACKAGES[@]}${NC} target"
    echo -e " Licenses: ${WHITE}${#LICENSE_PATHS[@]}${NC} lokasi"
    echo -e " Interval: ${WHITE}${POLL_INTERVAL}s normal / ${LONG_POLL_INTERVAL}s setelah popup${NC}"
    echo ""

    # Cek dependencies
    for dep in termux-clipboard-get curl; do
        if ! command -v "$dep" &>/dev/null; then
            log ERROR "$dep tidak ditemukan!"
            [[ "$dep" == "termux-clipboard-get" ]] && log ERROR "Jalankan: pkg install termux-api"
            [[ "$dep" == "curl" ]] && log ERROR "Jalankan: pkg install curl"
            exit 1
        fi
    done

    # Cek root
    if ! su -c "echo ok" &>/dev/null; then
        log ERROR "Root tidak tersedia! Grant izin di Magisk."
        exit 1
    fi

    log OK "Dependencies OK"
    log INFO "Mendengarkan clipboard..."
    echo ""

    # Init clipboard baseline
    LAST_CLIP=$(get_clipboard)

    # Start keepalive di background
    keepalive_loop &
    KEEPALIVE_PID=$!

    # Main loop
    while true; do
        sleep "$CURRENT_INTERVAL"

        local current_clip
        current_clip=$(get_clipboard)

        # Skip kalau kosong atau sama
        [[ -z "$current_clip" || "$current_clip" == "$LAST_CLIP" ]] && {
            # Reset interval kalau sudah lewat 15 menit
            local now elapsed
            now=$(date +%s)
            elapsed=$((now - LAST_POPUP_TIME))
            if [[ $CURRENT_INTERVAL -eq $LONG_POLL_INTERVAL && $elapsed -gt $LONG_POLL_INTERVAL ]]; then
                CURRENT_INTERVAL=$POLL_INTERVAL
                log INFO "Interval reset ke normal (${POLL_INTERVAL}s)"
            fi
            continue
        }

        # Ada perubahan
        LAST_CLIP="$current_clip"

        # Proses kalau URL
        if is_url "$current_clip"; then
            handle_link "$current_clip"
        fi

        # Cek reset interval
        local now elapsed
        now=$(date +%s)
        elapsed=$((now - LAST_POPUP_TIME))
        if [[ $CURRENT_INTERVAL -eq $LONG_POLL_INTERVAL && $elapsed -gt $LONG_POLL_INTERVAL ]]; then
            CURRENT_INTERVAL=$POLL_INTERVAL
            log INFO "Interval reset ke normal (${POLL_INTERVAL}s)"
        fi
    done
}

main
