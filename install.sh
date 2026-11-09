#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_NAME="dms-chrome-theme"
DMS_PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dms/plugins"
TARGET_LINK="$DMS_PLUGINS_DIR/$PLUGIN_NAME"

echo "==> Building Go helper binary (bin/chrome-theme-sync)..."
cd "$HERE"
mkdir -p bin
go build -ldflags="-s -w" -o bin/chrome-theme-sync ./cmd/chrome-theme-sync

echo "==> Ensuring Chrome managed policy directory exists and is writable..."
POLICY_DIR="/etc/opt/chrome/policies/managed"
if [[ ! -d "$POLICY_DIR" || ! -w "$POLICY_DIR" ]]; then
  echo "Setting permissions on $POLICY_DIR (requires sudo once)..."
  sudo install -d -o root -g "$USER" -m 0775 "$POLICY_DIR"
fi

# Ensure Chromium directory is also prepared if Chromium is installed
CHROMIUM_DIR="/etc/chromium/policies/managed"
if command -v chromium >/dev/null 2>&1 && [[ ! -d "$CHROMIUM_DIR" || ! -w "$CHROMIUM_DIR" ]]; then
  echo "Setting permissions on $CHROMIUM_DIR..."
  sudo install -d -o root -g "$USER" -m 0775 "$CHROMIUM_DIR" || true
fi

echo "==> Installing plugin into DMS..."
mkdir -p "$DMS_PLUGINS_DIR"

HERE_REAL=$(readlink -f "$HERE")
PLUGINS_REAL=$(readlink -f "$DMS_PLUGINS_DIR" 2>/dev/null || echo "$DMS_PLUGINS_DIR")

case "$HERE_REAL" in
  "$PLUGINS_REAL"/*)
    echo "Plugin already resides inside $DMS_PLUGINS_DIR."
    ;;
  *)
    echo "Linking $HERE -> $TARGET_LINK"
    ln -sfn "$HERE" "$TARGET_LINK"
    ;;
esac

echo "==> Cleaning up legacy systemd path units (if present)..."
if systemctl --user is-active dux-chrome-theme.path >/dev/null 2>&1; then
  echo "Disabling dux-chrome-theme.path..."
  systemctl --user disable --now dux-chrome-theme.path || true
fi
if systemctl --user is-active dux-chrome-theme.service >/dev/null 2>&1; then
  systemctl --user stop dux-chrome-theme.service || true
fi

cat <<EOF

✓ Installation successful!
  - Plugin registered at: $TARGET_LINK
  - Helper binary ready: $HERE/bin/chrome-theme-sync

Next steps:
  1. Open DMS Settings -> Plugins
  2. Click 'Scan for Plugins' (or restart DMS with 'dms restart')
  3. Enable 'Dynamic Chrome Theming'

The plugin will automatically sync Chrome's theme color in real time (<100ms)
whenever your desktop wallpaper, palette, or light/dark mode changes.
EOF
