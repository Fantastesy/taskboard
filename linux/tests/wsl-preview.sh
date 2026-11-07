#!/bin/bash
# Realistische Vorschau: Widget nimmt sich selbst mit Transparenz auf (grabToImage),
# das Bild wird auf ein Hintergrundbild gelegt - so wie es auf dem KDE-Desktop aussieht.
#   $1 Hintergrundbild (optional), Ergebnis: linux/tests/preview.png
U=tester; H=/home/$U
OUT=/mnt/h/Projekte/taskboard/linux/tests/preview.png
rm -f $H/grab.png "$OUT"
cat > $H/grab-inner.sh <<'IN'
TASKBOARD_TEST=grab plasmawindowed io.github.fantastesy.taskboard > $HOME/widget.log 2>&1 &
sleep 8
kill $!
IN
chown $U:$U $H/grab-inner.sh
su - $U -c "export DISPLAY=$DISPLAY QT_QPA_PLATFORM=xcb XDG_RUNTIME_DIR=/tmp/rt-$U; mkdir -p -m 700 /tmp/rt-$U; dbus-run-session bash $H/grab-inner.sh" 2>/dev/null
[ -f $H/grab.png ] || { echo "kein grab.png"; grep -iE 'qml|error' $H/widget.log | head; exit 1; }
read W HT < <(identify -format '%w %h' $H/grab.png)
BG=/tmp/bg.png
if [ -n "${1:-}" ] && [ -f "$1" ]; then
  convert "$1" -resize "$((W + 80))x$((HT + 80))^" -gravity center -extent "$((W + 80))x$((HT + 80))" $BG
else
  convert -size "$((W + 80))x$((HT + 80))" gradient:'#3a7bd5-#c06c84' -swirl 40 $BG
fi
composite -geometry +40+40 $H/grab.png $BG "$OUT" && identify "$OUT"
