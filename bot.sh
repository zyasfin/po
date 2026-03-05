#!/data/data/com.termux/files/usr/bin/bash
# ================================================================
# RootBot - Termux Script (Link-Only Edition)
# Usage  : bash bot.sh --device "Nama Device"
# Tmux   : tmux new-session -d -s bot "bash bot.sh --device 'HP Kantor'"
# ================================================================

# ════════════════════════════════════════════════════════════════
# KONFIGURASI - EDIT BAGIAN INI
# ════════════════════════════════════════════════════════════════

API_URL="https://montanaweb.xyz/keyproxy/api/v1/241ba761-e303-4805-a299-bbc5cd5f9b4d/submit"
KEEPALIVE_URL="https://montanaweb.xyz/keyproxy/dashboard.php"
KEEPALIVE_INTERVAL=300       # ping keepalive tiap 5 menit

TARGET_PACKAGES=(
    "com.roblox.clienu"
    "com.roblox.clienv"
    "com.roblox.clienw"
    "com.roblox.clienx"
    "com.roblox.clieny"
)

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

DONE_FILE="/sdcard/rb_done.txt"
CLIP_POLL=2
LAST_CLIP=""
DEVICE_NAME=""
KEEPALIVE_PID=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; DIM='\033[2m'; NC='\033[0m'

# ── Parse args ────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --device|-d) DEVICE_NAME="$2"; shift 2 ;;
        --device=*)  DEVICE_NAME="${1#*=}"; shift ;;
        *) shift ;;
    esac
done

if [[ -z "$DEVICE_NAME" ]]; then
    echo -e "${RED}ERROR: Device name wajib!${NC}"
    echo "Usage: bash bot.sh --device 'Nama HP'"
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

# ── Hit API ───────────────────────────────────────────────────────
fetch_key() {
    local link="$1"
    log INFO "Menghubungi API... (bisa 40-60 detik)"

    local response
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
    key=$(echo "$response"    | sed 's/ //g' | grep -o '"key":"[^"]*"'    | cut -d'"' -f4)
    status=$(echo "$response" | sed 's/ //g' | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

    if [[ "$status" == "success" && "$key" =~ ^FREE_[a-zA-Z0-9]{10,}$ ]]; then
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
        local dir; dir=$(dirname "$path")
        su -c "mkdir -p '$dir' && printf '%s' '$key' > '$path' && chmod 644 '$path'" 2>/dev/null
        [[ $? -eq 0 ]] && log OK "License -> $path" || log WARN "Gagal -> $path"
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

# ── Handle link baru dari clipboard ──────────────────────────────
handle_link() {
    local link="$1"
    log INFO "Link: $link"

    local key
    key=$(fetch_key "$link")
    key=$(echo "$key" | tail -1 | tr -d '[:space:]')

    if [[ -z "$key" || ! "$key" =~ ^FREE_ ]]; then
        log ERROR "Gagal dapat key"
        return 1
    fi

    log KEY "Menggunakan key: $key"

    write_all_licenses "$key"

    sleep 1
    kill_all_packages

    echo "$key" > "$DONE_FILE"
    log OK "Done file ditulis, APK dikasih tau"
    log INFO "─────────────────────────────────"
}

# ── Keepalive ─────────────────────────────────────────────────────
keepalive_loop() {
    while true; do
        sleep $KEEPALIVE_INTERVAL
        curl -s "$KEEPALIVE_URL" -H "User-Agent: RootBot-Keepalive/1.0" \
            --connect-timeout 5 --max-time 10 -o /dev/null 2>/dev/null
        log INFO "Keepalive OK"
    done
}

# ── Cleanup ───────────────────────────────────────────────────────
cleanup() {
    echo ""
    log WARN "Bot dihentikan"
    [[ -n "$KEEPALIVE_PID" ]] && kill "$KEEPALIVE_PID" 2>/dev/null
    rm -f "$DONE_FILE"
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
    echo -e " Mode    : ${WHITE}Clipboard Link Listener${NC}"
    echo ""

    for dep in termux-clipboard-get curl; do
        if ! command -v "$dep" &>/dev/null; then
            log ERROR "$dep tidak ditemukan!"
            exit 1
        fi
    done

    if ! su -c "echo ok" &>/dev/null; then
        log ERROR "Root tidak tersedia!"
        exit 1
    fi

    log OK "Dependencies OK"
    rm -f "$DONE_FILE"

    LAST_CLIP=$(termux-clipboard-get 2>/dev/null)

    keepalive_loop &
    KEEPALIVE_PID=$!

    log INFO "Listening clipboard untuk link..."
    echo ""

    while true; do
        sleep $CLIP_POLL

        current_clip=$(termux-clipboard-get 2>/dev/null)

        [[ -z "$current_clip" || "$current_clip" == "$LAST_CLIP" ]] && continue

        LAST_CLIP="$current_clip"

        if [[ "$current_clip" =~ ^https?:// ]]; then
            handle_link "$current_clip"
        fi
    done
}

main
