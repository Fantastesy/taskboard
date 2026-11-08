# Änderungen

## 2.0.0 – noch nicht veröffentlicht

### Windows und Linux (KDE)
- **Google Tasks als Speicher:** Deine Einträge können jetzt in deinem Google-Konto liegen, allein oder zusammen mit Obsidian. Im Zahnrad gibt es dafür „Speichern in“ mit zwei Häkchen; mindestens eins bleibt an. Sind beide an, werden `Todo.md` und die Google-Liste in beide Richtungen abgeglichen, kurz nach jeder Änderung und sonst alle 2 Minuten.
- **Neuinstallation:** Das Setup fragt mit denselben zwei Häkchen, wo gespeichert werden soll, und meldet dich auf Wunsch gleich bei Google an. Bei Updates bleibt alles, wie es ist.
- **„Liste wählen …“ und „Verbindung trennen“** im Zahnrad. Ohne Obsidian öffnet ein Klick auf den Titel Google Tasks.
- **Felder bei Google:** Titel, Datum, Notizen, Unteraufgaben, Erledigt und Reihenfolge stehen in den normalen Feldern. Uhrzeit, Wiederholung, Tags und das Erstellt-Datum stehen in der letzten Zeile der Beschreibung, weil Googles Schnittstelle dafür keine Felder hat.
- **Schutz vor Datenverlust:** Ändern beide Seiten dasselbe Feld, gewinnt der PC. Bei Google gelöschte Einträge kommen ins Archiv. Verschwindet viel auf einmal, wartet der Abgleich 30 Minuten. Nutzen zwei PCs denselben Vault, gleicht nur einer ab.
- Hakst du einen Hauptpunkt ab, setzt Google seine Unteraufgaben ebenfalls auf erledigt.

### Linux (KDE)
- Für Google Tasks wird Python 3 gebraucht (bei Kubuntu, Fedora KDE usw. dabei).

## 1.4.0 – 7. November 2026

### Windows und Linux (KDE)
- **Neuer Name: Task Board** (früher „Obsidian Todo“). Setup, Programmliste, Startmenü („Task Board entfernen“), Einstellungen und Widget heißen jetzt so – auch alle Ordner und Einträge im System. Das Update zieht eine bestehende Installation automatisch um; Liste, Einstellungen, Position und Tastenkürzel bleiben erhalten. Unter Windows wird ein Programmordner „Obsidian Todo“ zu „Task Board“ am selben Ort. Die Setup-Dateien heißen `TaskBoard-Setup-<version>.exe` und `TaskBoard-KDE-Setup-<version>.sh`, das Projekt auf GitHub heißt `taskboard` (alte Links leiten weiter).

### Windows
- **Rainmeter startet nach dem Setup zuverlässig:** Musste das Setup Rainmeter selbst starten, stürzte es dabei manchmal ab und die Liste fehlte bis zum nächsten Neustart. Jetzt wird Rainmeter wie per Doppelklick gestartet.
- **Kein zweites Rainmeter mehr:** Ein portables Rainmeter, das beim Setup gerade nicht lief, wurde nicht gefunden – das Setup installierte dann ein zweites. Jetzt merkt es sich den Ort (und schaut in der Autostart-Verknüpfung nach); bei einem Update wird nie ein zweites Rainmeter installiert.

### Linux (KDE)
- **Neue Liste landet oben rechts:** Bei der Erstinstallation erschien die Liste in der Bildschirmmitte statt oben rechts.

## 1.3.0 – 7. November 2026

