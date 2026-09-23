import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as M

// Nightscout CGM plugin popup. Native Omarchy chrome (KeyboardPanel +
// Style/Color + PanelKeyCatcher), following the same shape as the shipped
// weather panel and the community displays-arranger plugin: a small Panel
// that polls a bundled CLI on a timer and renders its JSON.
Panel {
    id: root
    moduleName: "loudestnoise.nightscout-cgm"
    ipcTarget: "loudestnoise.nightscout-cgm"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    readonly property var barIdentity: hostWidget || root

    property var settings: ({})

    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property color fg: Color.popups.text
    readonly property color muted: Util.alpha(fg, 0.55)

    // The CLI is bundled in the plugin (installed by `omarchy plugin add`),
    // so the plugin never depends on anything being on PATH. It must be
    // built once after install: see the plugin README.
    readonly property string cli: Quickshell.env("HOME")
        + "/.config/omarchy/plugins/loudestnoise.nightscout-cgm/bin/cgm"

    function setting(name, fallback) {
        var v = settings ? settings[name] : undefined;
        return (v === undefined || v === null || v === "") ? fallback : v;
    }
    readonly property string nightscoutUrl: setting("nightscoutUrl", "")
    readonly property real lowMmol: Number(setting("lowMmol", 4.0))
    readonly property real highMmol: Number(setting("highMmol", 8.0))
    readonly property real urgentHighMmol: Number(setting("urgentHighMmol", 15.0))
    readonly property bool showMgdl: setting("showMgdl", false) === true
    readonly property int refreshIntervalSec: {
        var n = parseInt(String(setting("refreshIntervalSec", 60)), 10);
        if (!isFinite(n)) n = 60;
        return Math.max(15, Math.min(600, n));
    }

    property var data: null

    readonly property string pillText: M.pillText(root.data, root.showMgdl)
    readonly property string pillTooltip: M.pillTooltip(root.data, root.showMgdl)

    // Every "current reading" binding below must gate on these instead of
    // plain `root.data` truthiness: QML evaluates a bound expression eagerly
    // even while its sibling `visible:` is false, and {error: "..."} (or a
    // reading with no previous/prediction fields yet) is truthy but missing
    // the numeric fields those expressions assume.
    readonly property bool hasReading: M.hasReading(root.data)
    readonly property bool hasPrevious: root.hasReading && typeof root.data.previousMmol === "number"
    readonly property bool hasPredictedLow: root.hasReading && !!root.data.predictedLowAtMs
    readonly property bool hasInRange: root.hasReading && !!root.data.inRangeAtMs

    function open() { controller.show(); refresh(); }
    function close() { controller.hide(); }
    function toggle() { opened ? close() : open(); }
    function switchPanel(direction) {
        if (bar && typeof bar.switchPanelFrom === "function")
            return bar.switchPanelFrom(barIdentity, direction);
        return false;
    }

    function refresh() {
        if (!root.nightscoutUrl) {
            root.data = { error: "Set a Nightscout URL in the plugin settings" };
            return;
        }
        if (fetchProc.running) return;
        fetchProc.command = M.cliArgs(root.cli, root.settings);
        fetchProc.running = true;
    }

    function ingest(text) {
        try {
            root.data = JSON.parse(text);
        } catch (e) {
            root.data = { error: "Failed to parse cgm output: " + e };
        }
    }

    function openInBrowser() {
        if (!root.nightscoutUrl) return;
        openProc.command = ["xdg-open", root.nightscoutUrl];
        openProc.running = true;
    }

    Timer {
        interval: root.refreshIntervalSec * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: fetchProc
        command: []
        stdout: StdioCollector { id: fetchStdout; waitForEnd: true; onStreamFinished: root.ingest(text) }
        stderr: StdioCollector { id: fetchStderr; waitForEnd: true }
        onExited: function (exitCode, exitStatus) {
            if (exitCode !== 0 && (!fetchStdout.text || fetchStdout.text === "")) {
                root.data = { error: fetchStderr.text || ("cgm exited with code " + exitCode) };
            }
        }
    }

    Process { id: openProc; command: [] }

    IpcHandler {
        target: root.ipcTarget
        function open(): void { root.open() }
        function close(): void { root.close() }
        function show(): void { root.open() }
        function hide(): void { root.close() }
        function toggle(): void { root.toggle() }
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        bar: root.bar
        owner: root.barIdentity
        open: root.opened
        focusTarget: keys
        contentWidth: panel.fittedContentWidth(Style.space(320))
        contentHeight: panel.fittedContentHeight(body.implicitHeight)

        PanelKeyCatcher {
            id: keys
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function (direction) { root.switchPanel(direction); }

            Column {
                id: body
                width: parent.width
                spacing: Style.space(10)

                // ---- header ----
                Item {
                    width: parent.width
                    implicitHeight: Math.max(hdr.implicitHeight, refreshBtn.implicitHeight)
                    Row {
                        id: hdr
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(6)
                        Text {
                            text: "Nightscout CGM"
                            color: root.fg
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.subtitle
                            font.bold: true
                        }
                    }
                    Button {
                        id: refreshBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Refresh"
                        bordered: true
                        fontFamily: root.fontFamily
                        fontSize: Style.font.caption
                        horizontalPadding: Style.space(8)
                        verticalPadding: Style.space(3)
                        onClicked: root.refresh()
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Math.max(1, Style.spacing.hairline)
                    color: Util.alpha(root.fg, 0.14)
                }

                // ---- error state ----
                Text {
                    visible: !!root.data && !!root.data.error
                    width: parent.width
                    text: (root.data && root.data.error) ? root.data.error : ""
                    color: Color.urgent
                    wrapMode: Text.WordWrap
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                }

                // ---- current reading ----
                Column {
                    visible: root.hasReading
                    width: parent.width
                    spacing: Style.space(4)

                    Text {
                        text: root.hasReading
                            ? M.primaryValue(root.data, root.showMgdl) + " " + M.primaryUnit(root.showMgdl) +
                              " (" + M.secondaryValueText(root.data, root.showMgdl) + ") " + root.data.directionArrow
                            : ""
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                        font.bold: true
                    }
                    Text {
                        text: root.hasReading ? "Updated " + M.minutesAgoText(root.data.timestampMs) : ""
                        color: root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }
                    Text {
                        visible: root.hasPrevious
                        text: root.hasPrevious ? "Previous: " + M.previousValueText(root.data, root.showMgdl) : ""
                        color: root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }
                    Text {
                        visible: root.hasPredictedLow
                        text: root.hasPredictedLow
                            ? "Predicted low at " + M.formatClock(root.data.predictedLowAtMs) : ""
                        color: Color.urgent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }
                    Text {
                        visible: root.hasInRange
                        text: root.hasInRange
                            ? "Back in range at " + M.formatClock(root.data.inRangeAtMs) : ""
                        color: root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }

                    Repeater {
                        model: root.hasReading && root.data.alerts ? root.data.alerts : []
                        delegate: Text {
                            width: body.width
                            text: "⚠ " + modelData
                            color: Color.urgent
                            wrapMode: Text.WordWrap
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Math.max(1, Style.spacing.hairline)
                    color: Util.alpha(root.fg, 0.14)
                }

                // ---- footer ----
                Row {
                    spacing: Style.space(6)
                    Button {
                        text: "Open in browser"
                        bordered: true
                        enabled: root.nightscoutUrl !== ""
                        fontFamily: root.fontFamily
                        fontSize: Style.font.caption
                        horizontalPadding: Style.space(10)
                        verticalPadding: Style.space(4)
                        onClicked: root.openInBrowser()
                    }
                }
            }
        }
    }
}
