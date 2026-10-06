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
    property bool lidClosed: false
    property bool showInBar: pluginData.showInBar ?? true
    // replicates BasePill.horizontalPadding so clicks cover the whole pill, not just the icon
    readonly property real pillPadding: (root.barConfig?.removeWidgetPadding ?? false) ? 0 : (root.barConfig?.widgetPadding ?? 12) * (root.widgetThickness / 30)

    ccWidgetIcon: unitActive ? "bedtime_off" : "bedtime"
    ccWidgetPrimaryText: "Lid Guard"
    ccWidgetSecondaryText: unitActive ? "close = screen off" : "close = suspend"
    ccWidgetIsActive: unitActive

    function toggleLidguard() {
        const cmd = unitActive
            ? ["systemctl", "--user", "stop", "lidguard.service"]
            : ["systemd-run", "--user", "--unit=lidguard", "systemd-inhibit", "--what=handle-lid-switch", "sleep", "infinity"]
        Quickshell.execDetached(cmd)
    }

    onCcWidgetToggled: root.toggleLidguard()

    horizontalBarPill: Component {
        Item {
        visible: root.showInBar
        implicitWidth: icon.width
        implicitHeight: icon.height

            DankIcon {
                id: icon
                name: unitActive ? "bedtime_off" : "bedtime"
                size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: unitActive ? Theme.primary : Theme.surfaceText
                opacity: unitActive ? 1.0 : 0.4
                anchors.centerIn: parent
            }

            MouseArea {
                width: parent.width + root.pillPadding * 2
                height: root.barThickness
                x: -root.pillPadding
                y: -(height - parent.height) / 2
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleLidguard()
            }
        }
    }

    verticalBarPill: Component {
        Item {
        visible: root.showInBar
        implicitWidth: icon.width
        implicitHeight: icon.height

            DankIcon {
                id: icon
                name: unitActive ? "bedtime_off" : "bedtime"
                size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: unitActive ? Theme.primary : Theme.surfaceText
                opacity: unitActive ? 1.0 : 0.4
                anchors.centerIn: parent
            }

            MouseArea {
                width: parent.width + root.pillPadding * 2
                height: root.barThickness
                x: -root.pillPadding
                y: -(height - parent.height) / 2
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleLidguard()
            }
        }
    }

    function applyState() {
        if (!unitActive || !lidClosed) {
            CompositorService.powerOnMonitors()
        } else {
            CompositorService.powerOffMonitors()
        }
    }

    function setUnitActive(active) {
        if (unitActive === active)
            return
        unitActive = active
        applyState()
    }

    function setLidClosed(closed) {
        if (lidClosed === closed)
            return
        lidClosed = closed
        applyState()
    }

    Component.onCompleted: {
        initialUnitState.running = true
        initialLidState.running = true
    } 

    // one time process, unit state initialization
    Process {
        id: initialUnitState
        command: ["systemctl", "--user", "is-active", "lidguard.service"]
        stdout: SplitParser {
            onRead: line => root.setUnitActive(line.trim() === "active")
        }
    }

    // one time process, lid state initialization
    Process {
        id: initialLidState
        command: [
            "dbus-send", 
            "--system", 
            "--print-reply=literal",
            "--dest=org.freedesktop.login1", 
            "/org/freedesktop/login1",
            "org.freedesktop.DBus.Properties.Get",
            "string:org.freedesktop.login1.Manager", 
            "string:LidClosed"
        ]
        stdout: SplitParser {
            onRead: line => root.setLidClosed(line.indexOf("true") !== -1)
        }
    }

    // systemd --user: unit state changes (session bus)
    Process {
        id: unitMonitor
        property string pending: ""
        command: [
            "dbus-monitor", "--session",
            "type='signal'," + 
            "interface='org.freedesktop.DBus.Properties'," + 
            "path='/org/freedesktop/systemd1/unit/lidguard_2eservice'"
        ]
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf('string "ActiveState"') !== -1) {
                    unitMonitor.pending = "ActiveState"
                    return
                }
                if (unitMonitor.pending === "ActiveState") {
                    unitMonitor.pending = ""
                    const m = line.match(/string "(.*)"/)
                    if (m) {
                        console.info("[lidguard] unit signal:", m[1])
                        root.setUnitActive(m[1] === "active")
                    }
                }
            }
        }
        Component.onCompleted: running = true
        onExited: running = true // auto restart
    }

    // systemd-logind: kernel lid events (system bus)
    Process {
        id: lidMonitor
        property string pending: ""
        command: [
            "dbus-monitor", "--system",
            "type='signal',sender='org.freedesktop.login1'," + 
            "interface='org.freedesktop.DBus.Properties'," +
            "path='/org/freedesktop/login1'"
        ]
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf('string "LidClosed"') !== -1) {
                    lidMonitor.pending = "LidClosed"
                    return
                }
                if (lidMonitor.pending === "LidClosed") {
                    lidMonitor.pending = ""
                    const m = line.match(/boolean (\w+)/)
                    if (m) {
                        console.info("[lidguard] lid signal:", line.trim())
                        root.setLidClosed(m[1] === "true")
                    }
                }
            }
        }
        Component.onCompleted: running = true
        onExited: running = true // auto restart
    }
}
