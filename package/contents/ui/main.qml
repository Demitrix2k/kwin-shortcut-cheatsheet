// The script's entry point. KWin caches the file a script starts with
// (ui/main.qml) and what it imports until the next login, so this file stays
// tiny and the cheat sheet itself lives in CheatSheet.qml, loaded under a new
// URL each time the script starts: an edited CheatSheet.qml takes effect when the script is
// turned off and on again, without logging out.
import QtQuick

Loader {
    source: Qt.resolvedUrl("CheatSheet.qml") + "?" + Date.now()
}
