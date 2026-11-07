// TaskBoardHotkey: globales Tastenkuerzel fuer "Neuer Punkt" der Rainmeter-Todo-Liste.
// Wartet unsichtbar auf Win+Shift+T (falls belegt: Strg+Alt+T) und oeffnet dann das Formular.
// Wird von Todo.ini beim Laden gestartet, laeuft nur einmal (Mutex).
// Aufruf: TaskBoardHotkey.exe "<Pfad zu Rainmeter.exe>"
// Bauen: csc /target:winexe /out:TaskBoardHotkey.exe hotkey.cs
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

class TaskBoardHotkey : Form
{
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mod, uint vk);
    [DllImport("user32.dll")] static extern bool AllowSetForegroundWindow(int pid);
    public const uint MOD_ALT = 1, MOD_CONTROL = 2, MOD_SHIFT = 4, MOD_WIN = 8, MOD_NOREPEAT = 0x4000;
    const int WM_HOTKEY = 0x0312;

    readonly string rainmeter;
    public string Combo;

    // Kuerzel als Text: "ctrl+alt+shift+win+<Taste>" (Taste = Name aus System.Windows.Forms.Keys, z. B. T, Space, F5, D1).
    // Das Einstellungen-Fenster nimmt es mit "TaskBoardHotkey.exe --record" auf und schreibt "Hotkey=..." in prefs.inc.
    public static bool Parse(string key, out uint mod, out uint vk)
    {
        mod = MOD_NOREPEAT; vk = 0;
        foreach (var part in key.Split('+'))
        {
            switch (part.ToLowerInvariant())
            {
                case "ctrl": mod |= MOD_CONTROL; break;
                case "alt": mod |= MOD_ALT; break;
                case "shift": mod |= MOD_SHIFT; break;
                case "win": mod |= MOD_WIN; break;
                default:
                    Keys k;
                    if (!Enum.TryParse(part, true, out k)) return false;
                    vk = (uint)k; break;
            }
        }
        return vk != 0;
    }
    // Anzeige: "Strg+Alt+T", "Win+Shift+Leertaste", "Strg+1"
    public static string Display(string key)
    {
        var outp = new System.Collections.Generic.List<string>();
        foreach (var part in key.Split('+'))
        {
            switch (part.ToLowerInvariant())
            {
                case "ctrl": outp.Add("Strg"); break;
                case "alt": outp.Add("Alt"); break;
                case "shift": outp.Add("Shift"); break;
                case "win": outp.Add("Win"); break;
                case "space": outp.Add("Leertaste"); break;
                default:
                    var p = part;
                    if (p.Length == 2 && (p[0] == 'D' || p[0] == 'd') && char.IsDigit(p[1])) p = p.Substring(1);
                    else if (p.StartsWith("NumPad", StringComparison.OrdinalIgnoreCase)) p = "Num " + p.Substring(6);
                    outp.Add(p.Length == 1 ? p.ToUpperInvariant() : p);
                    break;
            }
        }
        return string.Join("+", outp);
    }

    bool TryRegister(string key)
    {
        uint mod, vk;
        return Parse(key, out mod, out vk) && RegisterHotKey(Handle, 1, mod, vk);
    }

    TaskBoardHotkey(string rainmeter, string wish)
    {
        this.rainmeter = rainmeter;
        ShowInTaskbar = false;
        CreateHandle();
        if (wish.Equals("aus", StringComparison.OrdinalIgnoreCase)) { Combo = "aus"; return; }
        // gewuenschtes Kuerzel; ohne Wunsch (oder belegt) wie bisher: Win+Shift+T, sonst Strg+Alt+T
        if (wish != "" && TryRegister(wish)) { Combo = Display(wish); return; }
        if (TryRegister("win+shift+t")) Combo = "Win+Shift+T";
        else if (TryRegister("ctrl+alt+t")) Combo = "Strg+Alt+T";
    }
    // "Hotkey=..." aus prefs.inc (UTF-16) lesen
    static string ReadWish(string dir)
    {
        try
        {
            foreach (var line in File.ReadAllLines(Path.Combine(dir, "prefs.inc")))
            {
                var l = line.Trim();
                if (l.StartsWith("Hotkey=", StringComparison.OrdinalIgnoreCase)) return l.Substring(7).Trim().Trim('"');
            }
        }
        catch { }
        return "";
    }

    // Fenster nie anzeigen
    protected override void SetVisibleCore(bool value) { base.SetVisibleCore(false); }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY)
        {
            // Rainmeter darf das Formular in den Vordergrund holen
            AllowSetForegroundWindow(-1);
            Process.Start(rainmeter, "!CommandMeasure MeasureTodo \"OpenDialog(0, 1)\" TaskBoard");
        }
        base.WndProc(ref m);
    }

    // ---------- Pruefung fuer den Installer: TaskBoardHotkey.exe --check "<Fensterende>" ----------
    // Exitcode 0, wenn ein sichtbares Fenster existiert, dessen Titel so endet (Rainmeter benennt
    // Skin-Fenster nach dem Pfad der .ini), sonst 1. So muss der Installer nichts zur Laufzeit uebersetzen.
    delegate bool EnumProc(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc e, IntPtr p);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);

    static int CheckWindow(string end)
    {
        bool found = false;
        EnumWindows(delegate (IntPtr h, IntPtr p) {
            var sb = new System.Text.StringBuilder(512);
            GetWindowText(h, sb, 512);
            if (IsWindowVisible(h) && sb.ToString().EndsWith(end, StringComparison.OrdinalIgnoreCase)) found = true;
            return true;
        }, IntPtr.Zero);
        return found ? 0 : 1;
    }

    // ---------- Eingabefeld nicht verlieren: TaskBoardHotkey.exe --commit ----------
    // Rainmeters Eingabefeld (InputText, Fenster "InputBox") verwirft den Text, wenn man woanders hinklickt.
    // Die Skins oeffnen es darum mit FocusDismiss=0 und starten dazu diesen Waechter: Klickt man ausserhalb
    // des Feldes (auch auf ein Rainmeter-Fenster - die holen sich beim Klick keinen Fokus!) oder wechselt
    // in ein anderes Programm, schreibt er commit.flag (die Lua-Skripte erkennen daran "rausgeklickt"
    // statt Enter) und drueckt fuer den Benutzer Enter - der Text wird also uebernommen.
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out PT p);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RC r);
    struct PT { public int X, Y; }
    struct RC { public int L, T, R, B; }
    static bool MouseDown() { return (GetAsyncKeyState(0x01) & 0x8000) != 0 || (GetAsyncKeyState(0x02) & 0x8000) != 0; }

    static IntPtr FindInputBox()
    {
        IntPtr box = IntPtr.Zero;
        EnumWindows(delegate (IntPtr h, IntPtr p) {
            var t = new System.Text.StringBuilder(64); GetWindowText(h, t, 64);
            var c = new System.Text.StringBuilder(128); GetClassName(h, c, 128);
            if (t.ToString() == "InputBox" && c.ToString().StartsWith("WindowsForms") && IsWindowVisible(h)) { box = h; return false; }
            return true;
        }, IntPtr.Zero);
        return box;
    }

    static int Commit(string dir)
    {
        // Ein Feld nach dem anderen: Wurde gerade eins uebernommen und gleich das naechste geoeffnet
        // (z. B. Name -> "+ Notiz"), laeuft der alte Waechter evtl. noch kurz. Darauf warten statt aufzugeben.
        using (var m = new Mutex(false, "TaskBoardCommit"))
        {
            bool got;
            try { got = m.WaitOne(3000); } catch (AbandonedMutexException) { got = true; }
            if (!got) return 0;
            int rc;
            try { rc = CommitWatch(dir); } finally { m.ReleaseMutex(); }
            // Feld mit Enter/Esc zu: Zeiger kann noch versteckt sein -> ein paar Sekunden weiter aufpassen
            // (Mutex schon frei, damit der Waechter fuers naechste Feld sofort starten kann)
            var sw = Stopwatch.StartNew();
            while (sw.ElapsedMilliseconds < 8000 && !cursorBack) { CursorGuard(); Thread.Sleep(15); }
            return rc;
        }
    }

    // "Zeiger waehrend der Eingabe ausblenden" (Windows-Mauseinstellung): Beim Tippen versteckt Windows
    // den Zeiger. Normale Fenster holen ihn bei der naechsten Mausbewegung per SetCursor zurueck,
    // Rainmeter-Fenster tun das erst, wenn die Maus ein anderes Fenster/Element erreicht. Darum hier:
    // Maus bewegt + Zeiger unsichtbar -> mit dem Fenster unter der Maus verbinden und Pfeil setzen.
    [DllImport("user32.dll")] static extern bool GetCursorInfo(ref CURSORINFO ci);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(PT p);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] static extern IntPtr SetCursor(IntPtr c);
    [DllImport("user32.dll")] static extern IntPtr LoadCursor(IntPtr inst, IntPtr name);
    struct CURSORINFO { public int cbSize; public int flags; public IntPtr hCursor; public PT pt; }
    static PT lastPos;
    static bool havePos, typedHidden, cursorBack;
    static void CursorGuard()
    {
        var ci = new CURSORINFO(); ci.cbSize = Marshal.SizeOf(typeof(CURSORINFO));
        if (!GetCursorInfo(ref ci)) return;
        bool showing = (ci.flags & 1) != 0;
        if (!showing) typedHidden = true;
        bool moved = havePos && (ci.pt.X != lastPos.X || ci.pt.Y != lastPos.Y);
        lastPos = ci.pt; havePos = true;
        if (!moved) return;
        if (showing) { if (typedHidden) cursorBack = true; return; }
        IntPtr w = WindowFromPoint(ci.pt);
        if (w == IntPtr.Zero) return;
        uint other = GetWindowThreadProcessId(w, IntPtr.Zero), me = GetCurrentThreadId();
        if (other == 0 || other == me) return;
        if (AttachThreadInput(me, other, true))
        {
            SetCursor(LoadCursor(IntPtr.Zero, (IntPtr)32512));   // IDC_ARROW
            AttachThreadInput(me, other, false);
        }
        cursorBack = true;
    }

    // Text im offenen Feld sofort uebernehmen (wie rausgeklickt): commit.flag + Enter
    static void SendCommit(string dir, IntPtr box)
    {
        try { File.WriteAllText(Path.Combine(dir, "commit.flag"), "1"); } catch { }
        IntPtr edit = FindWindowEx(box, IntPtr.Zero, null, null);
        IntPtr target = edit != IntPtr.Zero ? edit : box;
        PostMessage(target, 0x0100, (IntPtr)0x0D, (IntPtr)0x001C0001);   // WM_KEYDOWN Enter
        PostMessage(target, 0x0101, (IntPtr)0x0D, unchecked((IntPtr)(int)0xC01C0001));   // WM_KEYUP
    }

    // Notbremse aus form.lua: kein Waechter da, aber ein Feld offen -> jetzt uebernehmen
    static int CommitNow(string dir)
    {
        IntPtr box = FindInputBox();
        if (box == IntPtr.Zero) return 1;
        SendCommit(dir, box);
        return 0;
    }

    static int CommitWatch(string dir)
    {
        var sw = Stopwatch.StartNew();
        IntPtr box = IntPtr.Zero;
        while (box == IntPtr.Zero && sw.ElapsedMilliseconds < 5000) { box = FindInputBox(); if (box == IntPtr.Zero) Thread.Sleep(40); }
        if (box == IntPtr.Zero) return 1;
        bool hadFocus = false;
        bool wasDown = MouseDown();     // Taste noch vom Klick gedrueckt, der das Feld geoeffnet hat: erst loslassen
        // Lebenszeichen fuer die Lua-Seite: fehlt es bei offenem Feld, startet sie den Waechter neu
        // (Klicks auf Rainmeter-Fenster kommen bei offenem Feld gar nicht an - ohne Waechter haengt sonst alles)
        string alive = Path.Combine(dir, "watch.alive");
        long lastBeat = -1;
        while (IsWindow(box) && IsWindowVisible(box))
        {
            if (sw.ElapsedMilliseconds - lastBeat >= 500)
            {
                lastBeat = sw.ElapsedMilliseconds;
                try { File.WriteAllText(alive, ((long)(DateTime.UtcNow - new DateTime(1970, 1, 1)).TotalSeconds).ToString()); } catch { }
            }
            bool down = MouseDown();
            bool clickOutside = false;
            if (down && !wasDown)
            {
                PT p; RC r;
                GetCursorPos(out p); GetWindowRect(box, out r);
                clickOutside = p.X < r.L || p.X >= r.R || p.Y < r.T || p.Y >= r.B;
            }
            wasDown = down;
            bool fg = GetForegroundWindow() == box;
            if (fg) hadFocus = true;
            if (clickOutside || (hadFocus && !fg))
            {
                SendCommit(dir, box);
                return 0;
            }
            // waehrend getippt wird: versteckten Zeiger bei Mausbewegung zurueckholen (jedes Mal neu)
            CursorGuard(); cursorBack = false;
            Thread.Sleep(15);
        }
        return 0;
    }

    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length >= 2 && args[0] == "--check") return CheckWindow(args[1]);
        if (args.Length >= 1 && args[0].StartsWith("--google-", StringComparison.Ordinal)) return GoogleCli.Run(Path.GetDirectoryName(Application.ExecutablePath), args);
        if (args.Length >= 1 && args[0] == "--commit") return Commit(Path.GetDirectoryName(Application.ExecutablePath));
        if (args.Length >= 1 && args[0] == "--commit-now") return CommitNow(Path.GetDirectoryName(Application.ExecutablePath));
        if (args.Length >= 1 && args[0] == "--record") return Recorder.Record(Path.GetDirectoryName(Application.ExecutablePath), ReadWish(Path.GetDirectoryName(Application.ExecutablePath)));
        Run(args);
        return 0;
    }

    static void Run(string[] args)
    {
        bool first;
        using (new Mutex(true, "TaskBoardHotkey", out first))
        {
            if (!first) return;
            string dir = Path.GetDirectoryName(Application.ExecutablePath);
            // Pfad zu Rainmeter.exe kommt von Todo.ini (#PROGRAMPATH#), sonst portables Layout annehmen
            string rm = args.Length > 0 && File.Exists(args[0])
                ? args[0]
                : Path.GetFullPath(Path.Combine(dir, @"..\..\..\Rainmeter.exe"));
            var f = new TaskBoardHotkey(rm, ReadWish(dir));
            // gewaehltes Kuerzel fuer Hilfe/Einstellungen festhalten
            File.WriteAllText(Path.Combine(dir, "hotkey.txt"), f.Combo ?? "keins frei");
            // fuer das Einstellungen-Fenster (hebt das aktive Kuerzel hervor)
            File.WriteAllText(Path.Combine(dir, "hotkey.inc"), "[Variables]\r\nHotkeyNow=" + (f.Combo ?? "keins frei") + "\r\n", System.Text.Encoding.Unicode);
            // Google-Abgleich im Hintergrund (google.cs); er haelt den Prozess auch ohne Tastenkuerzel am Leben
            GoogleBackground.Start(dir);
            if ((f.Combo == null || f.Combo == "aus") && !GoogleBackground.Wanted(dir)) return;
            Application.Run(f);
        }
    }
}

