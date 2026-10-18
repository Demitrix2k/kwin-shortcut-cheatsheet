// KWin Shortcut Cheat Sheet: a shortcut (Meta+/ by default) shows every
// global shortcut that has a key, as KDE has it right now: kglobalaccel is asked over D-Bus each
// time, so a key changed in System Settings shows up straight away.
// Typing filters it. Escape clears the filter, then closes it; so does a
// click (on it or on any other window) or the shortcut again.
import QtQuick
import QtQuick.Window as QW
import org.kde.kwin
import org.kde.kirigami as Kirigami
import "KeyNames.js" as KeyNames
import "Grouping.js" as Grouping

Item {
    id: root

    readonly property string actionName: "ShortcutCheatSheetShow"

    // A key combination drawn as a small keycap.
    // (Inline components can't see this file's ids, so the accent is passed in.)
    component KeyChip: Rectangle {
        property string text
        property color accent
        width: chipText.implicitWidth + Kirigami.Units.gridUnit / 2
        height: chipText.implicitHeight + 2
        radius: 3
        color: Qt.alpha(accent, 0.14)
        border.color: Qt.alpha(accent, 0.35)
        Text {
            id: chipText
            anchors.centerIn: parent
            text: parent.text
            color: Kirigami.Theme.textColor
            font.family: "monospace"
            font.pixelSize: Kirigami.Units.gridUnit * 0.68
        }
    }

    ShortcutHandler {
        name: root.actionName
        text: "KWin Shortcut Cheat Sheet: Show or hide the cheat sheet"
        sequence: "Meta+/"
        onActivated: sheet.visible ? sheet.close() : root.load()
    }

    // KWin never gives its own QML windows keyboard focus, so key presses
    // can't reach the sheet. Instead, while it is up, the keys it needs are
    // global shortcuts (letters, digits and space type into the filter;
    // Backspace deletes, Ctrl+Backspace a word; Ctrl+A selects the filter,
    // so Backspace, Delete or typing replaces all of it; Escape clears the
    // filter, then closes), and they
    // are all removed from KDE's list again when it closes, so the keys go
    // back to the apps. (A shortcut destroyed and made again without being
    // removed can end up deaf.)
    readonly property var typedKeys: "abcdefghijklmnopqrstuvwxyz0123456789".split("").concat([" "])
    function typeName(k) { return "ShortcutCheatSheetType " + (k === " " ? "Space" : k); }
    Loader {
        id: typing
        active: false
        sourceComponent: Item {
            ShortcutHandler {
                name: "ShortcutCheatSheetEscape"
                text: "KWin Shortcut Cheat Sheet: Clear the filter, or close (only while it is open)"
                sequence: "Escape"
                onActivated: sheet.query ? sheet.query = "" : sheet.close()
            }
            ShortcutHandler {
                name: "ShortcutCheatSheetBackspace"
                text: "KWin Shortcut Cheat Sheet: Delete a filter letter (only while it is open)"
                sequence: "Backspace"
                onActivated: sheet.query = sheet.allSelected ? "" : sheet.query.slice(0, -1)
            }
            ShortcutHandler {
                name: "ShortcutCheatSheetDeleteWord"
                text: "KWin Shortcut Cheat Sheet: Delete a filter word (only while it is open)"
                sequence: "Ctrl+Backspace"
                onActivated: sheet.query = sheet.allSelected ? "" : sheet.query.replace(/\S+\s*$|\s+$/, "")
            }
            ShortcutHandler {
                name: "ShortcutCheatSheetDelete"
                text: "KWin Shortcut Cheat Sheet: Delete the selected filter (only while it is open)"
                sequence: "Del"
                onActivated: if (sheet.allSelected) sheet.query = ""
            }
            ShortcutHandler {
                name: "ShortcutCheatSheetSelectAll"
                text: "KWin Shortcut Cheat Sheet: Select the whole filter (only while it is open)"
                sequence: "Ctrl+A"
                onActivated: sheet.allSelected = sheet.query !== ""
            }
            Instantiator {
                model: root.typedKeys
                delegate: ShortcutHandler {
                    required property string modelData
                    name: root.typeName(modelData)
                    text: "KWin Shortcut Cheat Sheet: Type into the filter (only while it is open)"
                    sequence: modelData === " " ? "Space" : modelData.toUpperCase()
                    onActivated: sheet.query = sheet.allSelected ? modelData : sheet.query + modelData
                }
            }
        }
    }
    function releaseKeys() {
        if (!typing.active) return;
        typing.active = false;
        const names = ["ShortcutCheatSheetEscape", "ShortcutCheatSheetBackspace", "ShortcutCheatSheetDeleteWord", "ShortcutCheatSheetDelete", "ShortcutCheatSheetSelectAll"].concat(typedKeys.map(typeName));
        for (const n of names) dbus("/kglobalaccel", "org.kde.KGlobalAccel", "unregister", ["kwin", n], () => {});
    }

    // Clicking any other window (or the desktop) activates it: close then.
    Connections {
        target: Workspace
        function onWindowActivated(w) { if (sheet.visible) sheet.close(); }
    }

    // Settings from System Settings > Window Management > KWin Scripts >
    // KWin Shortcut Cheat Sheet (contents/config/main.xml). Read on every open.
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
            groupHardware: String(setting("GroupHardwareKeys", true)) !== "false",
        });
        const own = rows.find(r => r.componentId === "kwin" && r.action === actionName);
        sheet.customAccent = String(setting("UseCustomAccent", false)) === "true"
            ? colorSetting(setting("AccentColor", "61,174,233")) : "transparent";
        sheet.open(sections, own ? own.keys.join(" or ") : "", errors, Workspace.activeScreen.geometry);
    }

    QW.Window {
        id: sheet
        // KWin treats this as a normal window whatever its flags, so border
        // effects may outline it; they can exclude it by this caption.
        title: "KWin Shortcut Cheat Sheet overlay"
        // Unmanaged, so KWin doesn't place it inside the work area: the dimmed
        // overlay covers panels too, from the monitor's top-left corner.
        flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
        color: "transparent"
        visible: false

        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false

        property var sections: []
        property string query: ""
        // Ctrl+A: the next Backspace, Delete or typed key replaces the
        // whole filter. Any change to the filter ends the selection.
        property bool allSelected: false
        onQueryChanged: { flick.contentY = 0; allSelected = false; }
        readonly property var shown: Grouping.filter(sections, query)
        readonly property int shownCount: shown.reduce((n, s) => n + s.rows.length, 0)
        property string ownKeys: ""
        property var errors: []
        property var area: null
        property color customAccent: "transparent"

        readonly property color accent: customAccent.a > 0 ? customAccent : Kirigami.Theme.highlightColor
        readonly property int unit: Kirigami.Units.gridUnit
        readonly property int columnWidth: unit * 26
        readonly property int columnCount: area ? Math.max(1, Math.min(3, Math.floor((area.width * 0.9) / (columnWidth + unit)))) : 1

        // The window covers the whole monitor, dimmed, so a click anywhere on
        // it closes the sheet (a click on the window that already had focus
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
            const total = shown.reduce((n, s) => n + s.rows.length + 2, 0);
            let col = 0, used = 0;
            for (const s of shown) {
                if (col < columnCount - 1 && used > 0 && used + (s.rows.length + 2) / 2 > total / columnCount) { col++; used = 0; }
                cols[col].push(s);
                used += s.rows.length + 2;
            }
            return cols;
        }

        function open(list, own, errs, where) {
            query = "";
            sections = list;
            ownKeys = own;
            errors = errs;
            area = where;
            flick.contentY = 0;
            show();
            raise();
            typing.active = true;
        }

        onVisibleChanged: if (!visible) root.releaseKeys()

        // The panel keeps the height it opened with while a filter narrows
        // the list, so it doesn't jump around under the pointer.
        readonly property real naturalHeight: Math.min(Math.round(height * 0.88), header.height + Math.max(content.implicitHeight, unit * 3) + footer.height + unit * 4)
        property real keptHeight: 0
        onNaturalHeightChanged: if (!query) keptHeight = naturalHeight

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.35)
        }
        MouseArea { anchors.fill: parent; onClicked: sheet.close() }

        Rectangle {
            id: panel
            width: Math.min(Math.round(sheet.width * 0.92), sheet.columnCount * (sheet.columnWidth + sheet.unit) + sheet.unit * 2)
            height: sheet.query ? Math.max(sheet.keptHeight, sheet.naturalHeight) : sheet.naturalHeight
            anchors.centerIn: parent
            radius: Kirigami.Units.cornerRadius
            color: Qt.alpha(Kirigami.Theme.backgroundColor, 0.97)
            border.color: sheet.accent
            border.width: 2

            MouseArea { anchors.fill: parent; onClicked: sheet.close() }

            Column {
                id: header
                x: sheet.unit; y: sheet.unit
                width: parent.width - sheet.unit * 2
                spacing: sheet.unit / 4
                Item {
                    width: parent.width
                    height: title.implicitHeight
                    Text {
                        id: title
                        text: "Keyboard shortcuts"
                        color: Kirigami.Theme.textColor
                        font.pixelSize: sheet.unit * 1.3
                        font.bold: true
                    }
                    // What's typed, at the right of the title.
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: title.verticalCenter
                        Text {
                            text: sheet.query ? "Filter: " : "Type to filter"
                            color: sheet.query ? sheet.accent : Kirigami.Theme.disabledTextColor
                            font.pixelSize: sheet.unit * 0.85
                            font.family: sheet.query ? "monospace" : Kirigami.Theme.defaultFont.family
                        }
                        Text {
                            visible: sheet.query !== ""
                            text: sheet.query
                            // Selected (Ctrl+A): drawn like a text selection.
                            color: sheet.allSelected ? Kirigami.Theme.highlightedTextColor : sheet.accent
                            font.pixelSize: sheet.unit * 0.85
                            font.family: "monospace"
                            Rectangle {
                                z: -1
                                anchors.fill: parent
                                visible: sheet.allSelected
                                color: Kirigami.Theme.highlightColor
                            }
                        }
                        Text {
                            visible: sheet.query !== ""
                            text: "\u258f  " + sheet.shownCount + (sheet.shownCount === 1 ? " match" : " matches")
                            color: sheet.accent
                            font.pixelSize: sheet.unit * 0.85
                            font.family: "monospace"
                        }
                    }
                }
                Text {
                    visible: sheet.errors.length > 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Skipped custom section lines (need “Title: regex”): " + sheet.errors.join("  ·  ")
                    color: Kirigami.Theme.negativeTextColor
                    font.pixelSize: sheet.unit * 0.75
                }
            }

            // Keys that work while the sheet is open.
            Flow {
                id: footer
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: sheet.unit }
                spacing: sheet.unit
                Repeater {
                    model: [
                        { keys: ["Esc"], text: sheet.query ? "clear filter" : "close" },
                    ].concat(sheet.ownKeys ? [{ keys: [sheet.ownKeys], text: "close" }] : [])
                     .concat([{ keys: [], text: "click anywhere to close · mouse wheel scrolls" }])
                    Row {
                        required property var modelData
                        spacing: sheet.unit / 4
                        Repeater {
                            model: modelData.keys
                            KeyChip { required property string modelData; text: modelData; accent: sheet.accent }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.text
                            color: Kirigami.Theme.disabledTextColor
                            font.pixelSize: sheet.unit * 0.7
                        }
                    }
                }
            }
            Rectangle {
                // A hairline between the list and the footer.
                anchors { left: parent.left; right: parent.right; bottom: footer.top; margins: sheet.unit; bottomMargin: sheet.unit / 2 }
                height: 1
                color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
            }

            Text {
                anchors.centerIn: flick
                visible: sheet.shownCount === 0
                text: sheet.query ? "No shortcuts match \u201c" + sheet.query + "\u201d" : "No global shortcuts have a key"
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: sheet.unit * 0.9
            }

            Flickable {
                id: flick
                anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: footer.top; margins: sheet.unit; topMargin: sheet.unit * 0.75 }
                contentHeight: content.implicitHeight
                clip: true
                interactive: contentHeight > height

                Row {
                    id: content
                    spacing: sheet.unit
                    Repeater {
                        model: sheet.columns
                        Column {
                            required property var modelData
                            width: sheet.columnWidth
                            spacing: sheet.unit * 0.75
                            Repeater {
                                model: modelData
                                Column {
                                    required property var modelData
                                    width: sheet.columnWidth
                                    spacing: 3
                                    Text {
                                        text: modelData.title
                                        color: sheet.accent
                                        font.bold: true
                                        font.pixelSize: sheet.unit * 0.85
                                        bottomPadding: 2
                                    }
                                    Repeater {
                                        model: modelData.rows
                                        Item {
                                            required property var modelData
                                            width: sheet.columnWidth
                                            height: Math.max(label.implicitHeight, chips.height)
                                            Text {
                                                id: label
                                                anchors.verticalCenter: parent.verticalCenter
                                                // The label keeps at least 45% of the row; keys that don't
                                                // fit in the rest are cut off on the left.
                                                width: Math.max(parent.width * 0.45, parent.width - chips.width - sheet.unit / 2)
                                                text: modelData.label
                                                color: Kirigami.Theme.textColor
                                                elide: Text.ElideRight
                                                font.pixelSize: sheet.unit * 0.72
                                            }
                                            Item {
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - label.width - sheet.unit / 2
                                                height: chips.height
                                                clip: true
                                                Row {
                                                    id: chips
                                                    anchors.right: parent.right
                                                    layoutDirection: Qt.RightToLeft
                                                    spacing: sheet.unit / 4
                                                    Repeater {
                                                        model: modelData.keys
                                                        KeyChip {
                                                            required property string modelData
                                                            text: modelData
                                                            accent: sheet.accent
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

            // Scroll hints: the list fades out at an edge with more beyond
            // it, and a thin bar at the right shows where the view is.
            Rectangle {
                anchors { left: flick.left; right: flick.right; bottom: flick.bottom }
                height: sheet.unit * 2.5
                visible: flick.contentY + flick.height < flick.contentHeight - 2
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: panel.color }
                }
            }
            Rectangle {
                anchors { left: flick.left; right: flick.right; top: flick.top }
                height: sheet.unit * 1.5
                visible: flick.contentY > 2
                gradient: Gradient {
                    GradientStop { position: 0; color: panel.color }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            Rectangle {
                visible: flick.interactive
                x: flick.x + flick.width + (sheet.unit - width) / 2
                y: flick.y + flick.visibleArea.yPosition * flick.height
                width: 3
                height: Math.max(sheet.unit, flick.visibleArea.heightRatio * flick.height)
                radius: 1.5
                color: Qt.alpha(sheet.accent, 0.6)
            }
        }
    }
}
