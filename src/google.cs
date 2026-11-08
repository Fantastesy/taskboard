// Google Tasks fuer Task Board: Anmeldung (OAuth mit Loopback + PKCE), Zugriff auf die Tasks-API und Abgleich
// mit der Todo.md. Gehoert zu TaskBoardHotkey.exe und wird zusammen mit hotkey.cs uebersetzt (build.ps1):
//   csc /target:winexe /r:System.Web.Extensions.dll /r:System.Security.dll hotkey.cs google.cs
// Nur C# 5 (csc aus .NET Framework 4): keine $-Strings, kein ?., keine =>-Member, kein "out var".
//
// So funktioniert der Abgleich (GoogleSync):
//   - Jede verbundene Zeile in der Todo.md traegt am Ende eine unsichtbare Kennung "%%tb:<Google-ID>%%"
//     (Obsidian-Kommentar). Die Liste blendet sie aus und behaelt sie beim Bearbeiten (wie die ➕/✅-Stempel).
//   - Zu jedem Eintrag merkt sich der Abgleich den letzten gemeinsamen Stand (google-sync.json). Daran sieht er,
//     welche Seite was geaendert hat. Aendern beide Seiten dasselbe Feld, gewinnt der PC.
//   - Was Google nicht kennt (Tags, Wiederholung, Uhrzeit, Erstellt-Datum), steht als letzte Zeile im Notizfeld:
//     "⟦tb #arbeit 🔁 täglich ⏰ 15:00 ➕ 2026-11-01⟧".
//   - Bei Google geloeschte Eintraege kommen ins Archiv (nichts geht verloren). Ist die Datei ploetzlich leer,
//     setzt der Abgleich aus. Aendert jemand die Datei waehrend des Abgleichs, wird nichts geschrieben und der
//     naechste Durchlauf holt es nach.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

// ---------- JSON (JavaScriptSerializer aus .NET 4) ----------
static class GJson
{
    static readonly JavaScriptSerializer js = new JavaScriptSerializer { MaxJsonLength = int.MaxValue, RecursionLimit = 64 };
    public static object Parse(string s) { return string.IsNullOrEmpty(s) ? null : js.DeserializeObject(s); }
    public static object TryParse(string s) { try { return Parse(s); } catch { return null; } }
    public static string Write(object o) { return js.Serialize(o); }
    public static Dictionary<string, object> Obj(object o) { return o as Dictionary<string, object>; }
    public static object Get(Dictionary<string, object> d, string k)
    {
        object v;
        return d != null && d.TryGetValue(k, out v) ? v : null;
    }
    public static string Str(Dictionary<string, object> d, string k)
    {
        object v = Get(d, k);
        return v == null ? null : Convert.ToString(v, CultureInfo.InvariantCulture);
    }
    public static bool Bool(Dictionary<string, object> d, string k) { return Get(d, k) is bool && (bool)Get(d, k); }
    public static object[] Arr(Dictionary<string, object> d, string k) { return Get(d, k) as object[]; }
    public static int Int(object o, int def)
    {
        try { return o == null ? def : Convert.ToInt32(o, CultureInfo.InvariantCulture); } catch { return def; }
    }
    // RFC 3339 -> UTC; unbekannt = DateTime.MinValue
    public static DateTime Date(string s)
    {
        DateTime d;
        if (s != null && DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out d)) return d;
        return DateTime.MinValue;
    }
}

// ---------- Ordner und Protokoll ----------
static class GLog
{
    public static string Dir;      // %LOCALAPPDATA%\TaskBoard (zum Testen: Umgebungsvariable TASKBOARD_GOOGLE_DIR)
    public static bool Echo;       // Kommandozeile: zusaetzlich auf die Konsole

    public static string StateDir()
    {
        string d = Environment.GetEnvironmentVariable("TASKBOARD_GOOGLE_DIR");
        if (string.IsNullOrEmpty(d)) d = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TaskBoard");
        Directory.CreateDirectory(d);
        return d;
    }

    // ohne Aufgabeninhalte und ohne Schluessel - nur Zahlen, Kennungen und Fehler
    public static void Write(string msg)
    {
        string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture) + " " + msg;
        if (Echo) { try { Console.WriteLine(line); } catch { } }
        if (Dir == null) return;
        try
        {
            string f = Path.Combine(Dir, "google.log");
            var fi = new FileInfo(f);
            if (fi.Exists && fi.Length > 512 * 1024) { File.Copy(f, f + ".1", true); File.Delete(f); }
            File.AppendAllText(f, line + "\r\n", new UTF8Encoding(false));
        }
        catch { }
    }
}

class GoogleException : Exception
{
    public readonly int Code;      // HTTP-Status, 0 = keine Verbindung
    public GoogleException(string msg, int code) : base(msg) { Code = code; }
}

// ---------- HTTP ----------
static class GHttp
{
    static GHttp()
    {
        try { ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; } catch { }   // TLS 1.2
        ServicePointManager.Expect100Continue = false;
    }

    public static int Send(string method, string url, string bearer, string contentType, string body, out string response)
    {
        var req = (HttpWebRequest)WebRequest.Create(url);
        req.Method = method;
        req.UserAgent = "TaskBoard";
        req.Accept = "application/json";
        req.Timeout = 30000;
        req.ReadWriteTimeout = 30000;
        if (bearer != null) req.Headers[HttpRequestHeader.Authorization] = "Bearer " + bearer;
        try
        {
            if (body != null)
            {
                byte[] b = Encoding.UTF8.GetBytes(body);
                req.ContentType = contentType;
                req.ContentLength = b.Length;
                using (Stream s = req.GetRequestStream()) s.Write(b, 0, b.Length);
            }
            else if (method != "GET" && method != "DELETE") req.ContentLength = 0;
            using (var resp = (HttpWebResponse)req.GetResponse())
            {
                response = ReadAll(resp);
                return (int)resp.StatusCode;
            }
        }
        catch (WebException e)
        {
            var r = e.Response as HttpWebResponse;
            if (r == null) { response = e.Message; return 0; }
            using (r) { response = ReadAll(r); return (int)r.StatusCode; }
        }
        catch (IOException e) { response = e.Message; return 0; }
    }

    static string ReadAll(HttpWebResponse r)
    {
        using (Stream s = r.GetResponseStream())
        using (var rd = new StreamReader(s, Encoding.UTF8)) return rd.ReadToEnd();
    }

    // "a=1&b=2" (Schluessel, Wert, Schluessel, Wert, ...)
    public static string Form(params string[] kv)
    {
        var sb = new StringBuilder();
        for (int i = 0; i + 1 < kv.Length; i += 2)
        {
            if (sb.Length > 0) sb.Append('&');
            sb.Append(Uri.EscapeDataString(kv[i])).Append('=').Append(Uri.EscapeDataString(kv[i + 1] ?? ""));
        }
        return sb.ToString();
    }

    // Fehlertext aus einer Google-Antwort
    public static string ErrText(string resp)
    {
        var d = GJson.Obj(GJson.TryParse(resp));
        var err = GJson.Get(d, "error");
        if (err is string) return (string)err + (GJson.Str(d, "error_description") != null ? " (" + GJson.Str(d, "error_description") + ")" : "");
        string m = GJson.Str(GJson.Obj(err), "message");
        if (m != null) return m;
        if (resp == null) return "";
        return resp.Length > 200 ? resp.Substring(0, 200) : resp;
    }
}

// ---------- Anmeldung ----------
// Zugang des Programms: google-client.json neben der exe (Google-Cloud-Projekt "Task Board", Typ Desktop-App;
// bei Desktop-Apps gilt das Client-Secret laut Google nicht als geheim). Der dauerhafte Schluessel des Nutzers
// (Refresh-Token) liegt nur auf diesem PC, mit DPAPI fuer das Windows-Konto verschluesselt: google-token.bin.
class GoogleAuth
{
    public const string Scope = "https://www.googleapis.com/auth/tasks";
    const string AuthUri = "https://accounts.google.com/o/oauth2/v2/auth";
    const string TokenUri = "https://oauth2.googleapis.com/token";
    const string RevokeUri = "https://oauth2.googleapis.com/revoke";
    static readonly byte[] Entropy = Encoding.UTF8.GetBytes("TaskBoard Google Tasks");

    readonly string clientId, clientSecret, dir;
    string access;
    DateTime accessUntil;
    public string LastError;
    public bool Revoked;        // Google hat den Zugang zurueckgezogen (abgemeldet / in den Kontoeinstellungen entfernt)
    public volatile bool CancelLogin;   // "Abbrechen" im Wartefenster

    GoogleAuth(string id, string secret, string dir) { clientId = id; clientSecret = secret; this.dir = dir; }

    public static GoogleAuth Load(string exeDir, string stateDir)
    {
        try
        {
            string f = Path.Combine(exeDir, "google-client.json");
            if (!File.Exists(f)) return null;
            var inst = GJson.Obj(GJson.Get(GJson.Obj(GJson.Parse(File.ReadAllText(f, Encoding.UTF8))), "installed"));
            string id = GJson.Str(inst, "client_id"), secret = GJson.Str(inst, "client_secret");
            if (string.IsNullOrEmpty(id) || string.IsNullOrEmpty(secret)) return null;
            return new GoogleAuth(id, secret, stateDir);
        }
        catch (Exception e) { GLog.Write("google-client.json unlesbar: " + e.Message); return null; }
    }

    string TokenFile { get { return Path.Combine(dir, "google-token.bin"); } }
    public bool Connected { get { return File.Exists(TokenFile); } }
#if DEV
    public string DevRefreshToken() { return LoadRefreshToken(); }   // nur Testfassung: Linux-Test mit demselben Testkonto
#endif

