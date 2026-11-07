.pragma library
// Task Board (frueher Obsidian Todo) - Kern fuer das KDE-Plasma-Widget.
// Liest und schreibt dasselbe Markdown-Format wie die Windows-Version (src/todo.lua):
//   - [ ] Text 🔁 wöchentlich ⏰ 15:00 📅 2026-11-05 ➕ 2026-11-01
//       - [ ] Unteraufgabe
//       - Notiz, Link oder Datei
// Alle Funktionen sind ohne Ein-/Ausgabe; Datei lesen/schreiben macht main.qml.

var ICON = { due: '📅', created: '➕', done: '✅', cancel: '❌', repeat: '🔁', time: '⏰' };
var MONTHS = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
var WEEKDAYS = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
var WEEKDAY_NAMES = ['Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag'];
var RULES = { 'täglich': 'täglich', 'taeglich': 'täglich', 'werktags': 'werktags',
    'wöchentlich': 'wöchentlich', 'woechentlich': 'wöchentlich', 'monatlich': 'monatlich',
    'jährlich': 'jährlich', 'jaehrlich': 'jährlich' };

// Zeichen, die ein neues Symbol einleiten (wie Lua-Byte 226/240: U+2000-U+2FFF und alles ausserhalb der BMP)
var SYM = '\\u2000-\\u2FFF\\uD800-\\uDFFF';
var DATE = '\\d{4}-\\d{2}-\\d{2}';
var CHECK = /^\s*[-*+] \[([ xX])\] ?(.*)$/;

function esc(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }
function pad(n) { return (n < 10 ? '0' : '') + n; }
function trim(s) { return s.replace(/^\s+/, '').replace(/\s+$/, ''); }

// ---------- Datum (immer 12 Uhr mittags, damit Sommerzeit nichts verschiebt) ----------
function dayOf(y, m, d) { return new Date(y, m - 1, d, 12); }
function today(now) { var d = now ? new Date(now) : new Date(); return dayOf(d.getFullYear(), d.getMonth() + 1, d.getDate()); }
function iso(d) { return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); }
function fromIso(s) { var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s || ''); return m ? dayOf(+m[1], +m[2], +m[3]) : null; }
function addDays(d, n) { return dayOf(d.getFullYear(), d.getMonth() + 1, d.getDate() + n); }
function daysBetween(a, b) { return Math.round((a.getTime() - b.getTime()) / 86400000); }
function sameDay(a, b) { return !!a && !!b && iso(a) === iso(b); }
function dotDate(d) { return pad(d.getDate()) + '.' + pad(d.getMonth() + 1) + '.'; }

function dueOf(text) {
    var m = new RegExp(esc(ICON.due) + '\\s*(' + DATE + ')').exec(text);
    return m ? fromIso(m[1]) : null;
}
function dueIsoOf(text) {
    var m = new RegExp(esc(ICON.due) + '\\s*(' + DATE + ')').exec(text);
    return m ? m[1] : '';
}
// Wiederholung "🔁 …" reicht bis zum naechsten Symbol ("🔁 alle 2 Wochen", "🔁 Mo,Mi,Fr")
function repPattern() { return new RegExp('\\s*' + esc(ICON.repeat) + '[^' + SYM + ']*[^\\s' + SYM + ']'); }
function ruleOf(text) {
    var m = new RegExp(esc(ICON.repeat) + '\\s*([^' + SYM + ']*[^\\s' + SYM + '])').exec(text);
    return m ? m[1] : null;
}
function normRule(r) { return RULES[r] || r; }
function timeOf(text) {
    var m = new RegExp(esc(ICON.time) + '\\s*(\\d\\d?):(\\d\\d)').exec(text);
    return m ? { h: +m[1], m: +m[2] } : null;
}
function timeStr(t) { return t ? pad(t.h) + ':' + pad(t.m) : ''; }

function stripDue(text) {
    text = text.replace(new RegExp('\\s*' + esc(ICON.due) + '\\s*' + DATE, 'g'), '');
    text = text.replace(repPattern(), '');
    return text.replace(new RegExp('\\s*' + esc(ICON.time) + '\\s*\\d\\d?:\\d\\d', 'g'), '');
}

