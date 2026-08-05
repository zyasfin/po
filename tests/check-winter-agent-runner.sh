#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/winter-supervisor.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() { grep -Fq -- "$2" "$1" || fail "$1 missing: $2"; }
reject_text() { ! grep -Fq -- "$2" "$1" || fail "$1 contains forbidden: $2"; }

TMP="$(mktemp -d)"
WATCHDOG_PID=''
cleanup() {
    [[ -s "$TMP/watchdog.pid" ]] && WATCHDOG_PID="$(cat "$TMP/watchdog.pid")"
    [[ "$WATCHDOG_PID" =~ ^[0-9]+$ ]] && kill "$WATCHDOG_PID" 2>/dev/null || true
    rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/home/.config/winter-supervisor" "$TMP/mockbin" "$TMP/download"
printf '%s\n' '0123456789ABCDEF0123456789ABCDEF' >"$TMP/home/.config/winter-supervisor/agent.key"
chmod 600 "$TMP/home/.config/winter-supervisor/agent.key"
bash "$SCRIPT" --print-service winter-agent >"$TMP/runner.sh"
bash -n "$TMP/runner.sh"
CALLS="$TMP/calls.log"; export CALLS

cat >"$TMP/mockbin/curl" <<'MOCK'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"$CALLS"
out=''
while (($#)); do [[ "$1" == -o ]] && { shift; out="$1"; }; shift || true; done
printf '%s\n' '-- mock agent' >"$out"
MOCK

cat >"$TMP/mockbin/lua" <<'MOCK'
#!/usr/bin/env bash
printf 'lua %s\n' "$*" >>"$CALLS"
# Simulate Wintercode auto-boot: no key prompt, launcher daemonizes and its
# internal root watchdog becomes the durable process.
python3 - "$WINTER_AGENT_LOG_FILE" "$WATCHDOG_PID_FILE" <<'PY'
import os, signal, sys, time
pid = os.fork()
if pid:
    raise SystemExit(0)
os.setsid()
signal.signal(signal.SIGHUP, signal.SIG_IGN)
with open(sys.argv[2], 'w') as f:
    f.write(str(os.getpid()))
with open(sys.argv[1], 'a') as f:
    f.write('[WATCHDOG] Started as root (pid %d) test\n' % os.getpid())
devnull = os.open('/dev/null', os.O_RDWR)
for fd in (0, 1, 2): os.dup2(devnull, fd)
time.sleep(60)
PY
for _ in $(seq 1 20); do [[ -s "$WATCHDOG_PID_FILE" ]] && break; sleep 0.05; done
printf 'Agent running in background (PID 99999)\n'
printf 'Tailing log... (Ctrl+C to detach, agent keeps running)\n'
exit 137
MOCK
chmod +x "$TMP/mockbin/"*

set +e
HOME="$TMP/home" PATH="$TMP/mockbin:$PATH" \
AGENT_PATH="$TMP/download/agent.lua" \
WINTER_AGENT_LOG_FILE="$TMP/home/.winterhub/agent.log" \
WATCHDOG_PID_FILE="$TMP/watchdog.pid" \
AGENT_RUNNER_ONCE=1 AGENT_MONITOR_INTERVAL=0.1 AGENT_WATCHDOG_WAIT=5 \
timeout 15 bash "$TMP/runner.sh" >"$TMP/runner.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] || { tail -n 80 "$TMP/runner.out"; fail "runner exit=$rc"; }
[[ -s "$TMP/watchdog.pid" ]] || fail 'watchdog pid missing'
WATCHDOG_PID="$(cat "$TMP/watchdog.pid")"
kill -0 "$WATCHDOG_PID" 2>/dev/null || fail 'watchdog is not alive'
[[ "$(grep -c '^lua ' "$CALLS")" -eq 1 ]] || fail 'Lua launched more than once'
require_text "$TMP/runner.out" "Wintercode watchdog alive: PID $WATCHDOG_PID"
require_text "$TMP/runner.out" 'Wintercode agent active'
reject_text "$TMP/runner.out" 'Key prompt not found'
reject_text "$TMP/runner.out" 'restart'

# A second runner (for example Termux:Boot racing Wintercode auto-boot) must
# adopt the already-live internal watchdog instead of launching Lua again.
: >"$CALLS"
HOME="$TMP/home" PATH="$TMP/mockbin:$PATH" \
AGENT_PATH="$TMP/download/agent.lua" \
WINTER_AGENT_LOG_FILE="$TMP/home/.winterhub/agent.log" \
WATCHDOG_PID_FILE="$TMP/watchdog2.pid" \
AGENT_RUNNER_ONCE=1 AGENT_MONITOR_INTERVAL=0.1 AGENT_WATCHDOG_WAIT=5 \
timeout 10 bash "$TMP/runner.sh" >"$TMP/adopt.out" 2>&1
! grep -q '^lua ' "$CALLS" || fail 'existing live watchdog should prevent another Lua launch'
require_text "$TMP/adopt.out" "Adopting existing Wintercode watchdog: PID $WATCHDOG_PID"
require_text "$TMP/adopt.out" 'Wintercode agent active'

printf 'Winter agent runner lifecycle checks passed\n'
