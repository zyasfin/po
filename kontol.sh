nextcloud_cookie_dl() {
    local user=""
    local pass=""
    local device_label=""
    local output="/sdcard/Download/cookie.txt"

    # BASE URL FIX
    local base_root="https://nextcloud.montanaweb.xyz/remote.php/dav/files"

    # parse flags
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -u|--user) user="$2"; shift ;;
            -p|--pass) pass="$2"; shift ;;
            -d|--device) device_label="$2"; shift ;;
            -o|--output) output="$2"; shift ;;
            *) echo "Unknown param: $1"; return 1 ;;
        esac
        shift
    done

    # validasi
    if [[ -z "$user" || -z "$device_label" ]]; then
        echo "Usage: nextcloud_cookie_dl -u user -p pass -d device_label [-o output]"
        return 1
    fi

    # prompt password kalau kosong
    if [[ -z "$pass" ]]; then
        read -s -p "Nextcloud app password: " pass
        echo
        while [[ -z "$pass" ]]; do
            read -s -p "Password tidak boleh kosong: " pass
            echo
        done
    fi

    local folder="${device_label:0:1}"
    local url="$base_root/$user/Shared/NEW/$folder/$device_label.txt"

    echo "[*] Downloading: $url"

    http_code=$(curl -s -o "$output" -w "%{http_code}" \
        -u "$user:$pass" \
        "$url")

    if [[ "$http_code" == "200" ]]; then
        echo "[+] Cookie saved → $output"
    elif [[ "$http_code" == "401" ]]; then
        echo "[!] Auth gagal (401) — cek password"
        return 1
    elif [[ "$http_code" == "404" ]]; then
        echo "[!] File tidak ditemukan: $url"
        return 1
    else
        echo "[!] Download gagal (HTTP $http_code)"
        return 1
    fi
}
