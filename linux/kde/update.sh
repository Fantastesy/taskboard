#!/bin/sh
# Updates fuer Task Board (frueher Obsidian Todo), KDE.
#   update.sh          automatisch: vom Widget beim Start und alle 6 Stunden, fragt hoechstens alle 6 Stunden bei GitHub
#   update.sh --check  von Hand ("Nach Updates suchen"): gibt "neu <version>" oder "aktuell <version>" aus
#   update.sh --now    von Hand ("Jetzt aktualisieren"): sofort installieren und Plasma neu starten (neue Version sofort sichtbar)
# Gibt es ein neueres Release, wird TaskBoard-KDE-Setup-<version>.sh geladen, die SHA-256-Pruefsumme
# verglichen und das Setup mit --silent ausgefuehrt. Einstellungen und Todo-Liste bleiben unveraendert.
DIR="${XDG_DATA_HOME:-$HOME/.local/share}/taskboard"
STAMP="$DIR/last-update-check"
LOG="$DIR/update.log"
# Name mit oder ohne Versionsnummer: TaskBoard-KDE-Setup-1.4.0.sh, bis 1.3.0 ObsidianTodo-KDE-Setup-1.3.0.sh (beide gleich)
ASSET_RE='^(TaskBoard|ObsidianTodo)-KDE-Setup(-[0-9.]+)?\.sh$'
MODE="${1:-auto}"

log() { printf '%s %s\n' "$(date +%FT%T)" "$*" >> "$LOG"; }

REPO="$(head -n1 "$DIR/repo.txt" 2>/dev/null)"
if ! printf '%s' "$REPO" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then   # Entwicklerversion
    [ "$MODE" = --check ] && echo "fehler kein-repo"
    exit 0
fi
CUR="$(head -n1 "$DIR/version.txt" 2>/dev/null)"

if [ "$MODE" = auto ]; then
    now="$(date +%s)"; last="$(cat "$STAMP" 2>/dev/null || echo 0)"
    [ $((now - last)) -lt 21600 ] && exit 0
    echo "$now" > "$STAMP"
fi

get() { if command -v curl >/dev/null 2>&1; then curl -fsSL -H "User-Agent: TaskBoard-Updater" "$@"; else wget -q -O - --header="User-Agent: TaskBoard-Updater" "$1"; fi; }

json="$(get "https://api.github.com/repos/$REPO/releases/latest")" || { log "GitHub nicht erreichbar"; [ "$MODE" = --check ] && echo "fehler offline"; exit 0; }
TAG="$(printf '%s' "$json" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"v\{0,1\}\([^"]*\)"$/\1/')"
[ -n "$TAG" ] || { [ "$MODE" = --check ] && echo "fehler keine-version"; exit 0; }
newer=0
[ "$TAG" != "$CUR" ] && [ "$(printf '%s\n%s\n' "$CUR" "$TAG" | sort -V | tail -n1)" = "$TAG" ] && newer=1
if [ "$MODE" = --check ]; then
    if [ "$newer" = 1 ]; then echo "neu $TAG"; else echo "aktuell $CUR"; fi
    exit 0
fi
[ "$newer" = 1 ] || exit 0

# Download-Adresse und Pruefsumme der Setup-Datei
if command -v python3 >/dev/null 2>&1; then
    info="$(printf '%s' "$json" | python3 -c 'import json,re,sys
for a in json.load(sys.stdin).get("assets",[]):
    if re.match(sys.argv[1], a.get("name","")): print(a.get("browser_download_url","")); print((a.get("digest") or "").replace("sha256:","")); break' "$ASSET_RE")"
    URL="$(printf '%s\n' "$info" | sed -n 1p)"; SHA="$(printf '%s\n' "$info" | sed -n 2p)"
else
    URL="$(printf '%s' "$json" | grep -oE "\"browser_download_url\": *\"[^\"]*/(TaskBoard|ObsidianTodo)-KDE-Setup(-[0-9.]+)?\.sh\"" | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')"; SHA=""
fi
[ -n "$URL" ] || { log "Release $TAG ohne KDE-Setup"; exit 0; }

TMP="$(mktemp)"
get "$URL" > "$TMP" || { log "Download fehlgeschlagen"; rm -f "$TMP"; exit 0; }
if [ -n "$SHA" ] && command -v sha256sum >/dev/null 2>&1; then
    [ "$(sha256sum "$TMP" | cut -d' ' -f1)" = "$SHA" ] || { log "Pruefsumme falsch fuer $TAG - Update abgebrochen"; rm -f "$TMP"; exit 1; }
fi
log "Update $CUR -> $TAG ($MODE)"
chmod +x "$TMP"
if [ "$MODE" = --now ]; then
    before="$(pgrep -u "$(id -u)" -x plasmashell | head -1)"
    bash "$TMP" --silent --restart >> "$LOG" 2>&1
    rm -f "$TMP"
    # aeltere Setups kennen --restart nicht: dann Plasma hier neu starten, damit die neue Version sofort geladen wird
    if [ -n "$before" ] && [ "$(pgrep -u "$(id -u)" -x plasmashell | head -1)" = "$before" ]; then
        log "Plasma wird neu gestartet"
        if [ "$(systemctl --user is-active plasma-plasmashell.service 2>/dev/null)" = active ] && systemctl --user restart plasma-plasmashell.service >> "$LOG" 2>&1; then :
        else
            if command -v kquitapp6 >/dev/null 2>&1; then kquitapp6 plasmashell >> "$LOG" 2>&1; else pkill -u "$(id -u)" -x plasmashell; fi
            for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1 || break; sleep 0.5; done
            if command -v kstart >/dev/null 2>&1; then kstart plasmashell >> "$LOG" 2>&1; fi
            sleep 2
            pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1 || (setsid plasmashell >/dev/null 2>&1 < /dev/null &)
        fi
    fi
else
    bash "$TMP" --silent >> "$LOG" 2>&1
    rm -f "$TMP"
fi