    string LoadRefreshToken()
    {
        try { return Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(TokenFile), Entropy, DataProtectionScope.CurrentUser)); }
        catch { return null; }
    }

    void SaveRefreshToken(string rt)
    {
        byte[] enc = ProtectedData.Protect(Encoding.UTF8.GetBytes(rt), Entropy, DataProtectionScope.CurrentUser);
        string tmp = TokenFile + ".tmp";
        File.WriteAllBytes(tmp, enc);
        if (File.Exists(TokenFile)) File.Delete(TokenFile);
        File.Move(tmp, TokenFile);
    }

    static string B64Url(byte[] b) { return Convert.ToBase64String(b).TrimEnd('=').Replace('+', '-').Replace('/', '_'); }
    static string RandomB64(int bytes)
    {
        var b = new byte[bytes];
        using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(b);
        return B64Url(b);
    }

    public string LoginUrl;      // Anmeldeseite der laufenden Anmeldung

    // Anmeldeseite im Browser oeffnen - auch noch einmal, wenn der Tab geschlossen wurde (Google nimmt dieselbe Adresse wieder an)
    public void OpenLoginPage()
    {
        string url = LoginUrl;
        if (url == null) return;
#if DEV
        if (Environment.GetEnvironmentVariable("TASKBOARD_NO_BROWSER") == "1") { GLog.Write("Anmeldeseite geoeffnet (Test)"); return; }
#endif
        Process.Start(url);
    }

    // Anmeldung im Browser: Google leitet nach der Zustimmung an http://127.0.0.1:<Port> zurueck, wo dieses
    // Programm kurz zuhoert. Wartet hoechstens timeoutSeconds.
    public bool Login(int timeoutSeconds)
    {
        LastError = null;
        string verifier = RandomB64(32), state = RandomB64(16), challenge;
        using (var sha = SHA256.Create()) challenge = B64Url(sha.ComputeHash(Encoding.ASCII.GetBytes(verifier)));
        var listener = new TcpListener(IPAddress.Loopback, 0);
        try
        {
            listener.Start();
            int port = ((IPEndPoint)listener.LocalEndpoint).Port;
            string redirect = "http://127.0.0.1:" + port;
            LoginUrl = AuthUri + "?" + GHttp.Form("client_id", clientId, "redirect_uri", redirect, "response_type", "code",
                "scope", Scope, "code_challenge", challenge, "code_challenge_method", "S256", "state", state,
                "access_type", "offline", "prompt", "consent");
            OpenLoginPage();
            DateTime until = DateTime.UtcNow.AddSeconds(timeoutSeconds);
            while (DateTime.UtcNow < until)
            {
                if (CancelLogin) { LastError = "abgebrochen"; return false; }
                if (!listener.Pending()) { Thread.Sleep(100); continue; }
                using (TcpClient client = listener.AcceptTcpClient())
                {
                    try
                    {
                        client.ReceiveTimeout = 5000;
                        client.SendTimeout = 5000;
                        NetworkStream ns = client.GetStream();
                        var q = Query(ReadRequestTarget(ns));
                        string code = Get(q, "code"), err = Get(q, "error");
                        if (code == null && err == null) { Respond(ns, 404, "Not found"); continue; }   // z. B. favicon.ico
                        if (err != null)
                        {
                            Respond(ns, 200, Page(false, "Die Anmeldung wurde abgebrochen. Du kannst dieses Fenster schließen."));
                            LastError = "abgebrochen (" + err + ")";
                            return false;
                        }
                        if (Get(q, "state") != state)
                        {
                            Respond(ns, 400, Page(false, "Ungültige Antwort von Google."));
                            LastError = "ungueltige Antwort (state)";
                            return false;
                        }
                        bool ok = Exchange(code, verifier, redirect);
                        Respond(ns, 200, ok ? Page(true, "Task Board ist jetzt mit Google verbunden. Du kannst dieses Fenster schließen.")
                                            : Page(false, "Die Anmeldung hat nicht geklappt: " + LastError));
                        return ok;
                    }
                    catch (IOException) { }          // Browser hat nur vorsorglich verbunden, ohne Anfrage
                    catch (SocketException) { }
                }
            }
            LastError = "Zeit abgelaufen";
            return false;
        }
        catch (Exception e) { LastError = e.Message; return false; }
        finally { LoginUrl = null; try { listener.Stop(); } catch { } }
    }

    static string ReadRequestTarget(NetworkStream ns)
    {
        var buf = new List<byte>();
        var one = new byte[1];
        while (buf.Count < 16384)
        {
            int n = ns.Read(one, 0, 1);
            if (n <= 0) break;
            buf.Add(one[0]);
            int c = buf.Count;
            if (c >= 4 && buf[c - 4] == 13 && buf[c - 3] == 10 && buf[c - 2] == 13 && buf[c - 1] == 10) break;
        }
        string head = Encoding.ASCII.GetString(buf.ToArray());
        int a = head.IndexOf(' ');
        int b = a < 0 ? -1 : head.IndexOf(' ', a + 1);
        return b < 0 ? null : head.Substring(a + 1, b - a - 1);
    }

    static Dictionary<string, string> Query(string target)
    {
        var d = new Dictionary<string, string>();
        int i = target == null ? -1 : target.IndexOf('?');
        if (i < 0) return d;
        foreach (string part in target.Substring(i + 1).Split('&'))
        {
            int e = part.IndexOf('=');
            if (e <= 0) continue;
            d[Uri.UnescapeDataString(part.Substring(0, e).Replace('+', ' '))] = Uri.UnescapeDataString(part.Substring(e + 1).Replace('+', ' '));
        }
        return d;
    }
    static string Get(Dictionary<string, string> d, string k) { string v; return d.TryGetValue(k, out v) ? v : null; }

    static void Respond(NetworkStream ns, int status, string html)
    {
        byte[] body = Encoding.UTF8.GetBytes(html);
        string head = "HTTP/1.1 " + status + (status == 200 ? " OK" : status == 404 ? " Not Found" : " Bad Request") + "\r\n" +
            "Content-Type: text/html; charset=utf-8\r\nContent-Length: " + body.Length + "\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n";
        byte[] h = Encoding.ASCII.GetBytes(head);
        ns.Write(h, 0, h.Length);
        ns.Write(body, 0, body.Length);
        ns.Flush();
    }

    static string Page(bool ok, string text)
    {
        return "<!doctype html><html lang=\"de\"><head><meta charset=\"utf-8\"><title>Task Board</title><style>" +
            "body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:#17151c;color:#ece9f1;font:18px/1.5 system-ui,'Segoe UI',sans-serif}" +
            "div{max-width:520px;padding:24px;text-align:center}h1{margin:0 0 12px;color:" + (ok ? "#f06292" : "#ff8a80") + "}</style></head><body><div><h1>" +
            (ok ? "Verbunden" : "Nicht verbunden") + "</h1><p>" + WebUtility.HtmlEncode(text) + "</p></div></body></html>";
    }

    bool Exchange(string code, string verifier, string redirect)
    {
        string resp;
        int st = GHttp.Send("POST", TokenUri, null, "application/x-www-form-urlencoded",
            GHttp.Form("code", code, "client_id", clientId, "client_secret", clientSecret, "redirect_uri", redirect,
                "grant_type", "authorization_code", "code_verifier", verifier), out resp);
        var d = GJson.Obj(GJson.TryParse(resp));
        if (st != 200 || d == null) { LastError = st == 0 ? "keine Verbindung zu Google" : "Google: " + GHttp.ErrText(resp); return false; }
        string scope = GJson.Str(d, "scope") ?? "";
        if (scope.IndexOf(Scope, StringComparison.Ordinal) < 0) { LastError = "der Zugriff auf Google Tasks wurde nicht erlaubt"; return false; }
        string rt = GJson.Str(d, "refresh_token");
        if (string.IsNullOrEmpty(rt)) { LastError = "Google hat keinen dauerhaften Schluessel geliefert"; return false; }
        SaveRefreshToken(rt);
        access = GJson.Str(d, "access_token");
        accessUntil = DateTime.UtcNow.AddSeconds(GJson.Int(GJson.Get(d, "expires_in"), 3600) - 120);
        Revoked = false;
        return true;
    }

    // gueltiger Zugriffsschluessel (1 Stunde gueltig), sonst null + LastError
    public string AccessToken()
    {
        if (access != null && DateTime.UtcNow < accessUntil) return access;
        string rt = LoadRefreshToken();
        if (rt == null) { LastError = "nicht angemeldet"; return null; }
        string resp;
        int st = GHttp.Send("POST", TokenUri, null, "application/x-www-form-urlencoded",
            GHttp.Form("client_id", clientId, "client_secret", clientSecret, "refresh_token", rt, "grant_type", "refresh_token"), out resp);
        var d = GJson.Obj(GJson.TryParse(resp));
        if (st == 200 && GJson.Str(d, "access_token") != null)
        {
            access = GJson.Str(d, "access_token");
            accessUntil = DateTime.UtcNow.AddSeconds(GJson.Int(GJson.Get(d, "expires_in"), 3600) - 120);
            return access;
        }
        if (GJson.Str(d, "error") == "invalid_grant")
        {
            // Zugang ungueltig (widerrufen oder abgelaufen): Schluessel weg, die Liste zeigt "Neu verbinden"
            Revoked = true;
            LastError = "abgemeldet";
            try { File.Delete(TokenFile); } catch { }
        }
        else LastError = st == 0 ? "offline" : "Google: " + GHttp.ErrText(resp);
        return null;
    }

    public void Invalidate() { access = null; }

    // Verbindung trennen: bei Google widerrufen und den Schluessel auf diesem PC loeschen
    public void Logout()
    {
        string rt = LoadRefreshToken();
        if (rt != null)
        {
            string resp;
            try { GHttp.Send("POST", RevokeUri, null, "application/x-www-form-urlencoded", GHttp.Form("token", rt), out resp); } catch { }
        }
        try { File.Delete(TokenFile); } catch { }
        access = null;
    }
}

// ---------- Aufgabe bei Google ----------
class RTask
{
    public string Id, Title = "", Notes = "", Due = "", Parent, Position = "";
    public bool Done, Hidden, Deleted;
    public DateTime Updated, Completed;   // UTC, MinValue = unbekannt

    public static RTask From(Dictionary<string, object> d)
    {
        if (d == null || GJson.Str(d, "id") == null) return null;
        var t = new RTask();
        t.Id = GJson.Str(d, "id");
        t.Title = GJson.Str(d, "title") ?? "";
        t.Notes = GJson.Str(d, "notes") ?? "";
        string due = GJson.Str(d, "due");
        t.Due = due != null && due.Length >= 10 ? due.Substring(0, 10) : "";
        t.Done = GJson.Str(d, "status") == "completed";
        t.Parent = GJson.Str(d, "parent");
        if (t.Parent == "") t.Parent = null;
        t.Position = GJson.Str(d, "position") ?? "";
        t.Hidden = GJson.Bool(d, "hidden");
        t.Deleted = GJson.Bool(d, "deleted");
        t.Updated = GJson.Date(GJson.Str(d, "updated"));
        t.Completed = GJson.Date(GJson.Str(d, "completed"));
        return t;
    }
}

// ---------- Tasks-API ----------
class TasksApi
{
    const string Base = "https://tasks.googleapis.com/tasks/v1/";
    readonly GoogleAuth auth;
    public int Calls;        // Anfragen (Google erlaubt dem ganzen Projekt 50.000 pro Tag)

    public TasksApi(GoogleAuth a) { auth = a; }
    static string E(string s) { return Uri.EscapeDataString(s); }

    public Dictionary<string, object> Call(string method, string path, Dictionary<string, object> body)
    {
        for (int attempt = 0; ; attempt++)
        {
            string tok = auth.AccessToken();
            if (tok == null) throw new GoogleException(auth.LastError ?? "nicht angemeldet", auth.Revoked ? 401 : 0);
            string resp;
            Calls++;
            int st = GHttp.Send(method, Base + path, tok, body != null ? "application/json; charset=utf-8" : null,
                body != null ? GJson.Write(body) : null, out resp);
            if (st >= 200 && st < 300) return GJson.Obj(GJson.TryParse(resp));
            if (st == 401 && attempt == 0) { auth.Invalidate(); continue; }
            if ((st == 429 || st >= 500) && attempt < 2) { Thread.Sleep(1500 * (attempt + 1)); continue; }
            throw new GoogleException(st == 0 ? "offline" : "Google " + st + ": " + GHttp.ErrText(resp), st);
        }
    }

    public List<Dictionary<string, object>> Lists()
    {
        var all = new List<Dictionary<string, object>>();
        string page = null;
        do
        {
            var d = Call("GET", "users/@me/lists?maxResults=100" + (page != null ? "&pageToken=" + E(page) : ""), null);
            var items = GJson.Arr(d, "items");
            if (items != null) foreach (object o in items) if (GJson.Obj(o) != null) all.Add(GJson.Obj(o));
            page = GJson.Str(d, "nextPageToken");
        } while (page != null);
        return all;
    }

    public Dictionary<string, object> NewList(string title)
    {
        return Call("POST", "users/@me/lists", new Dictionary<string, object> { { "title", title } });
    }

    // alle Aufgaben der Liste, auch erledigte; showHidden, weil Google in der eigenen App abgehakte Aufgaben ausblendet
    public List<RTask> Tasks(string list)
    {
        var all = new List<RTask>();
        string page = null;
        do
        {
            var d = Call("GET", "lists/" + E(list) + "/tasks?maxResults=100&showCompleted=true&showHidden=true" +
                (page != null ? "&pageToken=" + E(page) : ""), null);
            var items = GJson.Arr(d, "items");
            if (items != null)
                foreach (object o in items)
                {
                    RTask t = RTask.From(GJson.Obj(o));
                    if (t != null && !t.Deleted) all.Add(t);
                }
            page = GJson.Str(d, "nextPageToken");
        } while (page != null);
        return all;
    }

    static string Q(string parent, string previous)
    {
        var p = new List<string>();
        if (parent != null) p.Add("parent=" + E(parent));
        if (previous != null) p.Add("previous=" + E(previous));
        return p.Count > 0 ? "?" + string.Join("&", p) : "";
    }

    public RTask Insert(string list, Dictionary<string, object> body, string parent, string previous)
    {
        RTask t = RTask.From(Call("POST", "lists/" + E(list) + "/tasks" + Q(parent, previous), body));
        if (t == null) throw new GoogleException("Google hat die neue Aufgabe nicht bestaetigt", 0);
        return t;
    }

    public RTask Patch(string list, string id, Dictionary<string, object> body)
    {
        return RTask.From(Call("PATCH", "lists/" + E(list) + "/tasks/" + E(id), body));
    }

    public void Delete(string list, string id)
    {
        try { Call("DELETE", "lists/" + E(list) + "/tasks/" + E(id), null); }
        catch (GoogleException e) { if (e.Code != 404) throw; }    // schon weg (z. B. mit dem Hauptpunkt)
    }

    public RTask Move(string list, string id, string parent, string previous)
    {
        return RTask.From(Call("POST", "lists/" + E(list) + "/tasks/" + E(id) + "/move" + Q(parent, previous), null));
    }
}

// ---------- Textformat der Todo.md (wie src/todo.lua und linux/.../todo.js) ----------
static class Fmt
{
    public const string DueI = "\U0001F4C5", CreatedI = "➕", DoneI = "✅", CancelI = "❌", RepeatI = "\U0001F501", TimeI = "⏰";
    public const string TrailerOpen = "⟦tb", TrailerClose = "⟧";       // ⟦tb … ⟧
    // Zeichen, die ein neues Symbol einleiten (wie in todo.js: U+2000-U+2FFF und alles ausserhalb der BMP)
    const string SYM = @" -⿿\uD800-\uDFFF";
    const string DATE = @"\d{4}-\d{2}-\d{2}";
    static string Q(string s) { return Regex.Escape(s); }

    public static readonly Regex Check = new Regex(@"^(\s*)([-*+]) \[([ xX])\] ?(.*)$");
    static readonly Regex Marker = new Regex(@"\s*%%tb:([A-Za-z0-9_=-]+)%%");
    static readonly Regex DueRe = new Regex(Q(DueI) + @"\s*(" + DATE + ")");
    static readonly Regex DueStrip = new Regex(@"\s*" + Q(DueI) + @"\s*" + DATE);
    static readonly Regex RepStrip = new Regex(@"\s*" + Q(RepeatI) + "[^" + SYM + @"]*[^\s" + SYM + "]");
    static readonly Regex RuleRe = new Regex(Q(RepeatI) + @"\s*([^" + SYM + @"]*[^\s" + SYM + "])");
    static readonly Regex TimeRe = new Regex(Q(TimeI) + @"\s*(\d\d?):(\d\d)");
    static readonly Regex TimeStrip = new Regex(@"\s*" + Q(TimeI) + @"\s*\d\d?:\d\d");
    static readonly Regex CreatedRe = new Regex(Q(CreatedI) + @"\s*(" + DATE + ")");
    static readonly Regex CreatedStrip = new Regex(@"\s*" + Q(CreatedI) + @"\s*" + DATE);
    static readonly Regex DoneRe = new Regex(Q(DoneI) + @"\s*(" + DATE + ")");
    static readonly Regex DoneStrip = new Regex(@"\s*" + Q(DoneI) + @"\s*" + DATE);
    static readonly Regex TagRe = new Regex(@"(^|\s)#([^\s#.,;:!?()\[\]{}""'<>]+)");
    static readonly Regex Spaces = new Regex(@"\s{2,}");
    static readonly Regex Box = new Regex(@"\[[ xX]\]");
    static readonly string[] Months = { "Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember" };

