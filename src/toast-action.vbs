' Knoepfe in der Todo-Erinnerung: taskboard:done/<id> oder taskboard:snooze/<id>
' (registriert unter HKCU\Software\Classes\taskboard). Gibt die Aktion an todo.lua weiter, ohne Konsolenfenster.
Option Explicit
Dim url, rest, parts, act, id, fso, rm
If WScript.Arguments.Count < 1 Then WScript.Quit
url = WScript.Arguments(0)
rest = Mid(url, InStr(url, ":") + 1)
parts = Split(Replace(rest, "/", " ", 1, -1), " ")
If UBound(parts) < 1 Then WScript.Quit
act = LCase(parts(0))
id = parts(1)
' nur bekannte Aktionen und eine Zahl als Kennung durchlassen
If act <> "done" And act <> "snooze" Then WScript.Quit
If Not IsNumeric(id) Or id = "" Then WScript.Quit
id = CStr(CLng(id))
Set fso = CreateObject("Scripting.FileSystemObject")
' 2. Argument: Pfad zu Rainmeter.exe (traegt der Installer bei der Registrierung ein), sonst portables Layout
rm = ""
If WScript.Arguments.Count > 1 Then rm = WScript.Arguments(1)
If rm = "" Or Not fso.FileExists(rm) Then rm = fso.GetAbsolutePathName(fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "..\..\..\Rainmeter.exe"))
CreateObject("WScript.Shell").Run """" & rm & """ !CommandMeasure MeasureTodo ""ToastAction('" & act & "', " & id & ")"" TaskBoard", 0, False
