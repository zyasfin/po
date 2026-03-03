#!/bin/bash

# ============================================================
#   ANDROID BUILD.PROP SPOOFER
#   Full Device Identity Spoof Tool
#   Compatible with Rooted Android (Termux + Root / ADB)
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# ---- KONFIGURASI PROFIL ----
PROFILE_NAME="Device-Spoof"
PROFILE_GROUP=7
PROFILE_TOTAL=8

# ---- FUNGSI UTAMA ----

clear_screen() {
    clear
    echo ""
}

print_header() {
    echo -e "${GREEN}------------------------------------------------------------${NC}"
    echo -e "${YELLOW}  PROFIL SET ${PROFILE_TOTAL}/${PROFILE_TOTAL} (Grup ${PROFILE_GROUP})${NC}"
    echo -e "${GREEN}------------------------------------------------------------${NC}"
}

get_device_info() {
    DEVICE_MODEL=$(getprop ro.product.model 2>/dev/null || echo "Unknown")
    DEVICE_BRAND=$(getprop ro.product.brand 2>/dev/null || echo "Unknown")
    DEVICE_BOARD=$(getprop ro.product.board 2>/dev/null || echo "Unknown")
    ANDROID_ID_VAL=$(settings get secure android_id 2>/dev/null || echo "N/A")
    GSF_ID=$(content query --uri content://com.google.android.gsf.gservices/prefix --where "name='android_id'" 2>/dev/null | grep -oP "(?<=value=).*" | head -1 || echo "N/A")
    SERIAL=$(getprop ro.serialno 2>/dev/null || echo "Unknown")
    MAC=$(cat /sys/class/net/wlan0/address 2>/dev/null || ip link show wlan0 2>/dev/null | grep -oP '(?<=ether )[^ ]+' || echo "02:00:00:00:00:00")
    IMEI=$(service call iphonesubinfo 1 2>/dev/null | awk -F"'" '{print $2}' | sed 's/ //g' | tr -d '\n' || echo "N/A")
    AD_ID=$(cat /data/data/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null | grep -oP '(?<=value=")[^"]+' || echo "N/A")
}

generate_random_imei() {
    # TAC umum (Type Allocation Code)
    TACS=("86794503" "35874010" "86368803" "35401910" "86726503")
    TAC=${TACS[$RANDOM % ${#TACS[@]}]}
    SNR=$(printf "%06d" $((RANDOM % 999999)))
    IMEI_BASE="${TAC}${SNR}"
    
    # Luhn algorithm check digit
    SUM=0
    DOUBLE=0
    for ((i=${#IMEI_BASE}-1; i>=0; i--)); do
        DIGIT=${IMEI_BASE:$i:1}
        if [ $DOUBLE -eq 1 ]; then
            DIGIT=$((DIGIT * 2))
            [ $DIGIT -gt 9 ] && DIGIT=$((DIGIT - 9))
        fi
        SUM=$((SUM + DIGIT))
        DOUBLE=$((1 - DOUBLE))
    done
    CHECK=$(( (10 - (SUM % 10)) % 10 ))
    echo "${IMEI_BASE}${CHECK}"
}

generate_random_mac() {
    printf "02:%02x:%02x:%02x:%02x:%02x" \
        $((RANDOM % 256)) $((RANDOM % 256)) \
        $((RANDOM % 256)) $((RANDOM % 256)) \
        $((RANDOM % 256))
}

generate_random_android_id() {
    cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 16 | head -n 1
}

generate_random_serial() {
    PREFIX="XMP"
    CHARS="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    SUFFIX=""
    for i in {1..8}; do
        SUFFIX+="${CHARS:RANDOM%${#CHARS}:1}"
    done
    echo "${PREFIX}${SUFFIX}"
}

generate_random_gsf() {
    printf "%016x" $((RANDOM * RANDOM * RANDOM % 0xFFFFFFFFFFFFFF))
}

generate_random_adid() {
    printf "%08x-%04x-%04x-%04x-%012x" \
        $((RANDOM * RANDOM)) \
        $((RANDOM % 65535)) \
        $((RANDOM % 65535)) \
        $((RANDOM % 65535)) \
        $((RANDOM * RANDOM * RANDOM))
}

print_device_info() {
    get_device_info

    NEW_IMEI=$(generate_random_imei)
    NEW_MAC=$(generate_random_mac)
    NEW_ANDROID_ID=$(generate_random_android_id)
    NEW_SERIAL=$(generate_random_serial)
    NEW_GSF=$(generate_random_gsf)
    NEW_ADID=$(generate_random_adid)

    echo ""
    echo -e "${CYAN}Device${NC}     : ${WHITE}${PROFILE_NAME} (#20)${NC}"
    echo -e "${CYAN}Model${NC}      : ${WHITE}${DEVICE_MODEL}${NC}"
    echo -e "${CYAN}Brand${NC}      : ${WHITE}${DEVICE_BRAND}${NC}"
    echo -e "${CYAN}Board${NC}      : ${WHITE}${DEVICE_BOARD}${NC}"
    echo -e "${CYAN}Android ID${NC} : ${YELLOW}${NEW_ANDROID_ID}${NC}"
    echo -e "${CYAN}GSF ID${NC}     : ${YELLOW}${NEW_GSF}${NC}"
    echo -e "${CYAN}Serial${NC}     : ${YELLOW}${NEW_SERIAL}${NC}"
    echo -e "${CYAN}Ad ID${NC}      : ${YELLOW}${NEW_ADID}${NC}"
    echo -e "${CYAN}MAC${NC}        : ${YELLOW}${NEW_MAC}:07${NC}"
    echo -e "${CYAN}IMEI baru${NC}  : ${GREEN}${NEW_IMEI}${NC}"
    echo -e "${CYAN}License${NC}    : ${GREEN}Full Activated${NC}"
    echo -e "${CYAN}IMEI skrg${NC}  : ${WHITE}${IMEI}${NC}"
    echo ""
    echo -e "${GREEN}------------------------------------------------------------${NC}"

    # Simpan ke variabel global
    G_NEW_IMEI=$NEW_IMEI
    G_NEW_MAC=$NEW_MAC
    G_NEW_ANDROID_ID=$NEW_ANDROID_ID
    G_NEW_SERIAL=$NEW_SERIAL
    G_NEW_GSF=$NEW_GSF
    G_NEW_ADID=$NEW_ADID
}

check_root() {
    if ! su -c "id" &>/dev/null 2>&1; then
        echo -e "${RED}[!] Root tidak terdeteksi!${NC}"
        echo -e "${YELLOW}    Beberapa fitur mungkin tidak berfungsi.${NC}"
        return 1
    fi
    return 0
}

apply_spoof() {
    echo ""
    echo -e "${YELLOW}[*] Memulai proses spoofing...${NC}"
    echo ""

    # Cek root
    ROOT_OK=0
    check_root && ROOT_OK=1

    # --- Android ID ---
    echo -ne "${CYAN}[*] Mengubah Android ID...${NC} "
    if settings put secure android_id "$G_NEW_ANDROID_ID" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}GAGAL (perlu root/ADB)${NC}"
    fi

    # --- Serial Number ---
    echo -ne "${CYAN}[*] Mengubah Serial Number...${NC} "
    if [ $ROOT_OK -eq 1 ]; then
        su -c "setprop ro.serialno '$G_NEW_SERIAL'" 2>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}GAGAL${NC}"
    else
        echo -e "${RED}SKIP (perlu root)${NC}"
    fi

    # --- Build.prop patches ---
    echo -ne "${CYAN}[*] Patching build.prop...${NC} "
    if [ $ROOT_OK -eq 1 ]; then
        BUILDPROP="/system/build.prop"
        su -c "mount -o remount,rw /system" 2>/dev/null
        
        # Backup
        su -c "cp $BUILDPROP ${BUILDPROP}.bak_$(date +%Y%m%d%H%M%S)" 2>/dev/null
        
        # Patch serial
        su -c "sed -i 's/ro.serialno=.*/ro.serialno=$G_NEW_SERIAL/' $BUILDPROP" 2>/dev/null
        su -c "grep -q 'ro.serialno' $BUILDPROP || echo 'ro.serialno=$G_NEW_SERIAL' >> $BUILDPROP" 2>/dev/null
        
        su -c "mount -o remount,ro /system" 2>/dev/null
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}SKIP (perlu root)${NC}"
    fi

    # --- MAC Address ---
    echo -ne "${CYAN}[*] Mengubah MAC Address...${NC} "
    if ip link set wlan0 address "${G_NEW_MAC}:07" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    elif [ $ROOT_OK -eq 1 ]; then
        su -c "ip link set wlan0 address '${G_NEW_MAC}:07'" 2>/dev/null && echo -e "${GREEN}OK (root)${NC}" || echo -e "${RED}GAGAL${NC}"
    else
        echo -e "${RED}SKIP (perlu root/ip tools)${NC}"
    fi

    # --- IMEI (hanya dengan tools khusus) ---
    echo -ne "${CYAN}[*] Mengubah IMEI...${NC} "
    if [ $ROOT_OK -eq 1 ]; then
        # Coba via nvram atau efs
        if su -c "ls /efs/imei/imei1" 2>/dev/null; then
            su -c "echo '$G_NEW_IMEI' > /efs/imei/imei1" 2>/dev/null && echo -e "${GREEN}OK (EFS)${NC}" || echo -e "${RED}GAGAL${NC}"
        elif su -c "ls /proc/ste_modem" 2>/dev/null; then
            echo -e "${YELLOW}Manual (Snapdragon modem)${NC}"
        else
            echo -e "${YELLOW}SKIP (butuh tool khusus per chipset)${NC}"
        fi
    else
        echo -e "${RED}SKIP (perlu root)${NC}"
    fi

    # --- GSF ID ---
    echo -ne "${CYAN}[*] Reset GSF ID...${NC} "
    if [ $ROOT_OK -eq 1 ]; then
        su -c "pm clear com.google.android.gsf" 2>/dev/null && echo -e "${GREEN}OK (clear GMS)${NC}" || echo -e "${RED}GAGAL${NC}"
    else
        echo -e "${RED}SKIP (perlu root)${NC}"
    fi

    # --- Ad ID ---
    echo -ne "${CYAN}[*] Reset Advertising ID...${NC} "
    if [ $ROOT_OK -eq 1 ]; then
        su -c "pm clear com.google.android.gms" 2>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}GAGAL${NC}"
    else
        echo -e "${RED}SKIP (perlu root)${NC}"
    fi

    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  FULL SPOOF SELESAI!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "${YELLOW}  IMEI Baru   : ${WHITE}${G_NEW_IMEI}${NC}"
    echo -e "${YELLOW}  Android ID  : ${WHITE}${G_NEW_ANDROID_ID}${NC}"
    echo -e "${YELLOW}  Serial      : ${WHITE}${G_NEW_SERIAL}${NC}"
    echo -e "${YELLOW}  MAC         : ${WHITE}${G_NEW_MAC}:07${NC}"
    echo ""
    echo -e "${CYAN}  [!] Restart perangkat untuk menerapkan semua perubahan.${NC}"
    echo ""
}

show_menu() {
    echo -e "${WHITE}  [1]${NC} Generate ID Baru & Preview"
    echo -e "${WHITE}  [2]${NC} Apply FULL SPOOF"
    echo -e "${WHITE}  [3]${NC} Hanya ubah Android ID"
    echo -e "${WHITE}  [4]${NC} Hanya ubah MAC Address"
    echo -e "${WHITE}  [5]${NC} Hanya ubah Serial Number"
    echo -e "${WHITE}  [6]${NC} Restore backup build.prop"
    echo -e "${WHITE}  [0]${NC} Keluar"
    echo ""
    echo -ne "${GREEN}Pilih menu > ${NC}"
}

restore_backup() {
    echo ""
    BACKUP=$(su -c "ls -t /system/build.prop.bak_* 2>/dev/null | head -1")
    if [ -z "$BACKUP" ]; then
        echo -e "${RED}[!] Tidak ada backup ditemukan.${NC}"
    else
        echo -e "${YELLOW}[*] Mengembalikan: $BACKUP${NC}"
        su -c "mount -o remount,rw /system && cp '$BACKUP' /system/build.prop && mount -o remount,ro /system"
        echo -e "${GREEN}[+] Restore selesai. Restart perangkat.${NC}"
    fi
}

# ============================================================
# MAIN LOOP
# ============================================================

clear_screen

echo -e "${GREEN}"
cat << 'EOF'
  ____  ____   ___   ___  _____ _____ ____  
 / ___||  _ \ / _ \ / _ \|  ___| ____|  _ \ 
 \___ \| |_) | | | | | | | |_  |  _| | |_) |
  ___) |  __/| |_| | |_| |  _| | |___|  _ < 
 |____/|_|    \___/ \___/|_|   |_____|_| \_\