    public static string Today() { return DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture); }

    public static int IndentOf(string line)
    {
        int n = 0;
        foreach (char ch in line) { if (ch == ' ') n++; else if (ch == '\t') n += 4; else break; }
        return n;
    }

    public static string IdOf(string text) { Match m = Marker.Match(text); return m.Success ? m.Groups[1].Value : null; }
    public static string StripMarker(string text) { return Marker.Replace(text, ""); }
    public static string WithMarker(string text, string id) { text = StripMarker(text); return id == null ? text : text + " %%tb:" + id + "%%"; }

    static bool HasNonDigit(string s) { foreach (char c in s) if (c < '0' || c > '9') return true; return false; }

    public static List<string> TagsOf(string text)
    {
        var outp = new List<string>();
        foreach (Match m in TagRe.Matches(text))
        {
            string n = m.Groups[2].Value;
            if (HasNonDigit(n) && !outp.Contains(n)) outp.Add(n);
        }
        return outp;
    }

    public static string StripTags(string text)
    {
        text = TagRe.Replace(text, delegate (Match m) { return HasNonDigit(m.Groups[2].Value) ? m.Groups[1].Value : m.Value; });
        return Spaces.Replace(text, " ");
    }

    static string StripStamps(string text) { return DoneStrip.Replace(CreatedStrip.Replace(text, ""), ""); }
    static string StripDue(string text) { return TimeStrip.Replace(RepStrip.Replace(DueStrip.Replace(text, ""), "", 1), ""); }

    // Titel wie im Formular der Liste: ohne Termin, Wiederholung, Uhrzeit, Stempel, Tags und Kennung
    public static string Title(string text) { return StripTags(StripDue(StripStamps(StripMarker(text)))).Trim(); }
    public static string DueOf(string text) { Match m = DueRe.Match(text); return m.Success ? m.Groups[1].Value : ""; }
    public static string DoneDateOf(string text) { Match m = DoneRe.Match(text); return m.Success ? m.Groups[1].Value : null; }

    // alles, was Google nicht kennt, in fester Reihenfolge: "#a #b 🔁 regel ⏰ 09:00 ➕ 2026-11-01"
    public static string MetaOf(string text)
    {
        text = StripMarker(text);
        var parts = new List<string>();
        var tags = TagsOf(text);
        if (tags.Count > 0) parts.Add("#" + string.Join(" #", tags));
        Match r = RuleRe.Match(text);
        if (r.Success) parts.Add(RepeatI + " " + r.Groups[1].Value.Trim());
        Match t = TimeRe.Match(text);
        if (t.Success) parts.Add(TimeI + " " + int.Parse(t.Groups[1].Value, CultureInfo.InvariantCulture).ToString("00", CultureInfo.InvariantCulture) + ":" + t.Groups[2].Value);
        Match c = CreatedRe.Match(text);
        if (c.Success) parts.Add(CreatedI + " " + c.Groups[1].Value);
        return string.Join(" ", parts);
    }

    // Zeilentext nach "- [ ] " in der Reihenfolge, in der die Liste selbst schreibt (Titel, Tags, 🔁, ⏰, 📅, ➕, ✅)
    public static string LineText(Proj p, string doneDate, string id)
    {
        var sb = new StringBuilder(p.Title);
        foreach (string tag in TagsOf(p.Meta)) sb.Append(" #").Append(tag);
        Match r = RuleRe.Match(p.Meta);
        if (r.Success) sb.Append(' ').Append(RepeatI).Append(' ').Append(r.Groups[1].Value.Trim());
        Match t = TimeRe.Match(p.Meta);
        if (t.Success) sb.Append(' ').Append(TimeI).Append(' ').Append(int.Parse(t.Groups[1].Value, CultureInfo.InvariantCulture).ToString("00", CultureInfo.InvariantCulture)).Append(':').Append(t.Groups[2].Value);
        if (p.Due != "") sb.Append(' ').Append(DueI).Append(' ').Append(p.Due);
        Match c = CreatedRe.Match(p.Meta);
        if (c.Success) sb.Append(' ').Append(CreatedI).Append(' ').Append(c.Groups[1].Value);
        if (p.Done && doneDate != null) sb.Append(' ').Append(DoneI).Append(' ').Append(doneDate);
        if (id != null) sb.Append(" %%tb:").Append(id).Append("%%");
        return sb.ToString();
    }

    // Titel einer Google-Aufgabe: Tags darin wandern in die Zusatzangaben
    public static string RemoteTitle(string title, out List<string> tags)
    {
        title = StripMarker(title.Replace('\r', ' ').Replace('\n', ' '));
        tags = TagsOf(title);
        return StripTags(title).Trim();
    }

    public static string Trailer(string meta) { return TrailerOpen + " " + meta + TrailerClose; }

    // Googles Grenzen: Titel 1024, Notizen 8192 Zeichen. Was laenger ist, bleibt in der Datei vollstaendig;
    // bei Google steht der Anfang, die Schlusszeile mit den Zusatzangaben bleibt immer erhalten.
    public const int MaxTitle = 1024, MaxNotes = 8192;
    public static string FitTitle(string t) { return t.Length > MaxTitle ? t.Substring(0, MaxTitle).Trim() : t; }
    public static List<string> FitNotes(List<string> notes, string meta)
    {
        int room = MaxNotes - (meta != "" ? Trailer(meta).Length + 1 : 0);
        string joined = string.Join("\n", notes);
        if (joined.Length <= room) return new List<string>(notes);
        var outp = new List<string>();
        foreach (string l in joined.Substring(0, Math.Max(0, room)).Split('\n')) { string t = l.Trim(); if (t != "") outp.Add(t); }
        return outp;
    }

    // Notizzeile in der Datei. Sieht der Text wie eine Checkbox aus ("[ ] Milch"), ohne "- " schreiben -
    // sonst waere er beim naechsten Lesen eine Unteraufgabe.
    public static string NoteLine(string indent, string note)
    {
        return indent + "    " + (Regex.IsMatch(note, @"^\[[ xX]\]") ? "" : "- ") + note;
    }

    // Notizfeld von Google: eigene Notizzeilen + Zusatzangaben aus der Schlusszeile
    public static void SplitNotes(string notes, out List<string> human, out string meta)
    {
        human = new List<string>();
        meta = "";
        foreach (string raw in (notes ?? "").Replace("\r\n", "\n").Split('\n'))
        {
            string l = raw.Trim();
            if (l.StartsWith(TrailerOpen, StringComparison.Ordinal) && l.EndsWith(TrailerClose, StringComparison.Ordinal))
                meta = MetaOf(l.Substring(TrailerOpen.Length, l.Length - TrailerOpen.Length - TrailerClose.Length));
            else if (l != "") human.Add(l);
        }
    }

    // Zeilen eines Punkts fuers Archiv (ohne Einrueckung und Kennungen); deleted: "- [-] … ❌ heute"
    public static List<string> ArchiveBlock(List<string> lines, string indent, bool deleted, string suffix)
    {
        var b = new List<string>();
        foreach (string raw in lines)
        {
            string l = raw.StartsWith(indent, StringComparison.Ordinal) ? raw.Substring(indent.Length) : raw.TrimStart();
            l = StripMarker(l);
            if (l.Trim() != "") b.Add(l);
        }
        if (b.Count == 0) return b;
        if (deleted) b[0] = Box.Replace(b[0], "[-]", 1) + " " + CancelI + " " + Today();
        else if (b[0].IndexOf(DoneI, StringComparison.Ordinal) < 0) b[0] += " " + DoneI + " " + Today();
        if (suffix != null) b[0] += suffix;
        return b;
    }

    // Bloecke unter der Ueberschrift des aktuellen Monats anhaengen (wie archive() in todo.lua)
    public static string AppendArchive(string content, List<List<string>> blocks)
    {
        string c = content;
        if (string.IsNullOrEmpty(c))
            c = "---\ntags: [todo, archiv]\n---\n\n# Todo-Archiv\n\nErledigte und gelöschte Punkte aus [[Todo]], mit allen Notizen und Unteraufgaben. " +
                "➕ = erstellt, ✅ = erledigt, ❌ = gelöscht (`- [-]`).\n";
        DateTime now = DateTime.Now;
        string heading = "## " + Months[now.Month - 1] + " " + now.Year;
        string last = null;
        foreach (Match m in Regex.Matches(c, @"\n(## [^\r\n]*)")) last = m.Groups[1].Value;
        var sb = new StringBuilder(Regex.Replace(c, @"[\r\n]*$", ""));
        if (last != heading) sb.Append("\n\n").Append(heading).Append('\n');
        foreach (var b in blocks) sb.Append('\n').Append(string.Join("\n", b));
        sb.Append('\n');
        return sb.ToString();
    }
}

// ---------- Inhalt eines Eintrags, so wie ihn beide Seiten vergleichen ----------
class Proj
{
    public string Title = "", Meta = "", Due = "";
    public bool Done;
    public List<string> Notes = new List<string>();

    public string NotesKey { get { return string.Join("\n", Notes); } }

    public bool Same(Proj o)
    {
        return o != null && Title == o.Title && Meta == o.Meta && Due == o.Due && Done == o.Done && NotesKey == o.NotesKey;
    }

    public Proj Clone()
    {
        return new Proj { Title = Title, Meta = Meta, Due = Due, Done = Done, Notes = new List<string>(Notes) };
    }

    public Dictionary<string, object> ToJson()
    {
        return new Dictionary<string, object> { { "t", Title }, { "m", Meta }, { "d", Due }, { "x", Done }, { "n", Notes.ToArray() } };
    }

    public static Proj FromJson(Dictionary<string, object> d)
    {
        var p = new Proj { Title = GJson.Str(d, "t") ?? "", Meta = GJson.Str(d, "m") ?? "", Due = GJson.Str(d, "d") ?? "", Done = GJson.Bool(d, "x") };
        var n = GJson.Arr(d, "n");
        if (n != null) foreach (object o in n) if (o != null) p.Notes.Add(Convert.ToString(o, CultureInfo.InvariantCulture));
        return p;
    }

    public static Proj OfLocal(string text, bool done, List<string> notes)
    {
        var p = new Proj { Title = Fmt.Title(text), Meta = Fmt.MetaOf(text), Due = Fmt.DueOf(text), Done = done };
        if (notes != null) foreach (string n in notes) { string t = n.Trim(); if (t != "") p.Notes.Add(t); }
        return p;
    }

    // Unteraufgaben haben in der Todo.md keine Notizen - ihre Google-Notizen bleiben unberuehrt
    public static Proj OfRemote(RTask r, bool sub)
    {
        List<string> human, titleTags;
        string meta;
        Fmt.SplitNotes(r.Notes, out human, out meta);
        var p = new Proj { Title = Fmt.RemoteTitle(r.Title, out titleTags), Due = r.Due, Done = r.Done };
        p.Meta = titleTags.Count > 0 ? Fmt.MetaOf("#" + string.Join(" #", titleTags) + " " + meta) : meta;
        if (!sub) p.Notes = human;
        return p;
    }

    // Was Google wegen seiner Laengengrenzen nur gekuerzt speichern kann, gilt als gleich - sonst wuerde die
    // gekuerzte Fassung beim naechsten Abgleich als "Aenderung bei Google" in die Datei zurueckkommen
    public static void Align(Proj remote, Proj full)
    {
        if (full == null) return;
        if (remote.Title != full.Title && remote.Title == Fmt.FitTitle(full.Title)) remote.Title = full.Title;
        if (remote.NotesKey != full.NotesKey && remote.NotesKey == string.Join("\n", Fmt.FitNotes(full.Notes, full.Meta)))
            remote.Notes = new List<string>(full.Notes);
    }

    static string Pick(string b, string l, string r, bool localWins)
    {
        if (l == r) return l;
        if (b != null) { if (l == b) return r; if (r == b) return l; }
        return localWins ? l : r;
    }

    // Drei-Wege-Abgleich je Feld: was nur eine Seite geaendert hat, wird uebernommen; bei Streit gewinnt localWins
    public static Proj Merge(Proj b, Proj l, Proj r, bool localWins)
    {
        var m = new Proj();
        m.Title = Pick(b == null ? null : b.Title, l.Title, r.Title, localWins);
        if (m.Title == "") m.Title = l.Title != "" ? l.Title : r.Title;      // leeren Titel nie uebernehmen
        m.Meta = Pick(b == null ? null : b.Meta, l.Meta, r.Meta, localWins);
        m.Due = Pick(b == null ? null : b.Due, l.Due, r.Due, localWins);
        m.Done = Pick(b == null ? null : (b.Done ? "1" : "0"), l.Done ? "1" : "0", r.Done ? "1" : "0", localWins) == "1";
        string nk = Pick(b == null ? null : b.NotesKey, l.NotesKey, r.NotesKey, localWins);
        m.Notes = new List<string>(nk == l.NotesKey ? l.Notes : nk == r.NotesKey ? r.Notes : b.Notes);
        return m;
    }
}

// ---------- Todo.md als Folge von Zeilen und Punkten ----------
class TItem
{
    public string Indent = "", Line = "", Text = "";   // Text = alles nach "] "
    public bool Done, IsSub;
    public string Id;            // Google-ID aus der Kennung
    public string DoneDate;      // ✅-Datum (fuer neu geschriebene Zeilen)
    public Proj P;               // aktueller Inhalt
    public bool Dirty;           // Zeile aus P neu schreiben
    public bool MarkerChanged;   // nur die Kennung anhaengen/aendern
    public TBlock Block;

    public static TItem FromMatch(string line, Match m, bool sub, TBlock block)
    {
        string text = m.Groups[4].Value;
        return new TItem
        {
            Indent = m.Groups[1].Value, Line = line, Text = text, Done = m.Groups[3].Value != " ", IsSub = sub, Block = block,
            Id = Fmt.IdOf(text), DoneDate = Fmt.DoneDateOf(text)
        };
    }

    public string Output()
    {
        if (Dirty) return Indent + "- [" + (P.Done ? "x" : " ") + "] " + Fmt.LineText(P, P.Done ? (DoneDate ?? Fmt.Today()) : null, Id);
        if (MarkerChanged) return Fmt.WithMarker(Line, Id);
        return Line;
    }
}

class TChild { public TItem Sub; public string Raw; }   // Unteraufgabe oder unveraenderte Notiz-/Leerzeile

class TBlock
{
    public TItem Head;
    public List<TChild> Children = new List<TChild>();
    public List<TItem> Subs = new List<TItem>();
    public List<string> Notes = new List<string>();
    public bool Dirty;            // Unteraufgaben und Notizen neu zusammensetzen

    public List<string> Lines()
    {
        var outp = new List<string> { Head.Output() };
        if (!Dirty) { foreach (TChild c in Children) outp.Add(c.Sub != null ? c.Sub.Output() : c.Raw); }
        else
        {
            foreach (TItem s in Subs) outp.Add(s.Output());
            foreach (string n in Head.P.Notes) outp.Add(Fmt.NoteLine(Head.Indent, n));
        }
        return outp;
    }
}

class TSeg { public string Raw; public TBlock Block; }

class TodoDoc
{
    public string Bom = "", Nl = "\n";
    public List<TSeg> Segs = new List<TSeg>();

    public List<TBlock> Blocks() { return Segs.Where(s => s.Block != null).Select(s => s.Block).ToList(); }

