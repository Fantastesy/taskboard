# Updates fuer Task Board (frueher Obsidian Todo).
# Automatisch: wird vom Skin beim Laden und alle 6 Stunden gestartet (MeasureUpdate), fragt aber hoechstens
# alle 6 Stunden bei GitHub nach. Gibt es ein neueres Release, wird TaskBoard-Setup-<version>.exe
# geladen, die SHA-256-Pruefsumme verglichen und das Setup unsichtbar ausgefuehrt.
# Einstellungen und die Todo-Liste bleiben dabei unveraendert.
#   -Check  von Hand (Einstellungen "Nach Updates suchen"): gibt "neu <version>", "aktuell <version>" oder "fehler" aus
#   -Now    von Hand ("Jetzt aktualisieren"): sofort installieren, ohne 6-Stunden-Pause und auch bei AutoUpdate=0
param([switch]$Check, [switch]$Now)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # sonst ist Invoke-WebRequest in PowerShell 5 extrem langsam
$res = $PSScriptRoot
$stateDir = Join-Path $env:LOCALAPPDATA 'ObsidianTodo'
$stamp = Join-Path $stateDir 'last-update-check.txt'
$log = Join-Path $stateDir 'update.log'
$manual = $Check -or $Now

function Log($msg) {
    try { Add-Content -LiteralPath $log -Value "$(Get-Date -Format s) $msg" -Encoding UTF8 } catch {}
}

try {
    # im Einstellungen-Fenster abschaltbar (prefs.inc: AutoUpdate=0); Standard: an
    $prefs = Join-Path $res 'prefs.inc'
    if (-not $manual -and (Test-Path -LiteralPath $prefs) -and (Select-String -LiteralPath $prefs -Encoding Unicode -Pattern '^\s*AutoUpdate\s*=\s*0\s*$' -Quiet)) { exit 0 }
    $repo = (Get-Content -LiteralPath (Join-Path $res 'repo.txt') -ErrorAction Stop | Select-Object -First 1).Trim()
    if ($repo -notmatch '^[\w.-]+/[\w.-]+$') {   # kein Repo eingetragen (Entwicklerversion)
        if ($Check) { Write-Output 'fehler' }
        exit 0
    }
    $current = [version](Get-Content -LiteralPath (Join-Path $res 'version.txt') | Select-Object -First 1).Trim()

    New-Item -ItemType Directory -Force $stateDir | Out-Null
    if (-not $manual) {
        if (Test-Path -LiteralPath $stamp) {
            $last = [datetime]::Parse((Get-Content -LiteralPath $stamp | Select-Object -First 1), [Globalization.CultureInfo]::InvariantCulture)
            if ((Get-Date) - $last -lt [timespan]::FromHours(6)) { exit 0 }
        }
        Set-Content -LiteralPath $stamp -Value (Get-Date).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'TaskBoard-Updater' } -UseBasicParsing
    $latest = [version]($rel.tag_name -replace '^v', '')
    if ($Check) {
        if ($latest -gt $current) { Write-Output "neu $latest" } else { Write-Output "aktuell $current" }
        exit 0
    }
    if ($latest -le $current) { exit 0 }

    # Name mit oder ohne Versionsnummer: TaskBoard-Setup-1.4.0.exe, bis 1.3.0 ObsidianTodo-Setup-1.3.0.exe
    $asset = $rel.assets | Where-Object { $_.name -match '^TaskBoard-Setup(-[\d.]+)?\.exe$' } | Select-Object -First 1
    if (-not $asset) { $asset = $rel.assets | Where-Object { $_.name -match '^ObsidianTodo-Setup(-[\d.]+)?\.exe$' } | Select-Object -First 1 }
    if (-not $asset) { Log "Release $($rel.tag_name) ohne Windows-Setup"; exit 0 }

    $setup = Join-Path $env:TEMP "TaskBoard-Setup-$latest.exe"
    Invoke-WebRequest $asset.browser_download_url -OutFile $setup -UseBasicParsing

    # GitHub liefert die Pruefsumme jeder Release-Datei mit ("sha256:...")
    if ($asset.digest -match '^sha256:([0-9a-f]{64})$') {
        $hash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLower()
        if ($hash -ne $Matches[1]) { Remove-Item -LiteralPath $setup -Force; Log "Pruefsumme falsch fuer $($rel.tag_name) - Update abgebrochen"; exit 1 }
    }

    if ($Now) { Log "Update $current -> $latest (von Hand)" } else { Log "Update $current -> $latest" }
    # das Setup startet Rainmeter am Ende neu bzw. frischt die Liste auf -> die neue Version ist sofort da
    Start-Process -FilePath $setup -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'
} catch {
    Log "Fehler: $_"
    if ($Check) { Write-Output 'fehler' }
}
