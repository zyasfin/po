#!/bin/sh

# ============================================================
#   ANDROID SPOOFER + PROFILE MANAGER
#   Run with: su -c "bash <(curl -s <url>)"
# ============================================================

R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
W='\033[1;37m'
N='\033[0m'

GH_USER="zyasfin"
GH_REPO="po"
GH_TOKEN="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"
GH_BRANCH="main"
PROFILES_DIR="profiles"
API="https://api.github.com/repos/${GH_USER}/${GH_REPO}/contents/${PROFILES_DIR}"

# ============================================================
# CEK ROOT - jalankan ulang pakai su kalau belum root
# ============================================================
if [ "$(id -u)" != "0" ]; then
    echo -e "${Y}[*] Bukan root, mencoba su...${N}"
    SCRIPT_URL="https://raw.githubusercontent.com/${GH_USER}/${GH_REPO}/${GH_BRANCH}/android_spoofer.sh"
    curl -s "$SCRIPT_URL" > /sdcard/Download/sp.sh
    exec su -c "sh /sdcard/Download/sp.sh $*"
    exit 1
fi

# ============================================================
# GENERATE
# ============================================================
rand_imei() {
    TAC="86794503"
    SNR=$(printf "%06d" $((RANDOM % 999999)))
    BASE="${TAC}${SNR}"
    SUM=0; DBL=0
    for ((i=${#BASE}-1; i>=0; i--)); do
        D=${BASE:$i:1}
        [ $DBL -eq 1 ] && D=$((D*2)) && [ $D -gt 9 ] && D=$((D-9))
        SUM=$((SUM+D)); DBL=$((1-DBL))
    done
    echo "${BASE}$(( (10 - (SUM % 10)) % 10 ))"
}
rand_mac() {
    printf "02:%02x:%02x:%02x:%02x:%02x\n" \
        $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) \
        $((RANDOM%256)) $((RANDOM%256))
}
rand_id() {
    cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16; echo
}
rand_serial() {
    CHARS="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    S="XMP"
    for i in 1 2 3 4 5 6 7 8; do S="${S}$(echo "$CHARS" | cut -c$((RANDOM%36+1)))"; done
    echo "$S"
}
rand_gsf() { printf "%016x\n" $((RANDOM*RANDOM*RANDOM % 0xFFFFFFFFFFFFFF)); }

# ============================================================
# DEVICE INFO
# ============================================================
get_device_info() {
    MODEL=$(getprop ro.product.model 2>/dev/null);   [ -z "$MODEL" ]   && MODEL="Unknown"
    BRAND=$(getprop ro.product.brand 2>/dev/null);   [ -z "$BRAND" ]   && BRAND="Unknown"
    BOARD=$(getprop ro.product.board 2>/dev/null);   [ -z "$BOARD" ]   && BOARD="Unknown"
    SERIAL=$(getprop ro.serialno 2>/dev/null);       [ -z "$SERIAL" ]  && SERIAL="Unknown"
    MAC_NOW=$(cat /sys/class/net/wlan0/address 2>/dev/null); [ -z "$MAC_NOW" ] && MAC_NOW="N/A"
    IMEI_NOW=$(getprop persist.radio.imei 2>/dev/null); [ -z "$IMEI_NOW" ] && IMEI_NOW="N/A"
    AID_NOW=$(settings get secure android_id 2>/dev/null); [ -z "$AID_NOW" ] && AID_NOW="N/A"
}

print_header() {
    clear
    echo -e "${G} ========================================${N}"
    echo -e "${G}   ANDROID SPOOFER + PROFILE MANAGER${N}"
    echo -e "${G}   running as: $(id)${N}"
    echo -e "${G} ========================================${N}"
    echo ""
}

print_device() {
    echo -e " ${C}Device ${N}: ${W}${MODEL} (${BRAND})${N}"
    echo -e " ${C}Board  ${N}: ${W}${BOARD}${N}"
    echo -e " ${C}Serial ${N}: ${Y}${SERIAL}${N}"
    echo -e " ${C}MAC    ${N}: ${Y}${MAC_NOW}${N}"
    echo -e " ${C}IMEI   ${N}: ${Y}${IMEI_NOW}${N}"
    echo -e " ${C}And.ID ${N}: ${Y}${AID_NOW}${N}"
    echo ""
}

# ============================================================
# APPLY
# ============================================================
apply_ids() {
    local IMEI=$1 MAC=$2 AID=$3 SERIAL=$4

    echo ""
    echo -ne " ${C}[*] Android ID...${N} "
    settings put secure android_id "$AID" 2>/dev/null && echo -e "${G}OK${N}" || echo -e "${R}GAGAL${N}"

    echo -ne " ${C}[*] Serial...${N} "
    setprop ro.serialno "$SERIAL" 2>/dev/null && echo -e "${G}OK${N}" || echo -e "${R}GAGAL${N}"

    echo -ne " ${C}[*] MAC...${N} "
    ip link set wlan0 address "$MAC" 2>/dev/null && echo -e "${G}OK${N}" || echo -e "${R}GAGAL${N}"

    echo -ne " ${C}[*] Build.prop...${N} "
    mount -o remount,rw /system 2>/dev/null
    cp /system/build.prop /system/build.prop.bak 2>/dev/null
    sed -i "s/ro.serialno=.*/ro.serialno=$SERIAL/" /system/build.prop 2>/dev/null
    mount -o remount,ro /system 2>/dev/null
    echo -e "${G}OK${N}"

    echo -ne " ${C}[*] Reset GSF...${N} "
    pm clear com.google.android.gsf 2>/dev/null && echo -e "${G}OK${N}" || echo -e "${R}GAGAL${N}"

    echo -ne " ${C}[*] Reset Ad ID...${N} "
    pm clear com.google.android.gms 2>/dev/null && echo -e "${G}OK${N}" || echo -e "${R}GAGAL${N}"

    echo -ne " ${C}[*] IMEI (EFS)...${N} "
    if [ -f /efs/imei/imei1 ]; then
        echo "$IMEI" > /efs/imei/imei1 && echo -e "${G}OK${N}" || echo -e "${R}GAGAL${N}"
    else
        echo -e "${Y}SKIP (tidak ada /efs)${N}"
    fi

    echo ""
    echo -e "${G} ---- APPLIED ----${N}"
    echo -e " ${Y}IMEI   ${N}: ${W}${IMEI}${N}"
    echo -e " ${Y}MAC    ${N}: ${W}${MAC}${N}"
    echo -e " ${Y}And.ID ${N}: ${W}${AID}${N}"
    echo -e " ${Y}Serial ${N}: ${W}${SERIAL}${N}"
    echo -e "\n ${C}[!] Restart untuk menerapkan semua perubahan.${N}\n"
}

# ============================================================
# GITHUB
# ============================================================
gh_list_profiles() {
    curl -s -H "Authorization: token ${GH_TOKEN}" "${API}" 2>/dev/null | \
        grep -oP '"name":"\K[^"]+(?=\.json")'
}

gh_get_profile() {
    curl -s -H "Authorization: token ${GH_TOKEN}" "${API}/$1.json" 2>/dev/null | \
        grep -oP '"content":"\K[^"]+' | tr -d '\\n' | base64 -d 2>/dev/null
}

gh_save_profile() {
    local NAME=$1 CONTENT=$2
    local ENCODED=$(echo "$CONTENT" | base64 -w 0)
    local SHA=$(curl -s -H "Authorization: token ${GH_TOKEN}" "${API}/${NAME}.json" | \
        grep -oP '"sha":"\K[^"]+' | head -1)
    local PAYLOAD
    if [ -n "$SHA" ]; then
        PAYLOAD="{\"message\":\"Update ${NAME}\",\"content\":\"${ENCODED}\",\"sha\":\"${SHA}\",\"branch\":\"${GH_BRANCH}\"}"
    else
        PAYLOAD="{\"message\":\"Add ${NAME}\",\"content\":\"${ENCODED}\",\"branch\":\"${GH_BRANCH}\"}"
    fi
    curl -s -X PUT \
        -H "Authorization: token ${GH_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "${API}/${NAME}.json" | grep -q '"content"' && return 0 || return 1
}

# ============================================================
# MENU FUNCTIONS
# ============================================================
menu_save() {
    get_device_info
    COUNTER=$(gh_list_profiles | grep -c "^${BRAND}_${MODEL}_" 2>/dev/null || echo 0)
    PROF_NAME="${BRAND}_${MODEL}_$(printf '%03d' $((COUNTER+1)))"
    PROF_NAME=$(echo "$PROF_NAME" | tr ' ' '_')

    echo -e " ${C}Nama profil: ${W}${PROF_NAME}${N}"
    echo -ne " Ganti nama? (Enter = pakai ini): "
    read -r CUSTOM
    [ -n "$CUSTOM" ] && PROF_NAME=$(echo "$CUSTOM" | tr ' ' '_')

    JSON="{\"name\":\"${PROF_NAME}\",\"brand\":\"${BRAND}\",\"model\":\"${MODEL}\",\"board\":\"${BOARD}\",\"serial\":\"${SERIAL}\",\"imei\":\"${IMEI_NOW}\",\"mac\":\"${MAC_NOW}\",\"android_id\":\"${AID_NOW}\",\"saved_at\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}"

    echo -e " ${Y}[*] Menyimpan ke GitHub...${N}"
    gh_save_profile "$PROF_NAME" "$JSON" \
        && echo -e " ${G}[+] Tersimpan: ${PROF_NAME}${N}" \
        || echo -e " ${R}[!] Gagal simpan.${N}"
}

menu_load() {
    echo -e " ${Y}[*] Mengambil profil dari GitHub...${N}"
    PROFILES=($(gh_list_profiles))
    [ ${#PROFILES[@]} -eq 0 ] && echo -e " ${R}[!] Tidak ada profil.${N}" && return

    echo ""
    for i in "${!PROFILES[@]}"; do
        echo -e "  ${G}[$((i+1))]${N} ${PROFILES[$i]}"
    done
    echo ""
    echo -ne " Pilih profil > "
    read -r PNUM
    PNAME="${PROFILES[$((PNUM-1))]}"
    [ -z "$PNAME" ] && echo -e " ${R}Tidak valid.${N}" && return

    PJSON=$(gh_get_profile "$PNAME")
    [ -z "$PJSON" ] && echo -e " ${R}[!] Gagal load.${N}" && return

    P_SERIAL=$(echo "$PJSON" | grep -oP '"serial":"\K[^"]+')
    P_AID=$(echo "$PJSON" | grep -oP '"android_id":"\K[^"]+')

    echo ""
    echo -e " ${W}[1]${N} CLONE — Device ID & Serial sama, IMEI/MAC random"
    echo -e " ${W}[2]${N} FULL RANDOM — semua ID baru"
    echo -ne " Pilih > "
    read -r MODE

    if [ "$MODE" == "1" ]; then
        echo -e "\n ${C}Android ID : ${W}${P_AID}${N}"
        echo -e " ${C}Serial     : ${W}${P_SERIAL}${N}"
        apply_ids "$(rand_imei)" "$(rand_mac)" "$P_AID" "$P_SERIAL"
    elif [ "$MODE" == "2" ]; then
        apply_ids "$(rand_imei)" "$(rand_mac)" "$(rand_id)" "$(rand_serial)"
    fi
}

menu_spoof_new() {
    I=$(rand_imei); M=$(rand_mac); A=$(rand_id); S=$(rand_serial)
    echo ""
    echo -e " ${W}ID Baru:${N}"
    echo -e " IMEI   : ${G}${I}${N}"
    echo -e " MAC    : ${G}${M}${N}"
    echo -e " And.ID : ${G}${A}${N}"
    echo -e " Serial : ${G}${S}${N}"
    echo ""
    echo -ne " Apply? (y/n) > "
    read -r C
    [ "$C" = "y" ] || [ "$C" = "Y" ] && apply_ids "$I" "$M" "$A" "$S" || echo -e " ${Y}Dibatalkan.${N}"
}

# ============================================================
# ARGUMENT MODE
# ============================================================
if [ "$1" == "load" ]; then
    PNAME="$2"; MODE="$3"
    [ -z "$PNAME" ] || [ -z "$MODE" ] && echo -e "${R}Usage: script.sh load <profile> <1|2>${N}" && exit 1
    PJSON=$(gh_get_profile "$PNAME")
    [ -z "$PJSON" ] && echo -e "${R}[!] Profil tidak ditemukan: ${PNAME}${N}" && exit 1
    P_SERIAL=$(echo "$PJSON" | grep -oP '"serial":"\K[^"]+')
    P_AID=$(echo "$PJSON" | grep -oP '"android_id":"\K[^"]+')
    [ "$MODE" == "1" ] && apply_ids "$(rand_imei)" "$(rand_mac)" "$P_AID" "$P_SERIAL" \
                       || apply_ids "$(rand_imei)" "$(rand_mac)" "$(rand_id)" "$(rand_serial)"
    exit 0
fi

[ "$1" == "save"  ] && get_device_info && menu_save  && exit 0
[ "$1" == "spoof" ] && get_device_info && menu_spoof_new && exit 0
[ "$1" == "list"  ] && gh_list_profiles | nl -w2 -s") " && exit 0

# ============================================================
# INTERACTIVE
# ============================================================
get_device_info
print_header
print_device

echo -e " ${W}[1]${N} Spoof ID Baru (random)"
echo -e " ${W}[2]${N} Simpan profil device ini → GitHub"
echo -e " ${W}[3]${N} Load & Apply profil dari GitHub"
echo -e " ${W}[0]${N} Keluar"
echo ""
echo -ne " Pilih menu > "
read -r CHOICE

case $CHOICE in
    1) menu_spoof_new ;;
    2) menu_save ;;
    3) menu_load ;;
    0) echo -e "\n ${Y}Bye!${N}\n" ;;
    *) echo -e "\n ${R}Pilihan tidak valid.${N}\n" ;;
esac
