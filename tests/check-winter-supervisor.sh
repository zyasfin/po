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
require_text "$SCRIPT" 'su -c'
require_text "$SCRIPT" 'wm density 200'
require_text "$SCRIPT" 'settings put global window_animation_scale 0'
require_text "$SCRIPT" 'Root tweak $index/6'
require_text "$SCRIPT" 'RAW OUTPUT (direct)'
require_text "$SCRIPT" 'if su -c "$tweak"'
reject_text "$SCRIPT" 'output="$(su -c'
reject_text "$SCRIPT" 'su -c "$tweak" 2>&1'
require_text "$SCRIPT" 'TWEAK_OK'
require_text "$SCRIPT" 'TWEAK_FAIL'
require_text "$SCRIPT" 'run_progress'
require_text "$SCRIPT" 'pkg update -y'
require_text "$SCRIPT" 'keybot-watchdog'
require_text "$SCRIPT" 'winter-agent'
require_text "$SCRIPT" 'boot-services'
require_text "$SCRIPT" 'service-daemon start'
require_text "$SCRIPT" 'sv up keybot-watchdog'
require_text "$SCRIPT" 'sv up winter-agent'
require_text "$SCRIPT" 'pm path com.termux.boot'
reject_text "$SCRIPT" 'screen -dmS'
reject_text "$SCRIPT" 'screen -S watchdog_keybot'
require_text "$SCRIPT" 'WINTER_AGENT_KEY'
require_text "$SCRIPT" 'KEY_FILE'

for service in keybot-watchdog winter-agent boot-services; do
    bash "$SCRIPT" --print-service "$service" >/dev/null || fail "print service $service failed"
done
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
bash "$SCRIPT" --print-service keybot-watchdog >"$TMP/keybot-service.sh"
bash "$SCRIPT" --print-service winter-agent >"$TMP/winter-service.sh"
bash "$SCRIPT" --print-service boot-services >"$TMP/boot-service.sh"
require_text "$TMP/keybot-service.sh" 'su -c'
require_text "$TMP/keybot-service.sh" 'BotService'
require_text "$TMP/winter-service.sh" 'Enter script key (32 hex chars):'
require_text "$TMP/winter-service.sh" 'script -q -E never -c'
require_text "$TMP/boot-service.sh" 'service-daemon start'
require_text "$TMP/boot-service.sh" 'sv up keybot-watchdog'
require_text "$TMP/boot-service.sh" 'sv up winter-agent'

# Integration mock environment.
rm -rf "$TMP"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/prefix/bin" "$TMP/mockbin" "$TMP/download"
CALLS="$TMP/calls.log"
export CALLS

for command in pkg termux-wake-lock service-daemon am pm su wm settings sv curl lua script; do
cat >"$TMP/mockbin/$command" <<'MOCK'
#!/usr/bin/env bash
name="$(basename "$0")"
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALLS"
if [[ "$name" == pkg && "${MOCK_DEP_FAIL:-0}" == 1 ]]; then echo 'mock dependency failure' >&2; exit 42; fi
case "$name" in
  pkg) printf '[mock pkg] %s\n' "$*"; ;;
  pm)
    if [[ "${1:-}" == path ]]; then
      if [[ "${MOCK_BOOT_FAIL:-0}" == 1 ]]; then echo 'mock boot missing' >&2; exit 1; fi
      printf 'package:/data/app/termux.boot.apk\n'
    fi
    ;;
  am) printf 'Starting: Intent { cmp com.termux.boot/.BootActivity }\n' ;;
  service-daemon)
    mkdir -p "$PREFIX/var/run"
    (sleep 60) & printf '%s\n' "$!" >"$PREFIX/var/run/service-daemon.pid"
    ;;
  su)
    if [[ "${1:-}" == -c ]]; then
      command_text="${2:-}"
      printf 'su -c %s\n' "$command_text" >>"$CALLS"
      if [[ "$command_text" == 'id -u' ]]; then printf '0\n';
      elif [[ "${MOCK_ROOT_FAIL:-0}" == 1 && "$command_text" == *'wm density 200'* ]]; then echo 'mock root failure' >&2; exit 1;
      elif [[ "$command_text" == 'wm density 200' ]]; then printf 'Override density: 200\n';
      elif [[ "$command_text" == settings\ put\ * ]]; then :;
      elif [[ "$command_text" == settings\ get\ * ]]; then printf '0\n';
      else bash -c "$command_text" || exit $?; fi
    fi
    ;;
  wm) [[ "${1:-}" == density && $# -eq 1 ]] && printf 'Override density: 200\n' ;;
  settings)
    [[ "${1:-}" == get ]] && printf '0\n'
    ;;
  sv)
    service="${2:-}"
    if [[ "${MOCK_SV_FAIL:-0}" == 1 ]]; then echo 'mock service failure' >&2; exit 1; fi
    if [[ "${1:-}" == up || "${1:-}" == status ]]; then
      mkdir -p "$SVDIR/$service/supervise" "$LOGDIR/sv/$service"
      printf 'raw service log %s\n' "$service" >"$LOGDIR/sv/$service/current"
      printf 'run: %s: (pid 123) 1s\n' "$service"
    fi
    ;;
  curl)
    out=''
    while (($#)); do [[ "$1" == -o ]] && { shift; out="$1"; }; shift || true; done
    printf '%s\n' '-- agent' >"${out:-$TMP/download/agent.lua}"
    ;;
  lua)
    # The real agent uses the PTY prompt. Mock output indicates daemon PID.
    printf '[SETUP] done\nEnter script key (32 hex chars):'
    IFS= read -r key </dev/tty || true
    printf 'Agent running in background (PID 123)\n'
    ;;
  script) exec bash -c "$*" ;;