    // wie parse() in todo.js: eingerueckte Zeilen unter einem Punkt sind Unteraufgaben (Checkbox) oder Notizen
    public static TodoDoc Parse(string content)
    {
        var d = new TodoDoc();
        if (content.Length > 0 && content[0] == (char)0xFEFF) { d.Bom = ((char)0xFEFF).ToString(); content = content.Substring(1); }
        d.Nl = content.IndexOf("\r\n", StringComparison.Ordinal) >= 0 ? "\r\n" : "\n";
        TBlock cur = null;
        int curIndent = 0;
        var blanks = new List<string>();
        foreach (string line in content.Replace("\r\n", "\n").Split('\n'))
        {
            bool blank = line.Trim().Length == 0;
            Match m = Fmt.Check.Match(line);
            if (cur != null && !blank && Fmt.IndentOf(line) > curIndent)
            {
                foreach (string bl in blanks) cur.Children.Add(new TChild { Raw = bl });
                blanks.Clear();
                if (m.Success)
                {
                    TItem s = TItem.FromMatch(line, m, true, cur);
                    cur.Children.Add(new TChild { Sub = s });
                    cur.Subs.Add(s);
                }
                else
                {
                    cur.Children.Add(new TChild { Raw = line });
                    cur.Notes.Add(Regex.Replace(line.TrimStart(), @"^[-*+] ", ""));
                }
                continue;
            }
            if (cur != null && blank) { blanks.Add(line); continue; }
            foreach (string bl in blanks) d.Segs.Add(new TSeg { Raw = bl });
            blanks.Clear();
            if (cur != null) Finish(cur);
            if (m.Success)
            {
                cur = new TBlock();
                cur.Head = TItem.FromMatch(line, m, false, cur);
                curIndent = Fmt.IndentOf(line);
                d.Segs.Add(new TSeg { Block = cur });
            }
            else { cur = null; d.Segs.Add(new TSeg { Raw = line }); }
        }
        foreach (string bl in blanks) d.Segs.Add(new TSeg { Raw = bl });
        if (cur != null) Finish(cur);
        return d;
    }

    static void Finish(TBlock b)
    {
        b.Head.P = Proj.OfLocal(b.Head.Text, b.Head.Done, b.Notes);
        foreach (TItem s in b.Subs) s.P = Proj.OfLocal(s.Text, s.Done, null);
    }

    public string Serialize()
    {
        var lines = new List<string>();
        foreach (TSeg s in Segs) { if (s.Block != null) lines.AddRange(s.Block.Lines()); else lines.Add(s.Raw); }
        return Bom + string.Join(Nl, lines);
    }
}

// ---------- gemeinsamer Stand (google-sync.json) ----------
class SyncState
{
    public class Entry { public Proj P; public string Parent = ""; }

    public string List = "", Todo = "";
    public Dictionary<string, Entry> Items = new Dictionary<string, Entry>();
    public List<string> Order = new List<string>();                         // Reihenfolge der Punkte beim letzten Abgleich
    public Dictionary<string, string> Pending = new Dictionary<string, string>();   // neu angelegt, Kennung evtl. noch nicht in der Datei

    public static SyncState Load(string path)
    {
        var s = new SyncState();
        try
        {
            if (!File.Exists(path)) return s;
            var d = GJson.Obj(GJson.Parse(File.ReadAllText(path, Encoding.UTF8)));
            s.List = GJson.Str(d, "list") ?? "";
            s.Todo = GJson.Str(d, "todo") ?? "";
            var items = GJson.Obj(GJson.Get(d, "items"));
            if (items != null)
                foreach (var kv in items)
                {
                    var e = GJson.Obj(kv.Value);
                    if (e == null) continue;
                    s.Items[kv.Key] = new Entry { P = Proj.FromJson(GJson.Obj(GJson.Get(e, "p"))), Parent = GJson.Str(e, "par") ?? "" };
                }
            var order = GJson.Arr(d, "order");
            if (order != null) foreach (object o in order) s.Order.Add(Convert.ToString(o, CultureInfo.InvariantCulture));
            var pend = GJson.Obj(GJson.Get(d, "pending"));
            if (pend != null) foreach (var kv in pend) s.Pending[kv.Key] = Convert.ToString(kv.Value, CultureInfo.InvariantCulture);
        }
        catch (Exception e) { GLog.Write("google-sync.json unlesbar, Abgleich beginnt neu: " + e.Message); s = new SyncState(); }
        return s;
    }

    public void Save(string path)
    {
        var items = new Dictionary<string, object>();
        foreach (var kv in Items) items[kv.Key] = new Dictionary<string, object> { { "p", kv.Value.P.ToJson() }, { "par", kv.Value.Parent ?? "" } };
        var d = new Dictionary<string, object> {
            { "v", 1 }, { "list", List }, { "todo", Todo }, { "items", items }, { "order", Order.ToArray() },
            { "pending", Pending.ToDictionary(kv => kv.Key, kv => (object)kv.Value) } };
        GoogleSync.WriteText(path, GJson.Write(d));
    }
}

// ---------- ein Abgleich-Durchlauf ----------
class GoogleSync
{
    public string TodoPath, ArchivePath, ListId, StatePath;
    public bool CreateIfMissing;          // nur Google (ohne Obsidian): Datei selbst anlegen
    public TasksApi Api;

    TodoDoc doc;
    SyncState st;
    Dictionary<string, TItem> local;      // Google-ID -> Zeile in der Datei
    Dictionary<string, RTask> remote;     // Google-ID -> Aufgabe bei Google
    Dictionary<string, List<string>> rorder;   // Eltern-ID ("" = oben) -> Reihenfolge bei Google (mitgefuehrt)
    List<List<string>> archiveBlocks;
    readonly HashSet<string> reopened = new HashSet<string>();
    int nCreated, nPatched, nDeleted, nPulled, nAdded, nArchived, nMoved, nReordered;

    public string Summary
    {
        get
        {
            return "neu bei Google " + nCreated + ", geaendert bei Google " + nPatched + ", geloescht bei Google " + nDeleted +
                ", neu in der Datei " + nAdded + ", geaendert in der Datei " + nPulled + ", ins Archiv " + nArchived +
                ", verschoben bei Google " + nMoved + (nReordered > 0 ? ", Datei umsortiert" : "");
        }
    }

    public bool Run()
    {
        using (var mx = new Mutex(false, "TaskBoardGoogleSync"))
        {
            bool have;
            try { have = mx.WaitOne(TimeSpan.FromSeconds(60)); } catch (AbandonedMutexException) { have = true; }
            if (!have) { GLog.Write("Abgleich laeuft schon"); return false; }
            try { return RunLocked(); }
            catch
            {
                // Fehler mitten im Abgleich (z. B. Verbindung weg): schon bei Google angelegte Eintraege merken,
                // damit sie beim naechsten Mal wiedererkannt und nicht doppelt angelegt werden
                if (st != null && st.Pending.Count > 0) { try { SavePendingOnly(); } catch { } }
                throw;
            }
            finally { mx.ReleaseMutex(); }
        }
    }

    // ---------- Dateien ----------
    public static string ReadText(string path)
    {
        for (int i = 0; ; i++)
        {
            try { return File.Exists(path) ? new UTF8Encoding(false).GetString(File.ReadAllBytes(path)) : null; }
            catch (IOException) { if (i >= 5) throw; Thread.Sleep(200); }
        }
    }

    public static void WriteText(string path, string content)
    {
        byte[] bytes = new UTF8Encoding(false).GetBytes(content);
        string tmp = path + ".taskboard.tmp";
        File.WriteAllBytes(tmp, bytes);
        for (int i = 0; ; i++)
        {
            try
            {
                if (File.Exists(path)) File.Replace(tmp, path, null);
                else File.Move(tmp, path);
                return;
            }
            catch (IOException) { if (i >= 5) { File.WriteAllBytes(path, bytes); File.Delete(tmp); return; } Thread.Sleep(200); }
            catch (UnauthorizedAccessException) { File.WriteAllBytes(path, bytes); File.Delete(tmp); return; }
        }
    }

    static bool SamePath(string a, string b)
    {
        try { return string.Equals(Path.GetFullPath(a), Path.GetFullPath(b), StringComparison.OrdinalIgnoreCase); }
        catch { return false; }
    }

    // Datei lesen, bis sie zweimal gleich ist: die Liste schreibt nicht atomar, ein Lesen mittendrin saehe sie halb leer
    static string StableRead(string path)
    {
        string a = ReadText(path);
        for (int i = 0; i < 10; i++)
        {
            Thread.Sleep(120);
            string b = ReadText(path);
            if (b == a) return a;
            a = b;
        }
        return a;
    }

    public bool AllowMassChange;          // Schutz unten aufheben (nach 30 Minuten, siehe GoogleBackground)
    public string Suspicious;             // gesetzt, wenn der Schutz gegriffen hat: Beschreibung fuer die Statuszeile

    bool RunLocked()
    {
        st = null;
        string c0 = StableRead(TodoPath);
        if (c0 == null)
        {
            if (!CreateIfMissing) { GLog.Write("Todo-Datei fehlt - Abgleich ausgesetzt"); return false; }
            c0 = "";
        }
        DateTime fileTime = File.Exists(TodoPath) ? File.GetLastWriteTimeUtc(TodoPath) : DateTime.MinValue;
        doc = TodoDoc.Parse(c0.Length == 0 ? "# Todo\n" : c0);
        st = SyncState.Load(StatePath);
        if (st.List != ListId || !SamePath(st.Todo, TodoPath))
        {
            if (st.List != "") GLog.Write("andere Liste oder Datei - Abgleich beginnt neu");
            st = new SyncState { List = ListId, Todo = TodoPath };
        }
        archiveBlocks = new List<List<string>>();

        // Stand bei Google
        List<RTask> rl = Api.Tasks(ListId);
        remote = new Dictionary<string, RTask>();
        foreach (RTask r in rl) remote[r.Id] = r;
        rorder = new Dictionary<string, List<string>>();
        foreach (var g in rl.GroupBy(r => r.Parent ?? ""))
            rorder[g.Key] = g.OrderBy(r => r.Position, StringComparer.Ordinal).Select(r => r.Id).ToList();

        // Stand in der Datei
        local = new Dictionary<string, TItem>();
        int items = 0;
        foreach (TBlock b in doc.Blocks())
        {
            Register(b.Head); items++;
            foreach (TItem s in b.Subs) { Register(s); items++; }
        }
        // Schutz: Datei ohne Punkte, obwohl beim letzten Mal welche da waren -> lieber nichts tun
        if (items == 0 && st.Items.Count >= 3) { GLog.Write("Todo-Datei ohne Punkte - Abgleich ausgesetzt (Schutz)"); return false; }
        AdoptPending();
        AdoptSame();

        // Schutz: verschwinden viele offene Eintraege auf einmal (Datei zurueckgespielt, Google-Liste geleert), erst mal
        // nichts loeschen. Hat es seine Richtigkeit, wird es nach 30 Minuten uebernommen.
        int openKnown = st.Items.Count(e => !e.Value.P.Done);
        int goneLocal = st.Items.Count(e => !e.Value.P.Done && !local.ContainsKey(e.Key) && remote.ContainsKey(e.Key));
        int goneRemote = st.Items.Count(e => !e.Value.P.Done && local.ContainsKey(e.Key) && !remote.ContainsKey(e.Key));
        if (!AllowMassChange && (goneLocal >= 5 || goneRemote >= 5) && Math.Max(goneLocal, goneRemote) * 2 >= openKnown)
        {
            Suspicious = goneLocal >= goneRemote
                ? "In der Datei fehlen auf einmal " + goneLocal + " Einträge – bei Google wird vorerst nichts gelöscht."
                : "Bei Google fehlen auf einmal " + goneRemote + " Einträge – in der Datei wird vorerst nichts entfernt.";
            GLog.Write("Schutz: " + goneLocal + " Eintraege fehlen in der Datei, " + goneRemote + " bei Google (von " + openKnown + " offenen)");
            return false;
        }

        // 1. bekannte Eintraege: erst Punkte, dann Unteraufgaben
        foreach (string id in st.Items.Where(e => e.Value.Parent == "").Select(e => e.Key).ToList()) Known(id);
        foreach (string id in st.Items.Where(e => e.Value.Parent != "").Select(e => e.Key).ToList()) if (st.Items.ContainsKey(id)) Known(id);

        // 2. neu bei Google (erst Punkte, dann Unteraufgaben)
        // (remote.ContainsKey: in Schritt 1 bei Google geloeschte nicht gleich wieder hereinholen)
        foreach (RTask r in rl.Where(x => x.Parent == null).OrderBy(x => x.Position, StringComparer.Ordinal).ToList())
            if (!st.Items.ContainsKey(r.Id) && remote.ContainsKey(r.Id)) RemoteNew(remote[r.Id], fileTime);
        foreach (RTask r in rl.Where(x => x.Parent != null).OrderBy(x => x.Position, StringComparer.Ordinal).ToList())
            if (!st.Items.ContainsKey(r.Id) && remote.ContainsKey(r.Id)) RemoteNew(remote[r.Id], fileTime);

        // Kennungen, die es bei Google nicht (mehr) gibt (andere Liste, alter Stand): wie neu behandeln
        foreach (var kv in local.ToList())
            if (!remote.ContainsKey(kv.Key) && !st.Items.ContainsKey(kv.Key)) { kv.Value.Id = null; kv.Value.MarkerChanged = true; local.Remove(kv.Key); }

        // 3. neu in der Datei
        foreach (TBlock b in doc.Blocks())
        {
            if (b.Head.Id == null) CreateRemote(b.Head, null, b);
            foreach (TItem s in b.Subs) if (s.Id == null) CreateRemote(s, b.Head.Id, b);
        }

        // 4. Gliederung und Reihenfolge
        FixParents();
        SyncOrder();

        // 5. Datei schreiben - nur, wenn sie seit dem Lesen niemand geaendert hat
        string c1 = doc.Serialize();
        if (c0.Length == 0 && doc.Blocks().Count == 0) c1 = c0;
        if (c1 != c0)
        {
            string now = ReadText(TodoPath) ?? "";
            if (now != c0)
            {
                GLog.Write("Datei wurde waehrend des Abgleichs geaendert - naechster Durchlauf");
                SavePendingOnly();
                return false;
            }
            WriteText(TodoPath, c1);
        }
        if (archiveBlocks.Count > 0 && ArchivePath != null)
        {
            try { WriteText(ArchivePath, Fmt.AppendArchive(ReadText(ArchivePath), archiveBlocks)); }
            catch (Exception e) { GLog.Write("Archiv nicht geschrieben: " + e.Message); }
        }
        st.Pending.Clear();
        st.Order = doc.Blocks().Where(b => b.Head.Id != null && !b.Head.P.Done).Select(b => b.Head.Id).ToList();
        st.Save(StatePath);
        Written = c1;
        Changed = c1 != c0;
        return true;
    }

    public string Written;      // Inhalt der Datei nach dem Abgleich (der Dateiwaechter ignoriert eigenes Schreiben)
    public bool Changed;
    public int Activity { get { return nCreated + nPatched + nDeleted + nPulled + nAdded + nArchived + nMoved + nReordered; } }

