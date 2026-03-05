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
KEEPALIVE_INTERVAL=300       # ping keepalive tiap 5 menit

# Package yang di-kill setelah dapat key
TARGET_PACKAGES=(
    "com.roblox.clienu"
    "com.roblox.clienv"
    "com.roblox.clienw"
    "com.roblox.clienx"
    "com.roblox.clieny"
)

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

# File komunikasi dengan APK
SCREENSHOT_FILE="/sdcard/rb_screen.png"   # APK tulis
COORDS_FILE="/sdcard/rb_coords.txt"       # bot.sh tulis → APK baca
BROWSER_FILE="/sdcard/rb_browser.txt"     # APK tulis "check" → bot.sh tulis "yes/no"
DONE_FILE="/sdcard/rb_done.txt"           # bot.sh tulis key setelah berhasil

# Timing
CLIP_POLL=2            # cek clipboard tiap 2 detik
OCR_INTERVAL_NORMAL=10 # OCR tiap 10 detik (30 menit pertama)
OCR_INTERVAL_LONG=1800 # OCR tiap 30 menit setelah key berhasil
OCR_INTERVAL=10
LAST_OCR=0
LAST_SUCCESS=0
BOT_START=0
LAST_CLIP=""
DEVICE_NAME=""
KEEPALIVE_PID=""

# Tesseract
TESS_BIN="/data/data/com.termux/files/usr/bin/tesseract"
TESS_ENV=(
    "HOME=/data/data/com.termux/files/home"
    "PATH=/data/data/com.termux/files/usr/bin:/system/bin"
    "LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib"
    "TESSDATA_PREFIX=/data/data/com.termux/files/usr/share/tessdata"
)

# Colors
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
    local time
    time=$(date '+%H:%M:%S')
    case $level in
        INFO)  echo -e "${DIM}[$time]${NC} $msg" ;;
        OK)    echo -e "${DIM}[$time]${NC} ${GREEN}[OK]${NC} $msg" ;;
        WARN)  echo -e "${DIM}[$time]${NC} ${YELLOW}[WARN]${NC} $msg" ;;
        ERROR) echo -e "${DIM}[$time]${NC} ${RED}[ERROR]${NC} $msg" ;;
        KEY)   echo -e "${DIM}[$time]${NC} ${CYAN}[KEY]${NC} $msg" ;;
        OCR)   echo -e "${DIM}[$time]${NC} ${CYAN}[OCR]${NC} $msg" ;;
    esac
}

# ── Screencap dari Termux ─────────────────────────────────────────
do_screencap() {
    su -c "screencap -p $SCREENSHOT_FILE && chmod 644 $SCREENSHOT_FILE" 2>/dev/null
}

# ── OCR scan full layar ──────────────────────────────────────────
run_ocr() {
    [[ ! -f "$SCREENSHOT_FILE" ]] && return 1
    timeout 60 env "${TESS_ENV[@]}" "$TESS_BIN" "$SCREENSHOT_FILE" stdout tsv \
        --oem 1 --psm 3 2>/dev/null
}