esac
exit 0
MOCK
chmod +x "$TMP/mockbin/$command"
done

HOME="$TMP/home" PREFIX="$TMP/prefix" PATH="$TMP/mockbin:$PATH" \
WINTER_AGENT_KEY='test-secret' AGENT_PATH="$TMP/download/agent.lua" \
WINTER_AGENT_LOG_FILE="$TMP/home/winter_agent.log" \
SERVICE_START_ATTEMPTS=1 SERVICE_LOG_ATTEMPTS=1 \
bash "$SCRIPT" >"$TMP/install.out" 2>&1

require_text "$TMP/install.out" '[01]'
require_text "$TMP/install.out" '[02]'
key_pos="$(grep -nF '[01]' "$TMP/install.out" | head -1 | cut -d: -f1)"
dep_pos="$(grep -nF '[02]' "$TMP/install.out" | head -1 | cut -d: -f1)"
[[ "$key_pos" -lt "$dep_pos" ]] || fail 'key prompt must precede dependencies'
require_text "$TMP/install.out" '[03]'
require_text "$TMP/install.out" '[04]'
require_text "$TMP/install.out" '[05]'
require_text "$TMP/install.out" '[06]'
require_text "$TMP/install.out" '[07]'
require_text "$TMP/install.out" 'Keybot + Wintercode agent aktif'
require_text "$TMP/install.out" 'raw service log keybot-watchdog'
require_text "$TMP/install.out" 'raw service log winter-agent'
reject_text "$TMP/install.out" 'test-secret'
[[ -x "$TMP/prefix/var/service/keybot-watchdog/run" ]] || fail 'keybot run missing'
[[ -x "$TMP/prefix/var/service/winter-agent/run" ]] || fail 'winter run missing'
[[ -x "$TMP/home/.termux/boot/00-winter-supervisor.sh" ]] || fail 'boot script missing'
require_text "$CALLS" 'su -c wm density 200'
require_text "$SCRIPT" 'pkg upgrade -y'
update_line="$(grep -nF 'pkg update -y' "$SCRIPT" | head -1 | cut -d: -f1)"
upgrade_line="$(grep -nF 'pkg upgrade -y' "$SCRIPT" | head -1 | cut -d: -f1)"
[[ "$update_line" -lt "$upgrade_line" ]] || fail 'pkg upgrade must follow pkg update'
require_text "$CALLS" 'service-daemon start'
require_text "$CALLS" 'sv up keybot-watchdog'
require_text "$CALLS" 'sv up winter-agent'

run_failure_case() {
    local label="$1" expected="$2" forbidden="$3"
    shift 3
    set +e
    HOME="$TMP/home-$label" PREFIX="$TMP/prefix-$label" PATH="$TMP/mockbin:$PATH" \
    WINTER_AGENT_KEY='test-secret' AGENT_PATH="$TMP/download/$label-agent.lua" \
    SERVICE_START_ATTEMPTS=1 SERVICE_LOG_ATTEMPTS=1 "$@" bash "$SCRIPT" >"$TMP/$label.out" 2>&1
    local rc=$?
    set -e
    [[ "$rc" -ne 0 ]] || fail "$label should stop with nonzero"
    require_text "$TMP/$label.out" "$expected"
    reject_text "$TMP/$label.out" "$forbidden"
}
run_failure_case deps 'mock dependency failure' '[03]' env MOCK_DEP_FAIL=1
run_failure_case root 'mock root failure' '[04]' env MOCK_ROOT_FAIL=1
run_failure_case boot 'mock boot missing' '[06]' env MOCK_BOOT_FAIL=1
run_failure_case service 'mock service failure' '[07]' env MOCK_SV_FAIL=1

printf 'Combined supervisor checks passed\n'
