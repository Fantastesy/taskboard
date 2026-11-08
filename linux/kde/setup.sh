#!/usr/bin/env bash
# Task Board (frueher Obsidian Todo) - Setup fuer KDE Plasma 6 (alle Distributionen)
#
#   chmod +x TaskBoard-KDE-Setup.sh && ./TaskBoard-KDE-Setup.sh
#
# Optionen:
#   --silent      Update ohne Rueckfragen (nutzt die gespeicherte Einrichtung)
#   --restart     mit --silent: Plasma danach neu starten, damit die neue Version sofort geladen wird
#   --uninstall   Widget entfernen (Todo.md und Archiv bleiben erhalten), --yes ohne Rueckfrage
#   --mode sidebar|desktop|both Anzeige umschalten: Seitenleiste, Desktop oder beides (sonst im Zahnrad-Fenster)
#
# Das fertige Setup enthaelt das Widget als Anhang (siehe linux/build-kde.sh).
set -u

APP="Task Board"
PLUGIN_ID="io.github.fantastesy.taskboard"
SHORTCUT="Meta+Shift+T"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/taskboard"
CONF="$CONF_DIR/config"
GCONF="$CONF_DIR/google"     # Google Tasks / Obsidian an-aus (schreibt das Setup beim ersten Einrichten, danach das Zahnrad)
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/taskboard"
PLASMOID_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$PLUGIN_ID"
LOG="${TMPDIR:-/tmp}/taskboard-setup.log"
SILENT=0
UNINSTALL=0
YES=0
RESTART=0
SET_MODE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --silent) SILENT=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --yes) YES=1 ;;
        --restart) RESTART=1 ;;
        --mode) SET_MODE="${2:-}"; shift ;;
    esac
    shift
done
MENU_ENTRY="${XDG_DATA_HOME:-$HOME/.local/share}/applications/taskboard-uninstall.desktop"
# Namen bis 1.3.0 (Obsidian Todo) - werden beim Setup/Update umgezogen (migrate_files, migrate_widget)
OLD_ID="io.github.fantastesy.obsidiantodo"
OLD_CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/obsidian-todo"
OLD_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/obsidian-todo"
OLD_PLASMOID_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$OLD_ID"
OLD_MENU_ENTRY="${XDG_DATA_HOME:-$HOME/.local/share}/applications/obsidian-todo-uninstall.desktop"

log() { printf '%s %s\n' "$(date +%FT%T)" "$*" >> "$LOG"; }

