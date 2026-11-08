// Tests fuer den JS-Kern (linux/kde/package/contents/code/todo.js) mit Node:
//   node linux/tests/core-test.js [pfad/zu/Todo.md]
// Die Datei wird nur gelesen, nie geschrieben.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const src = fs.readFileSync(path.join(__dirname, '../kde/package/contents/code/todo.js'), 'utf8').replace(/^\.pragma library/, '');
const Core = {};
vm.createContext(Core);
vm.runInContext(src, Core);

let failed = 0;
function eq(name, got, want) {
    const ok = JSON.stringify(got) === JSON.stringify(want);
    if (!ok) failed++;
    console.log((ok ? 'ok   ' : 'FAIL ') + name + (ok ? '' : `\n     erwartet: ${JSON.stringify(want)}\n     bekommen: ${JSON.stringify(got)}`));
}

const NOW = new Date(2026, 10, 1, 14, 30); // So, 01.11.2026 14:30

// Datum / Regeln
eq('nextDate taeglich', Core.iso(Core.nextDate(Core.fromIso('2026-11-01'), 'täglich', NOW)), '2026-11-02');
eq('nextDate werktags (Fr->Mo)', Core.iso(Core.nextDate(Core.fromIso('2026-11-06'), 'werktags', NOW)), '2026-11-09');
eq('nextDate Mo,Mi,Fr ab So', Core.iso(Core.nextDate(Core.fromIso('2026-11-01'), 'Mo,Mi,Fr', NOW)), '2026-11-02');
eq('nextDate alle 2 Wochen', Core.iso(Core.nextDate(Core.fromIso('2026-11-01'), 'alle 2 Wochen', NOW)), '2026-11-15');
eq('nextDate monatlich', Core.iso(Core.nextDate(Core.fromIso('2026-10-15'), 'monatlich', NOW)), '2026-11-15');
eq('nextDate jaehrlich alt -> naechstes in Zukunft', Core.iso(Core.nextDate(Core.fromIso('2020-03-01'), 'jährlich', NOW)), '2027-03-01');
eq('ruleOf alle 2 Wochen', Core.ruleOf('Müll 🔁 alle 2 Wochen ⏰ 07:00 📅 2026-11-03'), 'alle 2 Wochen');
eq('timeOf', Core.timeOf('x ⏰ 7:05'), { h: 7, m: 5 });
eq('stripDue', Core.stripDue('Müll 🔁 alle 2 Wochen ⏰ 07:00 📅 2026-11-03'), 'Müll');
eq('taskText', Core.taskText('Lesen [[Buch|Das Buch]] https://www.example.com/a ➕ 2026-11-01'), 'Lesen Das Buch example.com ↗');
eq('convertDates', Core.convertDates('Steuer @fr @15:00', NOW), 'Steuer ⏰ 15:00 📅 2026-11-06'.replace('⏰ 15:00 📅 2026-11-06', '📅 2026-11-06 ⏰ 15:00'));
eq('dueLabel heute vorbei', Core.dueLabel(Core.fromIso('2026-11-01'), false, { h: 9, m: 0 }, NOW), { label: 'heute 09:00', state: 'over' });
eq('dueLabel morgen', Core.dueLabel(Core.fromIso('2026-11-02'), false, null, NOW), { label: 'morgen', state: 'due' });
eq('summary', Core.summary({ date: '2026-11-04', time: '15:00', rule: 'wöchentlich' }, NOW), 'Jeden Mittwoch, ab 04.11. um 15:00 – mit Erinnerung.');

// Base64/UTF-8 Rundreise mit Emojis und Umlauten
const sample = '- [ ] Grüße 🔁 täglich 📅 2026-11-01 ✅ ➕\r\n';
eq('base64 Rundreise', Core.fromBase64(Core.toBase64(sample)), sample);
eq('base64 wie Node', Core.toBase64(sample), Buffer.from(sample, 'utf8').toString('base64'));