// naechster Termin nach "due" (nicht vor heute)
// Regeln: täglich, werktags, wöchentlich, monatlich, jährlich, "alle N Tage|Wochen|Monate|Jahre", "Mo,Mi,Fr"
var WDNUM = { So: 0, Mo: 1, Di: 2, Mi: 3, Do: 4, Fr: 5, Sa: 6 };
function nextDate(due, rule, now) {
    var days = null;
    if (rule === 'werktags') rule = 'Mo,Di,Mi,Do,Fr';
    if (/^[A-Za-z,]+$/.test(rule) && !/[A-Za-z]{3}/.test(rule)) {
        var m, re = /[A-Za-z]{2}/g;
        while ((m = re.exec(rule))) {
            if (WDNUM[m[0]] !== undefined) { days = days || {}; days[WDNUM[m[0]]] = true; }
        }
    }
    var mm = /^alle (\d+) (\S+)$/.exec(rule);
    var n = mm ? +mm[1] : 0, unit = mm ? mm[2] : '';
    function step(d) {
        var y = d.getFullYear(), mo = d.getMonth() + 1, da = d.getDate();
        if (days) {
            var t = d;
            do { t = addDays(t, 1); } while (!days[t.getDay()]);
            return t;
        }
        if (n) {
            if (unit === 'Wochen') return dayOf(y, mo, da + 7 * n);
            if (unit === 'Monate') return dayOf(y, mo + n, da);
            if (unit === 'Jahre') return dayOf(y + n, mo, da);
            return dayOf(y, mo, da + n);
        }
        if (rule === 'wöchentlich') return dayOf(y, mo, da + 7);
        if (rule === 'monatlich') return dayOf(y, mo + 1, da);
        if (rule === 'jährlich') return dayOf(y + 1, mo, da);
        return dayOf(y, mo, da + 1);
    }
    var t0 = today(now);
    var nx = step(due || t0);
    while (nx < t0) nx = step(nx);
    return nx;
}

// ---------- Zeitstempel (➕ erstellt, ✅ erledigt): unsichtbar, bleiben beim Bearbeiten erhalten ----------
function stamp(icon, now) { return ' ' + icon + ' ' + iso(today(now)); }
function stripStamps(text) {
    [ICON.created, ICON.done].forEach(function (icon) {
        text = text.replace(new RegExp('\\s*' + esc(icon) + '\\s*' + DATE, 'g'), '');
    });
    return text;
}
function stampsOf(text) {
    var s = '';
    [ICON.created, ICON.done].forEach(function (icon) {
        var m = new RegExp(esc(icon) + '\\s*(' + DATE + ')').exec(text);
        if (m) s += ' ' + icon + ' ' + m[1];
    });
    return s;
}

// "@heute", "@morgen", "@fr", "@05.11.", "@täglich", "@15:00" (Schnell-Eingabe wie unter Windows)
var WD_INPUT = { so: 0, sonntag: 0, mo: 1, montag: 1, di: 2, dienstag: 2, mi: 3, mittwoch: 3,
    'do': 4, donnerstag: 4, fr: 5, freitag: 5, sa: 6, samstag: 6 };
function resolveDate(tok, now) {
    var base = today(now);
    tok = tok.toLowerCase();
    if (tok === 'heute') return base;
    if (tok === 'morgen') return addDays(base, 1);
    if (tok === 'übermorgen' || tok === 'uebermorgen') return addDays(base, 2);
    if (WD_INPUT[tok] !== undefined) return addDays(base, ((WD_INPUT[tok] - base.getDay()) % 7 + 7) % 7);
    var m = /^(\d\d?)\.(\d\d?)\.?(\d*)$/.exec(tok);
    if (m) {
        var year = m[3] ? +m[3] : base.getFullYear();
        if (year < 100) year += 2000;
        var t = dayOf(year, +m[2], +m[1]);
        if (!m[3] && t < base) t = dayOf(year + 1, +m[2], +m[1]);
        return t;
    }
    return null;
}
function convertDates(text, now) {
    text = text.replace(/@(\S+)/g, function (all, tok) {
        var rule = RULES[tok.toLowerCase()];
        if (rule) return ICON.repeat + ' ' + rule;
        var hm = /^(\d\d?):(\d\d)$/.exec(tok);
        if (hm) return ICON.time + ' ' + pad(+hm[1]) + ':' + hm[2];
        var t = resolveDate(tok, now);
        if (t) return ICON.due + ' ' + iso(t);
        return all;
    });
    if ((ruleOf(text) || timeOf(text)) && !dueOf(text)) text += ' ' + ICON.due + ' ' + iso(today(now));
    return text;
}
function datesToInput(text) {
    text = text.replace(new RegExp(esc(ICON.repeat) + '\\s*(\\S+)', 'g'), '@$1');
    text = text.replace(new RegExp(esc(ICON.time) + '\\s*(\\d\\d?:\\d\\d)', 'g'), '@$1');
    return text.replace(new RegExp(esc(ICON.due) + '\\s*(\\d{4})-(\\d{2})-(\\d{2})', 'g'), '@$3.$2.$1');
}

