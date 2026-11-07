#!/usr/bin/env bash
# Test der Funktionen aus 1.3.0 (eigene Reihenfolge, Ziehen, Tags, Update-Suche) im laufenden Test-Container.
set -u
export MSYS_NO_PATHCONV=1
command -v docker >/dev/null || export PATH="/h/Windows stuff/Docker Desktop/resources/bin:$PATH"
root="$(cd "$(dirname "$0")/../.." && pwd)"; out="$(cd "$root/linux/tests" && (pwd -W 2>/dev/null || pwd))"
c=obsidian-todo-kde
cmd() { docker exec $c bash -c "rm -f /tmp/taskboard-test.out; printf '%s\n' '$1' > /tmp/taskboard-test.cmd; chown abc /tmp/taskboard-test.cmd"; sleep "${2:-3}"; }
res() { docker exec $c cat /tmp/taskboard-test.out 2>/dev/null; echo; }
grab() { cmd "grab=$1" 3; docker cp $c:/tmp/taskboard-$1.png "$out/neu-$2.png" >/dev/null 2>&1 && echo "  Bild neu-$2.png" || echo "  FEHLER: kein Bild $2"; docker exec $c rm -f /tmp/taskboard-$1.png; }
todo() { docker exec $c bash -c 'f="$(grep ^TODO_FILE= /config/.config/taskboard/config | cut -d= -f2-)"; grep -n "\- \[" "$f"'; }
step() { echo "== $*"; }

# Testdatei wie bei Levin: Punkte ohne Datum vorne, mit Datum hinten (bisher wurden die mit Datum oben angezeigt)
docker exec $c bash -c 'f="$(grep ^TODO_FILE= /config/.config/taskboard/config | cut -d= -f2-)"; cat > "$f" <<EOT
# Todo

Wird angezeigt.
- [ ] Vlan 3. gerät
    - https://unifi.ui.com/x
- [ ] Bewerbung
- [ ] Drohn Frame / shop
- [ ] Lui Mittag 🔁 täglich ⏰ 16:00 📅 2026-11-04 ➕ 2026-11-01
- [ ] Lui Abend 🔁 täglich ⏰ 21:00 📅 2026-11-03 ➕ 2026-11-01
- [ ] eng 📅 2026-11-07 ➕ 2026-11-03
EOT
chown abc "$f"; touch /tmp/taskboard-test.enable; chown abc /tmp/taskboard-test.enable'
timeout 60 docker exec $c insession bash -c 'pkill -x plasmashell; sleep 2; (setsid plasmashell >/tmp/plasma.log 2>&1 &); sleep 18'
step "Einmal-Sortierung (Datei so wie bisher angezeigt)"; todo; cmd updstate; res
cmd show 3; grab panel 01-start
step "Tags anlegen";            cmd "tags=arbeit:blau,privat:pink,wichtig:rot" 3
step "Neuer Punkt mit Tags + Datum morgen (Formular)"; cmd form 2; cmd "formtags=arbeit,wichtig" 2; grab form 02-formular-tags; cmd "formfill=Bewerbung abschicken" 4; todo
step "Ziehen: Zeile 0 nach unten an Stelle 4"; cmd "move=0,4" 4; todo
step "Ziehen: Zeile 5 nach oben an Stelle 0"; cmd "move=5,0" 4; todo
cmd show 3; grab panel 03-nach-ziehen
step "Einstellungen mit Tags + Update-Suche"; cmd settings 3; cmd updcheck 8; cmd updstate; res; grab settings 04-einstellungen; cmd closesettings 2