// Parse / Aendern / Speichern
const file = '# Todo\n\n- [ ] B ohne Datum ➕ 2026-10-01\n- [ ] A morgen 📅 2026-11-02\n    - [ ] Teil 1\n    - Notiz https://x.de\n- [x] erledigt ✅ 2026-10-30\n- [x] Gießen 🔁 täglich 📅 2026-10-31 ✅ 2026-11-01\n';
let m = Core.parse(file);
eq('Sortierung (seit 1.3.0: Reihenfolge der Datei, erledigte unten)', m.display.map(t => Core.taskText(t.text)), ['B ohne Datum', 'A morgen', 'erledigt', 'Gießen']);
eq('Zaehler', [m.openCount, m.doneCount], [2, 2]);
eq('Unteraufgaben/Notizen', [m.display[1].subs.length, m.display[1].notes], [1, ['Notiz https://x.de']]);
eq('Rundreise unveraendert', Core.serialize(m), file);

const roll = Core.rollRecurring(m, NOW);
eq('Wiederholung Archiv-Kopie', roll.blocks, [['- [x] Gießen 📅 2026-10-31 ✅ 2026-11-01']]);
Core.applyChanges(m, roll.changes);
eq('Wiederholung neu offen (wie todo.lua: naechster Termin ab heute)', m.lines[7], '- [ ] Gießen 🔁 täglich 📅 2026-11-01');

m = Core.parse(file);
Core.flip(m, m.display[0].line, NOW);
eq('abhaken', m.lines[2], '- [x] B ohne Datum ➕ 2026-10-01 ✅ 2026-11-01');
m = Core.parse(Core.serialize(m));
const cl = Core.cleanup(m, NOW);
eq('Archivieren Bloecke', cl.blocks.length, 3);
Core.removeLines(m, cl.remove);
eq('nach Archivieren', Core.serialize(m), '# Todo\n\n- [ ] A morgen 📅 2026-11-02\n    - [ ] Teil 1\n    - Notiz https://x.de\n');

m = Core.parse(file);
Core.addTask(m, { title: 'Neu', date: '', time: '15:00', rule: '', notes: ['n1'] }, NOW);
eq('neuer Punkt mit Datum: nach Faelligkeit einsortiert', m.lines.slice(3, 5), ['- [ ] Neu ⏰ 15:00 📅 2026-11-01 ➕ 2026-11-01', '    - n1']);

m = Core.parse(file);
const t = m.display[1];
Core.editTask(m, t, { title: 'A geaendert', date: '2026-11-05', time: '', rule: 'Mo,Mi', notes: ['neu'] });
eq('bearbeiten behaelt Unteraufgaben', m.lines.slice(2, 5), ['- [ ] A geaendert 🔁 Mo,Mi 📅 2026-11-05', '    - [ ] Teil 1', '    - neu']);

eq('Archiv neu', Core.appendArchive('', [['- [x] a']], NOW).split('\n').slice(-4), ['## November 2026', '', '- [x] a', '']);

const st = { notified: {}, snoozed: {} };
m = Core.parse('- [ ] Anruf ⏰ 14:00 📅 2026-11-01\n- [ ] Später ⏰ 18:00 📅 2026-11-01\n');
eq('Erinnerung faellig', Core.dueReminders(m, st, NOW).map(r => r.title), ['Anruf']);
eq('Erinnerung nur einmal', Core.dueReminders(m, st, NOW).length, 0);

eq('linkOf Pfad', Core.linkOf('/home/user/Dokumente/a b.pdf'), 'file:///home/user/Dokumente/a%20b.pdf');
eq('linkOf Wiki', Core.linkOf('siehe [[Rainmeter Todo-Skin]]', 'Vault'), 'obsidian://open?vault=Vault&file=Rainmeter%20Todo-Skin');

