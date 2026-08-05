#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() { grep -Fq -- "$2" "$1" || fail "$1 missing: $2"; }
reject_text() { ! grep -Fq -- "$2" "$1" || fail "$1 contains forbidden: $2"; }

INSTALLER="$ROOT/testis.sh"
[[ -f "$INSTALLER" ]] || fail 'missing testis.sh'
bash -n "$INSTALLER"

# Single-file architecture: standalone service scripts must be gone
for file in kiro.sh keybot-watchdog.sh winter-agent-runner.sh boot-services.sh; do
  [[ ! -f "$ROOT/$file" ]] || fail "$file should be embedded in testis.sh, not standalone"
done

# Self-contained: no fetching of repo scripts
reject_text "$INSTALLER" 'KIRO_BASE_URL'
reject_text "$INSTALLER" 'BASE_URL'
reject_text "$INSTALLER" 'fetch()'

# Installer behavior
require_text "$INSTALLER" 'pkg install -y termux-services'
require_text "$INSTALLER" 'Masukkan key Wintercode agent'
require_text "$INSTALLER" 'chmod 600 "$KEY_FILE"'
require_text "$INSTALLER" 'keybot-watchdog'
require_text "$INSTALLER" 'winter-agent'
require_text "$INSTALLER" 'BOOT_SCRIPT="$BOOT_DIR/00-winter-supervisor.sh"'
require_text "$INSTALLER" 'wait_for_service_daemon()'
require_text "$INSTALLER" 'run_root()'
require_text "$INSTALLER" 'Root tweak gagal'
require_text "$INSTALLER" 'Root tweaks applied'
reject_text "$INSTALLER" 'screen -dmS'
reject_text "$INSTALLER" 'pkg install -y screen'

# SVDIR must be persisted for interactive shells (sv resolves names via SVDIR)
require_text "$INSTALLER" 'export SVDIR='
require_text "$INSTALLER" '>>"$HOME/.bashrc"'

# Embedded keybot watchdog content
require_text "$INSTALLER" 'com.example.androidkeybot'
require_text "$INSTALLER" 'BotService'
require_text "$INSTALLER" 'WATCHDOG_RESTART'
require_text "$INSTALLER" '.ui.MainActivity'
require_text "$INSTALLER" 'Heartbeat'

# Embedded winter agent runner content
require_text "$INSTALLER" 'https://api.wintercode.dev/loader/agent-obfuscated.lua'
require_text "$INSTALLER" 'refresh_agent()'
require_text "$INSTALLER" 'printf '\''%s\n'\'' "$agent_key" | lua "$AGENT_PATH"'
require_text "$INSTALLER" 'lua "$AGENT_PATH" </dev/null'
reject_text "$INSTALLER" 'echo "$agent_key"'

# Embedded boot services content
require_text "$INSTALLER" 'service-daemon start'
require_text "$INSTALLER" 'sv up keybot-watchdog'
require_text "$INSTALLER" 'sv up winter-agent'
require_text "$INSTALLER" 'termux-wake-lock'

# --print-service seam must emit each embedded script
for name in keybot-watchdog winter-agent boot-services; do
  bash "$INSTALLER" --print-service "$name" >/dev/null || fail "--print-service $name failed"
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/prefix/bin" "$TMP/mockbin"
CALLS="$TMP/calls.log"
export CALLS
for command in pkg su termux-wake-lock service-daemon am pm screen; do
  cat >"$TMP/mockbin/$command" <<'MOCK'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALLS"
if [[ "$(basename "$0")" == pm && "${1:-}" == path ]]; then echo 'package:/data/app/termux.boot.apk'; fi
if [[ "$(basename "$0")" == service-daemon && "${1:-}" == start ]]; then
    mkdir -p "$PREFIX/var/run"
    sleep 30 &
    echo $! >"$PREFIX/var/run/service-daemon.pid"
fi
exit 0
MOCK
  chmod +x "$TMP/mockbin/$command"
done

# Strict sv mock: like real runit, sv fails until runsvdir supervises the
# service (supervise/ dir exists). First query per service simulates the
# runsvdir scan landing, so installers must WAIT + RETRY before sv up.
cat >"$TMP/mockbin/sv" <<'MOCK'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALLS"
if [[ "${1:-}" == up || "${1:-}" == status ]]; then
    if [[ ! -d "$SVDIR/$2/supervise" ]]; then
        mkdir -p "$SVDIR/$2/supervise"
        echo "sv: fatal: unable to chdir to $2/supervise: file does not exist" >&2
        exit 1
    fi
fi
exit 0
MOCK
chmod +x "$TMP/mockbin/sv"

