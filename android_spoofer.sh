#!/bin/bash

# ============================================================
#   ANDROID ID SPOOFER + PROFILE MANAGER
#   GitHub sync | by SpooferKit
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
# GENERATE FUNCTIONS
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
        $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256))
}
rand_id() {
    cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16; echo
}
rand_serial() {
    CHARS="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    S="XMP"
    for i in {1..8}; do S+="${CHARS:$((RANDOM%${#CHARS})):1}"; done
    echo "$S"
}
rand_gsf() { printf "%016x\n" $((RANDOM*RANDOM*RANDOM % 0xFFFFFFFFFFFFFF)); }
rand_adid() {
    printf "%08x-%04x-%04x-%04x-%012x\n" \
        $((RANDOM*RANDOM)) $((RANDOM%65535)) $((RANDOM%65535)) \
        $((RANDOM%65535)) $((RANDOM*RANDOM*RANDOM))
}

# ============================================================
# DEVICE INFO
# ============================================================
get_device_info() {
    MODEL=$(getprop ro.product.model 2>/dev/null); [ -z "$MODEL" ] && MODEL="Unknown"
    BRAND=$(getprop ro.product.brand 2>/dev/null); [ -z "$BRAND" ] && BRAND="Unknown"
    BOARD=$(getprop ro.product.board 2>/dev/null); [ -z "$BOARD" ] && BOARD="Unknown"
    SERIAL=$(getprop ro.serialno 2>/dev/null); [ -z "$SERIAL" ] && SERIAL="Unknown"
    MAC_NOW=$(cat /sys/class/net/wlan0/address 2>/dev/null); [ -z "$MAC_NOW" ] && MAC_NOW="N/A"
    IMEI_NOW=$(getprop persist.radio.imei 2>/dev/null); [ -z "$IMEI_NOW" ] && IMEI_NOW="N/A"
    AID_NOW=$(settings get secure android_id 2>/dev/null); [ -z "$AID_NOW" ] && AID_NOW="N/A"
}

