#!/data/data/com.termux/files/usr/bin/bash
# ================================================================
# RootBot - Termux Script
# Usage  : bash bot.sh --device "Nama Device"
# Tmux   : tmux new-session -d -s bot "bash bot.sh --device 'HP Kantor'"
# ================================================================

API_URL="https://montanaweb.xyz/keyproxy/api/v1/241ba761-e303-4805-a299-bbc5cd5f9b4d/submit"
KEEPALIVE_URL="https://montanaweb.xyz/keyproxy/dashboard.php"
KEEPALIVE_INTERVAL=300

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

SCREENSHOT_FILE="/sdcard/rb_screen.png"
COORDS_FILE="/sdcard/rb_coords.txt"
BROWSER_FILE="/sdcard/rb_browser.txt"
DONE_FILE="/sdcard/rb_done.txt"

# ── Timing ────────────────────────────────────────────────────────
CLIP_POLL=2
OCR_INTERVAL_WARMUP=15     # 15 detik - 30 menit pertama sejak start
OCR_INTERVAL_NORMAL=300    # 5 menit  - setelah warmup / setelah 23 jam
OCR_INTERVAL_LONG=1800     # 30 menit - setelah dapat key
WARMUP_DURATION=1800       # 30 menit warmup dalam detik
RESET_COOLDOWN=82800       # 23 jam dalam detik

OCR_INTERVAL=$OCR_INTERVAL_WARMUP
BOT_START_TIME=$(date +%s)
LAST_OCR=0
LAST_SUCCESS=0
LAST_CLIP=""
DEVICE_NAME=""
KEEPALIVE_PID=""

TESS_BIN="/data/data/com.termux/files/usr/bin/tesseract"
TESS_ENV="HOME=/data/data/com.termux/files/home PATH=/data/data/com.termux/files/usr/bin:/system/bin LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib TESSDATA_PREFIX=/data/data/com.termux/files/usr/share"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; DIM='\033[2m'; NC='\033[0m'

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

log() {
    local level=$1 msg=$2
    local time=$(date '+%H:%M:%S')
    case $level in
        INFO)  echo -e "${DIM}[$time]${NC} $msg" ;;
        OK)    echo -e "${DIM}[$time]${NC} ${GREEN}[OK]${NC} $msg" ;;
        WARN)  echo -e "${DIM}[$time]${NC} ${YELLOW}[WARN]${NC} $msg" ;;
        ERROR) echo -e "${DIM}[$time]${NC} ${RED}[ERROR]${NC} $msg" ;;
        KEY)   echo -e "${DIM}[$time]${NC} ${CYAN}[KEY]${NC} $msg" ;;
        OCR)   echo -e "${DIM}[$time]${NC} ${CYAN}[OCR]${NC} $msg" ;;
    esac
}

run_ocr() {
    [[ ! -f "$SCREENSHOT_FILE" ]] && return 1
    env $TESS_ENV "$TESS_BIN" "$SCREENSHOT_FILE" stdout tsv 2>/dev/null
}

parse_popups() {
    local tsv="$1"
    local continue_words=()
    local receive_words=()
    local enter_words=()

    while IFS=$'\t' read -r level page block par line word left top width height conf text; do
        [[ "$level" != "5" ]] && continue
        [[ -z "$text" ]] && continue
        local cx=$((left + width/2))
        local cy=$((top + height/2))
        case "$text" in
            [Cc]ontinue) continue_words+=("$cx,$cy,$left,$top,$width,$height") ;;
            [Rr]eceive)  receive_words+=("$cx,$cy,$left,$top") ;;
            [Ee]nter)    enter_words+=("$cx,$cy,$top") ;;
        esac
    done <<< "$tsv"

    for cont in "${continue_words[@]}"; do
        local cont_cx=$(echo $cont | cut -d, -f1)
        local cont_cy=$(echo $cont | cut -d, -f2)
        local cont_top=$(echo $cont | cut -d, -f4)

        local recv_cx="" recv_cy=""
        for recv in "${receive_words[@]}"; do
            local rx=$(echo $recv | cut -d, -f1)
            local ry=$(echo $recv | cut -d, -f2)
            local dx=$((rx - cont_cx)); [[ $dx -lt 0 ]] && dx=$((-dx))
            if [[ $dx -lt 150 && $ry -gt $cont_cy ]]; then
                recv_cx=$rx; recv_cy=$ry; break
            fi
        done

        [[ -z "$recv_cx" ]] && continue

        local enter_top=$((cont_top - 50))
        for ent in "${enter_words[@]}"; do
            local ex=$(echo $ent | cut -d, -f1)
            local et=$(echo $ent | cut -d, -f3)
            local dx=$((ex - cont_cx)); [[ $dx -lt 0 ]] && dx=$((-dx))
            if [[ $dx -lt 150 && $et -lt $cont_top ]]; then
                enter_top=$et; break
            fi
        done

        local field_x=$cont_cx
        local field_y=$(( (enter_top + cont_top) / 2 ))

        local region=5
        if   [[ $cont_cx -lt 450  && $cont_cy -lt 400 ]]; then region=1
        elif [[ $cont_cx -lt 950  && $cont_cy -lt 400 ]]; then region=2
        elif [[ $cont_cx -ge 950  && $cont_cy -lt 400 ]]; then region=3
        elif [[ $cont_cx -lt 550  && $cont_cy -ge 400 ]]; then region=4
        fi

        cat > "$COORDS_FILE" << EOF
