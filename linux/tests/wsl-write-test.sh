#!/bin/bash
# Schreibtest: add -> toggle -> cleanup, nach jedem Schritt Todo.md/Archiv zeigen
T="/home/tester/Dokumente/Test Vault/Notizen"
cp "${TODO_SOURCE:-/mnt/h/Projekte/taskboard/linux/tests/sample-Todo.md}" "$T/Todo.md"; rm -f "$T/Todo-Archiv.md"; chown tester:tester "$T/Todo.md"
for step in add toggle cleanup; do
  bash /mnt/h/Projekte/taskboard/linux/tests/wsl-shot.sh 6 true "w-$step" "$step" >/dev/null 2>&1
  echo "===== nach $step: Todo.md ====="; cat "$T/Todo.md"
done
echo "===== Todo-Archiv.md ====="; cat "$T/Todo-Archiv.md" 2>/dev/null || echo "(fehlt)"
echo "===== Vergleich Original vs. jetzt ====="; diff "${TODO_SOURCE:-/mnt/h/Projekte/taskboard/linux/tests/sample-Todo.md}" "$T/Todo.md"
