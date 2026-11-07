# Hilfsskript fuer TaskBoard-Setup.exe (wird vom Installer unsichtbar aufgerufen).
#   detect    -Out <datei>                      Rainmeter, Obsidian und Vaults erkennen (key=value je Zeile)
#   install   -What rainmeter|obsidian          offizielle neueste Version von GitHub laden und installieren
#   apply     -App -Vault -TodoDir -RainmeterExe -SkinPath [-NewVault]
#                                               Skin verknuepfen, settings.inc schreiben, Todo.md anlegen, starten
#   uninstall -App                              Skin entfernen (Todo.md bleibt erhalten)
# apply zieht vorher eine Installation von vor der Umbenennung (Obsidian Todo, Skin "ObsidianTodo") um, siehe Move-OldInstall.
#   -OldApp = bisheriger Programmordner, falls er sich geaendert hat (z. B. "...\Obsidian Todo" -> "...\Task Board")
param(
    [Parameter(Mandatory)][ValidateSet('detect', 'resolve', 'install', 'apply', 'uninstall')][string]$Mode,
    [string]$Out, [string]$What, [string]$File, [string]$App, [string]$Vault, [string]$TodoDir,
    [string]$RainmeterExe, [string]$SkinPath, [switch]$NewVault, [string]$OldApp
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # sonst ist Invoke-WebRequest in PowerShell 5 extrem langsam
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$SkinName = 'TaskBoard'
$OldSkinName = 'ObsidianTodo'   # Name bis 1.3.0 (Obsidian Todo)
$log = Join-Path $env:TEMP 'TaskBoard-Setup.log'
function Log($m) { Add-Content -LiteralPath $log -Value "$(Get-Date -Format s) [$Mode] $m" -Encoding UTF8 }

function Find-Rainmeter {
    # 1. laufendes Rainmeter (auch portable Installationen)
    $p = Get-Process Rainmeter -ErrorAction SilentlyContinue | Select-Object -First 1
    $exe = if ($p) { $p.Path }
    # aus 32-Bit-PowerShell liefert Get-Process fuer 64-Bit-Programme keinen Pfad -> ueber WMI fragen
    if (-not $exe) {
        $exe = Get-CimInstance Win32_Process -Filter "Name='Rainmeter.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ExecutablePath } | Select-Object -First 1 -ExpandProperty ExecutablePath
    }
    # 2. vom Installer uebergebener Pfad (wichtig, wenn Rainmeter gerade beendet ist - z. B. beim Umzug -,
    #    sonst wuerde eine portable Installation nicht gefunden und eine falsche Rainmeter.ini angelegt)
    if (-not $exe -and $RainmeterExe -and (Test-Path -LiteralPath $RainmeterExe)) { $exe = $RainmeterExe }
    # von einer frueheren Einrichtung gemerkt (portables Rainmeter, das gerade nicht laeuft)
    if (-not $exe) {
        $saved = (Get-ItemProperty "HKCU:\Software\$SkinName" -Name RainmeterExe -ErrorAction SilentlyContinue).RainmeterExe
        if ($saved -and (Test-Path -LiteralPath $saved)) { $exe = $saved }
    }
    # Autostart-Verknuepfung "Rainmeter" (so starten viele ein portables Rainmeter)
    if (-not $exe) {
        $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Rainmeter.lnk'
        if (Test-Path -LiteralPath $lnk) {
            try { $t = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk).TargetPath; if ($t -and (Test-Path -LiteralPath $t)) { $exe = $t } } catch {}
        }
    }
    # 3. normale Installation
    if (-not $exe) {
        foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Rainmeter', 'HKLM:\SOFTWARE\Rainmeter', 'HKCU:\SOFTWARE\Rainmeter') {
            $d = (Get-ItemProperty $k -ErrorAction SilentlyContinue).'(default)'
            if ($d -and (Test-Path (Join-Path $d 'Rainmeter.exe'))) { $exe = Join-Path $d 'Rainmeter.exe'; break }
        }
    }
    # ProgramW6432 = echtes "Programme" auch aus 32-Bit-PowerShell (ProgramFiles waere dort "Programme (x86)")
    foreach ($pf in @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }) {
        if (-not $exe -and (Test-Path "$pf\Rainmeter\Rainmeter.exe")) { $exe = "$pf\Rainmeter\Rainmeter.exe" }
    }
    if (-not $exe) { return $null }

    # Einstellungsdatei: portable = neben der exe, sonst %APPDATA%\Rainmeter
    $dir = Split-Path $exe
    $ini = Join-Path $dir 'Rainmeter.ini'
    if (-not (Test-Path $ini)) { $ini = Join-Path $env:APPDATA 'Rainmeter\Rainmeter.ini' }
    $skins = $null
    if (Test-Path $ini) {
        $line = Select-String -LiteralPath $ini -Pattern '^\s*SkinPath\s*=\s*(.+)$' | Select-Object -First 1
        if ($line) { $skins = $line.Matches[0].Groups[1].Value.Trim() }
    }
    if (-not $skins) { $skins = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins\' }
    [pscustomobject]@{ Exe = $exe; Skins = $skins.TrimEnd('\'); Ini = $ini }
}

function Find-Obsidian {
    foreach ($c in "$env:LOCALAPPDATA\Programs\Obsidian\Obsidian.exe", "$env:LOCALAPPDATA\Obsidian\Obsidian.exe", "$env:ProgramFiles\Obsidian\Obsidian.exe") {
        if (Test-Path $c) { return $c }
    }
    $cmd = (Get-ItemProperty 'Registry::HKEY_CLASSES_ROOT\obsidian\shell\open\command' -ErrorAction SilentlyContinue).'(default)'
    if ($cmd -match '^"([^"]+)"') { return $Matches[1] }
    $null
}

function Get-ObsidianConfig {
    $f = Join-Path $env:APPDATA 'obsidian\obsidian.json'
    if (Test-Path $f) { try { return Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
    $null
}

$Sources = @{
    rainmeter = @('rainmeter/rainmeter', '^Rainmeter-[\d.]+(-r\d+)?\.exe$')
    obsidian  = @('obsidianmd/obsidian-releases', '^Obsidian-[\d.]+\.exe$')
}

function Find-LatestAsset($repo, $pattern) {
    $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'TaskBoard-Setup' } -UseBasicParsing
    $a = $rel.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
    if (-not $a) { throw "Keine passende Datei im neuesten Release von $repo" }
    $a
}

function Get-LatestAsset($repo, $pattern) {
    $a = Find-LatestAsset $repo $pattern
    $file = Join-Path $env:TEMP $a.name
    Invoke-WebRequest $a.browser_download_url -OutFile $file -UseBasicParsing
    if ($a.digest -match '^sha256:([0-9a-f]{64})$' -and (Get-FileHash $file -Algorithm SHA256).Hash.ToLower() -ne $Matches[1]) {
        throw "Pruefsumme von $($a.name) stimmt nicht"
    }
    $file
}

function Url($s) { [Uri]::EscapeDataString($s) }

# Abschnitt in einer .ini setzen/ergaenzen, Kodierung beibehalten (Rainmeter.ini ist meist UTF-16 LE)
function Set-IniSection($path, $section, $values) {
    $enc = [Text.Encoding]::Unicode
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $path) {
        $bytes = [IO.File]::ReadAllBytes($path)
        if (-not ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE)) { $enc = New-Object Text.UTF8Encoding($false) }
        foreach ($l in ($enc.GetString($bytes).TrimStart([char]0xFEFF) -split "`r?`n")) { $lines.Add($l) }
    } else {
        New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    }
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq "[$section]") { $start = $i; break } }
    if ($start -lt 0) {
        if ($lines.Count -and $lines[$lines.Count - 1] -ne '') { $lines.Add('') }
        $lines.Add("[$section]"); $start = $lines.Count - 1
    }
    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[') { $end = $i; break } }
    foreach ($k in $values.Keys) {
        $found = $false
        for ($i = $start + 1; $i -lt $end; $i++) {
            if ($lines[$i] -match "^\s*$([regex]::Escape($k))\s*=") { $lines[$i] = "$k=$($values[$k])"; $found = $true; break }
        }
        if (-not $found) { $lines.Insert($end, "$k=$($values[$k])"); $end++ }
    }
    [IO.File]::WriteAllText($path, ($lines -join "`r`n"), $enc)
}