appIndex=$region
receiveX=$recv_cx
receiveY=$recv_cy
continueX=$cont_cx
continueY=$cont_cy
fieldX=$field_x
fieldY=$field_y
EOF
        log OCR "Popup App$region: Continue($cont_cx,$cont_cy) Receive($recv_cx,$recv_cy) Field($field_x,$field_y)"
    done
}

check_browser_popup() {
    [[ ! -f "$BROWSER_FILE" ]] && return
    local content
    content=$(cat "$BROWSER_FILE" 2>/dev/null)
    [[ "$content" != "check" ]] && return

    log INFO "Cek browser popup via OCR..."
    local text
    text=$(env $TESS_ENV "$TESS_BIN" "$SCREENSHOT_FILE" stdout 2>/dev/null)

    if echo "$text" | grep -qi "chrome\|mint\|firefox\|just once\|always\|open with"; then
        echo "yes" > "$BROWSER_FILE"
        log OK "Browser popup terdeteksi!"
    else
        echo "no" > "$BROWSER_FILE"
        log INFO "Tidak ada browser popup"
    fi
}

should_run_ocr() {
    local now=$(date +%s)
    local elapsed=$((now - LAST_OCR))
    [[ $LAST_OCR -eq 0 || $elapsed -ge $OCR_INTERVAL ]]
}

# ── Update interval berdasarkan state ────────────────────────────
update_interval() {
    local now=$(date +%s)

    # Cek warmup selesai → naik ke 5 menit
    if [[ $OCR_INTERVAL -eq $OCR_INTERVAL_WARMUP ]]; then
        local elapsed_start=$((now - BOT_START_TIME))
        if [[ $elapsed_start -ge $WARMUP_DURATION ]]; then
            OCR_INTERVAL=$OCR_INTERVAL_NORMAL
            log INFO "Warmup selesai - OCR interval -> 5 menit"
        fi
    fi

    # Cek 23 jam tanpa key → balik ke 5 menit
    if [[ $OCR_INTERVAL -eq $OCR_INTERVAL_LONG && $LAST_SUCCESS -gt 0 ]]; then
        local elapsed_key=$((now - LAST_SUCCESS))
        if [[ $elapsed_key -ge $RESET_COOLDOWN ]]; then
            OCR_INTERVAL=$OCR_INTERVAL_NORMAL
            LAST_SUCCESS=0
            log INFO "23 jam tanpa key baru - OCR reset ke 5 menit"
        fi
    fi
}

