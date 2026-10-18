.pragma library
// Turns kglobalaccel's shortcut lists into the cheat sheet's sections. Kept free of
// QML so tools/test-grouping.mjs can run it under node.

// Qt modifier bits in a key code, in the order System Settings writes them.
var MODIFIERS = [
    [0x10000000, "Meta"],
    [0x04000000, "Ctrl"],
    [0x08000000, "Alt"],
    [0x02000000, "Shift"],
    [0x20000000, "Num"],
];

// KWin's own actions, by action id (ids are untranslated, labels are not).
// Checked in order; the first match wins, and what matches none goes to
// "Other KWin".
var KWIN_GROUPS = [
    { title: "Overview & effects", match: /^(Overview|Cycle Overview|Grid View|Expose|Show Desktop|view_|MoveZoom|Zoom|Invert|MoveMouseTo|Toggle Night Color|Toggle .*Show|ShowPaint|ShowFps|Edit Tiles|Increase Opacity|Decrease Opacity|Mouse|Magnifier|Cube|Track)/ },
    { title: "Window switching", match: /^(Walk Through|Switch Window|Activate Window)/ },
    { title: "Screens", match: /Screen|Output/ },
    { title: "Virtual desktops", match: /Desktop/ },
    { title: "Windows", match: /Window/ },
];
var OTHER_KWIN = "Other KWin";
var HARDWARE = "Hardware keys";

// Media, volume, brightness, power, launch and similar dedicated keys
// (Qt::Key_Back .. Key_Keyboard, Key_MediaLast, Key_Cancel .. Key_CameraFocus).
function isHardwareKey(code) {
    var key = (Number(code) || 0) & 0x01ffffff;
    return (key >= 0x01000061 && key <= 0x0100011f) || key === 0x0100ffff
        || (key >= 0x01020001 && key <= 0x0110ffff);
}

// Qt key code -> "Meta+Shift+←". names: KeyNames.names.
function keyText(code, names) {
    code = Number(code) || 0;
    if (!code) return "";
    var parts = [];
    for (var i = 0; i < MODIFIERS.length; i++)
        if (code & MODIFIERS[i][0]) parts.push(MODIFIERS[i][1]);
    var key = code & 0x01ffffff;
    var name = key === 0x20 ? "Space" : names[key];
    if (name === undefined && key > 0x20 && key < 0x01000000)
        name = String.fromCodePoint(key).toUpperCase();
    if (name === undefined) name = "0x" + key.toString(16);
    parts.push(name);
    return parts.join("+");
}

// "Title: regex" lines -> [{ title, match }]. Blank lines, "#" comments and
// lines whose regex doesn't compile are skipped (and reported in errors).
function parseRules(text, errors) {
    var rules = [];
    String(text || "").split("\n").forEach(function (line) {
        line = line.trim();
        if (!line || line[0] === "#") return;
        var colon = line.indexOf(":");
        if (colon < 1) { if (errors) errors.push(line); return; }
        try {
            rules.push({ title: line.slice(0, colon).trim(), match: new RegExp(line.slice(colon + 1).trim(), "i") });
        } catch (e) {
            if (errors) errors.push(line);
        }
    });
    return rules;
}

// One entry per line, trimmed and lower-cased; blank lines and "#" comments
// are skipped.
function parseList(text) {
    return String(text || "").split("\n")
        .map(function (line) { return line.trim().toLowerCase(); })
        .filter(function (line) { return line && line[0] !== "#"; });
}

function parsePattern(text) {
    text = String(text || "").trim();
    if (!text) return null;
    try { return new RegExp(text, "i"); } catch (e) { return null; }
}

// One component's allShortcutInfos() reply -> rows with at least one key.
// Each entry is [action, label, component, component label, context,
// context label, keys, default keys].
function rowsOf(path, infos, names) {
    var out = [];
    (infos || []).forEach(function (r) {
        if (/^ShortcutCheatSheet(Escape|Backspace|Delete|SelectAll|Type )/.test(String(r[0]))) return;   // the cheat sheet's own typing keys
        var keys = [];
        (r[6] || []).forEach(function (k) { var t = keyText(k, names); if (t) keys.push(t); });
        if (!keys.length) return;
        var codes = (r[6] || []).filter(function (k) { return Number(k); });
        out.push({
            path: String(path),
            action: String(r[0]),
            label: String(r[1]),
            componentId: String(r[2]),
            component: String(r[3]) || String(r[2]),
            keys: keys,
            hardware: codes.every(isHardwareKey),
        });
    });
    return out;
}