### Windows und Linux (KDE)
- **Punkte verschieben:** Einen Punkt mit der Maus an eine andere Stelle ziehen – eine Linie zeigt, wo er landet. Die Reihenfolge steht danach so in der Todo.md (auch in Obsidian). Ein normaler Klick hakt weiterhin ab.
- **Neue Punkte mit Datum kommen von selbst nach oben** (nach Fälligkeit zwischen die anderen Punkte mit Datum). Man kann sie danach trotzdem woandershin ziehen – sie bleiben dann dort. Beim ersten Start wird die Todo.md einmal so geordnet, wie die Liste bisher aussah.
- **Farbige Tags:** In den Einstellungen eigene Tags anlegen (Klick auf einen Tag = andere Farbe, × = entfernen) und sie im Formular einem Punkt zuweisen. In der Liste erscheinen sie als farbige Etiketten, in der Datei als Obsidian-Tag `#arbeit`.
- **„Nach Updates suchen“** in den Einstellungen. Gibt es eine neue Version, erscheint „Jetzt aktualisieren“ – sie wird sofort installiert und die Liste lädt neu, ohne Abmelden.
- **Hintergrund:** „Durchsichtig“ ist jetzt wirklich ganz durchsichtig, „Normal“ und „Leicht“ sind durchsichtiger als vorher. Eine feine Umrandung zeigt immer, wo der Kasten ist. Die bisherige Einstellung wird automatisch übernommen. Bei „Durchsichtig“ hat die Schrift einen leichten Schatten und bleibt so auch auf hellem Hintergrund lesbar. In der Seitenleiste ist der Kasten nur so hoch wie die Einträge, nicht mehr so hoch wie der ganze Bildschirm.
- **Rausklicken löscht nichts mehr:** Wer im Formular den Namen eintippt und dann direkt ins Notizfeld (oder irgendwo anders hin) klickt, behält den Text – vorher war er weg. Gilt auch für Notizen und Unteraufgaben in der Liste und für neue Tags. Ein leeres Feld verschwindet einfach; ein ganzer Eintrag wird beim Rausklicken aber nie gelöscht.
- Kurzhilfe ergänzt (Ziehen).
- **Namensfeld sitzt wieder in der Zeile (Windows):** Beim neuen Eintrag konnte das Eingabefeld über dem Formular hängen bleiben, danach ließ sich nichts mehr anklicken. Jetzt öffnet es sich erst, wenn das Formular an seinem Platz steht. Fällt der Helfer im Hintergrund aus, der das Rausklicken erkennt, startet er von selbst neu, statt alles zu blockieren.
- **Mauszeiger nach dem Tippen (Windows):** Mit der Windows-Einstellung „Zeiger während der Eingabe ausblenden“ blieb der Zeiger über der Liste und dem Formular unsichtbar, bis man rausfuhr. Jetzt ist er bei der ersten Mausbewegung wieder da.
- **Neue Notiz im Formular (Windows):** Das Eingabefeld öffnet sich in einer neuen Notizzeile statt auf dem Knopf „+ Notiz / Link“. Bleibt sie leer (oder Esc), verschwindet sie wieder.
- **Eingeklappte Liste (Windows):** Das unsichtbare Fenster darunter war noch so groß wie die ganze Liste und fing Klicks auf den Desktop ab. Jetzt ist es nur so groß wie die Kopfzeile.
- **Klick in eine freie Stelle der Liste (Linux)** übernimmt eine offene Notiz oder Unteraufgabe, wie ein Klick außerhalb.
- In der Kurzhilfe heißt es jetzt überall „Eintrag“ statt „Punkt“.
- **„Beides“ (Windows):** Wurde die Liste neu geladen (z. B. Einstellung geändert), während sie als Seitenleiste am Rand stand, landete sie danach an der falschen Stelle. Jetzt kehrt sie an ihren Desktop-Platz zurück.
- **„Durchsichtig“ (Linux) sieht jetzt aus wie unter Windows:** scharfe Schrift mit hartem dunklem Schatten (1 Pixel nach rechts unten) statt des verwaschenen Schattens; Tags mit gleicher Fläche und kräftigerem Rand wie unter Windows.
- **Notiz im Formular (Linux):** Nach „+ Notiz / Link“ landete das Getippte im Namensfeld. Jetzt springt der Cursor in die neue Notizzeile. Bleibt sie leer, verschwindet sie wieder.
- **KDE: Abmelden und Neustart hängen nicht mehr:** Die Seitenleiste war für KDE ein Dock-Fenster, das sich beim Abmelden nicht schließen ließ („Plasma-Arbeitsflächenbereich hat sich nicht beendet“, bis zu 2 Minuten Warten). Jetzt geht das Abmelden sofort, auch wenn die Liste gerade ausgefahren ist.

