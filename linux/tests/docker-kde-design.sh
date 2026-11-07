#!/usr/bin/env bash
# Design-Test (Tags rund, "+ Neuer Tag" als Eingabefeld, Hintergrund-Stufen mit Umrandung) im laufenden Container.
# Bilder per grabToImage (mit Transparenz) nach linux/tests/design-*.png
set -u
export MSYS_NO_PATHCONV=1
command -v docker >/dev/null || export PATH="/h/Windows stuff/Docker Desktop/resources/bin:$PATH"
root="$(cd "$(dirname "$0")/../.." && pwd)"; out="$(cd "$root/linux/tests" && (pwd -W 2>/dev/null || pwd))"
c=obsidian-todo-kde; n="pkg$(date +%s)"
tmp="$(mktemp -d)"; cp -r "$root/linux/kde/package" "$tmp/$n"; find "$tmp" -type f -exec sed -i 's/\r$//' {} +
docker cp "$(cd "$tmp" && (pwd -W 2>/dev/null || pwd))/$n" $c:/tmp/$n >/dev/null
docker exec $c bash -c "cp -r /tmp/$n/. /config/.local/share/plasma/plasmoids/io.github.fantastesy.taskboard/; chown -R abc /config/.local"
cmd() { docker exec $c bash -c "rm -f /tmp/taskboard-test.out; printf '%s\n' '$1' > /tmp/taskboard-test.cmd; chown abc /tmp/taskboard-test.cmd"; sleep "${2:-3}"; }
res() { docker exec $c cat /tmp/taskboard-test.out 2>/dev/null; echo; }
grab() { cmd "grab=$1" 3; docker cp $c:/tmp/taskboard-$1.png "$out/design-$2.png" >/dev/null 2>&1 && echo "  Bild design-$2.png" || echo "  KEIN Bild $2"; }
docker exec $c bash -c 'f="$(grep ^TODO_FILE= /config/.config/taskboard/config | cut -d= -f2-)"; cat > "$f" <<EOT
# Todo

- [ ] Ohne Tag
- [ ] Bewerbung abschicken #arbeit #privat 📅 2026-11-06 ➕ 2026-11-05
- [ ] Lui Augentropfen (Abend) 🔁 täglich ⏰ 21:00 📅 2026-11-05 ➕ 2026-11-01
- [ ] Vlan 3. gerät #arbeit
    - https://unifi.ui.com/x
- [ ] Drohn Frame / shop #privat
EOT
chown abc "$f"'
docker exec $c bash -c 'touch /tmp/taskboard-test.enable; chown abc /tmp/taskboard-test.enable'
timeout 60 docker exec $c insession bash -c 'pkill -x plasmashell; sleep 2; (setsid plasmashell >/tmp/plasma.log 2>&1 &); sleep 18'
cmd "mode=desktop" 4
cmd "tags=arbeit:lila,privat:pink" 3
echo "== Hintergrund-Stufen"
for op in 250 170 100 1; do cmd "opacity=$op" 2; grab list "liste-$op"; done
cmd "opacity=170" 2
echo "== Einstellungen"
cmd settings 4; grab settings einst-1
echo "== + Neuer Tag -> Eingabefeld"
cmd "tagedit=Einkauf" 2; grab settings einst-2-eingabe
cmd "tagedit=!" 3; grab settings einst-3-angelegt
docker exec $c bash -c 'grep -h "^tags=" /config/.config/plasma-org.kde.plasma.desktop-appletsrc'
echo "== Esc-Abbruch"
cmd "tagedit=Wegdamit" 2; cmd "tagedit=" 2; grab settings einst-4-abgebrochen
docker exec $c bash -c 'grep -h "^tags=" /config/.config/plasma-org.kde.plasma.desktop-appletsrc'
echo "== Opacity in der Konfig / Fehler im Log"
docker exec $c bash -c 'grep -h "^opacity=" /config/.config/plasma-org.kde.plasma.desktop-appletsrc; grep -i -E "taskboard.*(error|warn|TypeError|ReferenceError)" /tmp/plasma.log | tail -8'
