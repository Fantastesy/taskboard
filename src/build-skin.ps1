# Erzeugt die Rainmeter-Dateien Todo.ini, Formular\Formular.ini, Einstellungen\Einstellungen.ini und Rand\Rand.ini (UTF-16 LE).
# Aufruf: powershell -File build-skin.ps1 -Out <Skin-Ordner> [-Version 1.0.0]
# Benutzerabhaengige Werte (Pfad zur Todo.md, Vault-Name) stehen in @Resources\settings.inc,
# die der Installer schreibt - hier nur Platzhalter.
param([Parameter(Mandatory)][string]$Out, [string]$Version = '0.0.0')
$skin = $Out
New-Item -ItemType Directory -Force $skin | Out-Null
$box = [char]0xE739      # Checkbox (abgerundetes Quadrat)
$boxDone = [char]0xE73D  # CheckboxCompositeReversed (ausgefuellt mit Haken)
$clip = [char]0xE723     # Attach (Bueroklammer)
$cal = [char]0xE787      # Calendar
$rep = [char]0xE8EE      # RepeatAll (wiederkehrend)
$gear = [char]0xE713     # Setting (Zahnrad)
$close = [char]0xE711    # Cancel (X)

# Symbol-Knopf in der Liste: abgerundete, dunkle Flaeche mit Rand (das Symbol liegt als eigener String-Meter
# darueber und hat keine Maus-Aktionen, damit Klicks auf die Flaeche durchgehen)
function IconBtn($name, $x, $y, $h, $action, $w = 0) {
    if (-not $w) { $w = $h }
    $rect = "Rectangle 0.5,0.5,$($w - 1),$($h - 1),7 | StrokeWidth 1 | Stroke Color #ColorBtnStroke# | Fill Color"
@"
[${name}Btn]
Meter=Shape
X=$x
Y=$y
DynamicVariables=1
Shape=$rect #ColorBtnFill#
MouseOverAction=[!SetOption ${name}Btn Shape "$rect #ColorBtnHover#"][!UpdateMeter ${name}Btn][!Redraw]
MouseLeaveAction=[!SetOption ${name}Btn Shape "$rect #ColorBtnFill#"][!UpdateMeter ${name}Btn][!Redraw]
LeftMouseUpAction=$action

"@
}
$foldUp = [char]0xE70E   # ChevronUp (Liste offen -> einklappen)
$foldDown = [char]0xE70D # ChevronDown (Liste zu -> ausklappen)
$obs = '["obsidian://open?path=#TodoUrl#"]'

$ini = @"
; Obsidian Todo: Desktop-Liste fuer eine Todo.md im Obsidian-Vault
; Erzeugt von build-skin.ps1 - Aenderungen dort machen.
[Rainmeter]
Update=1000
AccurateText=1
DynamicWindowSize=1
; Tastenkuerzel-Helfer (Strg+Alt+T bzw. Win+Shift+T -> Neuer Punkt); laeuft nur einmal, bleibt bei Refresh bestehen
OnRefreshAction=["#@#TaskBoardHotkey.exe" "#PROGRAMPATH#Rainmeter.exe"]
ContextTitle=Todo.md in Obsidian öffnen
ContextAction=$obs
; Seitenleiste: Maus in der Liste haelt sie offen, Verlassen laesst sie hinausfahren (sidebar.lua)
MouseOverAction=[!CommandMeasure MeasureSide "Enter()" "TaskBoard\Rand"]
MouseLeaveAction=[!CommandMeasure MeasureSide "Leave()" "TaskBoard\Rand"][!CommandMeasure MeasureTodo "DragCancel()"]

[Metadata]
Name=Task Board
Author=Fantastesy
Version=$Version
License=PolyForm Noncommercial 1.0.0
Information=Zeigt die Checkboxen aus Todo.md im Obsidian-Vault an.

[Variables]
; Platzhalter - die echten Werte kommen aus settings.inc (schreibt der Installer)
TodoFile=#@#Todo.md
ArchiveFile=#@#Todo-Archiv.md
VaultName=
TodoUrl=
ArchiveUrl=
@IncludeSettings=#@#settings.inc
MaxItems=15
MaxNotes=30
MaxSubs=30
Width=460
; Einstellungen (Standardwerte; prefs.inc/colors.inc am Ende ueberschreiben sie):
; Anzeige sidebar|desktop|both, Seite right|left, Tempo fast|normal|slow, Einblenden Sekunden pro Punkt (0 = aus)
Mode=sidebar
LastMode=
Side=right
Speed=normal
RevealPerItem=10
RemindOn=1
RemindLead=0
AutoUpdate=1
Hotkey=
; eigene Tags mit Farbe (Einstellungen): "arbeit:blau,privat:pink"
Tags=
; 1 = Datei wurde einmal nach der alten Anzeige sortiert (seit 1.3.0 gilt die Reihenfolge in der Datei)
ManualOrder=0
Accent=lila
Opacity=170
; Symbol-Knoepfe (Zahnrad, Pfeil, Bueroklammer): dunkler und deckender als die Liste
ColorBtnFill=22,22,30,235
ColorBtnHover=48,48,62,245
ColorBtnStroke=255,255,255,48
AddW=130
RowH=36
NoteH=30
ListTop=62
FontFace=Segoe UI
IconFace=Segoe Fluent Icons
FontSize=13
ColorBg=12,12,18,170
ColorBorder=255,255,255,40
ColorText=255,255,255,255
ColorDone=175,175,188,240
ColorNote=232,232,240,255
ColorBox=200,200,212,255
ColorCheck=138,108,245,255
ColorAccent=165,185,255,255
ColorHover=255,255,255,22
BoxOpen=$box
BoxDone=$boxDone
ClipIcon=$clip
LinkArrow=↗
DueIcon=📅
CreatedIcon=➕
DoneIcon=✅
CancelIcon=❌
CalIcon=$cal
RepIcon=$rep
RepeatIcon=🔁
TimeIcon=⏰
NotifyText=
ColorOver=255,115,115,255
ColorToday=255,185,90,255
ColorDue=175,175,188,240
Collapsed=0
FoldOpen=$foldUp
FoldClosed=$foldDown
NewItem=
EditText=
EditX=12
EditY=0
EditW=400
; eigene Einstellungen (schreibt das Einstellungen-Fenster; bleiben bei Updates erhalten) - zuletzt, damit sie gewinnen
@IncludePrefs=#@#prefs.inc
@IncludeColors=#@#colors.inc

[MeasureTodo]
Measure=Script
ScriptFile=#@#todo.lua
UpdateDivider=2

