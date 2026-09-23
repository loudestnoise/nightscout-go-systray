import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Bar pill for the Nightscout CGM plugin. Mirrors the standard Omarchy
// bar-widget boilerplate (icon/text button that toggles a popup loaded from
// Panel.qml) used by first-party plugins such as omarchy.weather.
BarWidget {
    id: root
    moduleName: "loudestnoise.nightscout-cgm"

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool popoutSwitchClosing: panelLoader.item
        ? panelLoader.item.popoutSwitchClosing === true : false

    function injectPanel() {
        var p = panelLoader.item;
        if (!p) return;
        if ("bar" in p) p.bar = root.bar;
        if ("settings" in p) p.settings = root.settings;
        if ("anchorItem" in p) p.anchorItem = button;
        if ("hostWidget" in p) p.hostWidget = root;
    }
    function open() { if (panelLoader.item) panelLoader.item.open() }
    function close() { if (panelLoader.item) panelLoader.item.close() }
    function togglePanel() { if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle() }
    function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel); }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: panelLoader.item ? panelLoader.item.pillText : "..."
        slotSize: Style.bar.statusSlot
        tooltipText: panelLoader.item ? panelLoader.item.pillTooltip : "Nightscout CGM"
        onPressed: function (b) {
            if (b === Qt.LeftButton) root.togglePanel();
            else if (b === Qt.MiddleButton && panelLoader.item) panelLoader.item.refresh();
        }
    }
}
