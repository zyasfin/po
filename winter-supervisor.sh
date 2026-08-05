#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; DIM='\033[2m'; NC='\033[0m'
START_TS="$(date +%s)"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PREFIX
SVDIR="${SVDIR:-$PREFIX/var/service}"; export SVDIR
LOGDIR="${LOGDIR:-$PREFIX/var/log}"; export LOGDIR
INSTALL_DIR="$HOME/.local/lib/winter-supervisor"
CONFIG_DIR="$HOME/.config/winter-supervisor"
KEY_FILE="${WINTER_AGENT_KEY_FILE:-$CONFIG_DIR/agent.key}"
BOOT_DIR="$HOME/.termux/boot"
BOOT_SCRIPT="$BOOT_DIR/00-winter-supervisor.sh"
AGENT_URL="${AGENT_URL:-https://api.wintercode.dev/loader/agent-obfuscated.lua}"
AGENT_PATH="${AGENT_PATH:-/sdcard/Download/agent.lua}"
AGENT_LOG="${WINTER_AGENT_LOG_FILE:-$HOME/.winterhub/agent.log}"

info() { printf "  ${DIM}[INFO]${NC}  %s\n" "$*"; }
warn() { printf "  ${RED}[WARN]${NC}  %s\n" "$*" >&2; }
ok() { printf "  ${GREEN}[OK]${NC}    %s\n" "$*"; }
step() { printf "\n  ${GREEN}[%02d]${NC} %s\n" "$1" "$2"; }

print_service() {
    case "$1" in
    keybot-watchdog)
        cat <<'SERVICE_EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -u
PACKAGE_NAME="${PACKAGE_NAME:-com.example.androidkeybot}"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
RESTART_ACTION="${RESTART_ACTION:-com.example.androidkeybot.WATCHDOG_RESTART}"
LOG_FILE="${KEYBOT_LOG_FILE:-$HOME/keybot_watchdog.log}"
MAX_LOG_LINES="${MAX_LOG_LINES:-1000}"
log_message() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    printf '%s\n' "$msg" | tee -a "$LOG_FILE"
    if [[ -f "$LOG_FILE" ]] && (( $(wc -l < "$LOG_FILE") > MAX_LOG_LINES )); then
        tail -n 500 "$LOG_FILE" >"${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
}
is_app_running() {
    local pid
    pid="$(su -c "pidof $PACKAGE_NAME" 2>/dev/null || true)"
    [[ -n "$pid" ]] || return 1
    su -c "dumpsys activity services $PACKAGE_NAME 2>/dev/null | grep -q 'BotService'" 2>/dev/null && return 0
    sleep 2
    su -c "dumpsys activity services $PACKAGE_NAME 2>/dev/null | grep -q 'BotService'" 2>/dev/null
}
get_app_pid() { su -c "pidof $PACKAGE_NAME" 2>/dev/null || printf 'unknown\n'; }
start_app() {
    log_message "Starting Android Key Bot..."
    log_message "Trying broadcast..."
    su -c "am broadcast -a $RESTART_ACTION -n ${PACKAGE_NAME}/.receiver.WatchdogReceiver" >/dev/null 2>&1
    local waited=0
    while (( waited < 10 )); do
        sleep 1; waited=$((waited + 1))
        if su -c "dumpsys activity services $PACKAGE_NAME 2>/dev/null | grep -q 'BotService'" 2>/dev/null; then
            log_message "Started via broadcast (PID: $(get_app_pid), ${waited}s)"; return 0
        fi
    done
    log_message "Broadcast timeout"
    log_message "Trying MainActivity..."
    su -c "am start -n ${PACKAGE_NAME}/.ui.MainActivity" >/dev/null 2>&1
    waited=0
    while (( waited < 8 )); do
        sleep 1; waited=$((waited + 1))
        if su -c "dumpsys activity services $PACKAGE_NAME 2>/dev/null | grep -q 'BotService'" 2>/dev/null; then
            log_message "Started via MainActivity (PID: $(get_app_pid), ${waited}s)"; return 0
        fi
    done
    log_message "All start methods failed"; return 1
}
if ! su -c 'id' >/dev/null 2>&1; then log_message 'Root unavailable'; exit 1; fi
log_message "Keybot watchdog active — package: $PACKAGE_NAME; interval: ${CHECK_INTERVAL}s"
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock >/dev/null 2>&1 || true
failures=0; loops=0
while true; do
    if ! is_app_running; then
        failures=$((failures + 1)); log_message "App/BotService stopped (failure #$failures)"
        if start_app; then log_message 'Recovery succeeded'; failures=0; fi
        if (( failures >= 3 )); then log_message '3 failures; cooldown 5 minutes'; sleep 300; failures=0; fi
    elif (( failures > 0 )); then
        log_message "App recovered (PID: $(get_app_pid))"; failures=0
    fi
    loops=$((loops + 1)); if (( loops % 10 == 0 )); then log_message "Heartbeat — PID: $(get_app_pid)"; fi
    sleep "$CHECK_INTERVAL"