# ---------- Umzug von Obsidian Todo (bis 1.3.0) ----------
# Ordner: Einrichtung (config) und Update-Dateien unter neuem Namen weiterverwenden
migrate_files() {
    if [ -d "$OLD_CONF_DIR" ]; then
        if [ ! -f "$CONF_DIR/config" ]; then
            mkdir -p "$(dirname "$CONF_DIR")" && rm -rf "$CONF_DIR" && mv "$OLD_CONF_DIR" "$CONF_DIR" && log "Umzug: $OLD_CONF_DIR -> $CONF_DIR"
        else
            rm -rf "$OLD_CONF_DIR"
        fi
    fi
    if [ -d "$OLD_DATA_DIR" ]; then
        mkdir -p "$DATA_DIR"
        for f in last-update-check update.log; do
            [ -f "$OLD_DATA_DIR/$f" ] && [ ! -f "$DATA_DIR/$f" ] && cp "$OLD_DATA_DIR/$f" "$DATA_DIR/$f"
        done
        rm -rf "$OLD_DATA_DIR" && log "Umzug: $OLD_DATA_DIR entfernt"
    fi
    rm -f "$OLD_MENU_ENTRY" "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/obsidian-todo-update.desktop"
}
# Widget: altes Widget (alte ID) gegen ein neues mit neuer ID tauschen - an derselben Stelle, mit allen Einstellungen
# und dem Tastenkuerzel. Zwei Schritte: (1) alles auslesen, in einer Datei sichern, altes Widget entfernen;
# (2) ein paar Sekunden spaeter das neue anlegen. In einem Schritt ordnet Plasma 6.6 das neue Widget danach neu an
# und verschiebt es (Test 07.11.2026); nachtraegliches Setzen von geometry ignoriert Plasma ganz.
# Bricht Schritt 2 ab, holt das naechste Setup ihn aus der Datei nach. Das alte Paket wird erst danach geloescht.
MIGRATE_FILE="$CONF_DIR/widget-umzug.json"
migrate_widget() {
    [ -d "$OLD_PLASMOID_DIR" ] || [ -f "$MIGRATE_FILE" ] || return 0
    local out json
    if [ ! -f "$MIGRATE_FILE" ]; then
        out="$(plasma_query "
var oldId = '$OLD_ID', list = [];
function readAll(w, path, depth, res) {
    w.currentConfigGroup = path;
    var keys = w.configKeys, groups = w.configGroups;
    keys.forEach(function (k) { res.push([path, k, String(w.readConfig(k, ''))]); });
    if (depth < 3) groups.forEach(function (g) { readAll(w, path.concat([g]), depth + 1, res); });
    return res;
}
var ds = desktops();
for (var i = 0; i < ds.length; i++) {
    ds[i].widgets(oldId).forEach(function (w) {
        var g = w.geometry;
        list.push({ desk: i, x: g.x, y: g.y, w: g.width, h: g.height, sc: String(w.globalShortcut || ''), conf: readAll(w, [], 0, []) });
    });
}
// ganz alte Versionen (bis 1.1): eigene Leiste am Rand
var panel = false;
panels().forEach(function (p) { if (p.widgets(oldId).length) panel = true; });
print('MIGRATE=' + JSON.stringify({ list: list, panel: panel }) + '#ENDE');")"
        json="$(printf '%s' "$out" | tr -d '\n' | grep -o 'MIGRATE=.*#ENDE' | sed 's/^MIGRATE=//; s/#ENDE$//')"
        [ -n "$json" ] || { log "Umzug: Widget nicht auslesbar (Plasma nicht erreichbar) - naechstes Mal"; return 1; }
        mkdir -p "$CONF_DIR"; printf '%s\n' "$json" > "$MIGRATE_FILE"
        plasma_script "
var oldId = '$OLD_ID';
desktops().forEach(function (d) { d.widgets(oldId).forEach(function (w) { w.globalShortcut = ''; w.remove(); }); });
panels().forEach(function (p) {
    var ours = p.widgets(oldId);
    if (!ours.length) return;
    var others = p.widgets().length - ours.length;
    ours.forEach(function (x) { x.remove(); });
    if (others === 0) p.remove();
});" || { log "Umzug: altes Widget nicht entfernbar"; rm -f "$MIGRATE_FILE"; return 1; }
        sleep 3
    fi
    json="$(cat "$MIGRATE_FILE")"
    plasma_script "
var data = $json, newId = '$PLUGIN_ID', oldId = '$OLD_ID', ds = desktops();
data.list.forEach(function (m) {
    var d = ds[m.desk] || ds[0];
    // Position beim Anlegen mitgeben
    var n = d.addWidget(newId, m.x, m.y, m.w, m.h);
    if (!n) n = d.addWidget(oldId, m.x, m.y, m.w, m.h);   // neues Paket nicht ladbar: altes zuruecksetzen
    if (!n) return;
    m.conf.forEach(function (c) { n.currentConfigGroup = c[0]; n.writeConfig(c[1], c[2]); });
    n.currentConfigGroup = ['General'];
    if (m.sc) n.globalShortcut = m.sc;
    n.reloadConfig();
});
var have = false;
ds.forEach(function (d) { if (d.widgets(newId).length || d.widgets(oldId).length) have = true; });
if (data.panel && !have) {
    var d = ds[0];
    for (var i = 0; i < ds.length; i++) if (ds[i].screen === 0) d = ds[i];
    var g = screenGeometry(d.screen);
    var w = d.addWidget(newId, g.width - 520, 60, 480, 560);
    w.globalShortcut = '$SHORTCUT';
    w.currentConfigGroup = ['General'];
    w.writeConfig('mode', 'sidebar');
}" || { log "Umzug: neues Widget nicht angelegt (Plasma nicht erreichbar) - naechstes Mal aus $MIGRATE_FILE"; return 1; }
    rm -f "$MIGRATE_FILE"
    # altes Paket nur loeschen, wenn wirklich kein altes Widget mehr da ist
    out="$(plasma_query "var n = 0; desktops().forEach(function (d) { n += d.widgets('$OLD_ID').length; }); print('LEFT=' + n);")"
    case "$out" in *LEFT=0*) ;; *) log "Umzug: altes Widget noch da ($out) - altes Paket bleibt"; return 1 ;; esac
    if command -v kpackagetool6 >/dev/null 2>&1; then kpackagetool6 -t Plasma/Applet -r "$OLD_ID" >>"$LOG" 2>&1 || rm -rf "$OLD_PLASMOID_DIR"
    else rm -rf "$OLD_PLASMOID_DIR"; fi
    log "Umzug: Widget $OLD_ID -> $PLUGIN_ID"
}

# ---------- Dialoge (kdialog, sonst Terminal) ----------
HAVE_KDIALOG=0; command -v kdialog >/dev/null 2>&1 && [ -z "${TASKBOARD_NO_GUI:-}" ] && HAVE_KDIALOG=1
info() {
    log "INFO $1"
    [ "$SILENT" = 1 ] && return
    if [ "$HAVE_KDIALOG" = 1 ]; then kdialog --title "$APP" --msgbox "$1"; else printf '\n%s\n' "$1"; fi
}
fail() {
    log "FEHLER $1"
    if [ "$SILENT" = 1 ]; then
        command -v notify-send >/dev/null 2>&1 && notify-send -a "$APP" "Update fehlgeschlagen" "$1"
    elif [ "$HAVE_KDIALOG" = 1 ]; then kdialog --title "$APP" --error "$1"
    else printf '\nFEHLER: %s\n' "$1" >&2; fi
    exit 1
}
ask_yesno() {   # $1 Frage -> 0 = ja
    if [ "$HAVE_KDIALOG" = 1 ]; then kdialog --title "$APP" --yesno "$1"; return $?; fi
    local r; read -r -p "$1 [J/n] " r; [ -z "$r" ] || [ "$r" = j ] || [ "$r" = J ] || [ "$r" = y ]
}
ask_dir() {     # $1 Titel, $2 Startordner -> Ordner auf stdout
    if [ "$HAVE_KDIALOG" = 1 ]; then kdialog --title "$1" --getexistingdirectory "$2"; return $?; fi
    local r; read -r -p "$1 [$2]: " r; printf '%s\n' "${r:-$2}"
}
progress() {    # kurze Statusmeldung
    log "$1"
    [ "$SILENT" = 1 ] && return
    if [ "$HAVE_KDIALOG" = 1 ]; then kdialog --title "$APP" --passivepopup "$1" 8 >/dev/null 2>&1 & else printf '%s\n' "$1"; fi
}

