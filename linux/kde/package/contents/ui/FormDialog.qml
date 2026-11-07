// Formular fuer neue Punkte und "bearbeiten" - gleiche Moeglichkeiten und gleicher Look wie unter Windows
import QtQuick
import org.kde.plasma.plasmoid
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Dialogs
import QtQuick.Controls as QQC2
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "../code/todo.js" as Core
import "../code/palette.js" as P

// normales randloses Fenster (kein Plasma-Dialog): nur so laesst KDE es an der Titelzeile verschieben
Window {
    id: dlg
    property var app

    // Formularwerte
    property string mode: "new"
    property int line: -1
    property string orig: ""
    property string date: ""          // JJJJ-MM-TT oder ""
    property string time: ""          // HH:MM oder ""
    property string rule: ""
    property var notes: []
    property var tags: []             // zugewiesene Tags (Namen)
    property string errorText: ""
    property bool confirmDelete: false

    // Kalender / Uhrzeit / eigene Wiederholung
    property bool calOpen: false
    property int calYear: 2026
    property int calMonth: 0          // 0 = Januar
    property bool otherTime: false
    property bool custOpen: false
    property int custN: 1
    property int custUnit: 0
    property var custDays: [false, false, false, false, false, false, false]   // Mo..So

    readonly property var times: ["09:00", "12:00", "15:00", "18:00", "21:00"]
    readonly property var standardRules: ["", "täglich", "werktags", "wöchentlich", "monatlich"]
    readonly property var ruleNames: ["Nie", "Täglich", "Werktags", "Wöchentlich", "Monatlich"]
    readonly property var units: ["Tage", "Wochen", "Monate", "Jahre"]
    readonly property var unit1: ["täglich", "wöchentlich", "monatlich", "jährlich"]
    readonly property var wds: ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    title: "Task Board"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
    color: "transparent"
    readonly property int wantW: panel.implicitWidth
    readonly property int wantH: panel.implicitHeight
    width: wantW
    // nie hoeher als der Bildschirm; was nicht passt, laesst sich scrollen
    height: Math.min(wantH, Screen.desktopAvailableHeight - Kirigami.Units.gridUnit * 2)

    // ---------- Oeffnen ----------
    function reset() {
        errorText = ""; confirmDelete = false; calOpen = false; otherTime = false; custOpen = false;
        custN = 1; custUnit = 0; custDays = [false, false, false, false, false, false, false];
    }
    function openNew() {
        reset();
        mode = "new"; line = -1; orig = "";
        titleField.text = ""; date = ""; time = ""; rule = ""; notes = []; tags = [];
        showDialog();
    }
    function openEdit(values, ln, o) {
        reset();
        mode = "edit"; line = ln; orig = o;
        titleField.text = values.title; date = values.date; time = values.time; rule = values.rule;
        notes = values.notes.slice();
        tags = (values.tags || []).slice();
        otherTime = time !== "" && times.indexOf(time) < 0;
        if (otherTime) otherField.text = time;
        if (rule !== "" && standardRules.indexOf(rule) < 0) loadCustom(rule);
        showDialog();
    }
    function showDialog() {
        var d = Core.fromIso(date) || Core.today();
        calYear = d.getFullYear(); calMonth = d.getMonth();
        visible = true;
        raise();
        requestActivate();
        titleField.forceActiveFocus();
    }

    // nur fuer Tests: Formular wie von Hand ausfuellen (Titel, Datum per Kalender morgen, 09:00, woechentlich) und speichern
    function testFill(t) {
        titleField.text = t;
        var m = Core.addDays(Core.today(), 1);
        date = Core.iso(m); time = "09:00"; rule = "wöchentlich";
        save();
    }

    // ---------- Wiederholung ----------
    function loadCustom(r) {
        custN = 1; custUnit = 0;
        var days = [false, false, false, false, false, false, false];
        var k = unit1.indexOf(r);
        if (k >= 0) custUnit = k;
        var m = /^alle (\d+) (\S+)$/.exec(r);
        if (m) { custN = +m[1]; custUnit = Math.max(0, units.indexOf(m[2])); }
        else (r.match(/[A-Za-z]{2}/g) || []).forEach(function (d) { var i = wds.indexOf(d); if (i >= 0) days[i] = true; });
        custDays = days;
    }
    function customRule() {
        var days = [];
        for (var k = 0; k < 7; k++) if (custDays[k]) days.push(wds[k]);
        if (days.length) return days.join(",");
        if (custN === 1) return unit1[custUnit];
        return "alle " + custN + " " + units[custUnit];
    }
    function applyCustom() { rule = customRule(); }

    // ---------- Speichern ----------
    function parseTime(s) {
        var m = /^(\d\d?)[:.]?(\d\d)$/.exec(Core.trim(s)) || /^(\d\d?)$/.exec(Core.trim(s));
        if (!m) return null;
        var h = +m[1], mi = m[2] !== undefined ? +m[2] : 0;
        if (h > 23 || mi > 59) return null;
        return (h < 10 ? "0" : "") + h + ":" + (mi < 10 ? "0" : "") + mi;
    }
    function currentForm() { return { date: date, time: otherTime ? (parseTime(otherField.text) || "") : time, rule: rule }; }
    function save() {
        var title = Core.trim(titleField.text);
        if (title === "") {
            errorText = "Bitte zuerst eintragen, was zu tun ist.";
            titleField.forceActiveFocus();
            return;
        }
        if (otherTime) {
            var t = parseTime(otherField.text);
            if (otherField.text !== "" && !t) { errorText = "„" + otherField.text + "“ ist keine Uhrzeit – bitte z. B. 15:30 eingeben."; return; }
            time = t || "";
        }
        var values = { title: title, date: date, time: time, rule: rule, tags: tags.slice(),
                       notes: notes.map(function (n) { return Core.trim(n); }).filter(function (n) { return n !== ""; }) };
        app.saveForm(mode, line, orig, values);
        visible = false;
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        color: P.formBg
        radius: Kirigami.Units.gridUnit * 0.75
        Kirigami.Theme.colorSet: Kirigami.Theme.Complementary
        Kirigami.Theme.inherit: false
        implicitWidth: Kirigami.Units.gridUnit * 30
        implicitHeight: content.implicitHeight + Kirigami.Units.gridUnit * 2
        Keys.onEscapePressed: dlg.visible = false

        FileDialog {
            id: fileDialog
            title: "Datei anhängen"
            fileMode: FileDialog.OpenFiles
            onAccepted: {
                var n = dlg.notes.slice();
                selectedFiles.forEach(function (u) { n.push(decodeURIComponent(u.toString().replace(/^file:\/\//, ""))); });
                dlg.notes = n;
            }
        }

        component Caption: PC3.Label {
            color: P.done
            font.weight: Font.DemiBold
            Layout.topMargin: Kirigami.Units.largeSpacing
        }
        component Field: PC3.TextField {
            color: P.text
            topPadding: Kirigami.Units.smallSpacing * 2
            bottomPadding: Kirigami.Units.smallSpacing * 2
            leftPadding: Kirigami.Units.largeSpacing
            rightPadding: Kirigami.Units.largeSpacing
            placeholderTextColor: P.done
            background: Rectangle {
                radius: Kirigami.Units.gridUnit * 0.4
                color: P.field
                border.width: 1
                border.color: parent.activeFocus ? P.check(Plasmoid.configuration.accent) : P.fieldBorder
            }
        }

        Flickable {
            id: flick
            anchors.fill: parent
            clip: true
            contentWidth: width
            contentHeight: panel.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            PC3.ScrollBar.vertical: PC3.ScrollBar { policy: flick.interactive ? PC3.ScrollBar.AlwaysOn : PC3.ScrollBar.AlwaysOff }

        ColumnLayout {
            id: content
            x: Kirigami.Units.gridUnit
            y: Kirigami.Units.gridUnit
            width: flick.width - Kirigami.Units.gridUnit * 2
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                // an der Titelzeile ziehen = Fenster verschieben (KDE uebernimmt das Ziehen)
                PC3.Label {
                    text: dlg.mode === "edit" ? "Eintrag bearbeiten" : "Neuer Eintrag"
                    color: P.text
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.45
                    font.bold: true
                    Layout.fillWidth: true
                    // Titelzeile ziehen = Fenster verschieben
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.SizeAllCursor
                        onPressed: dlg.startSystemMove()
                    }
                }
                Chip { flat: true; iconName: "window-close"; textColor: P.done; onClicked: dlg.visible = false }
            }

            Caption { text: "Was ist zu tun?"; Layout.topMargin: Kirigami.Units.smallSpacing }
            Field {
                id: titleField
                Layout.fillWidth: true
                placeholderText: "Hier eintippen – Enter speichert"
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.15
                font.weight: Font.DemiBold
                onAccepted: dlg.save()               // Enter = sofort speichern
                onTextChanged: if (text !== "") dlg.errorText = ""
            }

            // ---------- Datum ----------
            Caption { text: "Fällig am" }
            Flow {
                id: dateFlow
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                readonly property string t0: Core.iso(Core.today())
                readonly property string t1: Core.iso(Core.addDays(Core.today(), 1))
                readonly property string t7: Core.iso(Core.addDays(Core.today(), 7))
                readonly property bool other: dlg.date !== "" && [t0, t1, t7].indexOf(dlg.date) < 0
                Chip { text: "Kein Datum"; selected: dlg.date === ""; onClicked: { dlg.date = ""; dlg.calOpen = false } }
                Chip { text: "Heute"; selected: dlg.date === dateFlow.t0; onClicked: { dlg.date = dateFlow.t0; dlg.calOpen = false } }
                Chip { text: "Morgen"; selected: dlg.date === dateFlow.t1; onClicked: { dlg.date = dateFlow.t1; dlg.calOpen = false } }
                Chip { text: "In 1 Woche"; selected: dlg.date === dateFlow.t7; onClicked: { dlg.date = dateFlow.t7; dlg.calOpen = false } }
                Chip {
                    iconName: "view-calendar"
                    text: dateFlow.other ? Core.dotDate(Core.fromIso(dlg.date)) + Core.fromIso(dlg.date).getFullYear() : "Datum wählen"
                    selected: dateFlow.other || dlg.calOpen
                    onClicked: dlg.calOpen = !dlg.calOpen
                }
            }

            // Kalender
            ColumnLayout {
                visible: dlg.calOpen
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                RowLayout {
                    Layout.fillWidth: true
                    Chip { flat: true; iconName: "go-previous"; textColor: P.note; onClicked: { if (dlg.calMonth === 0) { dlg.calMonth = 11; dlg.calYear-- } else dlg.calMonth-- } }
                    PC3.Label { text: Core.MONTHS[dlg.calMonth] + " " + dlg.calYear; color: P.text; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                    Chip { flat: true; iconName: "go-next"; textColor: P.note; onClicked: { if (dlg.calMonth === 11) { dlg.calMonth = 0; dlg.calYear++ } else dlg.calMonth++ } }
                }
                QQC2.DayOfWeekRow {
                    Layout.fillWidth: true
                    locale: Qt.locale("de_DE")
                    delegate: PC3.Label { text: shortName; horizontalAlignment: Text.AlignHCenter; color: P.done; font: Kirigami.Theme.smallFont }
                }
                // eigenes Monatsraster (6 Wochen ab Montag): QQC2.MonthGrid bleibt unter Qt 6.10 (Kubuntu 26.04) leer
                Grid {
                    id: monthGrid
                    Layout.fillWidth: true
                    columns: 7
                    readonly property int offset: (new Date(dlg.calYear, dlg.calMonth, 1).getDay() + 6) % 7
                    readonly property string todayIso: Core.iso(Core.today())
                    Repeater {
                        model: 42
                        delegate: Rectangle {
                            required property int index
                            readonly property var day: new Date(dlg.calYear, dlg.calMonth, 1 - monthGrid.offset + index)
                            readonly property string dayIso: Core.iso(Core.dayOf(day.getFullYear(), day.getMonth() + 1, day.getDate()))
                            readonly property bool sel: dayIso === dlg.date
                            readonly property bool isToday: dayIso === monthGrid.todayIso
                            width: monthGrid.width / 7
                            height: Kirigami.Units.gridUnit * 1.7
                            radius: Kirigami.Units.gridUnit * 0.4
                            color: sel ? P.check(Plasmoid.configuration.accent) : (dayHover.hovered ? P.chipHover : "transparent")
                            border.width: isToday && !sel ? 1 : 0
                            border.color: P.accent(Plasmoid.configuration.accent)
                            opacity: day.getMonth() === dlg.calMonth ? 1 : 0.3
                            HoverHandler { id: dayHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { dlg.date = parent.dayIso; dlg.calOpen = false } }
                            PC3.Label {
                                anchors.centerIn: parent
                                text: parent.day.getDate()
                                color: parent.sel ? P.text : (parent.isToday ? P.accent(Plasmoid.configuration.accent) : P.note)
                                font.bold: parent.sel
                            }
                        }
                    }
                }
            }

            // ---------- Uhrzeit ----------
            Caption { text: "Uhrzeit (mit Erinnerung)" }
            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Chip { text: "Keine"; selected: dlg.time === "" && !dlg.otherTime; onClicked: { dlg.time = ""; dlg.otherTime = false } }
                Repeater {
                    model: dlg.times
                    delegate: Chip { text: modelData; selected: dlg.time === modelData && !dlg.otherTime; onClicked: { dlg.time = modelData; dlg.otherTime = false } }
                }
                Chip {
                    text: "Andere"; selected: dlg.otherTime
                    onClicked: { dlg.otherTime = true; otherField.text = dlg.time; otherField.forceActiveFocus() }
                }
                Field {
                    id: otherField
                    visible: dlg.otherTime
                    width: Kirigami.Units.gridUnit * 5
                    placeholderText: "15:30"
                    onAccepted: dlg.save()
                }
            }

            // ---------- Wiederholen ----------
            Caption { text: "Wiederholen" }
            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: dlg.ruleNames.length
                    delegate: Chip {
                        text: dlg.ruleNames[index]
                        selected: dlg.rule === dlg.standardRules[index] && !dlg.custOpen
                        onClicked: { dlg.rule = dlg.standardRules[index]; dlg.custOpen = false }
                    }
                }
                Chip {
                    text: "Individuell …"
                    selected: dlg.custOpen || (dlg.rule !== "" && dlg.standardRules.indexOf(dlg.rule) < 0)
                    onClicked: { dlg.custOpen = !dlg.custOpen; if (dlg.custOpen) { if (dlg.rule !== "") dlg.loadCustom(dlg.rule); dlg.applyCustom() } }
                }
            }
            ColumnLayout {
                visible: dlg.custOpen
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    PC3.Label { text: "Alle"; color: P.note; height: Kirigami.Units.gridUnit * 1.8; verticalAlignment: Text.AlignVCenter }
                    Chip { text: "−"; onClicked: { if (dlg.custN > 1) dlg.custN--; dlg.custDays = [false, false, false, false, false, false, false]; dlg.applyCustom() } }
                    PC3.Label { text: dlg.custN; color: P.text; font.bold: true; width: Kirigami.Units.gridUnit * 1.5; height: Kirigami.Units.gridUnit * 1.8; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    Chip { text: "+"; onClicked: { if (dlg.custN < 99) dlg.custN++; dlg.custDays = [false, false, false, false, false, false, false]; dlg.applyCustom() } }
                    Repeater {
                        model: dlg.units
                        delegate: Chip {
                            text: modelData
                            selected: dlg.custUnit === index && dlg.custDays.indexOf(true) < 0
                            onClicked: { dlg.custUnit = index; dlg.custDays = [false, false, false, false, false, false, false]; dlg.applyCustom() }
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    PC3.Label { text: "oder an:"; color: P.note; height: Kirigami.Units.gridUnit * 1.8; verticalAlignment: Text.AlignVCenter }
                    Repeater {
                        model: dlg.wds
                        delegate: Chip {
                            text: modelData
                            selected: dlg.custDays[index]
                            onClicked: { var d = dlg.custDays.slice(); d[index] = !d[index]; dlg.custDays = d; dlg.applyCustom() }
                        }
                    }
                }
            }

            // ---------- Tags (anlegen und Farben in den Einstellungen) ----------
            Caption { text: "Tags" }
            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: dlg.app && dlg.app.tagList.length > 0
                Repeater {
                    model: dlg.app ? dlg.app.tagList : []
                    delegate: Chip {
                        readonly property bool on: dlg.tags.some(function (n) { return n.toLowerCase() === modelData.name.toLowerCase(); })
                        text: modelData.name
                        selected: on
                        fill: on ? P.tagDot(modelData.color) : (hovered ? P.chipHover : P.chip)
                        border.color: on ? P.tagDot(modelData.color) : P.chipStroke
                        textColor: on ? P.text : P.tagText(modelData.color)
                        onClicked: {
                            var name = modelData.name;
                            dlg.tags = on ? dlg.tags.filter(function (n) { return n.toLowerCase() !== name.toLowerCase(); }) : dlg.tags.concat([name]);
                        }
                    }
                }
            }
            PC3.Label {
                visible: !dlg.app || dlg.app.tagList.length === 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: P.done
                text: "Noch keine Tags – anlegen in den Einstellungen (Zahnrad)."
            }

            // ---------- Zusammenfassung ----------
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.largeSpacing
                implicitHeight: summaryLabel.implicitHeight + Kirigami.Units.largeSpacing * 2
                radius: Kirigami.Units.gridUnit * 0.4
                color: P.soft(Plasmoid.configuration.accent)
                PC3.Label {
                    id: summaryLabel
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Kirigami.Units.largeSpacing
                    wrapMode: Text.Wrap
                    text: dlg.errorText !== "" ? dlg.errorText : Core.summary(dlg.currentForm())
                    color: dlg.errorText !== "" ? P.over : P.accent(Plasmoid.configuration.accent)
                }
            }

            // ---------- Notizen ----------
            Caption { text: "Notizen, Links, Dateien" }
            Repeater {
                id: notesRep
                model: dlg.notes.length
                delegate: RowLayout {
                    Layout.fillWidth: true
                    property alias field: noteField
                    Field {
                        id: noteField
                        Layout.fillWidth: true
                        text: dlg.notes[index]
                        onTextEdited: { var n = dlg.notes; n[index] = text; }
                        // leer gelassen und woanders hingeklickt: Zeile wieder weg (wie unter Windows)
                        onActiveFocusChanged: if (!activeFocus && Core.trim(text) === "" && dlg.visible) {
                            var i = index;
                            Qt.callLater(function () { if (i < dlg.notes.length && Core.trim(dlg.notes[i]) === "") { var n = dlg.notes.slice(); n.splice(i, 1); dlg.notes = n; } });
                        }
                    }
                    Chip {
                        flat: true; iconName: "edit-delete-remove"; textColor: P.done
                        onClicked: { var n = dlg.notes.slice(); n.splice(index, 1); dlg.notes = n }
                    }
                }
            }
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                // neue Zeile bekommt gleich den Cursor (sonst landet das Getippte im Namensfeld)
                Chip { iconName: "list-add"; text: "Notiz / Link"; onClicked: {
                    var n = dlg.notes.slice(); n.push(""); dlg.notes = n;
                    Qt.callLater(function () { var it = notesRep.itemAt(dlg.notes.length - 1); if (it) it.field.forceActiveFocus(); });
                } }
                Chip { iconName: "mail-attachment"; text: "Datei"; onClicked: fileDialog.open() }
            }

            // ---------- Knoepfe ----------
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.gridUnit
                Chip {
                    visible: dlg.mode === "edit"
                    text: dlg.confirmDelete ? "Wirklich löschen?" : "Löschen"
                    textColor: P.danger
                    fill: dlg.confirmDelete ? "#3CFF7373" : P.chip
                    onClicked: {
                        if (!dlg.confirmDelete) { dlg.confirmDelete = true; return; }
                        dlg.app.deleteTask(dlg.line, dlg.orig);
                        dlg.visible = false;
                    }
                }
                Item { Layout.fillWidth: true }
                Chip { text: "Abbrechen"; onClicked: dlg.visible = false }
                Chip { text: "Speichern"; selected: true; onClicked: dlg.save() }
            }
        }
        }
    }
}