done
SERVICE_EOF
        ;;
    winter-agent)
        cat <<'SERVICE_EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -u
AGENT_URL="${AGENT_URL:-https://api.wintercode.dev/loader/agent-obfuscated.lua}"
AGENT_PATH="${AGENT_PATH:-/sdcard/Download/agent.lua}"
KEY_FILE="${WINTER_AGENT_KEY_FILE:-$HOME/.config/winter-supervisor/agent.key}"
AGENT_LOG="${WINTER_AGENT_LOG_FILE:-$HOME/.winterhub/agent.log}"
RESTART_DELAY="${AGENT_RESTART_DELAY:-10}"
log_message() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    printf '%s\n' "$msg" | tee -a "$AGENT_LOG"
}
run_once() {
    local prompt='Enter script key (32 hex chars):' prompt_tail='' output_tail='' char='' sent=0 rc=0 lua_command='' background_pid=''
    mkdir -p "$(dirname "$AGENT_PATH")" "$(dirname "$AGENT_LOG")"
    if ! curl -fsSL "$AGENT_URL" -o "${AGENT_PATH}.tmp"; then log_message 'Agent download failed'; return 1; fi
    [[ -s "${AGENT_PATH}.tmp" ]] || { log_message 'Agent download empty'; return 1; }
    mv "${AGENT_PATH}.tmp" "$AGENT_PATH"
    agent_key=''; [[ -s "$KEY_FILE" ]] && IFS= read -r agent_key <"$KEY_FILE" || true
    [[ -n "$agent_key" ]] || { log_message 'Saved key empty'; return 1; }
    command -v script >/dev/null 2>&1 || { log_message 'script command missing'; return 1; }
    printf -v lua_command 'exec lua %q' "$AGENT_PATH"
    coproc WINTER_LUA { exec script -q -E never -c "$lua_command" /dev/null 2>&1; }
    local lua_pid="$WINTER_LUA_PID" coproc_out="${WINTER_LUA[0]}" coproc_in="${WINTER_LUA[1]}" lua_out lua_in
    exec {lua_out}<&"$coproc_out"; exec {lua_in}>&"$coproc_in"
    trap 'kill "$lua_pid" 2>/dev/null || true' INT TERM
    while IFS= read -r -N 1 -u "$lua_out" char; do
        printf '%s' "$char" | tee -a "$AGENT_LOG"
        output_tail="${output_tail}${char}"; (( ${#output_tail} > 192 )) && output_tail="${output_tail: -192}"
        [[ "$output_tail" =~ Agent\ running\ in\ background\ \(PID\ ([0-9]+)\) ]] && background_pid="${BASH_REMATCH[1]}"
        if (( ! sent )); then
            prompt_tail="${prompt_tail}${char}"; (( ${#prompt_tail} > 96 )) && prompt_tail="${prompt_tail: -96}"
            if [[ "$prompt_tail" == *"$prompt"* ]]; then
                printf '%s\n' "$agent_key" >&"$lua_in"; sent=1; log_message 'Key injected after prompt'
            fi
        fi
    done
    exec 3>&- 2>/dev/null || true; exec {lua_out}<&-; exec {lua_in}>&-
    wait "$lua_pid" 2>/dev/null; rc=$?
    trap - INT TERM; agent_key=''
    (( sent == 1 )) || { log_message 'Key prompt not found'; return 1; }
    if [[ "$background_pid" =~ ^[0-9]+$ ]]; then
        for _ in $(seq 1 10); do kill -0 "$background_pid" 2>/dev/null && { log_message "Background agent alive: PID $background_pid"; return 0; }; sleep 0.1; done
        log_message "Background agent dead: PID $background_pid"; return 1
    fi
    return "$rc"
}
while true; do
    log_message 'Starting Wintercode agent...'
    if run_once; then log_message 'Wintercode agent active'; else log_message 'Wintercode agent exited; restart'; fi
    sleep "$RESTART_DELAY"
done
SERVICE_EOF
        ;;
    boot-services)
        cat <<'SERVICE_EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -u
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"; export PREFIX
SVDIR="${SVDIR:-$PREFIX/var/service}"; export SVDIR
LOGDIR="${LOGDIR:-$PREFIX/var/log}"; export LOGDIR
sleep "${TERMUX_BOOT_DELAY:-8}"
mkdir -p "$SVDIR" "$LOGDIR/sv"
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock >/dev/null 2>&1 || true
service-daemon start >/dev/null 2>&1 || true
sleep 2
sv up keybot-watchdog
sv up winter-agent
SERVICE_EOF
        ;;
    *) return 1 ;;
    esac
}

if [[ "${1:-}" == --print-service ]]; then print_service "${2:-}"; exit $?; fi

run_progress() {
    local title="$1"; shift
    local log_file="$HOME/.setup/winter-supervisor.log"
    mkdir -p "$(dirname "$log_file")"; : >"$log_file"
    ("$@") >"$log_file" 2>&1 & local pid=$! elapsed=0 pos=0 dir=1
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏') frame=0
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  ${DIM}[%s]${NC} %-34s' "${frames[$((frame % ${#frames[@]}))]}" "$title"
        frame=$((frame + 1)); elapsed=$((elapsed + 1)); sleep 1
    done
    if wait "$pid"; then
        printf '\r  ${GREEN}✅${NC} %-34s\n' "$title"
    else
        rc=$?; printf '\r  ${RED}❌${NC} %-34s exit=%s\n' "$title" "$rc"; tail -n 60 "$log_file"; return "$rc"
    fi
}

read_key() {
    local key=''
    if [[ -n "${WINTER_AGENT_KEY:-}" ]]; then key="$WINTER_AGENT_KEY"; KEY_SOURCE='ENV'
    elif [[ -s "$KEY_FILE" ]]; then IFS= read -r key <"$KEY_FILE" || true; KEY_SOURCE='saved'
    elif [[ -r /dev/tty ]]; then KEY_SOURCE='prompt'; IFS= read -r -p 'Masukkan key Wintercode agent: ' key </dev/tty || true
    else KEY_SOURCE='prompt'; IFS= read -r -p 'Masukkan key Wintercode agent: ' key || true; fi
    [[ -n "$key" ]] || return 1
    mkdir -p "$(dirname "$KEY_FILE")"; umask 077; printf '%s\n' "$key" >"$KEY_FILE"; chmod 600 "$KEY_FILE"; agent_key="$key"
}

step 1 'Installing dependencies'
run_progress 'pkg update' pkg update -y
run_progress 'pkg install termux-services' pkg install -y termux-services
run_progress 'pkg install curl' pkg install -y curl
run_progress 'pkg install lua54' pkg install -y lua54
run_progress 'pkg install sqlite' pkg install -y sqlite
run_progress 'pkg install termux-api' pkg install -y termux-api

step 2 'Applying root tweaks'
su -c 'wm density 200 && settings put global window_animation_scale 0 && settings put global transition_animation_scale 0 && settings put global animator_duration_scale 0 && settings put global force_resizable_activities 1 && settings put global enable_freeform_support 1'
ok 'Root tweaks applied'

step 3 'Loading Wintercode key'
agent_key=''; KEY_SOURCE=''; read_key || { warn 'Key kosong; stop'; exit 1; }
info "Key source: $KEY_SOURCE"; info 'Key: [REDACTED]'; ok 'Key saved mode 600'

step 4 'Installing service files'
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$BOOT_DIR" "$SVDIR" "$LOGDIR/sv"
print_service keybot-watchdog >"$INSTALL_DIR/keybot-watchdog.sh"
print_service winter-agent >"$INSTALL_DIR/winter-agent-runner.sh"
print_service boot-services >"$INSTALL_DIR/boot-services.sh"
chmod 700 "$INSTALL_DIR"/*.sh

step 5 'Installing Termux:Boot'
pm path com.termux.boot
am start -n com.termux.boot/.BootActivity
cp "$INSTALL_DIR/boot-services.sh" "$BOOT_SCRIPT"; chmod 700 "$BOOT_SCRIPT"

install_service() {
    local name="$1" path="$2"
    mkdir -p "$SVDIR/$name/log" "$LOGDIR/sv/$name"
    printf '#!/data/data/com.termux/files/usr/bin/sh\nexec "%s"\n' "$path" >"$SVDIR/$name/run"
    printf '#!/data/data/com.termux/files/usr/bin/sh\nexec svlogd -tt "%s"\n' "$LOGDIR/sv/$name" >"$SVDIR/$name/log/run"
    printf '#!/data/data/com.termux/files/usr/bin/sh\nsleep 10\n' >"$SVDIR/$name/finish"
    chmod 700 "$SVDIR/$name/run" "$SVDIR/$name/log/run" "$SVDIR/$name/finish"; rm -f "$SVDIR/$name/down"
}

step 6 'Starting runit services'
termux-wake-lock
install_service keybot-watchdog "$INSTALL_DIR/keybot-watchdog.sh"
install_service winter-agent "$INSTALL_DIR/winter-agent-runner.sh"
service-daemon start
sleep 2
sv up keybot-watchdog
sv up winter-agent


step 7 'Readback status'
sv status keybot-watchdog winter-agent
for service in keybot-watchdog winter-agent; do
    log_file="$LOGDIR/sv/$service/current"
    [[ -s "$log_file" ]] || { warn "Missing raw log: $log_file"; exit 1; }
    printf '[RAW SERVICE LOG: %s]\n' "$service"
    tail -n 20 "$log_file"
done
ok 'Keybot + Wintercode agent aktif di runit'
ok "Termux:Boot: $BOOT_SCRIPT"
printf 'Logs: tail -f %s/var/log/sv/{keybot-watchdog,winter-agent}/current\n' "$PREFIX"
