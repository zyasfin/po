#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PREFIX
export SVDIR="${SVDIR:-$PREFIX/var/service}"
export LOGDIR="${LOGDIR:-$PREFIX/var/log}"
INSTALL_DIR="$HOME/.local/lib/winter-supervisor"
CONFIG_DIR="$HOME/.config/winter-supervisor"
KEY_FILE="$CONFIG_DIR/agent.key"
BOOT_DIR="$HOME/.termux/boot"
BOOT_SCRIPT="$BOOT_DIR/00-winter-supervisor.sh"

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }

# Embedded service scripts — single-file installer, no repo fetch at runtime.
print_service() {
    case "$1" in
    keybot-watchdog)
        cat <<'EMBEDDED_SERVICE_EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -u

PACKAGE_NAME="${PACKAGE_NAME:-com.example.androidkeybot}"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
RESTART_ACTION="${RESTART_ACTION:-com.example.androidkeybot.WATCHDOG_RESTART}"
LOG_FILE="${KEYBOT_LOG_FILE:-$HOME/keybot_watchdog.log}"
MAX_LOG_LINES="${MAX_LOG_LINES:-1000}"

log_message() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    printf '%s\n' "$message" | tee -a "$LOG_FILE"
    if [[ -f "$LOG_FILE" ]] && (( $(wc -l < "$LOG_FILE") > MAX_LOG_LINES )); then
        tail -n 500 "$LOG_FILE" >"${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
}

run_root_tty() {
    local command="$1"
    if command -v script >/dev/null 2>&1; then
        # Device su expects an interactive shell/PTY; plain stdin pipe is
        # accepted visually but does not reliably execute/flush commands.
        if command -v timeout >/dev/null 2>&1; then
            printf '%s\nexit\n' "$command" | timeout 5 script -qec 'su' /dev/null 2>/dev/null
        else
            printf '%s\nexit\n' "$command" | script -qec 'su' /dev/null 2>/dev/null
        fi
    else
        printf '%s\nexit\n' "$command" | su
    fi
}

run_root() {
    run_root_tty "$1"
}

run_root_capture() {
    local tmpd="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}"
    mkdir -p "$tmpd" 2>/dev/null || tmpd="."
    local out="$tmpd/.winter_rootcap.$$"
    rm -f "$out" 2>/dev/null || true
    run_root_tty "{ $1 ; } > \"$out\" 2>/dev/null" >/dev/null 2>&1 || true
    [[ -f "$out" ]] && cat "$out" 2>/dev/null || true
    rm -f "$out" 2>/dev/null || true
}

root_available() {
    command -v su >/dev/null 2>&1 || return 1
    [[ "$(run_root_capture 'id -u' | tr -d '[:space:]')" == "0" ]]
}

service_running() {
    local pid
    pid="$(run_root_capture "pidof $PACKAGE_NAME" | grep -Eo '[0-9]+' | head -1 || true)"
    [[ -n "$pid" ]] || return 1
    run_root_capture "dumpsys activity services $PACKAGE_NAME" | grep -q 'BotService' && return 0
    sleep 2
    run_root_capture "dumpsys activity services $PACKAGE_NAME" | grep -q 'BotService'
}

get_app_pid() {
    local pid
    pid="$(run_root_capture "pidof $PACKAGE_NAME" | grep -Eo '[0-9]+' | head -1 || true)"
    [[ -n "$pid" ]] && printf '%s\n' "$pid" || printf 'unknown\n'
}

wait_for_service() {
    local timeout="$1" waited=0
    while (( waited < timeout )); do
        sleep 1
        waited=$((waited + 1))
        if run_root_capture "dumpsys activity services $PACKAGE_NAME" | grep -q 'BotService'; then
            log_message "Started (PID: $(get_app_pid), ${waited}s)"
            return 0
        fi
    done
    return 1
}

