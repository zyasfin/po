#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

START_TS="$(date +%s)"
TTY="${TTY_DEVICE:-/dev/tty}"
SETUP_LOG="${SETUP_LOG_FILE:-$HOME/.setup/winter-agent-setup.log}"
AGENT_URL="${AGENT_URL:-https://api.wintercode.dev/loader/agent-obfuscated.lua}"
AGENT_PATH="${AGENT_PATH:-/sdcard/Download/agent.lua}"
KEY_FILE="${WINTER_AGENT_KEY_FILE:-$HOME/.config/winter-supervisor/agent.key}"
AGENT_LOG="${WINTER_AGENT_LOG_FILE:-$HOME/winter_agent.log}"

info() { printf "  ${DIM}[INFO]${NC}  %s\n" "$*"; }
warn() { printf "  ${RED}[WARN]${NC}  %s\n" "$*" >&2; }
ok() { printf "  ${GREEN}[OK]${NC}    %s\n" "$*"; }
step() { printf "\n  ${GREEN}[%02d]${NC} %s\n" "$1" "$2"; }
elapsed() { printf '%s' "$(( $(date +%s) - START_TS ))"; }

run_progress() {
    local title="$1" est="$2" rc=0
    shift 2
    mkdir -p "$(dirname "$SETUP_LOG")"
    : >"$SETUP_LOG"
    ("$@") >>"$SETUP_LOG" 2>&1 &
    local pid=$! elapsed_local=0 pos=0 dir=1 width=18 frame=0
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

    printf '\n'
    while kill -0 "$pid" 2>/dev/null; do
        local bar='' column spinner
        for ((column=0; column<width; column++)); do
            [[ "$column" -eq "$pos" ]] && bar+='▓' || bar+='░'
        done
        spinner="${frames[$((frame % ${#frames[@]}))]}"
        frame=$((frame + 1))
        printf "\r  ${DIM}[+$(elapsed)]${NC} %s [%s] %02d:%02d  %-30s" \
            "$spinner" "$bar" "$((elapsed_local / 60))" "$((elapsed_local % 60))" "$title"
        pos=$((pos + dir))
        [[ "$pos" -ge $((width - 1)) ]] && dir=-1
        [[ "$pos" -le 0 ]] && dir=1
        elapsed_local=$((elapsed_local + 1))
        sleep 0.18
    done

    if wait "$pid"; then rc=0; else rc=$?; fi
    if (( rc == 0 )); then
        printf "\r  ${GREEN}✅${NC} %-50s %02d:%02d\n" \
            "$title" "$((elapsed_local / 60))" "$((elapsed_local % 60))"
        return 0
    fi

    printf "\r  ${RED}❌${NC} %-50s exit=%d\n" "$title" "$rc"
    tail -n 60 "$SETUP_LOG" || true
    return "$rc"
}

load_agent_key() {
    local key=''
    if [[ -n "${WINTER_AGENT_KEY:-}" ]]; then
        key="$WINTER_AGENT_KEY"
        KEY_SOURCE='ENV'
    elif [[ -s "$KEY_FILE" ]]; then
        IFS= read -r key <"$KEY_FILE" || true
        KEY_SOURCE='saved'
    else
        KEY_SOURCE='prompt'
        if [[ -r "$TTY" ]]; then
            IFS= read -r -p 'Masukkan key Wintercode agent: ' key <"$TTY" || true
        elif [[ -t 0 ]]; then
            IFS= read -r -p 'Masukkan key Wintercode agent: ' key || true
        fi
    fi

    [[ -n "$key" ]] || return 1
    mkdir -p "$(dirname "$KEY_FILE")"
    umask 077
    printf '%s\n' "$key" >"$KEY_FILE"
    chmod 600 "$KEY_FILE"
    agent_key="$key"
}

step 1 'Installing dependencies'
run_progress 'pkg update' 30 bash -c 'pkg update -y'
for package in lua54 sqlite; do
    run_progress "pkg install $package" 30 pkg install -y "$package"
done

step 2 'Loading Wintercode key'
agent_key=''
KEY_SOURCE=''
if ! load_agent_key; then
    warn 'Key kosong; installer berhenti.'
    exit 1
fi
info "Key source: $KEY_SOURCE"
info 'Key: [REDACTED]'
ok "Key tersimpan privat: $KEY_FILE (mode 600)"

step 3 'Downloading Wintercode agent'
mkdir -p "$(dirname "$AGENT_PATH")" "$(dirname "$AGENT_LOG")"
rm -f "${AGENT_PATH}.tmp"
run_progress 'download agent.lua' 30 curl -fL "$AGENT_URL" -o "${AGENT_PATH}.tmp"
[[ -s "${AGENT_PATH}.tmp" ]] || { warn 'Agent hasil download kosong.'; exit 1; }
mv "${AGENT_PATH}.tmp" "$AGENT_PATH"
ok "Agent downloaded: $AGENT_PATH"

step 4 'Running Wintercode agent'
info "Raw agent output (also saved to $AGENT_LOG):"
if printf '%s\n' "$agent_key" | lua "$AGENT_PATH" 2>&1 | tee -a "$AGENT_LOG"; then
    rc=0
else
    rc=$?
fi
agent_key=''
if (( rc != 0 )); then
    warn "Wintercode agent berhenti dengan exit $rc"
    exit "$rc"
fi
ok 'Wintercode agent selesai tanpa error'
