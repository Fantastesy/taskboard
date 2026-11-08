# Task Board

*Früher „Obsidian To-do“.*

Eine Todo-Liste für den Desktop, die direkt als Markdown in deinem [Obsidian](https://obsidian.md)-Vault gespeichert wird – unter **Windows** mit [Rainmeter](https://www.rainmeter.net), unter **Linux** als Widget für **KDE Plasma 6**. Beide nutzen dasselbe Dateiformat, dieselbe `Todo.md` funktioniert also auf beiden Systemen.


- Punkte abhaken, bearbeiten, löschen – alles landet als normale Obsidian-Checkbox (`- [ ] …`) in `Todo.md`
- Fälligkeitsdatum, Uhrzeit mit Windows-Erinnerung („Erledigt“ / „In 15 Min nochmal“)
- Wiederkehrende Punkte (täglich, werktags, wöchentlich, monatlich, individuell)
- Notizen, Links, Dateien und Unteraufgaben pro Punkt
- Archiv für erledigte Punkte (`Todo-Archiv.md`)
- **Google Tasks** als Speicher, allein oder zusammen mit Obsidian (ab 2.0, siehe unten)
- Als **Seitenleiste** am Bildschirmrand (gleitet herein, wenn die Maus an den Rand fährt), auf dem **Desktop** oder **beides**
- Einstellungen über das Zahnrad: Seite, Breite, Schriftgröße, Hintergrund, Akzentfarbe, Tempo, Einblenden, Erinnerungen, Tastenkürzel, Todo-Datei, Updates
- Tastenkürzel für einen neuen Eintrag, von überall – Enter speichert sofort (Standard Windows: **Win+Shift+T** bzw. Strg+Alt+T, KDE: **Meta+Shift+T**; im Zahnrad änderbar)

## Google Tasks (ab 2.0)

Im Zahnrad unter „Speichern in“ kannst du Obsidian, Google Tasks oder beides anhaken, bei einer Neuinstallation schon im Setup. Du meldest dich einmal im Browser bei Google an und wählst eine Liste.

- Titel, Datum, Notizen, Unteraufgaben, Erledigt und Reihenfolge stehen in den normalen Feldern von Google Tasks.
- Uhrzeit, Wiederholung und Tags kann Googles Schnittstelle nicht speichern. Sie stehen deshalb zusammen mit dem Erstellt-Datum in der letzten Zeile der Beschreibung (`⟦tb …⟧`). Eine Uhrzeit, die du direkt bei Google einträgst, sieht Task Board nicht.
- Abgeglichen wird kurz nach jeder Änderung und sonst alle 2 Minuten. Ändern beide Seiten dasselbe Feld, gewinnt der PC.
- Hakst du einen Hauptpunkt ab, setzt Google seine Unteraufgaben ebenfalls auf erledigt.
- Beim Anmelden zeigt Google „Google hat diese App nicht überprüft“: auf „Erweitert“ und dann „Zu Task Board wechseln“ klicken.
- Der Zugangsschlüssel bleibt auf deinem Computer. „Verbindung trennen“ im Zahnrad löscht ihn, ebenso das Deinstallieren. Mehr dazu in der [Datenschutzerklärung](https://fantastesy.github.io/taskboard/datenschutz.html).
- Unter Linux wird dafür Python 3 gebraucht (bei Kubuntu, Fedora KDE usw. dabei).

## Installation unter Windows

1. `TaskBoard-Setup-<version>.exe` aus den [Releases](../../releases/latest) herunterladen und starten.
2. Speicherort wählen, Vault auswählen (oder neuen anlegen) – fertig.

Der Installer
- installiert Rainmeter mit, falls es fehlt (offizielle Version, fragt einmal nach Adminrechten),
- installiert auf Wunsch Obsidian mit,
- findet vorhandene Vaults und eine vorhandene `Todo.md` und verwendet sie weiter,
- funktioniert auch mit portablem Rainmeter.

Windows zeigt beim ersten Start evtl. „Der Computer wurde durch Windows geschützt“, weil das Setup nicht kostenpflichtig signiert ist: **Weitere Informationen → Trotzdem ausführen**.

## Installation unter Linux (KDE Plasma 6)

Funktioniert auf jeder Distribution mit KDE Plasma 6 (Kubuntu, Fedora KDE, KDE neon, openSUSE, Manjaro/Arch KDE …). `TaskBoard-KDE-Setup-<version>.sh` aus den [Releases](../../releases/latest) herunterladen, dann:

```bash
chmod +x TaskBoard-KDE-Setup-*.sh
./TaskBoard-KDE-Setup-*.sh
```

Das Setup
- findet Obsidian (Paket, Flatpak, Snap oder AppImage) und installiert es auf Wunsch mit (Flatpak, sonst AppImage),
- lässt dich einen vorhandenen Vault wählen oder einen neuen anlegen und verwendet eine vorhandene `Todo.md` weiter,
- installiert das Widget (als Seitenleiste am rechten Rand, auf dem Desktop oder beides) und richtet **Meta+Shift+T** als Tastenkürzel ein,
- braucht keine Root-Rechte.

Erinnerungen mit den Knöpfen „Erledigt“ / „In 15 Min nochmal“ brauchen `notify-send` (Paket `libnotify-bin` bzw. `libnotify`). GNOME-Unterstützung ist geplant.

Was sich in welcher Version geändert hat, steht im [CHANGELOG](CHANGELOG.md).

## Updates

Windows und KDE prüfen beim Start und danach alle 6 Stunden, ob es ein neues Release gibt, und aktualisiert sich dann selbst im Hintergrund. Die SHA-256-Prüfsumme des Downloads wird dabei kontrolliert. Einstellungen und Todo-Liste bleiben erhalten.

## Deinstallation

Windows: über Einstellungen → Apps. Linux: Startmenü → „Task Board entfernen“ oder Rechtsklick auf die Liste. `Todo.md` und `Todo-Archiv.md` in deinem Vault bleiben in beiden Fällen erhalten.

## Selbst bauen

Windows-Setup (Windows 10/11, [Inno Setup 7](https://jrsoftware.org/isinfo.php)):

```powershell
powershell -File build.ps1            # -> dist\TaskBoard-Setup-<version>.exe (+ Kopie mit altem Namen)
```

KDE-Setup (Linux oder WSL):

```bash
bash linux/build-kde.sh               # -> dist/TaskBoard-KDE-Setup-<version>.sh (+ Kopie mit altem Namen)
node linux/tests/core-test.js         # Tests für die Logik der KDE-Version
```

| Ordner | Inhalt |
|---|---|
| `src/build-skin.ps1` | erzeugt die Rainmeter-Dateien (`Todo.ini`, Formular, Einstellungen, Rand-Streifen) |
| `src/todo.lua`, `src/form.lua`, `src/sidebar.lua` | Logik der Liste, des Formulars und der Seitenleiste |
| `src/hotkey.cs` | kleines Programm für das globale Tastenkürzel |
| `src/google.cs` | Google Tasks: Anmeldung und Abgleich (Teil von `TaskBoardHotkey.exe`) |
| `src/notify.ps1`, `src/toast-action.vbs` | Windows-Erinnerungen und deren Knöpfe |
| `src/update.ps1` | automatische Updates über GitHub-Releases |
| `installer/` | Inno-Setup-Skript und Hilfsskript für Erkennung/Einrichtung |
| `linux/kde/package/` | KDE-Plasma-Widget (QML); `contents/code/todo.js` ist die Logik im selben Format wie `todo.lua` |
| `linux/kde/setup.sh`, `update.sh` | Linux-Setup und automatische Updates |
| `linux/kde/google-sync.py` | Google Tasks unter Linux, dieselben Regeln wie `src/google.cs` (Python 3, nur Standardbibliothek) |
| `linux/tests/` | Tests (Logik mit Node, Widget und Setup in einem KDE-Docker-Container) |

Google-Anbindung im Build: `.secrets/google-client.json` (Zugang zum Google-Cloud-Projekt, nicht im Repo) kommt beim Bauen in die Setups.

Für ein Release: Version in `VERSION` erhöhen, beide Builds ausführen, Release mit Tag `v<VERSION>` anlegen und **alle vier** Setups aus `dist` anhängen: `TaskBoard-Setup-<version>.exe`, `TaskBoard-KDE-Setup-<version>.sh` und die gleichen Kopien `ObsidianTodo-Setup-<version>.exe`, `ObsidianTodo-KDE-Setup-<version>.sh`. Die Updater erkennen die Dateien am Namensanfang: ab der Umbenennung `TaskBoard-…` (oder zur Not den alten Namen), Versionen bis 1.3.0 nur `ObsidianTodo-…` – deshalb die Kopien.

**Umzug von „Obsidian Todo“ (bis 1.3.0):** Seit der Umbenennung heißt auch intern alles Task Board (Rainmeter-Skin `TaskBoard`, `TaskBoardHotkey.exe`, Registry `HKCU\Software\TaskBoard`, KDE-ID `io.github.fantastesy.taskboard`, Ordner `~/.config/taskboard` usw.). Das Setup zieht eine alte Installation dabei selbst um – Liste, Einstellungen, Fensterposition und Tastenkürzel bleiben erhalten:
- Windows: `installer/helper.ps1` → `Move-OldInstall` (Laufzeitdateien übernehmen, Abschnitte in `Rainmeter.ini` umbenennen, alte Reste entfernen; ein Programmordner „Obsidian Todo“ wird zu „Task Board“ daneben).
- KDE: `linux/kde/setup.sh` → `migrate_files` und `migrate_widget` (altes Widget auslesen und entfernen, danach das neue an dieselbe Stelle setzen).

## Lizenz

[PolyForm Noncommercial 1.0.0](LICENSE): Du darfst Task Board kostenlos benutzen, verändern und weitergeben – privat, in der Schule, im Verein oder in anderen nicht-kommerziellen Einrichtungen. **Verkaufen oder kommerziell einsetzen ist nicht erlaubt.** Für eine kommerzielle Nutzung bitte den Urheber über GitHub fragen.

Versionen bis einschließlich Commit `d905f10` (1. November 2026) wurden unter der MIT-Lizenz veröffentlicht; für diese Stände gilt weiterhin MIT.

Rainmeter (GPL-2.0) und Obsidian werden nicht mitgeliefert, sondern bei Bedarf von den offiziellen Quellen geladen.
