#!/bin/bash

# ============================================================
# ANDROID SPOOFER + PROFILE MANAGER (BASH VERSION)
# Run: su -c "bash script.sh"
# ============================================================

# ================= COLORS =================
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
W='\033[1;37m'
N='\033[0m'

# ================= CONFIG =================
GH_USER="zyasfin"
GH_REPO="po"
GH_BRANCH="main"
GH_TOKEN="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"   # <-- ISI TOKEN BARU DI SINI

PROFILES_DIR="profiles"
API="https://api.github.com/repos/${GH_USER}/${GH_REPO}/contents/${PROFILES_DIR}"

# ============================================================
# ROOT CHECK
# ============================================================
if [[ $(id -u) -ne 0 ]]; then
    echo -e "${Y}[*] Restarting as root...${N}"
    exec su -c "bash $0 $*"
    exit
fi

# ============================================================
# RANDOM GENERATORS
# ============================================================

rand_imei() {
    local tac="86794503"
    local snr
    snr=$(printf "%06d" $((RANDOM%999999)))
    local base="${tac}${snr}"
    local sum=0 dbl=0 d

    for ((i=${#base}-1;i>=0;i--)); do
        d=${base:$i:1}
        if (( dbl==1 )); then
            d=$((d*2))
            (( d>9 )) && d=$((d-9))
        fi
        sum=$((sum+d))
        dbl=$((1-dbl))
    done

    local check=$(((10-(sum%10))%10))
    echo "${base}${check}"
}

rand_mac() {
    printf "02:%02x:%02x:%02x:%02x:%02x\n" \
        $((RANDOM%256)) $((RANDOM%256)) \
        $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256))
}

rand_id() {
    tr -dc 'a-f0-9' </dev/urandom | head -c 16
    echo
}

rand_serial() {
    local chars="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local s="XMP"
    for i in {1..8}; do
        s+="${chars:RANDOM%36:1}"
    done
    echo "$s"
}

# ============================================================
# DEVICE INFO
# ============================================================
get_device_info() {
    MODEL=$(getprop ro.product.model 2>/dev/null || echo "Unknown")
    BRAND=$(getprop ro.product.brand 2>/dev/null || echo "Unknown")
    BOARD=$(getprop ro.product.board 2>/dev/null || echo "Unknown")
    SERIAL=$(getprop ro.serialno 2>/dev/null || echo "Unknown")
    MAC_NOW=$(cat /sys/class/net/wlan0/address 2>/dev/null || echo "N/A")
    IMEI_NOW=$(getprop persist.radio.imei 2>/dev/null || echo "N/A")
    AID_NOW=$(settings get secure android_id 2>/dev/null || echo "N/A")
}

# ============================================================
# APPLY IDS
# ============================================================
apply_ids() {

    local IMEI="$1"
    local MAC="$2"
    local AID="$3"
    local SERIAL="$4"

    echo -e "\n${C}Applying IDs...${N}"

    settings put secure android_id "$AID" 2>/dev/null
    setprop ro.serialno "$SERIAL" 2>/dev/null
    ip link set wlan0 address "$MAC" 2>/dev/null

    if [[ -f /efs/imei/imei1 ]]; then
        echo "$IMEI" > /efs/imei/imei1
    fi

    echo -e "\n${G}DONE${N}"
    echo -e "IMEI   : $IMEI"
    echo -e "MAC    : $MAC"
    echo -e "And.ID : $AID"
    echo -e "Serial : $SERIAL"
    echo -e "\n${Y}Reboot required.${N}"
}

# ============================================================
# GITHUB
# ============================================================

gh_list_profiles() {
    curl -s -H "Authorization: token ${GH_TOKEN}" "$API" \
    | grep '"name"' \
    | cut -d '"' -f4 \
    | sed 's/.json//'
}

gh_get_profile() {
    curl -s -H "Authorization: token ${GH_TOKEN}" "$API/$1.json" \
    | grep '"content"' \
    | cut -d '"' -f4 \
    | tr -d '\n' \
    | base64 -d 2>/dev/null
}

gh_save_profile() {

    local NAME="$1"
    local CONTENT="$2"
    local ENCODED
    ENCODED=$(echo "$CONTENT" | base64 | tr -d '\n')

    local SHA
    SHA=$(curl -s -H "Authorization: token ${GH_TOKEN}" "$API/${NAME}.json" \
        | grep '"sha"' | head -1 | cut -d '"' -f4)

    local PAYLOAD

    if [[ -n "$SHA" ]]; then
        PAYLOAD="{\"message\":\"Update ${NAME}\",\"content\":\"${ENCODED}\",\"sha\":\"${SHA}\",\"branch\":\"${GH_BRANCH}\"}"
    else
        PAYLOAD="{\"message\":\"Add ${NAME}\",\"content\":\"${ENCODED}\",\"branch\":\"${GH_BRANCH}\"}"
    fi

    curl -s -X PUT \
        -H "Authorization: token ${GH_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "$API/${NAME}.json" >/dev/null
}

# ============================================================
# MENU
# ============================================================

menu_spoof() {
    local I M A S
    I=$(rand_imei)
    M=$(rand_mac)
    A=$(rand_id)
    S=$(rand_serial)

    echo -e "\n${W}New IDs:${N}"
    echo "IMEI   : $I"
    echo "MAC    : $M"
    echo "And.ID : $A"
    echo "Serial : $S"

    read -p "Apply? (y/n): " C
    [[ "$C" =~ ^[Yy]$ ]] && apply_ids "$I" "$M" "$A" "$S"
}

menu_save() {
    get_device_info

    local NAME="${BRAND}_${MODEL}_$(date +%s)"
    NAME=$(echo "$NAME" | tr ' ' '_')

    JSON="{\"brand\":\"${BRAND}\",\"model\":\"${MODEL}\",\"serial\":\"${SERIAL}\",\"android_id\":\"${AID_NOW}\"}"

    gh_save_profile "$NAME" "$JSON"

    echo -e "${G}Saved as ${NAME}${N}"
}

menu_load() {

    mapfile -t PROFILES < <(gh_list_profiles)

    if [[ ${#PROFILES[@]} -eq 0 ]]; then
        echo "No profiles."
        return
    fi

    echo
    for i in "${!PROFILES[@]}"; do
        echo "[$((i+1))] ${PROFILES[$i]}"
    done

    read -p "Select: " NUM
    PNAME="${PROFILES[$((NUM-1))]}"

    [[ -z "$PNAME" ]] && return

    PJSON=$(gh_get_profile "$PNAME")

    P_SERIAL=$(echo "$PJSON" | sed -n 's/.*"serial":"\([^"]*\)".*/\1/p')
    P_AID=$(echo "$PJSON" | sed -n 's/.*"android_id":"\([^"]*\)".*/\1/p')

    apply_ids "$(rand_imei)" "$(rand_mac)" "$P_AID" "$P_SERIAL"
}

# ============================================================
# MAIN
# ============================================================

clear
echo -e "${G}ANDROID SPOOFER - BASH VERSION${N}"

echo
echo "[1] Spoof Random"
echo "[2] Save Profile"
echo "[3] Load Profile"
echo "[0] Exit"
echo

read -p "Select: " CH

case "$CH" in
    1) menu_spoof ;;
    2) menu_save ;;
    3) menu_load ;;
    0) exit ;;
    *) echo "Invalid." ;;
esac
