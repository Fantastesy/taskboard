#!/usr/bin/env bash
# 1.3.0: Einmal-Sortierung und "Jetzt aktualisieren" (laedt das neueste Release von GitHub) im laufenden Test-Container
set -u
export MSYS_NO_PATHCONV=1
command -v docker >/dev/null || export PATH="/h/Windows stuff/Docker Desktop/resources/bin:$PATH"
root="$(cd "$(dirname "$0")/../.." && pwd)"; out="$(cd "$root/linux/tests" && (pwd -W 2>/dev/null || pwd))"
c=obsidian-todo-kde; n="pkg$(date +%s)"
tmp="$(mktemp -d)"; cp -r "$root/linux/kde/package" "$tmp/$n"; find "$tmp" -type f -exec sed -i 's/\r$//' {} +
docker cp "$(cd "$tmp" && (pwd -W 2>/dev/null || pwd))/$n" $c:/tmp/$n >/dev/null
docker cp "$(cd "$root/linux/kde" && (pwd -W 2>/dev/null || pwd))/update.sh" $c:/tmp/update-neu.sh >/dev/null
docker exec $c bash -c "cp -r /tmp/$n/. /config/.local/share/plasma/plasmoids/io.github.fantastesy.taskboard/; sed 's/\r$//' /tmp/update-neu.sh > /config/.local/share/taskboard/update.sh; chmod +x /config/.local/share/taskboard/update.sh; chown -R abc /config/.local"
cmd() { docker exec $c bash -c "rm -f /tmp/taskboard-test.out; printf '%s\n' '$1' > /tmp/taskboard-test.cmd; chown abc /tmp/taskboard-test.cmd"; sleep "${2:-3}"; }
res() { docker exec $c cat /tmp/taskboard-test.out 2>/dev/null; echo; }
todo() { docker exec $c bash -c 'f="$(grep ^TODO_FILE= /config/.config/taskboard/config | cut -d= -f2-)"; grep -n "\- \[" "$f"'; }
docker exec $c bash -c 'f="$(grep ^TODO_FILE= /config/.config/taskboard/config | cut -d= -f2-)"; cat > "$f" <<EOT
# Todo

- [ ] Vlan 3. gerät
    - https://unifi.ui.com/x
- [ ] Bewerbung #arbeit
- [x] Alt erledigt ✅ 2026-11-01
- [ ] Lui Mittag 🔁 täglich ⏰ 16:00 📅 2026-11-04 ➕ 2026-11-01
- [ ] Lui Abend 🔁 täglich ⏰ 21:00 📅 2026-11-03 ➕ 2026-11-01
- [ ] eng 📅 2026-11-07 ➕ 2026-11-03
EOT
chown abc "$f"'
timeout 60 docker exec $c insession bash -c 'pkill -x plasmashell; sleep 2; (setsid plasmashell >/tmp/plasma.log 2>&1 &); sleep 18'
echo "== vorher"; todo
echo "== Einmal-Sortierung"; cmd migrate 5; todo; cmd updstate; res
echo "== Jetzt aktualisieren (Version im Container auf 1.2.1 gestellt -> holt 1.2.2 von GitHub)"
docker exec $c bash -c 'echo 1.2.1 > /config/.local/share/taskboard/version.txt; pgrep -x plasmashell'
cmd updcheck 8; cmd updstate; res
cmd updnow 45
docker exec $c bash -c 'echo "version.txt: $(cat /config/.local/share/taskboard/version.txt)"; echo "plasmashell: $(pgrep -x plasmashell)"; tail -4 /config/.local/share/taskboard/update.log'