start_app() {
    log_message "Starting Android Key Bot via watchdog broadcast..."
    run_root "am broadcast -a $RESTART_ACTION -n ${PACKAGE_NAME}/.receiver.WatchdogReceiver" >/dev/null 2>&1 || true
    if wait_for_service 10; then
        return 0
    fi

    log_message "Broadcast timeout; mencoba MainActivity..."
    run_root "am start -n ${PACKAGE_NAME}/.ui.MainActivity" >/dev/null 2>&1 || true
    if wait_for_service 8; then
        return 0
    fi

    log_message "Semua metode start gagal"
    return 1
}

log_message "Keybot watchdog aktif — package: $PACKAGE_NAME; interval: ${CHECK_INTERVAL}s"
failures=0
loops=0

while true; do
    if ! root_available; then
        log_message "Root tidak tersedia; retry 60 detik"
        [[ "${WATCHDOG_ONCE:-0}" == 1 ]] && exit 1
        sleep 60
        continue
    fi

    if service_running; then
        if (( failures > 0 )); then
            log_message "App recovered (PID: $(get_app_pid))"
        fi
        failures=0
    else
        failures=$((failures + 1))
        log_message "App/BotService mati (failure #$failures)"
        if start_app; then
            log_message "Recovery berhasil"
            failures=0
        elif (( failures >= 3 )); then
            log_message "3x gagal; cooldown 5 menit"
            [[ "${WATCHDOG_ONCE:-0}" == 1 ]] && exit 1
            sleep 300
            failures=0
        fi
    fi

    [[ "${WATCHDOG_ONCE:-0}" == 1 ]] && exit 0
    loops=$((loops + 1))
    if (( loops % 10 == 0 )); then
        log_message "Heartbeat — PID: $(get_app_pid)"
    fi
    sleep "$CHECK_INTERVAL"
done
EMBEDDED_SERVICE_EOF
        ;;
    winter-agent)
        cat <<'EMBEDDED_SERVICE_EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -u

AGENT_URL="${AGENT_URL:-https://api.wintercode.dev/loader/agent-obfuscated.lua}"
AGENT_PATH="${AGENT_PATH:-/sdcard/Download/agent.lua}"
KEY_FILE="${WINTER_AGENT_KEY_FILE:-$HOME/.config/winter-supervisor/agent.key}"
RESTART_DELAY="${AGENT_RESTART_DELAY:-10}"
LOG_FILE="${WINTER_AGENT_LOG_FILE:-$HOME/winter_agent.log}"
MAX_LOG_LINES="${MAX_LOG_LINES:-1000}"

log_message() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    printf '%s\n' "$message" | tee -a "$LOG_FILE"
    if [[ -f "$LOG_FILE" ]] && (( $(wc -l < "$LOG_FILE") > MAX_LOG_LINES )); then
        tail -n 500 "$LOG_FILE" >"${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
}

mkdir -p "$(dirname "$AGENT_PATH")"

refresh_agent() {
    if ! curl -fsSL "$AGENT_URL" -o "${AGENT_PATH}.tmp"; then
        return 1
    fi
    [[ -s "${AGENT_PATH}.tmp" ]] || return 1
    mv "${AGENT_PATH}.tmp" "$AGENT_PATH"
}

while true; do
    if [[ "${AGENT_SKIP_REFRESH:-0}" != 1 ]]; then
        log_message "Downloading Wintercode agent..."
        if ! refresh_agent && [[ ! -s "$AGENT_PATH" ]]; then
            log_message "Download gagal; retry ${RESTART_DELAY}s"
            [[ "${AGENT_ONCE:-0}" == 1 ]] && exit 1
            sleep "$RESTART_DELAY"
            continue
        fi
    fi

    agent_key=""
    if [[ -s "$KEY_FILE" ]]; then
        IFS= read -r agent_key <"$KEY_FILE" || true
    fi

    log_message "Starting Wintercode agent..."
    if [[ -n "$agent_key" ]]; then
        printf '%s\n' "$agent_key" | lua "$AGENT_PATH" >>"$LOG_FILE" 2>&1
        rc=$?
    else
        log_message "Key kosong; agent dijalankan tanpa input"
        lua "$AGENT_PATH" </dev/null >>"$LOG_FILE" 2>&1
        rc=$?
    fi
    agent_key=""

    log_message "Wintercode agent berhenti (exit $rc); restart ${RESTART_DELAY}s"
    [[ "${AGENT_ONCE:-0}" == 1 ]] && exit "$rc"
    sleep "$RESTART_DELAY"
