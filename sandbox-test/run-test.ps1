# Laeuft IN der Windows-Sandbox: installiert TaskBoard-Setup.exe unbeaufsichtigt und prueft Seitenleiste,
# Einblenden, Einstellungen und Deinstallation. Ergebnisse in Desktop\out (test.log + Bilder einzelner Fenster).
$out = 'C:\Users\WDAGUtilityAccount\Desktop\out'
$in = 'C:\Users\WDAGUtilityAccount\Desktop\TaskBoard-Test'
$log = "$out\test.log"
function W($s) { Add-Content -Path $log -Value $s -Encoding UTF8 }

Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public class RW {
    public delegate bool E(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] public static extern bool EnumWindows(E e, IntPtr p);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    public struct RECT { public int L, T, R, B; }
}
"@
# Fenster eines Skins: sichtbar? wo? (Rainmeter benennt Skin-Fenster nach dem Pfad der .ini)
function Find($end) {
    $script:fw = $null
    [RW]::EnumWindows({ param($h, $p) $t = New-Object Text.StringBuilder 512; [void][RW]::GetWindowText($h, $t, 512)
        if ($t.ToString().EndsWith($end)) { $script:fw = $h }; return $true }, [IntPtr]::Zero) | Out-Null
    $script:fw
}
function Win($end) {
    $h = Find $end
    if (-not $h) { return 'fehlt' }
    $r = New-Object RW+RECT; [void][RW]::GetWindowRect($h, [ref]$r)
    "sichtbar=$([RW]::IsWindowVisible($h)) [$($r.L),$($r.T) - $($r.R),$($r.B)]"
}
function Snap($end, $name) {
    $h = Find $end
    if (-not $h) { return }
    $r = New-Object RW+RECT; [void][RW]::GetWindowRect($h, [ref]$r)
    $w = [Math]::Max(1, $r.R - $r.L); $ht = [Math]::Max(1, $r.B - $r.T)
    $b = New-Object Drawing.Bitmap $w, $ht; $g = [Drawing.Graphics]::FromImage($b); $g.Clear([Drawing.Color]::FromArgb(255, 70, 90, 120))
    $dc = $g.GetHdc(); [void][RW]::PrintWindow($h, $dc, 2); $g.ReleaseHdc($dc); $b.Save("$out\$name.png")
}
$LIST = '\TaskBoard\Todo.ini'; $RAND = '\TaskBoard\Rand\Rand.ini'; $SET = '\TaskBoard\Einstellungen\Einstellungen.ini'
$wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
W "Start: $(Get-Date -Format s)  Arbeitsbereich: $wa"

# ---------- Installation ----------
Copy-Item (Get-ChildItem "$in\TaskBoard-Setup*.exe" | Select-Object -First 1).FullName "$env:TEMP\setup.exe"
$p = Start-Process "$env:TEMP\setup.exe" -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=$out\inno.log" -PassThru
$p.WaitForExit()
W "Setup Exitcode: $($p.ExitCode)"
Start-Sleep -Seconds 12
$rm = (Get-Process Rainmeter | Select-Object -First 1).Path
W "Helper-Log:"; Get-Content "$env:TEMP\TaskBoard-Setup.log" -ErrorAction SilentlyContinue | ForEach-Object { W "   $_" }
W "Mauszeiger nach Installation: $([Windows.Forms.Cursor]::Position)"
W "Nach Installation: Liste $(Win $LIST) | Rand $(Win $RAND)"

# ---------- Seitenleiste: Maus an den rechten Rand ----------
[RW]::SetCursorPos($wa.Right - 1, $wa.Top + 300) | Out-Null
Start-Sleep -Milliseconds 120; [RW]::SetCursorPos($wa.Right - 1, $wa.Top + 310) | Out-Null
Start-Sleep -Milliseconds 120
W "Waehrend Hereinfahren: Liste $(Win $LIST)"
Start-Sleep -Milliseconds 600
W "Maus am Rand: Liste $(Win $LIST)"
Snap $LIST 'seitenleiste'
# Maus in die Liste, dann weg
[RW]::SetCursorPos($wa.Right - 200, $wa.Top + 120) | Out-Null; Start-Sleep -Seconds 2
W "Maus in der Liste (2 s): Liste $(Win $LIST)"
[RW]::SetCursorPos($wa.Left + 300, $wa.Top + 300) | Out-Null; Start-Sleep -Seconds 3
W "Maus weg (3 s): Liste $(Win $LIST)"
# versteckt -> wieder an den Rand: muss hereinfahren
[RW]::SetCursorPos($wa.Right - 1, $wa.Top + 500) | Out-Null; Start-Sleep -Milliseconds 100; [RW]::SetCursorPos($wa.Right - 1, $wa.Top + 520) | Out-Null
Start-Sleep -Milliseconds 800
W "Wieder an den Rand: Liste $(Win $LIST)"
Snap $LIST 'rand-erneut'
[RW]::SetCursorPos($wa.Left + 300, $wa.Top + 300) | Out-Null; Start-Sleep -Seconds 3
W "Wieder weg: Liste $(Win $LIST)"

# ---------- Einblenden (wie beim Anmelden) ----------
& $rm '!CommandMeasure' 'MeasureTodo' 'Reveal()' 'TaskBoard'; Start-Sleep -Seconds 2
W "Einblenden: Liste $(Win $LIST)"
Snap $LIST 'eingeblendet'
Start-Sleep -Seconds 12
W "Nach 14 s (1 Punkt = 10 s): Liste $(Win $LIST)"

# ---------- Einstellungen ----------
& $rm '!ActivateConfig' 'TaskBoard\Einstellungen' 'Einstellungen.ini'; Start-Sleep -Seconds 3
W "Einstellungen: $(Win $SET)"
Snap $SET 'einstellungen'

# ---------- Umschalten auf Desktop ----------
$prefs = "$env:USERPROFILE\Documents\Rainmeter\Skins\TaskBoard\@Resources\prefs.inc"
& $rm '!WriteKeyValue' 'Variables' 'Mode' 'desktop' $prefs; & $rm '!Refresh' 'TaskBoard'; Start-Sleep -Seconds 4
W "Desktop-Modus: Liste $(Win $LIST) | Rand $(Win $RAND)"
Snap $LIST 'desktop'
W "prefs.inc: $((Get-Content $prefs -Encoding Unicode) -join ' | ')"

# ---------- Deinstallation ----------
$un = Get-ChildItem "$env:LOCALAPPDATA\Programs\Task Board\unins*.exe" | Select-Object -First 1
$p = Start-Process $un.FullName -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES' -PassThru
$p.WaitForExit(); Start-Sleep -Seconds 5
W "Nach Deinstallation: Liste $(Win $LIST) | Rand $(Win $RAND) | Aufgabe=$([bool](Get-ScheduledTask -TaskName 'TaskBoard-Einblenden' -ErrorAction SilentlyContinue)) | Todo.md=$(Test-Path "$env:USERPROFILE\Documents\Obsidian Vault\Todo.md")"
Copy-Item "$env:APPDATA\Rainmeter\Rainmeter.log" "$out\Rainmeter.log" -ErrorAction SilentlyContinue
W "Ende: $(Get-Date -Format s)"
Set-Content "$out\fertig.txt" 'ok'
shutdown.exe /s /t 3
