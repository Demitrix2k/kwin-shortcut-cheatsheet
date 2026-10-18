#!/bin/sh
# Builds dist/kwin-shortcut-cheatsheet-<version>.kwinscript (a zip of package/) for the
# KDE Store or `kpackagetool6 --type=KWin/Script -i`. Runs the tests first.
#
# In the built package the JS libraries live in contents/ui/lib-<version>/ rather than
# next to CheatSheet.qml. KWin's QML engine keeps every JS file it has imported until
# logout, keyed by its path, so after an in-place update (`kpackagetool6 -u`) a script
# that imports "Grouping.js" would keep running the old copy. A folder named after the
# version gives each release new paths, so turning the script off and on is enough.
# package/ itself keeps the plain imports, so loading it directly for development works.
set -eu
cd "$(dirname "$0")"

node tools/test-grouping.mjs
python3 tools/gen-keynames.py | cmp -s - package/contents/ui/KeyNames.js \
    || echo "note: KeyNames.js differs from this system's Qt headers (tools/gen-keynames.py to regenerate)" >&2

version=$(python3 -c 'import json; print(json.load(open("package/metadata.json"))["KPlugin"]["Version"])')
out="dist/kwin-shortcut-cheatsheet-$version.kwinscript"
lib="lib-$version"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp -r package/metadata.json package/contents "$stage/"
ui="$stage/contents/ui"
mkdir "$ui/$lib"
for js in Grouping.js KeyNames.js; do
    mv "$ui/$js" "$ui/$lib/$js"
    grep -q "^import \"$js\"" "$ui/CheatSheet.qml" \
        || { echo "build.sh: CheatSheet.qml doesn't import \"$js\"" >&2; exit 1; }
    sed -i "s#^import \"$js\"#import \"$lib/$js\"#" "$ui/CheatSheet.qml"
done
if grep -rqE '^import "[A-Za-z]+\.js"' "$ui"; then
    echo "build.sh: a JS import still points next to the QML file" >&2
    exit 1
fi

mkdir -p dist
rm -f "$out"
(cd "$stage" && python3 -m zipfile -c "$OLDPWD/$out" metadata.json contents)
echo "$out"