# ---------- Werkzeuge ----------
download() {    # $1 URL, $2 Ziel
    if command -v curl >/dev/null 2>&1; then curl -fsSL -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then wget -q -O "$2" "$1"
    else return 1; fi
}
fetch() {       # $1 URL -> stdout
    if command -v curl >/dev/null 2>&1; then curl -fsSL -H "User-Agent: TaskBoard-Setup" "$1"
    else wget -q -O - --header="User-Agent: TaskBoard-Setup" "$1"; fi
}
# Plasma-Skript ueber D-Bus ausfuehren (qdbus6, qdbus oder gdbus - je nach Distribution)
plasma_script() {
    local s="$1"
    for q in qdbus6 qdbus-qt6 qdbus; do
        if command -v "$q" >/dev/null 2>&1; then
            "$q" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$s" >/dev/null 2>&1 && return 0
        fi
    done
    if command -v gdbus >/dev/null 2>&1; then
        gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
            --method org.kde.PlasmaShell.evaluateScript "$s" >/dev/null 2>&1 && return 0
    fi
    return 1
}
# wie plasma_script, gibt aber die Ausgabe (print) des Skripts zurueck
plasma_query() {
    local s="$1"
    for q in qdbus6 qdbus-qt6 qdbus; do
        if command -v "$q" >/dev/null 2>&1; then
            "$q" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$s" 2>/dev/null && return 0
        fi
    done
    command -v gdbus >/dev/null 2>&1 && gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
        --method org.kde.PlasmaShell.evaluateScript "$s" 2>/dev/null
}

# ---------- Widget-Paket finden (Anhang dieses Skripts oder Entwicklerordner) ----------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SELF="$(readlink -f "$0")"
if grep -q '^__PAYLOAD_BELOW__$' "$SELF" 2>/dev/null; then
    sed -n '/^__PAYLOAD_BELOW__$/,$p' "$SELF" | tail -n +2 | base64 -d | tar -xz -C "$WORK" || fail "Das Setup ist beschädigt. Bitte neu herunterladen."
    PKG="$WORK/package"; UPD="$WORK/update.sh"; GPY="$WORK/google-sync.py"; VERSION="$(cat "$WORK/version.txt")"; REPO="$(cat "$WORK/repo.txt")"
else
    here="$(dirname "$SELF")"
    PKG="$here/package"; UPD="$here/update.sh"; GPY="$here/google-sync.py"; VERSION="dev"; REPO=""
fi
GCLIENT="$(dirname "$GPY")/google-client.json"     # Zugang des Programms zu Google (fehlt in Entwicklerfassungen)
[ -f "$PKG/metadata.json" ] || fail "Widget-Dateien nicht gefunden."

# ---------- Anzeige einrichten: Seitenleiste, Desktop oder beides ----------
# Seit 1.2.0 liegt das Widget immer auf dem Desktop des Hauptbildschirms; die Seitenleiste (Streifen am Rand +
# bildschirmhohes Panel) macht das Widget selbst. Die Anzeige steht in den Widget-Einstellungen (mode).
# Alte Versionen hatten eine eigene KDE-Leiste am rechten Rand - die wird hier entfernt.
#   $1 = sidebar|desktop|both (panel = alter Name fuer sidebar), $2 = 1: nur umbauen, wenn noch eine alte Leiste da ist
apply_mode() {
    local m="$1"
    [ "$m" = panel ] && m=sidebar
    case "$m" in sidebar|desktop|both) ;; *) return 1 ;; esac
    plasma_script "
var id = '$PLUGIN_ID', mode = '$m', onlyMigrate = '${2:-0}' === '1', hadPanel = false, w = null;
panels().forEach(function (p) {
    var ours = p.widgets(id);
    if (!ours.length) return;
    hadPanel = true;
    var others = p.widgets().length - ours.length;
    ours.forEach(function (x) { x.remove(); });
    if (others === 0) p.remove();
});
if (!(onlyMigrate && !hadPanel)) {
    desktops().forEach(function (d) { d.widgets(id).forEach(function (x) { if (!w) w = x; else x.remove(); }); });
    if (!w) {
        var d = desktops()[0];
        for (var i = 0; i < desktops().length; i++) if (desktops()[i].screen === 0) d = desktops()[i];
        var g = screenGeometry(d.screen);
        w = d.addWidget(id, g.width - 520, 60, 480, 560);   // Position beim Anlegen (geometry setzen wirkt nicht)
        w.globalShortcut = '$SHORTCUT';
    }
    w.currentConfigGroup = ['General'];
    w.writeConfig('mode', mode);
}"
}
set_conf() {   # $1 Schluessel, $2 Wert
    [ -f "$CONF" ] || return
    if grep -q "^$1=" "$CONF"; then sed -i "s|^$1=.*|$1=$2|" "$CONF"; else printf '%s=%s\n' "$1" "$2" >> "$CONF"; fi
}

