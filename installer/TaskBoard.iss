; Installer fuer Task Board (frueher Obsidian Todo) (Inno Setup 7)
; Bauen ueber ..\build.ps1 - der uebergibt AppVersion und baut vorher den Skin nach ..\dist\skin.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName "Task Board"
#define SkinDir "..\dist\skin\TaskBoard"

[Setup]
AppId={{16E88833-5A38-4DDC-8401-D15AD3FA1B60}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Task Board
VersionInfoVersion={#AppVersion}
; Programmordner: neu unter "Task Board"; bestehende Installationen bleiben, wo sie sind - nur ein Ordner
; namens "Obsidian Todo" (bis 1.3.0) wird zu "Task Board" daneben (DefDir; helper.ps1 zieht um und raeumt auf)
DefaultDirName={code:DefDir}
UsePreviousAppDir=no
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
de.WelcomeLabel2=Damit bekommst du eine Todo-Liste auf dem Desktop – gespeichert in deinem Obsidian-Vault, in Google Tasks oder in beiden.%n%nRainmeter (zeigt die Liste auf dem Desktop an) wird bei Bedarf automatisch mitinstalliert.

[Files]
Source: "helper.ps1"; Flags: dontcopy
; fuer die Google-Anmeldung schon waehrend des Setups (TaskBoardHotkey.exe --google-connect)
Source: "{#SkinDir}\@Resources\TaskBoardHotkey.exe"; Flags: dontcopy
Source: "{#SkinDir}\@Resources\google-client.json"; Flags: dontcopy skipifsourcedoesntexist
Source: "helper.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SkinDir}\*"; DestDir: "{app}\TaskBoard"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; altes Hilfe-Fenster (seit 1.2.0: Einstellungen)
Type: filesandordirs; Name: "{app}\TaskBoard\Hilfe"
; Startmenue-Eintrag von vor der Umbenennung in Task Board
Type: files; Name: "{userprograms}\Obsidian To-do entfernen.lnk"

[Icons]
Name: "{userprograms}\Task Board entfernen"; Filename: "{uninstallexe}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 31

[UninstallDelete]
; vom Skin zur Laufzeit erzeugte Dateien (settings.inc, hotkey.txt, ...)
Type: filesandordirs; Name: "{app}\TaskBoard"

[Code]
const
  RegKey = 'Software\TaskBoard';
  OldRegKey = 'Software\ObsidianTodo';   { bis 1.3.0 }
  UninstKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{16E88833-5A38-4DDC-8401-D15AD3FA1B60}_is1';

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
  OldAppDir: String;
  { Speicherort (nur bei Neuinstallation): Obsidian und/oder Google Tasks }
  FreshInstall: Boolean;
  StorePage, GooglePage: TWizardPage;
  ObsCheck, GoogleCheck: TNewCheckBox;
  GoogleBtn: TNewButton;
  GoogleLabel: TNewStaticText;
  GoogleListId, GoogleListName: String;

{ bisheriger Programmordner (leer bei Erstinstallation) }
function PrevAppDir: String;
begin
  Result := '';
  if not RegQueryStringValue(HKCU, UninstKey, 'Inno Setup: App Path', Result) then Result := '';
  Result := RemoveBackslash(Result);
end;

function DefDir(Param: String): String;
begin
  Result := PrevAppDir;
  if Result = '' then
    Result := ExpandConstant('{localappdata}\Programs\Task Board')
  else if CompareText(ExtractFileName(Result), 'Obsidian Todo') = 0 then
    Result := AddBackslash(ExtractFileDir(Result)) + 'Task Board';
end;

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

{ Obsidian gewaehlt? Bei Updates immer (die Einstellung bleibt, wie sie ist) }
function UseObsidian: Boolean;
begin
  Result := (not FreshInstall) or ObsCheck.Checked;
end;

{ Google-Anmeldung im Setup: TaskBoardHotkey.exe meldet an, laesst die Liste waehlen und schreibt "id<TAB>name" }
procedure GoogleConnectClick(Sender: TObject);
var
  RC, P: Integer;
  OutFile: String;
  Lines: TArrayOfString;
begin
  ExtractTemporaryFile('TaskBoardHotkey.exe');
  try ExtractTemporaryFile('google-client.json'); except end;
  OutFile := ExpandConstant('{tmp}\google-list.txt');
  DeleteFile(OutFile);
  GoogleBtn.Enabled := False;
  GoogleLabel.Caption := 'Dein Browser öffnet sich – bitte bei Google anmelden und Task Board erlauben. ' +
    'Bei „Google hat diese App nicht überprüft“: „Erweitert“ und dann „Zu Task Board wechseln“. Danach die Liste wählen.';
  WizardForm.Repaint;
  Exec(ExpandConstant('{tmp}\TaskBoardHotkey.exe'), '--google-connect --out "' + OutFile + '"', '', SW_SHOWNORMAL, ewWaitUntilTerminated, RC);
  GoogleBtn.Enabled := True;
  if (RC = 0) and LoadStringsFromFile(OutFile, Lines) and (GetArrayLength(Lines) > 0) and (Pos(#9, Lines[0]) > 0) then
  begin
    if (Length(Lines[0]) > 0) and (Lines[0][1] = #$FEFF) then Delete(Lines[0], 1, 1);
    P := Pos(#9, Lines[0]);
    GoogleListId := Copy(Lines[0], 1, P - 1);
    GoogleListName := Copy(Lines[0], P + 1, MaxInt);
    GoogleLabel.Caption := 'Verbunden. Deine Aufgaben kommen in die Google-Liste „' + GoogleListName + '“.';
    GoogleBtn.Caption := 'Andere Liste wählen';
  end
  else
    GoogleLabel.Caption := 'Die Anmeldung hat nicht geklappt oder wurde abgebrochen. Du kannst es nochmal versuchen.';
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
  if not RegQueryStringValue(HKCU, RegKey, 'Vault', PrevVault) then
    RegQueryStringValue(HKCU, OldRegKey, 'Vault', PrevVault);
  if not RegQueryStringValue(HKCU, RegKey, 'TodoDir', PrevTodoDir) then
    RegQueryStringValue(HKCU, OldRegKey, 'TodoDir', PrevTodoDir);
  { Neuinstallation: noch nie installiert und keine alte Handversion }
  FreshInstall := (PrevAppDir = '') and (PrevVault = '') and (OldTodoDir = '');

  { Seite: Speicherort (Haekchen, mindestens eins) - nur bei Neuinstallation }
  StorePage := CreateCustomPage(wpSelectDir, 'Speicherort', 'Wo sollen deine Aufgaben gespeichert werden?');
  ObsCheck := TNewCheckBox.Create(StorePage);
  ObsCheck.Parent := StorePage.Surface;
  ObsCheck.Width := StorePage.SurfaceWidth;
  ObsCheck.Caption := 'Obsidian – als Todo.md in deinem Obsidian-Vault';
  ObsCheck.Checked := True;
  GoogleCheck := TNewCheckBox.Create(StorePage);
  GoogleCheck.Parent := StorePage.Surface;
  GoogleCheck.Top := ObsCheck.Top + ObsCheck.Height + ScaleY(14);
  GoogleCheck.Width := StorePage.SurfaceWidth;
  GoogleCheck.Caption := 'Google Tasks – auch am Handy, Anmeldung mit deinem Google-Konto';
  GoogleCheck.Checked := False;
  with TNewStaticText.Create(StorePage) do
  begin
    Parent := StorePage.Surface;
    Top := GoogleCheck.Top + GoogleCheck.Height + ScaleY(18);
    Width := StorePage.SurfaceWidth;
    AutoSize := False;
    WordWrap := True;
    Height := ScaleY(80);
    Caption := 'Beides angehakt: Die Liste wird in beide Richtungen abgeglichen – was du in Obsidian änderst, ' +
      'landet bei Google, und was du am Handy änderst, steht danach auch in Obsidian. Später umstellbar im Zahnrad neben „Todo“.';
  end;

  { Seite: Google-Anmeldung }
  GooglePage := CreateCustomPage(StorePage.ID, 'Google Tasks', 'Mit deinem Google-Konto verbinden');
  GoogleLabel := TNewStaticText.Create(GooglePage);
  GoogleLabel.Parent := GooglePage.Surface;
  GoogleLabel.Width := GooglePage.SurfaceWidth;
  GoogleLabel.AutoSize := False;
  GoogleLabel.WordWrap := True;
  GoogleLabel.Height := ScaleY(90);
  GoogleLabel.Caption := 'Klicke auf „Mit Google anmelden“. Dein Browser öffnet sich; danach wählst du, in welcher Google-Liste ' +
    'deine Aufgaben liegen sollen. Andere Listen in deinem Konto bleiben unberührt.';
  GoogleBtn := TNewButton.Create(GooglePage);
  GoogleBtn.Parent := GooglePage.Surface;
  GoogleBtn.Top := GoogleLabel.Top + GoogleLabel.Height + ScaleY(10);
  GoogleBtn.Width := ScaleX(200);
  GoogleBtn.Height := ScaleY(30);
  GoogleBtn.Caption := 'Mit Google anmelden';
  GoogleBtn.OnClick := @GoogleConnectClick;

  { Seite: Voraussetzungen }
  PrereqPage := CreateCustomPage(GooglePage.ID, 'Benötigte Programme', 'Was zusätzlich installiert wird');
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
    if not UseObsidian then
      S := S + ''
    else if NeedObsidian then
      S := S + 'Obsidian ist nicht installiert. Die Todo-Liste funktioniert auch ohne, ' +
        'du kannst sie dann aber nicht in Obsidian öffnen.'
    else
      S := S + 'Obsidian: gefunden';
    PrereqLabel.Caption := S;
    ObsidianCheck.Visible := NeedObsidian and UseObsidian;
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
  if (PageID = StorePage.ID) then Result := not FreshInstall
  else if (PageID = GooglePage.ID) then Result := not FreshInstall or not GoogleCheck.Checked
  else if (PageID = PrereqPage.ID) then Result := not NeedRainmeter and not (NeedObsidian and UseObsidian)
  else if not UseObsidian and ((PageID = KeepPage.ID) or (PageID = VaultPage.ID) or (PageID = NewVaultPage.ID) or (PageID = TodoPage.ID)) then Result := True
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
  Result := NeedObsidian and UseObsidian and ObsidianCheck.Checked and not WizardSilent;
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
  if (CurPageID = StorePage.ID) and not ObsCheck.Checked and not GoogleCheck.Checked then
  begin
    MsgBox('Bitte mindestens einen Speicherort anhaken.', mbInformation, MB_OK);
    Result := False;
    Exit;
  end;
  if (CurPageID = GooglePage.ID) and (GoogleListId = '') then
  begin
    if not ObsCheck.Checked then
    begin
      MsgBox('Bitte zuerst bei Google anmelden – oder auf der vorigen Seite „Obsidian“ anhaken.', mbInformation, MB_OK);
      Result := False;
    end
    else if MsgBox('Ohne Google weiter? Du kannst Google später im Zahnrad neben „Todo“ verbinden.', mbConfirmation, MB_YESNO) = IDYES then
      GoogleCheck.Checked := False
    else
      Result := False;
    Exit;
  end;
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

  { laufendes Tastenkuerzel-Programm beenden, sonst laesst sich TaskBoardHotkey.exe nicht ersetzen
    (TodoHotkey.exe = Name bis 1.3.0) }
  Exec('taskkill.exe', '/F /IM TaskBoardHotkey.exe', '', SW_HIDE, ewWaitUntilTerminated, RC);
  Exec('taskkill.exe', '/F /IM TodoHotkey.exe', '', SW_HIDE, ewWaitUntilTerminated, RC);
  OldAppDir := PrevAppDir;

  { ohne Fenster (z. B. automatischer Test) laedt das Hilfsskript Rainmeter selbst - aber nie bei einem Update:
    dann gibt es Rainmeter schon (z. B. portabel und gerade beendet), ein zweites waere falsch }
  if WizardSilent and NeedRainmeter and (OldAppDir <> '') then
    Result := 'Rainmeter wurde nicht gefunden. Bitte Rainmeter starten und das Update noch einmal ausführen.'
  else if WizardSilent and NeedRainmeter then
  begin
    RunHelper('-Mode install -What rainmeter');
    Detect;
  end;
  if NeedRainmeter and (Result = '') then
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
    if (OldAppDir <> '') and (CompareText(OldAppDir, RemoveBackslash(ExpandConstant('{app}'))) <> 0) then
      Args := Args + ' -OldApp ' + Q(OldAppDir);
    if FreshInstall and GoogleCheck.Checked and (GoogleListId <> '') then
      Args := Args + ' -GoogleList ' + Q(GoogleListId) + ' -GoogleListName ' + Q(GoogleListName);
    if not UseObsidian then Args := Args + ' -NoObsidian';
    if RunHelper(Args) then
    begin
      if UseObsidian then
      begin
        RegWriteStringValue(HKCU, RegKey, 'Vault', RemoveBackslash(ChosenVault));
        RegWriteStringValue(HKCU, RegKey, 'TodoDir', RemoveBackslash(TodoPage.Values[0]));
      end;
    end
    else if not WizardSilent then
      MsgBox('Beim Einrichten ist etwas schiefgegangen. Details stehen in ' +
        ExpandConstant('{%TEMP}\TaskBoard-Setup.log'), mbError, MB_OK);
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
    RegDeleteKeyIncludingSubkeys(HKCU, OldRegKey);
  end;
end;

procedure DeinitializeSetup;
begin
  if VaultList <> nil then VaultList.Free;
  if TodoInList <> nil then TodoInList.Free;
end;
