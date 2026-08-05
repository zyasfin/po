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
