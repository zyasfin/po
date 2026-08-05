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

root_available() {
    command -v su >/dev/null 2>&1 && su -c 'id' >/dev/null 2>&1
}

service_running() {
    local pid
    pid="$(su -c "pidof $PACKAGE_NAME" 2>/dev/null || true)"
    [[ -n "$pid" ]] || return 1
    su -c "dumpsys activity services $PACKAGE_NAME 2>/dev/null | grep -q 'BotService'" 2>/dev/null && return 0
    sleep 2
    su -c "dumpsys activity services $PACKAGE_NAME 2>/dev/null | grep -q 'BotService'" 2>/dev/null
}

get_app_pid() {
    su -c "pidof $PACKAGE_NAME" 2>/dev/null || printf 'unknown\n'
}

wait_for_service() {
    local timeout="$1" waited=0
    while (( waited < timeout )); do
        sleep 1
        waited=$((waited + 1))
        if su -c "dumpsys activity services $PACKAGE_NAME 2>/dev/null | grep -q 'BotService'" 2>/dev/null; then
            log_message "Started (PID: $(get_app_pid), ${waited}s)"
            return 0
        fi
    done
    return 1
}

start_app() {
    log_message "Starting Android Key Bot via watchdog broadcast..."
    su -c "am broadcast -a $RESTART_ACTION -n ${PACKAGE_NAME}/.receiver.WatchdogReceiver" >/dev/null 2>&1 || true
    if wait_for_service 10; then
        return 0
    fi

    log_message "Broadcast timeout; mencoba MainActivity..."
    su -c "am start -n ${PACKAGE_NAME}/.ui.MainActivity" >/dev/null 2>&1 || true
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