// Google-Kennung "%%tb:<id>%%" (Abgleich): unsichtbar, bleibt erhalten, kommt nicht ins Archiv
const gf = '- [ ] Müll 🔁 täglich %%tb:abc_1-2%%\n- [ ] Post #arbeit ➕ 2026-10-01 %%tb:X9%%\n    - [ ] Marke %%tb:S1%%\n    - Notiz\n- [x] Alt ✅ 2026-10-31 %%tb:D1%%\n';
let gm = Core.parse(gf);
eq('Kennung unsichtbar', gm.display.map(t => Core.taskText(t.text)), ['Müll', 'Post', 'Alt']);
eq('Regel direkt vor der Kennung', Core.ruleOf(gm.display[0].text), 'täglich');
eq('Formular ohne Kennung', [Core.formOf(gm.display[0]).title, Core.formOf(gm.display[0]).rule], ['Müll', 'täglich']);
eq('Unteraufgabe im Eingabefeld ohne Kennung', Core.childInput(gm, gm.display[1].subs[0].line), 'Marke');
Core.flip(gm, gm.display[1].line, NOW);
eq('abhaken behaelt Kennung', gm.lines[1], '- [x] Post #arbeit ➕ 2026-10-01 %%tb:X9%% ✅ 2026-11-01');
gm = Core.parse(gf);
Core.editTask(gm, gm.display[1], { title: 'Post neu', date: '', time: '', rule: '', notes: ['Notiz'], tags: ['arbeit'] });
eq('bearbeiten behaelt Kennung', gm.lines[1], '- [ ] Post neu #arbeit ➕ 2026-10-01 %%tb:X9%%');
gm = Core.parse(gf);
Core.editChild(gm, gm.display[1].subs[0].line, 'Marke kaufen', NOW);
eq('Unteraufgabe bearbeiten behaelt Kennung', gm.lines[2], '    - [ ] Marke kaufen %%tb:S1%%');
gm = Core.parse(gf);
eq('Zeile wiederfinden, auch wenn die Kennung dazugekommen ist', !!Core.findTask(gm, 0, '- [ ] Müll 🔁 täglich'), true);
eq('Archiv ohne Kennung', Core.blockOf(gm, gm.display[1], 'x', NOW), ['- [ ] Post #arbeit ➕ 2026-10-01 ✅ 2026-11-01', '    - [ ] Marke', '    - Notiz']);
eq('Erledigte archivieren ohne Kennung', Core.cleanup(gm, NOW).blocks, [['- [x] Alt ✅ 2026-10-31']]);
const rg = Core.parse('- [x] Müll 🔁 täglich 📅 2026-10-31 ✅ 2026-11-01 %%tb:abc%%\n');
const rr = Core.rollRecurring(rg, NOW);
eq('Wiederholung: Archiv ohne Kennung', rr.blocks, [['- [x] Müll 📅 2026-10-31 ✅ 2026-11-01']]);
Core.applyChanges(rg, rr.changes);
eq('Wiederholung: Zeile behaelt Kennung', rg.lines[0], '- [ ] Müll 🔁 täglich 📅 2026-11-01 %%tb:abc%%');
const rs = { notified: {}, snoozed: {} };
Core.dueReminders(Core.parse('- [ ] Anruf ⏰ 14:00 📅 2026-11-01\n'), rs, NOW);
eq('Erinnerung nicht doppelt, wenn die Kennung dazukommt', Core.dueReminders(Core.parse('- [ ] Anruf ⏰ 14:00 📅 2026-11-01 %%tb:abc%%\n'), rs, NOW).length, 0);

// echte Datei (nur lesen)
const real = process.argv[2];
if (real && fs.existsSync(real)) {
    const c = fs.readFileSync(real, 'utf8');
    const rm = Core.parse(c);
    eq('echte Todo.md: Rundreise unveraendert', Core.serialize(rm) === c, true);
    console.log(`     ${rm.openCount} offen, ${rm.doneCount} erledigt:`);
    rm.display.forEach(t => {
        const d = Core.dueOf(t.text);
        const lab = d ? Core.dueLabel(d, t.done, Core.timeOf(t.text)).label : '';
        console.log(`       [${t.done ? 'x' : ' '}] ${Core.taskText(t.text)}${lab ? '  (' + lab + ')' : ''}${t.subs.length ? '  ' + t.subs.filter(s => s.done).length + '/' + t.subs.length : ''}${t.notes.length ? '  📎' + t.notes.length : ''}`);
    });
}
console.log(failed ? `\n${failed} Test(s) fehlgeschlagen` : '\nAlle Tests bestanden');
process.exit(failed ? 1 : 0);