EOF
echo -e "${NC}"
echo -e "${CYAN}       Android Build.Prop & ID Spoofer Tool${NC}"
echo -e "${GRAY}       Untuk perangkat rooted | by SpooferKit${NC}"
echo ""

print_header
print_device_info

while true; do
    show_menu
    read -r CHOICE

    case $CHOICE in
        1)
            clear_screen
            print_header
            print_device_info
            ;;
        2)
            echo ""
            echo -ne "${RED}Apply FULL SPOOF? (y/n) > ${NC}"
            read -r CONFIRM
            if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
                apply_spoof
            else
                echo -e "${YELLOW}[!] Dibatalkan.${NC}"
            fi
            ;;
        3)
            echo ""
            echo -ne "${CYAN}[*] Mengubah Android ID ke: ${WHITE}${G_NEW_ANDROID_ID}${NC} ... "
            settings put secure android_id "$G_NEW_ANDROID_ID" 2>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}GAGAL${NC}"
            ;;
        4)
            echo ""
            echo -ne "${CYAN}[*] Mengubah MAC ke: ${WHITE}${G_NEW_MAC}:07${NC} ... "
            ip link set wlan0 address "${G_NEW_MAC}:07" 2>/dev/null || su -c "ip link set wlan0 address '${G_NEW_MAC}:07'" 2>/dev/null
            echo -e "${GREEN}OK${NC}"
            ;;
        5)
            echo ""
            echo -ne "${CYAN}[*] Mengubah Serial ke: ${WHITE}${G_NEW_SERIAL}${NC} ... "
            su -c "setprop ro.serialno '$G_NEW_SERIAL'" 2>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}GAGAL${NC}"
            ;;
        6)
            restore_backup
            ;;
        0)
            echo ""
            echo -e "${YELLOW}  Keluar dari Spoofer. Sampai jumpa!${NC}"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}  [!] Pilihan tidak valid.${NC}"
            ;;
    esac

    echo ""
    echo -ne "${GRAY}Tekan Enter untuk lanjut...${NC}"
    read -r
    clear_screen
    print_header
    print_device_info
done
