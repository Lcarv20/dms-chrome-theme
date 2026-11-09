import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

QtObject {
    id: root

    // Injected by DMS PluginService
    property string pluginId: ""
    property var pluginService: null

    readonly property var log: Log.scoped("ChromeTheme")

    // Resolved path to the Go helper binary
    readonly property string helperBin: {
        const u = Qt.resolvedUrl("bin/chrome-theme-sync").toString();
        return u.startsWith("file://") ? u.substring(7) : u;
    }

    // ------------------------------------------------------------- Settings
    property bool enabled: true
    property string colorSource: "surfaceContainer"

    function reloadSettings() {
        if (!pluginService || !pluginId) return;
        const prevEnabled = enabled;
        const prevSource = colorSource;
        enabled = pluginService.loadPluginData(pluginId, "enabled", true);
        colorSource = pluginService.loadPluginData(pluginId, "colorSource", "surfaceContainer");

        if (prevEnabled !== enabled) {
            if (!enabled) {
                applyTimer.stop();
                statusMessage = "disabled in plugin settings";
            } else {
                scheduleApply();
            }
        } else if (prevSource !== colorSource && enabled) {
            scheduleApply();
        }
    }

    onPluginServiceChanged: reloadSettings()
    onPluginIdChanged: reloadSettings()

    property Connections pluginConnections: Connections {
        target: root.pluginService
        function onPluginDataChanged(changedId) {
            if (changedId === root.pluginId) {
                root.reloadSettings();
            }
        }
    }

    // ---------------------------------------------------------------- State
    property string statusMessage: "initializing"
    property string lastAppliedColor: ""
    property string lastStatus: ""
    property string lastBrowsers: ""
    property int lastElapsedMs: 0

    function colorToHex(c) {
        if (!c) return "#191920";
        const r = Math.round(c.r * 255).toString(16).padStart(2, "0");
        const g = Math.round(c.g * 255).toString(16).padStart(2, "0");
        const b = Math.round(c.b * 255).toString(16).padStart(2, "0");
        return "#" + r + g + b;
    }

    readonly property string currentTargetColor: {
        switch (colorSource) {
            case "primary": return colorToHex(Theme.primary);
            case "surface": return colorToHex(Theme.surface);
            case "surfaceDim": return colorToHex(Theme.surfaceDim);
            case "surfaceContainer":
            default:
                return colorToHex(Theme.surfaceContainer);
        }
    }

    // Debounce timer for rapid wallpaper / theme slider changes
    property Timer applyTimer: Timer {
        interval: 100
        onTriggered: root.executeSync(false)
    }

    function scheduleApply() {
        if (!enabled) return;
        applyTimer.restart();
    }

    // Process executor
    property Process syncProc: Process {
        id: proc
        stdout: SplitParser {
            onRead: data => {
                if (!data) return;
                try {
                    const res = JSON.parse(data.trim());
                    root.lastElapsedMs = res.elapsed_ms || 0;
                    root.lastAppliedColor = res.color || root.currentTargetColor;
                    root.lastStatus = res.status || "ok";
                    root.lastBrowsers = (res.browsers && res.browsers.length) ? res.browsers.join(", ") : "none";

                    if (res.status === "applied") {
                        root.statusMessage = "Applied in " + res.elapsed_ms + " ms (" + root.lastBrowsers + ")";
                        root.log.info("Chrome theme applied: " + res.color + " in " + res.elapsed_ms + " ms");
                    } else if (res.status === "noop") {
                        root.statusMessage = "Up to date (" + res.color + ")";
                    } else if (res.status === "error") {
                        root.statusMessage = "Error: " + (res.error || "unknown");
                        root.log.error("Chrome theme sync error: " + res.error);
                    }
                } catch (e) {
                    root.log.warning("Parsing sync output: " + data);
                }
            }
        }
        stderr: SplitParser {
            onRead: err => {
                if (err && err.trim().length > 0) {
                    root.log.error("Sync process stderr: " + err.trim());
                }
            }
        }
    }

    function executeSync(force) {
        if (proc.running) {
            applyTimer.restart();
            return;
        }

        const color = currentTargetColor;
        const args = [helperBin, "--color", color];
        if (force) {
            args.push("--force");
        }
        proc.command = args;
        proc.running = true;
    }

    function syncNow() {
        executeSync(true);
    }

    Component.onCompleted: {
        log.info("Chrome Theme daemon loaded. Helper: " + helperBin);
        reloadSettings();
        Theme.surfaceContainerChanged.connect(scheduleApply);
        Theme.surfaceChanged.connect(scheduleApply);
        Theme.primaryChanged.connect(scheduleApply);
        Theme.surfaceDimChanged.connect(scheduleApply);
        SessionData.isLightModeChanged.connect(scheduleApply);
        Qt.callLater(scheduleApply);
    }

    Component.onDestruction: {
        applyTimer.stop();
    }
}
