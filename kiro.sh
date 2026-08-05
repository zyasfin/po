#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

BASE_URL="${KIRO_BASE_URL:-https://raw.githubusercontent.com/zyasfin/po/refs/heads/main}"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PREFIX
export SVDIR="${SVDIR:-$PREFIX/var/service}"
export LOGDIR="${LOGDIR:-$PREFIX/var/log}"
INSTALL_DIR="$HOME/.local/lib/winter-supervisor"
CONFIG_DIR="$HOME/.config/winter-supervisor"
KEY_FILE="$CONFIG_DIR/agent.key"
BOOT_DIR="$HOME/.termux/boot"
BOOT_SCRIPT="$BOOT_DIR/00-winter-supervisor.sh"

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }

fetch() {
    curl -fsSL "$BASE_URL/$1" -o "$2"
}

read_agent_key() {
    local key="${WINTER_AGENT_KEY:-}"
    if [[ -z "$key" && -r /dev/tty ]]; then
        IFS= read -r -p 'Masukkan key Wintercode agent (boleh kosong): ' key </dev/tty || true
    elif [[ -z "$key" && -t 0 ]]; then
        IFS= read -r -p 'Masukkan key Wintercode agent (boleh kosong): ' key || true
    fi
    printf '%s' "$key"
}

install_service() {
    local name="$1" command_path="$2" service_dir
    service_dir="$SVDIR/$name"
    mkdir -p "$service_dir/log" "$LOGDIR/sv/$name"
    cat >"$service_dir/run" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
exec "$command_path"
EOF
    cat >"$service_dir/log/run" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
exec svlogd -tt "$LOGDIR/sv/$name"
EOF
    cat >"$service_dir/finish" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
sleep 10
EOF
    chmod 700 "$service_dir/run" "$service_dir/finish" "$service_dir/log/run"
    rm -f "$service_dir/down"
}

stop_legacy_watchdog() {
    local lock="$PREFIX/tmp/watchdog_keybot.lock" pid="" command_line=""
    if [[ -s "$lock" ]]; then
        IFS= read -r pid <"$lock" || true
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            command_line="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
            if [[ "$command_line" == *watchdog_keybot* || "$command_line" == *kiro.sh* ]]; then
                kill "$pid" 2>/dev/null || true
            fi
        fi
        rm -f "$lock"
    fi
    if command -v screen >/dev/null 2>&1; then
        screen -S watchdog_keybot -X quit >/dev/null 2>&1 || true
    fi
    rm -f "$BOOT_DIR/watchdog_keybot.sh" "$BOOT_DIR/watchdog_keybot_fixed.sh"
}

info 'Installing dependencies...'
pkg install -y termux-services curl lua54 sqlite termux-api >/dev/null

info 'Applying existing root tweaks...'
if command -v su >/dev/null 2>&1; then
    su -c '
        wm density 200 &&
        settings put global window_animation_scale 0 &&
        settings put global transition_animation_scale 0 &&
        settings put global animator_duration_scale 0 &&
        settings put global force_resizable_activities 1 &&
        settings put global enable_freeform_support 1
    ' >/dev/null 2>&1 || warn 'Root tweaks skipped'
else
    warn 'su tidak tersedia; root tweaks dan Keybot start perlu root'
fi

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$BOOT_DIR" "$SVDIR" "$LOGDIR/sv"
for script in keybot-watchdog.sh winter-agent-runner.sh boot-services.sh; do
    fetch "$script" "$INSTALL_DIR/$script"
    chmod 700 "$INSTALL_DIR/$script"
done

agent_key="$(read_agent_key)"
umask 077
printf '%s\n' "$agent_key" >"$KEY_FILE"
chmod 600 "$KEY_FILE"
if [[ -z "$agent_key" ]]; then
    warn 'Key kosong; Wintercode agent tetap dijalankan tanpa input key'
else
    ok 'Key disimpan privat untuk auto-restart agent'
fi
agent_key=""

stop_legacy_watchdog
install_service keybot-watchdog "$INSTALL_DIR/keybot-watchdog.sh"
install_service winter-agent "$INSTALL_DIR/winter-agent-runner.sh"
cp "$INSTALL_DIR/boot-services.sh" "$BOOT_SCRIPT"
chmod 700 "$BOOT_SCRIPT"

if command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock >/dev/null 2>&1 || true
fi
if ! service-daemon start >/dev/null 2>&1; then
    if [[ ! -s "$PREFIX/var/run/service-daemon.pid" ]] || ! kill -0 "$(cat "$PREFIX/var/run/service-daemon.pid")" 2>/dev/null; then
        warn 'runit service-daemon gagal start'
        exit 1
    fi
fi
sv up keybot-watchdog >/dev/null
sv up winter-agent >/dev/null

if command -v pm >/dev/null 2>&1 && ! pm path com.termux.boot >/dev/null 2>&1; then
    warn 'Termux:Boot belum terpasang. Install dari F-Droid lalu buka sekali.'
elif command -v am >/dev/null 2>&1; then
    am start -n com.termux.boot/.BootActivity >/dev/null 2>&1 || true
fi

ok 'Keybot + Wintercode agent aktif di runit'
ok "Termux:Boot installed: $BOOT_SCRIPT"
printf 'Status: sv status keybot-watchdog winter-agent\n'
printf 'Logs  : tail -f %s/var/log/sv/{keybot-watchdog,winter-agent}/current\n' "$PREFIX"
