import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "dmsChromeTheme"

    function daemon() {
        return pluginService && pluginService.pluginDaemonInstances
            ? (pluginService.pluginDaemonInstances["dmsChromeTheme"] || null)
            : null;
    }

    StyledText {
        text: "Dynamic Chrome Theming"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent ? parent.width : 360
        wrapMode: Text.Wrap
        text: "Dynamically synchronizes Chrome and Chromium browser theme colors with the Dux Shell Material 3 palette in real time with sub-100ms latency."
        color: Theme.surfaceTextSecondary
        font.pixelSize: Theme.fontSizeSmall
    }

    // ------------------------------------------------------------ Status Card
    Rectangle {
        width: parent ? parent.width : 360
        height: statusCol.implicitHeight + 24
        radius: Theme.borderRadiusMedium
        color: Theme.withAlpha(Theme.surfaceVariant, 0.4)
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.5)
        border.width: 1

        Column {
            id: statusCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 8

            Row {
                spacing: 8
                Rectangle {
                    width: 16
                    height: 16
                    radius: 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: {
                        const d = root.daemon();
                        return (d && d.lastAppliedColor) ? d.lastAppliedColor : Theme.surfaceContainer;
                    }
                    border.color: Theme.withAlpha(Theme.surfaceText, 0.4)
                    border.width: 1
                }

                StyledText {
                    text: {
                        const d = root.daemon();
                        if (!d) return "Daemon status: Not running";
                        return "Status: " + d.statusMessage;
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                }
            }

            StyledText {
                text: {
                    const d = root.daemon();
                    if (!d) return "";
                    const color = d.lastAppliedColor || "—";
                    const ms = d.lastElapsedMs || 0;
                    const browsers = d.lastBrowsers || "none";
                    return "Active Color: " + color + " · Latency: " + ms + " ms · Target: " + browsers;
                }
                color: Theme.surfaceTextSecondary
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    // ------------------------------------------------------------ Actions
    Row {
        spacing: Theme.spacingM

        DButton {
            text: "Sync Now"
            iconName: "refresh"
            onClicked: {
                const d = root.daemon();
                if (d) {
                    d.syncNow();
                }
            }
        }
    }

    // ------------------------------------------------------------ Settings
    ToggleSetting {
        settingKey: "enabled"
        label: "Enable Chrome theme sync"
        description: "Master switch. Automatically updates Chrome whenever desktop colors change."
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "colorSource"
        label: "Color Palette Source"
        description: "Select which Material 3 surface color is passed to Chrome's BrowserThemeColor."
        defaultValue: "surfaceContainer"
        options: [
            { label: "Surface Container (Default - Matches UI)", value: "surfaceContainer" },
            { label: "Surface (Neutral Background)", value: "surface" },
            { label: "Primary Accent (Vibrant Wallpaper Accent)", value: "primary" },
            { label: "Surface Dim (Darker Contrast)", value: "surfaceDim" }
        ]
    }

    onSettingChanged: {
        const d = root.daemon();
        if (d) {
            d.reloadSettings();
        }
    }
}
