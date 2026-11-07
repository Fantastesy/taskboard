#!/usr/bin/env bash
# Prueft alle Funktionen des Widgets im laufenden Test-Container (nach docker-kde-test.sh) ueber den Testeingang.
# Bilder per grabToImage (geht auch dort, wo Spectacle nicht laeuft, z. B. Kubuntu): linux/tests/alles-*.png
set -u
export MSYS_NO_PATHCONV=1
command -v docker >/dev/null || export PATH="/h/Windows stuff/Docker Desktop/resources/bin:$PATH"
root="$(cd "$(dirname "$0")/../.." && pwd)"; out="$(cd "$root/linux/tests" && (pwd -W 2>/dev/null || pwd))"
c=obsidian-todo-kde
cmd() { docker exec $c bash -c "rm -f /tmp/taskboard-test.out; printf '%s\n' '$1' > /tmp/taskboard-test.cmd; chown abc /tmp/taskboard-test.cmd"; sleep "${2:-3}"; }
res() { docker exec $c cat /tmp/taskboard-test.out 2>/dev/null; echo; }
grab() { cmd "grab=$1" 3; docker cp $c:/tmp/taskboard-$1.png "$out/alles-$2.png" >/dev/null 2>&1 && echo "  Bild alles-$2.png" || echo "  FEHLER: kein Bild $2"; docker exec $c rm -f /tmp/taskboard-$1.png; }
step() { echo "== $*"; }

docker exec $c bash -c 'touch /tmp/taskboard-test.enable; chown abc /tmp/taskboard-test.enable'
timeout 60 docker exec $c insession bash -c 'pkill -x plasmashell; sleep 2; (setsid plasmashell >/tmp/plasma.log 2>&1 &); sleep 15' 
step "Status";                 cmd status; res
step "Seitenleiste zeigen";    cmd show 2; cmd status; res; grab panel 01-seitenleiste; cmd hide 2
step "Punkt anlegen (add)";    cmd add 3; cmd todo; res
step "Formular: neu, Kalender"; cmd form; cmd formcal; grab form 02-formular-kalender
step "Formular ausfuellen + speichern"; cmd "formfill=Kalendertest" 4; cmd todo; res
step "Formular bearbeiten";    cmd editform; grab form 03-bearbeiten; cmd closeform 2
step "Notizen aufklappen";     cmd notes 2; cmd show 2; grab panel 04-notizen; cmd notes 2
step "Abhaken";                cmd toggle 3; cmd todo; res; cmd show 2; grab panel 05-abgehakt
step "Aufraeumen (Archiv)";    cmd cleanup 4; cmd todo; res; docker exec $c bash -c 'cat "$(grep ^ARCHIVE_FILE= /config/.config/taskboard/config | cut -d= -f2-)"'; cmd hide 2
step "Einstellungen";          cmd settings 3; grab settings 06-einstellungen
step "Tastenkuerzel aufnehmen"; cmd rectest 3; cmd status; res; grab settings 07-kuerzel-neu
step "Tastenkuerzel zuruecksetzen"; cmd resettest 3; cmd status; res; cmd closesettings 2
step "Akzent gruen";           cmd accent=green 2; cmd show 2; grab panel 08-gruen; cmd hide 2; cmd accent=purple 2
step "Links";                  cmd side=left 3; cmd show 2; grab panel 09-links; cmd hide 2; cmd side=right 3
step "Beides";                 cmd mode=both 4; cmd status; res; grab desk 10-beides-desktop; cmd show 3; grab panel 11-beides-panel; cmd hide 3
step "Desktop";                cmd mode=desktop 4; cmd deskinfo; res; grab desk 12-desktop
step "Seitenleiste";           cmd mode=sidebar 4; cmd status; res
step "Einblenden";             cmd reveal 3; cmd status; res
step "Todo-Datei wechseln";    cmd "choose=/config/Documents/Andere/Todo-Neu.md" 5; cmd todo; res
docker exec $c bash -c 'grep -E "^(VAULT|TODO_FILE|ARCHIVE_FILE)=" /config/.config/taskboard/config'
