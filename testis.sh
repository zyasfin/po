#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

BASE_URL="${KIRO_BASE_URL:-https://raw.githubusercontent.com/zyasfin/po/refs/heads/main}"
exec bash <(curl -fsSL "$BASE_URL/kiro.sh") "$@"

# Legacy functions stay in the installer:
# root tweaks, package setup, Termux:Boot, ZIP/config workflow, WinterHub agent,
# Roblox link resolution, and winter-rejoin execution remain available in the
# original setup flow when explicitly needed.

# ponytail: this wrapper intentionally delegates to kiro.sh; add separate setup
# flags only when the existing agent flow requires a non-interactive mode.