# Ist das Fenster der Liste da? (Rainmeter benennt Skin-Fenster nach dem Pfad der .ini)
# Fragt das mitgelieferte TaskBoardHotkey.exe (fertig uebersetzt) - Add-Type wuerde zur Laufzeit C# uebersetzen,
# und das ist nicht ueberall erlaubt. Kann nicht geprueft werden -> als "ok" werten (die .ini ist ohnehin gesetzt).
function Test-SkinWindow {
    $exe = Join-Path $App "$SkinName\@Resources\TaskBoardHotkey.exe"
    if (-not (Test-Path -LiteralPath $exe)) { return $true }
    try {
        # Seitenleiste: die Liste ist anfangs versteckt, dann zaehlt der sichtbare Rand-Streifen
        foreach ($end in "\$SkinName\Todo.ini", "\$SkinName\Rand\Rand.ini") {
            $p = Start-Process -FilePath $exe -ArgumentList '--check', "`"$end`"" -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -eq 0) { return $true }
        }
        return $false
    } catch { return $true }
}

# Rainmeter ueber den Explorer starten (wie ein Doppelklick). Direkt aus dem Setup gestartet (Prozesskette
# Setup -> PowerShell) stuerzte Rainmeter 4.5.28 beim Test am 07.11.2026 sofort ab, auch spaeter nach dem Setup.
function Start-Rainmeter {
    Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList "`"$RainmeterExe`""
}

# Rainmeter erst starten, wenn das Setup (Elternprozesse dieses Skripts) beendet ist - ein eigener,
# unsichtbarer PowerShell-Prozess wartet darauf (hoechstens 10 Minuten)
function Start-RainmeterAfterSetup {
    $ids = @()
    $id = $PID
    for ($i = 0; $i -lt 3; $i++) {
        $parent = (Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue).ParentProcessId
        if (-not $parent) { break }
        $pp = Get-CimInstance Win32_Process -Filter "ProcessId=$parent" -ErrorAction SilentlyContinue
        # nur das Setup selbst (Setup-exe und Inno-.tmp), nicht Explorer o. Ae., von dem es gestartet wurde
        if (-not $pp -or $pp.Name -notmatch 'Setup|\.tmp$') { break }
        $ids += $parent; $id = $parent
    }
    if (-not $ids) { $ids = @(-1) }   # keine Setup-Prozesse gefunden: nicht warten (-1 gibt es nicht)
    $exe = $RainmeterExe.Replace("'", "''")
    $cmd = "`$ids = @($($ids -join ',')); for (`$i = 0; `$i -lt 600 -and (Get-Process -Id `$ids -ErrorAction SilentlyContinue); `$i++) { Start-Sleep 1 }; " +
        "Start-Sleep 2; if (-not (Get-Process Rainmeter -ErrorAction SilentlyContinue)) { Start-Process -FilePath (Join-Path `$env:WINDIR 'explorer.exe') -ArgumentList ('`"' + '$exe' + '`"') }"
    Start-Process powershell.exe -ArgumentList '-NoProfile', '-WindowStyle', 'Hidden', '-Command', $cmd -WindowStyle Hidden
}

# Abschnitte [ObsidianTodo] und [ObsidianTodo\...] in Rainmeter.ini in [TaskBoard...] umbenennen
# (Position, Aktiv, Transparenz usw. bleiben so erhalten). Gibt es schon einen neuen Abschnitt, gewinnt der neue.
function Rename-IniSections($path) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    $bytes = [IO.File]::ReadAllBytes($path)
    $enc = if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { [Text.Encoding]::Unicode } else { New-Object Text.UTF8Encoding($false) }
    $lines = $enc.GetString($bytes).TrimStart([char]0xFEFF) -split "`r?`n"
    $have = @{}
    foreach ($l in $lines) { if ($l.Trim() -match "^\[($SkinName(\\.*)?)\]$") { $have[$Matches[1].ToLower()] = $true } }
    $out = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($l in $lines) {
        if ($l -match '^\s*\[') {
            $skip = $false
            if ($l.Trim() -match "^\[$OldSkinName(\\.*)?\]$") {
                $new = "$SkinName$($Matches[1])"
                if ($have[$new.ToLower()]) { $skip = $true; continue }
                $l = "[$new]"
            }
        }
        if (-not $skip) { $out.Add($l) }
    }
    [IO.File]::WriteAllText($path, ($out -join "`r`n"), $enc)
}

# Reste [ObsidianTodo...] entfernen: beim Neuladen nach dem Umzug schreibt Rainmeter fuer die geschlossenen
# alten Skins noch einmal "Active=0" in die alten Abschnitte
function Remove-OldIniSections($path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return }
    $bytes = [IO.File]::ReadAllBytes($path)
    $enc = if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { [Text.Encoding]::Unicode } else { New-Object Text.UTF8Encoding($false) }
    $lines = $enc.GetString($bytes).TrimStart([char]0xFEFF) -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    $skip = $false; $removed = $false
    foreach ($l in $lines) {
        if ($l -match '^\s*\[') { $skip = $l.Trim() -match "^\[$OldSkinName(\\.*)?\]$"; if ($skip) { $removed = $true } }
        if (-not $skip) { $out.Add($l) }
    }
    if ($removed) { [IO.File]::WriteAllText($path, ($out -join "`r`n"), $enc); Log 'Umzug: alte Abschnitte aus Rainmeter.ini entfernt' }
}

# Umzug einer Installation von vor der Umbenennung (Skin-Ordner "ObsidianTodo"): eigene Einstellungen, Positionen,
# Registry, Aufgabe, Protokoll und Statusordner auf "TaskBoard" umstellen und die alten Reste entfernen.
# Die Todo.md und das Archiv werden dabei nicht angefasst.
function Move-OldInstall {
    $newRes = Join-Path $App "$SkinName\@Resources"
    $oldLink = Join-Path $SkinPath $OldSkinName
    $oldSkin = $null; $isJunction = $false
    $it = Get-Item -LiteralPath $oldLink -Force -ErrorAction SilentlyContinue
    if ($it) {
        $isJunction = $it.LinkType -eq 'Junction'
        $oldSkin = if ($isJunction) { @($it.Target)[0] } else { $oldLink }
    }
    if (-not $oldSkin -or -not (Test-Path -LiteralPath $oldSkin)) {
        foreach ($d in @($OldApp, $App) | Where-Object { $_ }) {
            $c = Join-Path $d $OldSkinName
            if (Test-Path -LiteralPath (Join-Path $c '@Resources')) { $oldSkin = $c; break }
        }
    }
    if (-not $oldSkin -or -not (Test-Path -LiteralPath $oldSkin)) { return }
    Log "Umzug: alte Installation gefunden: $oldSkin"
    # Rainmeter.ini bestimmen, solange Rainmeter noch laeuft
    $rmInfo = Find-Rainmeter
    $ini = if ($rmInfo -and $rmInfo.Ini) { $rmInfo.Ini } else { $null }
    # ohne Rainmeter.ini trotzdem umziehen (sonst liefen alte und neue Liste doppelt) - nur die Positionen fehlen dann
    if (-not $ini -or -not (Test-Path -LiteralPath $ini)) { Log "Umzug: Rainmeter.ini nicht gefunden - Positionen werden nicht uebernommen"; $ini = $null }

    # Rainmeter laeuft weiter: wir aendern Rainmeter.ini und die Ordner, danach laedt apply alles mit !RefreshApp neu
    # (liest Rainmeter.ini neu ein). Rainmeter beenden und neu starten ist riskant - aus dem Setup heraus gestartet
    # stuerzte Rainmeter 4.5.28 beim Test am 07.11.2026 jedes Mal ab.
    Get-Process TodoHotkey -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300

    # alles, was der Skin zur Laufzeit angelegt hat (prefs.inc, colors.inc, settings.inc, Zustandsdateien), uebernehmen:
    # jede Datei aus dem alten @Resources, die das neue Paket nicht selbst mitbringt
    $oldRes = Join-Path $oldSkin '@Resources'
    if (Test-Path -LiteralPath $oldRes) {
        New-Item -ItemType Directory -Force $newRes | Out-Null
        Get-ChildItem -LiteralPath $oldRes -Recurse -File -Force | ForEach-Object {
            $rel = $_.FullName.Substring($oldRes.Length).TrimStart('\')
            $dst = Join-Path $newRes $rel
            if ($rel -match '^TodoHotkey\.exe$') { return }
            if (-not (Test-Path -LiteralPath $dst)) {
                New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
                Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
                Log "Umzug: uebernommen $rel"
            }
        }
    }

    # Fensterpositionen und Zustand in Rainmeter.ini
    if ($ini) { Rename-IniSections $ini; Log "Umzug: Rainmeter.ini umgestellt ($ini)" }

    # alte Verknuepfung im Skins-Ordner weg (eine alte Handversion ohne Verknuepfung wird gesichert, nicht geloescht)
    if (Test-Path -LiteralPath $oldLink) {
        if ($isJunction) { cmd /c rmdir "`"$oldLink`"" | Out-Null }
        else {
            $bakDir = Join-Path $App 'Sicherung'
            New-Item -ItemType Directory -Force $bakDir | Out-Null
            $bak = Join-Path $bakDir "$OldSkinName-alt-$(Get-Date -Format yyyyMMdd-HHmmss)"
            try { Move-Item -LiteralPath $oldLink -Destination $bak -ErrorAction Stop }
            catch { Copy-Item -LiteralPath $oldLink -Destination $bak -Recurse; Remove-Item -LiteralPath $oldLink -Recurse -Force }
            Log "Umzug: alte Handversion gesichert: $bak"
        }
    }

    # Registry (gewaehlte Todo-Datei, Vault), Erinnerungs-Knoepfe, Einblenden-Aufgabe, Statusordner
    $oldKey = "HKCU:\Software\$OldSkinName"; $newKey = "HKCU:\Software\$SkinName"
    if (Test-Path $oldKey) {
        New-Item -Path $newKey -Force | Out-Null
        $p = Get-ItemProperty $oldKey
        foreach ($n in 'Vault', 'TodoDir', 'TodoFile') {
            if ($p.$n -and -not (Get-ItemProperty $newKey -Name $n -ErrorAction SilentlyContinue)) { Set-ItemProperty $newKey -Name $n -Value $p.$n }
        }
        Remove-Item $oldKey -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item 'HKCU:\Software\Classes\todo-rm' -Recurse -Force -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "$OldSkinName-Einblenden" -Confirm:$false -ErrorAction SilentlyContinue
    $oldState = Join-Path $env:LOCALAPPDATA $OldSkinName; $newState = Join-Path $env:LOCALAPPDATA $SkinName
    if (Test-Path -LiteralPath $oldState) {
        New-Item -ItemType Directory -Force $newState | Out-Null
        Get-ChildItem -LiteralPath $oldState -Force | ForEach-Object {
            if (-not (Test-Path -LiteralPath (Join-Path $newState $_.Name))) { Move-Item -LiteralPath $_.FullName -Destination $newState -ErrorAction SilentlyContinue }
        }
        Remove-Item -LiteralPath $oldState -Recurse -Force -ErrorAction SilentlyContinue
    }

    # alte Programmdateien entfernen: alter Skin-Ordner, bei neuem Programmordner auch der alte (Sicherungen ziehen mit)
    if ($OldApp -and ($OldApp.TrimEnd('\') -ne $App.TrimEnd('\')) -and ((Split-Path $OldApp.TrimEnd('\') -Leaf) -eq 'Obsidian Todo') -and (Test-Path -LiteralPath $OldApp)) {
        $oldBak = Join-Path $OldApp 'Sicherung'
        if (Test-Path -LiteralPath $oldBak) {
            New-Item -ItemType Directory -Force (Join-Path $App 'Sicherung') | Out-Null
            Get-ChildItem -LiteralPath $oldBak -Force | Move-Item -Destination (Join-Path $App 'Sicherung') -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $OldApp -Recurse -Force -ErrorAction SilentlyContinue
        Log "Umzug: alter Programmordner entfernt: $OldApp"
    } elseif ($oldSkin -like "$($App.TrimEnd('\'))\*") {
        Remove-Item -LiteralPath $oldSkin -Recurse -Force -ErrorAction SilentlyContinue
        Log "Umzug: alter Skin-Ordner entfernt: $oldSkin"
    }
    Log 'Umzug fertig'
}

try {
    switch ($Mode) {
        'detect' {
            $rm = Find-Rainmeter
            $lines = @()
            if ($rm) { $lines += "RainmeterExe=$($rm.Exe)"; $lines += "SkinPath=$($rm.Skins)" }
            $obs = Find-Obsidian
            if ($obs) { $lines += "ObsidianExe=$obs" }
            $cfg = Get-ObsidianConfig
            if ($cfg -and $cfg.vaults) {
                foreach ($v in $cfg.vaults.PSObject.Properties.Value) {
                    if ($v.path -and (Test-Path -LiteralPath $v.path)) {
                        $lines += "Vault=$($v.path)"
                        # vorhandene Todo.md im Vault suchen (Hauptordner oder eine Ebene tiefer)
                        $t = Get-ChildItem -LiteralPath $v.path -Filter 'Todo.md' -File -Depth 1 -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($t) { $lines += "TodoIn=$($v.path)|$($t.DirectoryName)" }
                    }
                }
            }
            # vorhandene Obsidian-Todo-Liste (alte Handversion oder fruehere Installation): welche Todo.md nutzt sie?
            if ($rm) {
                # auch unter dem alten Namen (bis 1.3.0: ObsidianTodo)
                $cands = foreach ($n in $SkinName, $OldSkinName) { $o = Join-Path $rm.Skins $n; Join-Path $o '@Resources\settings.inc'; Join-Path $o 'Todo.ini' }
                foreach ($f in $cands) {
                    if (-not (Test-Path -LiteralPath $f)) { continue }
                    $m = Select-String -LiteralPath $f -Encoding Unicode -Pattern '^\s*TodoFile\s*=\s*(.+\.md)\s*$' | Select-Object -First 1
                    if ($m) {
                        $tf = $m.Matches[0].Groups[1].Value.Trim()
                        if (Test-Path -LiteralPath $tf) { $lines += "OldTodo=$tf"; break }
                    }
                }
            }
            [IO.File]::WriteAllLines($Out, $lines, (New-Object Text.UTF8Encoding($false)))
        }

        'resolve' {
            # nur Adresse, Dateiname und Pruefsumme ermitteln - den Download macht der Installer mit Fortschrittsanzeige
            $a = Find-LatestAsset $Sources[$What][0] $Sources[$What][1]
            $sha = if ($a.digest -match '^sha256:([0-9a-f]{64})$') { $Matches[1] } else { '' }
            [IO.File]::WriteAllLines($Out, @("Url=$($a.browser_download_url)", "Name=$($a.name)", "Sha=$sha", "Size=$($a.size)"), (New-Object Text.UTF8Encoding($false)))
        }

        'install' {
            if ($What -eq 'rainmeter') {
                # Notbremse: laeuft schon ein Rainmeter (z. B. portabel), niemals ein zweites installieren -
                # das Rainmeter-Setup wuerde das laufende beenden und den Autostart umbiegen
                if (Get-CimInstance Win32_Process -Filter "Name='Rainmeter.exe'" -ErrorAction SilentlyContinue) {
                    throw 'Rainmeter laeuft bereits - keine zweite Installation'
                }
                $f = if ($File) { $File } else { Get-LatestAsset $Sources.rainmeter[0] $Sources.rainmeter[1] }
                Log "Installiere $f"
                # Rainmeter installiert nach Programme und braucht dafuer Adminrechte (eine UAC-Abfrage).
                # Das Rainmeter-Setup startet Rainmeter danach selbst - MIT Adminrechten. Befehle von normalen
                # Programmen (unser "Liste aktivieren") blockiert Windows dann. Darum in derselben Admin-Sitzung
                # wieder beenden; 'apply' startet es danach ganz normal.
                $wrap = Join-Path $env:TEMP 'TaskBoard-rainmeter-install.ps1'
                $fq = $f.Replace("'", "''")
                Set-Content -LiteralPath $wrap -Encoding UTF8 -Value @"
`$p = Start-Process '$fq' -ArgumentList '/S', '/AUTOSTARTUP=1' -Wait -PassThru
for (`$i = 0; `$i -lt 10; `$i++) { Start-Sleep -Seconds 1; Get-Process Rainmeter -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
exit `$p.ExitCode
"@
                $p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$wrap`"" -Verb RunAs -Wait -PassThru
                Remove-Item -LiteralPath $wrap -Force -ErrorAction SilentlyContinue
                if ($p.ExitCode -ne 0) { throw "Rainmeter-Setup Exitcode $($p.ExitCode)" }
            } elseif ($What -eq 'obsidian') {
                $f = if ($File) { $File } else { Get-LatestAsset $Sources.obsidian[0] $Sources.obsidian[1] }
                Log "Installiere $f"
                $p = Start-Process $f -ArgumentList '/S' -Wait -PassThru
                if ($p.ExitCode -ne 0) { throw "Obsidian-Setup Exitcode $($p.ExitCode)" }
            }
        }

        'apply' {
            $res = Join-Path $App "$SkinName\@Resources"
            try { Move-OldInstall } catch { Log "Umzug FEHLER: $_" }
            New-Item -ItemType Directory -Force $Vault, $TodoDir | Out-Null

            # neuer Vault: Obsidian erkennt den Ordner an .obsidian und kennt ihn ueber obsidian.json
            if ($NewVault) { New-Item -ItemType Directory -Force (Join-Path $Vault '.obsidian') | Out-Null }
            $cfgFile = Join-Path $env:APPDATA 'obsidian\obsidian.json'
            $cfg = Get-ObsidianConfig
            if (-not $cfg) { $cfg = [pscustomobject]@{ vaults = [pscustomobject]@{} } }
            if (-not $cfg.vaults) { $cfg | Add-Member vaults ([pscustomobject]@{}) -Force }
            $known = $cfg.vaults.PSObject.Properties.Value | Where-Object { $_.path -and ($_.path.TrimEnd('\') -eq $Vault.TrimEnd('\')) }
            if (-not $known) {
                $id = -join ((1..16) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
                $ts = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
                $cfg.vaults | Add-Member $id ([pscustomobject]@{ path = $Vault.TrimEnd('\'); ts = $ts })
                New-Item -ItemType Directory -Force (Split-Path $cfgFile) | Out-Null
                [IO.File]::WriteAllText($cfgFile, ($cfg | ConvertTo-Json -Depth 10 -Compress), (New-Object Text.UTF8Encoding($false)))
                Log "Vault registriert: $Vault"
            }

            # Todo-Dateien nur anlegen, wenn es sie noch nicht gibt
            $todo = Join-Path $TodoDir 'Todo.md'
            # im Einstellungen-Fenster gewaehlte Datei mit anderem Namen (choose-todo.ps1) behalten
            $chosen = (Get-ItemProperty 'HKCU:\Software\TaskBoard' -Name TodoFile -ErrorAction SilentlyContinue).TodoFile
            if ($chosen -and ((Split-Path $chosen) -eq $TodoDir.TrimEnd('\'))) { $todo = $chosen }
            $archive = Join-Path $TodoDir 'Todo-Archiv.md'
            $utf8 = New-Object Text.UTF8Encoding($false)
            if (-not (Test-Path -LiteralPath $todo)) { [IO.File]::WriteAllText($todo, "# Todo`n`n- [ ] Mein erster Punkt`n", $utf8) }
            if (-not (Test-Path -LiteralPath $archive)) { [IO.File]::WriteAllText($archive, "# Todo-Archiv`n", $utf8) }

            # schon eingerichtet (Update)? settings.inc gibt es seit 1.0.0
            $wasInstalled = Test-Path -LiteralPath (Join-Path $res 'settings.inc')
            # settings.inc: alle benutzerabhaengigen Werte fuer den Skin (UTF-16 LE wie alle Rainmeter-Dateien)
            $vaultName = Split-Path $Vault.TrimEnd('\') -Leaf
            $inc = "[Variables]`r`nTodoFile=$todo`r`nArchiveFile=$archive`r`nVaultName=$vaultName`r`nTodoUrl=$(Url $todo)`r`nArchiveUrl=$(Url $archive)`r`n"
            [IO.File]::WriteAllText((Join-Path $res 'settings.inc'), $inc, [Text.Encoding]::Unicode)
            # eigene Einstellungen (Breite) - nur anlegen, nie ueberschreiben
            $prefs = Join-Path $res 'prefs.inc'
            if (-not (Test-Path -LiteralPath $prefs)) { [IO.File]::WriteAllText($prefs, "[Variables]`r`n", [Text.Encoding]::Unicode) }
            # Update von vor 1.2.0: Liste blieb bisher auf dem Desktop -> dort lassen (nur Neuinstallationen starten
            # mit der Seitenleiste). Wer schon eine Anzeige gewaehlt hat, behaelt sie.
            if ($wasInstalled -and -not (Select-String -LiteralPath $prefs -Encoding Unicode -Pattern '^\s*Mode\s*=' -Quiet)) {
                Add-Content -LiteralPath $prefs -Value 'Mode=desktop' -Encoding Unicode
                Log "Update: Anzeige bleibt Desktop"
            }
            $colors = Join-Path $res 'colors.inc'
            if (-not (Test-Path -LiteralPath $colors)) { [IO.File]::WriteAllText($colors, "[Variables]`r`n", [Text.Encoding]::Unicode) }

            # Einblenden beim Anmelden und Entsperren: Aufgabe ruft Reveal() in der Liste auf
            # (Aufwachen aus dem Standby erkennt die Liste selbst an der Zeitluecke)
            try {
                $user = "$env:USERDOMAIN\$env:USERNAME"
                $act = New-ScheduledTaskAction -Execute $RainmeterExe -Argument '!CommandMeasure MeasureTodo "Reveal()" TaskBoard'
                $tLogon = New-ScheduledTaskTrigger -AtLogOn -User $user
                $tLogon.Delay = 'PT60S'
                $cls = Get-CimClass -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_TaskSessionStateChangeTrigger
                $tUnlock = New-CimInstance -CimClass $cls -ClientOnly -Property @{ StateChange = 8; UserId = $user; Delay = 'PT3S' }
                $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
                $pr = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
                Register-ScheduledTask -TaskName 'TaskBoard-Einblenden' -Action $act -Trigger @($tLogon, $tUnlock) -Settings $set -Principal $pr -Force | Out-Null
            } catch { Log "Aufgabe fuers Einblenden nicht angelegt: $_" }

            # Skin im Rainmeter-Skins-Ordner per Verzeichnisverknuepfung (Junction, keine Adminrechte noetig)
            $link = Join-Path $SkinPath $SkinName
            $target = Join-Path $App $SkinName
            if (Test-Path -LiteralPath $link) {
                $item = Get-Item -LiteralPath $link -Force
                if ($item.LinkType -ne 'Junction') {
                    # alte Handversion: erst anhalten (Tastenkuerzel-Programm, Fenster), dann sichern statt loeschen.
                    # Die Sicherung kommt in den Programmordner, damit Rainmeter sie nicht als eigenen Skin anzeigt.
                    if (Get-Process Rainmeter -ErrorAction SilentlyContinue) {
                        foreach ($c in "$SkinName\Formular", "$SkinName\Hilfe", $SkinName) { & $RainmeterExe '!DeactivateConfig' $c }
                        Start-Sleep -Seconds 2
                    }
                    Get-Process TaskBoardHotkey -ErrorAction SilentlyContinue | Stop-Process -Force
                    Start-Sleep -Milliseconds 500
                    $bakDir = Join-Path $App 'Sicherung'
                    New-Item -ItemType Directory -Force $bakDir | Out-Null
                    $bak = Join-Path $bakDir "$SkinName-alt-$(Get-Date -Format yyyyMMdd-HHmmss)"
                    try { Move-Item -LiteralPath $link -Destination $bak -ErrorAction Stop }
                    catch {
                        # anderes Laufwerk: kopieren und dann loeschen
                        Copy-Item -LiteralPath $link -Destination $bak -Recurse -ErrorAction Stop
                        Remove-Item -LiteralPath $link -Recurse -Force -ErrorAction Stop
                    }
                    Log "Alte Version gesichert: $bak"
                } else { cmd /c rmdir "`"$link`"" | Out-Null }
            }
            # verwaiste Verknuepfungen aus frueheren Installationen in anderen Skins-Ordnern entfernen
            foreach ($other in @((Join-Path ([Environment]::GetFolderPath('MyDocuments')) "Rainmeter\Skins\$SkinName"))) {
                if ($other -ne $link) {
                    $it = Get-Item -LiteralPath $other -Force -ErrorAction SilentlyContinue
                    if ($it -and $it.LinkType -eq 'Junction') { cmd /c rmdir "`"$other`"" | Out-Null; Log "Alte Verknuepfung entfernt: $other" }
                }
            }
            New-Item -ItemType Directory -Force $SkinPath | Out-Null
            cmd /c mklink /J "`"$link`"" "`"$target`"" | Out-Null

            # Knoepfe in den Erinnerungen (taskboard:done/<id>) -> toast-action.vbs
            $cmdKey = 'HKCU:\Software\Classes\taskboard'
            New-Item -Path "$cmdKey\shell\open\command" -Force | Out-Null
            Set-ItemProperty $cmdKey -Name '(default)' -Value 'URL:Task Board'
            Set-ItemProperty $cmdKey -Name 'URL Protocol' -Value ''
            Set-ItemProperty "$cmdKey\shell\open\command" -Name '(default)' -Value "wscript.exe `"$res\toast-action.vbs`" `"%1`" `"$RainmeterExe`""

            # ---------- Liste in Rainmeter aktivieren ----------
            # 1. In Rainmeters Einstellungsdatei als aktiv eintragen (Erstinstallation: mit Position oben rechts).
            #    Das wirkt auch dann, wenn Befehle an Rainmeter nicht ankommen (z. B. Rainmeter laeuft mit Adminrechten).
            # 2. Laeuft Rainmeter schon: zusaetzlich per Befehl aktivieren; sonst normal starten (laedt die Liste selbst).
            # 3. Pruefen, ob das Fenster der Liste wirklich da ist.
            $rmInfo = Find-Rainmeter
            $ini = if ($rmInfo -and $rmInfo.Ini) { $rmInfo.Ini } else { Join-Path $env:APPDATA 'Rainmeter\Rainmeter.ini' }
            $known = (Test-Path -LiteralPath $ini) -and (Select-String -LiteralPath $ini -Pattern "^\[$SkinName\]\s*$" -Quiet)
            $values = [ordered]@{ Active = '1' }
            if (-not $known) {
                Add-Type -AssemblyName System.Windows.Forms
                $wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
                # Bezugspunkt rechte obere Ecke: die Liste waechst bei groesserer Breite nach links
                $values.WindowX = "$($wa.Right - 24)"; $values.WindowY = "$($wa.Top + 60)"
                $values.AnchorX = '100%'; $values.AnchorY = '0'
                $values.AlwaysOnTop = '-2'; $values.Draggable = '1'; $values.SavePosition = '1'; $values.KeepOnScreen = '1'
            }
            # Rainmeter-Pfad merken (findet ein portables Rainmeter auch dann, wenn es beim naechsten Update nicht laeuft)
            New-Item -Path "HKCU:\Software\$SkinName" -Force | Out-Null
            Set-ItemProperty "HKCU:\Software\$SkinName" -Name RainmeterExe -Value $RainmeterExe
            $running = [bool](Get-Process Rainmeter -ErrorAction SilentlyContinue)
            if (-not $running) { Set-IniSection $ini $SkinName $values; Log "In Rainmeter.ini eingetragen: $ini" }

            if ($running) {
                & $RainmeterExe '!RefreshApp'
                Start-Sleep -Seconds 2
                & $RainmeterExe '!ActivateConfig' $SkinName 'Todo.ini'
                if (-not $known) {
                    Start-Sleep -Seconds 1
                    & $RainmeterExe '!ZPos' '-2' $SkinName
                    & $RainmeterExe '!Draggable' '1' $SkinName
                    & $RainmeterExe '!SetAnchor' '100%' '0' $SkinName
                    Start-Sleep -Milliseconds 500
                    & $RainmeterExe '!SetWindowPosition' $values.WindowX $values.WindowY '100%' '0' $SkinName
                }
            } else {
                Start-Rainmeter
            }

            # Pruefen: ist das Fenster der Liste da? Sonst Rainmeter normal neu starten (Eintrag in der .ini wirkt dann)
            $ok = $false
            for ($i = 0; $i -lt 20 -and -not $ok; $i++) { Start-Sleep -Milliseconds 500; $ok = Test-SkinWindow }
            if (-not $ok -and (Get-Process Rainmeter -ErrorAction SilentlyContinue)) {
                Log 'Liste nach dem Aktivieren nicht sichtbar - Rainmeter wird neu gestartet'
                Get-Process Rainmeter -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Set-IniSection $ini $SkinName $values
                Start-Rainmeter
                for ($i = 0; $i -lt 30 -and -not $ok; $i++) { Start-Sleep -Milliseconds 500; $ok = Test-SkinWindow }
            }
            # Rainmeter laeuft gar nicht (stuerzt manchmal ab, solange das Setup noch laeuft - 4.5.28, 07.11.2026):
            # nach dem Ende des Setups noch einmal starten
            if (-not $ok -and -not (Get-Process Rainmeter -ErrorAction SilentlyContinue)) {
                Start-RainmeterAfterSetup
                Log 'Rainmeter laeuft nicht - wird nach dem Setup gestartet'
            }
            Log "Liste sichtbar: $ok"
            if ($ok) { Remove-OldIniSections $ini }
            Log "Fertig: $todo"
        }

        'uninstall' {
            $rm = Find-Rainmeter
            if ($rm -and (Get-Process Rainmeter -ErrorAction SilentlyContinue)) {
                foreach ($c in "$SkinName\Formular", "$SkinName\Einstellungen", "$SkinName\Rand", $SkinName) { & $rm.Exe '!DeactivateConfig' $c }
                Start-Sleep -Seconds 1
            }
            Get-Process TaskBoardHotkey, TodoHotkey -ErrorAction SilentlyContinue | Stop-Process -Force
            if ($rm) {
                $link = Join-Path $rm.Skins $SkinName
                $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
                if ($item -and $item.LinkType -eq 'Junction') { cmd /c rmdir "`"$link`"" | Out-Null }
            }
            Remove-Item 'HKCU:\Software\Classes\taskboard' -Recurse -Force -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName 'TaskBoard-Einblenden' -Confirm:$false -ErrorAction SilentlyContinue
            Remove-Item (Join-Path $env:LOCALAPPDATA 'TaskBoard') -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    exit 0
} catch {
    Log "FEHLER: $_"
    exit 1
}