    void Register(TItem it)
    {
        if (it.Id == null) return;
        if (local.ContainsKey(it.Id)) { it.Id = null; it.MarkerChanged = true; return; }   // kopierte Zeile: zweite ist neu
        local[it.Id] = it;
    }

    // nach einem abgebrochenen Durchlauf: neu angelegte Eintraege an ihrem Text wiedererkennen
    void AdoptPending()
    {
        if (st.Pending.Count == 0) return;
        foreach (TBlock b in doc.Blocks())
        {
            Adopt(b.Head);
            foreach (TItem s in b.Subs) Adopt(s);
        }
    }
    void Adopt(TItem it)
    {
        if (it.Id != null) return;
        string text = Fmt.StripMarker(it.Text);
        foreach (var kv in st.Pending)
        {
            if (kv.Value == text && remote.ContainsKey(kv.Key) && !local.ContainsKey(kv.Key))
            {
                it.Id = kv.Key;
                it.MarkerChanged = true;
                local[kv.Key] = it;
                return;
            }
        }
    }

    // Zeilen ohne gueltige Kennung an Titel, Datum und Status wiedererkennen, statt sie doppelt anzulegen
    // (Liste hin- und zurueckgewechselt, Datei ohne Kennungen mit einer schon gefuellten Liste verbunden)
    void AdoptSame()
    {
        var free = remote.Values.Where(r => !st.Items.ContainsKey(r.Id) && !local.ContainsKey(r.Id)).ToList();
        if (free.Count == 0) return;
        foreach (TBlock b in doc.Blocks())
        {
            AdoptSameOne(b.Head, "", free);
            if (b.Head.Id == null) continue;
            foreach (TItem s in b.Subs) AdoptSameOne(s, b.Head.Id, free);
        }
    }
    void AdoptSameOne(TItem it, string parent, List<RTask> free)
    {
        if (it.P.Title == "") return;
        if (it.Id != null && (remote.ContainsKey(it.Id) || st.Items.ContainsKey(it.Id))) return;
        foreach (RTask r in free)
        {
            if ((r.Parent ?? "") != parent) continue;
            Proj p = Proj.OfRemote(r, it.IsSub);
            if (p.Title != it.P.Title || p.Due != it.P.Due || p.Done != it.P.Done) continue;
            if (it.Id != null) local.Remove(it.Id);
            it.Id = r.Id;
            it.MarkerChanged = true;
            local[r.Id] = it;
            free.Remove(r);
            return;
        }
    }

    void SavePendingOnly()
    {
        var keep = SyncState.Load(StatePath);
        if (keep.List != ListId) keep = new SyncState { List = ListId, Todo = TodoPath };
        foreach (var kv in st.Pending) keep.Pending[kv.Key] = kv.Value;
        keep.Save(StatePath);
    }

    static string ParentOf(TItem it) { return it.IsSub ? it.Block.Head.Id ?? "" : ""; }

    void Known(string id)
    {
        SyncState.Entry e = st.Items[id];
        TItem L; local.TryGetValue(id, out L);
        RTask R; remote.TryGetValue(id, out R);
        if (L == null && R == null) { st.Items.Remove(id); return; }
        if (L == null)
        {
            // in der Datei weg (archiviert oder geloescht)
            bool sub = R.Parent != null;
            Proj pr = Proj.OfRemote(R, sub);
            Proj.Align(pr, e.P);
            if (!pr.Same(e.P))
            {
                // bei Google inzwischen geaendert -> nicht loeschen, sondern wieder in die Datei holen
                if (!sub) AddBlock(R, pr, true);
                else
                {
                    TItem parent;
                    if (!local.TryGetValue(R.Parent, out parent) || parent.IsSub) { DeleteRemote(id); return; }
                    AddSub(parent.Block, R, pr);
                }
                st.Items[id] = new SyncState.Entry { P = pr, Parent = sub ? R.Parent : "" };
                return;
            }
            DeleteRemote(id);
            return;
        }
        if (R == null)
        {
            // bei Google geloescht
            if (!L.P.Same(e.P) || (L.IsSub && L.Block.Head.Id == null))
            {
                // in der Datei inzwischen geaendert (oder Unteraufgabe eines solchen Punkts) -> bei Google neu anlegen (Schritt 3)
                local.Remove(id);
                L.Id = null;
                L.MarkerChanged = true;
                st.Items.Remove(id);
                return;
            }
            RemoveLocal(L);
            st.Items.Remove(id);
            return;
        }
        bool isSub = L.IsSub;
        Proj prr = Proj.OfRemote(R, isSub);
        Proj.Align(prr, L.P);
        Proj merged = Proj.Merge(e.P, L.P, prr, true);
        Apply(L, R, merged, prr);
        st.Items[id] = new SyncState.Entry { P = merged, Parent = ParentOf(L) };
    }

    void DeleteRemote(string id)
    {
        Api.Delete(ListId, id);
        // Google loescht die Unteraufgaben mit
        List<string> kids;
        if (rorder.TryGetValue(id, out kids))
            foreach (string kid in kids.ToList()) { remote.Remove(kid); st.Items.Remove(kid); }
        rorder.Remove(id);
        remote.Remove(id);
        foreach (var l in rorder.Values) l.Remove(id);
        st.Items.Remove(id);
        nDeleted++;
    }

    void Apply(TItem L, RTask R, Proj merged, Proj pr)
    {
        if (!merged.Same(L.P))
        {
            if (merged.Done && !L.P.Done)
                L.DoneDate = R.Completed != DateTime.MinValue ? R.Completed.ToLocalTime().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) : Fmt.Today();
            if (!L.IsSub && merged.NotesKey != L.P.NotesKey) L.Block.Dirty = true;
            L.P = merged;
            L.Dirty = true;
            nPulled++;
        }
        if (!merged.Same(pr))
        {
            RTask nr = Api.Patch(ListId, R.Id, Body(merged, R, L.IsSub, true));
            if (nr != null) remote[R.Id] = nr;
            nPatched++;
            // wieder geoeffnet: Google setzt die Aufgabe dabei selbst woanders hin -> in SyncOrder an ihren Platz zurueck
            if (pr.Done && !merged.Done)
            {
                foreach (var l in rorder.Values) l.Remove(R.Id);
                reopened.Add(R.Id);
            }
        }
    }

    // Inhalt fuer Google: Notizen + Schlusszeile mit den Zusatzangaben
    static Dictionary<string, object> Body(Proj p, RTask existing, bool sub, bool patch)
    {
        var d = new Dictionary<string, object>();
        d["title"] = Fmt.FitTitle(p.Title);
        var lines = new List<string>();
        if (sub) { if (existing != null) { List<string> h; string m; Fmt.SplitNotes(existing.Notes, out h, out m); lines.AddRange(Fmt.FitNotes(h, p.Meta)); } }
        else lines.AddRange(Fmt.FitNotes(p.Notes, p.Meta));
        if (p.Meta != "") lines.Add(Fmt.Trailer(p.Meta));
        string notes = string.Join("\n", lines);
        if (notes != "") d["notes"] = notes; else if (patch) d["notes"] = null;
        if (p.Due != "") d["due"] = p.Due + "T00:00:00.000Z"; else if (patch) d["due"] = null;
        d["status"] = p.Done ? "completed" : "needsAction";
        if (!p.Done && patch) d["completed"] = null;
        return d;
    }

    // ---------- Aenderungen an der Datei ----------
    void RemoveLocal(TItem L)
    {
        if (!L.IsSub)
        {
            TBlock b = L.Block;
            archiveBlocks.Add(Fmt.ArchiveBlock(b.Lines(), b.Head.Indent, !L.P.Done, null));
            doc.Segs.RemoveAll(s => s.Block == b);
            local.Remove(L.Id);
            foreach (TItem s in b.Subs) if (s.Id != null) local.Remove(s.Id);
        }
        else
        {
            TBlock b = L.Block;
            archiveBlocks.Add(Fmt.ArchiveBlock(new List<string> { L.Output() }, L.Indent, !L.P.Done,
                " · Unteraufgabe von „" + b.Head.P.Title + "“"));
            b.Subs.Remove(L);
            b.Children.RemoveAll(c => c.Sub == L);
            local.Remove(L.Id);
        }
        nArchived++;
    }

    void AddBlock(RTask r, Proj p, bool withChildren)
    {
        var head = new TItem { Id = r.Id, P = p, Dirty = true };
        if (p.Done) head.DoneDate = r.Completed != DateTime.MinValue ? r.Completed.ToLocalTime().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) : Fmt.Today();
        var b = new TBlock { Head = head, Dirty = true };
        head.Block = b;
        int at = InsertIndex(r.Id);
        if (at > 0 && doc.Segs[at - 1].Block == null && doc.Segs[at - 1].Raw.TrimStart().StartsWith("#", StringComparison.Ordinal))
            doc.Segs.Insert(at++, new TSeg { Raw = "" });     // Leerzeile unter einer Ueberschrift
        doc.Segs.Insert(at, new TSeg { Block = b });
        local[r.Id] = head;
        nAdded++;
        if (!withChildren) return;
        // wieder hereingeholter Punkt: seine Unteraufgaben gleich mit
        List<string> kids;
        if (rorder.TryGetValue(r.Id, out kids))
            foreach (string kid in kids)
            {
                RTask kr;
                if (!remote.TryGetValue(kid, out kr) || local.ContainsKey(kid)) continue;
                Proj kp = Proj.OfRemote(kr, true);
                AddSub(b, kr, kp);
                st.Items[kid] = new SyncState.Entry { P = kp, Parent = r.Id };
            }
    }

    // Platz fuer einen neuen Punkt: hinter seinem Vorgaenger bei Google, sonst vor dem ersten Punkt, sonst ans Ende
    int InsertIndex(string id)
    {
        List<string> ord;
        if (rorder.TryGetValue("", out ord))
        {
            int k = ord.IndexOf(id);
            for (int i = k - 1; i >= 0; i--)
            {
                TItem t;
                if (local.TryGetValue(ord[i], out t) && !t.IsSub)
                {
                    int at = doc.Segs.FindIndex(s => s.Block == t.Block);
                    if (at >= 0) return at + 1;
                }
            }
        }
        int first = doc.Segs.FindIndex(s => s.Block != null);
        if (first >= 0) return first;
        int end = doc.Segs.Count;
        while (end > 0 && doc.Segs[end - 1].Block == null && doc.Segs[end - 1].Raw.Trim() == "") end--;
        return end;
    }

    void AddSub(TBlock b, RTask r, Proj p)
    {
        var s = new TItem { Id = r.Id, P = p, Dirty = true, IsSub = true, Block = b, Indent = b.Head.Indent + "    " };
        if (p.Done) s.DoneDate = r.Completed != DateTime.MinValue ? r.Completed.ToLocalTime().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) : Fmt.Today();
        int at = 0;
        List<string> ord;
        if (rorder.TryGetValue(r.Parent ?? "", out ord))
        {
            int k = ord.IndexOf(r.Id);
            for (int i = k - 1; i >= 0; i--)
            {
                string prevId = ord[i];
                int j = b.Subs.FindIndex(x => x.Id == prevId);
                if (j >= 0) { at = j + 1; break; }
            }
        }
        b.Subs.Insert(at, s);
        b.Dirty = true;
        local[r.Id] = s;
        nAdded++;
    }

    void RemoteNew(RTask r, DateTime fileTime)
    {
        bool sub = r.Parent != null;
        TItem L;
        if (local.TryGetValue(r.Id, out L))
        {
            // Kennung steht schon in der Datei, aber es gibt keinen gemeinsamen Stand (anderer PC, neu eingerichtet):
            // je Feld zusammenfuehren, bei Streit gewinnt die neuere Seite
            Proj pr = Proj.OfRemote(r, L.IsSub);
            Proj.Align(pr, L.P);
            Proj merged = Proj.Merge(null, L.P, pr, r.Updated <= fileTime);
            Apply(L, r, merged, pr);
            st.Items[r.Id] = new SyncState.Entry { P = merged, Parent = ParentOf(L) };
            return;
        }
        if (r.Title.Trim() == "") return;              // leere Aufgabe (wird gerade in der Google-App getippt)
        Proj p = Proj.OfRemote(r, sub);
        if (!sub)
        {
            if (r.Done) return;                        // alte erledigte Aufgaben von Google nicht nachtragen
            AddBlock(r, p, false);
        }
        else
        {
            TItem parent;
            if (!local.TryGetValue(r.Parent, out parent) || parent.IsSub) return;
            AddSub(parent.Block, r, p);
        }
        st.Items[r.Id] = new SyncState.Entry { P = p, Parent = sub ? r.Parent : "" };
    }

    void CreateRemote(TItem it, string parentId, TBlock b)
    {
        if (it.IsSub && parentId == null) return;
        if (it.P.Title == "") return;      // leere Checkbox (wird gerade in Obsidian getippt)
        string prev = null;
        if (!it.IsSub)
        {
            foreach (TBlock x in doc.Blocks()) { if (x == b) break; if (x.Head.Id != null) prev = x.Head.Id; }
        }
        else
        {
            foreach (TItem x in b.Subs) { if (x == it) break; if (x.Id != null) prev = x.Id; }
        }
        RTask r = Api.Insert(ListId, Body(it.P, null, it.IsSub, false), parentId, prev);
        it.Id = r.Id;
        it.MarkerChanged = true;
        remote[r.Id] = r;
        local[r.Id] = it;
        InsertOrder(parentId ?? "", r.Id, prev);
        st.Items[r.Id] = new SyncState.Entry { P = it.P.Clone(), Parent = parentId ?? "" };
        st.Pending[r.Id] = Fmt.StripMarker(it.Text);
        // sofort merken: wird das Programm jetzt beendet (Update, Kuerzel neu), wird der Eintrag trotzdem wiedererkannt
        try { SavePendingOnly(); } catch { }
        nCreated++;
    }

    // ---------- Reihenfolge ----------
    List<string> OrderOf(string parent)
    {
        List<string> l;
        if (!rorder.TryGetValue(parent, out l)) { l = new List<string>(); rorder[parent] = l; }
        return l;
    }
    void InsertOrder(string parent, string id, string prev)
    {
        foreach (var l in rorder.Values) l.Remove(id);
        List<string> list = OrderOf(parent);
        int at = prev == null ? 0 : list.IndexOf(prev) + 1;
        list.Insert(at < 0 ? list.Count : at, id);
    }

    // false: Google lehnt die Verschiebung ab (z. B. Aufgabe mit Unteraufgaben unter eine andere) - dann bleibt es so
    bool MoveRemote(string id, string parent, string prev)
    {
        RTask nr;
        try { nr = Api.Move(ListId, id, parent == "" ? null : parent, prev); }
        catch (GoogleException e)
        {
            if (e.Code != 400) throw;
            GLog.Write("Verschieben abgelehnt: " + e.Message);
            return false;
        }
        if (nr != null) remote[id] = nr;
        InsertOrder(parent, id, prev);
        nMoved++;
        return true;
    }

    // Gliederung wie in der Datei (Unteraufgabe unter einem anderen Punkt, Punkt <-> Unteraufgabe)
    void FixParents()
    {
        foreach (TBlock b in doc.Blocks())
        {
            CheckParent(b.Head, "");
            if (b.Head.Id == null) continue;
            foreach (TItem s in b.Subs) CheckParent(s, b.Head.Id);
        }
    }
    void CheckParent(TItem it, string want)
    {
        RTask r;
        if (it.Id == null || !remote.TryGetValue(it.Id, out r)) return;
        if ((r.Parent ?? "") == want) return;
        if (!MoveRemote(it.Id, want, null)) return;
        SyncState.Entry e;
        if (st.Items.TryGetValue(it.Id, out e)) e.Parent = want;
    }

    static bool SeqEq(List<string> a, List<string> b) { return a.Count == b.Count && a.SequenceEqual(b); }

    void SyncOrder()
    {
        // wieder geoeffnete Aufgaben an ihren Platz in der Datei setzen (in Dateireihenfolge, der Vorgaenger steht dann schon)
        if (reopened.Count > 0)
        {
            string prevHead = null;
            foreach (TBlock b in doc.Blocks())
            {
                if (b.Head.Id == null) continue;
                if (reopened.Contains(b.Head.Id)) MoveRemote(b.Head.Id, "", prevHead);
                if (!b.Head.P.Done) prevHead = b.Head.Id;
                string prevSub = null;
                foreach (TItem s in b.Subs)
                {
                    if (s.Id == null) continue;
                    if (reopened.Contains(s.Id)) MoveRemote(s.Id, b.Head.Id, prevSub);
                    if (!s.P.Done) prevSub = s.Id;
                }
            }
        }
        // Punkte: wer hat seit dem letzten Abgleich umsortiert? Datei gewinnt, wenn beide.
        // Nur offene Eintraege: erledigte zeigt Google getrennt, ihre Position bedeutet nichts.
        List<string> localSeq = doc.Blocks().Where(b => b.Head.Id != null && !b.Head.P.Done).Select(b => b.Head.Id).ToList();
        var common = new HashSet<string>(localSeq.Where(id => OrderOf("").Contains(id)));
        List<string> l1 = localSeq.Where(common.Contains).ToList();
        List<string> r1 = OrderOf("").Where(common.Contains).ToList();
        if (!SeqEq(l1, r1))
        {
            var inBase = new HashSet<string>(st.Order.Where(common.Contains));
            List<string> b1 = st.Order.Where(common.Contains).ToList();
            bool localChanged = !SeqEq(l1.Where(inBase.Contains).ToList(), b1);
            bool remoteChanged = !SeqEq(r1.Where(inBase.Contains).ToList(), b1);
            if (localChanged || !remoteChanged) PushOrder("", l1, r1);
            else PullOrder(r1);
        }
        // Unteraufgaben: immer wie in der Datei
        foreach (TBlock b in doc.Blocks())
        {
            if (b.Head.Id == null) continue;
            List<string> have = OrderOf(b.Head.Id);
            List<string> want = b.Subs.Where(s => s.Id != null && !s.P.Done && have.Contains(s.Id)).Select(s => s.Id).ToList();
            List<string> cur = have.Where(want.Contains).ToList();
            if (!SeqEq(want, cur)) PushOrder(b.Head.Id, want, cur);
        }
    }

    // Google so umsortieren wie "want": die laengste schon richtig liegende Folge bleibt, der Rest wird verschoben
    void PushOrder(string parent, List<string> want, List<string> have)
    {
        int n = want.Count;
        var pos = want.Select(id => have.IndexOf(id)).ToArray();
        var len = new int[n];
        var prevIdx = new int[n];
        int best = -1;
        for (int i = 0; i < n; i++)
        {
            len[i] = 1; prevIdx[i] = -1;
            for (int j = 0; j < i; j++) if (pos[j] < pos[i] && len[j] + 1 > len[i]) { len[i] = len[j] + 1; prevIdx[i] = j; }
            if (best < 0 || len[i] > len[best]) best = i;
        }
        var keep = new HashSet<int>();
        for (int i = best; i >= 0; i = prevIdx[i]) keep.Add(i);
        for (int k = 0; k < n; k++)
        {
            if (keep.Contains(k)) continue;
            MoveRemote(want[k], parent, k > 0 ? want[k - 1] : null);
        }
    }

    // Datei so umsortieren wie bei Google (nur die verbundenen Punkte; ihre Plaetze in der Datei bleiben)
    void PullOrder(List<string> want)
    {
        var slots = new List<int>();
        var byId = new Dictionary<string, TBlock>();
        for (int i = 0; i < doc.Segs.Count; i++)
        {
            TBlock b = doc.Segs[i].Block;
            if (b != null && b.Head.Id != null && want.Contains(b.Head.Id)) { slots.Add(i); byId[b.Head.Id] = b; }
        }
        if (slots.Count != want.Count) return;
        for (int k = 0; k < slots.Count; k++) doc.Segs[slots[k]] = new TSeg { Block = byId[want[k]] };
        nReordered++;
    }
}