done
EMBEDDED_SERVICE_EOF
        ;;
    boot-services)
        cat <<'EMBEDDED_SERVICE_EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -u

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PREFIX
export SVDIR="${SVDIR:-$PREFIX/var/service}"
export LOGDIR="${LOGDIR:-$PREFIX/var/log}"
DELAY="${TERMUX_BOOT_DELAY:-8}"

sleep "$DELAY"
mkdir -p "$SVDIR" "$LOGDIR/sv"

if command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock >/dev/null 2>&1 || true
fi

if ! service-daemon start >/dev/null 2>&1; then
    if [[ ! -s "$PREFIX/var/run/service-daemon.pid" ]] || ! kill -0 "$(cat "$PREFIX/var/run/service-daemon.pid")" 2>/dev/null; then
        exit 1
    fi
fi
sv up keybot-watchdog >/dev/null 2>&1 || true
sv up winter-agent >/dev/null 2>&1 || true
EMBEDDED_SERVICE_EOF
        ;;
    *)
        warn "Layanan tidak dikenal: $1"
        return 1
        ;;
    esac
}

# Debug seam: dump an embedded service script without installing anything.
if [[ "${1:-}" == --print-service ]]; then
    print_service "${2:-}"
    exit $?
fi

read_agent_key() {
    local key="${WINTER_AGENT_KEY:-}"
    if [[ -z "$key" && -r /dev/tty ]]; then
        IFS= read -r -p 'Masukkan key Wintercode agent (boleh kosong): ' key </dev/tty || true
    elif [[ -z "$key" && -t 0 ]]; then
        IFS= read -r -p 'Masukkan key Wintercode agent (boleh kosong): ' key || true
    fi
    printf '%s' "$key"
}

wait_for_service_daemon() {
    local attempt=0 pidfile="$PREFIX/var/run/service-daemon.pid" pid=""
    while (( attempt < 2 )); do
        if [[ -s "$pidfile" ]]; then
            pid="$(cat "$pidfile" 2>/dev/null || true)"
            if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
                return 0
            fi
        fi
        service-daemon start >/dev/null 2>&1 || true
        attempt=$((attempt + 1))
        sleep 1
    done
    return 1
}

device_model() {
    local brand='' model=''
    if command -v getprop >/dev/null 2>&1; then
        brand="$(getprop ro.product.manufacturer 2>/dev/null | head -1)"
        model="$(getprop ro.product.model 2>/dev/null | head -1)"
    fi
    printf '%s %s' "$brand" "$model" | sed 's/^ *//; s/ *$//'
}

device_id() {
    local prop value
    # Serial/HWID dari Android properties. Tidak panggil Termux:API:
    # command telephony bisa menunggu permission dan menggantung installer.
    for prop in ro.boot.serialno ro.serialno ro.boot.hardware ro.hardware ro.product.device; do
        value="$(getprop "$prop" 2>/dev/null | head -1 | tr -d '[:space:]' || true)"
        if [[ -n "$value" && "$value" != "unknown" && "$value" != "0" ]]; then
            printf '%s' "$value"
            return 0
        fi
    done
    printf 'tidak tersedia'
}

install_service() {
    local name="$1" command_path="$2" service_dir
    service_dir="$SVDIR/$name"
    mkdir -p "$service_dir/log" "$LOGDIR/sv/$name"
    cat >"$service_dir/run" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
exec "$command_path"
EOF
    cat >"$service_dir/log/run" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
exec svlogd -tt "$LOGDIR/sv/$name"
EOF
    cat >"$service_dir/finish" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
sleep 10
EOF
    chmod 700 "$service_dir/run" "$service_dir/finish" "$service_dir/log/run"
    rm -f "$service_dir/down"
}