[MeasureInput]
Measure=Plugin
Plugin=InputText
DynamicVariables=1
X=16
Y=[MeterAdd:Y]
W=(#Width#-32)
H=#RowH#
SolidColor=32,32,42,255
FontColor=#ColorText#
FontFace=#FontFace#
FontSize=#FontSize#
FocusDismiss=1
DefaultValue=
Command1=[!SetVariable NewItem """`$UserInput`$"""][!CommandMeasure MeasureTodo "Add()"]

[MeasureEdit]
Measure=Plugin
Plugin=InputText
DynamicVariables=1
X=#EditX#
Y=#EditY#
W=#EditW#
H=#RowH#
SolidColor=32,32,42,255
FontColor=#ColorText#
FontFace=#FontFace#
FontSize=#FontSize#
; bleibt beim Rausklicken offen, TaskBoardHotkey.exe --commit uebernimmt dann den Text (todo.lua openEditor)
FocusDismiss=0
DefaultValue=#EditText#
Command1=[!SetVariable NewItem """`$UserInput`$"""][!CommandMeasure MeasureTodo "SaveEdit()"]
OnDismissAction=[!CommandMeasure MeasureTodo "EditCancel()"]

[MeasureFilePick]
Measure=Plugin
Plugin=RunCommand
Program=powershell.exe
Parameter=-NoProfile -ExecutionPolicy Bypass -STA -File "#@#pick-file.ps1"
State=Hide
OutputType=UTF8
Timeout=-1
FinishAction=[!CommandMeasure MeasureTodo "FilePicked()"]

; Windows-Erinnerung fuer Punkte mit Uhrzeit (Text setzt todo.lua)
[MeasureNotify]
Measure=Plugin
Plugin=RunCommand
Program=powershell.exe
Parameter=-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "#@#notify.ps1" "#NotifyText#"
State=Hide
DynamicVariables=1
Timeout=-1

; Automatische Updates: beim Laden und dann alle 6 Stunden (update.ps1 prueft selbst hoechstens alle 6 h bei GitHub)
[MeasureUpdate]
Measure=Plugin
Plugin=RunCommand
Program=powershell.exe
Parameter=-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "#@#update.ps1"
State=Hide
Timeout=-1

[MeasureUpdateTimer]
Measure=Calc
Formula=1
UpdateDivider=21600
OnUpdateAction=[!CommandMeasure MeasureUpdate "Run"]

[MeterBg]
Meter=Shape
DynamicVariables=1
Shape=Rectangle 0.5,0.5,(#Width#-1),119,12 | Fill Color #ColorBg# | StrokeWidth 1 | Stroke Color #ColorBorder#

[MeterTitle]
Meter=String
X=20
Y=16
FontFace=#FontFace#
FontSize=(#FontSize#+4)
FontWeight=700
FontColor=#ColorText#
AntiAlias=1
Text=Todo
LeftMouseUpAction=$obs
ToolTipText=In Obsidian öffnen

[MeterCount]
Meter=String
DynamicVariables=1
; beim Einblenden steht hier "Ausblenden" (todo.lua)
LeftMouseUpAction=[!CommandMeasure MeasureTodo "HideReveal(true)"]
X=(#Width#-62)
Y=22
StringAlign=Right
FontFace=#FontFace#
FontSize=(#FontSize#-1)
FontWeight=500
FontColor=#ColorDone#
AntiAlias=1
Text=

; Zahnrad neben dem Titel: Einstellungen ein-/ausblenden
$(IconBtn 'Gear' 84 14 32 '[!ToggleConfig "TaskBoard\Einstellungen" "Einstellungen.ini"]')
[MeterHelp]
Meter=String
X=100
Y=30
StringAlign=CenterCenter
FontFace=#IconFace#
FontSize=(#FontSize#-2)
FontColor=#ColorDone#
AntiAlias=1
Text=$gear

; Pfeil zum Ein-/Ausklappen der ganzen Liste (ohne Tooltip: der bliebe beim Herein-/Hinausfahren stehen)
$(IconBtn 'Fold' '(#Width#-50)' 14 32 '[!CommandMeasure MeasureTodo "ToggleCollapse()"]')
[MeterFold]
Meter=String
DynamicVariables=1
X=(#Width#-34)
Y=30
StringAlign=CenterCenter
FontFace=#IconFace#
FontSize=(#FontSize#-3)
FontColor=#ColorDone#
AntiAlias=1
Text=#FoldOpen#


"@

# Checkbox-Zeile: Kaestchen als eigener Meter (<name>Box, Icon-Schrift, Farbe per Lua),
# Text rechts daneben, damit umgebrochene Zeilen unter dem Text weiterlaufen
function CheckMeter($name, $x, $h, $size, $weight, $left, $right, $tip) {
    $tx = $x + 33
@"
[${name}Box]
Meter=String
DynamicVariables=1
Hidden=1
X=$x
Y=0
W=30
Padding=8,13,0,0
FontFace=#FontFace#
FontSize=$size
FontWeight=$weight
FontColor=#ColorText#
SolidColor=0,0,0,1
AntiAlias=1
InlinePattern=^(.)
InlineSetting=Face | #IconFace#
InlinePattern2=^(.)
InlineSetting2=Size | ($size-2)
InlinePattern3=^(.)
InlineSetting3=
Text=
LeftMouseUpAction=$left
RightMouseUpAction=$right

[$name]
Meter=String
DynamicVariables=1
Hidden=1
X=$tx
Y=0
ClipStringW=(#Width#-96-33)
Padding=0,6,8,6
ClipString=2
FontFace=#FontFace#
FontSize=$size
FontWeight=$weight
FontColor=#ColorText#
SolidColor=0,0,0,1
AntiAlias=1
InlinePattern=([$cal$rep].*)`$
InlineSetting=Color | #ColorDue#
InlinePattern2=([$cal$rep])
InlineSetting2=Face | #IconFace#
InlinePattern3=([$cal$rep].*)`$
InlineSetting3=Size | ($size-2)
InlinePattern4=^(.*)`$
InlineSetting4=
Text=
LeftMouseUpAction=$left
RightMouseUpAction=$right
MouseOverAction=[!SetOption $name SolidColor "#ColorHover#"][!UpdateMeter $name][!Redraw]
MouseLeaveAction=[!SetOption $name SolidColor "0,0,0,1"][!UpdateMeter $name][!Redraw]


"@
}
for ($i = 1; $i -le 15; $i++) {
    # Druecken auf den Text startet das Ziehen (todo.lua DragStart); ein normaler Klick hakt trotzdem ab
    $ini += (CheckMeter "Item$i" 12 '#RowH#' '#FontSize#' 600 "[!CommandMeasure MeasureTodo `"Toggle($i)`"]" "[!CommandMeasure MeasureTodo `"Edit($i)`"]" 'Linksklick: abhaken | Rechtsklick: bearbeiten').Replace(
        "[Item$i]`r`nMeter=String", "[Item$i]`r`nMeter=String`r`nLeftMouseDownAction=[!CommandMeasure MeasureTodo `"DragStart($i)`"]").Replace(
        "[Item$i]`nMeter=String", "[Item$i]`nMeter=String`nLeftMouseDownAction=[!CommandMeasure MeasureTodo `"DragStart($i)`"]")
    # Tags als farbige Etiketten hinter dem Text (Text, Farben und Position setzt todo.lua)
    for ($k = 1; $k -le 3; $k++) {
        # abgerundete Flaeche hinter dem Etikett (Pillenform, Groesse setzt todo.lua)
        $ini += "[TagBg${i}_$k]`r`nMeter=Shape`r`nHidden=1`r`nX=0`r`nY=0`r`nShape=Rectangle 0,0,1,1 | StrokeWidth 0`r`n`r`n"
        $ini += "[Tag${i}_$k]`r`nMeter=String`r`nDynamicVariables=1`r`nHidden=1`r`nX=0`r`nY=0`r`nPadding=10,3,10,4`r`nFontFace=#FontFace#`r`nFontSize=(#FontSize#-3)`r`nFontWeight=600`r`nFontColor=255,255,255,255`r`nSolidColor=0,0,0,0`r`nAntiAlias=1`r`nText=`r`n`r`n"
    }
}
for ($i = 1; $i -le 30; $i++) {
    $ini += CheckMeter "Sub$i" 36 '#NoteH#' '(#FontSize#-1)' 500 "[!CommandMeasure MeasureTodo `"ToggleSub($i)`"]" "[!CommandMeasure MeasureTodo `"EditSub($i)`"]" 'Unteraufgabe - Linksklick: abhaken | Rechtsklick: bearbeiten'
}
for ($i = 1; $i -le 15; $i++) {
$ini += @"
[Progress$i]
Meter=String
DynamicVariables=1
Hidden=1
X=(#Width#-136)
Y=0
W=50
H=#RowH#
Padding=0,7,0,0
StringAlign=Left
FontFace=#FontFace#
FontSize=(#FontSize#-2)
FontWeight=500
FontColor=#ColorDone#
AntiAlias=1
Text=

$((IconBtn "Clip$i" '(#Width#-66)' 0 30 "[!CommandMeasure MeasureTodo `"ToggleNotes($i)`"]" 52).Replace('Meter=Shape', "Meter=Shape`r`nHidden=1"))
; Bueroklammer + Anzahl, mittig auf ClipBtn$i (Y setzt todo.lua)
[Clip$i]
Meter=String
DynamicVariables=1
Hidden=1
X=(#Width#-40)
Y=0
StringAlign=Center
FontFace=#FontFace#
FontSize=(#FontSize#-1)
FontWeight=500
FontColor=#ColorDone#
AntiAlias=1
InlinePattern=^(.)
InlineSetting=Face | #IconFace#
InlinePattern2=^(.)
InlineSetting2=Size | (#FontSize#+1)
Text=

[NoteAdd$i]
Meter=String
DynamicVariables=1
Hidden=1
X=46
Y=0
H=#NoteH#
Padding=2,4,4,0
FontFace=#FontFace#
FontSize=(#FontSize#-2)
FontWeight=500
FontColor=#ColorAccent#
SolidColor=0,0,0,1
AntiAlias=1
Text=+ Notiz
LeftMouseUpAction=[!CommandMeasure MeasureTodo "AddNote($i)"]

[SubAdd$i]
Meter=String
DynamicVariables=1
Hidden=1
X=150
Y=0
H=#NoteH#
Padding=2,4,4,0
FontFace=#FontFace#
FontSize=(#FontSize#-2)
FontWeight=500
FontColor=#ColorAccent#
SolidColor=0,0,0,1
AntiAlias=1
Text=+ Unteraufgabe
LeftMouseUpAction=[!CommandMeasure MeasureTodo "AddSub($i)"]

[FileAdd$i]
Meter=String
DynamicVariables=1
Hidden=1
X=302
Y=0
H=#NoteH#
Padding=2,4,4,0
FontFace=#FontFace#
FontSize=(#FontSize#-2)
FontWeight=500
FontColor=#ColorAccent#
SolidColor=0,0,0,1
AntiAlias=1
Text=+ Datei
LeftMouseUpAction=[!CommandMeasure MeasureTodo "PickFile($i)"]


"@
}
for ($i = 1; $i -le 30; $i++) {
$ini += @"
[Note$i]
Meter=String
DynamicVariables=1
Hidden=1
X=46
Y=0
ClipStringW=(#Width#-66)
Padding=0,4,0,4
ClipString=2
FontFace=#FontFace#
FontSize=(#FontSize#-2)
FontWeight=500
FontColor=#ColorNote#
SolidColor=0,0,0,1
AntiAlias=1
InlinePattern=^(.*)`$
InlineSetting=
Text=
RightMouseUpAction=[!CommandMeasure MeasureTodo "EditNote($i)"]


"@
}
$ini += @"
[MeterMore]
Meter=String
DynamicVariables=1
Hidden=1
X=20
Y=0
FontFace=#FontFace#
FontSize=(#FontSize#-1)
FontWeight=500
FontColor=#ColorDone#
AntiAlias=1
Text=
LeftMouseUpAction=$obs

; "+ Neuer Punkt" als Knopf wie Zahnrad/Pfeil: Flaeche (Breite AddW setzt todo.lua nach der Textbreite) + Text
[AddBtn]
Meter=Shape
DynamicVariables=1
X=12
Y=0
Shape=Rectangle 0.5,0.5,#AddW#,31,7 | StrokeWidth 1 | Stroke Color #ColorBtnStroke# | Fill Color #ColorBtnFill#
MouseOverAction=[!SetOption AddBtn Shape "Rectangle 0.5,0.5,#AddW#,31,7 | StrokeWidth 1 | Stroke Color #ColorBtnStroke# | Fill Color #ColorBtnHover#"][!UpdateMeter AddBtn][!Redraw]
MouseLeaveAction=[!SetOption AddBtn Shape "Rectangle 0.5,0.5,#AddW#,31,7 | StrokeWidth 1 | Stroke Color #ColorBtnStroke# | Fill Color #ColorBtnFill#"][!UpdateMeter AddBtn][!Redraw]
LeftMouseUpAction=[!CommandMeasure MeasureTodo "OpenDialog(0)"]

[MeterAdd]
Meter=String
DynamicVariables=1
X=24
Y=0
FontFace=#FontFace#
FontSize=#FontSize#
FontWeight=600
FontColor=#ColorAccent#
AntiAlias=1
Text=+ Neuer Eintrag

[MeterClean]
Meter=String
DynamicVariables=1
Hidden=1
X=(#Width#-20)
Y=0
StringAlign=Right
FontFace=#FontFace#
FontSize=(#FontSize#-2)
FontWeight=500
FontColor=#ColorDone#
SolidColor=0,0,0,1
AntiAlias=1
Text=Erledigte archivieren
LeftMouseUpAction=[!CommandMeasure MeasureTodo "Cleanup()"]

; ---------- Ziehen (todo.lua DragStart/DragOver/DragDrop): nur waehrend des Ziehens sichtbar, ganz oben ----------
; DropAll faengt das Loslassen ausserhalb der Zeilen ab (= abbrechen), Drop1..15 liegen ueber den Zeilen
[DropAll]
Meter=Image
Hidden=1
X=0
Y=0
W=#Width#
H=400
SolidColor=0,0,0,1
LeftMouseUpAction=[!CommandMeasure MeasureTodo "DragCancel()"]

"@
for ($i = 1; $i -le 15; $i++) {
    $ini += "[Drop$i]`r`nMeter=Image`r`nHidden=1`r`nX=0`r`nY=0`r`nW=#Width#`r`nH=1`r`nSolidColor=0,0,0,1`r`nMouseOverAction=[!CommandMeasure MeasureTodo `"DragOver($i)`"]`r`nLeftMouseUpAction=[!CommandMeasure MeasureTodo `"DragDrop($i)`"]`r`n`r`n"
}
$ini += @"
; Linie, wo der gezogene Punkt landet
[DropLine]
Meter=Image
Hidden=1
DynamicVariables=1
X=12
Y=0
W=(#Width#-24)
H=3
SolidColor=#ColorCheck#
"@

$ini = [regex]::Replace($ini, '(?m)^(\[(?!Rainmeter\]|Metadata\]|Variables\]|Measure|MeterBg\]|MeterTitle\]|MeterCount\]|MeterFold\]|MeterHelp\]|GearBtn\]|FoldBtn\])[^\]]+\]\r?\n)', '$1Group=List'+"`r`n")
[IO.File]::WriteAllText("$skin\Todo.ini", $ini, [Text.Encoding]::Unicode)

# ---------- Formular: eigene Config TaskBoard\Formular (neuer Punkt / bearbeiten), Logik in form.lua ----------
$fw = 560
$chevL = [char]0xE76B; $chevR = [char]0xE76C
function Act($call) { '[!CommandMeasure MeasureForm "' + $call + '"]' }
function Label($name, $text) {
@"
[$name]
Meter=String
X=22
Y=0
FontFace=#FontFace#
FontSize=10
FontWeight=600
FontColor=#ColorDone#
AntiAlias=1
Text=$text


"@
}
# Knopf mit abgerundetem Hintergrund (die Flaeche zeichnet form.lua in MeterShapes)
function Chip($name, $x, $y, $text, $call, $extra = '') {
@"
[$name]
Meter=String
X=$x
Y=$y
Padding=12,6,12,6
FontFace=#FontFace#
FontSize=11
FontWeight=600
FontColor=#ColorNote#
SolidColor=0,0,0,1
AntiAlias=1
Text=$text
LeftMouseUpAction=$(Act $call)
$extra

"@
}
$form = @"
; Formular der Obsidian-Todo-Liste. Erzeugt von ..\@Resources\build-skin.ps1 - Aenderungen dort machen.
[Rainmeter]
Update=100
AccurateText=1
DynamicWindowSize=1

[Variables]
Width=$fw
FontFace=Segoe UI
IconFace=Segoe Fluent Icons
ColorBg=12,12,18,235
ColorText=255,255,255,255
ColorNote=225,225,235,255
ColorDone=175,175,188,240
ColorAccent=165,185,255,255
ColorCheck=138,108,245,255
ColorOver=255,115,115,255
Input=
InText=
InX=20
InY=0
InW=480
InH=34
InSize=12
InStyle=Normal
; Akzentfarbe aus dem Einstellungen-Fenster
@IncludeColors=#@#colors.inc

[MeasureInput]
Measure=Plugin
Plugin=InputText
DynamicVariables=1
X=#InX#
Y=#InY#
W=#InW#
H=#InH#
; Farbe wie die Feldflaeche, damit das Eingabefeld nicht als eigener Kasten auffaellt
SolidColor=30,32,39,255
FontColor=#ColorText#
FontFace=#FontFace#
FontSize=#InSize#
StringStyle=#InStyle#
; bleibt beim Rausklicken offen, TaskBoardHotkey.exe --commit uebernimmt dann den Text (form.lua openInput)
FocusDismiss=0
OnDismissAction=[!CommandMeasure MeasureForm "InputCancel()"]
DefaultValue=#InText#
Command1=[!SetVariable Input """`$UserInput`$"""][!CommandMeasure MeasureForm "InputDone()"]

[MeasureFilePick]
Measure=Plugin
Plugin=RunCommand
Program=powershell.exe
Parameter=-NoProfile -ExecutionPolicy Bypass -STA -File "#@#pick-file.ps1"
State=Hide
OutputType=UTF8
Timeout=-1
FinishAction=[!CommandMeasure MeasureForm "FilePicked()"]

; Logik nach den Eingabe-Measures, damit das Textfeld beim ersten Durchlauf schon bereit ist
[MeasureForm]
Measure=Script
ScriptFile=#@#form.lua

[MeterBg]
Meter=Shape
Shape=Rectangle 0,0,$fw,200,12 | Fill Color #ColorBg# | StrokeWidth 0

[MeterShapes]
Meter=Shape
Shape=Rectangle 0,0,0,0 | StrokeWidth 0

[MeterHead]
Meter=String
X=22
Y=16
FontFace=#FontFace#
FontSize=17
FontWeight=700
FontColor=#ColorText#
AntiAlias=1
Text=Neuer Eintrag

[MeterClose]
Meter=String
X=($fw-50)
Y=12
W=40
H=40
Padding=13,12,0,0
FontFace=#IconFace#
FontSize=11
FontColor=#ColorDone#
SolidColor=0,0,0,1
AntiAlias=1
Text=$close
ToolTipText=Abbrechen
LeftMouseUpAction=$(Act "Click('cancel')")


"@
$form += Label 'LblTitle' 'To-do'
$form += @"
[FieldTitle]
Meter=String
X=20
Y=0
W=($fw-40-28)
Padding=16,6,12,7
ClipString=2
FontFace=#FontFace#
FontSize=13
FontWeight=600
FontColor=#ColorText#
SolidColor=0,0,0,1
AntiAlias=1
Text=
LeftMouseUpAction=$(Act "Click('title')")


"@
$form += Label 'LblDate' 'Fällig am'
$form += Chip 'DateNone' 20 0 'Kein Datum' "Click('nodate')"
$form += Chip 'DateToday' '6R' 'r' 'Heute' "Click('date', 0)"
$form += Chip 'DateTomorrow' '6R' 'r' 'Morgen' "Click('date', 1)"
$form += Chip 'DateWeek' '6R' 'r' 'In 1 Woche' "Click('date', 7)"
$form += Chip 'DateCal' '6R' 'r' 'Datum wählen' "Click('cal')"
# Kalender: Jahr (« ») und Monat (‹ ›) mit Pfeilen, Klick auf den Monat -> Monatsauswahl,
# Wochentage, 6 x 7 Tage (Spaltenbreite 74)
$form += @"
[CalPrevY]
Meter=String
X=20
Y=0
Hidden=1
Padding=12,4,12,6
FontFace=#FontFace#
FontSize=14
FontWeight=600
FontColor=#ColorNote#
SolidColor=0,0,0,1
AntiAlias=1
Text=«
ToolTipText=Jahr zurück
LeftMouseUpAction=$(Act "Click('year', -1)")

[CalNextY]
Meter=String
X=($fw-62)
Y=0
Hidden=1
Padding=12,4,12,6
FontFace=#FontFace#
FontSize=14
FontWeight=600
FontColor=#ColorNote#
SolidColor=0,0,0,1
AntiAlias=1
Text=»
ToolTipText=Jahr vor
LeftMouseUpAction=$(Act "Click('year', 1)")

[CalPrev]
Meter=String
X=70
Y=0
Hidden=1
Padding=12,8,12,8
FontFace=#IconFace#
FontSize=10
FontColor=#ColorNote#
SolidColor=0,0,0,1
AntiAlias=1
Text=$chevL
LeftMouseUpAction=$(Act "Click('month', -1)")

[CalMonth]
Meter=String
X=($fw/2)
Y=0
Hidden=1
StringAlign=Center
FontFace=#FontFace#
FontSize=12
FontWeight=700
FontColor=#ColorText#
SolidColor=0,0,0,1
AntiAlias=1
Text=
ToolTipText=Monat oder Jahr auswählen
LeftMouseUpAction=$(Act "Click('monthview')")

[CalNext]
Meter=String
X=($fw-110)
Y=0
Hidden=1
Padding=12,8,12,8
FontFace=#IconFace#
FontSize=10
FontColor=#ColorNote#
SolidColor=0,0,0,1
AntiAlias=1
Text=$chevR
LeftMouseUpAction=$(Act "Click('month', 1)")


"@
$wd = 'Mo','Di','Mi','Do','Fr','Sa','So'
for ($k = 0; $k -lt 7; $k++) {
    $form += @"
[Wd$($k+1)]
Meter=String
X=$(20 + $k*74 + 37)
Y=0
Hidden=1
StringAlign=Center
FontFace=#FontFace#
FontSize=10
FontWeight=600
FontColor=#ColorDone#
AntiAlias=1
Text=$($wd[$k])


"@
}
for ($k = 1; $k -le 42; $k++) {
    $col = ($k - 1) % 7
    $form += @"
[Day$k]
Meter=String
X=$(20 + $col*74 + 37)
Y=0
W=40
H=26
Hidden=1
Padding=0,6,0,0
StringAlign=Center
FontFace=#FontFace#
FontSize=11
FontWeight=600
FontColor=#ColorNote#
SolidColor=0,0,0,1
AntiAlias=1
Text=
LeftMouseUpAction=$(Act "Click('day', $k)")


"@
}
# Monatsauswahl (X setzt form.lua)
$months3 = 'Jan','Feb','Mär','Apr','Mai','Jun','Jul','Aug','Sep','Okt','Nov','Dez'
for ($k = 1; $k -le 12; $k++) {
    $form += @"
[Mon$k]
Meter=String
X=0
Y=0
W=80
H=26
Hidden=1
Padding=0,6,0,0
StringAlign=Center
FontFace=#FontFace#
FontSize=11
FontWeight=600
FontColor=#ColorNote#
SolidColor=0,0,0,1
AntiAlias=1
Text=$($months3[$k-1])
LeftMouseUpAction=$(Act "Click('pickmonth', $k)")


"@
}
$form += Label 'LblTime' 'Uhrzeit (mit Windows-Erinnerung)'
$form += Chip 'TimeNone' 20 0 'Keine' "Click('notime')"
$times = '09:00','12:00','15:00','18:00','21:00'
for ($k = 1; $k -le 5; $k++) { $form += Chip "Time$k" '6R' 'r' $times[$k-1] "Click('time', $k)" }
$form += Chip 'TimeOther' '6R' 'r' 'Andere' "Click('timeother')"
# Uhr: grosse Anzeige HH:MM (Stunde/Minute anklickbar) und 24 Zahlen auf dem Zifferblatt (Position setzt form.lua)
$form += @"
[ClockH]
Meter=String
X=($fw/2-8)
Y=0
Hidden=1
StringAlign=Right
Padding=8,0,4,0
FontFace=#FontFace#
FontSize=26
FontWeight=700
FontColor=#ColorText#
SolidColor=0,0,0,1
AntiAlias=1
Text=12
ToolTipText=Stunde wählen
LeftMouseUpAction=$(Act "Click('clockmode', 'h')")

[ClockColon]
Meter=String
X=($fw/2)
Y=0
Hidden=1
StringAlign=Center
FontFace=#FontFace#
FontSize=26
FontWeight=700
FontColor=#ColorDone#
AntiAlias=1
Text=:

[ClockM]
Meter=String
X=($fw/2+8)
Y=0
Hidden=1
Padding=4,0,8,0
FontFace=#FontFace#
FontSize=26
FontWeight=700
FontColor=#ColorDone#
SolidColor=0,0,0,1
AntiAlias=1
Text=00
ToolTipText=Minute wählen
LeftMouseUpAction=$(Act "Click('clockmode', 'm')")


"@
for ($k = 1; $k -le 24; $k++) {
    $form += @"
[Clock$k]
Meter=String
X=0
Y=0
W=34
H=34
Hidden=1
StringAlign=CenterCenter
FontFace=#FontFace#
FontSize=11
FontWeight=600
FontColor=#ColorNote#
SolidColor=0,0,0,1
AntiAlias=1
Text=
LeftMouseUpAction=$(Act "Click('clock', $k)")


"@
}
$form += Chip 'ClockCancel' 20 0 'Abbrechen' "Click('clockcancel')"
$form += Chip 'ClockOk' '6R' 'r' 'Übernehmen' "Click('clockok')"
$form += Label 'LblRule' 'Wiederholen'
# Jaehrlich hat keinen eigenen Knopf mehr (passt sonst nicht in eine Zeile) -> Individuell, "Alle 1 Jahre"
$rules = 'Nie','Täglich','Werktags','Wöchentlich','Monatlich'
for ($k = 1; $k -le 5; $k++) { $form += Chip "Rule$k" $(if ($k -eq 1) { 20 } else { '6R' }) $(if ($k -eq 1) { 0 } else { 'r' }) $rules[$k-1] "Click('rule', $k)" }
$form += Chip 'Rule7' '6R' 'r' 'Individuell' "Click('custom')"
# eigene Wiederholung: "Alle [-] N [+] Tage|Wochen|Monate|Jahre" oder Wochentage
$form += @"
[CustAlle]
Meter=String
X=22
Y=0
Hidden=1
Padding=0,6,0,6
FontFace=#FontFace#
FontSize=11
FontWeight=600
FontColor=#ColorNote#
AntiAlias=1
Text=Alle


"@
$form += Chip 'CustMinus' '10R' 'r' '–' "Click('custn', -1)"
$form += @"
[CustN]
Meter=String
X=4R
Y=r
W=30
Hidden=1
Padding=0,6,0,6
StringAlign=Left
FontFace=#FontFace#
FontSize=12
FontWeight=700
FontColor=#ColorText#
AntiAlias=1
Text=1
InlinePattern=.*
InlineSetting=Face | #FontFace#


"@
$form += Chip 'CustPlus' '4R' 'r' '+' "Click('custn', 1)"
$units = 'Tage','Wochen','Monate','Jahre'
for ($k = 1; $k -le 4; $k++) { $form += Chip "CustU$k" $(if ($k -eq 1) { '6R' } else { '6R' }) 'r' $units[$k-1] "Click('custu', $k)" }
$form += @"
[CustOder]
Meter=String
X=22
Y=0
Hidden=1
FontFace=#FontFace#
FontSize=10
FontWeight=600
FontColor=#ColorDone#
AntiAlias=1
Text=oder an bestimmten Wochentagen:


"@
for ($k = 1; $k -le 7; $k++) { $form += Chip "CustWd$k" $(if ($k -eq 1) { 20 } else { '6R' }) $(if ($k -eq 1) { 0 } else { 'r' }) $wd[$k-1] "Click('custwd', $k)" }
# Tags: ein Knopf pro Tag aus den Einstellungen (X/Y, Text und Farbe setzt form.lua), an/aus per Klick
$form += Label 'LblTags' 'Tags'
for ($k = 1; $k -le 8; $k++) { $form += Chip "TagChip$k" 20 0 '' "Click('tag', $k)" 'Hidden=1' }
$form += @"
[TagHint]
Meter=String
X=22
Y=0
Hidden=1
FontFace=#FontFace#
FontSize=10
FontColor=#ColorDone#
AntiAlias=1
Text=Noch keine Tags – anlegen in den Einstellungen (Zahnrad).


"@
$form += @"
[Summary]
Meter=String
X=20
Y=0
W=($fw-40-24)
Padding=12,8,12,8
ClipString=2
FontFace=#FontFace#
FontSize=11
FontWeight=600
FontColor=#ColorAccent#
AntiAlias=1
Text=


"@
$form += Label 'LblNotes' 'Notizen, Links, Dateien'
for ($k = 1; $k -le 8; $k++) {
    $form += @"
[Note$k]
Meter=String
X=20
Y=0
W=($fw-40-24-40)
Hidden=1
Padding=12,7,12,7
ClipString=2
FontFace=#FontFace#
FontSize=11
FontColor=#ColorNote#
SolidColor=0,0,0,1
AntiAlias=1
Text=
ToolTipText=Klicken zum Bearbeiten
LeftMouseUpAction=$(Act "Click('note', $k)")

[NoteDel$k]
Meter=String
X=($fw-58)
Y=0
Hidden=1
Padding=12,9,12,7
FontFace=#IconFace#
FontSize=9
FontColor=#ColorDone#
SolidColor=0,0,0,1
AntiAlias=1
Text=$close
ToolTipText=Notiz entfernen
LeftMouseUpAction=$(Act "Click('notedel', $k)")


"@
}
$form += Chip 'NoteAdd' 20 0 '+ Notiz / Link' "Click('noteadd')"
$form += Chip 'FileAdd' '6R' 'r' '+ Datei' "Click('file')"
$form += Chip 'BtnDelete' 20 0 'Löschen' "Click('delete')"
$form += Chip 'BtnCancel' 0 0 'Abbrechen' "Click('cancel')"
$form += Chip 'BtnSave' 0 0 'Speichern' "Click('save')"
$form = $form.Replace("[BtnSave]`nMeter=String", "[BtnSave]`nMeter=String`nFontWeight=700").Replace("[BtnSave]`r`nMeter=String", "[BtnSave]`r`nMeter=String`r`nFontWeight=700")
New-Item -ItemType Directory -Force "$skin\Formular" | Out-Null
[IO.File]::WriteAllText("$skin\Formular\Formular.ini", $form, [Text.Encoding]::Unicode)

# ---------- Einstellungen-Fenster: Config TaskBoard\Einstellungen, geoeffnet ueber das Zahnrad ----------
# Anzeige (Seitenleiste/Desktop/beides) und Breite schreiben in prefs.inc (bleibt bei Updates erhalten).
# Darunter die Kurzhilfe: "#..." = Ueberschrift, sonst "Stichwort: Erklaerung" (Stichwort fett)
$helpLines = @(
    '#So funktioniert''s'
    'Klick: Eintrag abhaken (nochmal klicken = rückgängig)'
    'Rechtsklick: Eintrag bearbeiten oder löschen'
    'Ziehen: Eintrag mit der Maus an eine andere Stelle schieben (neue Einträge mit Datum kommen von selbst nach oben)'
    '+ Neuer Eintrag: neuen Eintrag anlegen, überall auch mit dem Tastenkürzel (siehe oben)'
    'Enter: speichert den Eintrag sofort (Datum vorher wählen oder später ergänzen)'
    'Titel „Todo“: Liste in Obsidian öffnen'
    'Seitenleiste: Maus an den Bildschirmrand – die Liste fährt herein'
    'Anmelden, Aufwachen, Entsperren: die Liste kommt kurz von selbst'
    'Farben: orange = heute fällig, rot = überfällig'
    'Erledigte archivieren: abgehakte Einträge wandern ins Archiv'
)
# ---------- Einstellungen-Fenster: Config TaskBoard\Einstellungen, zwei Spalten ----------
$hw = 960                       # Fensterbreite
$colL = 22; $colR = 500; $colW = 438
$archive = '["obsidian://open?path=#ArchiveUrl#"]'
# ----- Knoepfe: abgerundete Flaeche mit Rand (Shape) + Beschriftung darueber -----
# Breite aus der Textbreite (Segoe UI Semibold), damit die Knoepfe ohne Laufzeit-Rechnerei fest liegen.
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
$btnFont = New-Object Drawing.Font('Segoe UI Semibold', 11, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Point)
function BtnWidth($text) { [Math]::Max(44, [Windows.Forms.TextRenderer]::MeasureText($text, $btnFont).Width + 22) }
$btnH = 34
$script:btnVars = ''
# $x: absolute X; $y: Y der Flaeche ('10R' unter der Ueberschrift, 'r' = gleiche Zeile wie der vorige Knopf)
# Zustaende ueber Variablen: B_ Flaeche, S_ Rand, T_ Schrift, O_ Hover-/Klick-Aufhellung
function SetChip($name, $x, $y, $text, $action, $color = '#ColorNote#', $size = 11, $w = 0) {
    if (-not $w) { $w = BtnWidth $text }
    $script:btnVars += "B_$name=255,255,255,14`r`nS_$name=255,255,255,38`r`nT_$name=$color`r`nO_$name=0`r`n"
    $ty = [int](($btnH - 19) / 2) - 1
    if ($size -gt 12) { $ty = 2 }
    # 'r' bezieht sich auf die Beschriftung des vorigen Knopfs (liegt $ty tiefer als dessen Flaeche)
    $sy = if ($y -eq 'r') { "-$($script:lastTy)r" } else { $y }
    $script:lastTy = $ty
    $hover = "[!SetVariable O_$name 26][!UpdateMeter $name][!Redraw]"
    $leave = "[!SetVariable O_$name 0][!UpdateMeter $name][!Redraw]"
    $down = "[!SetVariable O_$name 60][!UpdateMeter $name][!Redraw]"
@"
[$name]
Meter=Shape
X=$x
Y=$sy
DynamicVariables=1
Shape=Rectangle 0.5,0.5,$($w - 1),$($btnH - 1),8 | Fill Color #B_$name# | StrokeWidth 1 | Stroke Color #S_$name#
Shape2=Rectangle 0.5,0.5,$($w - 1),$($btnH - 1),8 | Fill Color 255,255,255,#O_$name# | StrokeWidth 0
MouseOverAction=$hover
MouseLeaveAction=$leave
LeftMouseDownAction=$down
LeftMouseUpAction=$hover$action

[${name}Text]
Meter=String
X=$([int]($w / 2))r
Y=${ty}r
StringAlign=Center
DynamicVariables=1
FontFace=#FontFace#
FontSize=$size
FontWeight=600
FontColor=#T_$name#
AntiAlias=1
Text=$text


"@
}
# unsichtbare Linie an der Unterkante der letzten Knopfreihe, damit 'R' darunter richtig Abstand haelt
function Spacer($name, $x) {
    "[$name]`r`nMeter=Image`r`nX=$x`r`nY=$($btnH - $script:lastTy)r`r`nW=1`r`nH=1`r`n`r`n"
}
function Caption($name, $text, $x = 22, $y = '22R') {
@"
[$name]
Meter=String
X=$x
Y=$y
FontFace=#FontFace#
FontSize=13
FontWeight=700
FontColor=#ColorAccent#
AntiAlias=1
Text=$text


"@
}
# kleine Gruppen-Ueberschrift (AUSSEHEN / VERHALTEN) ueber einer Spalte
function GroupHead($name, $text, $x) {
"[$name]
Meter=String
X=$x
Y=60
FontFace=#FontFace#
FontSize=9
FontWeight=600
FontColor=#ColorDone#
AntiAlias=1
Text=$text

"
}
function Small($name, $text, $x, $y = '8R') {
@"
[$name]
Meter=String
X=$x
Y=$y
W=$colW
ClipString=2
FontFace=#FontFace#
FontSize=10
FontColor=#ColorDone#
AntiAlias=1
Text=$text


"@
}
# ausgewaehlter Knopf in der Akzentfarbe
$sel = '[!SetVariable B_{0} "#ColorCheck#"][!SetVariable S_{0} "#ColorCheck#"][!SetVariable T_{0} "#ColorText#"][!UpdateMeter *][!Redraw]'
# Farbpunkte: ausgewaehlter bekommt einen hellen Ring
$selRing = '[!SetVariable S_{0} "255,255,255,230"][!SetVariable B_{0} "255,255,255,40"][!UpdateMeter *][!Redraw]'
# Wert in prefs.inc / colors.inc schreiben
function P($k, $v) { "[!WriteKeyValue Variables $k `"$v`" `"#@#prefs.inc`"]" }
function C($k, $v) { "[!WriteKeyValue Variables $k `"$v`" `"#@#colors.inc`"]" }
$refAll = '[!Refresh TaskBoard][!Refresh TaskBoard\Rand][!Refresh TaskBoard\Formular][!Refresh]'
# Eine Einstellung: Ueberschrift + Knoepfe in einer Reihe. Ein String-Measure vergleicht den aktuellen Wert
# ($current) mit dem Muster jedes Knopfs und hebt den passenden hervor.
# $opts: @( @(Beschriftung, Muster, Bangs [, Schriftfarbe, Schriftgroesse]), ... )
function Row($key, $caption, $x, $y, $current, $opts) {
    $s = Caption "Cap$key" $caption $x $y
    $m = "[Sel$key]`r`nMeasure=String`r`nString=$current`r`n"
    $cx = $x; $cy = '10R'; $i = 0
    foreach ($o in $opts) {
        $i++
        $color = if ($o.Count -gt 3) { $o[3] } else { '#ColorNote#' }
        $size = if ($o.Count -gt 4) { $o[4] } else { 11 }
        $w = if ($size -gt 12) { 44 } else { BtnWidth $o[0] }
        $s += SetChip "$key$i" $cx $cy $o[0] $o[2] $color $size $w
        $n = if ($i -eq 1) { '' } else { "$i" }
        $how = if ($size -gt 12) { $selRing } else { $sel }
        $m += "IfMatch$n=$($o[1])`r`nIfMatchAction$n=$($how -f "$key$i")`r`n"
        $cx = $cx + $w + 8; $cy = 'r'
    }
    $s += Spacer "End$key" $x
    $s + $m + "`r`n"
}

$hini = @"
; Einstellungen der Obsidian-Todo-Liste. Erzeugt von build-skin.ps1 - Aenderungen dort machen.
[Rainmeter]
Update=1000
AccurateText=1
DynamicWindowSize=1
; immer im Vordergrund und mittig auf dem Hauptbildschirm (auch wenn die Liste in der Seitenleiste steckt)
OnRefreshAction=[!ZPos 2][!SetWindowPosition "50%" "50%" "50%" "50%"]

[Variables]
ArchiveUrl=
TodoFile=
@IncludeSettings=#@#settings.inc
Width=460
Mode=sidebar
Side=right
Speed=normal
FontSize=13
Opacity=170
RevealPerItem=10
RemindOn=1
RemindLead=0
AutoUpdate=1
HotkeyNow=
Accent=lila
Tags=
NewTag=
TagInX=0
TagInY=0
TagInW=150
@IncludePrefs=#@#prefs.inc
@IncludeHotkey=#@#hotkey.inc
FontFace=Segoe UI
IconFace=Segoe Fluent Icons
ColorBg=12,12,18,235
ColorText=255,255,255,255
ColorNote=200,200,212,255
ColorDone=175,175,188,240
ColorAccent=165,185,255,255
ColorCheck=138,108,245,255
ColorHover=255,255,255,22
@IncludeColors=#@#colors.inc

; Tastenkuerzel neu setzen: TaskBoardHotkey.exe beenden, die Liste startet es beim Auffrischen neu
[MeasureKillHotkey]
Measure=Plugin
Plugin=RunCommand
Program=taskkill.exe
Parameter=/f /im TaskBoardHotkey.exe
State=Hide
FinishAction=[!Refresh TaskBoard][!Delay 1500][!Refresh]

; neues Tastenkuerzel aufnehmen (kleines Fenster), danach TaskBoardHotkey neu starten
[MeasureRecord]
Measure=Plugin
Plugin=RunCommand
Program="#@#TaskBoardHotkey.exe"
Parameter=--record
State=Hide
Timeout=-1
FinishAction=[!CommandMeasure MeasureKillHotkey "Run"]

; Tags verwalten und Updates von Hand (settings.lua)
[MeasureSettings]
Measure=Script
ScriptFile=#@#settings.lua

; Name fuer einen neuen Tag (Feld erscheint ueber "+ Neuer Tag")
[MeasureTagInput]
Measure=Plugin
Plugin=InputText
DynamicVariables=1
X=#TagInX#
Y=#TagInY#
W=#TagInW#
H=22
SolidColor=30,32,39,255
FontColor=#ColorText#
FontFace=#FontFace#
FontSize=11
OnDismissAction=[!CommandMeasure MeasureSettings "AddCancel()"]
; bleibt offen, bis Enter (speichern) oder Esc (abbrechen) - sonst schliesst es sich, sobald es kurz den Fokus verliert
FocusDismiss=0
DefaultValue=
Command1=[!SetVariable NewTag """`$UserInput`$"""][!CommandMeasure MeasureSettings "AddDone()"]

; "Nach Updates suchen": update.ps1 -Check gibt "neu 1.3.1" / "aktuell 1.3.0" / "fehler" aus
[MeasureUpdCheck]
Measure=Plugin
Plugin=RunCommand
Program=powershell.exe
Parameter=-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "#@#update.ps1" -Check
State=Hide
OutputType=UTF8
Timeout=60000
FinishAction=[!CommandMeasure MeasureSettings "UpdChecked()"]

; "Jetzt aktualisieren": laedt das Setup und installiert sofort (Rainmeter laedt die Liste danach neu)
[MeasureUpdNow]
Measure=Plugin
Plugin=RunCommand
Program=powershell.exe
Parameter=-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "#@#update.ps1" -Now
State=Hide
Timeout=-1

; Todo-Datei waehlen (Dateidialog, schreibt settings.inc)
[MeasureChoose]
Measure=Plugin
Plugin=RunCommand
Program=powershell.exe
Parameter=-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "#@#choose-todo.ps1"
State=Hide
OutputType=UTF8
Timeout=-1
FinishAction=[!Refresh TaskBoard][!Refresh TaskBoard\Formular][!Refresh]

[MeterBg]
Meter=Shape
DynamicVariables=1
Shape=Rectangle 0,0,$hw,([MeterEnd:Y]+[MeterEnd:H]+18),12 | Fill Color #ColorBg# | StrokeWidth 0

[MeterTitle]
Meter=String
X=22
Y=16
FontFace=#FontFace#
FontSize=17
FontWeight=700
FontColor=#ColorText#
AntiAlias=1
Text=Einstellungen

[MeterClose]
Meter=String
X=($hw-50)
Y=12
W=40
H=40
Padding=13,12,0,0
FontFace=#IconFace#
FontSize=11
FontColor=#ColorDone#
SolidColor=0,0,0,1
AntiAlias=1
Text=$close
LeftMouseUpAction=[!DeactivateConfig]
MouseOverAction=[!SetOption MeterClose SolidColor "#ColorHover#"][!UpdateMeter MeterClose][!Redraw]
MouseLeaveAction=[!SetOption MeterClose SolidColor "0,0,0,1"][!UpdateMeter MeterClose][!Redraw]


"@

# ----- linke Spalte: Aussehen -----
$hini += GroupHead 'GrpLook' 'AUSSEHEN' $colL
$hini += Row 'Mode' 'Anzeige' $colL '12R' '#Mode#' @(
    @('Seitenleiste', '^sidebar$', "$(P Mode sidebar)$refAll"),
    @('Desktop', '^desktop$', "$(P Mode desktop)$refAll"),
    @('Beides', '^both$', "$(P Mode both)$refAll"))
$hini += Small 'ModeInfo' 'Seitenleiste: fährt am Bildschirmrand herein. Desktop: liegt auf dem Hintergrund. Beides: liegt auf dem Desktop und fährt am Rand als Seitenleiste herein.' $colL
$hini += Row 'Side' 'Seite' $colL '22R' '#Side#' @(
    @('Links', '^left$', "$(P Side left)$refAll"),
    @('Rechts', '^right$', "$(P Side right)$refAll"))
$hini += Row 'Width' 'Breite' $colL '22R' '#Width#' @(
    @('Breit', '^560$', "$(P Width 560)$refAll"),
    @('Normal', '^460$', "$(P Width 460)$refAll"),
    @('Schmal', '^380$', "$(P Width 380)$refAll"))
$hini += Row 'Font' 'Schriftgröße' $colL '22R' '#FontSize#' @(
    @('Groß', '^15$', "$(P FontSize 15)$(P RowH 40)$(P NoteH 34)$refAll"),
    @('Normal', '^13$', "$(P FontSize 13)$(P RowH 36)$(P NoteH 30)$refAll"),
    @('Klein', '^12$', "$(P FontSize 12)$(P RowH 32)$(P NoteH 28)$refAll"))
$hini += Row 'Opacity' 'Hintergrund' $colL '22R' '#Opacity#' @(
    @('Deckend', '^250$', "$(P Opacity 250)$refAll"),
    @('Normal', '^170$', "$(P Opacity 170)$refAll"),
    @('Leicht', '^100$', "$(P Opacity 100)$refAll"),
    @('Durchsichtig', '^1$', "$(P Opacity 1)$refAll"))
# Akzentfarbe: Kaestchen, Knoepfe (ColorCheck) und Links/Ueberschriften (ColorAccent)
$accents = @(
    @('lila', '138,108,245,255', '165,185,255,255'),
    @('blau', '60,130,240,255', '140,190,255,255'),
    @('gruen', '50,170,100,255', '140,220,170,255'),
    @('orange', '235,135,40,255', '255,195,130,255'),
    @('rot', '220,70,70,255', '255,160,160,255'),
    @('pink', '220,80,165,255', '255,165,215,255'))
$opts = @()
foreach ($a in $accents) {
    $opts += , @([string][char]0x25CF, "^$($a[0])$", "$(C Accent $a[0])$(C ColorCheck $a[1])$(C ColorAccent $a[2])$refAll", $a[1], 17)
}
$hini += Row 'Accent' 'Akzentfarbe' $colL '22R' '#Accent#' $opts
# Tags: Liste aus prefs.inc (Tags=name:farbe,...), angeordnet von settings.lua. Klick = Farbe wechseln, × = entfernen
$hini += Caption 'CapTags' 'Tags' $colL
$hini += "[TagShapes]`r`nMeter=Shape`r`nShape=Rectangle 0,0,0,0 | StrokeWidth 0`r`n`r`n"
for ($k = 1; $k -le 8; $k++) {
    $hini += "[TagS$k]`r`nMeter=String`r`nHidden=1`r`nX=$colL`r`nY=0`r`nPadding=12,7,12,7`r`nFontFace=#FontFace#`r`nFontSize=11`r`nFontWeight=600`r`nFontColor=#ColorNote#`r`nSolidColor=0,0,0,1`r`nAntiAlias=1`r`nText=`r`nLeftMouseUpAction=[!CommandMeasure MeasureSettings `"Cycle($k)`"]`r`n`r`n"
    $hini += "[TagX$k]`r`nMeter=String`r`nHidden=1`r`nX=$colL`r`nY=0`r`nPadding=11,10,11,9`r`nFontFace=#IconFace#`r`nFontSize=8`r`nFontColor=#ColorDone#`r`nSolidColor=0,0,0,1`r`nAntiAlias=1`r`nText=$close`r`nLeftMouseUpAction=[!CommandMeasure MeasureSettings `"Remove($k)`"]`r`n`r`n"
}
$hini += "[TagAdd]`r`nMeter=String`r`nX=$colL`r`nY=0`r`nW=150`r`nPadding=12,7,12,7`r`nFontFace=#FontFace#`r`nFontSize=11`r`nFontWeight=600`r`nFontColor=#ColorAccent#`r`nSolidColor=0,0,0,1`r`nAntiAlias=1`r`nText=+ Neuer Tag`r`nLeftMouseUpAction=[!CommandMeasure MeasureSettings `"AddStart()`"]`r`n`r`n"
$hini += Small 'TagInfo' 'Klick auf einen Tag wechselt seine Farbe. Zuweisen im Formular (neuer Eintrag / Rechtsklick). In der Datei steht er als #tag.' $colL '0'
$hini += "[LeftEnd]`r`nMeter=Image`r`nX=$colL`r`nY=0R`r`nW=1`r`nH=1`r`n`r`n"

# ----- rechte Spalte: Verhalten -----
$hini += GroupHead 'GrpBehave' 'VERHALTEN' $colR
$hini += Row 'Speed' 'Tempo der Seitenleiste' $colR '12R' '#Speed#' @(
    @('Schnell', '^fast$', "$(P Speed fast)$refAll"),
    @('Normal', '^normal$', "$(P Speed normal)$refAll"),
    @('Gemütlich', '^slow$', "$(P Speed slow)$refAll"))
$hini += Row 'Reveal' 'Beim Anmelden/Aufwachen einblenden' $colR '22R' '#RevealPerItem#' @(
    @('20 s', '^20$', "$(P RevealPerItem 20)$refAll"),
    @('10 s', '^10$', "$(P RevealPerItem 10)$refAll"),
    @('5 s', '^5$', "$(P RevealPerItem 5)$refAll"),
    @('Aus', '^0$', "$(P RevealPerItem 0)$refAll"))
$hini += Small 'RevealInfo' 'Sekunden pro offenem Eintrag (höchstens 2 Minuten).' $colR
$hini += Row 'Remind' 'Erinnerungen' $colR '22R' '#RemindOn#-#RemindLead#' @(
    @('15 Min vorher', '^1-15$', "$(P RemindOn 1)$(P RemindLead 15)$refAll"),
    @('5 Min vorher', '^1-5$', "$(P RemindOn 1)$(P RemindLead 5)$refAll"),
    @('Pünktlich', '^1-0$', "$(P RemindOn 1)$(P RemindLead 0)$refAll"),
    @('Aus', '^0-', "$(P RemindOn 0)$refAll"))
$kill = '[!CommandMeasure MeasureKillHotkey "Run"]'
# Tastenkuerzel: aktuelles anzeigen, Klick darauf nimmt ein neues auf (TaskBoardHotkey.exe --record), "Zuruecksetzen" = Standard
$hini += Caption 'CapHotkey' 'Tastenkürzel für neuen Eintrag' $colR
$hini += SetChip 'HotkeyNow1' $colR '10R' '#HotkeyNow#' '[!CommandMeasure MeasureRecord "Run"]' '#ColorText#' 11 190
$hini += SetChip 'HotkeyReset' ($colR + 198) 'r' 'Zurücksetzen' "$(P Hotkey '')$kill"
$hini += "[SelHotkeyNow]`r`nMeasure=String`r`nString=x`r`nIfMatch=x`r`nIfMatchAction=$($sel -f 'HotkeyNow1')`r`n`r`n"
$hini += Spacer 'EndHotkey' $colR
$hini += Small 'HotkeyInfo' 'Zum Ändern auf das Kürzel klicken und die neue Kombination drücken (Esc = abbrechen).' $colR
$hini += Caption 'CapFile' 'Todo-Datei' $colR
$hini += Small 'FileNow' '#TodoFile#' $colR
$hini += SetChip 'File1' $colR '10R' 'Andere Datei wählen …' '[!CommandMeasure MeasureChoose "Run"]'
$hini += Spacer 'EndFile' $colR
$hini += Row 'Update' 'Automatische Updates' $colR '22R' '#AutoUpdate#' @(
    @('An', '^1$', "$(P AutoUpdate 1)[!Refresh]"),
    @('Aus', '^0$', "$(P AutoUpdate 0)[!Refresh]"))
# von Hand nach Updates suchen; gibt es eins, erscheint "Jetzt aktualisieren" (settings.lua)
$hini += SetChip 'UpdCheck' $colR '12R' 'Nach Updates suchen' '[!CommandMeasure MeasureSettings "CheckUpdates()"]'
$updNow = SetChip 'UpdNow' ($colR + (BtnWidth 'Nach Updates suchen') + 8) 'r' 'Jetzt aktualisieren' '[!CommandMeasure MeasureSettings "InstallNow()"]'
$hini += $updNow.Replace("[UpdNow]`r`nMeter=Shape", "[UpdNow]`r`nMeter=Shape`r`nHidden=1").Replace("[UpdNowText]`r`nMeter=String", "[UpdNowText]`r`nMeter=String`r`nHidden=1").Replace("[UpdNow]`nMeter=Shape", "[UpdNow]`nMeter=Shape`nHidden=1").Replace("[UpdNowText]`nMeter=String", "[UpdNowText]`nMeter=String`nHidden=1")
$hini += "[SelUpdNow]`r`nMeasure=String`r`nString=x`r`nIfMatch=x`r`nIfMatchAction=$($sel -f 'UpdNow')`r`n`r`n"
$hini += Spacer 'EndUpd' $colR
$hini += Small 'UpdInfo' ' ' $colR
$hini += "[RightEnd]`r`nMeter=Image`r`nX=$colR`r`nY=0R`r`nW=1`r`nH=1`r`n`r`n"

# ----- unten ueber die ganze Breite: Kurzhilfe, Archiv, Version -----
$n = 0
foreach ($l in $helpLines) {
    $n++
    if ($l.StartsWith('#')) {
        # unter der laengeren Spalte beginnen
        $hini += (Caption "Line$n" $l.Substring(1) 22 '(max([LeftEnd:Y],[RightEnd:Y])+30)').Replace("Text=", "DynamicVariables=1`r`nText=")
        continue
    }
    $hini += @"
[Line$n]
Meter=String
X=22
Y=4R
W=($hw-44)
ClipString=2
FontFace=#FontFace#
FontSize=11
FontColor=#ColorNote#
AntiAlias=1
InlinePattern=^([^:]+:)
InlineSetting=Weight | 700
InlinePattern2=^([^:]+:)
InlineSetting2=Color | #ColorText#
Text=$l


"@
}
$hini += @"
[MeterArchive]
Meter=String
X=22
Y=18R
FontFace=#FontFace#
FontSize=11
FontWeight=600
FontColor=#ColorAccent#
SolidColor=0,0,0,1
AntiAlias=1
Text=Archiv öffnen ↗
LeftMouseUpAction=$archive

[MeterEnd]
Meter=String
X=($hw-22)
Y=r
StringAlign=Right
FontFace=#FontFace#
FontSize=10
FontColor=#ColorDone#
AntiAlias=1
Text=Task Board $Version
"@
# Zeilenenden vereinheitlichen (die Ersetzungen hier erwarten CRLF, egal wie diese Datei gespeichert ist)
$hini = $hini -replace "(?<!`r)`n", "`r`n"
$script:btnVars = $script:btnVars -replace "(?<!`r)`n", "`r`n"
# Startwerte der Knopf-Variablen in [Variables] (vor colors.inc)
$hini = $hini.Replace("ColorHover=255,255,255,22`r`n@IncludeColors", "ColorHover=255,255,255,22`r`n" + $script:btnVars.Replace('#ColorNote#', '200,200,212,255') + "@IncludeColors")
New-Item -ItemType Directory -Force "$skin\Einstellungen" | Out-Null
[IO.File]::WriteAllText("$skin\Einstellungen\Einstellungen.ini", $hini, [Text.Encoding]::Unicode)

# ---------- Rand-Streifen fuer die Seitenleiste: Config TaskBoard\Rand (Logik in sidebar.lua) ----------
$rand = @"
; Unsichtbarer Streifen am rechten Bildschirmrand: Maus dagegen -> Liste faehrt herein. Erzeugt von build-skin.ps1.
[Rainmeter]
; schnelle Aktualisierung nur fuer die Animation; ohne Animation tut sidebar.lua nichts
Update=16
AccurateText=1
OnRefreshAction=[!ZPos 2][!Draggable 0][!KeepOnScreen 0][!ClickThrough 0][!SnapEdges 0]

[Variables]
Width=460
Mode=sidebar
@IncludePrefs=#@#prefs.inc

[MeasureSide]
Measure=Script
ScriptFile=#@#sidebar.lua

; 1 Pixel breit; Deckkraft 1 von 255 reicht, damit Rainmeter die Maus bemerkt
[MeterEdge]
Meter=Image
W=1
H=1080
SolidColor=0,0,0,1
MouseOverAction=[!CommandMeasure MeasureSide "EdgeHit()"]
MouseLeaveAction=[!CommandMeasure MeasureSide "EdgeLeave()"]
"@
New-Item -ItemType Directory -Force "$skin\Rand" | Out-Null
[IO.File]::WriteAllText("$skin\Rand\Rand.ini", $rand, [Text.Encoding]::Unicode)