// Anzeige des Termins: { label, state: 'done' | 'over' | 'today' | 'due' }
function dueLabel(due, done, t, now) {
    var n = daysBetween(due, today(now));
    var label;
    if (n === 0) label = 'heute';
    else if (n === 1) label = 'morgen';
    else if (n === -1) label = 'gestern';
    else if (n > 1 && n < 7) label = WEEKDAYS[due.getDay()];
    else label = dotDate(due);
    if (t) label += ' ' + timeStr(t);
    if (done) return { label: label, state: 'done' };
    if (n < 0) return { label: label, state: 'over' };
    var d = now ? new Date(now) : new Date();
    if (n === 0 && t && d.getHours() * 60 + d.getMinutes() >= t.h * 60 + t.m) return { label: label, state: 'over' };
    if (n === 0) return { label: label, state: 'today' };
    return { label: label, state: 'due' };
}

// ---------- Anzeige-Text ----------
// [[Link]] und [[Link|Alias]] lesbar machen
function pretty(text) {
    return text.replace(/\[\[(.*?)\]\]/g, function (a, s) { var i = s.indexOf('|'); return i >= 0 ? s.substring(i + 1) : s; });
}
var URL_RE = /https?:\/\/[^\s)\]>"]+/g;
function shortLinks(text) {
    return text.replace(URL_RE, function (url) {
        var h = /^https?:\/\/([^\/:?#]+)/.exec(url);
        return (h ? h[1] : url).replace(/^www\./, '') + ' ↗';
    });
}
// Pfade (Linux "/…" oder "~/…", Windows "C:\…") auf den Datei-/Ordnernamen kuerzen
function isPath(note) { return /^(\/|~\/|[A-Za-z]:\\|\\\\)/.test(trim(note)); }
function shortPath(note) {
    var p = trim(note).replace(/[\\\/\s]+$/, '');
    var m = /([^\\\/]+)$/.exec(p);
    return m ? m[1] : p;
}
function noteText(note) { return isPath(note) ? shortPath(note) : shortLinks(pretty(note)); }
function taskText(text) { return trim(shortLinks(pretty(stripTags(stripDue(stripStamps(text)))))); }

// ---------- Tags (Obsidian-Schreibweise "#arbeit" in der Zeile) ----------
// Ein Tag beginnt nach Zeilenanfang oder Leerzeichen mit #, enthaelt keine Leer-/Satzzeichen und nicht nur Ziffern.
var TAG_RE = /(^|\s)#([^\s#.,;:!?()\[\]{}"'<>]+)/g;
function tagsOf(text) {
    var out = [], m;
    TAG_RE.lastIndex = 0;
    while ((m = TAG_RE.exec(text))) if (/\D/.test(m[2]) && out.indexOf(m[2]) < 0) out.push(m[2]);
    return out;
}
function stripTags(text) {
    return text.replace(TAG_RE, function (all, pre, name) { return /\D/.test(name) ? pre : all; }).replace(/\s{2,}/g, ' ');
}
// Tag-Name aus einer Eingabe: ohne #, Leerzeichen -> Bindestrich
function cleanTag(s) { return trim(String(s || '')).replace(/^#+/, '').replace(/\s+/g, '-').replace(/[#.,;:!?()\[\]{}"'<>]/g, ''); }
// Tag-Liste aus der Einstellung "arbeit:blau,privat:pink" -> [{ name, color }]
function parseTagConf(s) {
    var out = [];
    String(s || '').split(',').forEach(function (p) {
        var i = p.lastIndexOf(':'), name = cleanTag(i > 0 ? p.substring(0, i) : p), color = i > 0 ? trim(p.substring(i + 1)) : 'grau';
        if (name && /\D/.test(name)) out.push({ name: name, color: color || 'grau' });
    });
    return out;
}
function tagConfString(list) { return list.map(function (t) { return t.name + ':' + t.color; }).join(','); }

// erster Link einer Notiz: Webadresse, [[Obsidian-Notiz]] oder Pfad
function linkOf(note, vault, home) {
    var u = /https?:\/\/[^\s)\]>"]+/.exec(note);
    if (u) return u[0];
    var w = /\[\[([^\]|#]+)/.exec(note);
    if (w) return 'obsidian://open?vault=' + encodeURIComponent(vault || '') + '&file=' + encodeURIComponent(trim(w[1]));
    if (isPath(note)) {
        var p = trim(note);
        if (p.indexOf('~/') === 0 && home) p = home + p.substring(1);
        if (p.charAt(0) === '/') return 'file://' + encodeURI(p);
    }
    return null;
}

// ---------- Datei zerlegen ----------
function indentOf(line) { return /^(\s*)/.exec(line)[1].replace(/\t/g, '    ').length; }

function parse(content) {
    var bom = '';
    if (content.charCodeAt(0) === 0xFEFF) { bom = '\uFEFF'; content = content.substring(1); }
    var nl = content.indexOf('\r\n') >= 0 ? '\r\n' : '\n';
    var lines = content.split(/\r?\n/);
    var open = [], done = [], current = null;
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var m = CHECK.exec(line);
        var inside = current && !/^\s*$/.test(line) && indentOf(line) > current.indent;
        if (inside && m) {
            current.subs.push({ line: i, done: m[1] !== ' ', text: m[2] });
            current.last = i;
        } else if (inside) {
            current.notes.push(line.replace(/^\s+/, '').replace(/^[-*+] /, ''));
            current.noteLines.push(i);
            current.last = i;
        } else if (m) {
            current = { line: i, last: i, indent: indentOf(line), done: m[1] !== ' ', text: m[2], notes: [], noteLines: [], subs: [] };
            (current.done ? done : open).push(current);
        } else if (current && /^\s*$/.test(line)) {
            // Leerzeile: gehoert nur dazu, wenn danach noch eingerueckt weitergeht
        } else {
            current = null;
        }
    }
    // Reihenfolge = Reihenfolge in der Datei (eigene Reihenfolge per Ziehen); neue Punkte mit Datum
    // werden beim Anlegen nach Faelligkeit oben einsortiert (placeDated), erledigte stehen darunter
    open.concat(done).forEach(function (t) { t.dueTime = dueTimeOf(t.text); t.tags = tagsOf(t.text); });
    return { bom: bom, nl: nl, lines: lines, display: open.concat(done), openCount: open.length, doneCount: done.length };
}
// Faelligkeit als Zahl (Datum + Uhrzeit), ohne Datum Infinity
function dueTimeOf(text) {
    var d = dueOf(text), tm = timeOf(text);
    return d ? d.getTime() + (tm ? (tm.h - 12) * 3600000 + tm.m * 60000 : 0) : Infinity;
}
// model.display usw. nach Aenderungen an model.lines neu bestimmen
function reparse(model) {
    var p = parse(model.lines.join('\n'));
    model.display = p.display; model.openCount = p.openCount; model.doneCount = p.doneCount;
}

// Einmalig beim Umstieg auf die eigene Reihenfolge: offene Punkte in der Datei so ordnen, wie sie bisher
// angezeigt wurden (mit Datum nach Faelligkeit zuerst). Erledigte bleiben an ihrem Platz. true = geaendert
function sortOnce(model) {
    var all = model.display.slice().sort(function (a, b) { return a.line - b.line; });
    var lines = model.lines, changed = false, out = [], pos = 0;
    var k = 0;
    while (k < all.length) {
        // zusammenhaengender Lauf: zwischen den Punkten nur Leerzeilen
        var run = [all[k]];
        while (k + 1 < all.length && all[k + 1].line > all[k].last && lines.slice(all[k].last + 1, all[k + 1].line).every(function (l) { return /^\s*$/.test(l); })
               && all[k + 1].indent === all[k].indent) { k++; run.push(all[k]); }
        k++;
        var open = run.filter(function (t) { return !t.done; });
        var sorted = open.map(function (t, i) { return { t: t, i: i }; })
            .sort(function (a, b) { return a.t.dueTime !== b.t.dueTime ? (a.t.dueTime < b.t.dueTime ? -1 : 1) : a.i - b.i; })
            .map(function (x) { return x.t; });
        if (sorted.every(function (t, i) { return t === open[i]; })) continue;
        changed = true;
        // Zeilen vor dem Lauf uebernehmen, dann die Bloecke in neuer Reihenfolge (Luecken bleiben an ihrer Stelle)
        for (; pos < run[0].line; pos++) out.push(lines[pos]);
        var oi = 0;
        run.forEach(function (slot, si) {
            var t = slot.done ? slot : sorted[oi++];
            for (var x = t.line; x <= t.last; x++) out.push(lines[x]);
            var gapEnd = si + 1 < run.length ? run[si + 1].line : slot.last + 1;
            for (x = slot.last + 1; x < gapEnd; x++) out.push(lines[x]);
        });
        pos = run[run.length - 1].last + 1;
    }
    if (!changed) return false;
    for (; pos < lines.length; pos++) out.push(lines[pos]);
    model.lines = out;
    reparse(model);
    return true;
}

// Block (Zeilen) eines Punkts mit Datum nach Faelligkeit zwischen die anderen offenen Punkte mit Datum
// einsortieren: vor den ersten, der spaeter faellig ist, sonst hinter den letzten. Gibt es noch keinen
// Punkt mit Datum, kommt er ganz nach oben. Selbst verschobene Punkte ohne Datum bleiben so, wo sie sind.
function placeDated(model, block, dueTime) {
    var at = -1, lastDated = null, first = null;
    for (var i = 0; i < model.display.length; i++) {
        var t = model.display[i];
        if (t.done || t.indent > 0) continue;
        if (!first) first = t;
        if (t.dueTime === Infinity) continue;
        if (t.dueTime > dueTime) { at = t.line; break; }
        lastDated = t;
    }
    if (at < 0 && lastDated) at = lastDated.last + 1;
    if (at < 0 && first) at = first.line;
    if (at < 0) { insertAtEnd(model, block); return; }
    for (var k = 0; k < block.length; k++) model.lines.splice(at + k, 0, block[k]);
}

// Punkt "from" an die Stelle von "to" verschieben (beide offene Punkte). Nach unten: hinter "to", nach oben: davor.
function moveTask(model, from, to) {
    if (!from || !to || from === to) return false;
    var lines = model.lines, n = from.last - from.line + 1;
    var block = lines.splice(from.line, n);
    var at = to.line > from.line ? to.last - n + 1 : to.line;
    for (var k = 0; k < block.length; k++) lines.splice(at + k, 0, block[k]);
    reparse(model);
    return true;
}

function serialize(model) { return model.bom + model.lines.join(model.nl); }

// Punkt wiederfinden, auch wenn die Datei inzwischen geaendert wurde
function findTask(model, lineNo, orig) {
    var d = model.display, i;
    for (i = 0; i < d.length; i++) if (d[i].line === lineNo && model.lines[d[i].line] === orig) return d[i];
    for (i = 0; i < d.length; i++) if (model.lines[d[i].line] === orig) return d[i];
    return null;
}
function findChild(model, t, lineNo, orig) {
    if (model.lines[lineNo] === orig && lineNo > t.line && lineNo <= t.last) return lineNo;
    for (var k = t.line + 1; k <= t.last; k++) if (model.lines[k] === orig) return k;
    return -1;
}

// ---------- Aenderungen (veraendern model.lines) ----------
// abhaken setzt "✅ heute", zuruecknehmen entfernt es wieder
function flip(model, lineNo, now) {
    var line = model.lines[lineNo];
    var nowDone = line.indexOf('[ ]') >= 0;
    line = line.replace(/\[([ xX])\]/, nowDone ? '[x]' : '[ ]');
    line = line.replace(new RegExp('\\s*' + esc(ICON.done) + '\\s*' + DATE, 'g'), '');
    if (nowDone) line += stamp(ICON.done, now);
    model.lines[lineNo] = line;
}

// Zeilen hinter den letzten Todo-Punkt einfuegen, sonst ans Ende (vor eine leere Schlusszeile)
function insertAtEnd(model, block) {
    var pos = -1, lines = model.lines;
    model.display.forEach(function (t) { if (t.last > pos) pos = t.last; });
    if (pos < 0) {
        pos = lines.length - 1;
        while (pos >= 0 && lines[pos] === '') pos--;
    }
    for (var k = 0; k < block.length; k++) lines.splice(pos + 1 + k, 0, block[k]);
    if (lines[lines.length - 1] !== '') lines.push('');
}

// Formular -> Kopfzeile "Titel 🔁 regel ⏰ zeit 📅 datum"
function formText(form) {
    var text = trim(stripTags(form.title || ''));
    (form.tags || []).forEach(function (t) { t = cleanTag(t); if (t) text += ' #' + t; });
    if (form.rule) text += ' ' + ICON.repeat + ' ' + form.rule;
    if (form.time) text += ' ' + ICON.time + ' ' + form.time;
    if (form.date) text += ' ' + ICON.due + ' ' + form.date;
    return text;
}

// Formularwerte eines vorhandenen Punkts
function formOf(t) {
    var tm = timeOf(t.text), r = ruleOf(t.text);
    return { title: trim(stripTags(stripDue(stripStamps(t.text)))), date: dueIsoOf(t.text), time: timeStr(tm),
        rule: r ? normRule(r) : '', notes: t.notes.slice(), tags: tagsOf(t.text) };
}

// neuer Punkt aus dem Formular; gibt den neuen Text zurueck. Mit Datum: oben nach Faelligkeit einsortiert.
function addTask(model, form, now) {
    if (form.time || form.rule) { if (!form.date) form.date = iso(today(now)); }
    var text = formText(form) + stamp(ICON.created, now);
    var block = ['- [ ] ' + text];
    (form.notes || []).forEach(function (n) { n = trim(n); if (n) block.push('    - ' + n); });
    if (form.date) placeDated(model, block, dueTimeOf(text)); else insertAtEnd(model, block);
    return text;
}

// vorhandenen Punkt aus dem Formular neu zusammensetzen (Unteraufgaben bleiben).
// Hat sich der Termin geaendert, wird ein offener Punkt neu nach Faelligkeit einsortiert; sonst bleibt er, wo er ist.
function editTask(model, t, form) {
    if ((form.time || form.rule) && !form.date) form.date = iso(today());
    var lines = model.lines;
    var indent = /^(\s*)/.exec(lines[t.line])[1];
    var text = formText(form) + stampsOf(t.text);
    var block = [/^(\s*[-*+] \[[ xX]\])/.exec(lines[t.line])[1] + ' ' + text];
    t.subs.forEach(function (s) { block.push(lines[s.line]); });
    (form.notes || []).forEach(function (n) { n = trim(n); if (n) block.push(indent + '    - ' + n); });
    lines.splice(t.line, t.last - t.line + 1);
    var newDue = dueTimeOf(text);
    if (!t.done && indent === '' && form.date && newDue !== dueTimeOf(t.text)) {
        reparse(model);
        placeDated(model, block, newDue);
    } else {
        for (var k = 0; k < block.length; k++) lines.splice(t.line + k, 0, block[k]);
    }
    return text;
}

function removeTask(model, t) { model.lines.splice(t.line, t.last - t.line + 1); }

// neue Notiz / Unteraufgabe / Datei unter einem Punkt
function addChild(model, t, kind, text, now) {
    var indent = /^(\s*)/.exec(model.lines[t.line])[1] + '    ';
    if (kind === 'sub') {
        var pos = t.line;
        t.subs.forEach(function (s) { if (s.line > pos) pos = s.line; });
        model.lines.splice(pos + 1, 0, indent + '- [ ] ' + convertDates(text, now) + stamp(ICON.created, now));
    } else {
        model.lines.splice(t.last + 1, 0, indent + '- ' + text);
    }
}
// Notiz / Unteraufgabe aendern; leerer Text loescht die Zeile
function editChild(model, lineNo, text, now) {
    var orig = model.lines[lineNo];
    if (!trim(text)) { model.lines.splice(lineNo, 1); return; }
    var m = /^(\s*[-*+] \[[ xX]\] )(.*)$/.exec(orig);
    if (m) { model.lines[lineNo] = m[1] + convertDates(trim(text), now) + stampsOf(m[2]); return; }
    var p = /^(\s*[-*+] )/.exec(orig) || /^(\s*)/.exec(orig);
    model.lines[lineNo] = p[1] + trim(text);
}
function childInput(model, lineNo) {
    var orig = model.lines[lineNo];
    var m = CHECK.exec(orig);
    if (m) return datesToInput(stripStamps(m[2]));
    return orig.replace(/^\s+/, '').replace(/^[-*+] /, '');
}

// ---------- Archiv (Todo-Archiv.md) ----------
function blockOf(model, t, mark, now) {
    var lines = model.lines;
    var indent = /^(\s*)/.exec(lines[t.line])[1];
    var b = [];
    for (var k = t.line; k <= t.last; k++) {
        var line = lines[k];
        if (line.substring(0, indent.length) === indent) line = line.substring(indent.length);
        if (/\S/.test(line)) b.push(line);
    }
    if (mark === '-') b[0] = b[0].replace(/\[[ xX]\]/, '[-]') + stamp(ICON.cancel, now);
    else if (b[0].indexOf(ICON.done) < 0) b[0] += stamp(ICON.done, now);
    return b;
}

// Bloecke unter der Ueberschrift des aktuellen Monats anhaengen; gibt den neuen Archiv-Inhalt zurueck
function appendArchive(content, blocks, now) {
    var c = content;
    if (!c) {
        c = '---\ntags: [todo, archiv]\n---\n\n# Todo-Archiv\n\nErledigte und gelöschte Punkte aus [[Todo]], mit allen Notizen und Unteraufgaben. ' +
            '➕ = erstellt, ✅ = erledigt, ❌ = gelöscht (`- [-]`).\n';
    }
    var d = now ? new Date(now) : new Date();
    var heading = '## ' + MONTHS[d.getMonth()] + ' ' + d.getFullYear();
    var lastHeading = null, m, re = /\n(## [^\r\n]*)/g;
    while ((m = re.exec(c))) lastHeading = m[1];
    var out = c.replace(/[\r\n]*$/, '');
    if (lastHeading !== heading) out += '\n\n' + heading + '\n';
    blocks.forEach(function (b) { out += '\n' + b.join('\n'); });
    return out + '\n';
}

// abgehakte wiederkehrende Punkte: Kopie ins Archiv, Punkt wieder offen auf den naechsten Termin.
// Gibt { blocks, changes } zurueck oder null; erst Archiv schreiben, dann applyChanges().
function rollRecurring(model, now) {
    var blocks = [], changes = {}, lines = model.lines;
    var doneRe = new RegExp('\\s*' + esc(ICON.done) + '\\s*' + DATE, 'g');
    model.display.forEach(function (t) {
        var rule = t.done && ruleOf(t.text);
        if (!rule) return;
        var line = lines[t.line];
        var copy = line.substring(/^(\s*)/.exec(line)[1].length).replace(repPattern(), '');
        if (copy.indexOf(ICON.done) < 0) copy += stamp(ICON.done, now);
        blocks.push([copy]);
        var nxt = ICON.due + ' ' + iso(nextDate(dueOf(t.text), normRule(rule), now));
        line = line.replace(/\[[xX]\]/, '[ ]').replace(doneRe, '');
        if (dueOf(line)) line = line.replace(new RegExp(esc(ICON.due) + '\\s*' + DATE), nxt);
        else line += ' ' + nxt;
        changes[t.line] = line;
        t.subs.forEach(function (s) {
            if (s.done) changes[s.line] = lines[s.line].replace(/\[[xX]\]/, '[ ]').replace(doneRe, '');
        });
    });
    return blocks.length ? { blocks: blocks, changes: changes } : null;
}
function applyChanges(model, changes) { for (var k in changes) model.lines[+k] = changes[k]; }

// "Erledigte archivieren": { blocks, remove } oder null
function cleanup(model, now) {
    var remove = {}, blocks = [];
    model.display.forEach(function (t) {
        if (t.done) {
            blocks.push(blockOf(model, t, 'x', now));
            for (var k = t.line; k <= t.last; k++) remove[k] = true;
        } else {
            var parent = trim(stripDue(stripStamps(t.text)));
            t.subs.forEach(function (s) {
                if (!s.done) return;
                var line = '- [x] ' + s.text;
                if (s.text.indexOf(ICON.done) < 0) line += stamp(ICON.done, now);
                blocks.push([line + ' · Unteraufgabe von „' + parent + '“']);
                remove[s.line] = true;
            });
        }
    });
    return blocks.length ? { blocks: blocks, remove: remove } : null;
}
function removeLines(model, remove) { model.lines = model.lines.filter(function (l, n) { return !remove[n]; }); }

// ---------- Erinnerungen ----------
// state = { notified: {}, snoozed: {} }; gibt faellige Punkte [{ key, title, time }] zurueck
function dueReminders(model, state, now) {
    var out = [], t0 = today(now), d = now ? new Date(now) : new Date();
    var mins = d.getHours() * 60 + d.getMinutes();
    model.display.forEach(function (t) {
        var tm = timeOf(t.text), day = dueOf(t.text);
        if (t.done || !tm || !day) return;
        var again = state.snoozed[t.text] && d.getTime() >= state.snoozed[t.text];
        if (state.notified[t.text] && !again) return;
        if (day < t0 || (sameDay(day, t0) && mins >= tm.h * 60 + tm.m)) {
            state.notified[t.text] = true;
            delete state.snoozed[t.text];
            out.push({ key: t.text, title: trim(pretty(stripDue(stripStamps(t.text)))), time: timeStr(tm) });
        }
    });
    return out;
}

// ---------- Formular: Zusammenfassung ----------
function summary(form, now) {
    if (!form.date && !form.time && !form.rule) return 'Ohne Termin – steht einfach auf der Liste.';
    var day = fromIso(form.date) || today(now), s;
    var r = form.rule;
    if (r === 'täglich') s = 'Täglich';
    else if (r === 'werktags') s = 'Werktags (Mo–Fr)';
    else if (r === 'wöchentlich') s = 'Jeden ' + WEEKDAY_NAMES[day.getDay()];
    else if (r === 'monatlich') s = 'Jeden Monat am ' + day.getDate() + '.';
    else if (r === 'jährlich') s = 'Jedes Jahr am ' + day.getDate() + '. ' + MONTHS[day.getMonth()];
    else if (r) {
        var a = /^alle (\d+) (\S+)$/.exec(r);
        if (a) s = 'Alle ' + a[1] + ' ' + a[2];
        else {
            var names = r.match(/[A-Za-z]{2}/g) || [];
            s = 'Jeden ' + (names.length > 1 ? names.slice(0, -1).join(', ') + ' und ' : '') + names[names.length - 1];
        }
    } else {
        var n = daysBetween(day, today(now));
        if (n === 0) s = 'Fällig heute';
        else if (n === 1) s = 'Fällig morgen';
        else s = 'Fällig ' + WEEKDAY_NAMES[day.getDay()] + ', ' + day.getDate() + '. ' + MONTHS[day.getMonth()] + ' ' + day.getFullYear();
    }
    if (r) s += ', ab ' + (sameDay(day, today(now)) ? 'heute' : dotDate(day));
    if (form.time) s += ' um ' + form.time + ' – mit Erinnerung';
    return s + '.';
}

// ---------- UTF-8 und Base64 (Dateien werden per Shell als Base64 gelesen/geschrieben) ----------
var B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function utf8Encode(s) {
    var out = [];
    for (var i = 0; i < s.length; i++) {
        var c = s.charCodeAt(i);
        if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
            var c2 = s.charCodeAt(i + 1);
            if (c2 >= 0xDC00 && c2 <= 0xDFFF) { c = 0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00); i++; }
        }
        if (c < 0x80) out.push(c);
        else if (c < 0x800) out.push(0xC0 | (c >> 6), 0x80 | (c & 63));
        else if (c < 0x10000) out.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
        else out.push(0xF0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    }
    return out;
}
function utf8Decode(b) {
    var s = '', i = 0;
    while (i < b.length) {
        var c = b[i++], cp;
        if (c < 0x80) cp = c;
        else if (c < 0xE0) cp = ((c & 31) << 6) | (b[i++] & 63);
        else if (c < 0xF0) { cp = ((c & 15) << 12) | ((b[i] & 63) << 6) | (b[i + 1] & 63); i += 2; }
        else { cp = ((c & 7) << 18) | ((b[i] & 63) << 12) | ((b[i + 1] & 63) << 6) | (b[i + 2] & 63); i += 3; }
        if (cp >= 0x10000) { cp -= 0x10000; s += String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 1023)); }
        else s += String.fromCharCode(cp);
    }
    return s;
}
function toBase64(str) {
    var b = utf8Encode(str), out = '';
    for (var i = 0; i < b.length; i += 3) {
        var n = (b[i] << 16) | ((b[i + 1] || 0) << 8) | (b[i + 2] || 0);
        out += B64.charAt(n >> 18) + B64.charAt((n >> 12) & 63) +
            (i + 1 < b.length ? B64.charAt((n >> 6) & 63) : '=') + (i + 2 < b.length ? B64.charAt(n & 63) : '=');
    }
    return out;
}
function fromBase64(s) {
    s = s.replace(/[^A-Za-z0-9+\/]/g, '');
    var b = [];
    for (var i = 0; i < s.length; i += 4) {
        var n = (B64.indexOf(s.charAt(i)) << 18) | (B64.indexOf(s.charAt(i + 1)) << 12) |
            ((B64.indexOf(s.charAt(i + 2)) & 63) << 6) | (B64.indexOf(s.charAt(i + 3)) & 63);
        b.push((n >> 16) & 255);
        if (i + 2 < s.length) b.push((n >> 8) & 255);
        if (i + 3 < s.length) b.push(n & 255);
    }
    return utf8Decode(b);
}

// Text fuer die Shell in einfache Anfuehrungszeichen setzen
function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
