#!/bin/bash
# Testlauf in WSL: Testbenutzer, Kopie einer Todo.md, Widget installieren und in einem Fenster starten
U=tester
id $U >/dev/null 2>&1 || useradd -m -s /bin/bash $U
H=/home/$U
mkdir -p "$H/Dokumente/Test Vault/Notizen" "$H/Dokumente/Test Vault/.obsidian" "$H/.config/taskboard"
[ -f "$H/Dokumente/Test Vault/Notizen/Todo.md" ] || cp "${TODO_SOURCE:-/mnt/h/Projekte/taskboard/linux/tests/sample-Todo.md}" "$H/Dokumente/Test Vault/Notizen/Todo.md"
cat > "$H/.config/taskboard/config" <<CFG
VAULT=$H/Dokumente/Test Vault
VAULT_NAME=Test Vault
TODO_FILE=$H/Dokumente/Test Vault/Notizen/Todo.md
ARCHIVE_FILE=$H/Dokumente/Test Vault/Notizen/Todo-Archiv.md
CFG
chown -R $U:$U "$H"
PKG=/mnt/h/Projekte/taskboard/linux/kde/package
su - $U -c "kpackagetool6 -t Plasma/Applet -r io.github.fantastesy.taskboard >/dev/null 2>&1; kpackagetool6 -t Plasma/Applet -i '$PKG'"
# Fenster starten (WSLg), Fehler mitschreiben
su - $U -c "export WAYLAND_DISPLAY=$WAYLAND_DISPLAY DISPLAY=$DISPLAY XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir QT_QPA_PLATFORM=xcb; timeout ${1:-25} dbus-run-session plasmawindowed io.github.fantastesy.taskboard" > /tmp/widget.log 2>&1
grep -iE 'error|warn|qml|\.qml:|TypeError|ReferenceError|not (a type|installed)|Cannot' /tmp/widget.log | grep -v 'kf.svg\|QDBus\|xdg-desktop-portal\|kf.kio\|Fontconfig' | head -40
echo "--- Zeilen gesamt: $(wc -l < /tmp/widget.log)"