// ---------- Neues Kuerzel aufnehmen: TaskBoardHotkey.exe --record ----------
// Kleines dunkles Fenster: "Neue Tastenkombination druecken". Schreibt Hotkey=... in prefs.inc (UTF-16) und endet mit 0;
// Esc oder Fenster verlassen = abbrechen (1). Prueft vorher, ob ein anderes Programm die Kombination schon belegt.
class Recorder : Form
{
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mod, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);

    readonly Label info = new Label();
    readonly Label hint = new Label();
    readonly string current;
    public string Result;

    Recorder(string current)
    {
        this.current = current;
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.CenterScreen;
        TopMost = true;
        ShowInTaskbar = false;
        KeyPreview = true;
        BackColor = System.Drawing.Color.FromArgb(22, 22, 30);
        Size = new System.Drawing.Size(460, 150);
        Padding = new Padding(1);
        foreach (var l in new[] { info, hint })
        {
            l.Dock = DockStyle.Top;
            l.TextAlign = System.Drawing.ContentAlignment.MiddleCenter;
            l.ForeColor = System.Drawing.Color.White;
            Controls.Add(l);
        }
        info.Font = new System.Drawing.Font("Segoe UI Semibold", 15f);
        info.Height = 80;
        info.Text = "Neue Tastenkombination drücken …";
        hint.Font = new System.Drawing.Font("Segoe UI", 10f);
        hint.ForeColor = System.Drawing.Color.FromArgb(175, 175, 188);
        hint.Height = 50;
        hint.Text = "z. B. Strg+Alt+T  ·  Esc = abbrechen";
        Controls.SetChildIndex(info, 1);
        Paint += (s, e) => e.Graphics.DrawRectangle(new System.Drawing.Pen(System.Drawing.Color.FromArgb(70, 70, 85)), 0, 0, Width - 1, Height - 1);
        Shown += (s, e) => { Activate(); SetForegroundWindow(Handle); };
        Deactivate += (s, e) => { if (Result == null) Close(); };
        KeyDown += OnKey;
    }

    static bool Down(Keys k) { return (GetAsyncKeyState((int)k) & 0x8000) != 0; }

    void OnKey(object s, KeyEventArgs e)
    {
        e.Handled = true; e.SuppressKeyPress = true;
        var k = e.KeyCode;
        if (k == Keys.Escape) { Close(); return; }
        bool win = Down(Keys.LWin) || Down(Keys.RWin);
        var mods = new System.Collections.Generic.List<string>();
        if (e.Control) mods.Add("ctrl");
        if (e.Alt) mods.Add("alt");
        if (e.Shift) mods.Add("shift");
        if (win) mods.Add("win");
        // nur Zusatztasten gedrueckt: Vorschau zeigen
        if (k == Keys.ControlKey || k == Keys.ShiftKey || k == Keys.Menu || k == Keys.LWin || k == Keys.RWin)
        {
            info.Text = mods.Count > 0 ? TaskBoardHotkey.Display(string.Join("+", mods)) + "+ …" : "Neue Tastenkombination drücken …";
            return;
        }
        bool fkey = k >= Keys.F1 && k <= Keys.F24;
        bool strong = e.Control || e.Alt || win;
        if (!strong && !fkey)
        {
            hint.Text = "Bitte mit Strg, Alt oder Win kombinieren  ·  Esc = abbrechen";
            return;
        }
        mods.Add(k.ToString());
        string key = string.Join("+", mods);
        uint mod, vk;
        // schon von einem anderen Programm belegt? (das eigene, laufende Kuerzel zaehlt nicht)
        if (!key.Equals(current, StringComparison.OrdinalIgnoreCase) && TaskBoardHotkey.Parse(key, out mod, out vk))
        {
            if (!RegisterHotKey(Handle, 7, mod, vk))
            {
                info.Text = TaskBoardHotkey.Display(key);
                hint.Text = "Diese Kombination ist schon belegt – bitte eine andere  ·  Esc = abbrechen";
                return;
            }
            UnregisterHotKey(Handle, 7);
        }
        Result = key;
        info.Text = TaskBoardHotkey.Display(key) + "  ✓";
        Refresh();
        System.Threading.Thread.Sleep(400);
        Close();
    }

    public static int Record(string dir, string current)
    {
        var f = new Recorder(current);
        Application.EnableVisualStyles();
        Application.Run(f);
        if (f.Result == null) return 1;
        // Hotkey=... in prefs.inc setzen (UTF-16 wie alle Rainmeter-Dateien)
        string prefs = Path.Combine(dir, "prefs.inc");
        var lines = new System.Collections.Generic.List<string>();
        if (File.Exists(prefs)) lines.AddRange(File.ReadAllLines(prefs));
        if (lines.Count == 0) lines.Add("[Variables]");
        bool done = false;
        for (int i = 0; i < lines.Count; i++)
            if (lines[i].Trim().StartsWith("Hotkey=", StringComparison.OrdinalIgnoreCase)) { lines[i] = "Hotkey=" + f.Result; done = true; }
        if (!done) lines.Add("Hotkey=" + f.Result);
        File.WriteAllLines(prefs, lines, System.Text.Encoding.Unicode);
        return 0;
    }
}