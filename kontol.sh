#!/data/data/com.termux/files/usr/bin/bash

main() {
    local user=""
    local pass=""
    local device_label=""
    local output="/sdcard/Download/cookie.txt"
    local base_root="https://nextcloud.montanaweb.xyz/remote.php/dav/files"

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -u|--user) user="$2"; shift ;;
            -p|--pass) pass="$2"; shift ;;
            -d|--device) device_label="$2"; shift ;;
            -o|--output) output="$2"; shift ;;
            *) echo "Unknown param: $1"; exit 1 ;;
        esac
        shift
    done

    if [[ -z "$user" || -z "$device_label" ]]; then
        echo "Usage: -d DEVICE -u USER -p PASS"
        exit 1
    fi

    if [[ -z "$pass" ]]; then
        read -s -p "Nextcloud password: " pass
        echo
    fi

    local folder="${device_label:0:1}"
    local url="$base_root/$user/Shared/NEW/$folder/$device_label.txt"

    echo "[*] Downloading: $url"

    http_code=$(curl -s -o "$output" -w "%{http_code}" \
        -u "$user:$pass" \
        "$url")

    if [[ "$http_code" == "200" ]]; then
        echo "[+] Cookie saved → $output"
    else
        echo "[!] Failed (HTTP $http_code)"
        exit 1
    fi

    # Run winter-rejoin
    echo "[*] Downloading winter-rejoin.lua..."
    cd /sdcard/Download/ && \
        curl -L -o /sdcard/Download/winter-rejoin.lua \
        https://api.wintercode.dev/loader/winter-rejoin.lua && \
        lua /sdcard/Download/winter-rejoin.lua </dev/null
}

main "$@"
