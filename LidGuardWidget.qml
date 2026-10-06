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

    pillClickAction: () => root.toggleLidguard()

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

    function monitorExited(proc, timer) {
        if (Date.now() - proc.startedAt < 30000)
            proc.restarts++
        else
            proc.restarts = 0
        if (proc.restarts < 5)
            timer.restart()
        else
            console.warn("[lidguard]", proc.command[0], "gave up after 5 failed restarts")
    }

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
        property int restarts: 0
        property real startedAt: 0
        Component.onCompleted: {
            startedAt = Date.now()
            running = true
        }
        onExited: root.monitorExited(unitMonitor, unitRestart)
    }

    Timer {
        id: unitRestart
        interval: 3000
        onTriggered: {
            unitMonitor.startedAt = Date.now()
            unitMonitor.running = true
        }
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
        property int restarts: 0
        property real startedAt: 0
        Component.onCompleted: {
            startedAt = Date.now()
            running = true
        }
        onExited: root.monitorExited(lidMonitor, lidRestart)
    }

    Timer {
        id: lidRestart
        interval: 3000
        onTriggered: {
            lidMonitor.startedAt = Date.now()
            lidMonitor.running = true
        }
    }
}