# ── Parse TSV cari popup (pakai awk) ─────────────────────────────
# Tetap scan kata "receive" dari layar (bisa muncul 5-7x tiap app),
# semua log ditampilkan sebagai TARGET agar tidak false flag.
parse_popups() {
    local tsv="$1"
    [[ -z "$tsv" ]] && return

    local result
    result=$(echo "$tsv" | awk -F'\t' '
    BEGIN {
        cont_n = 0; tgt_n = 0; enter_n = 0
    }
    {
        if ($1 != "5") next
        if (NF < 12) next
        text = $12
        left = $7+0; top = $8+0; w = $9+0; h = $10+0
        cx = left + int(w/2)
        cy = top + int(h/2)

        tl = tolower(text)
        if (tl ~ /continue/) {
            cont_cx[cont_n]=cx; cont_cy[cont_n]=cy; cont_top[cont_n]=top; cont_n++
        }
        if (tl ~ /receive/) {
            tgt_cx[tgt_n]=cx; tgt_cy[tgt_n]=cy; tgt_n++
        }
        if (tl ~ /enter/) {
            enter_cx[enter_n]=cx; enter_top[enter_n]=top; enter_n++
        }
    }
    END {
        for (i=0; i<cont_n; i++) {
            cx = cont_cx[i]; cy = cont_cy[i]; ctop = cont_top[i]

            best_tx = -1; best_ty = -1
            for (j=0; j<tgt_n; j++) {
                dx = tgt_cx[j] - cx; if (dx<0) dx=-dx
                if (dx < 150 && (tgt_cy[j] > cy || cy - tgt_cy[j] < 200)) {
                    best_tx = tgt_cx[j]; best_ty = tgt_cy[j]; break
                }
            }
            if (best_tx < 0) continue

            enter_y = ctop - 50
            for (j=0; j<enter_n; j++) {
                dx = enter_cx[j] - cx; if (dx<0) dx=-dx
                if (dx < 150 && enter_top[j] < ctop) {
                    enter_y = enter_top[j]; break
                }
            }

            field_x = cx
            field_y = int((enter_y + ctop) / 2)

            region = 5
            if (cx < 450 && cy < 400) region = 1
            else if (cx < 950 && cy < 400) region = 2
            else if (cx >= 950 && cy < 400) region = 3
            else if (cx < 550 && cy >= 400) region = 4

            print region"|"best_tx"|"best_ty"|"cx"|"cy"|"field_x"|"field_y
        }
    }
    ')

    if [[ -z "$result" ]]; then
        log OCR "parse_popups: awk tidak output apapun - cek kondisi dx<150"
        echo "$tsv" | awk -F'\t' '
        $1=="5" && NF>=12 {
            tl=tolower($12)
            if (tl~/continue/ || tl~/receive/) {
                cx=$7+0+int($9/2); cy=$8+0+int($10/2)
                print "[DEBUG] "tl" -> cx="cx" cy="cy
            }
        }' | while read -r dbg; do log OCR "$dbg"; done
        return
    fi

    log OCR "parse_popups: awk hasil = $result"

    while IFS="|" read -r region tgt_x tgt_y cont_x cont_y field_x field_y; do
        printf "appIndex=%s\ntargetX=%s\ntargetY=%s\ncontinueX=%s\ncontinueY=%s\nfieldX=%s\nfieldY=%s\n" \
            "$region" "$tgt_x" "$tgt_y" "$cont_x" "$cont_y" "$field_x" "$field_y" > "$COORDS_FILE"
        log OCR "Popup App$region: TARGET($tgt_x,$tgt_y) Continue($cont_x,$cont_y) Field($field_x,$field_y)"
    done <<< "$result"
}

# ── Cek browser popup ─────────────────────────────────────────────
check_browser_popup() {
    [[ ! -f "$BROWSER_FILE" ]] && return
    local content
    content=$(cat "$BROWSER_FILE" 2>/dev/null)
    [[ "$content" != "check" ]] && return

    log INFO "Cek browser popup via OCR..."
    local text
    text=$(env "${TESS_ENV[@]}" "$TESS_BIN" "$SCREENSHOT_FILE" stdout 2>/dev/null)

    if echo "$text" | grep -qi "chrome\|mint\|firefox\|just once\|always\|open with"; then
        echo "yes" > "$BROWSER_FILE"
        log OK "Browser popup terdeteksi!"
    else
        echo "no" > "$BROWSER_FILE"
        log INFO "Tidak ada browser popup"
    fi
}

# ── Cek apakah perlu OCR ──────────────────────────────────────────
should_run_ocr() {
    local now
    now=$(date +%s)
    local elapsed=$((now - LAST_OCR))
    [[ $LAST_OCR -eq 0 || $elapsed -ge $OCR_INTERVAL ]]
}

# ── Hit API ───────────────────────────────────────────────────────
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

# ── Tulis license ke semua path ───────────────────────────────────
write_all_licenses() {
    local key="$1"
    log INFO "Menulis license ke ${#LICENSE_PATHS[@]} lokasi..."
    for path in "${LICENSE_PATHS[@]}"; do
        local dir
        dir=$(dirname "$path")
        su -c "mkdir -p '$dir' && printf '%s' '$key' > '$path' && chmod 644 '$path'" 2>/dev/null
        if su -c "test -f '$path'" 2>/dev/null; then
            log OK "License -> $path"
        else
            log WARN "Gagal -> $path"
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

# ── Handle link baru dari clipboard ──────────────────────────────
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
    LAST_SUCCESS=$(date +%s)
    OCR_INTERVAL=$OCR_INTERVAL_LONG
    log INFO "OCR interval -> 30 menit"
    log INFO "─────────────────────────────────"
}

# ── Keepalive ─────────────────────────────────────────────────────
keepalive_loop() {
    while true; do
        sleep "$KEEPALIVE_INTERVAL"
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
    rm -f "$COORDS_FILE" "$BROWSER_FILE" "$DONE_FILE"
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
    echo -e " OCR scan: ${WHITE}10 detik (30 menit pertama) / 30 menit setelah key${NC}"
    echo ""

    # Cek deps
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

    log INFO "Listening clipboard + monitor screenshot..."
    echo ""

    BOT_START=$(date +%s)

    while true; do
        sleep "$CLIP_POLL"

        # ── 1. Cek browser popup ──────────────────────────────────
        if [[ -f "$BROWSER_FILE" ]]; then
            local content
            content=$(cat "$BROWSER_FILE" 2>/dev/null)
            if [[ "$content" == "check" ]]; then
                check_browser_popup
            fi
        fi

        # ── 2. OCR scan ───────────────────────────────────────────
        if [[ $OCR_INTERVAL -eq $OCR_INTERVAL_LONG && $LAST_SUCCESS -gt 0 ]]; then
            local now_s
            now_s=$(date +%s)
            local elapsed_s=$((now_s - LAST_SUCCESS))
            if [[ $elapsed_s -ge $OCR_INTERVAL_LONG ]]; then
                OCR_INTERVAL=$OCR_INTERVAL_NORMAL
                log OCR "OCR interval reset ke normal"
            fi
        fi

        if should_run_ocr; then
            log OCR "Screencap..."
            do_screencap
            local screen_size
            screen_size=$(stat -c %s "$SCREENSHOT_FILE" 2>/dev/null || echo 0)
            log OCR "Screenshot: ${screen_size}bytes"

            if [[ $screen_size -lt 50000 ]]; then
                log OCR "Screenshot terlalu kecil, skip"
            else
                log OCR "Jalankan tesseract --oem 0 --psm 3..."
                local tsv
                tsv=$(timeout 60 env "${TESS_ENV[@]}" "$TESS_BIN" "$SCREENSHOT_FILE" stdout tsv --oem 0 --psm 3 2>&1)
                local tsv_lines
                tsv_lines=$(echo "$tsv" | wc -l)
                log OCR "Tesseract output: ${tsv_lines} baris"

                log OCR "Sample output: $(echo "$tsv" | head -3 | tr '\t' '|' | tr '\n' ' ')"

                local words
                words=$(echo "$tsv" | awk -F'\t' '$1=="5" && NF>=12 && $11+0>30 {print $12"(conf="int($11)")"}' | tr '\n' ' ')
                if [[ -n "$words" ]]; then
                    log OCR "Kata terdeteksi: $words"
                else
                    log OCR "Tidak ada kata terdeteksi (level 5, conf>30)"
                fi

                # Cari kata target di layar, log sebagai TARGET (bukan nama asli kata)
                local target_found
                target_found=$(echo "$tsv" | awk -F'\t' '$1=="5" && NF>=12 {tl=tolower($12); if(tl~/receive/) print $12,"x="$7,"y="$8,"conf="$11}')
                if [[ -n "$target_found" ]]; then
                    log OCR "TARGET DITEMUKAN: $target_found"
                else
                    log OCR "TARGET tidak ditemukan di output"
                fi

                if [[ -n "$tsv" ]]; then
                    parse_popups "$tsv"
                    if [[ -f "$COORDS_FILE" ]]; then
                        log OCR "COORDS TERBUAT: $(tr '\n' ' ' < "$COORDS_FILE")"
                    else
                        log OCR "Coords tidak terbuat"
                    fi
                fi
            fi
            LAST_OCR=$(date +%s)
            [[ $OCR_INTERVAL -eq $OCR_INTERVAL_LONG ]] && log OCR "Berikutnya 30 menit lagi"
        fi

        # ── 3. Cek clipboard ──────────────────────────────────────
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