stop_legacy_watchdog() {
    local lock="$PREFIX/tmp/watchdog_keybot.lock" pid="" command_line=""
    if [[ -s "$lock" ]]; then
        IFS= read -r pid <"$lock" || true
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            command_line="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
            if [[ "$command_line" == *watchdog_keybot* || "$command_line" == *kiro.sh* || "$command_line" == *testis.sh* ]]; then
                kill "$pid" 2>/dev/null || true
            fi
        fi
        rm -f "$lock"
    fi
    if command -v screen >/dev/null 2>&1; then
        screen -S watchdog_keybot -X quit >/dev/null 2>&1 || true
    fi
    rm -f "$BOOT_DIR/watchdog_keybot.sh" "$BOOT_DIR/watchdog_keybot_fixed.sh"
}

info '[1/7] Installing dependencies...'
pkg install -y termux-services curl lua54 sqlite termux-api util-linux >/dev/null
sleep 1

run_root_tty() {
    local command="$1"
    if command -v script >/dev/null 2>&1; then
        # Device su expects an interactive shell/PTY; plain stdin pipe is
        # accepted visually but does not reliably execute/flush commands.
        if command -v timeout >/dev/null 2>&1; then
            printf '%s\nexit\n' "$command" | timeout 5 script -qec 'su' /dev/null 2>/dev/null
        else
            printf '%s\nexit\n' "$command" | script -qec 'su' /dev/null 2>/dev/null
        fi
    else
        printf '%s\nexit\n' "$command" | su
    fi
}

run_root_command() {
    local command="$1" output='' rc=1
    # Primary path: normal Magisk/KernelSU su -c.
    if command -v timeout >/dev/null 2>&1; then
        output="$(timeout 5 su -c "$command" 2>&1)" && rc=0 || rc=$?
    else
        output="$(su -c "$command" 2>&1)" && rc=0 || rc=$?
    fi
    if (( rc == 0 )); then
        printf '%s\n' "$output"
        return 0
    fi
    # Device-specific fallback: su only works from an interactive PTY.
    run_root_tty "$command"
}

run_root() {
    run_root_command "$1"
}

probe_root() {
    local uid=''
    uid="$(run_root_command 'id -u' 2>/dev/null | tr -d '[:space:]' || true)"
    [[ "$uid" == "0" ]]
}

apply_root_tweaks() {
    local i=0 tweak output rc failed=0
    local tweaks=(
        'wm density 200'
        'settings put global window_animation_scale 0'
        'settings put global transition_animation_scale 0'
        'settings put global animator_duration_scale 0'
        'settings put global force_resizable_activities 1'
        'settings put global enable_freeform_support 1'
    )
    for tweak in "${tweaks[@]}"; do
        i=$((i + 1))
        info "[2/7] Root tweak $i/6: $tweak"
        output=''
        if output="$(run_root_command "$tweak" 2>&1)"; then
            rc=0
        else
            rc=$?
        fi
        if [[ -n "$output" ]]; then
            printf '%s\n' "$output" | sed 's/^/  [su] /'
        fi
        if (( rc == 0 )); then
            printf '  [su] TWEAK_OK: %s\n' "$tweak"
        else
            printf '  [su] TWEAK_FAIL: %s\n' "$tweak"
            failed=1
        fi
        sleep 1
    done
    if (( failed )); then
        warn 'Sebagian root tweak gagal; detail di atas'
    else
        ok 'Root tweaks applied'
    fi
}

info '[2/7] Applying root tweaks...'
if command -v su >/dev/null 2>&1; then
    if probe_root; then
        apply_root_tweaks
    else
        warn 'Root untuk Termux belum aktif (su tidak bisa root).'
        warn 'su tersedia, tapi root shell tidak mengembalikan marker. Buka Magisk/KernelSU > Superuser > izinkan Termux.'
        warn 'Tes manual: su lalu id -u (harus 0). Lanjut tanpa root tweaks; watchdog Keybot butuh root.'
    fi
else
    warn 'su tidak tersedia; root tweaks dan Keybot start perlu root'
fi

