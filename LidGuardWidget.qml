// Lid Guard: lid close = screen off instead of suspend.
// Source of truth: lidguard systemd unit (systemctl is-active), not local state.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property bool unitActive: false
    property bool screensOff: false
    property string prevLid: "" // "" until first poll

    ccWidgetIcon: unitActive ? "nightlight" : "nightlight_off"
    ccWidgetPrimaryText: "Lid Guard"
    ccWidgetSecondaryText: unitActive ? "Close = screen off" : "Close = suspend"
    ccWidgetIsActive: unitActive

    onCcWidgetToggled: {
        // ponytail: single command per toggle; truth comes from the unit, not from here
        const cmd = unitActive
            ? ["systemctl", "--user", "stop", "lidguard.service"]
            : ["systemd-run", "--user", "--unit=lidguard", "systemd-inhibit",
               "--what=handle-lid-switch", "sleep", "infinity"]
        Quickshell.execDetached(cmd)
        ToastService.showInfo(unitActive ? "Lid Guard off" : "Lid Guard on")
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            DankIcon {
                name: root.unitActive ? "nightlight" : "nightlight_off"
                size: Theme.iconSize
                color: root.unitActive ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.unitActive ? "screen off" : "suspend"
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: root.unitActive ? "nightlight" : "nightlight_off"
            size: Theme.iconSize
            color: root.unitActive ? Theme.primary : Theme.surfaceVariantText
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    function setScreens(off) {
        screensOff = off
        // dms dpms hangs forever if already in target state -> hard kill at 15s
        Quickshell.execDetached(["timeout", "-s", "KILL", "15", "dms", "dpms", off ? "off" : "on"])
    }

    function handleState(line) {
        const parts = (line || "").split("|")
        const closed = (parts[0] || "unknown") === "closed"
        const active = (parts[1] || "inactive") === "active"
        unitActive = active
        if (!active) {
            if (screensOff)
                setScreens(false) // guard killed while lid closed: wake screens back up
        } else if (closed && !screensOff) {
            setScreens(true)
        } else if (!closed && screensOff) {
            setScreens(false)
        }
        prevLid = closed ? "closed" : "open"
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: poll.running = true
    }

    Process {
        id: poll
        command: ["sh", "-c",
            "lid=$(awk '{print $2}' /proc/acpi/button/lid/*/state 2>/dev/null | head -1); " +
            "echo \"${lid:-unknown}|$(systemctl --user is-active lidguard.service)\""]
        stdout: SplitParser {
            onRead: line => root.handleState(line)
        }
    }
}
