#!/usr/bin/env bash
# Seitenleiste ohne Qt.WindowStaysOnTopHint: Fenstertyp (kein Dock mehr), liegt sie trotzdem ueber
# normalen Fenstern, und laesst sich in der ausgefahrenen Liste noch tippen? (laufender Container, X11)
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
X() { docker exec $c insession bash -c "export DISPLAY=:1; $1"; }
docker exec $c bash -c 'touch /tmp/taskboard-test.enable; chown abc /tmp/taskboard-test.enable'
timeout 60 docker exec $c insession bash -c 'pkill -x plasmashell; sleep 2; (setsid plasmashell >/tmp/plasma.log 2>&1 &); sleep 18'
cmd "mode=sidebar" 4
echo "== normales Fenster oeffnen (kwrite) und nach vorn holen"
X '(setsid kwrite >/dev/null 2>&1 &); sleep 5; xdotool search --class kwrite | head -1 | xargs -r xdotool windowactivate'
sleep 2
echo "== Liste ausfahren"
cmd show 3
X 'for w in $(xprop -root _NET_CLIENT_LIST_STACKING | sed "s/.*# //; s/,//g"); do
  pid=$(xprop -id $w _NET_WM_PID 2>/dev/null | awk "{print \$3}"); cls=$(xprop -id $w WM_CLASS 2>/dev/null | cut -d= -f2)
  t=$(xprop -id $w _NET_WM_WINDOW_TYPE 2>/dev/null | cut -d= -f2); st=$(xprop -id $w _NET_WM_STATE 2>/dev/null | cut -d= -f2)
  g=$(xwininfo -id $w 2>/dev/null | grep -E "Absolute upper-left X|Width|Height" | awk "{print \$NF}" | tr "\n" " ")
  echo "$w$cls |$t |$st | $g"; done'
echo "(unten in der Liste = ganz oben auf dem Bildschirm)"