info '[3/7] Installing service files...'
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$BOOT_DIR" "$SVDIR" "$LOGDIR/sv"
print_service keybot-watchdog >"$INSTALL_DIR/keybot-watchdog.sh"
print_service winter-agent >"$INSTALL_DIR/winter-agent-runner.sh"
print_service boot-services >"$INSTALL_DIR/boot-services.sh"
chmod 700 "$INSTALL_DIR/keybot-watchdog.sh" "$INSTALL_DIR/winter-agent-runner.sh" "$INSTALL_DIR/boot-services.sh"
sleep 1

info '[4/7] Saving agent key...'
agent_key="$(read_agent_key)"
umask 077
printf '%s\n' "$agent_key" >"$KEY_FILE"
chmod 600 "$KEY_FILE"
if [[ -z "$agent_key" ]]; then
    warn 'Key kosong; Wintercode agent tetap dijalankan tanpa input key'
else
    ok 'Key disimpan privat untuk auto-restart agent'
fi
agent_key=""
sleep 1

info '[5/7] Installing Termux:Boot...'
stop_legacy_watchdog
install_service keybot-watchdog "$INSTALL_DIR/keybot-watchdog.sh"
install_service winter-agent "$INSTALL_DIR/winter-agent-runner.sh"
cp "$INSTALL_DIR/boot-services.sh" "$BOOT_SCRIPT"
chmod 700 "$BOOT_SCRIPT"
sleep 1

# Persist SVDIR so sv resolves service names in future shells.
if ! grep -qs 'export SVDIR=' "$HOME/.bashrc" 2>/dev/null; then
    printf 'export SVDIR=%s\n' "$SVDIR" >>"$HOME/.bashrc"
fi

info '[6/7] Starting services...'
if command -v termux-wake-lock >/dev/null 2>&1; then
    info '[6/7] Acquiring wake lock...'
    termux-wake-lock >/dev/null 2>&1 || true
else
    info '[6/7] Wake lock command unavailable; continuing...'
fi
if ! wait_for_service_daemon; then
    warn 'runit service-daemon gagal start'
    exit 1
fi

# runsvdir scans SVDIR every 5s; sv up fails until it supervises each
# service. Poll with visible progress, then read back actual run state.
service_ready() {
    local name="$1" status=''
    status="$(sv status "$name" 2>&1 || true)"
    printf '  [sv] %s\n' "$status"
    [[ "$status" == run:* || "$status" == *$'\nrun:'* ]]
}

services_ready=1
for service in keybot-watchdog winter-agent; do
    info "[6/7] Starting service: $service"
    attempt=0
    started=0
    while (( attempt < 15 )); do
        attempt=$((attempt + 1))
        printf '  [sv] waiting %s (%d/15)\n' "$service" "$attempt"
        sv up "$service" >/dev/null 2>&1 || sv start "$service" >/dev/null 2>&1 || true
        if service_ready "$service"; then
            started=1
            break
        fi
        sleep 1
    done
    if (( ! started )); then
        warn "Service $service belum running setelah 15s"
        services_ready=0
    else
        ok "Service $service running"
    fi
done

info '[7/7] Readback status...'
if command -v pm >/dev/null 2>&1 && ! pm path com.termux.boot >/dev/null 2>&1; then
    warn 'Termux:Boot belum terpasang. Install dari F-Droid lalu buka sekali.'
elif command -v am >/dev/null 2>&1; then
    am start -n com.termux.boot/.BootActivity >/dev/null 2>&1 || true
    ok "Termux:Boot configured: $BOOT_SCRIPT"
fi

if (( services_ready )); then
    ok 'Keybot + Wintercode agent aktif di runit'
    printf 'Status: sv status keybot-watchdog winter-agent\n'
    printf 'Logs  : tail -f %s/var/log/sv/{keybot-watchdog,winter-agent}/current\n' "$PREFIX"
else
    warn 'Service belum semua running; tail ditunda sampai status benar-benar run.'
    printf 'Cek: sv status keybot-watchdog winter-agent\n'
fi
printf 'Device : %s\n' "$(device_model)"
printf 'Device ID : %s\n' "$(device_id)"