# Ordner von Obsidian Todo (bis 1.3.0) uebernehmen - vor allem anderen, damit die gespeicherte Einrichtung gefunden wird
migrate_files

# ---------- Deinstallieren ----------
if [ "$UNINSTALL" = 1 ]; then
    if [ "$YES" = 0 ] && [ "$SILENT" = 0 ]; then
        ask_yesno "$APP wirklich entfernen?

Deine Todo.md und das Archiv bleiben erhalten." || exit 0
    fi
    plasma_script "
['$PLUGIN_ID', '$OLD_ID'].forEach(function (id) {
    panels().forEach(function (p) {
        var ours = p.widgets(id);
        if (!ours.length) return;
        var others = p.widgets().length - ours.length;
        ours.forEach(function (w) { w.remove(); });
        if (others === 0) p.remove();
    });
    desktops().forEach(function (d) { d.widgets(id).forEach(function (w) { w.remove(); }); });
});"
    kpackagetool6 -t Plasma/Applet -r "$PLUGIN_ID" >/dev/null 2>&1 || rm -rf "$PLASMOID_DIR"
    kpackagetool6 -t Plasma/Applet -r "$OLD_ID" >/dev/null 2>&1 || rm -rf "$OLD_PLASMOID_DIR"
    # Google-Verbindung trennen (bei Google widerrufen, Schluessel loeschen)
    if [ -f "$DATA_DIR/google-sync.py" ] && [ -f "$CONF_DIR/google-token.json" ] && command -v python3 >/dev/null 2>&1; then
        python3 "$DATA_DIR/google-sync.py" logout >/dev/null 2>&1
    fi
    # Programmdaten weg - eine Todo.md/Archiv von "nur Google" und Sicherungen bleiben (wie beim Vault: nichts geht verloren)
    if [ -d "$DATA_DIR" ]; then
        find "$DATA_DIR" -mindepth 1 -maxdepth 1 ! -name Todo.md ! -name Todo-Archiv.md ! -name Sicherung -exec rm -rf {} +
        rmdir "$DATA_DIR" 2>/dev/null
    fi
    rm -rf "$CONF_DIR"
    rm -f "$MENU_ENTRY" "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/taskboard-update.desktop"
    info "$APP wurde entfernt. Deine Todo.md und das Archiv sind noch da."
    exit 0
fi

# ---------- Nur Anzeige umschalten (Rechtsklick-Menue des Widgets) ----------
if [ -n "$SET_MODE" ]; then
    [ -f "$CONF" ] || fail "$APP ist noch nicht eingerichtet."
    case "$SET_MODE" in panel|sidebar|desktop|both) ;; *) fail "Unbekannte Anzeige: $SET_MODE (sidebar, desktop oder both)." ;; esac
    apply_mode "$SET_MODE" || fail "KDE Plasma hat die Änderung nicht angenommen. Bitte später noch einmal versuchen."
    set_conf MODE "$SET_MODE"
    exit 0
fi

# ---------- Voraussetzungen ----------
case "${XDG_CURRENT_DESKTOP:-}" in
    *KDE*) ;;
    *) [ "$SILENT" = 1 ] || fail "Dieses Setup ist für KDE Plasma. Erkannt wurde: ${XDG_CURRENT_DESKTOP:-unbekannt}." ;;
esac
# jede Plasma-Sitzung setzt KDE_SESSION_VERSION; sonst plasmashell ohne Grafik fragen
PLASMA_VER="${KDE_SESSION_VERSION:-}"
if [ -z "$PLASMA_VER" ] && command -v plasmashell >/dev/null 2>&1; then
    # ohne Sitzung (z. B. per SSH): an der verlinkten Plasma-Bibliothek erkennen
    # Plasma 6 und neuer bauen auf Qt 6 auf (libPlasma selbst zaehlt eigene Versionen)
    ldd "$(command -v plasmashell)" 2>/dev/null | grep -q 'libQt6Core\.so' && PLASMA_VER=6
fi
[ "${PLASMA_VER%%.*}" -ge 6 ] 2>/dev/null || fail "Benötigt KDE Plasma 6 (gefunden: ${PLASMA_VER:-keins})."
# kpackagetool6 ist nicht ueberall installiert (z. B. Kubuntu) - dann wird das Widget direkt kopiert
HAVE_KPT=0; command -v kpackagetool6 >/dev/null 2>&1 && HAVE_KPT=1

