#!/usr/bin/env bash
# Test des KDE-Setups auf einem echten Plasma-6-Desktop in Docker (linuxserver/webtop:fedora-kde).
# Laeuft unter Linux oder in der Git-Bash unter Windows (Docker Desktop):
#   bash linux/tests/docker-kde-test.sh [setup-datei] [bild-praefix]
# Ablauf: frischer Container -> Setup im Terminal-Modus (Obsidian nein, neuer Vault, Seitenleiste)
#         -> CPU pruefen (keine Dauerschleife) -> Screenshots: Einblenden, danach, Maus am Rand.
# Den Desktop kann man waehrenddessen unter http://localhost:3010 ansehen.
set -u
export MSYS_NO_PATHCONV=1
root="$(cd "$(dirname "$0")/../.." && pwd)"
setup="${1:-$(ls "$root"/dist/TaskBoard-KDE-Setup-*.sh | tail -1)}"
prefix="${2:-kde}"
out="$root/linux/tests"
c=obsidian-todo-kde
img="${IMG:-lscr.io/linuxserver/webtop:fedora-kde}"   # IMG=lscr.io/linuxserver/webtop:ubuntu-kde fuer Kubuntu
command -v docker >/dev/null || export PATH="/h/Windows stuff/Docker Desktop/resources/bin:$PATH"

dist_win="$(cd "$(dirname "$setup")" && pwd -W 2>/dev/null || pwd)"
docker rm -f $c >/dev/null 2>&1
docker run -d --name $c --shm-size=1g -p 127.0.0.1:${PORT:-3010}:3000 -e PUID=1000 -e PGID=1000 -e TZ=Europe/Berlin \
    -e LC_ALL=de_DE.UTF-8 -e QT_FORCE_STDERR_LOGGING=1 -e "QT_LOGGING_RULES=qml.debug=true;js.debug=true" -v "$dist_win:/setup:ro" $img >/dev/null || exit 1
for i in $(seq 1 60); do sleep 3; docker exec $c pgrep -x plasmashell >/dev/null 2>&1 && break; done
sleep 15   # Plasma fertig starten lassen

# Hilfsprogramme im Container: Befehle in der Plasma-Sitzung ausfuehren, Screenshots (Spectacle, Wayland)
docker exec $c bash -c '
if command -v dnf >/dev/null; then dnf install -y -q spectacle sudo >/dev/null 2>&1; else apt-get update -qq >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq kde-spectacle sudo >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y -qq spectacle sudo >/dev/null 2>&1; fi
cat > /usr/local/bin/insession-inner <<"EOF"
#!/bin/bash
p=$(pgrep -u "$(id -u)" -x plasmashell | head -1)
while IFS= read -r -d "" kv; do
  case "$kv" in DISPLAY=*|WAYLAND_DISPLAY=*|XDG_SESSION_TYPE=*|DBUS_SESSION_BUS_ADDRESS=*|XDG_RUNTIME_DIR=*|KDE_SESSION_VERSION=*|XDG_CURRENT_DESKTOP=*|HOME=*|XDG_SESSION_ID=*|LANG=*|XDG_DATA_DIRS=*|QT_*=*) export "$kv" ;; esac
done < /proc/$p/environ
exec "$@"
EOF
printf "#!/bin/bash\nexec sudo -u abc /usr/local/bin/insession-inner \"\$@\"\n" > /usr/local/bin/insession
chmod +x /usr/local/bin/insession /usr/local/bin/insession-inner'

shot() { [ -n "${NOSHOT:-}" ] && return; docker exec $c insession bash -c "spectacle -b -n -f -o /tmp/$1.png; sleep 2"; docker cp $c:/tmp/$1.png "$(cd "$out" && (pwd -W 2>/dev/null || pwd))/$prefix-$1.png" >/dev/null 2>&1 && echo "Bild: $prefix-$1.png"; }
cpu() { docker exec $c bash -c 'p=$(pgrep -x plasmashell | head -1); a=$(awk "{print $14+$15}" /proc/$p/stat); sleep 3; b=$(awk "{print $14+$15}" /proc/$p/stat); echo $(( (b-a) * 100 / 300 ))'; }

echo "== Setup: $(basename "$setup")"
docker exec $c insession bash -c "cd ~ && cp '/setup/$(basename "$setup")' setup.sh && printf 'n\n\n\np\n' | TASKBOARD_NO_GUI=1 bash ./setup.sh >/tmp/setup.out 2>&1; echo exit=\$?; tail -3 /tmp/taskboard-setup.log"
sleep 4; shot 1-eingeblendet
echo "== CPU plasmashell (sollte niedrig sein): $(cpu) %"
sleep 14; shot 2-danach
echo "== CPU plasmashell: $(cpu) %"
echo "== Leisten:"
docker exec $c insession bash -c 'f=~/.config/plasma-org.kde.plasma.desktop-appletsrc; awk "/^\[Containments\]\[[0-9]+\]\$/{c=\$0} /^(plugin|location|formfactor)=/{print c, \$0}" $f | grep -B2 -A0 taskboard'
echo "Fertig. Container laeuft weiter ($c, http://localhost:3010); entfernen: docker rm -f $c"
