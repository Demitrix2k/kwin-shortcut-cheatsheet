// Checks Grouping.js and KeyNames.js under node: node tools/test-grouping.mjs
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

const ui = new URL("../package/contents/ui/", import.meta.url);
const load = (file, names) => {
    const src = readFileSync(new URL(file, ui), "utf8").replace(/^\.pragma library\s*$/m, "");
    return new Function(`${src}\nreturn { ${names} };`)();
};
const { names } = load("KeyNames.js", "names");
const G = load("Grouping.js", "keyText, parseRules, parsePattern, rowsOf, sections, filter");

// Key codes.
const META = 0x10000000, CTRL = 0x04000000, ALT = 0x08000000, SHIFT = 0x02000000;
assert.equal(G.keyText(META | 0x2f, names), "Meta+/");
assert.equal(G.keyText(META | SHIFT | 0x01000012, names), "Meta+Shift+←");
assert.equal(G.keyText(CTRL | ALT | 0x01000007, names), "Ctrl+Alt+Del");
assert.equal(G.keyText(META | 0x20, names), "Meta+Space");
assert.equal(G.keyText(META | 0x61, names), "Meta+A");
assert.equal(G.keyText(0x01000030 + 11, names), "F12");
assert.equal(G.keyText(0, names), "");

// Rules.
const errors = [];
const rules = G.parseRules("# comment\nFocus: ^Switch Window|Focus\n\nBroken: (\nno colon here", errors);
assert.equal(rules.length, 1);
assert.equal(rules[0].title, "Focus");
assert.deepEqual(errors, ["Broken: (", "no colon here"]);
assert.equal(G.parsePattern(""), null);
assert.equal(G.parsePattern("("), null);

// Grouping. Entries: [action, label, component, component label, context,
// context label, keys, default keys].
const info = (action, label, keys, comp = "kwin", compLabel = "KWin") =>
    [action, label, comp, compLabel, "default", "Default Context", keys, []];
const kwin = G.rowsOf("/component/kwin", [
    info("Overview", "Toggle Overview", [META | 0x57]),
    info("Window Close", "Close Window", [ALT | 0x01000033]),
    info("Window Maximize", "Maximize Window", []),                      // unbound: hidden
    info("Switch to Desktop 1", "Switch to Desktop 1", [CTRL | 0x01000030]),
    info("Window to Next Screen", "Move Window to Next Screen", [META | SHIFT | 0x01000014]),
    info("Show Desktop", "Peek at Desktop", [META | 0x44]),
    info("Walk Through Windows", "Walk Through Windows", [ALT | 0x01000001]),
    info("disableInputCapture", "Disable Active Input Capture", [META | SHIFT | 0x01000000]),
    info("TilerFocusLeft", "Tiler: Focus Left", [META | 0x48]),
    info("TilerFocusRight", "Tiler: Focus Right", [META | 0x4c]),
    info("Lonely", "Lonely: only one", [META | 0x4f]),                  // single prefix: not split
    info("KeysGuideType a", "Keys Guide: type into the filter", [0x41]), // own typing keys: hidden
    info("KeysGuideEscape", "Keys Guide: clear the filter, or close", [0x01000000]),
    info("KeysGuideSelectAll", "Keys Guide: select the whole filter", [CTRL | 0x41]),
    info("KeysGuideDeleteWord", "Keys Guide: delete a filter word", [CTRL | 0x01000003]),
], names);
const plasma = G.rowsOf("/component/plasmashell", [
    info("show dashboard", "Show Desktop Grid", [CTRL | 0x01000033], "plasmashell", "Plasma"),
], names);
const all = kwin.concat(plasma);

const titles = s => s.map(x => x.title);
let s = G.sections(all, {});
assert.deepEqual(titles(s), ["Overview & effects", "Window switching", "Screens", "Virtual desktops", "Windows", "Tiler", "Other KWin", "Plasma"]);
assert.deepEqual(s.find(x => x.title === "Tiler").rows.map(r => r.label), ["Focus Left", "Focus Right"]);
assert.ok(s.find(x => x.title === "Other KWin").rows.some(r => r.label === "Lonely: only one"));
assert.ok(s.find(x => x.title === "Overview & effects").rows.some(r => r.label === "Peek at Desktop"));

s = G.sections(all, { custom: G.parseRules("Focus: Focus|^Walk Through"), hide: G.parsePattern("^Plasma: ") });
assert.equal(s[0].title, "Focus");
assert.deepEqual(s[0].rows.map(r => r.label), ["Focus Left", "Focus Right", "Walk Through Windows"]);
assert.ok(!titles(s).includes("Plasma"));
assert.ok(!titles(s).includes("Tiler"));

s = G.sections(all, { splitScripts: false });
assert.ok(!titles(s).includes("Tiler"));

const f = G.filter(G.sections(all, {}), "meta shift");
assert.deepEqual(f.flatMap(x => x.rows.map(r => r.label)).sort(), ["Disable Active Input Capture", "Move Window to Next Screen"]);
assert.deepEqual(G.filter(G.sections(all, {}), "tiler right").flatMap(x => x.rows.map(r => r.label)), ["Focus Right"]);
assert.equal(G.filter(G.sections(all, {}), " ").length, G.sections(all, {}).length);
assert.equal(G.filter(G.sections(all, {}), "zzz").length, 0);

console.log("ok");
