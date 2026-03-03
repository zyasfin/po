#!/bin/bash

R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
W='\033[1;37m'
N='\033[0m'

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
    cat /dev/urandom 2>/dev/null | tr -dc 'a-f0-9' | head -c 16
    echo
}

rand_serial() {
    CHARS="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    S="XMP"
    for i in {1..8}; do S+="${CHARS:$((RANDOM%${#CHARS})):1}"; done
    echo "$S"
}

rand_gsf() {
    printf "%016x\n" $((RANDOM * RANDOM * RANDOM % 0xFFFFFFFFFFFFFF))
}

rand_adid() {
    printf "%08x-%04x-%04x-%04x-%012x\n" \
        $((RANDOM*RANDOM)) $((RANDOM%65535)) $((RANDOM%65535)) \
        $((RANDOM%65535)) $((RANDOM*RANDOM*RANDOM))
}

MODEL=$(getprop ro.product.model 2>/dev/null); [ -z "$MODEL" ] && MODEL="Unknown"
BRAND=$(getprop ro.product.brand 2>/dev/null); [ -z "$BRAND" ] && BRAND="Unknown"
BOARD=$(getprop ro.product.board 2>/dev/null); [ -z "$BOARD" ] && BOARD="Unknown"
SERIAL=$(getprop ro.serialno 2>/dev/null); [ -z "$SERIAL" ] && SERIAL="Unknown"
MAC_NOW=$(cat /sys/class/net/wlan0/address 2>/dev/null); [ -z "$MAC_NOW" ] && MAC_NOW="N/A"
IMEI_NOW=$(getprop persist.radio.imei 2>/dev/null); [ -z "$IMEI_NOW" ] && IMEI_NOW="N/A"
AID_NOW=$(settings get secure android_id 2>/dev/null); [ -z "$AID_NOW" ] && AID_NOW="N/A"

NEW_IMEI=$(rand_imei)
NEW_MAC=$(rand_mac)
NEW_AID=$(rand_id)
NEW_SERIAL=$(rand_serial)
NEW_GSF=$(rand_gsf)
NEW_ADID=$(rand_adid)

clear
echo -e "${G} ========================================${N}"
echo -e "${G}   ANDROID ID SPOOFER - Termux Root Tool${N}"
echo -e "${G} ========================================${N}"
echo ""
echo -e " ${C}Device ${N}: ${W}${MODEL} (${BRAND})${N}"
echo -e " ${C}Board  ${N}: ${W}${BOARD}${N}"
echo -e " ${C}Serial ${N}: ${Y}${SERIAL}${N}"
echo -e " ${C}MAC    ${N}: ${Y}${MAC_NOW}${N}"
echo -e " ${C}IMEI   ${N}: ${Y}${IMEI_NOW}${N}"
echo -e " ${C}And.ID ${N}: ${Y}${AID_NOW}${N}"
echo ""
echo -e " ${W}---- ID BARU ----${N}"
echo -e " ${C}IMEI   ${N}: ${G}${NEW_IMEI}${N}"
echo -e " ${C}MAC    ${N}: ${G}${NEW_MAC}${N}"
echo -e " ${C}And.ID ${N}: ${G}${NEW_AID}${N}"
echo -e " ${C}Serial ${N}: ${G}${NEW_SERIAL}${N}"
echo -e " ${C}GSF ID ${N}: ${G}${NEW_GSF}${N}"
echo -e " ${C}Ad ID  ${N}: ${G}${NEW_ADID}${N}"
echo ""
echo -ne " Apply FULL SPOOF? (y/n) > "
read -r CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "\n ${Y}Dibatalkan.${N}\n"
    exit 0
fi

echo ""
ROOT=0
su -c "id" &>/dev/null && ROOT=1

echo -ne " ${C}[*] Android ID...${N} "
settings put secure android_id "$NEW_AID" 2>/dev/null && echo -e "${G}OK${N}" || echo -e "${R}GAGAL${N}"

echo -ne " ${C}[*] Serial Number...${N} "
[ $ROOT -eq 1 ] && su -c "setprop ro.serialno '$NEW_SERIAL'" 2>/dev/null && echo -e "${G}OK${N}" || echo -e "${Y}SKIP${N}"

echo -ne " ${C}[*] MAC Address...${N} "
ip link set wlan0 address "$NEW_MAC" 2>/dev/null && echo -e "${G}OK${N}" || \
    { [ $ROOT -eq 1 ] && su -c "ip link set wlan0 address '$NEW_MAC'" 2>/dev/null && echo -e "${G}OK${N}" || echo -e "${R}GAGAL${N}"; }

echo -ne " ${C}[*] Build.prop...${N} "
if [ $ROOT -eq 1 ]; then
    su -c "mount -o remount,rw /system 2>/dev/null; cp /system/build.prop /system/build.prop.bak 2>/dev/null; sed -i 's/ro.serialno=.*/ro.serialno=$NEW_SERIAL/' /system/build.prop 2>/dev/null; mount -o remount,ro /system 2>/dev/null" && echo -e "${G}OK${N}" || echo -e "${R}GAGAL${N}"
else
    echo -e "${Y}SKIP${N}"
fi

echo -ne " ${C}[*] Reset GSF...${N} "
[ $ROOT -eq 1 ] && su -c "pm clear com.google.android.gsf" 2>/dev/null && echo -e "${G}OK${N}" || echo -e "${Y}SKIP${N}"

echo -ne " ${C}[*] Reset Ad ID...${N} "
[ $ROOT -eq 1 ] && su -c "pm clear com.google.android.gms" 2>/dev/null && echo -e "${G}OK${N}" || echo -e "${Y}SKIP${N}"

echo ""
echo -e "${G} ========================================${N}"
echo -e "${G}   SPOOF SELESAI!${N}"
echo -e "${G} ========================================${N}"
echo ""
echo -e " ${Y}IMEI   ${N}: ${W}${NEW_IMEI}${N}"
echo -e " ${Y}MAC    ${N}: ${W}${NEW_MAC}${N}"
echo -e " ${Y}And.ID ${N}: ${W}${NEW_AID}${N}"
echo -e " ${Y}Serial ${N}: ${W}${NEW_SERIAL}${N}"
echo ""
echo -e " ${C}[!] Restart untuk menerapkan semua perubahan.${N}"
echo ""