# ---------- Obsidian finden ----------
OBS_CONFIGS=(
    "${XDG_CONFIG_HOME:-$HOME/.config}/obsidian/obsidian.json"
    "$HOME/.var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json"
    "$HOME/snap/obsidian/current/.config/obsidian/obsidian.json"
)
obsidian_installed() {
    command -v obsidian >/dev/null 2>&1 && return 0
    command -v flatpak >/dev/null 2>&1 && flatpak info md.obsidian.Obsidian >/dev/null 2>&1 && return 0
    [ -d /snap/obsidian ] && return 0
    ls "$HOME"/Applications/Obsidian*.AppImage "$HOME"/.local/bin/Obsidian*.AppImage >/dev/null 2>&1 && return 0
    command -v xdg-mime >/dev/null 2>&1 && [ -n "$(xdg-mime query default x-scheme-handler/obsidian 2>/dev/null)" ] && return 0
    return 1
}
# alle bekannten Vaults (Pfad je Zeile)
list_vaults() {
    for f in "${OBS_CONFIGS[@]}"; do
        [ -f "$f" ] || continue
        if command -v python3 >/dev/null 2>&1; then
            python3 -c 'import json,sys
for v in json.load(open(sys.argv[1])).get("vaults",{}).values():
    p=v.get("path")
    if p: print(p)' "$f" 2>/dev/null
        else
            grep -o '"path":"[^"]*"' "$f" | sed 's/^"path":"//; s/"$//; s/\\\//\//g; s/\\\\/\\/g'
        fi
    done | while IFS= read -r p; do [ -d "$p" ] && printf '%s\n' "$p"; done | sort -u
}
# Vault in obsidian.json eintragen (Flatpak-Obsidian hat eine eigene Datei)
register_vault() {
    local vault="$1" f
    if command -v flatpak >/dev/null 2>&1 && flatpak info md.obsidian.Obsidian >/dev/null 2>&1; then f="${OBS_CONFIGS[1]}"
    elif [ -d /snap/obsidian ]; then f="${OBS_CONFIGS[2]}"
    else f="${OBS_CONFIGS[0]}"; fi
    mkdir -p "$(dirname "$f")"
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$f" "$vault" <<'PY'
import json, os, secrets, sys, time
f, vault = sys.argv[1], sys.argv[2].rstrip('/')
data = {}
if os.path.exists(f):
    try: data = json.load(open(f))
    except Exception: data = {}
vaults = data.setdefault('vaults', {})
if not any(v.get('path', '').rstrip('/') == vault for v in vaults.values()):
    vaults[secrets.token_hex(8)] = {'path': vault, 'ts': int(time.time() * 1000)}
    json.dump(data, open(f, 'w'))
PY
    elif [ ! -f "$f" ]; then
        printf '{"vaults":{"%s":{"path":"%s","ts":%s000}}}' "$(head -c8 /dev/urandom | od -An -tx1 | tr -d ' \n')" "$vault" "$(date +%s)" > "$f"
    else
        log "obsidian.json nicht geaendert (python3 fehlt)"
    fi
}
install_obsidian() {
    if command -v flatpak >/dev/null 2>&1; then
        progress "Obsidian wird über Flatpak installiert …"
        flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >>"$LOG" 2>&1
        flatpak install --user -y --noninteractive flathub md.obsidian.Obsidian >>"$LOG" 2>&1 && return 0
    fi
    # sonst offizielles AppImage nach ~/Applications
    progress "Obsidian wird heruntergeladen …"
    local arch pat url
    arch="$(uname -m)"
    if [ "$arch" = aarch64 ]; then pat='Obsidian-[0-9.]*-arm64\.AppImage'; else pat='Obsidian-[0-9.]*\.AppImage'; fi
    url="$(fetch https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest | grep -o "\"browser_download_url\": *\"[^\"]*/$pat\"" | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')"
    [ -n "$url" ] || return 1
    mkdir -p "$HOME/Applications" "$HOME/.local/share/applications"
    download "$url" "$HOME/Applications/Obsidian.AppImage" || return 1
    chmod +x "$HOME/Applications/Obsidian.AppImage"
    cat > "$HOME/.local/share/applications/obsidian.desktop" <<EOF
[Desktop Entry]
Name=Obsidian
Exec="$HOME/Applications/Obsidian.AppImage" --no-sandbox %u
Type=Application
Icon=obsidian
Terminal=false
MimeType=x-scheme-handler/obsidian;
Categories=Office;
EOF
    command -v xdg-mime >/dev/null 2>&1 && xdg-mime default obsidian.desktop x-scheme-handler/obsidian
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1
    return 0
}

# ---------- Einrichtung waehlen ----------
VAULT=""; TODO_DIR=""; MODE=""
if [ -f "$CONF" ]; then
    VAULT="$(sed -n 's/^VAULT=//p' "$CONF")"
    TODO_DIR="$(dirname "$(sed -n 's/^TODO_FILE=//p' "$CONF")")"
    MODE="$(sed -n 's/^MODE=//p' "$CONF")"
fi
# Speicherort: beim ersten Einrichten waehlbar; "nur Google" bleibt bei spaeteren Laeufen, wie es ist
FRESH=0; [ -f "$CONF" ] || FRESH=1
USE_OBSIDIAN=1; GOOGLE_LIST=""; GOOGLE_LIST_NAME=""
[ -f "$GCONF" ] && grep -q '^OBSIDIAN_ON=0' "$GCONF" && USE_OBSIDIAN=0
if [ -f "$GCONF" ] && grep -q '^GOOGLE_ON=1' "$GCONF"; then
    GOOGLE_LIST="$(sed -n 's/^GOOGLE_LIST=//p' "$GCONF")"
    GOOGLE_LIST_NAME="$(sed -n 's/^GOOGLE_LIST_NAME=//p' "$GCONF")"
fi

if [ "$SILENT" = 0 ]; then
    info "Willkommen bei $APP!

Damit bekommst du eine Todo-Liste als KDE-Widget – gespeichert in deinem Obsidian-Vault, in Google Tasks oder in beiden."

    # zwei Haekchen, mindestens eins
    while [ "$FRESH" = 1 ]; do
        if [ "$HAVE_KDIALOG" = 1 ]; then
            sel="$(kdialog --title "$APP" --checklist "Wo sollen deine Aufgaben gespeichert werden?