fetch_key() {
    local link="$1"
    log INFO "Menghubungi API... (bisa 40-60 detik)" >&2

    local response
    response=$(curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "User-Agent: RootBot-Termux/1.0" \
        --connect-timeout 15 \
        --max-time 90 \
        -d "{\"link\":\"$link\",\"device\":\"$DEVICE_NAME\",\"device_id\":\"${DEVICE_NAME}_termux\"}" \
        2>/dev/null)

    if [[ -z "$response" ]]; then
        log ERROR "Tidak ada response dari API" >&2
        return 1
    fi

    local key status
    key=$(echo "$response"    | sed 's/ //g' | grep -o '"key":"[^"]*"'    | cut -d'"' -f4)
    status=$(echo "$response" | sed 's/ //g' | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

    if [[ "$status" == "success" && "$key" =~ ^FREE_[a-zA-Z0-9]{10,}$ ]]; then
        log KEY "Key: $key" >&2
        echo "$key"
        return 0
    else
        log ERROR "API error: $response" >&2
        return 1
    fi
}

write_all_licenses() {
    local key="$1"
    log INFO "Menulis license ke ${#LICENSE_PATHS[@]} lokasi..."
    for path in "${LICENSE_PATHS[@]}"; do
        local dir; dir=$(dirname "$path")
        su -c "mkdir -p '$dir' && printf '%s' '$key' > '$path' && chmod 644 '$path'" 2>/dev/null
        [[ $? -eq 0 ]] && log OK "License -> $path" || log WARN "Gagal -> $path"
    done
}

kill_all_packages() {
    log INFO "Kill ${#TARGET_PACKAGES[@]} package..."
    for pkg in "${TARGET_PACKAGES[@]}"; do
        su -c "am force-stop '$pkg'" 2>/dev/null
        log OK "Kill -> $pkg"
        sleep 0.3
    done
}

handle_link() {
    local link="$1"
    log INFO "Link: $link"

    local key
    key=$(fetch_key "$link" 2>/dev/null)
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

    # Dapat key → 30 menit, reset timer 23 jam
    LAST_SUCCESS=$(date +%s)
    OCR_INTERVAL=$OCR_INTERVAL_LONG
    log INFO "OCR interval -> 30 menit, 23 jam timer reset"
    log INFO "─────────────────────────────────"
}

keepalive_loop() {
    while true; do
        sleep $KEEPALIVE_INTERVAL
        curl -s "$KEEPALIVE_URL" -H "User-Agent: RootBot-Keepalive/1.0" \
            --connect-timeout 5 --max-time 10 -o /dev/null 2>/dev/null
        log INFO "Keepalive OK"
    done
}

cleanup() {
    echo ""
    log WARN "Bot dihentikan"
    [[ -n "$KEEPALIVE_PID" ]] && kill "$KEEPALIVE_PID" 2>/dev/null
    rm -f "$COORDS_FILE" "$BROWSER_FILE" "$DONE_FILE"
    exit 0
}
trap cleanup SIGINT SIGTERM

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
    echo -e " OCR scan: ${WHITE}warmup=15s (30mnt) → normal=5mnt → key=30mnt → 23jam → 5mnt${NC}"
    echo ""

    for dep in termux-clipboard-get curl "$TESS_BIN"; do
        if [[ ! -x "$dep" ]] && ! command -v "$dep" &>/dev/null; then
            log ERROR "$dep tidak ditemukan!"
            exit 1
        fi
    done

    if ! su -c "echo ok" &>/dev/null; then
        log ERROR "Root tidak tersedia!"
        exit 1
    fi

    log OK "Dependencies OK"
    rm -f "$COORDS_FILE" "$BROWSER_FILE" "$DONE_FILE"
    LAST_CLIP=$(termux-clipboard-get 2>/dev/null)

    keepalive_loop &
    KEEPALIVE_PID=$!

    log INFO "Warmup 30 menit - OCR tiap 15 detik..."
    echo ""

    while true; do
        sleep $CLIP_POLL

        # Update interval state
        update_interval

        # Cek browser popup
        if [[ -f "$BROWSER_FILE" ]]; then
            content=$(cat "$BROWSER_FILE" 2>/dev/null)
            if [[ "$content" == "check" ]]; then
                check_browser_popup
            fi
        fi

        # OCR scan
        if should_run_ocr && [[ -f "$SCREENSHOT_FILE" ]]; then
            log OCR "Scan tesseract... (interval: ${OCR_INTERVAL}s)"
            tsv=$(run_ocr)
            if [[ -n "$tsv" ]]; then
                parse_popups "$tsv"
            fi
            LAST_OCR=$(date +%s)
        fi

        # Cek clipboard
        local current_clip
        current_clip=$(termux-clipboard-get 2>/dev/null)
        [[ -z "$current_clip" || "$current_clip" == "$LAST_CLIP" ]] && continue
        LAST_CLIP="$current_clip"

        if [[ "$current_clip" =~ ^https?:// ]]; then
            handle_link "$current_clip"
        fi
    done
}

main
