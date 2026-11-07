#!/usr/bin/env bash
# Widget-Dateien in den laufenden Test-Container kopieren (ohne kpackagetool6), Plasma neu starten, Akzent + Einstellungen pruefen
set -u
export MSYS_NO_PATHCONV=1
command -v docker >/dev/null || export PATH="/h/Windows stuff/Docker Desktop/resources/bin:$PATH"
root="$(cd "$(dirname "$0")/../.." && pwd)"; out="$(cd "$root/linux/tests" && (pwd -W 2>/dev/null || pwd))"
c=obsidian-todo-kde; n="pkg$(date +%s)"
tmp="$(mktemp -d)"; cp -r "$root/linux/kde/package" "$tmp/$n"; find "$tmp" -type f -exec sed -i 's/\r$//' {} +
docker cp "$(cd "$tmp" && (pwd -W 2>/dev/null || pwd))/$n" $c:/tmp/$n >/dev/null
docker exec $c bash -c "cp -r /tmp/$n/. /config/.local/share/plasma/plasmoids/io.github.fantastesy.taskboard/; chown -R abc /config/.local/share/plasma/plasmoids"
timeout 60 docker exec $c insession bash -c 'pkill -x plasmashell; sleep 2; (setsid plasmashell >/tmp/plasma.log 2>&1 &); sleep 15'
cmd() { docker exec $c bash -c "printf '%s\n' '$1' > /tmp/taskboard-test.cmd; chown abc /tmp/taskboard-test.cmd"; sleep "${2:-3}"; }
grab() { cmd "grab=$1" 3; docker cp $c:/tmp/taskboard-$1.png "$out/alles-$2.png" >/dev/null 2>&1 && echo "  Bild alles-$2.png"; }
cmd accent=gruen 2; cmd show 3; grab panel 08-gruen; cmd hide 2; cmd accent=lila 2
cmd settings 3; grab settings 06-einstellungen; cmd closesettings 2
