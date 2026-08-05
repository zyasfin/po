#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() { grep -Fq -- "$2" "$1" || fail "$1 missing: $2"; }
reject_text() { ! grep -Fq -- "$2" "$1" || fail "$1 contains forbidden: $2"; }

for file in kiro.sh testis.sh keybot-watchdog.sh winter-agent-runner.sh boot-services.sh; do
  [[ -f "$ROOT/$file" ]] || fail "missing $file"
  bash -n "$ROOT/$file"
done

require_text "$ROOT/kiro.sh" 'pkg install -y termux-services'
require_text "$ROOT/kiro.sh" 'Masukkan key Wintercode agent'
require_text "$ROOT/kiro.sh" 'chmod 600 "$KEY_FILE"'
require_text "$ROOT/kiro.sh" 'keybot-watchdog'
require_text "$ROOT/kiro.sh" 'winter-agent'
require_text "$ROOT/kiro.sh" 'BOOT_SCRIPT="$BOOT_DIR/00-winter-supervisor.sh"'
reject_text "$ROOT/kiro.sh" 'screen -dmS'
reject_text "$ROOT/kiro.sh" 'pkg install -y screen'

require_text "$ROOT/keybot-watchdog.sh" 'com.example.androidkeybot'
require_text "$ROOT/keybot-watchdog.sh" 'BotService'
require_text "$ROOT/keybot-watchdog.sh" 'WATCHDOG_RESTART'
require_text "$ROOT/keybot-watchdog.sh" '.ui.MainActivity'
require_text "$ROOT/keybot-watchdog.sh" 'Heartbeat'

require_text "$ROOT/winter-agent-runner.sh" 'https://api.wintercode.dev/loader/agent-obfuscated.lua'
require_text "$ROOT/winter-agent-runner.sh" 'refresh_agent()'
require_text "$ROOT/winter-agent-runner.sh" 'printf '\''%s\n'\'' "$agent_key" | lua "$AGENT_PATH"'
require_text "$ROOT/winter-agent-runner.sh" 'lua "$AGENT_PATH" </dev/null'
require_text "$ROOT/winter-agent-runner.sh" 'while true'
reject_text "$ROOT/winter-agent-runner.sh" 'echo "$agent_key"'

require_text "$ROOT/boot-services.sh" 'service-daemon start'
require_text "$ROOT/boot-services.sh" 'sv up keybot-watchdog'
require_text "$ROOT/boot-services.sh" 'sv up winter-agent'
require_text "$ROOT/boot-services.sh" 'termux-wake-lock'
require_text "$ROOT/testis.sh" '/kiro.sh'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/prefix/bin" "$TMP/mockbin"
CALLS="$TMP/calls.log"
export CALLS
for command in pkg su termux-wake-lock service-daemon sv am pm screen; do
  cat >"$TMP/mockbin/$command" <<'MOCK'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALLS"
if [[ "$(basename "$0")" == pm && "${1:-}" == path ]]; then echo 'package:/data/app/termux.boot.apk'; fi
exit 0
MOCK
  chmod +x "$TMP/mockbin/$command"
done

HOME="$TMP/home" \
PREFIX="$TMP/prefix" \
PATH="$TMP/mockbin:$PATH" \
KIRO_BASE_URL="file://$ROOT" \
WINTER_AGENT_KEY='test-key-not-a-real-secret' \
bash "$ROOT/kiro.sh" >"$TMP/install.out"

BOOT="$TMP/home/.termux/boot/00-winter-supervisor.sh"
KEY="$TMP/home/.config/winter-supervisor/agent.key"
[[ -x "$BOOT" ]] || fail 'Termux:Boot script not installed'
[[ -x "$TMP/prefix/var/service/keybot-watchdog/run" ]] || fail 'keybot service missing'
[[ -x "$TMP/prefix/var/service/winter-agent/run" ]] || fail 'winter agent service missing'
[[ "$(cat "$KEY")" == 'test-key-not-a-real-secret' ]] || fail 'agent key not stored'
[[ "$(stat -c '%a' "$KEY")" == 600 ]] || fail 'agent key mode is not 600'
reject_text "$TMP/install.out" 'test-key-not-a-real-secret'
require_text "$CALLS" 'sv up keybot-watchdog'
require_text "$CALLS" 'sv up winter-agent'

: >"$CALLS"
HOME="$TMP/home" PREFIX="$TMP/prefix" PATH="$TMP/mockbin:$PATH" TERMUX_BOOT_DELAY=0 bash "$BOOT"
require_text "$CALLS" 'service-daemon start'
require_text "$CALLS" 'sv up keybot-watchdog'
require_text "$CALLS" 'sv up winter-agent'

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
WINTER_AGENT_LOG_FILE="$TMP/agent/agent.log" bash "$ROOT/winter-agent-runner.sh"
[[ "$(cat "$TMP/agent/stdin-with-key")" == 'runner-key' ]] || fail 'saved key not passed to agent stdin'
reject_text "$TMP/agent/agent.log" 'runner-key'

: >"$TMP/agent/key"
LUA_STDIN="$TMP/agent/stdin-empty" \
HOME="$TMP/home" PATH="$TMP/mockbin:$PATH" AGENT_ONCE=1 AGENT_SKIP_REFRESH=1 \
AGENT_PATH="$TMP/agent/agent.lua" WINTER_AGENT_KEY_FILE="$TMP/agent/key" \
WINTER_AGENT_LOG_FILE="$TMP/agent/agent-empty.log" bash "$ROOT/winter-agent-runner.sh"
[[ ! -s "$TMP/agent/stdin-empty" ]] || fail 'empty key should continue without stdin'

cat >"$TMP/mockbin/sleep" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$TMP/mockbin/sleep"
: >"$CALLS"
HOME="$TMP/home" PATH="$TMP/mockbin:$PATH" WATCHDOG_ONCE=1 \
KEYBOT_LOG_FILE="$TMP/keybot.log" bash "$ROOT/keybot-watchdog.sh"
require_text "$CALLS" 'su -c pidof com.example.androidkeybot'
require_text "$CALLS" 'su -c am broadcast -a com.example.androidkeybot.WATCHDOG_RESTART'
require_text "$CALLS" 'BotService'

printf 'Unified supervisor checks passed\n'
