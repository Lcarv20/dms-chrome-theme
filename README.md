# Dynamic Chrome Theming (`dms-chrome-theme`)

A native daemon plugin for [Dux Modular Shell](https://github.com/duxlabs-dev/dux-shell) (DMS) that dynamically synchronizes Google Chrome and Chromium browser theme colors with your desktop's Material 3 palette in real time (<100ms latency).

Whenever your desktop wallpaper, accent color, or light/dark mode changes in Dux Shell, the browser window frame, tab strip, and accent color update instantly without requiring a browser restart or waiting for multi-second polling intervals.

## How It Works

1. **Native DMS Event Hook:** The plugin daemon runs in-process inside Dux Shell (Quickshell) and listens directly to `Theme.surfaceContainerChanged`, `Theme.primaryChanged`, and `SessionData.isLightModeChanged`.
2. **Managed Policy Sync:** A compiled, self-contained Go helper (`bin/chrome-theme-sync`) writes the active palette color into Chromium's managed enterprise policy:
   `/etc/opt/chrome/policies/managed/color.json` (as well as `/etc/chromium/policies/managed/` and `/etc/brave/policies/managed/` if present).
3. **Synchronous Policy Refresh:** If a Chromium browser instance is running, the helper executes `--refresh-platform-policy` synchronously, triggering an immediate policy reload across all browser windows.

## Features

- **Sub-100ms Latency:** Changes take effect instantly rather than falling back to Chromium's 3–5 second filesystem poll timer.
- **Zero Overhead:** Features an in-memory fast-path check: if the policy color already matches the target color, no file writes or IPC reloads occur.
- **Configurable Color Source:** Select between `Surface Container` (default, matches shell panels and titlebars), `Surface`, `Primary Accent`, or `Surface Dim` directly from DMS Settings → Plugins.
- **Light & Dark Mode Support:** Respects Dux Shell's dark/light mode toggles on the fly.
- **Multi-Browser Support:** Works with Google Chrome, Chromium, and Brave.

## Prerequisites

- **Dux Modular Shell** (`dms` >= 2.0.0)
- **Go** (for compiling the helper binary)
- Write permissions for the user to `/etc/opt/chrome/policies/managed` (handled automatically by `install.sh`)

## Installation

Clone the repository and run the installer:

```bash
git clone https://github.com/Lcarv20/dms-chrome-theme.git ~/.config/dms/plugins/dms-chrome-theme
cd ~/.config/dms/plugins/dms-chrome-theme
make install
```

Or from an existing checkout:

```bash
./install.sh
```

Then:
1. Open **DMS Settings** (`Mod+Ctrl+T` or via top bar) → **Plugins**.
2. Click **Scan for Plugins** (or run `dms restart`).
3. Enable **Dynamic Chrome Theming**.

## CLI Usage (Standalone)

The included Go helper can also be used standalone in scripts:

```bash
# Sync specific color to Chrome:
./bin/chrome-theme-sync --color "#191920"

# Check current policy color:
./bin/chrome-theme-sync --status

# Force refresh:
./bin/chrome-theme-sync --color "#191920" --force
```

## License

[MIT](LICENSE) © Luís Carvalho
