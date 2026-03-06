#!/data/data/com.termux/files/usr/bin/bash
LC_ALL=C

INTERVAL="${1:-1}"

# ── ANSI Colors ──────────────────────────────────────────
RESET="\033[0m"; BOLD="\033[1m"; DIM="\033[2m"
FG_WHITE="\033[97m"; FG_GRAY="\033[90m"; FG_CYAN="\033[96m"
FG_GREEN="\033[92m"; FG_YELLOW="\033[93m"; FG_RED="\033[91m"
FG_BLUE="\033[94m"; FG_MAGENTA="\033[95m"; FG_ORANGE="\033[38;5;208m"
TL="╔"; TR="╗"; BL="╚"; BR="╝"; VL="║"; ML="╠"; MR="╣"
BAR_WIDTH=18; TOTAL_WIDTH=54

# ── CPU sampling ─────────────────────────────────────────
read_cpu_stat() {
  awk '/^cpu /{u=$2;n=$3;s=$4;i=$5;w=$6;r=$7;si=$8;st=$9
    print u+n+s+i+w+r+si+st,i;exit}' /proc/stat
}
read -r PREV_TOTAL PREV_IDLE <<<"$(read_cpu_stat)"
get_cpu_pct() {
  read -r CT CI <<<"$(read_cpu_stat)"
  DT=$((CT-PREV_TOTAL)); DI=$((CI-PREV_IDLE))
  PREV_TOTAL="$CT"; PREV_IDLE="$CI"
  [ "$DT" -le 0 ] && echo "0.0" && return
  awk -v dt="$DT" -v di="$DI" 'BEGIN{printf "%.1f",((dt-di)/dt)*100}'
}

# ── ARM CPU part → core name ──────────────────────────────
part_to_name() {
  case "$1" in
    0xd01) echo "Cortex-A32"      ;; 0xd03) echo "Cortex-A53"      ;;
    0xd04) echo "Cortex-A35"      ;; 0xd05) echo "Cortex-A55"      ;;
    0xd06) echo "Cortex-A65"      ;; 0xd07) echo "Cortex-A57"      ;;
    0xd08) echo "Cortex-A72"      ;; 0xd09) echo "Cortex-A73"      ;;
    0xd0a) echo "Cortex-A75"      ;; 0xd0b) echo "Cortex-A76"      ;;
    0xd0c) echo "Neoverse-N1"     ;; 0xd0d) echo "Cortex-A77"      ;;
    0xd0e) echo "Cortex-A76AE"    ;; 0xd40) echo "Neoverse-V1"     ;;
    0xd41) echo "Cortex-A78"      ;; 0xd42) echo "Cortex-A78AE"    ;;
    0xd43) echo "Cortex-A65AE"    ;; 0xd44) echo "Cortex-X1"       ;;
    0xd46) echo "Cortex-A510"     ;; 0xd47) echo "Cortex-A710"     ;;
    0xd48) echo "Cortex-X2"       ;; 0xd49) echo "Neoverse-N2"     ;;
    0xd4a) echo "Neoverse-E1"     ;; 0xd4b) echo "Cortex-A78C"     ;;
    0xd4c) echo "Cortex-X1C"      ;; 0xd4d) echo "Cortex-A715"     ;;
    0xd4e) echo "Cortex-X3"       ;; 0xd4f) echo "Neoverse-V2"     ;;
    0xd80) echo "Cortex-A520"     ;; 0xd81) echo "Cortex-A720"     ;;
    0xd82) echo "Cortex-X4"       ;; 0xd84) echo "Cortex-A725"     ;;
    0xd85) echo "Cortex-X925"     ;; 0xd87) echo "Cortex-A520AE"   ;;
    0x800) echo "Kryo 2xx Gold"   ;; 0x801) echo "Kryo 2xx Silver" ;;
    0x802) echo "Kryo 3xx Gold"   ;; 0x803) echo "Kryo 3xx Silver" ;;
    0x804) echo "Kryo 485 Gold"   ;; 0x805) echo "Kryo 485 Silver" ;;
    0x001) echo "Mongoose M1"     ;; 0x002) echo "Mongoose M2"     ;;
    0x003) echo "Meerkat M3"      ;; 0x004) echo "Meerkat M4"      ;;
    0x022) echo "Apple Firestorm" ;; 0x023) echo "Apple Icestorm"  ;;
    0x030) echo "Apple Blizzard"  ;; 0x031) echo "Apple Avalanche" ;;
    *) [ -n "$1" ] && echo "ARM($1)" || echo "Unknown" ;;
  esac
}

