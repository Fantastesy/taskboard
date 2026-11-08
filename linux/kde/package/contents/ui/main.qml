// Task Board (frueher Obsidian Todo) - KDE-Plasma-Widget.
// Liest/schreibt die Todo.md ueber kleine Shell-Befehle (cat/base64/mv), weil QML selbst keine Dateien schreiben kann.
// Pfade kommen aus ~/.config/taskboard/config (schreibt das Setup).
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import "../code/todo.js" as Core
import "../code/palette.js" as P

PlasmoidItem {
    id: root

    // ---------- Einstellungen ----------
    property string todoFile: ""
    property string archiveFile: ""
    property string vaultName: ""
    property string home: ""
    property bool configMissing: false
    property bool hasNotifySend: false
    property string version: ""
    // Tastenkuerzel fuer "neuer Punkt" (Einstellungen); "" = aus
    readonly property string hotkey: Plasmoid.globalShortcut ? String(Plasmoid.globalShortcut) : ""
    readonly property string mode: Plasmoid.configuration.mode

    // ---------- Zustand ----------
    property var model: null          // Ergebnis von Core.parse
    property string lastContent: ""
    property bool fileMissing: false
    property var rows: []              // aufbereitete Punkte fuer die Ansicht
    property var openNotes: ({})       // Text eines Punkts -> Notizen aufgeklappt
    property bool collapsed: false
    property int maxItems: 15
    property var reminderState: ({ notified: {}, snoozed: {} })
    property bool busy: false
    property var queue: []
    // waehrend in der Liste getippt wird, nicht neu aufbauen (sonst verschwindet das Eingabefeld)
    property bool editing: false
    property bool pendingRebuild: false
    onEditingChanged: if (!editing && pendingRebuild) rebuildRows()

    Plasmoid.icon: "checkbox"
    // eigener dunkler, durchsichtiger Hintergrund wie unter Windows statt Plasma-Rahmen
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    toolTipMainText: "Task Board"
    toolTipSubText: model ? model.openCount + " offen" : ""
    // klein, damit die Liste auf dem Desktop nie zum Symbol wird (der Halter ist nur so hoch wie die Liste)
    switchWidth: inPanel ? Kirigami.Units.gridUnit * 8 : 0
    switchHeight: inPanel ? Kirigami.Units.gridUnit * 2 : 0
    // Desktop: ganze Liste. Leiste: schmaler Streifen; die Liste klappt als Popup daneben auf.
    // (Die ganze Liste IN einer Leiste geht nicht: KDE begrenzt die Leistenbreite, und das Umschalten
    //  zwischen Symbol und Liste schaukelte sich mit der Leistengroesse zu einer Dauerschleife auf.)
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar ? fullRepresentation : compactRepresentation
    // Desktop-Liste bei "Beides": blendet aus, solange das Panel am Rand offen ist
    readonly property real deskOpacity: mode === "both" && side.shown ? 0 : 1
    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Vertical || Plasmoid.formFactor === PlasmaCore.Types.Horizontal

    // ---------- Einblenden beim Anmelden / Aufwachen / Entsperren ----------
    // In der Seitenleiste klappt die Liste auf (die Leiste faehrt dafuer heraus):
    // 10 Sekunden pro offenem Punkt, hoechstens 2 Minuten.
    property bool revealed: false
    property bool startupRevealDone: false
    // per Maus/Einblenden geoeffnet -> klappt von selbst wieder zu, sobald die Maus die Liste verlaesst
    property bool autoOpened: false
    // Nur aufklappen - KDE faehrt die (automatisch ausgeblendete) Leiste dafuer selbst heraus.
    // Den Status NICHT selbst auf "Aufmerksamkeit" setzen: KDE merkt sich beim Aufklappen den Status
    // und stellt ihn beim Zuklappen wieder her - dann bliebe die Leiste dauerhaft sichtbar.
    function reveal() {
        var per = Plasmoid.configuration.revealPerItem;
        if (!model || model.openCount === 0 || per <= 0) return;
        var secs = Math.min(120, per * model.openCount);
        if (inPanel) {
            // Widget steckt (von Hand) in einer Leiste: Popup aufklappen
            revealTimer.interval = secs * 1000;
            revealed = true;
            autoOpened = true;
            root.expanded = true;
            revealTimer.restart();
            return;
        }
        if (mode === "desktop") return;
        revealed = true;
        revealTimer.interval = secs * 1000;
        revealTimer.restart();
        side.reveal(secs);
    }
    function hideReveal() {
        revealTimer.stop();
        revealed = false;
        if (autoOpened) { root.expanded = false; autoOpened = false; }
        side.hide();
    }
    // Maus im Panel der Seitenleiste bzw. im aufgeklappten Popup
    function hoverLeft() { if (inPanel) { if (autoOpened && !revealed) closeTimer.restart(); } else side.leave(); }
    function hoverEntered() { closeTimer.stop(); side.enter(); }
    Timer { id: closeTimer; interval: 900; onTriggered: { if (root.autoOpened) { root.expanded = false; root.autoOpened = false; } } }
    onExpandedChanged: if (!root.expanded) root.autoOpened = false
    Timer { id: revealTimer; onTriggered: { root.revealed = false; if (root.autoOpened) { root.expanded = false; root.autoOpened = false; } } }

    // Aufwachen: waehrend Standby laufen keine Timer -> grosse Luecke zwischen zwei Durchlaeufen
    property double lastTick: Date.now()
    property string lastLocked: ""
    Timer {
        interval: 5000; running: true; repeat: true
        onTriggered: {
            var now = Date.now();
            if (now - root.lastTick > 60000) root.reveal();
            root.lastTick = now;
            // Entsperren: LockedHint der Sitzung wechselt von yes auf no
            root.run('loginctl show-session "${XDG_SESSION_ID:-self}" -p LockedHint --value 2>/dev/null', function (code, out) {
                var locked = out.trim();
                if (root.lastLocked === "yes" && locked === "no") root.reveal();
                if (locked) root.lastLocked = locked;
            });
        }
    }

    // ---------- Rechtsklick-Menue ----------
    function runSetup(args) {
        // abgekoppelt starten: beim Umschalten wird dieses Widget selbst entfernt
        run('s="${XDG_DATA_HOME:-$HOME/.local/share}/taskboard/setup.sh"; [ -f "$s" ] && setsid bash "$s" ' + args + ' >/dev/null 2>&1 < /dev/null &');
    }
    Plasmoid.contextualActions: [
        PlasmaCore.Action { text: "Neuer Eintrag"; icon.name: "list-add"; onTriggered: root.openForm(null) },
        PlasmaCore.Action { text: root.obsidianOn ? "In Obsidian öffnen" : "Google Tasks öffnen"; icon.name: "document-open"; onTriggered: root.openInObsidian() },
        PlasmaCore.Action { text: "Einstellungen …"; icon.name: "configure"; onTriggered: root.openSettings() },
        PlasmaCore.Action { isSeparator: true },
        PlasmaCore.Action { text: "Task Board entfernen …"; icon.name: "edit-delete"; onTriggered: root.runSetup("--uninstall") }
    ]

    // Streifen in der Leiste: fuellt die ganze Leistenlaenge, damit die Maus beim Herausfahren
    // sofort darueber ist; Drueberfahren klappt die Liste auf, Klick klappt auf/zu.
    compactRepresentation: MouseArea {
        hoverEnabled: true
        Layout.fillHeight: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        Layout.fillWidth: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small
        onEntered: { root.hoverEntered(); if (!root.expanded) { root.autoOpened = true; root.expanded = true; } }
        onExited: root.hoverLeft()
        onClicked: { root.autoOpened = false; root.expanded = !root.expanded; }
        Kirigami.Icon {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: Kirigami.Units.smallSpacing
            width: Math.min(parent.width, Kirigami.Units.iconSizes.medium)
            height: width
            source: "checkbox"
        }
        PC3.Label {
            visible: root.model && root.model.openCount > 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 2
            text: root.model ? root.model.openCount : ""
            font.bold: true
        }
    }

    // Desktop: die Liste (bei "Seitenleiste" unsichtbar - dann gibt es nur das Panel am Rand)
    fullRepresentation: Item {
        Layout.preferredWidth: deskView.implicitWidth
        Layout.preferredHeight: deskView.implicitHeight
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 4
        TodoView {
            id: deskView
            app: root
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.min(implicitHeight, parent.height)
            visible: root.mode !== "sidebar" || root.inPanel
            opacity: root.inPanel ? 1 : root.deskOpacity
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
        }
    }

    FormDialog {
        id: form
        app: root
    }
    SidePanel {
        id: side
        app: root
    }
    SettingsDialog {
        id: settings
        app: root
    }
    function openSettings() { settings.open(); }
    function setHotkey(k) { Plasmoid.globalShortcut = k; }
    // Todo-Datei wechseln: Vault = naechster Ordner mit .obsidian darueber; Dateien anlegen; config umschreiben
    function chooseTodo(path) {
        if (!path) return;
        if (!/\.md$/i.test(path)) path += ".md";
        run('f=' + q(path) + '; d=$(dirname "$f"); a="$d/Todo-Archiv.md"; v="$d"; p="$d"; '
            + 'while [ "$p" != "/" ] && [ -n "$p" ]; do [ -d "$p/.obsidian" ] && { v="$p"; break; }; p=$(dirname "$p"); done; '
            + 'mkdir -p "$d"; [ -f "$f" ] || printf "# Todo\\n\\n- [ ] Mein erster Eintrag\\n" > "$f"; '
            + '[ -f "$a" ] || printf "# Todo-Archiv\\n" > "$a"; '
            + 'c="${XDG_CONFIG_HOME:-$HOME/.config}/taskboard/config"; mkdir -p "$(dirname "$c")"; touch "$c"; '
            + 'grep -v -E "^(VAULT|VAULT_NAME|TODO_FILE|ARCHIVE_FILE)=" "$c" > "$c.tmp"; '
            + 'printf "VAULT=%s\\nVAULT_NAME=%s\\nTODO_FILE=%s\\nARCHIVE_FILE=%s\\n" "$v" "$(basename "$v")" "$f" "$a" >> "$c.tmp" && mv -f "$c.tmp" "$c"; '
            // eine Datei gewaehlt = in Obsidian speichern (war "nur Google" eingestellt, ist das jetzt vorbei)
            + 'g="${XDG_CONFIG_HOME:-$HOME/.config}/taskboard/google"; [ -f "$g" ] && sed -i "s/^OBSIDIAN_ON=.*/OBSIDIAN_ON=1/" "$g"; true',
            function () { googleHint = ""; lastContent = ""; model = null; loadConfig(); });
    }

    // Tastenkuerzel des Widgets (Setup traegt Meta+Shift+T ein) -> neuer Punkt
    Connections {
        target: Plasmoid
        function onActivated() { root.openForm(null) }
    }

    // ---------- Shell-Befehle ----------
    P5Support.DataSource {
        id: exec
        engine: "executable"
        property var callbacks: ({})
        onNewData: (sourceName, data) => {
            var cb = callbacks[sourceName];
            delete callbacks[sourceName];
            disconnectSource(sourceName);
            if (cb) cb(data["exit code"], data["stdout"] || "", data["stderr"] || "");
        }
    }
    property int execCounter: 0
    function run(cmd, cb) {
        execCounter++;
        var key = cmd + " # " + execCounter;   // jede Quelle braucht einen eigenen Namen
        exec.callbacks[key] = cb || null;
        exec.connectSource(key);
    }
    function q(s) { return Core.shq(s); }

    function readFile(path, cb) {
        run('f=' + q(path) + '; if [ -f "$f" ]; then base64 -w0 "$f"; else echo __MISSING__; fi', function (code, out) {
            if (code !== 0) return cb(null);
            out = out.trim();
            cb(out === "__MISSING__" ? null : Core.fromBase64(out));
        });
    }
    function writeFile(path, content, cb) {
        var tmp = path + ".taskboard.tmp";
        run('printf %s ' + q(Core.toBase64(content)) + ' | base64 -d > ' + q(tmp) + ' && mv -f ' + q(tmp) + ' ' + q(path),
            function (code) { cb(code === 0); });
    }

    // ---------- Einstellungen laden ----------
    function loadConfig() {
        run('printf "HOME=%s\\n" "$HOME"; cat "${XDG_CONFIG_HOME:-$HOME/.config}/taskboard/config" 2>/dev/null; command -v notify-send >/dev/null && echo NOTIFY=1; command -v python3 >/dev/null && echo PYTHON=1; printf "TEST=%s\\n" "$TASKBOARD_TEST"; [ -f /tmp/taskboard-test.enable ] && echo TESTCMD=1; printf "APPVERSION=%s\\n" "$(head -n1 "${XDG_DATA_HOME:-$HOME/.local/share}/taskboard/version.txt" 2>/dev/null)"',
            function (code, out) {
                var cfg = {};
                out.split("\n").forEach(function (l) {
                    var i = l.indexOf("=");
                    if (i > 0) cfg[l.substring(0, i).trim()] = l.substring(i + 1).trim();
                });
                home = cfg.HOME || "";
                todoFile = cfg.TODO_FILE || "";
                archiveFile = cfg.ARCHIVE_FILE || "";
                vaultName = cfg.VAULT_NAME || "";
                hasNotifySend = cfg.NOTIFY === "1";
                hasPython = cfg.PYTHON === "1";
                version = cfg.APPVERSION || "";
                configMissing = todoFile === "";
                refresh();
                pollGoogle(function () { if (!root.syncRunning) root.runSync(); });
                // nur fuer automatische Tests: TASKBOARD_TEST=new|edit oeffnet das Formular
                if (cfg.TEST) testTimer.mode = cfg.TEST;
                testCmds = cfg.TESTCMD === "1";
            });
    }

    // ---------- Lesen / Anzeigen ----------
    function refresh() {
        if (configMissing || busy || todoFile === "") return;
        readFile(todoFile, function (c) {
            if (busy) return;
            if (c === null) { fileMissing = true; return; }
            fileMissing = false;
            if (c === lastContent && model) return;
            setContent(c);
            // abgehakte wiederkehrende Punkte (auch aus Obsidian) weiterschieben
            if (Core.rollRecurring(model, new Date())) enqueue(function (m) { return rollOp(m); });
        });
    }

    function setContent(c) {
        var changed = c !== lastContent;
        lastContent = c;
        model = Core.parse(c);
        rebuildRows();
        if (googleOn && changed && c !== lastSyncedContent) syncSoon.restart();
        // nach der Anmeldung einmal einblenden
        if (!startupRevealDone) { startupRevealDone = true; reveal(); }
        if (!Plasmoid.configuration.manualOrder && !migrationQueued) { migrationQueued = true; migrateOrder(); }
    }
    property bool migrationQueued: false

    function dueInfo(text, done) {
        var d = Core.dueOf(text);
        if (!d) return { label: "", state: "" };
        return Core.dueLabel(d, done, Core.timeOf(text));
    }

    function rebuildRows() {
        if (editing) { pendingRebuild = true; return; }
        pendingRebuild = false;
        if (!model) { rows = []; return; }
        var out = [];
        var shown = model.display.slice(0, maxItems);
        shown.forEach(function (t) {
            var di = dueInfo(t.text, t.done);
            var subsDone = 0;
            var subs = t.subs.map(function (s) {
                if (s.done) subsDone++;
                var sd = dueInfo(s.text, s.done);
                return { line: s.line, orig: model.lines[s.line], done: s.done, title: Core.taskText(s.text),
                         dueLabel: sd.label, dueState: sd.state };
            });
            var notes = t.notes.map(function (n, k) {
                return { line: t.noteLines[k], orig: model.lines[t.noteLines[k]], text: Core.noteText(n),
                         link: Core.linkOf(n, vaultName, home) || "" };
            });
            var noteKey = Core.stripMarker(t.text);    // ohne Google-Kennung: bleibt aufgeklappt, wenn der Abgleich sie anhaengt
            out.push({ key: noteKey, line: t.line, orig: model.lines[t.line], done: t.done, title: Core.taskText(t.text),
                       dueLabel: di.label, dueState: di.state, repeat: !!Core.ruleOf(t.text),
                       tags: t.tags.map(function (n) { return { name: n, color: tagColor(n) }; }),
                       subs: subs, subsDone: subsDone, notes: notes, open: !!openNotes[noteKey] });
        });
        rows = out;
    }

    // ---------- Tags ----------
    // [{ name, color }] aus den Einstellungen ("arbeit:blau,privat:pink")
    readonly property var tagList: Core.parseTagConf(Plasmoid.configuration.tags)
    onTagListChanged: rebuildRows()
    function tagColor(name) {
        for (var i = 0; i < tagList.length; i++) if (tagList[i].name.toLowerCase() === String(name).toLowerCase()) return tagList[i].color;
        return "grau";
    }
    function saveTags(list) { Plasmoid.configuration.tags = Core.tagConfString(list); }
    function addTag(name, color) {
        name = Core.cleanTag(name);
        if (!name || !/\D/.test(name)) return false;
        var list = tagList.slice();
        if (list.length >= 8) return false;          // wie Windows: hoechstens 8 Tags
        for (var i = 0; i < list.length; i++) if (list[i].name.toLowerCase() === name.toLowerCase()) return false;
        // wie Windows: erste noch nicht benutzte Farbe
        if (!color) {
            var used = {};
            for (var j = 0; j < list.length; j++) used[list[j].color] = true;
            color = P.TAG_COLORS[list.length % 6];
            for (var k = 0; k < P.TAG_COLORS.length; k++) if (!used[P.TAG_COLORS[k]]) { color = P.TAG_COLORS[k]; break; }
        }
        list.push({ name: name, color: color });
        saveTags(list);
        return true;
    }
    function removeTag(name) { saveTags(tagList.filter(function (t) { return t.name !== name; })); }
    // naechste Farbe fuer einen Tag (Klick auf den Farbpunkt)
    function cycleTagColor(name) {
        saveTags(tagList.map(function (t) {
            if (t.name !== name) return t;
            var i = P.TAG_COLORS.indexOf(t.color);
            return { name: t.name, color: P.TAG_COLORS[(i + 1) % P.TAG_COLORS.length] };
        }));
    }

    // ---------- Reihenfolge ----------
    // Punkt per Ziehen verschieben (nur offene Punkte; die Reihenfolge steht danach so in der Datei)
    function moveTask(fromLine, fromOrig, toLine, toOrig) {
        enqueue(function (m) {
            var a = Core.findTask(m, fromLine, fromOrig), b = Core.findTask(m, toLine, toOrig);
            if (!a || !b || a.done || b.done) return false;
            return Core.moveTask(m, a, b);
        });
    }
    // Umstieg auf die eigene Reihenfolge (seit 1.3.0): die Datei einmal so ordnen, wie sie bisher angezeigt wurde
    function migrateOrder() {
        if (Plasmoid.configuration.manualOrder) return;
        enqueue(function (m) {
            Plasmoid.configuration.manualOrder = true;
            return Core.sortOnce(m);
        });
    }

    // ---------- Updates von Hand (Einstellungen: "Nach Updates suchen") ----------
    // updateState: "" | "checking" | "current" | "available" | "installing" | "error"
    property string updateState: ""
    property string updateVersion: ""
    function checkForUpdates() {
        updateState = "checking";
        run('u="${XDG_DATA_HOME:-$HOME/.local/share}/taskboard/update.sh"; [ -f "$u" ] && sh "$u" --check 2>/dev/null || echo fehler', function (code, out) {
            var m = /^(neu|aktuell) (\S+)/m.exec(out);
            if (!m) { updateState = "error"; return; }
            updateVersion = m[2];
            updateState = m[1] === "neu" ? "available" : "current";
        });
    }
    // jetzt installieren: laeuft ausserhalb von Plasma weiter (Plasma wird am Ende neu gestartet und laedt die neue Version)
    function installUpdate() {
        updateState = "installing";
        run('u="${XDG_DATA_HOME:-$HOME/.local/share}/taskboard/update.sh"; '
            + 'if command -v systemd-run >/dev/null 2>&1 && systemd-run --user --quiet --collect sh "$u" --now >/dev/null 2>&1; then :; '
            + 'else setsid sh "$u" --now >/dev/null 2>&1 < /dev/null & fi');
    }

    Timer {
        interval: 2000; running: !root.configMissing; repeat: true
        onTriggered: root.refresh()
    }
    // jede Minute neu zeichnen (heute 15:00 wird rechtzeitig rot) und Erinnerungen pruefen
    Timer {
        interval: 30000; running: true; repeat: true; triggeredOnStart: false
        onTriggered: { root.rebuildRows(); root.checkReminders(); }
    }

    // ---------- Aenderungen (nacheinander, jeweils auf frisch gelesener Datei) ----------
    // op(model) aendert model.lines und gibt zurueck:
    //   false/undefined = nichts zu tun, true = Todo speichern,
    //   { archive: [bloecke], after: function(model) } = erst Archiv schreiben, dann after() und Todo speichern
    function enqueue(op) {
        queue.push(op);
        if (!busy) nextOp();
    }
    function nextOp() {
        if (queue.length === 0) { busy = false; return; }
        busy = true;
        var op = queue.shift();
        readFile(todoFile, function (c) {
            if (c === null) { fileMissing = true; return nextOp(); }
            var m = Core.parse(c);
            var r = op(m);
            if (!r) { setContent(c); return nextOp(); }
            var saveTodo = function () {
                var nc = Core.serialize(m);
                writeFile(todoFile, nc, function (ok) {
                    if (ok) setContent(nc);
                    nextOp();
                });
            };
            if (r === true) return saveTodo();
            // erst ins Archiv, nur bei Erfolg die Todo.md aendern
            readFile(archiveFile, function (ac) {
                writeFile(archiveFile, Core.appendArchive(ac || "", r.archive, new Date()), function (ok) {
                    if (!ok) return nextOp();
                    r.after(m);
                    saveTodo();
                });
            });
        });
    }

    function rollOp(m) {
        var r = Core.rollRecurring(m, new Date());
        if (!r) return false;
        return { archive: r.blocks, after: function (mm) { Core.applyChanges(mm, r.changes); } };
    }

    function toggle(line, orig) {
        enqueue(function (m) {
            var t = Core.findTask(m, line, orig);
            if (!t) return false;
            Core.flip(m, t.line, new Date());
            // wiederkehrend: gleich weiterschieben (nach dem Speichern als eigene Aenderung)
            if (Core.ruleOf(t.text)) enqueue(function (mm) { return rollOp(mm); });
            return true;
        });
    }
    function toggleSub(taskLine, taskOrig, line, orig) {
        enqueue(function (m) {
            var t = Core.findTask(m, taskLine, taskOrig);
            if (!t) return false;
            var ln = Core.findChild(m, t, line, orig);
            if (ln < 0) return false;
            Core.flip(m, ln, new Date());
            return true;
        });
    }
    function toggleNotes(key) {
        var e = openNotes;
        if (e[key]) delete e[key]; else e[key] = true;
        openNotes = e;
        rebuildRows();
    }
    function cleanup() {
        enqueue(function (m) {
            var r = Core.cleanup(m, new Date());
            if (!r) return false;
            return { archive: r.blocks, after: function (mm) { Core.removeLines(mm, r.remove); } };
        });
    }
    // Notiz / Unteraufgabe / Datei hinzufuegen
    function addChild(taskLine, taskOrig, kind, text) {
        text = Core.trim(text || "");
        if (!text) return;
        enqueue(function (m) {
            var t = Core.findTask(m, taskLine, taskOrig);
            if (!t) return false;
            Core.addChild(m, t, kind, text, new Date());
            if (kind !== "sub") { var e = openNotes; e[Core.stripMarker(t.text)] = true; openNotes = e; }
            return true;
        });
    }
    // Notiz / Unteraufgabe aendern (leer = loeschen)
    function editChild(taskLine, taskOrig, line, orig, text) {
        enqueue(function (m) {
            var t = Core.findTask(m, taskLine, taskOrig);
            if (!t) return false;
            var ln = Core.findChild(m, t, line, orig);
            if (ln < 0) return false;
            Core.editChild(m, ln, text, new Date());
            return true;
        });
    }
    function childInput(line) { return model ? Core.childInput(model, line) : ""; }

    // ---------- Formular ----------
    function openForm(row) {
        if (row) {
            var t = model ? Core.findTask(model, row.line, row.orig) : null;
            if (!t) return;
            form.openEdit(Core.formOf(t), row.line, row.orig);
        } else {
            form.openNew();
        }
    }
    function saveForm(mode, line, orig, values) {
        enqueue(function (m) {
            if (mode === "new") {
                var text = Core.addTask(m, values, new Date());
                if (values.notes && values.notes.length) { var e = openNotes; e[text] = true; openNotes = e; }
                return true;
            }
            var t = Core.findTask(m, line, orig);
            if (!t) return false;
            var wasOpen = openNotes[Core.stripMarker(t.text)];
            var nt = Core.editTask(m, t, values);
            if (wasOpen) { var e2 = openNotes; e2[Core.stripMarker(nt)] = true; openNotes = e2; }
            return true;
        });
    }
    function deleteTask(line, orig) {
        enqueue(function (m) {
            var t = Core.findTask(m, line, orig);
            if (!t) return false;
            var block = Core.blockOf(m, t, "-", new Date());
            return { archive: [block], after: function (mm) {
                var t2 = Core.findTask(mm, line, orig);
                if (t2) Core.removeTask(mm, t2);
            } };
        });
    }

    // ---------- Oeffnen ----------
    function openInObsidian(path) {
        // nur Google: Titel oeffnet Google Tasks im Browser, das Archiv ist eine Datei auf diesem PC
        if (!obsidianOn) { Qt.openUrlExternally(path ? "file://" + encodeURI(path) : "https://tasks.google.com/"); return; }
        Qt.openUrlExternally("obsidian://open?path=" + encodeURIComponent(path || todoFile));
    }
    function openLink(url) { if (url) Qt.openUrlExternally(url); }

    // ---------- Erinnerungen ----------
    function checkReminders() {
        if (!model || !Plasmoid.configuration.remindOn) return;
        var lead = Plasmoid.configuration.remindLead * 60000;
        Core.dueReminders(model, reminderState, new Date(Date.now() + lead)).forEach(function (r) {
            var body = r.title + " (" + r.time + ")";
            if (hasNotifySend) {
                run('notify-send -a "Task Board" -i checkbox -u critical --action=done=Erledigt --action=snooze="In 15 Min nochmal" --wait "Todo fällig" ' + q(body),
                    function (code, out) {
                        var a = out.trim();
                        if (a === "done") doneByKey(r.key);
                        else if (a === "snooze") reminderState.snoozed[r.key] = Date.now() + 15 * 60000;
                    });
            } else {
                run('kdialog --title "Todo fällig" --passivepopup ' + q(body) + ' 60');
            }
        });
    }
    function doneByKey(key) {
        enqueue(function (m) {
            for (var i = 0; i < m.display.length; i++) {
                var t = m.display[i];
                if (Core.stripMarker(t.text) === key && !t.done) {
                    Core.flip(m, t.line, new Date());
                    if (Core.ruleOf(t.text)) enqueue(function (mm) { return rollOp(mm); });
                    return true;
                }
            }
            return false;
        });
    }

    // ---------- Google Tasks (google-sync.py, gleiche Regeln wie src/google.cs unter Windows) ----------
    // Abgleich 3 Sekunden nach einer Aenderung an der Datei (wer in Obsidian tippt, dem wird nicht mitten in die Zeile
    // geschrieben), sonst alle 2 Minuten. Google erlaubt dem ganzen Projekt 50.000 Anfragen pro Tag.
    property bool googleOn: false
    property bool obsidianOn: true
    property bool googleConnected: false
    property string googleStatus: ""
    property string googleList: ""
    property string googleListName: ""
    property string googleHint: ""          // kurzer Hinweis statt der Statuszeile ("Browser oeffnet sich ...")
    property bool googleBusy: false
    property bool hasPython: true
    property bool syncRunning: false
    property bool syncAgain: false
    property string lastSyncedContent: ""
    readonly property string gpy: '"${XDG_DATA_HOME:-$HOME/.local/share}/taskboard/google-sync.py"'

    // Einstellung (~/.config/taskboard/google) und Stand des Abgleichs (google-status) lesen
    function pollGoogle(after) {
        run('cat "${XDG_CONFIG_HOME:-$HOME/.config}/taskboard/google" 2>/dev/null; echo "==S=="; cat "${XDG_DATA_HOME:-$HOME/.local/share}/taskboard/google-status" 2>/dev/null; true',
            function (code, out) {
                var i = out.indexOf("==S==");
                var kv = {};
                out.substring(0, Math.max(i, 0)).split("\n").forEach(function (l) {
                    var p = l.indexOf("=");
                    if (p > 0) kv[l.substring(0, p).trim()] = l.substring(p + 1).trim();
                });
                var st = i < 0 ? [] : out.substring(i + 5).replace(/^\n/, "").split("\n");
                var wasOn = googleOn;
                googleOn = kv.GOOGLE_ON === "1";
                obsidianOn = kv.OBSIDIAN_ON !== "0";
                googleList = kv.GOOGLE_LIST || "";
                googleListName = kv.GOOGLE_LIST_NAME || "";
                googleConnected = st[1] === "1";
                googleStatus = st.slice(2).join(" ").trim();
                if (googleOn && !wasOn) runSync();
                if (after) after();
            });
    }
    function runSync() {
        if (!googleOn || configMissing) return;
        if (syncRunning) { syncAgain = true; return; }
        syncRunning = true;
        run('python3 ' + gpy + ' sync 2>/dev/null; true', function (code, out) {
            syncRunning = false;
            readFile(todoFile, function (c) {
                // Was der Abgleich selbst geschrieben hat, loest keinen weiteren aus. Hat jemand waehrenddessen
                // geaendert, passt die Pruefsumme nicht - dann geht es normal ueber syncSoon weiter.
                if (c !== null && Qt.md5(c) === out.trim()) lastSyncedContent = c;
                root.refresh();
                pollGoogle();
                if (syncAgain) { syncAgain = false; syncSoon.restart(); }
            });
        });
    }
    Timer { id: syncSoon; interval: 3000; onTriggered: root.runSync() }
    Timer {
        interval: 120000; running: root.googleOn; repeat: true
        onTriggered: root.runSync()
    }
    Timer {
        interval: settings.visible ? 2000 : 30000; running: true; repeat: true
        onTriggered: root.pollGoogle()
    }
    Timer { id: hintTimer; interval: 6000; onTriggered: root.googleHint = "" }
    function showHint(t) { googleHint = t; hintTimer.restart(); }

    // connect | pick-list | disconnect | enable 0/1 | store google/obsidian
    function googleRun(args, hint) {
        if (googleBusy) return;
        if (!hasPython) { showHint("Für Google Tasks wird Python 3 gebraucht (Paket python3)."); return; }
        googleBusy = true;
        hintTimer.stop();
        googleHint = hint;
        run('python3 ' + gpy + ' ' + args + ' 2>&1 | tail -n1', function (code, out) {
            googleBusy = false;
            googleHint = "";
            if (out.indexOf("kein-vault") >= 0) {
                // noch nie eine Datei in Obsidian eingerichtet: jetzt eine waehlen (chooseTodo schaltet Obsidian dann ein)
                showHint("Bitte die Todo-Datei in deinem Obsidian-Vault wählen …");
                settings.chooseFile();
                return;
            }
            var bad = /^fehler: ?(.*)$/m.exec(out);
            if (bad) showHint("Das hat nicht geklappt: " + bad[1]);
            // die Datei kann sich geaendert haben (nur Google <-> Obsidian)
            lastContent = "";
            model = null;
            loadConfig();
        });
    }
    // Haekchen "Speichern in": mindestens eins bleibt an
    function storeClick(which) {
        if (googleBusy) return;
        if (which === "google") {
            if (googleOn) {
                if (!obsidianOn) { showHint("Ohne Google braucht die Liste Obsidian – zuerst „Obsidian“ anhaken."); return; }
                googleRun("enable 0", "");
            } else if (googleConnected && googleList !== "") googleRun("enable 1", "");
            else googleRun("connect", "Dein Browser öffnet sich – bitte bei Google anmelden und Task Board erlauben …");
        } else if (obsidianOn) {
            if (!googleOn) { showHint("Mindestens ein Speicherort muss angehakt sein."); return; }
            googleRun("store google", "Wird umgestellt …");
        } else googleRun("store obsidian", "Wird umgestellt …");
    }

    // ---------- Automatische Updates (update.sh prueft selbst hoechstens alle 6 Stunden) ----------
    function checkUpdate() {
        if (!Plasmoid.configuration.autoUpdate) return;
        run('u="$HOME/.local/share/taskboard/update.sh"; [ -x "$u" ] && "$u" >/dev/null 2>&1; true');
    }
    Timer {
        interval: 6 * 3600 * 1000; running: true; repeat: true
        onTriggered: root.checkUpdate()
    }
    Timer {
        interval: 60000; running: true; repeat: false
        onTriggered: root.checkUpdate()
    }

    Timer {
        id: testTimer
        property string mode: ""
        interval: 1500; running: mode !== ""
        onTriggered: {
            if (mode === "add") root.saveForm("new", -1, "", { title: "Testpunkt", date: "", time: "15:00", rule: "", notes: ["https://kde.org"] });
            else if (mode === "toggle") root.toggle(root.rows[0].line, root.rows[0].orig);
            else if (mode === "cleanup") root.cleanup();
            else if (mode === "grab") root.fullRepresentationItem.grabToImage(function (r) { r.saveToFile(root.home + "/grab.png"); });
            else root.openForm(mode === "edit" && root.rows.length ? root.rows[0] : null);
        }
    }

    // nur fuer automatische Tests (eingeschaltet, wenn beim Start /tmp/taskboard-test.enable existiert):
    property bool testCmds: false
    // nur fuer automatische Tests: Befehle aus /tmp/taskboard-test.cmd (Datei wird danach geloescht)
    // show | hide | settings | reveal | edge | mode=<sidebar|desktop|both> | side=<left|right>
    Timer {
        interval: 1500; running: root.testCmds; repeat: true
        onTriggered: root.run('f=/tmp/taskboard-test.cmd; [ -f "$f" ] && { cat "$f"; rm -f "$f"; }; true', function (code, out) {
            out.split("\n").forEach(function (c) {
                c = c.trim();
                if (c === "show") side.show();
                else if (c === "hide") side.hide();
                else if (c === "edge") side.edgeHit();
                else if (c === "edgeleave") side.edgeLeft();
                else if (c === "rectest") { settings.startRecording(); settings.recordKey({ key: Qt.Key_K, modifiers: Qt.ControlModifier | Qt.AltModifier, accepted: false }); }
                else if (c === "resettest") root.setHotkey("Meta+Shift+T");
                else if (c === "redge") side.debugEdge = !side.debugEdge;
                else if (c === "add") root.saveForm("new", -1, "", { title: "Testpunkt", date: "", time: "15:00", rule: "", notes: ["https://kde.org"] });
                else if (c === "toggle") root.toggle(root.rows[0].line, root.rows[0].orig);
                else if (c === "cleanup") root.cleanup();
                else if (c === "form") root.openForm(null);
                else if (c === "editform") root.openForm(root.rows[0]);
                else if (c === "closeform") form.visible = false;
                else if (c === "formcal") form.calOpen = !form.calOpen;
                else if (c === "formshot") form.contentItem.grabToImage(function (r) { r.saveToFile("/tmp/taskboard-form.png"); });
                else if (c.indexOf("grab=") === 0) {
                    var gn = c.substring(5);
                    var gi = gn === "form" ? form.contentItem : gn === "settings" ? settings.contentItem : gn === "panel" ? side.panelItem : root.fullRepresentationItem;
                    if (gi) gi.grabToImage(function (r) { r.saveToFile("/tmp/taskboard-" + gn + ".png"); });
                }
                else if (c.indexOf("formfill=") === 0) form.testFill(c.substring(9));
                // move=2,0: Zeile 2 an die Stelle von Zeile 0 ziehen (wie mit der Maus)
                else if (c.indexOf("move=") === 0) { var mv = c.substring(5).split(","); var dv2 = root.fullRepresentationItem.children[0]; dv2.dragStart(+mv[0]); dv2.dragTo = +mv[1]; dv2.dragEnd(); }
                else if (c.indexOf("tags=") === 0) Plasmoid.configuration.tags = c.substring(5);
                else if (c.indexOf("opacity=") === 0) Plasmoid.configuration.opacity = +c.substring(8);
                else if (c.indexOf("tagedit=") === 0) settings.testTagEdit(c.substring(8));
                else if (c.indexOf("formtags=") === 0) { form.tags = c.substring(9).split(","); }
                else if (c.indexOf("store=") === 0) root.storeClick(c.substring(6));
                else if (c === "gpick") root.googleRun("pick-list", "Einen Moment – Listen werden geladen …");
                else if (c === "gdisconnect") root.googleRun("disconnect", "Verbindung wird getrennt …");
                else if (c === "gstate") root.run('printf %s ' + root.q("on=" + root.googleOn + " obs=" + root.obsidianOn + " conn=" + root.googleConnected + " busy=" + root.googleBusy + " sync=" + root.syncRunning + " list=" + root.googleListName + " status=" + root.googleStatus + " hint=" + root.googleHint + " file=" + root.todoFile) + ' > /tmp/taskboard-test.out');
                else if (c === "rows") root.run('printf %s ' + root.q(root.rows.map(function (r) { return (r.done ? "[x] " : "[ ] ") + r.title + (r.dueLabel ? " (" + r.dueLabel + ")" : "") + (r.repeat ? " R" : "") + " #" + r.tags.map(function (t) { return t.name; }).join(",") + " subs=" + r.subs.map(function (s) { return s.title; }).join("/") + " notes=" + r.notes.length + " open=" + r.open; }).join("\n")) + ' > /tmp/taskboard-test.out');
                else if (c === "updcheck") root.checkForUpdates();
                else if (c === "updnow") root.installUpdate();
                else if (c === "migrate") { Plasmoid.configuration.manualOrder = false; root.migrateOrder(); }
                else if (c === "updstate") root.run('printf %s ' + root.q("update=" + root.updateState + " " + root.updateVersion + " order=" + Plasmoid.configuration.manualOrder) + ' > /tmp/taskboard-test.out');
                else if (c.indexOf("choose=") === 0) root.chooseTodo(c.substring(7));
                else if (c === "todo") root.run('{ echo "datei=' + root.todoFile + '"; cat ' + root.q(root.todoFile) + '; } > /tmp/taskboard-test.out');
                else if (c === "formsize") root.run('printf %s ' + root.q("window=" + form.width + "x" + form.height + " inhalt=" + form.wantW + "x" + form.wantH) + ' > /tmp/taskboard-test.out');
                else if (c === "notes") root.toggleNotes(root.rows[0].key);
                else if (c === "settings") root.openSettings();
                else if (c === "closesettings") settings.visible = false;
                else if (c === "reveal") root.reveal();
                else if (c.indexOf("mode=") === 0) Plasmoid.configuration.mode = c.substring(5);
                else if (c.indexOf("side=") === 0) Plasmoid.configuration.side = c.substring(5);
                else if (c.indexOf("accent=") === 0) Plasmoid.configuration.accent = c.substring(7);
                else if (c.indexOf("hotkey=") === 0) root.setHotkey(c.substring(7));
                else if (c === "settingsmove") { settings.x = settings.x - 200; settings.y = settings.y - 100; root.run("printf %s " + root.q("settings " + settings.x + "," + settings.y) + " > /tmp/taskboard-test.out"); }
                else if (c === "deskinfo") { var d2 = root.fullRepresentationItem.children[0]; var bx = d2.deskContainer(); root.run("printf %s " + root.q(bx ? "halter " + bx.width + "x" + bx.height + " liste " + d2.implicitWidth + "x" + d2.implicitHeight : "kein Halter") + " > /tmp/taskboard-test.out"); }
                else if (c === "desksize") { var d3 = root.fullRepresentationItem.children[0]; var b3 = d3.deskContainer(); b3.height = d3.implicitHeight; root.run("printf %s " + root.q("halter jetzt " + b3.width + "x" + b3.height) + " > /tmp/taskboard-test.out"); }
                else if (c === "direct" || c === "undirect") { var dv = root.fullRepresentationItem.children[0]; dv.setDirectMove(c === "direct"); root.run("printf %s " + root.q(dv.box ? "bedingung=" + dv.box.editModeCondition : "kein Halter") + " > /tmp/taskboard-test.out"); }
                else if (c === "status") root.run('printf %s ' + root.q("shown=" + side.shown + " mode=" + root.mode + " hotkey=" + root.hotkey + " version=" + root.version) + ' > /tmp/taskboard-test.out');
            });
        })
    }

    Component.onCompleted: {
        // alte Hintergrund-Stufen (bis 1.2: 218/190/150) auf die neuen umstellen
        var old = { 218: 170, 190: 100, 150: 1 };
        if (old[Plasmoid.configuration.opacity] !== undefined)
            Plasmoid.configuration.opacity = old[Plasmoid.configuration.opacity];
        loadConfig();
    }
}