// rows: all components' rows. options: { custom: rules, hide: RegExp|null,
// splitScripts: bool, groupHardware: bool, hiddenSections: [lower-cased
// titles] }. Returns
// [{ title, rows: [{ label, keys, search }] }].
function sections(rows, options) {
    options = options || {};
    var custom = options.custom || [];
    var hide = options.hide || null;
    var splitScripts = options.splitScripts !== false;
    var groupHardware = options.groupHardware !== false;
    var hiddenSections = options.hiddenSections || [];

    var visible = rows.filter(function (row) {
        return !hide || !(hide.test(row.label) || hide.test(row.action) || hide.test(row.component + ": " + row.label));
    });

    // KWin scripts register their shortcuts in KWin's component, mostly
    // labelled "Script Name: what it does". A prefix used by two or more
    // shortcuts becomes a section of its own.
    var prefixOf = function (row) {
        var m = /^([^:]{1,40}?): (.+)$/.exec(row.label);
        return m ? [m[1], m[2]] : null;
    };
    var prefixCount = {};
    if (splitScripts) {
        visible.forEach(function (row) {
            if (row.componentId !== "kwin") return;
            var p = prefixOf(row);
            if (p) prefixCount[p[0]] = (prefixCount[p[0]] || 0) + 1;
        });
    }

    var order = [];          // section titles in display order
    var byTitle = {};
    var add = function (title, row, label) {
        if (!byTitle[title]) { byTitle[title] = []; order.push(title); }
        byTitle[title].push({ label: label || row.label, keys: row.keys, search: row.keys.join(" ") });
    };
    // Fixed order: custom sections, KWin's built-in groups, scripts, other
    // KWin, then other components by name. Reserve the leading slots now.
    custom.forEach(function (rule) { if (!byTitle[rule.title]) { byTitle[rule.title] = []; order.push(rule.title); } });
    KWIN_GROUPS.forEach(function (g) { if (!byTitle[g.title]) { byTitle[g.title] = []; order.push(g.title); } });

    var scripts = {}, others = {}, otherKwin = [], hardware = [];
    visible.forEach(function (row) {
        for (var i = 0; i < custom.length; i++) {
            if (custom[i].match.test(row.label) || custom[i].match.test(row.action)) {
                var p0 = prefixOf(row);
                add(custom[i].title, row, p0 && prefixCount[p0[0]] > 1 ? p0[1] : row.label);
                return;
            }
        }
        if (groupHardware && row.hardware) {
            hardware.push(row);
            return;
        }
        if (row.componentId === "kwin") {
            var p = prefixOf(row);
            if (p && prefixCount[p[0]] > 1) {
                (scripts[p[0]] = scripts[p[0]] || []).push([row, p[1]]);
                return;
            }
            for (var j = 0; j < KWIN_GROUPS.length; j++) {
                if (KWIN_GROUPS[j].match.test(row.action)) { add(KWIN_GROUPS[j].title, row); return; }
            }
            otherKwin.push(row);
            return;
        }
        (others[row.component] = others[row.component] || []).push(row);
    });
    Object.keys(scripts).sort(cmp).forEach(function (name) {
        scripts[name].forEach(function (pair) { add(name, pair[0], pair[1]); });
    });
    otherKwin.forEach(function (row) { add(OTHER_KWIN, row); });
    Object.keys(others).sort(cmp).forEach(function (name) {
        others[name].forEach(function (row) { add(name, row); });
    });
    hardware.forEach(function (row) { add(HARDWARE, row); });

    return order
        .map(function (title) {
            return { title: title, rows: collapseRuns(byTitle[title]).sort(function (a, b) { return cmp(a.label, b.label); }) };
        })
        .filter(function (s) { return s.rows.length && hiddenSections.indexOf(s.title.toLowerCase()) < 0; });
}

// Numbered rows like "Switch to Desktop 1/2/3" on Ctrl+F1/F2/F3, three or
// more in a row with one key each, become one row: "Switch to Desktop 1–3"
// on "Ctrl+F1 … 3". The row keeps every key in .search for the filter.
function collapseRuns(rows) {
    var groups = {};
    rows.forEach(function (row, i) {
        var lm = /^(.*?)(\d+)$/.exec(row.label);
        var km = row.keys.length === 1 ? /^(.*?)(\d+)$/.exec(row.keys[0]) : null;
        if (!lm || !km) return;
        var ln = Number(lm[2]), kn = Number(km[2]);
        var id = lm[1] + "\u0000" + km[1] + "\u0000" + (kn - ln);
        (groups[id] = groups[id] || []).push({ i: i, ln: ln, kn: kn, lp: lm[1], kp: km[1] });
    });
    var drop = {}, merged = {};
    Object.keys(groups).forEach(function (id) {
        var g = groups[id].sort(function (a, b) { return a.ln - b.ln; });
        for (var start = 0; start < g.length;) {
            var end = start;
            while (end + 1 < g.length && g[end + 1].ln === g[end].ln + 1) end++;
            if (end - start >= 2) {
                var first = g[start], last = g[end], search = [];
                for (var k = start; k <= end; k++) { drop[g[k].i] = true; search.push(rows[g[k].i].keys[0]); }
                merged[first.i] = {
                    label: first.lp + first.ln + "\u2013" + last.ln,
                    keys: [first.kp + first.kn + " \u2026 " + last.kn],
                    search: search.join(" "),
                };
            }
            start = end + 1;
        }
    });
    var out = [];
    rows.forEach(function (row, i) {
        if (merged[i]) out.push(merged[i]);
        else if (!drop[i]) out.push(row);
    });
    return out;
}

// Sections with only the rows whose section title, label or keys contain
// every word of the query (ignoring case).
function filter(list, query) {
    var words = String(query || "").toLowerCase().split(/\s+/).filter(function (w) { return w; });
    if (!words.length) return list;
    var out = [];
    list.forEach(function (s) {
        var rows = s.rows.filter(function (row) {
            var hay = (s.title + " " + row.label + " " + (row.search || row.keys.join(" "))).toLowerCase();
            return words.every(function (w) { return hay.indexOf(w) >= 0; });
        });
        if (rows.length) out.push({ title: s.title, rows: rows });
    });
    return out;
}

function cmp(a, b) { return String(a).localeCompare(String(b)); }
