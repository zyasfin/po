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