Beides angehakt: Die Liste wird in beide Richtungen abgeglichen – was du in Obsidian änderst, landet bei Google, und was du am Handy änderst, steht danach auch in Obsidian. Später umstellbar im Zahnrad neben „Todo“." \
                obsidian "Obsidian – als Todo.md in deinem Vault" on \
                google "Google Tasks – auch am Handy, Anmeldung mit deinem Google-Konto" off)" || exit 0
        else
            sel=""
            read -r -p "In Obsidian speichern? [J/n] " r; case "$r" in n*|N*) ;; *) sel="obsidian" ;; esac
            read -r -p "In Google Tasks speichern? [j/N] " r; case "$r" in j*|J*|y*) sel="$sel google" ;; esac
        fi
        case "$sel" in *obsidian*) USE_OBSIDIAN=1 ;; *) USE_OBSIDIAN=0 ;; esac
        case "$sel" in
            *google*)
                if ! command -v python3 >/dev/null 2>&1; then
                    info "Für Google Tasks wird Python 3 gebraucht (Paket python3). Bitte installieren und das Setup noch einmal starten."
                    continue
                fi
                if [ ! -f "$GCLIENT" ]; then
                    info "Diese Fassung enthält keinen Google-Zugang. Bitte die fertige Version von GitHub nehmen."
                    continue
                fi
                if python3 "$GPY" connect --out "$WORK/google-list" >>"$LOG" 2>&1; then
                    GOOGLE_LIST="$(cut -f1 "$WORK/google-list")"
                    GOOGLE_LIST_NAME="$(cut -f2 "$WORK/google-list")"
                else
                    [ "$USE_OBSIDIAN" = 1 ] && ask_yesno "Die Anmeldung bei Google hat nicht geklappt.

Ohne Google weiter? Du kannst Google später im Zahnrad neben „Todo“ verbinden." && break
                    continue
                fi
                ;;
            *obsidian*) ;;
            *)
                info "Bitte mindestens einen Speicherort anhaken."
                continue
                ;;
        esac
        break
    done

    if [ "$USE_OBSIDIAN" = 1 ]; then
    if ! obsidian_installed; then
        if ask_yesno "Obsidian ist nicht installiert. Soll es mitinstalliert werden?

