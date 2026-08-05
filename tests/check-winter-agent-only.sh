#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/winter-supervisor.sh"
ORIGINAL_TESTIS_HASH='934fbe4583d90537d07e0cbb3c229dcd1122d46ee85b700652c9795757080743'

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() { grep -Fq -- "$2" "$1" || fail "$1 missing: $2"; }
reject_text() { ! grep -Fq -- "$2" "$1" || fail "$1 contains forbidden: $2"; }

[[ "$(sha256sum "$ROOT/testis.sh" | cut -d' ' -f1)" == "$ORIGINAL_TESTIS_HASH" ]] || fail 'testis.sh changed'
bash -n "$SCRIPT"
reject_text "$SCRIPT" 'keybot-watchdog'
reject_text "$SCRIPT" 'service-daemon'
reject_text "$SCRIPT" 'Termux:Boot'
require_text "$SCRIPT" 'https://api.wintercode.dev/loader/agent-obfuscated.lua'
require_text "$SCRIPT" '/sdcard/Download/agent.lua'
require_text "$SCRIPT" 'Enter script key (32 hex chars):'
require_text "$SCRIPT" 'coproc WINTER_LUA'
require_text "$SCRIPT" 'printf '\''%s\n'\'' "$agent_key" >&"$lua_in"'
reject_text "$SCRIPT" 'printf '\''%s\n'\'' "$agent_key" | lua'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/mockbin" "$TMP/download"
CALLS="$TMP/calls.log"
export CALLS

cat >"$TMP/mockbin/pkg" <<'MOCK'
#!/usr/bin/env bash
printf 'pkg %s\n' "$*" >>"$CALLS"
printf 'mock pkg: %s\n' "$*"
exit 0
MOCK

cat >"$TMP/mockbin/curl" <<'MOCK'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"$CALLS"
[[ "${MOCK_CURL_FAIL:-0}" == 1 ]] && { echo 'mock curl failure' >&2; exit 22; }
out=''
while (($#)); do
    [[ "$1" == -o ]] && { shift; out="$1"; }
    shift || true
done
[[ -n "$out" ]] || exit 2
printf '%s\n' '-- mock agent' >"$out"
exit 0
MOCK

cat >"$TMP/mockbin/lua" <<'MOCK'
#!/usr/bin/env bash
printf 'lua %s\n' "$*" >>"$CALLS"
# Simulate a setup child (pkg/apt) consuming anything sent too early.
IFS= read -r -t 0.2 discarded || true
printf '[SETUP] Dependencies complete\n'
printf 'Enter script key (32 hex chars):'
IFS= read -r key || true
printf '%s\n' "$key" >"$LUA_STDIN"
printf '\nagent raw output: started\n'
exit "${MOCK_LUA_RC:-0}"
MOCK
chmod +x "$TMP/mockbin/"*

KEY_FILE="$TMP/home/.config/winter-supervisor/agent.key"
AGENT_PATH="$TMP/download/agent.lua"
LOG_FILE="$TMP/home/winter_agent.log"
SECRET_ONE='test-secret-one'
SECRET_TWO='test-secret-two'

# First use: ENV wins, gets stored, and reaches Lua stdin without leaking.
LUA_STDIN="$TMP/lua-stdin-1" \
HOME="$TMP/home" PATH="$TMP/mockbin:$PATH" \
WINTER_AGENT_KEY="$SECRET_ONE" WINTER_AGENT_KEY_FILE="$KEY_FILE" \
AGENT_PATH="$AGENT_PATH" WINTER_AGENT_LOG_FILE="$LOG_FILE" \
bash "$SCRIPT" >"$TMP/run1.out" 2>&1
[[ "$(cat "$KEY_FILE")" == "$SECRET_ONE" ]] || fail 'ENV key not stored'
[[ "$(stat -c '%a' "$KEY_FILE")" == 600 ]] || fail 'key mode not 600'
[[ "$(cat "$TMP/lua-stdin-1")" == "$SECRET_ONE" ]] || fail 'ENV key not passed to Lua stdin'
reject_text "$TMP/run1.out" "$SECRET_ONE"
reject_text "$LOG_FILE" "$SECRET_ONE"
require_text "$TMP/run1.out" 'Key source: ENV'
require_text "$TMP/run1.out" 'Key: [REDACTED]'
require_text "$TMP/run1.out" 'agent raw output: started'

# Second use: no ENV; saved key is reused without a prompt.
LUA_STDIN="$TMP/lua-stdin-2" \
HOME="$TMP/home" PATH="$TMP/mockbin:$PATH" \
WINTER_AGENT_KEY_FILE="$KEY_FILE" AGENT_PATH="$AGENT_PATH" \
WINTER_AGENT_LOG_FILE="$LOG_FILE" \
bash "$SCRIPT" >"$TMP/run2.out" 2>&1
[[ "$(cat "$TMP/lua-stdin-2")" == "$SECRET_ONE" ]] || fail 'saved key not reused'
require_text "$TMP/run2.out" 'Key source: saved'
reject_text "$TMP/run2.out" "$SECRET_ONE"

# New ENV rotates saved key.
LUA_STDIN="$TMP/lua-stdin-3" \
HOME="$TMP/home" PATH="$TMP/mockbin:$PATH" \
WINTER_AGENT_KEY="$SECRET_TWO" WINTER_AGENT_KEY_FILE="$KEY_FILE" \
AGENT_PATH="$AGENT_PATH" WINTER_AGENT_LOG_FILE="$LOG_FILE" \
bash "$SCRIPT" >"$TMP/run3.out" 2>&1
[[ "$(cat "$KEY_FILE")" == "$SECRET_TWO" ]] || fail 'new ENV did not rotate saved key'
[[ "$(cat "$TMP/lua-stdin-3")" == "$SECRET_TWO" ]] || fail 'rotated key not passed to Lua'
reject_text "$TMP/run3.out" "$SECRET_TWO"

# Download failure is fatal; Lua must not start.
: >"$CALLS"
set +e
LUA_STDIN="$TMP/lua-stdin-fail" \
HOME="$TMP/home-fail" PATH="$TMP/mockbin:$PATH" MOCK_CURL_FAIL=1 \
WINTER_AGENT_KEY="$SECRET_ONE" WINTER_AGENT_KEY_FILE="$TMP/fail-key" \
AGENT_PATH="$TMP/download/fail-agent.lua" WINTER_AGENT_LOG_FILE="$TMP/fail.log" \
bash "$SCRIPT" >"$TMP/fail.out" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail 'download failure should stop'
require_text "$TMP/fail.out" 'mock curl failure'
! grep -q '^lua ' "$CALLS" || fail 'Lua must not start after download failure'
reject_text "$TMP/fail.out" "$SECRET_ONE"

printf 'Winter agent-only checks passed\n'
