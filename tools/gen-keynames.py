#!/usr/bin/env python3
"""Generate package/contents/ui/KeyNames.js from Qt's qnamespace.h.

kglobalaccel hands shortcuts over as Qt key codes (Qt::Key | modifiers).
QML can't turn those back into text the way QKeySequence::toString() does,
so the cheat sheet carries this table of the special keys' names instead.
Printable keys aren't listed: their code is the character itself.

Usage: tools/gen-keynames.py [path/to/qnamespace.h] > package/contents/ui/KeyNames.js
"""
import re
import sys

HEADER = sys.argv[1] if len(sys.argv) > 1 else "/usr/include/qt6/QtCore/qnamespace.h"

# Shorter or friendlier names than Qt's enum, close to what System Settings shows.
RENAME = {
    "Escape": "Esc",
    "Insert": "Ins",
    "Delete": "Del",
    "Left": "←",
    "Up": "↑",
    "Right": "→",
    "Down": "↓",
    "PageUp": "PgUp",
    "PageDown": "PgDown",
    # Media, volume, brightness and power keys: what's printed on the key, not Qt's enum.
    "VolumeUp": "Volume Up",
    "VolumeDown": "Volume Down",
    "VolumeMute": "Mute",
    "MicMute": "Mic Mute",
    "MicVolumeUp": "Mic Volume Up",
    "MicVolumeDown": "Mic Volume Down",
    "MediaPlay": "Play",
    "MediaPause": "Pause",
    "MediaTogglePlayPause": "Play/Pause",
    "MediaStop": "Stop",
    "MediaNext": "Next Track",
    "MediaPrevious": "Previous Track",
    "MediaRecord": "Record",
    "AudioForward": "Fast Forward",
    "AudioRewind": "Rewind",
    "MonBrightnessUp": "Brightness Up",
    "MonBrightnessDown": "Brightness Down",
    "KeyboardBrightnessUp": "Keyboard Light Up",
    "KeyboardBrightnessDown": "Keyboard Light Down",
    "KeyboardLightOnOff": "Keyboard Light",
    "TouchpadToggle": "Touchpad",
    "TouchpadOn": "Touchpad On",
    "TouchpadOff": "Touchpad Off",
    "PowerOff": "Power",
    "PowerDown": "Power Down",
    "ScreenSaver": "Lock Screen",
    "WLAN": "Wi-Fi",
    "WebCam": "Webcam",
    "Zenkaku_Hankaku": "Zenkaku/Hankaku",
    "HomePage": "Home Page",
    # Names that read worse split into words.
    "Super_L": "Super",
    "Super_R": "Super",
    "Hyper_L": "Hyper",
    "Hyper_R": "Hyper",
    "AltGr": "AltGr",
    "SysReq": "SysReq",
    "iTouch": "iTouch",
}


def friendly(name):
    """Qt's enum name as words: "LaunchMail" -> "Launch Mail", "Launch0" -> "Launch 0"."""
    if name in RENAME:
        return RENAME[name]
    name = name.replace("_", " ")
    name = re.sub(r"(?<=[a-z])(?=[A-Z0-9])|(?<=[0-9])(?=[A-Za-z])|(?<=[A-Z])(?=[A-Z][a-z])", " ", name)
    return name


names = {}
with open(HEADER, encoding="utf-8") as f:
    for m in re.finditer(r"\bKey_(\w+)\s*=\s*(0x[0-9a-fA-F]+)", f.read()):
        name, code = m.group(1), int(m.group(2), 16)
        if code < 0x01000000:
            continue                    # printable: the code is the character
        names.setdefault(code, friendly(name))   # first name wins over aliases

out = [
    ".pragma library",
    "// Qt key names for special keys, generated from QtCore/qnamespace.h",
    "// by tools/gen-keynames.py. Printable keys aren't listed: their code is",
    "// the character.",
    "var names = {",
]
out += [f'    0x{code:08x}: "{name}",' for code, name in sorted(names.items())]
out[-1] = out[-1].rstrip(",")
out.append("};")
print("\n".join(out))
