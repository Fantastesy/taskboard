# "Todo-Datei ändern" im Einstellungen-Fenster: Datei auswählen (vorhandene oder neue Todo.md),
# Vault ermitteln (naechster Ordner mit .obsidian darueber), settings.inc neu schreiben und die Wahl
# fuer Updates merken. Gibt "ok" aus, wenn etwas geaendert wurde.
Add-Type -AssemblyName System.Windows.Forms
$res = $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding($false)

# aktuelle Datei als Startpunkt
$cur = Select-String -LiteralPath (Join-Path $res 'settings.inc') -Encoding Unicode -Pattern '^TodoFile=(.+)$' -ErrorAction SilentlyContinue |
    Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value }

$owner = New-Object Windows.Forms.Form
$owner.TopMost = $true; $owner.ShowInTaskbar = $false
$dlg = New-Object Windows.Forms.SaveFileDialog
$dlg.Title = 'Todo-Datei wählen (vorhandene auswählen oder neuen Namen eingeben)'
$dlg.Filter = 'Markdown (*.md)|*.md'
$dlg.OverwritePrompt = $false
$dlg.FileName = 'Todo.md'
if ($cur) { $dlg.InitialDirectory = Split-Path $cur }
if ($dlg.ShowDialog($owner) -ne [Windows.Forms.DialogResult]::OK) { $owner.Dispose(); exit 0 }
$owner.Dispose()

$todo = $dlg.FileName
$dir = Split-Path $todo
$archive = Join-Path $dir 'Todo-Archiv.md'
# Vault: naechster Ordner nach oben, der .obsidian enthaelt (sonst der Ordner der Datei)
$vault = $dir
$p = $dir
while ($p) {
    if (Test-Path -LiteralPath (Join-Path $p '.obsidian')) { $vault = $p; break }
    $parent = Split-Path $p
    if ($parent -eq $p) { break }
    $p = $parent
}
if (-not (Test-Path -LiteralPath $todo)) { [IO.File]::WriteAllText($todo, "# Todo`n`n- [ ] Mein erster Eintrag`n", $utf8) }
if (-not (Test-Path -LiteralPath $archive)) { [IO.File]::WriteAllText($archive, "# Todo-Archiv`n", $utf8) }

function Url($s) { [Uri]::EscapeDataString($s) }
$inc = "[Variables]`r`nTodoFile=$todo`r`nArchiveFile=$archive`r`nVaultName=$(Split-Path $vault -Leaf)`r`nTodoUrl=$(Url $todo)`r`nArchiveUrl=$(Url $archive)`r`n"
[IO.File]::WriteAllText((Join-Path $res 'settings.inc'), $inc, [Text.Encoding]::Unicode)

# fuer kuenftige Updates merken (das Setup liest diese Werte)
New-Item -Path 'HKCU:\Software\TaskBoard' -Force | Out-Null
Set-ItemProperty 'HKCU:\Software\TaskBoard' -Name Vault -Value $vault
Set-ItemProperty 'HKCU:\Software\TaskBoard' -Name TodoDir -Value $dir
Set-ItemProperty 'HKCU:\Software\TaskBoard' -Name TodoFile -Value $todo
[Console]::Out.Write('ok')
