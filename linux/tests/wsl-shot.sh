#!/bin/bash
# Testlauf in WSL (Ubuntu + WSLg): Widget in einem Fenster starten, optional klicken, alle Fenster als PNG speichern.
#   $1 Wartezeit bis zur Aktion (s), $2 Aktion (Shell-Befehl mit xdotool; $W = Widget-Fenster), $3 Ausgabe-Praefix
command -v xwd >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y -qq x11-apps imagemagick xdotool >/dev/null 2>&1
U=tester; H=/home/$U
OUTDIR=/mnt/h/Projekte/taskboard/linux/tests
PREFIX=${3:-shot}
rm -f $H/cap-*.png $H/widget.log "$OUTDIR/$PREFIX"-*.png
cat > $H/shot-inner.sh <<'IN'
plasmawindowed io.github.fantastesy.taskboard > $HOME/widget.log 2>&1 &
PID=$!
sleep "$WAIT"
W=$(xdotool search --name "Obsidian Todo" | tail -1)
eval "$ACTION"
sleep 2
n=0
for w in $(xdotool search --onlyvisible --pid $PID 2>/dev/null); do
  xwd -id $w -silent 2>/dev/null | convert xwd:- $HOME/cap-$n.png 2>/dev/null && n=$((n+1))
done
kill $PID
IN
chown $U:$U $H/shot-inner.sh
su - $U -c "export DISPLAY=$DISPLAY QT_QPA_PLATFORM=xcb XDG_RUNTIME_DIR=/tmp/rt-$U TASKBOARD_TEST='${4:-}' WAIT='${1:-10}' ACTION='${2:-true}'; mkdir -p -m 700 /tmp/rt-$U; dbus-run-session bash $H/shot-inner.sh" 2>/dev/null
for f in $H/cap-*.png; do [ -f "$f" ] && cp "$f" "$OUTDIR/$PREFIX-$(basename "$f" .png | cut -d- -f2).png"; done
ls -la "$OUTDIR/$PREFIX"-*.png 2>/dev/null
grep -iE 'TypeError|ReferenceError|\.qml:[0-9]' $H/widget.log | sort -u | head
