// Liste der Punkte im Windows-Look: dunkel, halbdurchsichtig, abgerundet
import QtQuick
import QtQuick.Effects
import org.kde.plasma.plasmoid
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "../code/palette.js" as P

Rectangle {
    id: view
    property var app
    // im Panel der Seitenleiste (SidePanel.qml): Maus rein/raus steuert das Hinausgleiten
    property bool inPanel: false
    // so hoch darf die Liste hoechstens werden (Bildschirmhoehe); passen nicht alle Eintraege hinein,
    // blaettert man mit dem Mausrad (wie unter Windows)
    property real maxHeight: 1e6
    function scrollTop() { flick.contentY = 0; }

    // Plasmas Halter des Widgets auf dem Desktop (ItemContainer)
    function deskContainer() {
        for (var p = view.parent; p; p = p.parent)
            if (p.editModeCondition !== undefined && p.editMode !== undefined) return p;
        return null;
    }
    property var box: null
    property int savedCondition: -1
    function setDirectMove(on) {
        if (!box) box = deskContainer();
        if (!box) return;
        if (on) {
            if (savedCondition < 0) savedCondition = box.editModeCondition;
            box.editModeCondition = 3;          // ItemContainer.AfterPress
        } else if (!box.dragActive && savedCondition >= 0) {
            box.editModeCondition = savedCondition;
            savedCondition = -1;
        }
    }
    // Plasmas Halter so hoch machen wie die Liste (sonst ist der Rahmen beim Verschieben viel groesser)
    function fitBox() {
        if (inPanel || !visible) return;
        if (!box) box = deskContainer();
        if (!box || box.dragActive || !box.layout) return;
        var h = Math.ceil(implicitHeight);
        if (Math.abs(box.height - h) > 1) { box.height = h; box.layout.save(); }
    }
    onImplicitHeightChanged: fitTimer.restart()
    onVisibleChanged: fitTimer.restart()
    Component.onCompleted: fitTimer.restart()
    Timer { id: fitTimer; interval: 400; onTriggered: view.fitBox() }
    Connections {
        target: view.box
        // nach dem Ziehen: Bearbeitungsrahmen wieder weg, normales Verhalten zurueck
        function onDragActiveChanged() {
            if (view.box.dragActive) return;
            view.box.editMode = false;
            if (!headHover.hovered) view.setDirectMove(false);
            view.fitBox();
        }
    }

    color: P.bg(Plasmoid.configuration.opacity)
    radius: Kirigami.Units.gridUnit * 0.75
    // feine helle Umrandung, damit man den Kasten auch bei wenig/keinem Hintergrund sieht
    border.width: 1
    border.color: Plasmoid.configuration.opacity <= 100 ? "#5AFFFFFF" : "#28FFFFFF"
    // dunkle Farbgruppe, damit Eingabefelder und Texte von Plasma hell auf dunkel erscheinen
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary
    Kirigami.Theme.inherit: false

    // ---------- Punkte verschieben (Ziehen in TaskRow) ----------
    property int dragFrom: -1
    property int dragTo: -1
    function dragStart(i) { dragFrom = i; dragTo = i; app.editing = true; }   // waehrenddessen nicht neu aufbauen
    // Zielplatz = offener Punkt unter der Maus (oberhalb des ersten -> erster, unterhalb des letzten -> letzter)
    function dragMove(scenePos) {
        if (dragFrom < 0) return;
        var p = rowsList.mapFromItem(null, scenePos.x, scenePos.y);
        var target = -1;
        for (var i = 0; i < rowsRep.count; i++) {
            var it = rowsRep.itemAt(i);
            if (!it || app.rows[i].done) continue;
            if (target < 0 || p.y >= it.y) target = i;
        }
        if (target >= 0) dragTo = target;
    }
    function dragEnd() {
        var from = dragFrom, to = dragTo;
        dragFrom = -1; dragTo = -1;
        app.editing = false;
        if (from < 0 || to < 0 || from === to) return;
        var a = app.rows[from], b = app.rows[to];
        if (a && b) app.moveTask(a.line, a.orig, b.line, b.orig);
    }
    // Linie, wo der Punkt landet: nach unten gezogen unter dem Ziel, nach oben darueber
    Rectangle {
        z: 10
        visible: view.dragFrom >= 0 && view.dragTo >= 0 && view.dragTo !== view.dragFrom
        readonly property var target: visible ? rowsRep.itemAt(view.dragTo) : null
        x: col.x + rowsCol.x
        width: rowsCol.width
        height: 3
        radius: 1.5
        color: P.check(Plasmoid.configuration.accent)
        // Zeilen liegen im blaetterbaren Bereich (flick): dessen Lage und Verschiebung mitrechnen
        y: target ? col.y + rowsCol.y + flick.y - flick.contentY
            + (view.dragTo > view.dragFrom ? target.y + target.height : target.y) - 1 : 0
    }

    // ---------- Blaettern ----------
    // Hoehe von allem ausser den Zeilen (Kopf, "+ Neuer Eintrag", Hinweise); daraus der Platz fuer die Zeilen
    readonly property real indH: Math.round(Kirigami.Units.gridUnit * 1.3)
    readonly property real chromeH: head.implicitHeight + addRow.implicitHeight + addRow.Layout.topMargin
        + (moreLabel.visible ? moreLabel.implicitHeight + moreLabel.Layout.topMargin : 0)
        + (setupHint.visible ? setupHint.implicitHeight + col.spacing : 0)
        + col.spacing + Kirigami.Units.largeSpacing * 2 + 2
    readonly property bool overflow: rowsList.implicitHeight > maxHeight - chromeH
    // Platz fuer den unteren Hinweis; der obere bekommt seine Zeile nur, solange geblaettert ist (dann wird der
    // Zeilenbereich um genau so viel kleiner - die Liste behaelt ihre Hoehe, wie unter Windows)
    readonly property real rowsMax: Math.max(Kirigami.Units.gridUnit * 4, maxHeight - chromeH - (overflow ? indH : 0))
    // Anzahl Zeilen, die mindestens zur Haelfte oberhalb bzw. unterhalb des sichtbaren Bereichs liegen
    function hiddenRows(above, contentY, height, count) {
        var n = 0;
        for (var i = 0; i < count; i++) {
            var it = rowsRep.itemAt(i);
            if (!it) continue;
            var mid = it.y + it.height / 2;
            if (above ? mid < contentY : mid > contentY + height) n++;
        }
        return n;
    }
    function scrollBy(dy) {
        flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy));
    }

    implicitWidth: Kirigami.Units.gridUnit * 24
    implicitHeight: col.implicitHeight + Kirigami.Units.largeSpacing * 2
    Layout.preferredWidth: implicitWidth
    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.preferredHeight: implicitHeight
    Layout.minimumHeight: implicitHeight

    // Klick auf eine freie Stelle der Liste: ein offenes Eingabefeld (Notiz, Unteraufgabe) verliert den
    // Fokus und uebernimmt den Text, wie beim Rausklicken. Der Klick selbst geht normal weiter.
    MouseArea {
        anchors.fill: parent
        z: -1
        onPressed: function(mouse) { view.forceActiveFocus(); mouse.accepted = false; }
    }

    // Durchsichtig: harter dunkler Schatten 1 px nach rechts unten wie unter Windows (Rainmeter
    // StringEffect=Shadow, FontEffectColor 0,0,0,210). Eine schwarze Kopie der Spalte liegt versetzt
    // darunter, die Schrift selbst bleibt scharf obendrauf.
    MultiEffect {
        visible: Plasmoid.configuration.opacity <= 1
        source: col
        x: col.x + 1
        y: col.y + 1
        width: col.width
        height: col.height
        colorization: 1.0
        colorizationColor: "black"
        brightness: -1.0
        opacity: 210 / 255
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        // ---------- Kopf ----------
        RowLayout {
            id: head
            Layout.fillWidth: true
            // Desktop: Liste an der Kopfzeile ziehen = verschieben (wie unter Windows, ohne Bearbeitungsmodus).
            // Plasma verschiebt Widgets selbst erst nach langem Druecken. Ueber der Kopfzeile stellen wir seinen
            // Halter (ItemContainer) auf "schon beim Druecken" um; danach wieder zurueck.
            HoverHandler {
                id: headHover
                enabled: !view.inPanel && !Plasmoid.immutable
                cursorShape: Qt.SizeAllCursor
                onHoveredChanged: view.setDirectMove(hovered)
            }
            PC3.Label {
                text: "Todo"
                color: P.text
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.45 * Plasmoid.configuration.fontScale
                font.bold: true
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: view.app.openInObsidian() }
                PC3.ToolTip { text: view.app.obsidianOn ? "In Obsidian öffnen" : "Google Tasks öffnen" }
            }
            // Zahnrad: Einstellungen (wie unter Windows)
            Chip {
                iconButton: true
                // Zahnrad als Schriftzeichen (Breeze hat kein verlaessliches Zahnrad-Symbol); FE0E = nicht als Emoji
                text: "\u2699\uFE0E"
                fontScale: 1.35
                bold: false
                textColor: P.done
                Layout.leftMargin: Kirigami.Units.smallSpacing
                onClicked: view.app.openSettings()
            }
            Item { Layout.fillWidth: true }
            // nach dem Einblenden auf dem Desktop: sofort wieder ausblenden (in der Seitenleiste macht das das X)
            Chip {
                visible: view.app.revealed && !view.inPanel
                text: "Ausblenden"
                onClicked: view.app.hideReveal()
            }
            PC3.Label {
                text: view.app.configMissing ? "nicht eingerichtet"
                    : view.app.fileMissing ? "Datei fehlt"
                    : view.app.model ? view.app.model.openCount + " offen" : ""
                color: view.app.fileMissing || view.app.configMissing ? P.over : P.muted(Plasmoid.configuration.opacity <= 1)
                font.weight: Font.DemiBold
            }
            // Einklappen nur auf dem Desktop
            Chip {
                iconButton: true
                iconName: view.app.collapsed ? "arrow-down" : "arrow-up"
                visible: !view.inPanel
                textColor: P.done
                onClicked: view.app.collapsed = !view.app.collapsed
            }
            // in der Seitenleiste an derselben Stelle ein X: faehrt sie sofort hinaus (beendet auch das Einblenden)
            Chip {
                iconButton: true
                text: "✕"
                visible: view.inPanel
                textColor: P.done
                onClicked: view.app.hideReveal()
            }
        }

        PC3.Label {
            id: setupHint
            visible: view.app.configMissing && (!view.app.collapsed || view.inPanel)
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: P.note
            text: "Noch nicht eingerichtet – bitte das Task-Board-Setup ausführen."
        }

        // ---------- Punkte ----------
        ColumnLayout {
            id: rowsCol
            visible: (!view.app.collapsed || view.inPanel) && !view.app.configMissing
            Layout.fillWidth: true
            spacing: 0

            // Hinweis "weiter oben stehen noch Eintraege" (nur wenn geblaettert ist), Klick = eine Seite zurueck
            PC3.Label {
                id: upLabel
                readonly property int n: view.hiddenRows(true, flick.contentY, flick.height, rowsRep.count)
                visible: view.overflow && flick.contentY > 0
                Layout.fillWidth: true
                Layout.preferredHeight: view.indH
                Layout.leftMargin: Kirigami.Units.smallSpacing
                verticalAlignment: Text.AlignVCenter
                color: P.accent(Plasmoid.configuration.accent)
                font: Kirigami.Theme.smallFont
                text: "▴ " + Math.max(1, n) + " weitere"
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: view.scrollBy(-flick.height * 0.9) }
            }

            // die Zeilen: hoechstens so hoch wie Platz ist, der Rest per Mausrad
            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(rowsList.implicitHeight, view.rowsMax - (upLabel.visible ? view.indH : 0))
                contentWidth: width
                contentHeight: rowsList.implicitHeight
                clip: true
                // nicht mit der Maus ziehen (das ist zum Verschieben der Eintraege da), nur Mausrad
                interactive: false
                boundsBehavior: Flickable.StopAtBounds
                onContentHeightChanged: if (contentY > Math.max(0, contentHeight - height)) contentY = Math.max(0, contentHeight - height)

                ColumnLayout {
                    id: rowsList
                    width: flick.width
                    spacing: 0
                    Repeater {
                        id: rowsRep
                        model: view.app.rows
                        delegate: TaskRow {
                            Layout.fillWidth: true
                            app: view.app
                            row: modelData
                            list: view
                            rowIndex: index
                        }
                    }
                }
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: function (ev) {
                        view.scrollBy(ev.pixelDelta.y !== 0 ? -ev.pixelDelta.y : -ev.angleDelta.y / 120 * Kirigami.Units.gridUnit * 3);
                    }
                }
            }

            // Hinweis "weiter unten stehen noch Eintraege", Klick = eine Seite weiter
            PC3.Label {
                visible: view.overflow
                Layout.fillWidth: true
                Layout.preferredHeight: view.indH
                Layout.leftMargin: Kirigami.Units.smallSpacing
                verticalAlignment: Text.AlignVCenter
                color: P.accent(Plasmoid.configuration.accent)
                font: Kirigami.Theme.smallFont
                readonly property int n: view.hiddenRows(false, flick.contentY, flick.height, rowsRep.count)
                text: n > 0 ? "▾ " + n + " weitere" : ""
                HoverHandler { cursorShape: parent.n > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { onTapped: view.scrollBy(flick.height * 0.9) }
            }

            PC3.Label {
                id: moreLabel
                readonly property int hidden: view.app.model ? view.app.model.display.length - view.app.rows.length : 0
                visible: (view.app.model && view.app.model.display.length === 0) || hidden > 0
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.topMargin: Kirigami.Units.smallSpacing
                color: P.muted(Plasmoid.configuration.opacity <= 1)
                text: moreLabel.hidden > 0 ? "+ " + moreLabel.hidden + (view.app.obsidianOn ? " weitere in Obsidian" : " weitere bei Google") : "Alles erledigt"
                HoverHandler { cursorShape: moreLabel.hidden > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { onTapped: if (moreLabel.hidden > 0) view.app.openInObsidian() }
            }

            RowLayout {
                id: addRow
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                // als Knopf wie Zahnrad und Pfeil
                Chip {
                    iconButton: true
                    text: "+ Neuer Eintrag"
                    textColor: P.accent(Plasmoid.configuration.accent)
                    bold: true
                    onClicked: view.app.openForm(null)
                }
                Item { Layout.fillWidth: true }
                PC3.Label {
                    visible: view.app.model && view.app.model.doneCount > 0
                    text: "Erledigte archivieren"
                    color: P.muted(Plasmoid.configuration.opacity <= 1)
                    font: Kirigami.Theme.smallFont
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: view.app.cleanup() }
                }
            }
        }
    }
}