### Nur Linux (KDE)
- Updates über „Jetzt aktualisieren“ starten Plasma am Ende selbst neu, damit die neue Version sofort da ist.

## 1.2.2 – 2. November 2026

### Nur Linux (KDE)
- **Datum wählen zeigte unter Kubuntu/Ubuntu keinen Kalender** (keine Tageszahlen, Qt 6.10). Der Kalender ist jetzt selbst gebaut und funktioniert überall. Das Formular wird außerdem nie höher als der Bildschirm; passt es nicht, lässt es sich scrollen.
- Kurzhilfe in den Einstellungen: Verschieben auf dem Desktop geht an der Kopfzeile (nicht mehr über den Bearbeitungsmodus).
- **Update von Hand zeigte weiter die alte Liste:** Plasma behielt die alte Widget-Version im Speicher, bis man sich neu anmeldete (keine Einstellungen, keine Seitenleiste). Das Setup startet Plasma jetzt am Ende neu, dann ist die neue Version sofort da. Der Bildschirm flackert dabei kurz.

### Windows
- Keine Änderungen (gleiche Version wie 1.2.1, nur neue Nummer).

## 1.2.1 – 2. November 2026

### Windows und Linux (KDE)
- **Seitenleiste:** Der Rand reagiert nur noch im mittleren Teil. Oben und unten bleiben je 20 % der Bildschirmhöhe frei, so öffnet die Liste nicht mehr, wenn man in eine Ecke fährt (Schließen-Knopf, Uhr).

### Nur Linux (KDE)
- Das Setup läuft jetzt auch unter Kubuntu/Ubuntu: Dort fehlt das Werkzeug `kpackagetool6`, mit dem 1.2.0 abbrach. Das Setup kopiert das Widget dann selbst an die richtige Stelle.

## 1.2.0 – 2. November 2026

### Windows und Linux (KDE Plasma 6) – beide sehen jetzt gleich aus
- **Seitenleiste:** Fährt die Maus an den Bildschirmrand, gleitet die Liste als bildschirmhohes Panel herein und nach dem Wegfahren wieder hinaus. Solange die Maus am Rand oder in der Liste ist, bleibt sie offen. Wahlweise am rechten oder linken Rand.
- **Anzeige:** Seitenleiste, Desktop oder Beides. Bei „Beides“ liegt die Liste auf dem Desktop, blendet am Rand sanft aus und gleitet als Panel herein.
- **Einstellungen (Zahnrad statt „?“)** – sortiert nach Aussehen und Verhalten:
  - Aussehen: Anzeige, Seite, Breite, Schriftgröße, Hintergrund (deckend bis durchsichtig), Akzentfarbe (6 Farben)
  - Verhalten: Tempo der Seitenleiste, Einblenden beim Anmelden/Aufwachen (Sekunden pro Punkt oder aus), Erinnerungen (pünktlich, 5 oder 15 Minuten vorher, aus), Tastenkürzel (anklicken und neue Kombination drücken; „Zurücksetzen“), Todo-Datei wechseln, automatische Updates an/aus
  - darunter die Kurzhilfe, „Archiv öffnen“ und die Versionsnummer
- **Richtige Knöpfe:** Zahnrad, Pfeil, Büroklammer und „+ Neuer Punkt“ mit Rand und Hover-Effekt; Klickflächen nur noch so groß wie ihr Inhalt (ein Klick neben einen Punkt hakt ihn nicht mehr ab).
- In der Seitenleiste gibt es keinen Einklapp-Pfeil (die Liste ist dort ohnehin bildschirmhoch).
- Einstellungen und Formular lassen sich an der Titelzeile verschieben.

### Nur Windows
- **Wer die Liste schon hatte, behält nach dem Update „Desktop“.** Neuinstallationen starten mit der Seitenleiste. Umschalten: Zahnrad → Anzeige.
- Beim Tastenkürzel wird geprüft, ob ein anderes Programm die Kombination schon belegt.