(Die Todo-Liste funktioniert auch ohne – du kannst sie dann nur nicht in Obsidian öffnen.)"; then
            install_obsidian || info "Obsidian konnte nicht installiert werden. Du kannst es später von obsidian.md installieren."
        fi
    fi

    mapfile -t VAULTS < <(list_vaults)
    CHOICE="__new__"
    if [ "${#VAULTS[@]}" -gt 0 ]; then
        if [ "$HAVE_KDIALOG" = 1 ]; then
            args=()
            for i in "${!VAULTS[@]}"; do
                st=off; { [ "${VAULTS[$i]}" = "$VAULT" ] || { [ -z "$VAULT" ] && [ "$i" = 0 ]; }; } && st=on
                args+=("$i" "${VAULTS[$i]}" "$st")
            done
            args+=("__new__" "Neuen Vault anlegen" off)
            CHOICE="$(kdialog --title "$APP" --radiolist "In welchem Obsidian-Vault soll die Todo-Liste gespeichert werden?" "${args[@]}")" || exit 0
        else
            printf 'Gefundene Vaults:\n'; for i in "${!VAULTS[@]}"; do printf '  %s) %s\n' "$i" "${VAULTS[$i]}"; done
            read -r -p "Nummer wählen (leer = neuer Vault): " CHOICE; [ -z "$CHOICE" ] && CHOICE="__new__"
        fi
    fi
    if [ "$CHOICE" = "__new__" ]; then
        docs="$(xdg-user-dir DOCUMENTS 2>/dev/null || echo "$HOME/Documents")"
        mkdir -p "$docs/Obsidian Vault"
        VAULT="$(ask_dir "Ordner für den neuen Vault wählen" "$docs/Obsidian Vault")" || exit 0
        [ -n "$VAULT" ] || exit 0
        mkdir -p "$VAULT/.obsidian"
        rmdir "$docs/Obsidian Vault" 2>/dev/null   # nur weg, wenn ungenutzt und leer
        NEW_VAULT=1
    else
        VAULT="${VAULTS[$CHOICE]}"
        NEW_VAULT=0
    fi
    VAULT="${VAULT%/}"

    # vorhandene Todo.md vorschlagen
    suggest="$VAULT"
    [ "$VAULT" = "$(sed -n 's/^VAULT=//p' "$CONF" 2>/dev/null)" ] && [ -n "$TODO_DIR" ] && suggest="$TODO_DIR"
    if [ "$suggest" = "$VAULT" ]; then
        found="$(find "$VAULT" -maxdepth 2 -name Todo.md -not -path '*/.*' 2>/dev/null | head -1)"
        [ -n "$found" ] && suggest="$(dirname "$found")"
    fi
    while :; do
        TODO_DIR="$(ask_dir "Ordner für Todo.md (im Vault)" "$suggest")" || exit 0
        TODO_DIR="${TODO_DIR%/}"
        case "$TODO_DIR/" in "$VAULT"/*) break ;; esac
        info "Der Ordner muss im Vault liegen:
$VAULT"
    done
    [ "$NEW_VAULT" = 1 ] && register_vault "$VAULT"
    else
        # nur Google: die Liste arbeitet mit einer Kopie auf diesem PC
        [ -n "$VAULT" ] && [ -n "$TODO_DIR" ] || { VAULT="$DATA_DIR"; TODO_DIR="$DATA_DIR"; }
    fi

    # Anzeige
    cur="${MODE:-panel}"
    if [ "$HAVE_KDIALOG" = 1 ]; then
        on() { [ "$cur" = "$1" ] && echo on || echo off; }
        MODE="$(kdialog --title "$APP" --radiolist "Wo soll die Liste angezeigt werden?

Seitenleiste: erscheint, wenn die Maus an den rechten Bildschirmrand fährt, und nach dem Anmelden/Aufklappen für 10 Sekunden pro offenem Punkt.
Desktop: liegt auf dem Hintergrundbild (unter den Fenstern).

Später umschaltbar per Rechtsklick auf die Liste." \
            panel "Seitenleiste am rechten Rand (empfohlen)" "$(on panel)" \
            desktop "Auf dem Desktop" "$(on desktop)" \
            both "Beides" "$(on both)")" || exit 0
    else
        read -r -p "Anzeige: [p]Seitenleiste (Standard), [d]Desktop, [b]eides: " r
        case "$r" in d*) MODE=desktop ;; b*) MODE=both ;; *) MODE=panel ;; esac
    fi
else
    [ -n "$VAULT" ] && [ -n "$TODO_DIR" ] || fail "Keine gespeicherte Einrichtung gefunden."
fi

# ---------- Dateien ----------
TODO_FILE="$TODO_DIR/Todo.md"
ARCHIVE_FILE="$TODO_DIR/Todo-Archiv.md"
if [ "$SILENT" = 1 ] && [ -f "$CONF" ]; then
    # Update: gewaehlte Dateien behalten (auch mit eigenem Namen)
    t="$(sed -n 's/^TODO_FILE=//p' "$CONF")"; a="$(sed -n 's/^ARCHIVE_FILE=//p' "$CONF")"
    [ -n "$t" ] && TODO_FILE="$t"
    [ -n "$a" ] && ARCHIVE_FILE="$a"
fi
mkdir -p "$TODO_DIR"
if [ "$USE_OBSIDIAN" = 1 ]; then
    [ -f "$TODO_FILE" ] || printf '# Todo\n\n- [ ] Mein erster Eintrag\n' > "$TODO_FILE"
else
    [ -f "$TODO_FILE" ] || printf '# Todo\n' > "$TODO_FILE"
fi
[ -f "$ARCHIVE_FILE" ] || printf '# Todo-Archiv\n' > "$ARCHIVE_FILE"

mkdir -p "$CONF_DIR"
cat > "$CONF" <<EOF
# Task Board - geschrieben vom Setup
VAULT=$VAULT
VAULT_NAME=$(basename "$VAULT")
TODO_FILE=$TODO_FILE
ARCHIVE_FILE=$ARCHIVE_FILE
MODE=${MODE:-panel}
EOF
# Speicherort beim ersten Einrichten festhalten (spaeter aendert das Zahnrad diese Datei, Updates lassen sie in Ruhe)
if [ "$FRESH" = 1 ] && [ "$SILENT" = 0 ]; then
    {
        printf 'OBSIDIAN_ON=%s\n' "$USE_OBSIDIAN"
        if [ -n "$GOOGLE_LIST" ]; then printf 'GOOGLE_ON=1\nGOOGLE_LIST=%s\nGOOGLE_LIST_NAME=%s\n' "$GOOGLE_LIST" "$GOOGLE_LIST_NAME"
        else printf 'GOOGLE_ON=0\n'; fi
    } > "$GCONF"
fi

# ---------- Widget installieren ----------
FIRST_INSTALL=1
[ -f "$PLASMOID_DIR/metadata.json" ] && FIRST_INSTALL=0
if [ "$HAVE_KPT" = 1 ]; then
    if [ "$FIRST_INSTALL" = 0 ] || kpackagetool6 -t Plasma/Applet -s "$PLUGIN_ID" >/dev/null 2>&1; then
        FIRST_INSTALL=0
        kpackagetool6 -t Plasma/Applet -u "$PKG" >>"$LOG" 2>&1 || fail "Widget konnte nicht aktualisiert werden (Details: $LOG)."
    else
        kpackagetool6 -t Plasma/Applet -i "$PKG" >>"$LOG" 2>&1 || fail "Widget konnte nicht installiert werden (Details: $LOG)."
    fi
else
    # ohne kpackagetool6: genau dorthin kopieren, wo es kpackagetool6 auch hinlegt
    log "kpackagetool6 fehlt - Widget wird direkt nach $PLASMOID_DIR kopiert"
    rm -rf "$PLASMOID_DIR" && mkdir -p "$(dirname "$PLASMOID_DIR")" && cp -r "$PKG" "$PLASMOID_DIR" \
        || fail "Widget konnte nicht installiert werden (Details: $LOG)."
fi
# Updates
mkdir -p "$DATA_DIR"
cp "$UPD" "$DATA_DIR/update.sh"; chmod +x "$DATA_DIR/update.sh"
# Google-Abgleich (Widget ruft ihn auf) und Zugang des Programms zu Google
[ -f "$GPY" ] && { cp "$GPY" "$DATA_DIR/google-sync.py"; chmod +x "$DATA_DIR/google-sync.py"; }
[ -f "$GCLIENT" ] && cp "$GCLIENT" "$DATA_DIR/google-client.json"
printf '%s\n' "$VERSION" > "$DATA_DIR/version.txt"
printf '%s\n' "$REPO" > "$DATA_DIR/repo.txt"
# Setup selbst aufheben: fuer "Anzeige umschalten" und "entfernen" (Rechtsklick-Menue, Startmenue)
[ "$SELF" != "$DATA_DIR/setup.sh" ] && cp "$SELF" "$DATA_DIR/setup.sh"
chmod +x "$DATA_DIR/setup.sh"

# Startmenue: "Task Board entfernen" (der alte Eintrag "Obsidian To-do entfernen" fliegt in migrate_files raus)
mkdir -p "$(dirname "$MENU_ENTRY")"
cat > "$MENU_ENTRY" <<EOF
[Desktop Entry]
Type=Application
Name=Task Board entfernen
Comment=Entfernt die Todo-Liste (Todo.md und Archiv bleiben erhalten)
Exec=bash "$DATA_DIR/setup.sh" --uninstall
Icon=edit-delete
Terminal=false
Categories=Utility;
EOF
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$(dirname "$MENU_ENTRY")" >/dev/null 2>&1

# altes Obsidian-Todo-Widget gegen das neue austauschen (Platz, Einstellungen und Kuerzel bleiben).
# Erst hier, damit das neue Widget beim Start schon version.txt usw. vorfindet.
migrate_widget || true

# ---------- Anzeige einrichten (beim Update bleibt alles, wie es ist) ----------
if [ "$SILENT" = 0 ]; then
    apply_mode "${MODE:-sidebar}" || log "Anzeige konnte nicht automatisch eingerichtet werden"
else
    # Update von einer Version mit eigener KDE-Leiste: auf das neue Desktop-Widget umbauen
    apply_mode "${MODE:-sidebar}" 1 || log "Umbau der alten Seitenleiste fehlgeschlagen"
fi

# Plasma haelt die alte Widget-Version im Speicher, bis plasmashell neu startet. Beim Setup von Hand (z. B. Update
# von einer alten Version ohne Auto-Update) deshalb Plasma neu starten, sonst bleibt die alte Liste stehen.
restart_plasma() {
    command -v plasmashell >/dev/null 2>&1 || return 1
    pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1 || return 1
    if [ "$(systemctl --user is-active plasma-plasmashell.service 2>/dev/null)" = active ]; then
        systemctl --user restart plasma-plasmashell.service >>"$LOG" 2>&1 && return 0
    fi
    if command -v kquitapp6 >/dev/null 2>&1; then kquitapp6 plasmashell >>"$LOG" 2>&1; else pkill -u "$(id -u)" -x plasmashell; fi
    for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1 || break; sleep 0.5; done
    if command -v kstart >/dev/null 2>&1; then kstart plasmashell >>"$LOG" 2>&1
    else (setsid plasmashell >/dev/null 2>&1 &); fi
    for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1 && return 0; sleep 0.5; done
    (setsid plasmashell >/dev/null 2>&1 &)   # kstart hat nicht geklappt
    sleep 1; pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1
}
if [ "$SILENT" = 0 ] || [ "$RESTART" = 1 ]; then
    log "Plasma wird neu gestartet (neue Widget-Version laden)"
    restart_plasma || log "Plasma-Neustart nicht moeglich - neue Version nach dem naechsten Anmelden"
    sleep 4
fi

log "fertig: $TODO_FILE (Version $VERSION)"
if [ "$SILENT" = 1 ]; then
    command -v notify-send >/dev/null 2>&1 && { if [ "$RESTART" = 1 ]; then notify-send -a "$APP" -i checkbox "$APP aktualisiert" "Version $VERSION ist installiert."; else notify-send -a "$APP" -i checkbox "$APP aktualisiert" "Version $VERSION ist installiert. Sie wird nach dem nächsten Anmelden aktiv."; fi; }
else
    case "${MODE:-panel}" in
        panel|sidebar) where="Die Liste gleitet herein, wenn du mit der Maus an den rechten Bildschirmrand fährst, und nach dem Anmelden/Aufklappen kurz von selbst." ;;
        desktop) where="Die Liste liegt oben rechts auf deinem Desktop." ;;
        *) where="Die Liste liegt auf deinem Desktop und gleitet zusätzlich am rechten Bildschirmrand herein." ;;
    esac
    if [ "$USE_OBSIDIAN" = 0 ]; then stored="Gespeichert wird bei Google Tasks (Liste „$GOOGLE_LIST_NAME“)."
    elif [ -n "$GOOGLE_LIST" ]; then stored="Gespeichert wird in:
$TODO_FILE
und in Google Tasks (Liste „$GOOGLE_LIST_NAME“)."
    else stored="Gespeichert wird in:
$TODO_FILE"; fi
    info "Fertig!

$where
$stored

Neuer Eintrag von überall: $SHORTCUT
Anzeige, Farben und mehr: Zahnrad neben „Todo“.
Entfernen: Rechtsklick auf die Liste.
Entfernen geht auch über das Startmenü: „Task Board entfernen“."
fi
exit 0