// ---------- Einstellungen der Liste (Dateien in @Resources, UTF-16 LE wie bei Rainmeter) ----------
static class SkinIni
{
    public static Dictionary<string, string> Read(string path)
    {
        var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            if (!File.Exists(path)) return d;
            foreach (string line in File.ReadAllLines(path))      // erkennt UTF-16 und UTF-8 am BOM
            {
                int i = line.IndexOf('=');
                if (i <= 0) continue;
                string k = line.Substring(0, i).Trim();
                if (k.StartsWith(";") || k.StartsWith("[")) continue;
                d[k] = line.Substring(i + 1).Trim().Trim('"');
            }
        }
        catch { }
        return d;
    }

    public static string Get(Dictionary<string, string> d, string k, string def)
    {
        string v;
        return d.TryGetValue(k, out v) ? v : def;
    }

    // Werte setzen (vorhandene Zeilen ersetzen, neue anhaengen)
    public static void Set(string path, Dictionary<string, string> values)
    {
        var lines = File.Exists(path) ? File.ReadAllLines(path).ToList() : new List<string> { "[Variables]" };
        foreach (var kv in values)
        {
            string key = kv.Key;
            int idx = lines.FindIndex(l => { int i = l.IndexOf('='); return i > 0 && string.Equals(l.Substring(0, i).Trim(), key, StringComparison.OrdinalIgnoreCase); });
            string nl = kv.Key + "=" + kv.Value;
            if (idx >= 0) lines[idx] = nl; else lines.Add(nl);
        }
        while (lines.Count > 0 && lines[lines.Count - 1].Trim() == "") lines.RemoveAt(lines.Count - 1);
        File.WriteAllText(path, string.Join("\r\n", lines) + "\r\n", Encoding.Unicode);
    }
}

// aktuelle Einstellung (prefs.inc: GoogleOn, GoogleList, GoogleListName, ObsidianOn; settings.inc: Dateien)
class GConf
{
    public string Res;
    public bool GoogleOn, ObsidianOn;
    public string ListId = "", ListName = "", TodoFile = "", ArchiveFile = "";

    public string Prefs { get { return Path.Combine(Res, "prefs.inc"); } }
    public string Settings { get { return Path.Combine(Res, "settings.inc"); } }

    public static GConf Load(string res)
    {
        var c = new GConf { Res = res };
        var p = SkinIni.Read(c.Prefs);
        var s = SkinIni.Read(c.Settings);
        c.GoogleOn = SkinIni.Get(p, "GoogleOn", "0") == "1";
        c.ObsidianOn = SkinIni.Get(p, "ObsidianOn", "1") != "0";
        c.ListId = SkinIni.Get(p, "GoogleList", "");
        c.ListName = SkinIni.Get(p, "GoogleListName", "");
        c.TodoFile = SkinIni.Get(s, "TodoFile", "");
        c.ArchiveFile = SkinIni.Get(s, "ArchiveFile", "");
        return c;
    }

    // "Nur Google": die Liste liest eine Kopie auf diesem PC
    public static string LocalTodo { get { return Path.Combine(GLog.StateDir(), "Todo.md"); } }
    public static string LocalArchive { get { return Path.Combine(GLog.StateDir(), "Todo-Archiv.md"); } }
    public static string StatePath { get { return Path.Combine(GLog.StateDir(), "google-sync.json"); } }

    // settings.inc fuer die Liste schreiben. Ohne Obsidian: Titel oeffnet Google Tasks im Browser.
    public void WriteSettings(string todo, string archive, string vaultName, bool obsidian)
    {
        string inc = "[Variables]\r\nTodoFile=" + todo + "\r\nArchiveFile=" + archive + "\r\nVaultName=" + vaultName + "\r\n";
        if (obsidian) inc += "TodoUrl=" + Uri.EscapeDataString(todo) + "\r\nArchiveUrl=" + Uri.EscapeDataString(archive) + "\r\n";
        else inc += "TodoUrl=\r\nArchiveUrl=\r\nTodoOpen=https://tasks.google.com/\r\nTodoOpenTip=Google Tasks öffnen\r\nArchiveOpen=" + archive + "\r\n";
        File.WriteAllText(Settings, inc, Encoding.Unicode);
    }
}

// Zustand fuers Einstellungen-Fenster: google-status.inc (GoogleState, GoogleStatus, GoogleConnected)
static class GStatus
{
    public static void Write(string res, string state, string text, bool connected)
    {
        try
        {
            string path = Path.Combine(res, "google-status.inc");
            string content = "[Variables]\r\nGoogleState=" + state + "\r\nGoogleStatus=" + text.Replace("\r", " ").Replace("\n", " ") +
                "\r\nGoogleConnected=" + (connected ? "1" : "0") + "\r\n";
            if (File.Exists(path) && File.ReadAllText(path) == content) return;
            File.WriteAllText(path, content, Encoding.Unicode);
            // dasselbe als UTF-8 fuer settings.lua (liest den Stand alle 2 Sekunden, ohne Neuladen)
            File.WriteAllText(Path.Combine(res, "google-status.txt"), state + "\n" + (connected ? "1" : "0") + "\n" + text, new UTF8Encoding(false));
        }
        catch { }
    }

    // den laufenden Abgleich (TaskBoardHotkey.exe im Hintergrund) sofort anstossen
    public static void Poke()
    {
        try
        {
            EventWaitHandle ev;
            if (EventWaitHandle.TryOpenExisting("TaskBoardGoogleSyncNow", out ev)) { ev.Set(); ev.Dispose(); }
        }
        catch { }
    }
}

// ---------- Abgleich im Hintergrund (laeuft im TaskBoardHotkey-Prozess) ----------
// Nach jeder Aenderung an der Todo.md (Liste, Obsidian, Claude) nach 1,5 s, sonst alle 2 Minuten.
// Google erlaubt dem ganzen Projekt 50.000 Anfragen pro Tag; ein ruhiger Durchlauf kostet eine.
class GoogleBackground
{
    readonly string res;
    readonly AutoResetEvent wake = new AutoResetEvent(false);
    FileSystemWatcher watcher;
    string watched;
    volatile string lastWritten;
    long lastEventTicks;             // Zeitpunkt der letzten fremden Aenderung an der Datei
    DateTime suspiciousSince = DateTime.MinValue;
    bool allowMass;

    GoogleBackground(string res) { this.res = res; }

    // ---------- Ein Vault auf zwei PCs (Nextcloud): nur einer gleicht mit Google ab ----------
    // Sonst aendern beide dieselbe Datei und dieselbe Liste gleichzeitig (Konflikte, doppelte Archiv-Eintraege).
    // ".taskboard-sync" neben der Todo.md: "<PC>\t<Unix-Zeit>", spaetestens alle 5 Minuten erneuert.
    // Der andere PC haelt sich zurueck, solange die Datei juenger als 20 Minuten ist; ist der PC aus, uebernimmt er.
    const int OwnerRenewSec = 300, OwnerStaleSec = 1200;