# Full install run
HOME="$TMP/home" \
PREFIX="$TMP/prefix" \
PATH="$TMP/mockbin:$PATH" \
WINTER_AGENT_KEY='test-key-not-a-real-secret' \
bash "$INSTALLER" >"$TMP/install.out"

BOOT="$TMP/home/.termux/boot/00-winter-supervisor.sh"
KEY="$TMP/home/.config/winter-supervisor/agent.key"
[[ -x "$BOOT" ]] || fail 'Termux:Boot script not installed'
[[ -x "$TMP/prefix/var/service/keybot-watchdog/run" ]] || fail 'keybot service missing'
[[ -x "$TMP/prefix/var/service/winter-agent/run" ]] || fail 'winter agent service missing'
[[ -x "$TMP/home/.local/lib/winter-supervisor/keybot-watchdog.sh" ]] || fail 'keybot script not installed'
[[ -x "$TMP/home/.local/lib/winter-supervisor/winter-agent-runner.sh" ]] || fail 'agent runner not installed'
[[ "$(cat "$KEY")" == 'test-key-not-a-real-secret' ]] || fail 'agent key not stored'
[[ "$(stat -c '%a' "$KEY")" == 600 ]] || fail 'agent key mode is not 600'
reject_text "$TMP/install.out" 'test-key-not-a-real-secret'
require_text "$TMP/install.out" 'aktif di runit'
require_text "$TMP/install.out" 'Root tweaks applied'
require_text "$TMP/home/.bashrc" 'export SVDIR='
require_text "$CALLS" 'sv status keybot-watchdog'
require_text "$CALLS" 'sv up keybot-watchdog'
require_text "$CALLS" 'sv up winter-agent'

# Boot script behavior
: >"$CALLS"
HOME="$TMP/home" PREFIX="$TMP/prefix" PATH="$TMP/mockbin:$PATH" TERMUX_BOOT_DELAY=0 bash "$BOOT"
require_text "$CALLS" 'service-daemon start'
require_text "$CALLS" 'sv up keybot-watchdog'
require_text "$CALLS" 'sv up winter-agent'

# Extracted winter agent runner: key via stdin, never in logs
bash "$INSTALLER" --print-service winter-agent >"$TMP/runner.sh"
cat >"$TMP/mockbin/lua" <<'MOCK'
#!/usr/bin/env bash
cat >"$LUA_STDIN"
exit 0
MOCK
chmod +x "$TMP/mockbin/lua"
mkdir -p "$TMP/agent"
: >"$TMP/agent/agent.lua"
printf '%s\n' 'runner-key' >"$TMP/agent/key"
LUA_STDIN="$TMP/agent/stdin-with-key" \
HOME="$TMP/home" PATH="$TMP/mockbin:$PATH" AGENT_ONCE=1 AGENT_SKIP_REFRESH=1 \
AGENT_PATH="$TMP/agent/agent.lua" WINTER_AGENT_KEY_FILE="$TMP/agent/key" \
WINTER_AGENT_LOG_FILE="$TMP/agent/agent.log" bash "$TMP/runner.sh"
[[ "$(cat "$TMP/agent/stdin-with-key")" == 'runner-key' ]] || fail 'saved key not passed to agent stdin'
reject_text "$TMP/agent/agent.log" 'runner-key'

# Empty key path: agent runs without stdin input
: >"$TMP/agent/key"
LUA_STDIN="$TMP/agent/stdin-empty" \
HOME="$TMP/home" PATH="$TMP/mockbin:$PATH" AGENT_ONCE=1 AGENT_SKIP_REFRESH=1 \
AGENT_PATH="$TMP/agent/agent.lua" WINTER_AGENT_KEY_FILE="$TMP/agent/key" \
WINTER_AGENT_LOG_FILE="$TMP/agent/agent-empty.log" bash "$TMP/runner.sh"
[[ ! -s "$TMP/agent/stdin-empty" ]] || fail 'empty key should continue without stdin'

# Extracted keybot watchdog: detects dead service, recovers via broadcast
bash "$INSTALLER" --print-service keybot-watchdog >"$TMP/keybot.sh"
cat >"$TMP/mockbin/sleep" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$TMP/mockbin/sleep"
: >"$CALLS"
HOME="$TMP/home" PATH="$TMP/mockbin:$PATH" WATCHDOG_ONCE=1 \
KEYBOT_LOG_FILE="$TMP/keybot.log" bash "$TMP/keybot.sh"
require_text "$CALLS" 'su -c pidof com.example.androidkeybot'
require_text "$CALLS" 'su -c am broadcast -a com.example.androidkeybot.WATCHDOG_RESTART'
require_text "$CALLS" 'BotService'

printf 'Unified supervisor checks passed\n'
