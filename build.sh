#!/bin/sh
# Builds dist/keys-guide-<version>.kwinscript (a zip of package/) for the
# KDE Store or `kpackagetool6 --type=KWin/Script -i`. Runs the tests first.
set -eu
cd "$(dirname "$0")"

node tools/test-grouping.mjs
python3 tools/gen-keynames.py | cmp -s - package/contents/ui/KeyNames.js \
    || echo "note: KeyNames.js differs from this system's Qt headers (tools/gen-keynames.py to regenerate)" >&2

version=$(python3 -c 'import json; print(json.load(open("package/metadata.json"))["KPlugin"]["Version"])')
out="dist/keys-guide-$version.kwinscript"
mkdir -p dist
rm -f "$out"
(cd package && python3 -m zipfile -c "../$out" metadata.json contents)
echo "$out"
