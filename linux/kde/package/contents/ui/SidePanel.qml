// Seitenleiste wie unter Windows (src/sidebar.lua):
// - ein unsichtbarer, 1 Pixel schmaler Streifen am rechten (oder linken) Rand des Bildschirms, immer im Vordergrund
// - beruehrt die Maus den Rand, gleitet die Liste als Panel herein (bei "Kurz warten" erst, wenn sie dort bleibt)
// - verlaesst die Maus das Panel, gleitet es nach kurzer Zeit wieder hinaus; das X in der Liste oder ein
//   Wechsel in ein anderes Programm schiebt es sofort hinaus
// Bei "Beides" blendet die Liste auf dem Desktop dabei sanft aus (main.qml, deskOpacity) und danach wieder ein.
import QtQuick
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

Item {
    id: side
    property var app

    readonly property string mode: Plasmoid.configuration.mode
    readonly property bool active: mode === "sidebar" || mode === "both"
    readonly property bool onLeft: Plasmoid.configuration.side === "left"
    readonly property int margin: 8
    // Arbeitsbereich des Bildschirms (ohne Leisten), in globalen Koordinaten
    readonly property rect area: Plasmoid.containment && Plasmoid.containment.availableScreenRect.width > 0
        ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, Screen.width, Screen.height)
    readonly property int gx: Screen.virtualX + area.x
    readonly property int gy: Screen.virtualY + area.y
    readonly property int leaveMs: Plasmoid.configuration.speed === "fast" ? 300
        : Plasmoid.configuration.speed === "slow" ? 2000 : 1000
    // Vom Rand zur Liste: so lange bleibt sie offen, bis die Maus die Liste erreicht hat (frueher war das
    // Panel-Fenster dafuer bildschirmhoch - das fing aber alle Klicks auf den Desktop darunter ab)
    readonly property int graceMs: 1500

    property bool shown: false
    property bool revealing: false
    property bool mouseInside: false
    property bool wasInside: false      // seit dem Hereingleiten schon einmal in der Liste gewesen
    property double shownAt: 0
    property bool debugEdge: false      // nur fuer Tests: Streifen rot zeigen

    function show() {
        if (!active) return;
        leaveTimer.stop();
        if (!shown) {
            // frisch geoeffnet: oben anfangen, die Maus muss erst noch vom Rand zur Liste
            wasInside = mouseInside;
            shownAt = Date.now();
            panelView.scrollTop();
        }
        shown = true;
    }
    function hide() { leaveTimer.stop(); openTimer.stop(); jitterTimer.stop(); revealTimer.stop(); revealing = false; shown = false; }
    function leaveIn(ms) { leaveTimer.interval = ms; leaveTimer.restart(); }
    // Maus am Rand
    // solange die Maus am Rand bleibt, bleibt die Liste offen; erst wenn sie Rand und Liste verlaesst, hinaus
    property bool onEdge: false
    function edgeHit() {
        onEdge = true;
        leaveTimer.stop();
        jitterTimer.stop();
        // laeuft die Wartezeit schon, nicht neu anfangen (Zittern, s. jitterTimer)
        if (!shown && Plasmoid.configuration.openDelay > 0) { if (!openTimer.running) openTimer.start(); }
        else show();
    }
    function edgeLeft() {
        onEdge = false;
        if (openTimer.running) jitterTimer.restart();
        if (shown && !mouseInside && !revealing) leaveIn(wasInside ? leaveMs : Math.max(graceMs, leaveMs));
    }
    function enter() { mouseInside = true; wasInside = true; leaveTimer.stop(); }
    function leave() { mouseInside = false; if (shown && !revealing && !onEdge) leaveIn(leaveMs); }
    // Einblenden (Anmelden/Aufwachen/Entsperren) fuer so viele Sekunden
    function reveal(seconds) {
        if (!active) return;
        revealing = true;
        show();
        revealTimer.interval = seconds * 1000;
        revealTimer.restart();
    }
    function revealEnd() { revealing = false; if (!mouseInside && !onEdge) leaveIn(leaveMs); }

    onActiveChanged: { if (!active) hide(); placeEdge(); }
    onOnLeftChanged: placeEdge()
    onAreaChanged: placeEdge()
    // Plasma uebernimmt die Position eines offenen Fensters erst beim naechsten Erscheinen:
    // Streifen kurz ausblenden und an der neuen Stelle wieder zeigen
    function placeEdge() {
        edge.visible = false;
        if (active) edgeTimer.restart();
    }
    Timer { id: edgeTimer; interval: 50; onTriggered: edge.visible = side.active }
    Component.onCompleted: placeEdge()

    // ---------- Animation (selbst gemacht wie unter Windows; KWins Gleiten ist nicht ueberall an) ----------
    // slide: 0 = draussen, 1 = ganz drin. Dauer je nach Tempo.
    readonly property int slideMs: Plasmoid.configuration.speed === "fast" ? 130
        : Plasmoid.configuration.speed === "slow" ? 380 : 220
    property real slide: 0
    Behavior on slide {
        NumberAnimation { duration: side.slideMs; easing.type: side.shown ? Easing.OutCubic : Easing.InCubic }
    }
    onShownChanged: slide = shown ? 1 : 0

    Timer {
        id: leaveTimer
        interval: side.leaveMs
        // waehrend in der Liste getippt wird oder ein Dateidialog offen ist, nicht wegfahren
        onTriggered: if (side.app.editing) restart(); else if (!side.mouseInside && !side.onEdge && !side.revealing) side.shown = false
    }
    Timer { id: revealTimer; onTriggered: side.revealEnd() }
    // "Kurz warten": erst hereingleiten, wenn die Maus so lange am Rand geblieben ist
    Timer { id: openTimer; interval: Math.max(1, Plasmoid.configuration.openDelay); onTriggered: if (side.onEdge || jitterTimer.running) side.show() }
    // Der Streifen ist 1 Pixel breit: zittert die Hand ein Pixel nach links, gilt die Maus als weg vom Rand. Erst
    // wenn sie laenger als 150 ms weg ist, bricht die Wartezeit ab.
    Timer { id: jitterTimer; interval: 150; onTriggered: if (!side.onEdge) openTimer.stop() }

    // ---------- anderes Programm aktiv (Klick in sein Fenster, Alt+Tab): sofort hinaus ----------
    Loader {
        id: activeWatch
        active: side.active
        source: "ActiveWindowWatch.qml"
    }
    Connections {
        target: activeWatch.item
        ignoreUnknownSignals: true
        function onOtherAppActivated() {
            // die ersten 2 Sekunden nicht: beim Anmelden holen sich startende Programme selbst den Fokus
            if (!side.shown || side.app.editing || Date.now() - side.shownAt < 2000) return;
            side.app.hideReveal();
        }
    }

    // ---------- Rand-Streifen ----------
    PlasmaCore.Dialog {
        id: edge
        visible: false
        type: PlasmaCore.Dialog.Notification
        // kein Qt.WindowStaysOnTopHint: damit macht libplasma ein Dock-Fenster daraus, das KWin beim
        // Abmelden nicht schliessen kann ("Plasma-Arbeitsflaechenbereich hat sich nicht beendet").
        // Als Benachrichtigungs-Fenster liegt es trotzdem ueber normalen Fenstern.
        flags: Qt.WindowDoesNotAcceptFocus | Qt.FramelessWindowHint
        location: PlasmaCore.Types.Floating
        backgroundHints: PlasmaCore.Types.NoBackground
        hideOnWindowDeactivate: false
        x: side.onLeft ? side.gx : side.gx + side.area.width - 1
        // nur der mittlere Teil des Rands: oben und unten je 20 % frei (Ecken loesen nichts aus)
        y: side.gy + Math.floor(side.area.height * 0.2)
        mainItem: Item {
            width: 1
            height: side.area.height - 2 * Math.floor(side.area.height * 0.2)
            // fast durchsichtig: ganz durchsichtige Flaechen bemerkt die Maus nicht ueberall
            Rectangle { anchors.fill: parent; color: side.debugEdge ? "red" : "#02000000" }
            HoverHandler { onHoveredChanged: hovered ? side.edgeHit() : side.edgeLeft() }
        }
    }

    // ---------- Panel ----------
    // Das Fenster reicht bis an den Bildschirmrand; darin gleitet die Liste von aussen herein.
    // Es ist nur so hoch wie die Liste: darunter gehen Klicks auf den Desktop bzw. die Fenster dahinter.
    readonly property int panelW: Plasmoid.configuration.listWidth + margin
    readonly property int maxH: side.area.height - 2 * side.margin
    readonly property Item panelItem: panel.mainItem   // nur fuer Tests (Bild der Liste)
    readonly property Item panelList: panelView         // nur fuer Tests (Blaettern)
    PlasmaCore.Dialog {
        id: panel
        visible: side.shown || side.slide > 0
        type: PlasmaCore.Dialog.Notification
        // kein Qt.WindowStaysOnTopHint, siehe Rand-Streifen
        flags: Qt.FramelessWindowHint
        location: PlasmaCore.Types.Floating
        backgroundHints: PlasmaCore.Types.NoBackground
        hideOnWindowDeactivate: false
        x: side.onLeft ? side.gx : side.gx + side.area.width - side.panelW
        y: side.gy + side.margin
        mainItem: Item {
            width: side.panelW
            height: Math.max(1, Math.min(panelView.implicitHeight, side.maxH))
            clip: true
            // ganzes Panel-Fenster (Liste und der schmale Streifen bis zum Bildschirmrand) zaehlt als "Maus in der Liste"
            HoverHandler { onHoveredChanged: hovered ? side.enter() : side.leave() }
            TodoView {
                id: panelView
                width: Plasmoid.configuration.listWidth
                height: Math.min(implicitHeight, parent.height)
                maxHeight: side.maxH
                // drin: margin vom Rand; draussen: ganz hinter dem Rand
                x: side.onLeft
                    ? side.margin - (Plasmoid.configuration.listWidth + side.margin) * (1 - side.slide)
                    : (Plasmoid.configuration.listWidth + side.margin) * (1 - side.slide)
                app: side.app
                inPanel: true
            }
        }
    }
}
