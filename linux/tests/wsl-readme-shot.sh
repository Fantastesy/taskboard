#!/bin/bash
# README-Bild: dunkles Breeze-Design, Liste + Formular nebeneinander (nur Beispieldaten)
U=tester; H=/home/$U; T="$H/Dokumente/Test Vault/Notizen"
cp /mnt/h/Projekte/taskboard/linux/tests/sample-Todo.md "$T/Todo.md"; chown $U:$U "$T/Todo.md"
su - $U -c "kwriteconfig6 --file plasmarc --group Theme --key name breeze-dark; kwriteconfig6 --file kdeglobals --group General --key ColorScheme BreezeDark; [ -f /usr/share/color-schemes/BreezeDark.colors ] && cp /usr/share/color-schemes/BreezeDark.colors ~/.config/kdeglobals.tmp && cat ~/.config/kdeglobals.tmp >> ~/.config/kdeglobals; rm -f ~/.config/kdeglobals.tmp"
D=/mnt/h/Projekte/taskboard/linux/tests
bash $D/wsl-shot.sh 8 true list >/dev/null
bash $D/wsl-shot.sh 8 true form edit >/dev/null
ls -la $D/list-*.png $D/form-*.png
