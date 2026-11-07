; Installer fuer Task Board (frueher Obsidian Todo) (Inno Setup 7)
; Bauen ueber ..\build.ps1 - der uebergibt AppVersion und baut vorher den Skin nach ..\dist\skin.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName "Task Board"
#define SkinDir "..\dist\skin\ObsidianTodo"

[Setup]
AppId={{16E88833-5A38-4DDC-8401-D15AD3FA1B60}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Task Board
VersionInfoVersion={#AppVersion}
; bestehende Installationen behalten ihren Ordner (Inno nimmt den vorherigen), neue landen unter "Task Board"
DefaultDirName={localappdata}\Programs\Task Board
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=TaskBoard-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#AppName}
CloseApplications=no

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[Messages]
de.WelcomeLabel2=Damit bekommst du eine Todo-Liste auf dem Desktop, die direkt in deinem Obsidian-Vault gespeichert wird.%n%nRainmeter (zeigt die Liste auf dem Desktop an) wird bei Bedarf automatisch mitinstalliert.

[Files]
Source: "helper.ps1"; Flags: dontcopy
Source: "helper.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SkinDir}\*"; DestDir: "{app}\ObsidianTodo"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; altes Hilfe-Fenster (seit 1.2.0: Einstellungen)
Type: filesandordirs; Name: "{app}\ObsidianTodo\Hilfe"
; Startmenue-Eintrag von vor der Umbenennung in Task Board
Type: files; Name: "{userprograms}\Obsidian To-do entfernen.lnk"

[Icons]
Name: "{userprograms}\Task Board entfernen"; Filename: "{uninstallexe}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 31

[UninstallDelete]
; vom Skin zur Laufzeit erzeugte Dateien (settings.inc, hotkey.txt, ...)
Type: filesandordirs; Name: "{app}\ObsidianTodo"

[Code]
const
  RegKey = 'Software\ObsidianTodo';

var
  RainmeterExe, SkinPath, ObsidianExe: String;
  OldTodoDir: String;   { Ordner der Todo.md einer vorhandenen (alten) Obsidian-Todo-Liste }
  VaultList, TodoInList: TStringList;
  PrevVault, PrevTodoDir: String;
  PrereqPage: TWizardPage;
  PrereqLabel: TNewStaticText;
  ObsidianCheck: TNewCheckBox;
  VaultPage: TInputOptionWizardPage;
  KeepPage: TWizardPage;
  KeepLabel: TNewStaticText;
  ChangeCheck: TNewCheckBox;
  NewVaultPage, TodoPage: TInputDirWizardPage;
  LastVaultForTodo: String;
  SilentVault: String;
  DownloadPage: TDownloadWizardPage;

function OnDownloadProgress(const Url, FileName: String; const Progress, ProgressMax: Int64): Boolean;
begin
  Result := True;
end;

function HelperPath: String;
begin
  Result := ExpandConstant('{tmp}\helper.ps1');
end;

{ immer das 64-Bit-PowerShell (das Setup selbst ist 32 Bit; das 32-Bit-PowerShell sieht 64-Bit-Programme nicht richtig) }
function PowerShellExe: String;
begin
  Result := ExpandConstant('{sysnative}\WindowsPowerShell\v1.0\powershell.exe');
  if not FileExists(Result) then Result := 'powershell.exe';
end;

function RunHelper(const Args: String): Boolean;
var
  RC: Integer;
begin
  Result := Exec(PowerShellExe,
    '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + HelperPath + '" ' + Args,
    '', SW_HIDE, ewWaitUntilTerminated, RC) and (RC = 0);
end;

function Q(const S: String): String;
begin
  { Pfad in Anfuehrungszeichen, ohne abschliessenden Backslash (sonst wird \" als Escape gelesen) }
  Result := '"' + RemoveBackslashUnlessRoot(S) + '"';
end;

procedure Detect;
var
  Lines: TArrayOfString;
  I, P: Integer;
  Key, Value, OutFile: String;
begin
  RainmeterExe := ''; SkinPath := ''; ObsidianExe := ''; OldTodoDir := '';
  VaultList.Clear; TodoInList.Clear;
  OutFile := ExpandConstant('{tmp}\detect.txt');
  DeleteFile(OutFile);
  if not RunHelper('-Mode detect -Out "' + OutFile + '"') then Exit;
  if not LoadStringsFromFile(OutFile, Lines) then Exit;
  for I := 0 to GetArrayLength(Lines) - 1 do
  begin
    P := Pos('=', Lines[I]);
    if P = 0 then Continue;
    Key := Copy(Lines[I], 1, P - 1);
    Value := Copy(Lines[I], P + 1, MaxInt);
    if Key = 'RainmeterExe' then RainmeterExe := Value
    else if Key = 'SkinPath' then SkinPath := Value
    else if Key = 'ObsidianExe' then ObsidianExe := Value
    else if Key = 'Vault' then VaultList.Add(Value)
    else if Key = 'TodoIn' then TodoInList.Add(Value)
    else if Key = 'OldTodo' then OldTodoDir := ExtractFileDir(Value);
  end;
end;

function NeedRainmeter: Boolean;
begin
  Result := RainmeterExe = '';
end;

function NeedObsidian: Boolean;
begin
  Result := ObsidianExe = '';
end;

function NewVaultChosen: Boolean;
begin
  if SilentVault <> '' then begin Result := False; Exit; end;
  Result := (VaultList.Count = 0) or (VaultPage.SelectedValueIndex = VaultList.Count);
end;

function ChosenVault: String;
begin
  if SilentVault <> '' then Result := SilentVault
  else if NewVaultChosen then Result := NewVaultPage.Values[0]
  else Result := VaultList[VaultPage.SelectedValueIndex];
end;

{ vorhandene Todo.md im Vault? dann deren Ordner vorschlagen, sonst den Vault selbst }
function SuggestTodoDir(const Vault: String): String;
var
  I, P: Integer;
begin
  Result := Vault;
  { vorhandene Liste weiterverwenden, wenn sie in diesem Vault liegt }
  if (OldTodoDir <> '') and (Pos(Lowercase(AddBackslash(Vault)), Lowercase(AddBackslash(OldTodoDir))) = 1) then
  begin
    Result := OldTodoDir;
    Exit;
  end;
  if CompareText(RemoveBackslash(Vault), RemoveBackslash(PrevVault)) = 0 then
    if PrevTodoDir <> '' then begin Result := PrevTodoDir; Exit; end;
  for I := 0 to TodoInList.Count - 1 do
  begin
    P := Pos('|', TodoInList[I]);
    if CompareText(RemoveBackslash(Copy(TodoInList[I], 1, P - 1)), RemoveBackslash(Vault)) = 0 then
    begin
      Result := Copy(TodoInList[I], P + 1, MaxInt);
      Exit;
    end;
  end;
end;

{ bisherige Einrichtung: fruehere Setup-Auswahl oder alte Handversion }
function KnownTodoDir: String;
begin
  Result := '';
  if (PrevVault <> '') and (PrevTodoDir <> '') and DirExists(PrevTodoDir) then Result := PrevTodoDir
  else if OldTodoDir <> '' then Result := OldTodoDir;
end;

function KeepSetup: Boolean;
begin
  Result := (KnownTodoDir <> '') and not ChangeCheck.Checked;
end;

procedure InitializeWizard;
var
  I: Integer;
begin
  VaultList := TStringList.Create;
  TodoInList := TStringList.Create;
  ExtractTemporaryFile('helper.ps1');
  Detect;
  RegQueryStringValue(HKCU, RegKey, 'Vault', PrevVault);
  RegQueryStringValue(HKCU, RegKey, 'TodoDir', PrevTodoDir);

  { Seite: Voraussetzungen }
  PrereqPage := CreateCustomPage(wpSelectDir, 'Benötigte Programme', 'Was zusätzlich installiert wird');
  PrereqLabel := TNewStaticText.Create(PrereqPage);
  PrereqLabel.Parent := PrereqPage.Surface;
  PrereqLabel.Width := PrereqPage.SurfaceWidth;
  PrereqLabel.AutoSize := False;
  PrereqLabel.WordWrap := True;
  PrereqLabel.Height := ScaleY(110);
  ObsidianCheck := TNewCheckBox.Create(PrereqPage);
  ObsidianCheck.Parent := PrereqPage.Surface;
  ObsidianCheck.Top := PrereqLabel.Top + PrereqLabel.Height + ScaleY(8);
  ObsidianCheck.Width := PrereqPage.SurfaceWidth;
  ObsidianCheck.Caption := 'Obsidian auch installieren (offizielle Version von obsidian.md)';
  ObsidianCheck.Checked := True;

  { Seite: bisherige Einrichtung uebernehmen }
  KeepPage := CreateCustomPage(PrereqPage.ID, 'Bisherige Einrichtung gefunden', 'Deine Todo-Liste wird weiterverwendet');
  KeepLabel := TNewStaticText.Create(KeepPage);
  KeepLabel.Parent := KeepPage.Surface;
  KeepLabel.Width := KeepPage.SurfaceWidth;
  KeepLabel.AutoSize := False;
  KeepLabel.WordWrap := True;
  KeepLabel.Height := ScaleY(70);
  ChangeCheck := TNewCheckBox.Create(KeepPage);
  ChangeCheck.Parent := KeepPage.Surface;
  ChangeCheck.Top := KeepLabel.Top + KeepLabel.Height + ScaleY(8);
  ChangeCheck.Width := KeepPage.SurfaceWidth;
  ChangeCheck.Caption := 'Andere Todo-Liste wählen';
  ChangeCheck.Checked := False;

  { Seite: Vault waehlen }
  VaultPage := CreateInputOptionPage(KeepPage.ID, 'Obsidian-Vault',
    'In welchem Vault soll die Todo-Liste gespeichert werden?',
    'Diese Vaults wurden auf deinem PC gefunden:', True, False);
  for I := 0 to VaultList.Count - 1 do
    VaultPage.Add(VaultList[I]);
  VaultPage.Add('Neuen Vault anlegen');
  VaultPage.SelectedValueIndex := 0;
  for I := 0 to VaultList.Count - 1 do
    if (PrevVault = '') and (OldTodoDir <> '') and (Pos(Lowercase(AddBackslash(VaultList[I])), Lowercase(AddBackslash(OldTodoDir))) = 1) then
      VaultPage.SelectedValueIndex := I
    else if CompareText(RemoveBackslash(VaultList[I]), RemoveBackslash(PrevVault)) = 0 then
      VaultPage.SelectedValueIndex := I;

  { Seite: neuer Vault }
  NewVaultPage := CreateInputDirPage(VaultPage.ID, 'Neuer Vault',
    'Wo soll der neue Obsidian-Vault liegen?',
    'Der Ordner wird angelegt und in Obsidian eingetragen.', False, 'Obsidian Vault');
  NewVaultPage.Add('');
  NewVaultPage.Values[0] := ExpandConstant('{userdocs}\Obsidian Vault');

  { Seite: Ordner fuer Todo.md }
  TodoPage := CreateInputDirPage(NewVaultPage.ID, 'Speicherort der Liste',
    'In welchem Ordner sollen Todo.md und Todo-Archiv.md liegen?',
    'Eine vorhandene Todo.md wird weiterverwendet, sonst wird eine neue angelegt.', False, '');
  TodoPage.Add('');

  DownloadPage := CreateDownloadPage('Programme werden heruntergeladen', 'Von den offiziellen Seiten (GitHub). Die Prüfsumme wird kontrolliert.', @OnDownloadProgress);
end;

procedure CurPageChanged(CurPageID: Integer);
var
  S: String;
begin
  if CurPageID = KeepPage.ID then
    KeepLabel.Caption := 'Deine Liste in' + #13#10 + AddBackslash(KnownTodoDir) + 'Todo.md' + #13#10 +
      'wird weiterverwendet, mit allen Punkten, Notizen und dem Archiv.';
  if CurPageID = PrereqPage.ID then
  begin
    S := '';
    if NeedRainmeter then
      S := S + 'Rainmeter ist nicht installiert. Es wird jetzt kostenlos von rainmeter.net mitinstalliert ' +
        '(Windows fragt dafür einmal nach Administratorrechten).' + #13#10#13#10
    else
      S := S + 'Rainmeter: gefunden (' + RainmeterExe + ')' + #13#10#13#10;
    if NeedObsidian then
      S := S + 'Obsidian ist nicht installiert. Die Todo-Liste funktioniert auch ohne, ' +
        'du kannst sie dann aber nicht in Obsidian öffnen.'
    else
      S := S + 'Obsidian: gefunden';
    PrereqLabel.Caption := S;
    ObsidianCheck.Visible := NeedObsidian;
  end
  else if CurPageID = TodoPage.ID then
  begin
    if LastVaultForTodo <> ChosenVault then
    begin
      LastVaultForTodo := ChosenVault;
      TodoPage.Values[0] := SuggestTodoDir(ChosenVault);
    end;
  end;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if (PageID = PrereqPage.ID) then Result := not NeedRainmeter and not NeedObsidian
  else if (PageID = KeepPage.ID) then Result := KnownTodoDir = ''
  else if (PageID = VaultPage.ID) then Result := KeepSetup or (VaultList.Count = 0)
  else if (PageID = NewVaultPage.ID) then Result := KeepSetup or not NewVaultChosen
  else if (PageID = TodoPage.ID) then Result := KeepSetup;
end;

{ Adresse/Pruefsumme der neuesten offiziellen Version holen und zur Download-Seite hinzufuegen }
function AddDownload(const What: String): String;
var
  Lines: TArrayOfString;
  I: Integer;
  Url, Name, Sha, OutFile: String;
begin
  Result := '';
  OutFile := ExpandConstant('{tmp}\resolve.txt');
  DeleteFile(OutFile);
  if not RunHelper('-Mode resolve -What ' + What + ' -Out "' + OutFile + '"') then Exit;
  if not LoadStringsFromFile(OutFile, Lines) then Exit;
  for I := 0 to GetArrayLength(Lines) - 1 do
  begin
    if Pos('Url=', Lines[I]) = 1 then Url := Copy(Lines[I], 5, MaxInt)
    else if Pos('Name=', Lines[I]) = 1 then Name := Copy(Lines[I], 6, MaxInt)
    else if Pos('Sha=', Lines[I]) = 1 then Sha := Copy(Lines[I], 5, MaxInt);
  end;
  if (Url = '') or (Name = '') then Exit;
  DownloadPage.Add(Url, Name, Sha);
  Result := ExpandConstant('{tmp}\') + Name;
end;

function WantObsidian: Boolean;
begin
  { ohne Fenster (Updates, automatische Tests) nie ungefragt Obsidian installieren }
  Result := NeedObsidian and ObsidianCheck.Checked and not WizardSilent;
end;

{ Rainmeter/Obsidian laden (mit Fortschrittsanzeige) und installieren }
function InstallPrograms: Boolean;
var
  RmFile, ObsFile: String;
  Busy: TOutputMarqueeProgressWizardPage;
begin
  Result := True;
  RmFile := ''; ObsFile := '';
  DownloadPage.Clear;
  if NeedRainmeter then RmFile := AddDownload('rainmeter');
  if WantObsidian then ObsFile := AddDownload('obsidian');
  if NeedRainmeter and (RmFile = '') then
  begin
    MsgBox('Die Download-Adresse von Rainmeter konnte nicht ermittelt werden. Bist du mit dem Internet verbunden?', mbError, MB_OK);
    Result := False;
    Exit;
  end;

  DownloadPage.Show;
  try
    try
      DownloadPage.Download;
    except
      if DownloadPage.AbortedByUser then
        MsgBox('Download abgebrochen.', mbInformation, MB_OK)
      else
        MsgBox('Download fehlgeschlagen: ' + GetExceptionMessage, mbError, MB_OK);
      Result := False;
      Exit;
    end;
  finally
    DownloadPage.Hide;
  end;

  Busy := CreateOutputMarqueeProgressPage('Programme werden installiert', 'Einen Moment bitte.');
  Busy.Show;
  try
    if ObsFile <> '' then
    begin
      Busy.SetText('Obsidian wird installiert …', '');
      Busy.Animate;
      if not RunHelper('-Mode install -What obsidian -File "' + ObsFile + '"') then
        MsgBox('Obsidian konnte nicht installiert werden. Du kannst es später selbst von obsidian.md installieren.', mbInformation, MB_OK);
    end;
    if RmFile <> '' then
    begin
      Busy.SetText('Rainmeter wird installiert … (bitte die Windows-Abfrage mit „Ja“ bestätigen)', '');
      Busy.Animate;
      RunHelper('-Mode install -What rainmeter -File "' + RmFile + '"');
    end;
    Detect;
  finally
    Busy.Hide;
  end;
  if NeedRainmeter then
  begin
    MsgBox('Rainmeter konnte nicht installiert werden. Bitte installiere es von rainmeter.net und starte dieses Setup danach noch einmal.', mbError, MB_OK);
    Result := False;
  end;
end;

{ Vault zur bisherigen Liste: fruehere Setup-Auswahl, sonst der bekannte Vault, in dem sie liegt }
function VaultFor(const Dir: String): String;
var
  I: Integer;
begin
  Result := PrevVault;
  if Result <> '' then Exit;
  for I := 0 to VaultList.Count - 1 do
    if Pos(Lowercase(AddBackslash(VaultList[I])), Lowercase(AddBackslash(Dir))) = 1 then
    begin
      Result := VaultList[I];
      Exit;
    end;
  Result := Dir;
end;

procedure ApplyKeep;
begin
  if not KeepSetup then begin SilentVault := ''; Exit; end;
  SilentVault := VaultFor(KnownTodoDir);
  TodoPage.Values[0] := KnownTodoDir;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  V: String;
begin
  Result := True;
  if CurPageID = KeepPage.ID then ApplyKeep;
  if CurPageID = TodoPage.ID then
  begin
    V := AddBackslash(ChosenVault);
    if CompareText(Copy(AddBackslash(TodoPage.Values[0]), 1, Length(V)), V) <> 0 then
    begin
      MsgBox('Der Ordner muss im Vault liegen:' + #13#10 + ChosenVault, mbError, MB_OK);
      Result := False;
    end;
  end
  else if (CurPageID = wpReady) and (NeedRainmeter or WantObsidian) then
    Result := InstallPrograms;
end;

{ unbeaufsichtigtes Update: gespeicherte Auswahl wiederverwenden }
procedure ApplySilentDefaults;
begin
  if PrevVault <> '' then
  begin
    SilentVault := PrevVault;
    TodoPage.Values[0] := PrevTodoDir;
    if TodoPage.Values[0] = '' then TodoPage.Values[0] := PrevVault;
  end
  else if TodoPage.Values[0] = '' then
    TodoPage.Values[0] := SuggestTodoDir(ChosenVault);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  RC: Integer;
begin
  Result := '';
  if WizardSilent then ApplySilentDefaults;

  { laufendes Tastenkuerzel-Programm beenden, sonst laesst sich TodoHotkey.exe nicht ersetzen }
  Exec('taskkill.exe', '/F /IM TodoHotkey.exe', '', SW_HIDE, ewWaitUntilTerminated, RC);

  { ohne Fenster (z. B. automatischer Test) laedt das Hilfsskript Rainmeter selbst }
  if WizardSilent and NeedRainmeter then
  begin
    RunHelper('-Mode install -What rainmeter');
    Detect;
  end;
  if NeedRainmeter then
    Result := 'Rainmeter konnte nicht installiert werden. Bitte installiere es von rainmeter.net und starte dieses Setup danach noch einmal.';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Args: String;
begin
  if CurStep = ssPostInstall then
  begin
    Args := '-Mode apply -App ' + Q(ExpandConstant('{app}')) +
      ' -Vault ' + Q(ChosenVault) + ' -TodoDir ' + Q(TodoPage.Values[0]) +
      ' -RainmeterExe ' + Q(RainmeterExe) + ' -SkinPath ' + Q(SkinPath);
    if NewVaultChosen then Args := Args + ' -NewVault';
    if RunHelper(Args) then
    begin
      RegWriteStringValue(HKCU, RegKey, 'Vault', RemoveBackslash(ChosenVault));
      RegWriteStringValue(HKCU, RegKey, 'TodoDir', RemoveBackslash(TodoPage.Values[0]));
    end
    else if not WizardSilent then
      MsgBox('Beim Einrichten ist etwas schiefgegangen. Details stehen in ' +
        ExpandConstant('{%TEMP}\ObsidianTodo-Setup.log'), mbError, MB_OK);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  RC: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    Exec(PowerShellExe, '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
      ExpandConstant('{app}\helper.ps1') + '" -Mode uninstall', '', SW_HIDE, ewWaitUntilTerminated, RC);
    RegDeleteKeyIncludingSubkeys(HKCU, RegKey);
  end;
end;

procedure DeinitializeSetup;
begin
  if VaultList <> nil then VaultList.Free;
  if TodoInList <> nil then TodoInList.Free;
end;