### Nur Linux (KDE)
- Keine eigene KDE-Leiste mehr: Die Liste ist immer ein Widget auf dem Desktop, die Seitenleiste macht das Widget selbst (ohne hellen Plasma-Rahmen). Eine Seitenleiste aus 1.1.x wird beim Update automatisch umgebaut; die neue Ansicht erscheint nach dem nächsten Anmelden.
- Die Liste auf dem Desktop lässt sich direkt an der Kopfzeile verschieben (ohne Bearbeitungsmodus).
- Die Anzeige wird im Zahnrad-Fenster umgeschaltet statt im Rechtsklick-Menü.
## 1.1.1 – 2. November 2026

### Windows
- Hat das Setup Rainmeter erst mitinstalliert, wurde die Liste danach nicht eingeschaltet (das Rainmeter-Setup startet Rainmeter mit Adminrechten, Windows blockiert dann den Befehl zum Aktivieren). Die Liste wird jetzt fest in Rainmeters Einstellungen eingetragen, Rainmeter normal gestartet, und das Setup prüft am Ende, ob die Liste wirklich zu sehen ist.

**Wer 1.1.0 schon installiert hat und die Liste nicht sieht:** Rechtsklick auf das Rainmeter-Symbol unten rechts → Skins → ObsidianTodo → Todo.ini. Das Update auf 1.1.1 kommt automatisch.

## 1.1.0 – 1. November 2026

### Windows
- Die Liste kommt beim Anmelden, Aufwachen und Entsperren kurz nach vorne (10 Sekunden pro offenem Punkt, höchstens 2 Minuten), mit „Ausblenden ✕“ oben rechts. Ist die Todo.md direkt nach dem Hochfahren noch nicht lesbar (z. B. Cloud-Ordner), wird das Einblenden nachgeholt.
- Breite einstellbar im Hilfe-Fenster (schmal / normal / breit); bleibt bei Updates erhalten.
- „Obsidian To-do entfernen“ im Startmenü.
- Das Setup erkennt eine vorhandene Installation oder eine von Hand eingerichtete Liste und übernimmt die Todo-Liste, ohne erneut nach dem Vault zu fragen.
- Ein bereits laufendes (auch portables) Rainmeter wird zuverlässig erkannt; es wird nie ein zweites installiert.
- Bei einer Erstinstallation sitzt die Liste oben rechts auf dem Desktop.

### Linux (KDE Plasma 6)
- Neue Anzeige „Seitenleiste“: ein unsichtbarer Streifen am rechten Bildschirmrand. Fährt die Maus an den Rand, kommt er herein und die Liste klappt daneben auf; Maus weg → zu.
- Beim Anmelden, Aufwachen und Entsperren klappt die Liste kurz von selbst auf, mit „Ausblenden“.
- Anzeige umschaltbar per Rechtsklick auf die Liste: Seitenleiste, Desktop oder beides.
- „Obsidian To-do entfernen“ im Startmenü und im Rechtsklick-Menü.
- Gleicher Look wie unter Windows (dunkel, halbdurchsichtig, lila Kästchen).

### Beide
- Setup-Dateien tragen die Versionsnummer im Namen; die automatischen Updates erkennen sie trotzdem.
- Lizenz: PolyForm Noncommercial 1.0.0 (frei nutzbar, nicht kommerziell).

**Hinweis für Linux-Nutzer von 1.0.0:** 1.0.0 kennt nur den alten Dateinamen ohne Versionsnummer und findet 1.1.0 deshalb nicht von selbst. Bitte einmal von Hand installieren (siehe unten); danach kommen Updates wieder automatisch.

## 1.0.0 – 1. November 2026

Erste Version: Windows (Rainmeter) mit Setup und automatischen Updates, Linux als KDE-Plasma-6-Widget.

---

## Installation

**Windows:** `ObsidianTodo-Setup-<version>.exe` aus den [Releases](../../releases/latest) herunterladen und starten. Windows zeigt evtl. „Der Computer wurde durch Windows geschützt“ → „Weitere Informationen“ → „Trotzdem ausführen“.

**Linux (KDE Plasma 6):** `ObsidianTodo-KDE-Setup-<version>.sh` aus den [Releases](../../releases/latest) herunterladen, dann im Terminal:

```bash
chmod +x ObsidianTodo-KDE-Setup-*.sh
./ObsidianTodo-KDE-Setup-*.sh
```

Danach aktualisieren sich beide Versionen automatisch.
