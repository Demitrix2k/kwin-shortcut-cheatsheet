// Keys Guide: a shortcut (Meta+/ by default) shows every global shortcut that
// has a key, as KDE has it right now: kglobalaccel is asked over D-Bus each
// time, so a key changed in System Settings shows up straight away.
// Escape, a click (on it or on any other window) or the shortcut again
// closes it.
import QtQuick
import QtQuick.Window as QW
import org.kde.kwin
import org.kde.kirigami as Kirigami
import "KeyNames.js" as KeyNames
import "Grouping.js" as Grouping

Item {
    id: root

    readonly property string actionName: "KeysGuideShow"

    ShortcutHandler {
        name: root.actionName
        text: "Keys Guide: Show or hide the shortcut overview"
        sequence: "Meta+/"
        onActivated: guide.visible ? guide.close() : root.load()
    }

    // KWin never gives its own QML windows keyboard focus, so Escape can't
    // reach the guide as a key press. Instead a global Escape shortcut exists
    // only while the guide is up, and is removed from KDE's list again when
    // it closes, so Escape goes back to the apps. (A shortcut destroyed and
    // made again without being removed can end up deaf.)
    Loader {
        id: escapeKey
        active: false
        sourceComponent: ShortcutHandler {
            name: "KeysGuideEscape"
            text: "Keys Guide: Close (only while it is open)"
            sequence: "Escape"
            onActivated: guide.close()
        }
    }
    function releaseEscape() {
        if (!escapeKey.active) return;
        escapeKey.active = false;
        dbus("/kglobalaccel", "org.kde.KGlobalAccel", "unregister", ["kwin", "KeysGuideEscape"], () => {});
    }

    // Clicking any other window (or the desktop) activates it: close then.
    Connections {
        target: Workspace
        function onWindowActivated(w) { if (guide.visible) guide.close(); }
    }

    // Settings from System Settings > Window Management > KWin Scripts >
    // Keys Guide (contents/config/main.xml). Read on every open.
    function setting(key, fallback) {
        const v = KWin.readConfig(key, fallback);
        return v === undefined || v === null ? fallback : v;
    }

    function colorSetting(text) {
        const m = /^(\d+),(\d+),(\d+)(?:,(\d+))?$/.exec(String(text).trim());
        if (m) return Qt.rgba(m[1] / 255, m[2] / 255, m[3] / 255, m[4] === undefined ? 1 : m[4] / 255);
        return String(text);    // "#rrggbb" or a colour name
    }

    function dbus(path, iface, method, args, done) {
        const call = Qt.createQmlObject('import org.kde.kwin; DBusCall { service: "org.kde.kglobalaccel" }', root);
        call.path = path;
        call.dbusInterface = iface;
        call.method = method;
        call.arguments = args || [];
        call.finished.connect(ret => { done(ret && ret.length ? ret[0] : []); call.destroy(); });
        call.failed.connect(() => { done([]); call.destroy(); });
        call.call();
    }

    function load() {
        dbus("/kglobalaccel", "org.kde.KGlobalAccel", "allComponents", [], paths => {
            paths = (paths || []).map(String);
            let rows = [];
            let pending = paths.length;
            if (!pending) return;
            for (const p of paths) {
                dbus(p, "org.kde.kglobalaccel.Component", "allShortcutInfos", [], infos => {
                    rows = rows.concat(Grouping.rowsOf(p, infos, KeyNames.names));
                    if (--pending === 0) show(rows);
                });
            }
        });
    }

    function show(rows) {
        const errors = [];
        const sections = Grouping.sections(rows, {
            custom: Grouping.parseRules(setting("CustomGroups", ""), errors),
            hide: Grouping.parsePattern(setting("HidePattern", "")),
            splitScripts: String(setting("SplitScripts", true)) !== "false",
        });
        const own = rows.find(r => r.componentId === "kwin" && r.action === actionName);
        guide.customAccent = String(setting("UseCustomAccent", false)) === "true"
            ? colorSetting(setting("AccentColor", "61,174,233")) : "transparent";
        guide.open(sections, own ? own.keys.join(" or ") : "", errors, Workspace.activeScreen.geometry);
    }

    QW.Window {
        id: guide
        // KWin treats this as a normal window whatever its flags, so border
        // effects may outline it; they can exclude it by this caption.
        title: "Keys Guide overlay"
        // Unmanaged, so KWin doesn't place it inside the work area: the dimmed
        // overlay covers panels too, from the monitor's top-left corner.
        flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
        color: "transparent"
        visible: false

        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false

        property var sections: []
        property string ownKeys: ""
        property var errors: []
        property var area: null
        property color customAccent: "transparent"

        readonly property color accent: customAccent.a > 0 ? customAccent : Kirigami.Theme.highlightColor
        readonly property int unit: Kirigami.Units.gridUnit
        readonly property int columnWidth: unit * 26
        readonly property int columnCount: area ? Math.max(1, Math.min(3, Math.floor((area.width * 0.9) / (columnWidth + unit)))) : 1

        // The window covers the whole monitor, dimmed, so a click anywhere on
        // it closes the guide (a click on the window that already had focus
        // activates nothing). The panel in the middle is sized from the
        // laid-out content, so its size stays a binding: the lists fill in
        // after open() has set the sections.
        width: area ? area.width : 1
        height: area ? area.height : 1
        x: area ? area.x : 0
        y: area ? area.y : 0

        // Sections in order, split into columns of about the same length.
        readonly property var columns: {
            const cols = [];
            for (let i = 0; i < columnCount; i++) cols.push([]);
            const total = sections.reduce((n, s) => n + s.rows.length + 2, 0);
            let col = 0, used = 0;
            for (const s of sections) {
                if (col < columnCount - 1 && used > 0 && used + (s.rows.length + 2) / 2 > total / columnCount) { col++; used = 0; }
                cols[col].push(s);
                used += s.rows.length + 2;
            }
            return cols;
        }

        function open(list, own, errs, where) {
            sections = list;
            ownKeys = own;
            errors = errs;
            area = where;
            flick.contentY = 0;
            show();
            raise();
            escapeKey.active = true;
        }

        onVisibleChanged: if (!visible) root.releaseEscape()

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.35)
        }
        MouseArea { anchors.fill: parent; onClicked: guide.close() }

        Rectangle {
            id: panel
            width: Math.min(Math.round(guide.width * 0.92), guide.columnCount * (guide.columnWidth + guide.unit) + guide.unit * 2)
            height: Math.min(Math.round(guide.height * 0.88), header.height + Math.max(content.implicitHeight, guide.unit * 3) + guide.unit * 3)
            anchors.centerIn: parent
            radius: Kirigami.Units.cornerRadius
            color: Qt.alpha(Kirigami.Theme.backgroundColor, 0.97)
            border.color: guide.accent
            border.width: 2

            MouseArea { anchors.fill: parent; onClicked: guide.close() }

            Column {
                id: header
                x: guide.unit; y: guide.unit
                width: parent.width - guide.unit * 2
                spacing: guide.unit / 4
                Text {
                    text: "Keyboard shortcuts"
                    color: Kirigami.Theme.textColor
                    font.pixelSize: guide.unit * 1.3
                    font.bold: true
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Live from KDE. Esc, a click anywhere" + (guide.ownKeys ? " or " + guide.ownKeys : "")
                          + " closes; scroll with the mouse wheel."
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: guide.unit * 0.75
                }
                Text {
                    visible: guide.errors.length > 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Skipped custom section lines (need “Title: regex”): " + guide.errors.join("  ·  ")
                    color: Kirigami.Theme.negativeTextColor
                    font.pixelSize: guide.unit * 0.75
                }
            }

            Text {
                anchors.centerIn: flick
                visible: guide.sections.length === 0
                text: "No global shortcuts have a key"
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: guide.unit * 0.9
            }

            Flickable {
                id: flick
                anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; margins: guide.unit; topMargin: guide.unit * 0.75 }
                contentHeight: content.implicitHeight
                clip: true
                interactive: contentHeight > height

                Row {
                    id: content
                    spacing: guide.unit
                    Repeater {
                        model: guide.columns
                        Column {
                            required property var modelData
                            width: guide.columnWidth
                            spacing: guide.unit * 0.75
                            Repeater {
                                model: modelData
                                Column {
                                    required property var modelData
                                    width: guide.columnWidth
                                    spacing: 3
                                    Text {
                                        text: modelData.title
                                        color: guide.accent
                                        font.bold: true
                                        font.pixelSize: guide.unit * 0.85
                                        bottomPadding: 2
                                    }
                                    Repeater {
                                        model: modelData.rows
                                        Item {
                                            required property var modelData
                                            width: guide.columnWidth
                                            height: Math.max(label.implicitHeight, chips.height)
                                            Text {
                                                id: label
                                                anchors.verticalCenter: parent.verticalCenter
                                                // The label keeps at least 45% of the row; keys that don't
                                                // fit in the rest are cut off on the left.
                                                width: Math.max(parent.width * 0.45, parent.width - chips.width - guide.unit / 2)
                                                text: modelData.label
                                                color: Kirigami.Theme.textColor
                                                elide: Text.ElideRight
                                                font.pixelSize: guide.unit * 0.72
                                            }
                                            Item {
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - label.width - guide.unit / 2
                                                height: chips.height
                                                clip: true
                                                Row {
                                                    id: chips
                                                    anchors.right: parent.right
                                                    layoutDirection: Qt.RightToLeft
                                                    spacing: guide.unit / 4
                                                    Repeater {
                                                        model: modelData.keys
                                                        Rectangle {
                                                            required property string modelData
                                                            width: keyText.implicitWidth + guide.unit / 2
                                                            height: keyText.implicitHeight + 2
                                                            radius: 3
                                                            color: Qt.alpha(guide.accent, 0.14)
                                                            border.color: Qt.alpha(guide.accent, 0.35)
                                                            Text {
                                                                id: keyText
                                                                anchors.centerIn: parent
                                                                text: modelData
                                                                color: Kirigami.Theme.textColor
                                                                font.family: "monospace"
                                                                font.pixelSize: guide.unit * 0.68
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