# ── SoC brand detection ───────────────────────────────────
detect_cpu_brand() {
  local dt_model="" raw="" platform="" soc_model="" soc_vendor=""
  local hw_field="" chip_id=""

  # Collect all sources
  for f in /proc/device-tree/model /sys/firmware/devicetree/base/model; do
    [ -f "$f" ] && dt_model=$(cat "$f" 2>/dev/null | tr -d '\0' | xargs) && break
  done
  for f in /sys/devices/soc0/machine /sys/devices/platform/soc/soc0/machine; do
    [ -f "$f" ] && raw=$(cat "$f" 2>/dev/null | tr -d '\0' | xargs) && break
  done
  platform=$(getprop ro.board.platform 2>/dev/null | xargs)
  soc_model=$(getprop ro.soc.model 2>/dev/null | xargs)
  soc_vendor=$(getprop ro.soc.manufacturer 2>/dev/null | xargs)
  hw_field=$(grep -m1 -i "^Hardware" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
  for f in /proc/device-tree/compatible /sys/firmware/devicetree/base/compatible; do
    [ -f "$f" ] && chip_id=$(cat "$f" 2>/dev/null | tr -d '\0' | tr ',' ' ' | xargs) && break
  done

  CPU_BRAND="Unknown SoC"

  # Combine all DT sources into one searchable string
  local dtm
  dtm=$(echo "$dt_model $raw $chip_id $hw_field" | tr '[:upper:]' '[:lower:]')

  # ── PASS 1: device-tree / sysfs string matching ───────
  # Qualcomm QRB industrial
  case "$dtm" in
    *"qrb5165"*) CPU_BRAND="Qualcomm QRB5165 (Snapdragon 865)" ; return ;;
    *"qrb4210"*) CPU_BRAND="Qualcomm QRB4210 (Snapdragon 410)" ; return ;;
    *"qrb2210"*) CPU_BRAND="Qualcomm QRB2210 (Snapdragon 225)" ; return ;;
  esac

  # Qualcomm SM / SDA codename in DT
  case "$dtm" in
    *"sm8650"*)            CPU_BRAND="Qualcomm Snapdragon 8 Gen3"   ; return ;;
    *"sm8550"*)            CPU_BRAND="Qualcomm Snapdragon 8 Gen2"   ; return ;;
    *"sm8475"*)            CPU_BRAND="Qualcomm Snapdragon 8+ Gen1"  ; return ;;
    *"sm8450"*)            CPU_BRAND="Qualcomm Snapdragon 8 Gen1"   ; return ;;
    *"sm8350"*)            CPU_BRAND="Qualcomm Snapdragon 888"      ; return ;;
    *"sm8250"*)            CPU_BRAND="Qualcomm Snapdragon 865"      ; return ;;
    *"sm8150"*)            CPU_BRAND="Qualcomm Snapdragon 855"      ; return ;;
    *"sda845"*|*"sdm845"*) CPU_BRAND="Qualcomm Snapdragon 845"     ; return ;;
    *"sdm660"*)            CPU_BRAND="Qualcomm Snapdragon 660"      ; return ;;
    *"sdm636"*)            CPU_BRAND="Qualcomm Snapdragon 636"      ; return ;;
    *"sdm632"*)            CPU_BRAND="Qualcomm Snapdragon 632"      ; return ;;
    *"sdm450"*)            CPU_BRAND="Qualcomm Snapdragon 450"      ; return ;;
    *"sm7675"*)            CPU_BRAND="Qualcomm Snapdragon 7+ Gen3"  ; return ;;
    *"sm7550"*)            CPU_BRAND="Qualcomm Snapdragon 7 Gen2"   ; return ;;
    *"sm7450"*)            CPU_BRAND="Qualcomm Snapdragon 7+ Gen2"  ; return ;;
    *"sm7325"*)            CPU_BRAND="Qualcomm Snapdragon 778G"     ; return ;;
    *"sm6375"*)            CPU_BRAND="Qualcomm Snapdragon 695"      ; return ;;
    *"sm6350"*)            CPU_BRAND="Qualcomm Snapdragon 690"      ; return ;;
    *"sm4350"*)            CPU_BRAND="Qualcomm Snapdragon 480"      ; return ;;
  esac

  # Rockchip
  case "$dtm" in
    *"rk3588s"*)   CPU_BRAND="Rockchip RK3588S"   ; return ;;
    *"rk3588"*)    CPU_BRAND="Rockchip RK3588"    ; return ;;
    *"rk3568"*)    CPU_BRAND="Rockchip RK3568"    ; return ;;
    *"rk3566"*)    CPU_BRAND="Rockchip RK3566"    ; return ;;
    *"rk3399pro"*) CPU_BRAND="Rockchip RK3399Pro" ; return ;;
    *"rk3399"*)    CPU_BRAND="Rockchip RK3399"    ; return ;;
    *"rk3328"*)    CPU_BRAND="Rockchip RK3328"    ; return ;;
    *"rk3326"*)    CPU_BRAND="Rockchip RK3326"    ; return ;;
    *"rk3288"*)    CPU_BRAND="Rockchip RK3288"    ; return ;;
    *"rk3229"*)    CPU_BRAND="Rockchip RK3229"    ; return ;;
    *"rk3128"*)    CPU_BRAND="Rockchip RK3128"    ; return ;;
  esac

  # MediaTek
  case "$dtm" in
    *"mt6989"*|*"dimensity 9300"*) CPU_BRAND="MediaTek Dimensity 9300" ; return ;;
    *"mt6985"*|*"dimensity 9200"*) CPU_BRAND="MediaTek Dimensity 9200" ; return ;;
    *"mt6983"*|*"dimensity 9000"*) CPU_BRAND="MediaTek Dimensity 9000" ; return ;;
    *"mt6893"*|*"dimensity 1200"*) CPU_BRAND="MediaTek Dimensity 1200" ; return ;;
    *"mt6891"*|*"dimensity 1100"*) CPU_BRAND="MediaTek Dimensity 1100" ; return ;;
    *"mt6877"*|*"dimensity 900"*)  CPU_BRAND="MediaTek Dimensity 900"  ; return ;;
    *"mt6873"*|*"dimensity 800"*)  CPU_BRAND="MediaTek Dimensity 800"  ; return ;;
    *"mt6853"*|*"dimensity 700"*)  CPU_BRAND="MediaTek Dimensity 700"  ; return ;;
    *"mt6833"*)                    CPU_BRAND="MediaTek Dimensity 6020"  ; return ;;
    *"mt6781"*)                    CPU_BRAND="MediaTek Helio G96"       ; return ;;
    *"mt6785"*)                    CPU_BRAND="MediaTek Helio G90T"      ; return ;;
    *"mt6769"*|*"mt6768"*)         CPU_BRAND="MediaTek Helio G85"       ; return ;;
  esac

  # Samsung Exynos
  case "$dtm" in
    *"exynos2400"*|*"s5e9935"*) CPU_BRAND="Samsung Exynos 2400" ; return ;;
    *"exynos2200"*|*"s5e9925"*) CPU_BRAND="Samsung Exynos 2200" ; return ;;
    *"exynos2100"*|*"s5e9840"*) CPU_BRAND="Samsung Exynos 2100" ; return ;;
    *"exynos990"*)               CPU_BRAND="Samsung Exynos 990"  ; return ;;
    *"exynos9825"*)              CPU_BRAND="Samsung Exynos 9825" ; return ;;
    *"exynos9820"*)              CPU_BRAND="Samsung Exynos 9820" ; return ;;
    *"exynos9810"*)              CPU_BRAND="Samsung Exynos 9810" ; return ;;
    *"exynos9611"*)              CPU_BRAND="Samsung Exynos 9611" ; return ;;
    *"exynos9610"*)              CPU_BRAND="Samsung Exynos 9610" ; return ;;
    *"exynos7885"*)              CPU_BRAND="Samsung Exynos 7885" ; return ;;
    *"exynos7904"*)              CPU_BRAND="Samsung Exynos 7904" ; return ;;
    *"exynos8895"*)              CPU_BRAND="Samsung Exynos 8895" ; return ;;
  esac

  # HiSilicon Kirin
  case "$dtm" in
    *"kirin990"*|*"hi3690"*) CPU_BRAND="HiSilicon Kirin 990" ; return ;;
    *"kirin980"*|*"hi3680"*) CPU_BRAND="HiSilicon Kirin 980" ; return ;;
    *"kirin970"*|*"hi3660"*) CPU_BRAND="HiSilicon Kirin 970" ; return ;;
    *"kirin960"*)             CPU_BRAND="HiSilicon Kirin 960" ; return ;;
    *"kirin710"*)             CPU_BRAND="HiSilicon Kirin 710" ; return ;;
  esac

  # Google Tensor
  case "$dtm" in
    *"zuma"*)                CPU_BRAND="Google Tensor G3" ; return ;;
    *"gs201"*|*"tensor g2"*) CPU_BRAND="Google Tensor G2" ; return ;;
    *"gs101"*|*"tensor"*)    CPU_BRAND="Google Tensor G1" ; return ;;
  esac

  # Allwinner
  case "$dtm" in
    *"sun50iw9"*|*"a100"*)  CPU_BRAND="Allwinner A100"     ; return ;;
    *"sun50iw10"*|*"h616"*) CPU_BRAND="Allwinner H616"     ; return ;;
    *"sun50iw6"*|*"a64"*)   CPU_BRAND="Allwinner A64"      ; return ;;
    *"sun8i"*"h3"*)         CPU_BRAND="Allwinner H3"       ; return ;;
    *"sun8i"*"h5"*)         CPU_BRAND="Allwinner H5"       ; return ;;
    *"sun50i"*)              CPU_BRAND="Allwinner (sun50i)" ; return ;;
  esac

  # Amlogic
  case "$dtm" in
    *"s922x"*)  CPU_BRAND="Amlogic S922X"  ; return ;;
    *"a311d"*)  CPU_BRAND="Amlogic A311D"  ; return ;;
    *"s905x3"*) CPU_BRAND="Amlogic S905X3" ; return ;;
    *"s905x"*)  CPU_BRAND="Amlogic S905X"  ; return ;;
    *"s905"*)   CPU_BRAND="Amlogic S905"   ; return ;;
  esac

  # Broadcom / Raspberry Pi
  case "$dtm" in
    *"bcm2712"*) CPU_BRAND="Broadcom BCM2712 (RPi 5)" ; return ;;
    *"bcm2711"*) CPU_BRAND="Broadcom BCM2711 (RPi 4)" ; return ;;
    *"bcm2837"*) CPU_BRAND="Broadcom BCM2837 (RPi 3)" ; return ;;
    *"bcm2836"*) CPU_BRAND="Broadcom BCM2836 (RPi 2)" ; return ;;
  esac

  # NVIDIA Tegra
  case "$dtm" in
    *"tegra234"*) CPU_BRAND="NVIDIA Tegra234 (Orin)"   ; return ;;
    *"tegra194"*) CPU_BRAND="NVIDIA Tegra194 (Xavier)" ; return ;;
    *"tegra186"*) CPU_BRAND="NVIDIA Tegra186 (Parker)" ; return ;;
    *"tegra210"*) CPU_BRAND="NVIDIA Tegra210 (X1)"     ; return ;;
  esac

  # ── PASS 2: ro.board.platform codename ────────────────
  case "$platform" in
    # Samsung Exynos
    universal9611)  CPU_BRAND="Samsung Exynos 9611"        ; return ;;
    universal9610)  CPU_BRAND="Samsung Exynos 9610"        ; return ;;
    universal9820)  CPU_BRAND="Samsung Exynos 9820"        ; return ;;
    universal9825)  CPU_BRAND="Samsung Exynos 9825"        ; return ;;
    universal990)   CPU_BRAND="Samsung Exynos 990"         ; return ;;
    universal2100)  CPU_BRAND="Samsung Exynos 2100"        ; return ;;
    universal2200)  CPU_BRAND="Samsung Exynos 2200"        ; return ;;
    universal2400)  CPU_BRAND="Samsung Exynos 2400"        ; return ;;
    universal1280)  CPU_BRAND="Samsung Exynos 1280"        ; return ;;
    universal1380)  CPU_BRAND="Samsung Exynos 1380"        ; return ;;
    universal7885)  CPU_BRAND="Samsung Exynos 7885"        ; return ;;
    universal7904)  CPU_BRAND="Samsung Exynos 7904"        ; return ;;
    universal8895)  CPU_BRAND="Samsung Exynos 8895"        ; return ;;
    # Qualcomm
    sdm845)         CPU_BRAND="Qualcomm Snapdragon 845"    ; return ;;
    sdm660)         CPU_BRAND="Qualcomm Snapdragon 660"    ; return ;;
    sdm636)         CPU_BRAND="Qualcomm Snapdragon 636"    ; return ;;
    sdm632)         CPU_BRAND="Qualcomm Snapdragon 632"    ; return ;;
    sdm450)         CPU_BRAND="Qualcomm Snapdragon 450"    ; return ;;
    msmnile)        CPU_BRAND="Qualcomm Snapdragon 855"    ; return ;;
    kona)           CPU_BRAND="Qualcomm Snapdragon 865"    ; return ;;
    huracan)        CPU_BRAND="Qualcomm Snapdragon 870"    ; return ;;
    lahaina)        CPU_BRAND="Qualcomm Snapdragon 888"    ; return ;;
    shima)          CPU_BRAND="Qualcomm Snapdragon 888+"   ; return ;;
    waipio)         CPU_BRAND="Qualcomm Snapdragon 8 Gen1" ; return ;;
    taro)           CPU_BRAND="Qualcomm Snapdragon 8+ Gen1"; return ;;
    kalama)         CPU_BRAND="Qualcomm Snapdragon 8 Gen2" ; return ;;
    pineapple)      CPU_BRAND="Qualcomm Snapdragon 8 Gen3" ; return ;;
    sun)            CPU_BRAND="Qualcomm Snapdragon 8 Gen4" ; return ;;
    crow)           CPU_BRAND="Qualcomm Snapdragon 7 Gen1" ; return ;;
    cape)           CPU_BRAND="Qualcomm Snapdragon 7+ Gen2"; return ;;
    holi)           CPU_BRAND="Qualcomm Snapdragon 778G"   ; return ;;
    lito)           CPU_BRAND="Qualcomm Snapdragon 765G"   ; return ;;
    atoll)          CPU_BRAND="Qualcomm Snapdragon 730G"   ; return ;;
    bengal)         CPU_BRAND="Qualcomm Snapdragon 662"    ; return ;;
    sm6150)         CPU_BRAND="Qualcomm Snapdragon 675"    ; return ;;
    # MediaTek
    mt6989)         CPU_BRAND="MediaTek Dimensity 9300"    ; return ;;
    mt6985)         CPU_BRAND="MediaTek Dimensity 9200"    ; return ;;
    mt6983)         CPU_BRAND="MediaTek Dimensity 9000"    ; return ;;
    mt6893)         CPU_BRAND="MediaTek Dimensity 1200"    ; return ;;
    mt6891)         CPU_BRAND="MediaTek Dimensity 1100"    ; return ;;
    mt6877)         CPU_BRAND="MediaTek Dimensity 900"     ; return ;;
    mt6873)         CPU_BRAND="MediaTek Dimensity 800"     ; return ;;
    mt6853)         CPU_BRAND="MediaTek Dimensity 700"     ; return ;;
    mt6768)         CPU_BRAND="MediaTek Helio G85"         ; return ;;
    mt6769)         CPU_BRAND="MediaTek Helio G85"         ; return ;;
    mt6785)         CPU_BRAND="MediaTek Helio G90T"        ; return ;;
    mt6781)         CPU_BRAND="MediaTek Helio G96"         ; return ;;
    mt6833)         CPU_BRAND="MediaTek Dimensity 6020"    ; return ;;
  esac

  # ── PASS 3: ro.soc.model — non-Qualcomm only ──────────
  local v_low; v_low=$(echo "$soc_vendor" | tr '[:upper:]' '[:lower:]')
  if [ -n "$soc_model" ]; then
    case "$v_low" in
      *"samsung"*)
        case "$(echo "$soc_model" | tr '[:upper:]' '[:lower:]')" in
          exynos2400|s5e9935) CPU_BRAND="Samsung Exynos 2400" ; return ;;
          exynos2200|s5e9925) CPU_BRAND="Samsung Exynos 2200" ; return ;;
          exynos2100|s5e9840) CPU_BRAND="Samsung Exynos 2100" ; return ;;
          exynos990)          CPU_BRAND="Samsung Exynos 990"  ; return ;;
          exynos9825)         CPU_BRAND="Samsung Exynos 9825" ; return ;;
          exynos9820)         CPU_BRAND="Samsung Exynos 9820" ; return ;;
          exynos9811)         CPU_BRAND="Samsung Exynos 9810" ; return ;;
          exynos9611)         CPU_BRAND="Samsung Exynos 9611" ; return ;;
          exynos9610)         CPU_BRAND="Samsung Exynos 9610" ; return ;;
          exynos7885)         CPU_BRAND="Samsung Exynos 7885" ; return ;;
          *)                  CPU_BRAND="Samsung $soc_model"  ; return ;;
        esac ;;
      *"mediatek"*|*"mtk"*)
        case "$(echo "$soc_model" | tr '[:upper:]' '[:lower:]')" in
          mt6989|*"dimensity 9300"*) CPU_BRAND="MediaTek Dimensity 9300" ; return ;;
          mt6985|*"dimensity 9200"*) CPU_BRAND="MediaTek Dimensity 9200" ; return ;;
          mt6983|*"dimensity 9000"*) CPU_BRAND="MediaTek Dimensity 9000" ; return ;;
          mt6893|*"dimensity 1200"*) CPU_BRAND="MediaTek Dimensity 1200" ; return ;;
          mt6877|*"dimensity 900"*)  CPU_BRAND="MediaTek Dimensity 900"  ; return ;;
          mt6768|mt6769)             CPU_BRAND="MediaTek Helio G85"       ; return ;;
          mt6785)                    CPU_BRAND="MediaTek Helio G90T"      ; return ;;
          mt6781)                    CPU_BRAND="MediaTek Helio G96"       ; return ;;
          *)                         CPU_BRAND="MediaTek $soc_model"      ; return ;;
        esac ;;
      *"hisilicon"*)  CPU_BRAND="HiSilicon $soc_model"  ; return ;;
      *"google"*)     CPU_BRAND="Google $soc_model"      ; return ;;
      "")             ;;  # no vendor, skip
      *)              CPU_BRAND="$soc_vendor $soc_model" ; return ;;
    esac
  fi

  # ── PASS 4: CPU part combination fingerprint ──────────
  local parts
  parts=$(grep "CPU part" /proc/cpuinfo 2>/dev/null | \
          awk '{print $NF}' | tr '[:upper:]' '[:lower:]' | sort -u | tr '\n' '|')

  case "$parts" in
    *"0x802"*"0x803"*|*"0x803"*"0x802"*)  CPU_BRAND="Qualcomm Snapdragon 845"     ;;
    *"0x804"*"0x805"*|*"0x805"*"0x804"*)  CPU_BRAND="Qualcomm Snapdragon 855/860" ;;
    *"0x805"*"0xd0d"*|*"0xd0d"*"0x805"*)  CPU_BRAND="Qualcomm Snapdragon 865"     ;;
    *"0xd05"*"0xd41"*"0xd44"*)             CPU_BRAND="Qualcomm Snapdragon 888"     ;;
    *"0xd46"*"0xd47"*"0xd48"*)             CPU_BRAND="Qualcomm Snapdragon 8 Gen1"  ;;
    *"0xd46"*"0xd4d"*"0xd4e"*)             CPU_BRAND="Qualcomm Snapdragon 8 Gen2"  ;;
    *"0xd80"*"0xd81"*"0xd82"*)             CPU_BRAND="Qualcomm Snapdragon 8 Gen3"  ;;
    *"0xd84"*"0xd85"*)                     CPU_BRAND="Qualcomm Snapdragon 8 Gen4"  ;;
    *"0xd46"*"0xd47"*)                     CPU_BRAND="MediaTek Dimensity 1200"     ;;
    *"0xd05"*"0xd47"*"0xd48"*)             CPU_BRAND="MediaTek Dimensity 9000"     ;;
  esac
  [ "$CPU_BRAND" != "Unknown SoC" ] && return

  # ── PASS 5: last resort raw string ────────────────────
  local any="${hw_field:-${raw:-$dt_model}}"
  [ -n "$any" ] && CPU_BRAND="$any"
}

