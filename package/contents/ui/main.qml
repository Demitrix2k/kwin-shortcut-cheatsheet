// Keys Guide's entry point. KWin caches the file a script starts with
// (ui/main.qml) and what it imports until the next login, so this file stays
// tiny and the guide itself lives in Guide.qml, loaded under a new URL each
// time the script starts: an edited Guide.qml takes effect when the script is
// turned off and on again, without logging out.
import QtQuick

Loader {
    source: Qt.resolvedUrl("Guide.qml") + "?" + Date.now()
}