    // null = wir duerfen abgleichen, sonst der Name des anderen PCs
    static string OtherOwner(string todoFile)
    {
        try
        {
            string f = Path.Combine(Path.GetDirectoryName(todoFile), ".taskboard-sync");
            string me = Environment.MachineName;
            long now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            string[] p = File.Exists(f) ? File.ReadAllText(f, Encoding.UTF8).Trim().Split('\t') : new string[0];
            long ts = 0;
            bool valid = p.Length == 2 && long.TryParse(p[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out ts);
            if (valid && p[0] != me && now - ts < OwnerStaleSec) return p[0];
            if (!valid || p[0] != me || now - ts >= OwnerRenewSec)
                File.WriteAllText(f, me + "\t" + now.ToString(CultureInfo.InvariantCulture), new UTF8Encoding(false));
        }
        catch { }        // Ordner nicht beschreibbar o. Ae.: normal weiter abgleichen
        return null;
    }

    public static void Start(string res)
    {
        var b = new GoogleBackground(res);
        var t = new Thread(b.Loop) { IsBackground = true, Name = "TaskBoardGoogleSync" };
        t.Start();
    }

    void Loop()
    {
        try { GLog.Dir = GLog.StateDir(); } catch { }
        EventWaitHandle poke;
        try { poke = new EventWaitHandle(false, EventResetMode.AutoReset, "TaskBoardGoogleSyncNow"); }
        catch { poke = new EventWaitHandle(false, EventResetMode.AutoReset); }
        GoogleAuth auth = null;
        DateTime tokenStamp = DateTime.MinValue;
        int failures = 0;
        string lastOk = null;
        while (true)
        {
            int waitMs = 300000;
            try
            {
                GConf c = GConf.Load(res);
                string tokenFile = Path.Combine(GLog.StateDir(), "google-token.bin");
                DateTime stamp = File.Exists(tokenFile) ? File.GetLastWriteTimeUtc(tokenFile) : DateTime.MinValue;
                if (auth == null || stamp != tokenStamp) { auth = GoogleAuth.Load(res, GLog.StateDir()); tokenStamp = stamp; }
                bool connected = auth != null && auth.Connected;
                if (!c.GoogleOn || c.ListId == "" || auth == null)
                {
                    Watch(null);
                    GStatus.Write(res, "aus", connected ? "Abgleich mit Google ist ausgeschaltet." : "Nicht mit Google verbunden.", connected);
                }
                else if (!connected)
                {
                    Watch(null);
                    GStatus.Write(res, "abgemeldet", "Google-Zugang abgelaufen oder entfernt – bitte neu verbinden.", false);
                }
                else
                {
                    string other = c.ObsidianOn ? OtherOwner(c.TodoFile) : null;
                    if (other != null)
                    {
                        // der andere PC gleicht diesen Vault gerade ab; unsere Aenderungen kommen ueber die Nextcloud zu ihm
                        Watch(null);
                        GStatus.Write(res, "ok", "Verbunden · Abgleich läuft gerade auf „" + other + "“", true);
                        waitMs = 300000;
                    }
                    else
                    {
                        Watch(c.TodoFile);
                        var s = new GoogleSync
                        {
                            TodoPath = c.TodoFile, ArchivePath = c.ArchiveFile, ListId = c.ListId, StatePath = GConf.StatePath,
                            CreateIfMissing = !c.ObsidianOn, Api = new TasksApi(auth), AllowMassChange = allowMass
                        };
                        bool ok = s.Run();
                        if (ok)
                        {
                            lastWritten = s.Written;
                            failures = 0;
                            suspiciousSince = DateTime.MinValue;
                            allowMass = false;
                            lastOk = DateTime.Now.ToString("HH:mm", CultureInfo.InvariantCulture);
                            if (s.Activity > 0) GLog.Write("Abgleich: " + s.Summary + " (" + s.Api.Calls + " Anfragen)");
                            GStatus.Write(res, "ok", "Verbunden · Liste „" + c.ListName + "“ · zuletzt abgeglichen " + lastOk, true);
                            waitMs = 120000;
                        }
                        else if (s.Suspicious != null)
                        {
                            // Schutz gegriffen: 30 Minuten abwarten (Datei kommt zurueck?), danach uebernehmen
                            if (suspiciousSince == DateTime.MinValue) suspiciousSince = DateTime.UtcNow;
                            allowMass = (DateTime.UtcNow - suspiciousSince).TotalMinutes >= 30;
                            GStatus.Write(res, "fehler", s.Suspicious, true);
                            waitMs = 60000;
                        }
                        else { failures++; waitMs = 20000; }      // z. B. Datei gerade geaendert: bald nochmal
                    }
                }
            }
            catch (GoogleException e)
            {
                failures++;
                bool offline = e.Code == 0;
                if (!offline) GLog.Write("Abgleich: " + e.Message);
                string when = lastOk != null ? " (zuletzt abgeglichen " + lastOk + ")" : "";
                if (e.Code == 401) GStatus.Write(res, "abgemeldet", "Google-Zugang abgelaufen oder entfernt – bitte neu verbinden.", false);
                else if (e.Code == 404) GStatus.Write(res, "fehler", "Die Google-Liste gibt es nicht mehr – bitte eine Liste wählen.", true);
                else GStatus.Write(res, offline ? "offline" : "fehler", (offline ? "Keine Verbindung zu Google – wird nachgeholt" : "Fehler bei Google – wird nochmal versucht") + when, true);
                waitMs = Math.Min(600000, 30000 * (1 << Math.Min(failures, 4)));
            }
            catch (Exception e)
            {
                failures++;
                GLog.Write("Abgleich: " + e);
                GStatus.Write(res, "fehler", "Fehler beim Abgleich – wird nochmal versucht (Details: google.log).", true);
                waitMs = Math.Min(600000, 30000 * (1 << Math.Min(failures, 4)));
            }
            int woke = WaitHandle.WaitAny(new WaitHandle[] { wake, poke }, waitMs);
            if (woke == 0)
            {
                // Datei geaendert: warten, bis sie 3 Sekunden ruht (hoechstens 30) - wer in Obsidian tippt, dem soll
                // der Abgleich nicht mitten in die Zeile schreiben
                DateTime until = DateTime.UtcNow.AddSeconds(30);
                while (DateTime.UtcNow < until && (DateTime.UtcNow.Ticks - Interlocked.Read(ref lastEventTicks)) < TimeSpan.TicksPerSecond * 3)
                    Thread.Sleep(250);
            }
            else if (woke == 1) Thread.Sleep(300);
            wake.Reset();
        }
    }

    void Watch(string file)
    {
        if (file == watched) return;
        if (watcher != null) { watcher.EnableRaisingEvents = false; watcher.Dispose(); watcher = null; }
        watched = null;
        if (string.IsNullOrEmpty(file)) return;
        try
        {
            string dir = Path.GetDirectoryName(file);
            if (!Directory.Exists(dir)) return;              // naechster Durchlauf versucht es wieder (z. B. Laufwerk noch nicht da)
            watcher = new FileSystemWatcher(dir, Path.GetFileName(file)) { NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.Size };
            FileSystemEventHandler h = delegate { OnFileEvent(); };
            watcher.Changed += h;
            watcher.Created += h;
            watcher.Renamed += delegate { OnFileEvent(); };
            watcher.EnableRaisingEvents = true;
            watched = file;
        }
        catch (Exception e) { GLog.Write("Dateiwaechter: " + e.Message); }
    }

    void OnFileEvent()
    {
        try
        {
            string now = GoogleSync.ReadText(watched);
            if (now != null && now == lastWritten) return;       // eigenes Schreiben
        }
        catch { }
        Interlocked.Exchange(ref lastEventTicks, DateTime.UtcNow.Ticks);
        wake.Set();
    }

    // laeuft der Abgleich ueberhaupt? (fuer TaskBoardHotkey: Prozess am Leben halten)
    public static bool Wanted(string res) { return GConf.Load(res).GoogleOn; }
}

// ---------- Fenster dieses Programms ----------
// Rainmeter startet es versteckt (RunCommand State=Hide); dann verschluckt Windows das erste Anzeigen.
class TbForm : Form
{
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);

    protected TbForm()
    {
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false; MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        TopMost = true;
        BackColor = System.Drawing.Color.FromArgb(28, 26, 34);
        ForeColor = System.Drawing.Color.FromArgb(236, 233, 241);
        Font = new System.Drawing.Font("Segoe UI", 11f);
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        ShowWindow(Handle, 5);      // SW_SHOW
        SetForegroundWindow(Handle);
    }

    protected Button MakeButton(string text, int left, int top, int width, bool primary)
    {
        var b = new Button { Text = text, Width = width, Height = 36, Left = left, Top = top, FlatStyle = FlatStyle.Flat,
            BackColor = primary ? System.Drawing.Color.FromArgb(220, 80, 165) : System.Drawing.Color.FromArgb(45, 42, 54),
            ForeColor = primary ? System.Drawing.Color.White : ForeColor };
        if (primary) b.FlatAppearance.BorderSize = 0;
        else b.FlatAppearance.BorderColor = System.Drawing.Color.FromArgb(80, 76, 92);
        return b;
    }
}

// Warten auf die Anmeldung im Browser. "Seite nochmal öffnen", falls der Tab zu ist; "Abbrechen", damit niemand festhaengt.
class LoginWait : TbForm
{
    const string AgainEvent = "TaskBoardGoogleLoginAgain";
    readonly GoogleAuth auth;
    readonly Label info;
    bool ok;

    // zweiter Klick auf "Google Tasks" im Zahnrad: die wartende Anmeldung oeffnet ihre Seite nochmal
    public static void SignalAgain()
    {
        try
        {
            EventWaitHandle ev;
            if (EventWaitHandle.TryOpenExisting(AgainEvent, out ev)) { ev.Set(); ev.Dispose(); }
        }
        catch { }
    }

    void Reopen()
    {
        try { auth.OpenLoginPage(); }
        catch (Exception e) { GLog.Write("Browser nicht startbar: " + e.Message); }
    }

    LoginWait(GoogleAuth a)
    {
        auth = a;
        Text = "Task Board – Anmeldung bei Google";
        info = new Label { Left = 20, Top = 18, Width = 500, Height = 110,
            Text = "Dein Browser öffnet sich. Bitte melde dich dort bei Google an und erlaube Task Board den Zugriff.\n\n" +
                   "Bei „Google hat diese App nicht überprüft“: auf „Erweitert“ und dann auf „Zu Task Board wechseln“ klicken." };
        Controls.Add(info);
        Button again = MakeButton("Seite nochmal öffnen", 20, 140, 220, true);
        again.Click += delegate { Reopen(); };
        Controls.Add(again);
        Button cancel = MakeButton("Abbrechen", 250, 140, 130, false);
        cancel.Click += delegate { auth.CancelLogin = true; info.Text = "Wird abgebrochen …"; };
        Controls.Add(cancel);
        ClientSize = new System.Drawing.Size(540, 192);
        FormClosing += delegate { auth.CancelLogin = true; };
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        var t = new Thread(delegate ()
        {
            // eine Stunde: Familienkonten brauchen die Zustimmung der Eltern, und das Fenster hat einen Abbrechen-Knopf
            bool r = auth.Login(3600);
            try { BeginInvoke((MethodInvoker)delegate { ok = r; Close(); }); } catch { }
        });
        t.IsBackground = true;
        t.Start();
        var watch = new Thread(delegate ()
        {
            try
            {
                using (var ev = new EventWaitHandle(false, EventResetMode.AutoReset, AgainEvent))
                    while (!IsDisposed)
                        if (ev.WaitOne(500)) BeginInvoke((MethodInvoker)Reopen);
            }
            catch { }
        });
        watch.IsBackground = true;
        watch.Start();
    }

    public static bool Run(GoogleAuth a)
    {
        using (var f = new LoginWait(a)) { f.ShowDialog(); return f.ok; }
    }
}

// ---------- Auswahl der Google-Liste (kleines dunkles Fenster) ----------
class ListPicker : TbForm
{
    readonly List<RadioButton> radios = new List<RadioButton>();
    readonly List<string[]> lists;
    public string Id, Name2;

    ListPicker(List<string[]> lists, string current)
    {
        this.lists = lists;
        Text = "Task Board – Google-Liste";
        int y = 18;
        var head = new Label { Text = "In welcher Google-Liste sollen deine Aufgaben liegen?", AutoSize = true, Left = 20, Top = y };
        Controls.Add(head);
        y += 40;
        bool any = false;
        foreach (string[] l in lists)
        {
            var rb = new RadioButton { Text = l[1], AutoSize = true, Left = 26, Top = y, Tag = l[0] };
            if (l[0] == current || (current == "" && l[1] == "Task Board")) { rb.Checked = true; any = true; }
            radios.Add(rb); Controls.Add(rb);
            y += 32;
        }
        bool haveTb = lists.Any(l => l[1] == "Task Board");
        var nw = new RadioButton { Text = haveTb ? "Neue Liste anlegen: „Task Board (neu)“" : "Neue Liste anlegen: „Task Board“", AutoSize = true, Left = 26, Top = y, Tag = "" };
        if (!any) nw.Checked = true;
        radios.Add(nw); Controls.Add(nw);
        y += 44;
        var note = new Label { Text = "Andere Listen in deinem Google-Konto bleiben unberührt.", AutoSize = true, Left = 20, Top = y, ForeColor = System.Drawing.Color.FromArgb(175, 175, 188) };
        note.Font = new System.Drawing.Font("Segoe UI", 9.5f);
        Controls.Add(note);
        y += 36;
        Button ok = MakeButton("Übernehmen", 20, y, 130, true);
        Button cancel = MakeButton("Abbrechen", 160, y, 120, false);
        ok.Click += delegate { Choose(); };
        cancel.Click += delegate { DialogResult = DialogResult.Cancel; Close(); };
        Controls.Add(ok); Controls.Add(cancel);
        AcceptButton = ok; CancelButton = cancel;
        ClientSize = new System.Drawing.Size(Math.Max(520, head.PreferredWidth + 40), y + 56);
    }

    void Choose()
    {
        RadioButton rb = radios.FirstOrDefault(r => r.Checked);
        if (rb == null) return;
        Id = (string)rb.Tag;
        Name2 = Id == "" ? "" : rb.Text;
        DialogResult = DialogResult.OK;
        Close();
    }

    // gewaehlte Liste {id, name}; neue Liste wird hier angelegt; null = abgebrochen
    public static string[] Pick(TasksApi api, string current)
    {
        // Name landet in prefs.inc und auf der Kommandozeile des Setups: keine Zeilenumbrueche, Tabs, Anfuehrungszeichen
        var lists = api.Lists().Select(l => new[] { GJson.Str(l, "id"),
            Regex.Replace(GJson.Str(l, "title") ?? "", "[\\r\\n\\t]", " ").Replace('"', '\'') }).ToList();
        using (var f = new ListPicker(lists, current ?? ""))
        {
            if (f.ShowDialog() != DialogResult.OK) return null;
            if (f.Id != "") return new[] { f.Id, f.Name2 };
            string title = lists.Any(l => l[1] == "Task Board") ? "Task Board (neu)" : "Task Board";
            var created = api.NewList(title);
            return new[] { GJson.Str(created, "id"), title };
        }
    }
}