# ── Per-cluster core detection ────────────────────────────
detect_clusters() {
  CORE_COUNT=$(nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo)

  declare -A part_count
  declare -A part_maxfreq

  local cur_proc=-1 cur_part=""
  while IFS=: read -r key val; do
    key=$(echo "$key" | xargs); val=$(echo "$val" | xargs)
    case "$key" in
      "processor") cur_proc="$val"; cur_part="" ;;
      "CPU part")
        cur_part=$(echo "$val" | tr '[:upper:]' '[:lower:]')
        part_count["$cur_part"]=$(( ${part_count["$cur_part"]:-0} + 1 ))
        local ff="/sys/devices/system/cpu/cpu${cur_proc}/cpufreq/cpuinfo_max_freq"
        if [ -f "$ff" ]; then
          local fr; fr=$(cat "$ff" 2>/dev/null)
          [ "${fr:-0}" -gt "${part_maxfreq[$cur_part]:-0}" ] && part_maxfreq["$cur_part"]="$fr"
        fi
        ;;
    esac
  done < /proc/cpuinfo

  CLUSTER_LINES=()

  if [ ${#part_count[@]} -gt 0 ]; then
    local sorted
    sorted=$(for p in "${!part_maxfreq[@]}"; do
      echo "${part_maxfreq[$p]:-0} $p"
    done | sort -n | awk '{print $2}')

    local labels=("LITTLE" "big" "prime" "ultra")
    local idx=0
    while IFS= read -r part; do
      [ -z "$part" ] && continue
      local name; name=$(part_to_name "$part")
      local cnt="${part_count[$part]}"
      local freq="${part_maxfreq[$part]:-0}"
      local ghz; ghz=$(awk -v f="$freq" 'BEGIN{printf "%.2f",f/1000000}')
      local lbl="${labels[$idx]:-cluster$idx}"
      CLUSTER_LINES+=("${cnt}x ${name}  @${ghz}GHz  [${lbl}]")
      idx=$((idx+1))
    done <<< "$sorted"
  else
    declare -A freq_count
    for ff in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/cpuinfo_max_freq; do
      [ -f "$ff" ] || continue
      local fr; fr=$(cat "$ff" 2>/dev/null)
      freq_count["$fr"]=$(( ${freq_count["$fr"]:-0} + 1 ))
    done

    local labels=("LITTLE" "big" "prime" "ultra")
    local idx=0
    for freq in $(printf '%s\n' "${!freq_count[@]}" | sort -n); do
      local cnt="${freq_count[$freq]}"
      local ghz; ghz=$(awk -v f="$freq" 'BEGIN{printf "%.2f",f/1000000}')
      local lbl="${labels[$idx]:-cluster$idx}"
      CLUSTER_LINES+=("${cnt}x (no part info)  @${ghz}GHz  [${lbl}]")
      idx=$((idx+1))
    done

    [ ${#CLUSTER_LINES[@]} -eq 0 ] && CLUSTER_LINES+=("${CORE_COUNT}x cores  (freq info unavailable)")
  fi
}

# ── Live max freq ─────────────────────────────────────────
get_cur_freq() {
  local max=0
  for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do
    [ -f "$f" ] || continue
    local v; v=$(cat "$f" 2>/dev/null)
    [ "${v:-0}" -gt "$max" ] && max="$v"
  done
  [ "$max" -gt 0 ] && awk -v f="$max" 'BEGIN{printf "%.2f",f/1000000}' || echo "?.??"
}

# ── RAM ──────────────────────────────────────────────────
get_mem() {
  awk '/MemTotal:/{t=$2}/MemFree:/{f=$2}/Buffers:/{b=$2}/^Cached:/{c=$2}
       /SReclaimable:/{sr=$2}/Shmem:/{sh=$2}
       END{u=t-f-b-c-sr+sh;if(u<0)u=0
         printf "%.1f %.1f %.1f",u/1048576,t/1048576,(t>0)?u/t*100:0
       }' /proc/meminfo
}

# ── Storage ──────────────────────────────────────────────
get_storage() {
  local mp="/"
  for p in /data /sdcard /storage/emulated/0; do
    df "$p" &>/dev/null && mp="$p" && break
  done
  df -k "$mp" 2>/dev/null | awk 'NR==2{
    printf "%.1f %.1f %.1f",$3/1048576,$2/1048576,($2>0)?$3/$2*100:0}'
}

# ── Progress bar ─────────────────────────────────────────
make_bar() {
  local pct="$1" w="$2"
  local filled=$(awk -v p="$pct" -v w="$w" 'BEGIN{printf "%d",p/100*w}')
  local empty=$((w-filled))
  local color
  awk -v p="$pct" 'BEGIN{exit !(p<50)}' && color="$FG_GREEN" \
  || { awk -v p="$pct" 'BEGIN{exit !(p<80)}' && color="$FG_YELLOW" || color="$FG_RED"; }
  local bar="${color}"
  for((i=0;i<filled;i++)); do bar+="█"; done
  bar+="${DIM}${FG_GRAY}"
  for((i=0;i<empty;i++));  do bar+="░"; done
  bar+="${RESET}"
  echo -e "$bar"
}

# ── Box helpers ───────────────────────────────────────────
print_top() { echo -e "${FG_CYAN}${TL}$(printf '═%.0s' $(seq 1 $TOTAL_WIDTH))${TR}${RESET}"; }
print_bot() { echo -e "${FG_CYAN}${BL}$(printf '═%.0s' $(seq 1 $TOTAL_WIDTH))${BR}${RESET}"; }
print_div() { echo -e "${FG_CYAN}${ML}$(printf '═%.0s' $(seq 1 $TOTAL_WIDTH))${MR}${RESET}"; }
print_row() {
  local content="$1"
  local visible; visible=$(echo -e "$content" | sed 's/\x1B\[[0-9;]*[mK]//g')
  local pad=$((TOTAL_WIDTH-${#visible}))
  printf "${FG_CYAN}${VL}${RESET} "
  echo -ne "$content"
  printf "%*s" "$((pad-1))" ""
  echo -e " ${FG_CYAN}${VL}${RESET}"
}
print_empty() { print_row ""; }

# ── Uptime ────────────────────────────────────────────────
get_uptime() {
  awk '{s=int($1);printf "%02dh %02dm %02ds",int(s/3600),int((s%3600)/60),s%60}' /proc/uptime
}

# ── Init ─────────────────────────────────────────────────
detect_cpu_brand
detect_clusters

tput civis 2>/dev/null
trap 'tput cnorm 2>/dev/null; echo ""; exit' INT TERM

# ── Main loop ─────────────────────────────────────────────
while true; do
  CPU_PCT="$(get_cpu_pct)"
  CUR_GHZ="$(get_cur_freq)"
  read -r MEM_U MEM_T MEM_P <<<"$(get_mem)"
  read -r STG_U STG_T STG_P <<<"$(get_storage)"
  UPTIME="$(get_uptime)"
  TIME_NOW="$(date '+%H:%M:%S')"
  CPU_BAR="$(make_bar "$CPU_PCT" $BAR_WIDTH)"
  MEM_BAR="$(make_bar "$MEM_P"   $BAR_WIDTH)"
  STG_BAR="$(make_bar "$STG_P"   $BAR_WIDTH)"

  clear; echo ""
  print_top
  print_empty
  print_row "${BOLD}${FG_ORANGE}  ⚡ SYSTEM MONITOR${RESET}${FG_GRAY}                     ${FG_WHITE}${TIME_NOW}${RESET}"
  print_row "${FG_GRAY}  Uptime : ${FG_WHITE}${UPTIME}${RESET}"
  print_div

  print_row "${FG_ORANGE}${BOLD}  CPU   ${RESET} ${FG_WHITE}${BOLD}${CPU_BRAND}${RESET}"
  print_row "${FG_GRAY}         Cores : ${FG_WHITE}${CORE_COUNT} total${RESET}"
  for line in "${CLUSTER_LINES[@]}"; do
    print_row "${FG_GRAY}                ${FG_CYAN}${line}${RESET}"
  done
  print_row "${FG_GRAY}         Live  : ${FG_YELLOW}${CUR_GHZ} GHz${FG_GRAY} (highest active)${RESET}"
  print_empty
  print_row "${FG_CYAN}${BOLD}  Load  ${RESET} ${CPU_BAR}  ${BOLD}${CPU_PCT}%${RESET}"
  print_div

  print_row "${FG_MAGENTA}${BOLD}  RAM   ${RESET} ${MEM_BAR}  ${BOLD}${MEM_U} / ${MEM_T} GB${RESET}  ${FG_GRAY}(${MEM_P}%)${RESET}"
  print_div

  print_row "${FG_BLUE}${BOLD}  DISK  ${RESET} ${STG_BAR}  ${BOLD}${STG_U} / ${STG_T} GB${RESET}  ${FG_GRAY}(${STG_P}%)${RESET}"
  print_div

  print_row "${FG_GRAY}  Refresh ${FG_WHITE}${INTERVAL}s${FG_GRAY}  ·  ${FG_WHITE}Ctrl+C${FG_GRAY} to exit${RESET}"
  print_empty
  print_bot; echo ""

  sleep "$INTERVAL"
done