print_header() {
    clear
    echo -e "${G} ========================================${N}"
    echo -e "${G}   ANDROID SPOOFER + PROFILE MANAGER${N}"
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
# APPLY SPOOF
# ============================================================
apply_ids() {
    local IMEI=$1 MAC=$2 AID=$3 SERIAL=$4
    ROOT=0; su -c "id" &>/dev/null && ROOT=1

    echo ""
    echo -ne " ${C}[*] Android ID...${N} "
    settings put secure android_id "$AID" 2>/dev/null && echo -e "${G}OK${N}" || echo -e "${R}GAGAL${N}"

    echo -ne " ${C}[*] Serial...${N} "
    [ $ROOT -eq 1 ] && su -c "setprop ro.serialno '$SERIAL'" 2>/dev/null && echo -e "${G}OK${N}" || echo -e "${Y}SKIP (no root)${N}"

    echo -ne " ${C}[*] MAC...${N} "
    ip link set wlan0 address "$MAC" 2>/dev/null && echo -e "${G}OK${N}" || \
        { [ $ROOT -eq 1 ] && su -c "ip link set wlan0 address '$MAC'" 2>/dev/null && echo -e "${G}OK${N}" || echo -e "${R}GAGAL${N}"; }

    echo -ne " ${C}[*] Build.prop...${N} "
    if [ $ROOT -eq 1 ]; then
        su -c "mount -o remount,rw /system 2>/dev/null; \
               cp /system/build.prop /system/build.prop.bak 2>/dev/null; \
               sed -i 's/ro.serialno=.*/ro.serialno=$SERIAL/' /system/build.prop 2>/dev/null; \
               mount -o remount,ro /system 2>/dev/null" && echo -e "${G}OK${N}" || echo -e "${R}GAGAL${N}"
    else
        echo -e "${Y}SKIP (no root)${N}"
    fi

    echo -ne " ${C}[*] Reset GSF...${N} "
    [ $ROOT -eq 1 ] && su -c "pm clear com.google.android.gsf" 2>/dev/null && echo -e "${G}OK${N}" || echo -e "${Y}SKIP${N}"

    echo -ne " ${C}[*] Reset Ad ID...${N} "
    [ $ROOT -eq 1 ] && su -c "pm clear com.google.android.gms" 2>/dev/null && echo -e "${G}OK${N}" || echo -e "${Y}SKIP${N}"

    echo ""
    echo -e "${G} ---- APPLIED ----${N}"
    echo -e " ${Y}IMEI   ${N}: ${W}${IMEI}${N}"
    echo -e " ${Y}MAC    ${N}: ${W}${MAC}${N}"
    echo -e " ${Y}And.ID ${N}: ${W}${AID}${N}"
    echo -e " ${Y}Serial ${N}: ${W}${SERIAL}${N}"
    echo -e "\n ${C}[!] Restart untuk menerapkan semua perubahan.${N}\n"
}

# ============================================================
# GITHUB FUNCTIONS
# ============================================================
gh_list_profiles() {
    curl -s -H "Authorization: token ${GH_TOKEN}" "${API}" 2>/dev/null | \
        grep -oP '"name":"\K[^"]+(?=\.json")' 
}

gh_get_profile() {
    local NAME=$1
    curl -s -H "Authorization: token ${GH_TOKEN}" "${API}/${NAME}.json" 2>/dev/null | \
        grep -oP '"content":"\K[^"]+' | tr -d '\\n' | base64 -d 2>/dev/null
}

gh_save_profile() {
    local NAME=$1
    local CONTENT=$2
    local ENCODED=$(echo "$CONTENT" | base64 -w 0)

    # Cek apakah file sudah ada (untuk dapat SHA)
    local SHA=$(curl -s -H "Authorization: token ${GH_TOKEN}" "${API}/${NAME}.json" | \
        grep -oP '"sha":"\K[^"]+' | head -1)

    local PAYLOAD
    if [ -n "$SHA" ]; then
        PAYLOAD="{\"message\":\"Update profile ${NAME}\",\"content\":\"${ENCODED}\",\"sha\":\"${SHA}\",\"branch\":\"${GH_BRANCH}\"}"
    else
        PAYLOAD="{\"message\":\"Add profile ${NAME}\",\"content\":\"${ENCODED}\",\"branch\":\"${GH_BRANCH}\"}"
    fi

    RESULT=$(curl -s -X PUT \
        -H "Authorization: token ${GH_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "${API}/${NAME}.json")

    echo "$RESULT" | grep -q '"content"' && return 0 || return 1
}

# ============================================================
# MENU: SAVE PROFILE
# ============================================================
menu_save() {
    get_device_info
    echo ""
    # Auto nama: Brand_Model_001
    COUNTER=$(gh_list_profiles | grep -c "^${BRAND}_${MODEL}_" 2>/dev/null || echo 0)
    COUNTER=$((COUNTER + 1))
    PROF_NAME="${BRAND}_${MODEL}_$(printf '%03d' $COUNTER)"
    PROF_NAME=$(echo "$PROF_NAME" | tr ' ' '_')

    echo -e " ${C}Nama profil otomatis: ${W}${PROF_NAME}${N}"
    echo -ne " Ganti nama? (Enter = pakai ini, atau ketik nama baru): "
    read -r CUSTOM_NAME
    [ -n "$CUSTOM_NAME" ] && PROF_NAME=$(echo "$CUSTOM_NAME" | tr ' ' '_')

    echo ""
    echo -e " ${Y}[*] Menyimpan profil '${PROF_NAME}' ke GitHub...${N}"

    JSON="{
  \"name\": \"${PROF_NAME}\",
  \"brand\": \"${BRAND}\",
  \"model\": \"${MODEL}\",
  \"board\": \"${BOARD}\",
  \"serial\": \"${SERIAL}\",
  \"imei\": \"${IMEI_NOW}\",
  \"mac\": \"${MAC_NOW}\",
  \"android_id\": \"${AID_NOW}\",
  \"gsf\": \"N/A\",
  \"saved_at\": \"$(date '+%Y-%m-%d %H:%M:%S')\"
}"

    if gh_save_profile "$PROF_NAME" "$JSON"; then
        echo -e " ${G}[+] Profil berhasil disimpan!${N}"
        echo -e " ${C}    github.com/${GH_USER}/${GH_REPO}/blob/${GH_BRANCH}/${PROFILES_DIR}/${PROF_NAME}.json${N}"
    else
        echo -e " ${R}[!] Gagal menyimpan. Cek token/koneksi.${N}"
    fi
}

# ============================================================
# MENU: LOAD PROFILE
# ============================================================
menu_load() {
    echo ""
    echo -e " ${Y}[*] Mengambil daftar profil dari GitHub...${N}"
    PROFILES=($(gh_list_profiles))

    if [ ${#PROFILES[@]} -eq 0 ]; then
        echo -e " ${R}[!] Tidak ada profil ditemukan.${N}"
        return
    fi

    echo ""
    echo -e " ${W} Daftar Profil:${N}"
    for i in "${!PROFILES[@]}"; do
        echo -e "  ${G}[$((i+1))]${N} ${PROFILES[$i]}"
    done
    echo ""
    echo -ne " Pilih nomor profil > "
    read -r PNUM
    PNUM=$((PNUM - 1))

    if [ -z "${PROFILES[$PNUM]}" ]; then
        echo -e " ${R}[!] Pilihan tidak valid.${N}"
        return
    fi

    PNAME="${PROFILES[$PNUM]}"
    echo ""
    echo -e " ${Y}[*] Loading profil '${PNAME}'...${N}"
    PJSON=$(gh_get_profile "$PNAME")

    if [ -z "$PJSON" ]; then
        echo -e " ${R}[!] Gagal load profil.${N}"
        return
    fi

    # Parse JSON sederhana
    P_BRAND=$(echo "$PJSON" | grep -oP '"brand":\s*"\K[^"]+')
    P_MODEL=$(echo "$PJSON" | grep -oP '"model":\s*"\K[^"]+')
    P_SERIAL=$(echo "$PJSON" | grep -oP '"serial":\s*"\K[^"]+')
    P_IMEI=$(echo "$PJSON" | grep -oP '"imei":\s*"\K[^"]+')
    P_MAC=$(echo "$PJSON" | grep -oP '"mac":\s*"\K[^"]+')
    P_AID=$(echo "$PJSON" | grep -oP '"android_id":\s*"\K[^"]+')

    echo ""
    echo -e " ${W} Info Profil:${N}"
    echo -e "  Brand  : ${C}${P_BRAND}${N}"
    echo -e "  Model  : ${C}${P_MODEL}${N}"
    echo -e "  Serial : ${C}${P_SERIAL}${N}"
    echo -e "  IMEI   : ${C}${P_IMEI}${N}"
    echo -e "  MAC    : ${C}${P_MAC}${N}"
    echo -e "  And.ID : ${C}${P_AID}${N}"
    echo ""
    echo -e " ${W}Mode apply:${N}"
    echo -e "  ${G}[1]${N} CLONE — Device ID & Serial SAMA, IMEI/MAC random"
    echo -e "  ${G}[2]${N} FULL RANDOM — semua ID baru"
    echo -ne " Pilih > "
    read -r MODE

    if [ "$MODE" == "1" ]; then
        echo -e "\n ${Y}[*] Applying clone...${N}"
        echo -e " ${C}  Android ID : ${W}${P_AID}${N}"
        echo -e " ${C}  Serial     : ${W}${P_SERIAL}${N}"
        echo -e " ${C}  IMEI/MAC   : ${W}random${N}"
        apply_ids "$(rand_imei)" "$(rand_mac)" "$P_AID" "$P_SERIAL"
    elif [ "$MODE" == "2" ]; then
        echo -e "\n ${Y}[*] Applying full random...${N}"
        apply_ids "$(rand_imei)" "$(rand_mac)" "$(rand_id)" "$(rand_serial)"
    else
        echo -e " ${R}[!] Pilihan tidak valid.${N}"
    fi
}

# ============================================================
# MENU: SPOOF BARU (tanpa profil)
# ============================================================
menu_spoof_new() {
    NEW_IMEI=$(rand_imei)
    NEW_MAC=$(rand_mac)
    NEW_AID=$(rand_id)
    NEW_SERIAL=$(rand_serial)

    echo ""
    echo -e " ${W}---- ID BARU ----${N}"
    echo -e " IMEI   : ${G}${NEW_IMEI}${N}"
    echo -e " MAC    : ${G}${NEW_MAC}${N}"
    echo -e " And.ID : ${G}${NEW_AID}${N}"
    echo -e " Serial : ${G}${NEW_SERIAL}${N}"
    echo ""
    echo -ne " Apply? (y/n) > "
    read -r C
    [[ "$C" == "y" || "$C" == "Y" ]] && apply_ids "$NEW_IMEI" "$NEW_MAC" "$NEW_AID" "$NEW_SERIAL" || echo -e " ${Y}Dibatalkan.${N}"
}

# ============================================================
# MAIN
# ============================================================
get_device_info

# --- ARGUMENT MODE ---
if [ "$1" == "load" ]; then
    PNAME="$2"
    MODE="$3"
    if [ -z "$PNAME" ] || [ -z "$MODE" ]; then
        echo -e "${R}Usage: script.sh load <profile_name> <1|2>${N}"
        echo -e "${Y}  1 = Clone (Device ID & Serial sama)${N}"
        echo -e "${Y}  2 = Full Random${N}"
        exit 1
    fi
    echo -e "${Y}[*] Loading profil '${PNAME}'...${N}"
    PJSON=$(gh_get_profile "$PNAME")
    if [ -z "$PJSON" ]; then
        echo -e "${R}[!] Profil tidak ditemukan: ${PNAME}${N}"
        exit 1
    fi
    P_SERIAL=$(echo "$PJSON" | grep -oP '"serial":\s*"\K[^"]+')
    P_AID=$(echo "$PJSON" | grep -oP '"android_id":\s*"\K[^"]+')
    if [ "$MODE" == "1" ]; then
        echo -e "${G}[+] CLONE — Android ID & Serial sama, IMEI/MAC random${N}"
        apply_ids "$(rand_imei)" "$(rand_mac)" "$P_AID" "$P_SERIAL"
    elif [ "$MODE" == "2" ]; then
        echo -e "${G}[+] FULL RANDOM${N}"
        apply_ids "$(rand_imei)" "$(rand_mac)" "$(rand_id)" "$(rand_serial)"
    else
        echo -e "${R}[!] Mode tidak valid. Gunakan 1 atau 2.${N}"
        exit 1
    fi
    exit 0
fi

if [ "$1" == "save" ]; then
    print_header
    print_device
    menu_save
    exit 0
fi

if [ "$1" == "spoof" ]; then
    print_header
    print_device
    menu_spoof_new
    exit 0
fi

if [ "$1" == "list" ]; then
    echo -e "${Y}[*] Daftar profil:${N}"
    gh_list_profiles | nl -w2 -s") "
    exit 0
fi

# --- INTERACTIVE MODE ---
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
    0) echo -e "\n ${Y}Bye!${N}\n"; exit 0 ;;
    *) echo -e "\n ${R}Pilihan tidak valid.${N}\n" ;;
esac

# ============================================================
# ARGUMENT MODE (non-interactive)
# Usage: script.sh load <profile_name> <mode 1|2>
#        script.sh save
#        script.sh spoof
# ============================================================