// ---------- Umschalten: Obsidian an/aus (nur Google = Kopie auf diesem PC) ----------
static class StoreSwitch
{
    // "google": Obsidian aus. Die Liste liest ab jetzt %LOCALAPPDATA%\TaskBoard\Todo.md (Kopie des bisherigen Inhalts).
    // "obsidian": Obsidian an. Die Kopie kommt zurueck in die Todo.md im Vault (alte Fassung wird vorher gesichert).
    public static string Switch(string res, string to)
    {
        GConf c = GConf.Load(res);
        string localTodo = GConf.LocalTodo, localArchive = GConf.LocalArchive;
        var prefs = SkinIni.Read(c.Prefs);
        if (to == "google")
        {
            if (!c.ObsidianOn) return "ok";
            if (!c.GoogleOn) return "fehler: erst mit Google verbinden";
            string src = GoogleSync.ReadText(c.TodoFile);
            if (src != null) GoogleSync.WriteText(localTodo, src);
            else if (!File.Exists(localTodo)) GoogleSync.WriteText(localTodo, "# Todo\n");
            if (!File.Exists(localArchive)) GoogleSync.WriteText(localArchive, "");
            SkinIni.Set(c.Prefs, new Dictionary<string, string> { { "ObsidianOn", "0" }, { "VaultTodoFile", c.TodoFile }, { "VaultArchiveFile", c.ArchiveFile } });
            c.WriteSettings(localTodo, localArchive, SkinIni.Get(SkinIni.Read(c.Settings), "VaultName", ""), false);
            MoveState(localTodo);
            return "ok";
        }
        // zurueck zu Obsidian
        if (c.ObsidianOn) return "ok";
        string todo = SkinIni.Get(prefs, "VaultTodoFile", ""), archive = SkinIni.Get(prefs, "VaultArchiveFile", "");
        if (todo == "")
        {
            try { todo = (string)Microsoft.Win32.Registry.GetValue(@"HKEY_CURRENT_USER\Software\TaskBoard", "TodoFile", "") ?? ""; } catch { }
            if (todo == "")
            {
                string dir = null;
                try { dir = (string)Microsoft.Win32.Registry.GetValue(@"HKEY_CURRENT_USER\Software\TaskBoard", "TodoDir", null); } catch { }
                if (dir != null) todo = Path.Combine(dir, "Todo.md");
            }
        }
        if (todo == "") return "kein-vault";
        if (archive == "") archive = Path.Combine(Path.GetDirectoryName(todo), "Todo-Archiv.md");
        string cur = GoogleSync.ReadText(localTodo);
        if (cur != null)
        {
            string old = GoogleSync.ReadText(todo);
            if (old != null && old != cur)
            {
                string bak = Path.Combine(GLog.StateDir(), "Sicherung");
                Directory.CreateDirectory(bak);
                GoogleSync.WriteText(Path.Combine(bak, "Todo-" + DateTime.Now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture) + ".md"), old);
            }
            Directory.CreateDirectory(Path.GetDirectoryName(todo));
            GoogleSync.WriteText(todo, cur);
        }
        // Archiv der Kopie an das Archiv im Vault anhaengen
        string la = GoogleSync.ReadText(localArchive);
        if (!string.IsNullOrEmpty(la) && la.Trim() != "")
        {
            var blocks = new List<List<string>>();
            foreach (string l in la.Replace("\r\n", "\n").Split('\n'))
                if (Fmt.Check.IsMatch(l) || Regex.IsMatch(l, @"^\s*[-*+] \[-\]")) blocks.Add(new List<string> { l });
                else if (blocks.Count > 0 && l.Trim() != "" && l.StartsWith(" ")) blocks[blocks.Count - 1].Add(l);
            if (blocks.Count > 0) GoogleSync.WriteText(archive, Fmt.AppendArchive(GoogleSync.ReadText(archive), blocks));
            GoogleSync.WriteText(localArchive, "");
        }
        string vault = Path.GetDirectoryName(todo);
        for (string p = vault; p != null; p = Path.GetDirectoryName(p)) if (Directory.Exists(Path.Combine(p, ".obsidian"))) { vault = p; break; }
        SkinIni.Set(c.Prefs, new Dictionary<string, string> { { "ObsidianOn", "1" } });
        c.WriteSettings(todo, archive, Path.GetFileName(vault.TrimEnd('\\')), true);
        MoveState(todo);
        return "ok";
    }

    // gemeinsamer Stand gilt fuer die neue Datei weiter (gleicher Inhalt) - sonst begaenne der Abgleich neu
    static void MoveState(string todo)
    {
        try
        {
            if (!File.Exists(GConf.StatePath)) return;
            var s = SyncState.Load(GConf.StatePath);
            s.Todo = todo;
            s.Save(GConf.StatePath);
        }
        catch { }
    }
}

// ---------- Kommandozeile (Setup, Einstellungen, Tests) ----------
//   --google-login                 Browser oeffnen, anmelden; "ok" oder "fehler: …"
//   --google-logout                Verbindung trennen (bei Google widerrufen, Schluessel loeschen)
//   --google-lists                 Listen: "<id>\t<Name>"
//   --google-newlist <Name>        neue Liste anlegen, gibt die id aus
//   --google-sync <todo> <archiv> <liste>   ein Abgleich
//   --google-dump <liste>          Aufgaben ausgeben (Tests)
//   --google-api <METHODE> <pfad> [json-datei]   beliebige Anfrage (Tests)
static class GoogleCli
{
    static void Out(string s) { try { Console.WriteLine(s); } catch { } }

    public static int Run(string exeDir, string[] args)
    {
        try { Console.OutputEncoding = new UTF8Encoding(false); } catch { }
        GLog.Dir = GLog.StateDir();
        GLog.Echo = Environment.GetEnvironmentVariable("TASKBOARD_GOOGLE_ECHO") == "1";
        if (args[0] == "--google-sync-now") { GStatus.Poke(); return 0; }
        if (args[0] == "--google-login-again") { LoginWait.SignalAgain(); return 0; }
        // Test: nur den Hintergrund-Abgleich laufen lassen (ohne Tastenkuerzel), <Sekunden> lang
        if (args[0] == "--google-background") { GoogleBackground.Start(exeDir); Thread.Sleep(1000 * (args.Length > 1 ? int.Parse(args[1]) : 60)); return 0; }
        GoogleAuth auth = GoogleAuth.Load(exeDir, GLog.Dir);
        if (auth == null) { Out("fehler: google-client.json fehlt"); return 2; }
        var api = new TasksApi(auth);
        try
        {
            switch (args[0])
            {
                // Einstellungen: anmelden + Liste waehlen + einschalten. Setup: "--google-connect --out <datei>"
                // schreibt nur "id\tname" in die Datei (die Einstellungen schreibt dann das Setup).
                case "--google-connect":
                {
                    Application.EnableVisualStyles();
                    string outFile = args.Length > 2 && args[1] == "--out" ? args[2] : null;
                    // Rainmeter beendet das Programm, sobald das Einstellungen-Fenster zugeht. Die Anmeldung laeuft
                    // deshalb in einem eigenen Prozess, der das ueberlebt; dieser hier wartet nur auf ihn.
                    if (outFile == null && !(args.Length > 1 && args[1] == "--detached"))
                    {
                        using (Process p = Process.Start(new ProcessStartInfo(Application.ExecutablePath, "--google-connect --detached") { UseShellExecute = true }))
                        {
                            p.WaitForExit();
                            return p.ExitCode;
                        }
                    }
                    if (!auth.Connected || outFile != null)
                    {
                        bool first;
                        using (var waiting = new Mutex(true, "TaskBoardGoogleLoginWait", out first))
                        {
                            // wartet schon (z. B. Tab geschlossen und nochmal geklickt): dort die Seite nochmal oeffnen
                            if (!first) { LoginWait.SignalAgain(); Out("laeuft"); return 0; }
                            try
                            {
                                if (!LoginWait.Run(auth))
                                {
                                    GLog.Write("Anmeldung fehlgeschlagen: " + auth.LastError);
                                    if (outFile == null) GStatus.Write(exeDir, "aus", "Nicht verbunden: " + auth.LastError, false);
                                    Out("fehler: " + auth.LastError);
                                    return 1;
                                }
                            }
                            finally { waiting.ReleaseMutex(); }
                        }
                        GLog.Write("angemeldet");
                    }
                    string current = outFile == null ? SkinIni.Get(SkinIni.Read(Path.Combine(exeDir, "prefs.inc")), "GoogleList", "") : "";
                    string[] pick = ListPicker.Pick(api, current);
                    if (pick == null) { Out("abgebrochen"); if (outFile == null) GStatus.Write(exeDir, "aus", "Verbunden, aber noch keine Liste gewählt.", true); return 1; }
                    if (outFile != null) { File.WriteAllText(outFile, pick[0] + "\t" + pick[1], new UTF8Encoding(true)); Out("ok"); return 0; }
                    return TurnOn(exeDir, pick);
                }
                case "--google-pick-list":
                {
                    Application.EnableVisualStyles();
                    string current = SkinIni.Get(SkinIni.Read(Path.Combine(exeDir, "prefs.inc")), "GoogleList", "");
                    string[] pick = ListPicker.Pick(api, current);
                    if (pick == null) { Out("abgebrochen"); return 1; }
                    return TurnOn(exeDir, pick);
                }
                case "--google-disconnect":
                {
                    auth.Logout();
                    SkinIni.Set(Path.Combine(exeDir, "prefs.inc"), new Dictionary<string, string> { { "GoogleOn", "0" } });
                    try { File.Delete(GConf.StatePath); } catch { }
                    GStatus.Write(exeDir, "aus", "Nicht mit Google verbunden.", false);
                    GLog.Write("Verbindung getrennt");
                    GStatus.Poke();
                    Out("ok");
                    return 0;
                }
                case "--google-store":
                {
                    string r = StoreSwitch.Switch(exeDir, args.Length > 1 ? args[1] : "");
                    GLog.Write("Speicherort: " + (args.Length > 1 ? args[1] : "?") + " -> " + r);
                    GStatus.Poke();
                    Out(r);
                    return r == "ok" ? 0 : 1;
                }
                case "--google-login":
                    if (auth.Login(300)) { GLog.Write("angemeldet"); Out("ok"); return 0; }
                    GLog.Write("Anmeldung fehlgeschlagen: " + auth.LastError);
                    Out("fehler: " + auth.LastError);
                    return 1;
                case "--google-logout":
                    auth.Logout();
                    GLog.Write("abgemeldet");
                    Out("ok");
                    return 0;
#if DEV
                case "--google-export-token":
                    File.WriteAllText(args[1], auth.DevRefreshToken(), new UTF8Encoding(false));
                    return 0;
#endif
                case "--google-parse":
                    // Test ohne Google: Datei zerlegen und wieder zusammensetzen (muss genau gleich sein)
                    string content = GoogleSync.ReadText(args[1]);
                    TodoDoc pd = TodoDoc.Parse(content);
                    Out("unveraendert zusammengesetzt: " + (pd.Serialize() == content ? "ja" : "NEIN"));
                    foreach (TBlock b in pd.Blocks())
                    {
                        Out((b.Head.P.Done ? "[x] " : "[ ] ") + b.Head.P.Title + " | meta " + b.Head.P.Meta + " | due " + b.Head.P.Due +
                            " | notes " + b.Head.P.Notes.Count + " | id " + (b.Head.Id ?? "-"));
                        foreach (TItem si in b.Subs) Out("    " + (si.P.Done ? "[x] " : "[ ] ") + si.P.Title + " | meta " + si.P.Meta + " | due " + si.P.Due);
                        // Probe: Zeile neu schreiben und wieder lesen -> gleicher Inhalt?
                        string re = "- [" + (b.Head.P.Done ? "x" : " ") + "] " + Fmt.LineText(b.Head.P, b.Head.DoneDate ?? Fmt.Today(), "TESTID");
                        Match rm = Fmt.Check.Match(re);
                        Proj back = Proj.OfLocal(rm.Groups[4].Value, rm.Groups[3].Value != " ", b.Head.P.Notes);
                        if (!back.Same(b.Head.P) || Fmt.IdOf(rm.Groups[4].Value) != "TESTID") Out("    !! neu geschrieben anders: " + re);
                    }
                    return 0;
                case "--google-status":
                    Out(auth.Connected ? "verbunden" : "nicht verbunden");
                    return 0;
                case "--google-lists":
                    foreach (var l in api.Lists()) Out(GJson.Str(l, "id") + "\t" + GJson.Str(l, "title"));
                    return 0;
                case "--google-newlist":
                    Out(GJson.Str(api.NewList(args.Length > 1 ? args[1] : "Task Board"), "id"));
                    return 0;
                case "--google-dump":
                    List<RTask> all = api.Tasks(args[1]);
                    var byId = all.ToDictionary(x => x.Id);
                    foreach (RTask t in all.OrderBy(x => x.Parent == null || !byId.ContainsKey(x.Parent) ? x.Position : byId[x.Parent].Position + "/" + x.Position, StringComparer.Ordinal))
                        Out((t.Parent != null ? "    " : "") + (t.Done ? "[x] " : "[ ] ") + t.Title + (t.Due != "" ? " | due " + t.Due : "") +
                            (t.Notes != "" ? " | notes " + t.Notes.Replace("\n", " / ") : "") + (t.Hidden ? " | hidden" : "") + " | id " + t.Id);
                    return 0;
                case "--google-api":
                    Dictionary<string, object> body = args.Length > 3 ? GJson.Obj(GJson.Parse(File.ReadAllText(args[3], Encoding.UTF8))) : null;
                    Out(GJson.Write(api.Call(args[1], args[2], body)));
                    return 0;
                case "--google-sync":
                    var s = new GoogleSync { TodoPath = args[1], ArchivePath = args[2], ListId = args[3], StatePath = Path.Combine(GLog.Dir, "google-sync.json"), Api = api };
                    bool ok = s.Run();
                    GLog.Write((ok ? "Abgleich: " : "Abgleich abgebrochen: ") + s.Summary + " (" + api.Calls + " Anfragen)");
                    Out((ok ? "ok: " : "abgebrochen: ") + s.Summary + " (" + api.Calls + " Anfragen)");
                    return ok ? 0 : 1;
            }
        }
        catch (GoogleException e) { GLog.Write("Fehler: " + e.Message); Out("fehler: " + e.Message); return 1; }
        catch (Exception e) { GLog.Write("Fehler: " + e); Out("fehler: " + e.Message); return 1; }
        Out("unbekannter Befehl");
        return 2;
    }

    // Liste merken und Abgleich einschalten (neue Liste = neuer gemeinsamer Stand)
    static int TurnOn(string res, string[] pick)
    {
        var old = SkinIni.Read(Path.Combine(res, "prefs.inc"));
        if (SkinIni.Get(old, "GoogleList", "") != pick[0] && SkinIni.Get(old, "ObsidianOn", "1") == "0")
        {
            // nur Google: die Kopie auf diesem PC gehoert zur alten Liste - sie wird aus der neuen Liste neu gefuellt
            GoogleSync.WriteText(GConf.LocalTodo, "# Todo\n");
            try { File.Delete(GConf.StatePath); } catch { }
        }
        SkinIni.Set(Path.Combine(res, "prefs.inc"), new Dictionary<string, string> { { "GoogleOn", "1" }, { "GoogleList", pick[0] }, { "GoogleListName", pick[1] } });
        GStatus.Write(res, "ok", "Verbunden · Liste „" + pick[1] + "“ · wird abgeglichen …", true);
        GLog.Write("Liste gewaehlt: " + pick[0]);
        GStatus.Poke();
        Out("ok");
        return 0;
    }
}
