#!/bin/bash
# ============================================
#  BULK UNINSTALLER AUTO - Termux Edition
#  Usage: ./bulk_uninstall_auto.sh <prefix>
#  Contoh: ./bulk_uninstall_auto.sh com.google
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
RESET='\033[0m'

check_mode() {
  if command -v adb &>/dev/null && adb devices 2>/dev/null | grep -q "device$"; then
    MODE="adb"
  elif [ "$(id -u)" = "0" ]; then
    MODE="root"
  else
    MODE="normal"
  fi
}

do_uninstall() {
  local pkg="$1"
  local out
  case $MODE in
    adb)    out=$(adb shell pm uninstall --user 0 "$pkg" 2>&1) ;;
    root)   out=$(pm uninstall --user 0 "$pkg" 2>&1) ;;
    normal) out=$(pm uninstall "$pkg" 2>&1) ;;
  esac
  echo "$out" | grep -qi "success" && return 0 || return 1
}

find_by_prefix() {
  local prefix="$1"
  if [ "$MODE" = "adb" ]; then
    adb shell pm list packages 2>/dev/null | sed 's/package://' | tr -d '\r'
  else
    pm list packages 2>/dev/null | sed 's/package://' | tr -d '\r'
  fi | grep -i "^${prefix}" | sort
}

if [ -z "$1" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo -e "${BOLD}Penggunaan:${RESET}"
  echo -e "  ./bulk_uninstall_auto.sh com.google"
  echo -e "  ./bulk_uninstall_auto.sh com.samsung.knox"
  echo ""
  echo -e "${YELLOW}Semua package dengan prefix tsb langsung dihapus tanpa nanya.${RESET}"
  exit 0
fi

PREFIX="$1"

echo -e "${BOLD}${CYAN}"
echo "  ╔════════════════════════════════════╗"
echo "  ║  BULK UNINSTALLER AUTO - Termux    ║"
echo "  ╚════════════════════════════════════╝"
echo -e "${RESET}"

check_mode
echo -e "${CYAN}[Mode: ${BOLD}$MODE${RESET}${CYAN}]${RESET}"
echo -e "${CYAN}[Prefix: ${BOLD}$PREFIX${RESET}${CYAN}]${RESET}"
echo ""

mapfile -t PKGS < <(find_by_prefix "$PREFIX")
total=${#PKGS[@]}

if [ "$total" -eq 0 ]; then
  echo -e "${RED}[!] Tidak ada package yang cocok dengan '${PREFIX}'.${RESET}"
  echo -e "${YELLOW}[i] Cek dulu: pm list packages | grep -i '${PREFIX}'${RESET}"
  exit 1
fi

echo -e "${GREEN}[✓] Ditemukan ${BOLD}$total${RESET}${GREEN} package:${RESET}"
for i in "${!PKGS[@]}"; do
  printf "  ${MAGENTA}%2d.${RESET} %s\n" "$((i+1))" "${PKGS[$i]}"
done
echo ""

# Konfirmasi sekali sebelum eksekusi
printf "${RED}${BOLD}Hapus semua $total package di atas? [y/N]: ${RESET}"
read -r confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
  echo -e "${YELLOW}Dibatalkan.${RESET}"
  exit 0
fi

echo ""
echo -e "${BOLD}────────────────────────────────────${RESET}"

ok=0; fail=0; current=0

for pkg in "${PKGS[@]}"; do
  ((current++))
  printf "${BOLD}[%d/%d]${RESET} 📦 %-50s " "$current" "$total" "$pkg"
  if do_uninstall "$pkg"; then
    echo -e "${GREEN}✓${RESET}"
    ((ok++))
  else
    echo -e "${RED}✗ Gagal${RESET}"
    ((fail++))
  fi
done

echo ""
echo -e "${BOLD}════════════════════════${RESET}"
echo -e "${BOLD}       RINGKASAN        ${RESET}"
echo -e "${BOLD}════════════════════════${RESET}"
echo -e "  ${GREEN}✓ Berhasil  : $ok${RESET}"
echo -e "  ${RED}✗ Gagal     : $fail${RESET}"
echo -e "${BOLD}════════════════════════${RESET}"
