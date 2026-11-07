#!/bin/bash
# Setup-Test in WSL: frischer Benutzer, Setup im Terminal-Modus mit vorgegebenen Antworten
U=setuptest; H=/home/$U
pkill -u $U 2>/dev/null; userdel -rf $U >/dev/null 2>&1; useradd -m -s /bin/bash $U
mkdir -p $H/Dokumente && chown -R $U:$U $H
bash /mnt/h/Projekte/taskboard/linux/build-kde.sh || exit 1
cp /mnt/h/Projekte/taskboard/dist/TaskBoard-KDE-Setup.sh $H/ && chown $U:$U $H/TaskBoard-KDE-Setup.sh
# Antworten: Obsidian installieren? n | Vault-Ordner: Standard | Todo-Ordner: Standard
su - $U -c "export XDG_CURRENT_DESKTOP=KDE TASKBOARD_NO_GUI=1 LANG=de_DE.UTF-8; printf 'n\n\n\n' | bash ./TaskBoard-KDE-Setup.sh" 2>&1 | tail -15
echo "===== Ergebnis ====="
cat $H/.config/taskboard/config
ls -la "$H/Dokumente/Obsidian Vault" "$H/.local/share/taskboard" 2>&1
su - $U -c "kpackagetool6 -t Plasma/Applet -l | grep obsidian"
cat $H/.config/obsidian/obsidian.json 2>/dev/null; echo
echo "===== Update-Lauf (silent) ====="
su - $U -c "export XDG_CURRENT_DESKTOP=KDE; bash ./TaskBoard-KDE-Setup.sh --silent; echo exit=\$?"
tail -3 /tmp/taskboard-setup.log
