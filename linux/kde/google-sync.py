#!/usr/bin/env python3
# Google Tasks fuer Task Board unter Linux. Gegenstueck zu src/google.cs (Windows): gleiche Regeln, gleiches Format.
# Nur Python-Standardbibliothek.
#
#   google-sync.py sync                  ein Abgleich (das Widget ruft das nach Aenderungen und alle 30 Sekunden auf)
#   google-sync.py connect [--out DATEI] anmelden + Liste waehlen + einschalten (--out: nur "id<TAB>name" schreiben, fuers Setup)
#   google-sync.py pick-list             andere Liste waehlen
#   google-sync.py disconnect            Verbindung trennen (bei Google widerrufen, Schluessel loeschen)
#   google-sync.py store google|obsidian Obsidian aus/an ("nur Google" = Kopie in ~/.local/share/taskboard)
#   google-sync.py enable 0|1            Abgleich aus/an (Verbindung bleibt)
#   google-sync.py logout                nur abmelden (Deinstallation)
#   google-sync.py login-again           wartende Anmeldung: Seite im Browser nochmal oeffnen (Tab geschlossen)
#   Tests: sync-file <todo> <archiv> <liste> | dump <liste> | api <METHODE> <pfad> [json-datei] | parse <datei> | lists | newlist <name>
#
# So funktioniert der Abgleich:
#   - Jede verbundene Zeile in der Todo.md traegt am Ende eine unsichtbare Kennung "%%tb:<Google-ID>%%".
#   - Zu jedem Eintrag merkt sich der Abgleich den letzten gemeinsamen Stand (google-sync.json). Aendern beide Seiten
#     dasselbe Feld, gewinnt der PC.
#   - Was Google nicht kennt (Tags, Wiederholung, Uhrzeit, Erstellt-Datum), steht als letzte Zeile im Notizfeld:
#     "⟦tb #arbeit 🔁 täglich ⏰ 15:00 ➕ 2026-11-01⟧".
#   - Bei Google geloeschte Eintraege kommen ins Archiv. Verschwindet viel auf einmal, wird 30 Minuten gewartet.
import base64
import fcntl
import hashlib
import html
import json
import os
import re
import secrets
import select
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from http.client import HTTPException

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_test_dir = os.environ.get("TASKBOARD_GOOGLE_DIR")
CONF_DIR = _test_dir or os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "taskboard")
DATA_DIR = _test_dir or os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "taskboard")
CONF = os.path.join(CONF_DIR, "config")           # vom Setup: VAULT, VAULT_NAME, TODO_FILE, ARCHIVE_FILE, MODE
GCONF = os.path.join(CONF_DIR, "google")          # GOOGLE_ON, GOOGLE_LIST, GOOGLE_LIST_NAME, OBSIDIAN_ON, VAULT_TODO_FILE, ...
TOKEN = os.path.join(CONF_DIR, "google-token.json")
STATE = os.path.join(DATA_DIR, "google-sync.json")
STATUS = os.path.join(DATA_DIR, "google-status")  # Zustand \n verbunden(0/1) \n Text - liest das Einstellungen-Fenster
LOGFILE = os.path.join(DATA_DIR, "google.log")
GUARD = os.path.join(DATA_DIR, "google-guard")    # seit wann der Schutz gegen Massen-Loeschen greift
AGAIN = os.path.join(DATA_DIR, "google-login-again")   # gibt es die Datei, oeffnet die wartende Anmeldung ihre Seite nochmal
LOCAL_TODO = os.path.join(DATA_DIR, "Todo.md")
LOCAL_ARCHIVE = os.path.join(DATA_DIR, "Todo-Archiv.md")
CLIENT = os.environ.get("TASKBOARD_CLIENT") or os.path.join(SCRIPT_DIR, "google-client.json")

SCOPE = "https://www.googleapis.com/auth/tasks"
AUTH_URI = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URI = "https://oauth2.googleapis.com/token"
REVOKE_URI = "https://oauth2.googleapis.com/revoke"
API = "https://tasks.googleapis.com/tasks/v1/"
ECHO = os.environ.get("TASKBOARD_GOOGLE_ECHO") == "1"


def log(msg):
    """Protokoll ohne Aufgabeninhalte und Schluessel - nur Zahlen, Kennungen, Fehler."""
    line = datetime.now().strftime("%Y-%m-%d %H:%M:%S") + " " + msg
    if ECHO:
        print(line)
    try:
        os.makedirs(DATA_DIR, exist_ok=True)
        if os.path.exists(LOGFILE) and os.path.getsize(LOGFILE) > 512 * 1024:
            os.replace(LOGFILE, LOGFILE + ".1")
        with open(LOGFILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass


class GoogleError(Exception):
    def __init__(self, msg, code):
        super().__init__(msg)
        self.code = code      # HTTP-Status, 0 = keine Verbindung


# ---------- Dateien ----------
def read_text(path):
    """None, wenn es die Datei nicht gibt. Ein BOM bleibt als Zeichen erhalten."""
    try:
        with open(path, "rb") as f:
            return f.read().decode("utf-8", "replace")
    except FileNotFoundError:
        return None


def write_text(path, content, mode=None):
    """Atomar schreiben (die Liste und Obsidian sehen nie eine halbe Datei)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = "%s.%d.taskboard.tmp" % (path, os.getpid())
    with open(tmp, "wb") as f:
        f.write(content.encode("utf-8"))
    if mode is not None:
        os.chmod(tmp, mode)
    elif os.path.exists(path):
        shutil.copymode(path, tmp)
    os.replace(tmp, path)


def stable_read(path):
    """Lesen, bis der Inhalt zweimal gleich ist (es koennte gerade jemand schreiben)."""
    a = read_text(path)
    for _ in range(10):
        time.sleep(0.12)
        b = read_text(path)
        if b == a:
            return a
        a = b
    return a


def read_kv(path):
    out = {}
    for line in (read_text(path) or "").splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def set_kv(path, values):
    """Schluessel setzen, Rest der Datei bleibt."""
    lines = (read_text(path) or "").splitlines()
    for k, v in values.items():
        new = k + "=" + v
        for i, line in enumerate(lines):
            if line.split("=", 1)[0].strip() == k and "=" in line:
                lines[i] = new
                break
        else:
            lines.append(new)
    write_text(path, "\n".join(lines) + "\n")


def write_status(state, text, connected):
    content = state + "\n" + ("1" if connected else "0") + "\n" + text.replace("\n", " ")
    if read_text(STATUS) != content:
        try:
            write_text(STATUS, content)
        except OSError:
            pass


# ---------- HTTP ----------
def http(method, url, bearer=None, ctype=None, body=None):
    data = body.encode("utf-8") if body is not None else (b"" if method in ("POST", "PATCH", "PUT") else None)
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("User-Agent", "TaskBoard")
    req.add_header("Accept", "application/json")
    if bearer:
        req.add_header("Authorization", "Bearer " + bearer)
    if ctype:
        req.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except (urllib.error.URLError, HTTPException, OSError) as e:      # z. B. Verbindung mittendrin abgerissen
        return 0, str(e)


def err_text(resp):
    try:
        d = json.loads(resp)
    except ValueError:
        return (resp or "")[:200]
    e = d.get("error") if isinstance(d, dict) else None
    if isinstance(e, str):
        return e + (" (" + d["error_description"] + ")" if d.get("error_description") else "")
    if isinstance(e, dict) and e.get("message"):
        return e["message"]
    return (resp or "")[:200]


def form(**kv):
    return urllib.parse.urlencode(kv)


# ---------- Anmeldung ----------
# Zugang des Programms: google-client.json neben diesem Skript (Google-Cloud-Projekt "Task Board", Typ Desktop-App).
# Der dauerhafte Schluessel des Nutzers liegt nur auf diesem PC, nur fuer ihn lesbar (Rechte 600).
class GoogleAuth:
    def __init__(self, client_id, secret):
        self.client_id, self.secret = client_id, secret
        self.access = None
        self.access_until = 0
        self.stale = False        # Google hat den gespeicherten Zugriffsschluessel abgelehnt
        self.last_error = None
        self.revoked = False

    @staticmethod
    def load():
        try:
            inst = json.loads(read_text(CLIENT) or "{}").get("installed") or {}
        except ValueError as e:
            log("google-client.json unlesbar: " + str(e))
            return None
        if not inst.get("client_id") or not inst.get("client_secret"):
            return None
        return GoogleAuth(inst["client_id"], inst["client_secret"])

    @property
    def connected(self):
        return os.path.exists(TOKEN)

    @staticmethod
    def _stored():
        try:
            d = json.loads(read_text(TOKEN) or "{}")
            return d if isinstance(d, dict) else {}
        except ValueError:
            return {}

    def _save(self, d, refresh):
        """Dauerhaften und aktuellen Schluessel sichern (nur fuer den Nutzer lesbar). Der aktuelle gilt eine Stunde -
        so holt nicht jeder Abgleich einen neuen."""
        self.access = d.get("access_token")
        self.access_until = time.time() + int(d.get("expires_in", 3600)) - 120
        self.stale = False
        write_text(TOKEN, json.dumps({"refresh_token": refresh, "access_token": self.access, "access_until": self.access_until}), mode=0o600)

    def login(self, timeout=300, cancelled=None, reopen=None):
        """Anmeldung im Browser: Google leitet nach der Zustimmung an http://127.0.0.1:<Port> zurueck."""
        self.last_error = None
        verifier = secrets.token_urlsafe(32)
        state = secrets.token_urlsafe(16)
        challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            srv.bind(("127.0.0.1", 0))
            srv.listen(5)
            redirect = "http://127.0.0.1:%d" % srv.getsockname()[1]
            url = AUTH_URI + "?" + form(client_id=self.client_id, redirect_uri=redirect, response_type="code", scope=SCOPE,
                                        code_challenge=challenge, code_challenge_method="S256", state=state,
                                        access_type="offline", prompt="consent")

            def open_page():
                if os.environ.get("TASKBOARD_NO_BROWSER") == "1":
                    log("Anmeldeseite geoeffnet (Test)")
                    return
                subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

            open_page()
            until = time.time() + timeout
            while time.time() < until:
                if cancelled and cancelled():
                    self.last_error = "abgebrochen"
                    return False
                if reopen and reopen():
                    open_page()      # Google nimmt dieselbe Adresse wieder an
                if not select.select([srv], [], [], 0.2)[0]:
                    continue
                conn, _ = srv.accept()
                with conn:
                    try:
                        conn.settimeout(5)
                        q = self._read_query(conn)
                        code, err = q.get("code"), q.get("error")
                        if code is None and err is None:
                            self._respond(conn, 404, "Not found")      # z. B. favicon.ico
                            continue
                        if err is not None:
                            self._respond(conn, 200, self._page(False, "Die Anmeldung wurde abgebrochen. Du kannst dieses Fenster schließen."))
                            self.last_error = "abgebrochen (" + err + ")"
                            return False
                        if q.get("state") != state:
                            self._respond(conn, 400, self._page(False, "Ungültige Antwort von Google."))
                            self.last_error = "ungueltige Antwort (state)"
                            return False
                        ok = self._exchange(code, verifier, redirect)
                        self._respond(conn, 200, self._page(True, "Task Board ist jetzt mit Google verbunden. Du kannst dieses Fenster schließen.") if ok
                                      else self._page(False, "Die Anmeldung hat nicht geklappt: " + str(self.last_error)))
                        return ok
                    except OSError:
                        pass          # Browser hat nur vorsorglich verbunden, ohne Anfrage
            self.last_error = "Zeit abgelaufen"
            return False
        except OSError as e:
            self.last_error = str(e)
            return False
        finally:
            srv.close()

    @staticmethod
    def _read_query(conn):
        buf = b""
        while b"\r\n\r\n" not in buf and len(buf) < 16384:
            part = conn.recv(1024)
            if not part:
                break
            buf += part
        parts = buf.split(b"\r\n", 1)[0].decode("ascii", "replace").split(" ")
        target = parts[1] if len(parts) > 1 else ""
        return dict(urllib.parse.parse_qsl(target.split("?", 1)[1])) if "?" in target else {}

    @staticmethod
    def _respond(conn, status, page):
        body = page.encode("utf-8")
        reason = {200: "OK", 404: "Not Found"}.get(status, "Bad Request")
        head = "HTTP/1.1 %d %s\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % (status, reason, len(body))
        conn.sendall(head.encode("ascii") + body)

    @staticmethod
    def _page(ok, text):
        return ("<!doctype html><html lang=\"de\"><head><meta charset=\"utf-8\"><title>Task Board</title><style>"
                "body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:#17151c;color:#ece9f1;font:18px/1.5 system-ui,sans-serif}"
                "div{max-width:520px;padding:24px;text-align:center}h1{margin:0 0 12px;color:" + ("#f06292" if ok else "#ff8a80") + "}</style></head><body><div><h1>" +
                ("Verbunden" if ok else "Nicht verbunden") + "</h1><p>" + html.escape(text) + "</p></div></body></html>")

    def _exchange(self, code, verifier, redirect):
        st, resp = http("POST", TOKEN_URI, ctype="application/x-www-form-urlencoded",
                        body=form(code=code, client_id=self.client_id, client_secret=self.secret, redirect_uri=redirect,
                                  grant_type="authorization_code", code_verifier=verifier))
        try:
            d = json.loads(resp)
        except ValueError:
            d = None
        if st != 200 or not isinstance(d, dict):
            self.last_error = "keine Verbindung zu Google" if st == 0 else "Google: " + err_text(resp)
            return False
        if SCOPE not in (d.get("scope") or ""):
            self.last_error = "der Zugriff auf Google Tasks wurde nicht erlaubt"
            return False
        if not d.get("refresh_token"):
            self.last_error = "Google hat keinen dauerhaften Schluessel geliefert"
            return False
        self._save(d, d["refresh_token"])
        self.revoked = False
        return True

    def access_token(self):
        if self.access and time.time() < self.access_until:
            return self.access
        stored = self._stored()
        rt = stored.get("refresh_token")
        if not rt:
            self.last_error = "nicht angemeldet"
            return None
        if not self.stale and stored.get("access_token") and time.time() < float(stored.get("access_until") or 0):
            self.access, self.access_until = stored["access_token"], float(stored["access_until"])
            return self.access
        st, resp = http("POST", TOKEN_URI, ctype="application/x-www-form-urlencoded",
                        body=form(client_id=self.client_id, client_secret=self.secret, refresh_token=rt, grant_type="refresh_token"))
        try:
            d = json.loads(resp)
        except ValueError:
            d = {}
        if st == 200 and d.get("access_token"):
            self._save(d, rt)
            return self.access
        if isinstance(d, dict) and d.get("error") == "invalid_grant":
            self.revoked = True
            self.last_error = "abgemeldet"
            try:
                os.remove(TOKEN)      # Zugang ungueltig: die Liste zeigt "Neu verbinden"
            except OSError:
                pass
        else:
            self.last_error = "offline" if st == 0 else "Google: " + err_text(resp)
        return None

    def invalidate(self):
        self.access = None
        self.stale = True

    def logout(self):
        rt = self._stored().get("refresh_token")
        if rt:
            st, _ = http("POST", REVOKE_URI, ctype="application/x-www-form-urlencoded", body=form(token=rt))
            log("Abmeldung bei Google: Antwort %d" % st)
        try:
            os.remove(TOKEN)
        except OSError:
            pass
        self.access = None


# ---------- Aufgabe bei Google ----------
def parse_date(s):
    """RFC 3339 -> Unix-Zeit, unbekannt = 0"""
    if not s:
        return 0
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0


class RTask:
    def __init__(self, d):
        self.id = d.get("id")
        self.title = d.get("title") or ""
        self.notes = d.get("notes") or ""
        due = d.get("due") or ""
        self.due = due[:10] if len(due) >= 10 else ""
        self.done = d.get("status") == "completed"
        self.parent = d.get("parent") or None
        self.position = d.get("position") or ""
        self.hidden = bool(d.get("hidden"))
        self.deleted = bool(d.get("deleted"))
        self.updated = parse_date(d.get("updated"))
        self.completed = parse_date(d.get("completed"))

    def completed_day(self):
        if self.completed:
            return datetime.fromtimestamp(self.completed).strftime("%Y-%m-%d")
        return today()


class TasksApi:
    def __init__(self, auth):
        self.auth = auth
        self.calls = 0

    @staticmethod
    def _e(s):
        return urllib.parse.quote(s, safe="")

    def call(self, method, path, body=None):
        attempt = 0
        while True:
            tok = self.auth.access_token()
            if tok is None:
                raise GoogleError(self.auth.last_error or "nicht angemeldet", 401 if self.auth.revoked else 0)
            self.calls += 1
            st, resp = http(method, API + path, bearer=tok, ctype="application/json; charset=utf-8" if body is not None else None,
                            body=json.dumps(body, ensure_ascii=False) if body is not None else None)
            if 200 <= st < 300:
                try:
                    return json.loads(resp) if resp else None
                except ValueError:
                    return None
            if st == 401 and attempt == 0:
                self.auth.invalidate()
            elif (st == 429 or st >= 500) and attempt < 2:
                time.sleep(1.5 * (attempt + 1))
            else:
                raise GoogleError("offline" if st == 0 else "Google %d: %s" % (st, err_text(resp)), st)
            attempt += 1

    def lists(self):
        out, page = [], None
        while True:
            d = self.call("GET", "users/@me/lists?maxResults=100" + ("&pageToken=" + self._e(page) if page else "")) or {}
            out += d.get("items") or []
            page = d.get("nextPageToken")
            if not page:
                return out

    def new_list(self, title):
        return self.call("POST", "users/@me/lists", {"title": title})

    def tasks(self, lst):
        """Alle Aufgaben, auch erledigte; showHidden, weil Google in der eigenen App abgehakte Aufgaben ausblendet."""
        out, page = [], None
        while True:
            d = self.call("GET", "lists/" + self._e(lst) + "/tasks?maxResults=100&showCompleted=true&showHidden=true" +
                          ("&pageToken=" + self._e(page) if page else "")) or {}
            for it in d.get("items") or []:
                t = RTask(it)
                if t.id and not t.deleted:
                    out.append(t)
            page = d.get("nextPageToken")
            if not page:
                return out

    def _q(self, parent, previous):
        p = []
        if parent is not None:
            p.append("parent=" + self._e(parent))
        if previous is not None:
            p.append("previous=" + self._e(previous))
        return "?" + "&".join(p) if p else ""

    def insert(self, lst, body, parent, previous):
        d = self.call("POST", "lists/" + self._e(lst) + "/tasks" + self._q(parent, previous), body)
        if not d or not d.get("id"):
            raise GoogleError("Google hat die neue Aufgabe nicht bestaetigt", 0)
        return RTask(d)

    def patch(self, lst, tid, body):
        d = self.call("PATCH", "lists/" + self._e(lst) + "/tasks/" + self._e(tid), body)
        return RTask(d) if d and d.get("id") else None

    def delete(self, lst, tid):
        try:
            self.call("DELETE", "lists/" + self._e(lst) + "/tasks/" + self._e(tid))
        except GoogleError as e:
            if e.code != 404:     # schon weg (z. B. mit dem Hauptpunkt)
                raise

    def move(self, lst, tid, parent, previous):
        d = self.call("POST", "lists/" + self._e(lst) + "/tasks/" + self._e(tid) + "/move" + self._q(parent, previous))
        return RTask(d) if d and d.get("id") else None


# ---------- Textformat der Todo.md (wie todo.js und src/todo.lua) ----------
DUE_I, CREATED_I, DONE_I, CANCEL_I, REPEAT_I, TIME_I = "\U0001F4C5", "➕", "✅", "❌", "\U0001F501", "⏰"
TRAILER_OPEN, TRAILER_CLOSE = "⟦tb", "⟧"
# Zeichen, die ein neues Symbol einleiten (wie in todo.js: U+2000-U+2FFF und alles ausserhalb der BMP)
SYM = " -⿿\U00010000-\U0010FFFF"
DATE = r"\d{4}-\d{2}-\d{2}"
CHECK = re.compile(r"^(\s*)([-*+]) \[([ xX])\] ?(.*)$")
MARKER = re.compile(r"\s*%%tb:([A-Za-z0-9_=-]+)%%")
DUE_RE = re.compile(re.escape(DUE_I) + r"\s*(" + DATE + ")")
DUE_STRIP = re.compile(r"\s*" + re.escape(DUE_I) + r"\s*" + DATE)
REP_STRIP = re.compile(r"\s*" + re.escape(REPEAT_I) + "[^" + SYM + r"]*[^\s" + SYM + "]")
RULE_RE = re.compile(re.escape(REPEAT_I) + r"\s*([^" + SYM + r"]*[^\s" + SYM + "])")
TIME_RE = re.compile(re.escape(TIME_I) + r"\s*(\d\d?):(\d\d)")
TIME_STRIP = re.compile(r"\s*" + re.escape(TIME_I) + r"\s*\d\d?:\d\d")
CREATED_RE = re.compile(re.escape(CREATED_I) + r"\s*(" + DATE + ")")
CREATED_STRIP = re.compile(r"\s*" + re.escape(CREATED_I) + r"\s*" + DATE)
DONE_RE = re.compile(re.escape(DONE_I) + r"\s*(" + DATE + ")")
DONE_STRIP = re.compile(r"\s*" + re.escape(DONE_I) + r"\s*" + DATE)
TAG_RE = re.compile(r"""(^|\s)#([^\s#.,;:!?()\[\]{}"'<>]+)""")
SPACES = re.compile(r"\s{2,}")
BOX = re.compile(r"\[[ xX]\]")
MONTHS = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
MAX_TITLE, MAX_NOTES = 1024, 8192       # Grenzen bei Google


def today():
    return datetime.now().strftime("%Y-%m-%d")


def indent_of(line):
    n = 0
    for ch in line:
        if ch == " ":
            n += 1
        elif ch == "\t":
            n += 4
        else:
            break
    return n


def id_of(text):
    m = MARKER.search(text)
    return m.group(1) if m else None


def strip_marker(text):
    return MARKER.sub("", text)


def with_marker(text, tid):
    text = strip_marker(text)
    return text if tid is None else text + " %%tb:" + tid + "%%"


def has_non_digit(s):
    return any(c < "0" or c > "9" for c in s)


def tags_of(text):
    out = []
    for m in TAG_RE.finditer(text):
        n = m.group(2)
        if has_non_digit(n) and n not in out:
            out.append(n)
    return out


def strip_tags(text):
    text = TAG_RE.sub(lambda m: m.group(1) if has_non_digit(m.group(2)) else m.group(0), text)
    return SPACES.sub(" ", text)


def strip_stamps(text):
    return DONE_STRIP.sub("", CREATED_STRIP.sub("", text))


def strip_due(text):
    return TIME_STRIP.sub("", REP_STRIP.sub("", DUE_STRIP.sub("", text), count=1))


def title_of(text):
    """Titel wie im Formular der Liste: ohne Termin, Wiederholung, Uhrzeit, Stempel, Tags und Kennung."""
    return strip_tags(strip_due(strip_stamps(strip_marker(text)))).strip()


def due_of(text):
    m = DUE_RE.search(text)
    return m.group(1) if m else ""


def done_date_of(text):
    m = DONE_RE.search(text)
    return m.group(1) if m else None


def meta_of(text):
    """Alles, was Google nicht kennt, in fester Reihenfolge: "#a #b 🔁 regel ⏰ 09:00 ➕ 2026-11-01"."""
    text = strip_marker(text)
    parts = []
    tags = tags_of(text)
    if tags:
        parts.append("#" + " #".join(tags))
    r = RULE_RE.search(text)
    if r:
        parts.append(REPEAT_I + " " + r.group(1).strip())
    t = TIME_RE.search(text)
    if t:
        parts.append("%s %02d:%s" % (TIME_I, int(t.group(1)), t.group(2)))
    c = CREATED_RE.search(text)
    if c:
        parts.append(CREATED_I + " " + c.group(1))
    return " ".join(parts)


def line_text(p, done_date, tid):
    """Zeilentext nach "- [ ] " in der Reihenfolge, in der die Liste selbst schreibt."""
    s = p.title
    for tag in tags_of(p.meta):
        s += " #" + tag
    r = RULE_RE.search(p.meta)
    if r:
        s += " " + REPEAT_I + " " + r.group(1).strip()
    t = TIME_RE.search(p.meta)
    if t:
        s += " %s %02d:%s" % (TIME_I, int(t.group(1)), t.group(2))
    if p.due:
        s += " " + DUE_I + " " + p.due
    c = CREATED_RE.search(p.meta)
    if c:
        s += " " + CREATED_I + " " + c.group(1)
    if p.done and done_date:
        s += " " + DONE_I + " " + done_date
    if tid:
        s += " %%tb:" + tid + "%%"
    return s


def remote_title(title):
    title = strip_marker(title.replace("\r", " ").replace("\n", " "))
    return strip_tags(title).strip(), tags_of(title)


def trailer(meta):
    return TRAILER_OPEN + " " + meta + TRAILER_CLOSE


def u16len(s):
    """Laenge in UTF-16-Einheiten (so zaehlt die Windows-Fassung; Emojis zaehlen doppelt)."""
    return len(s) + sum(1 for ch in s if ch > "\uffff")


def u16cut(s, n):
    used, end = 0, 0
    for ch in s:
        used += 2 if ch > "\uffff" else 1
        if used > n:
            break
        end += 1
    return s[:end]


def fit_title(t):
    return u16cut(t, MAX_TITLE).strip() if u16len(t) > MAX_TITLE else t


def fit_notes(notes, meta):
    """Was laenger ist als Googles Grenze, bleibt in der Datei vollstaendig; bei Google steht der Anfang."""
    room = MAX_NOTES - (u16len(trailer(meta)) + 1 if meta else 0)
    joined = "\n".join(notes)
    if u16len(joined) <= room:
        return list(notes)
    return [l.strip() for l in u16cut(joined, max(0, room)).split("\n") if l.strip()]


def note_line(indent, note):
    """Sieht der Text wie eine Checkbox aus ("[ ] Milch"), ohne "- " schreiben - sonst waere es eine Unteraufgabe."""
    return indent + "    " + ("" if re.match(r"^\[[ xX]\]", note) else "- ") + note


def split_notes(notes):
    """Notizfeld von Google: eigene Notizzeilen + Zusatzangaben aus der Schlusszeile."""
    human, meta = [], ""
    for raw in (notes or "").replace("\r\n", "\n").split("\n"):
        l = raw.strip()
        if l.startswith(TRAILER_OPEN) and l.endswith(TRAILER_CLOSE):
            meta = meta_of(l[len(TRAILER_OPEN):-len(TRAILER_CLOSE)])
        elif l:
            human.append(l)
    return human, meta


def archive_block(lines, indent, deleted, suffix=None):
    b = []
    for raw in lines:
        l = raw[len(indent):] if raw.startswith(indent) else raw.lstrip()
        l = strip_marker(l)
        if l.strip():
            b.append(l)
    if not b:
        return b
    if deleted:
        b[0] = BOX.sub("[-]", b[0], count=1) + " " + CANCEL_I + " " + today()
    elif DONE_I not in b[0]:
        b[0] += " " + DONE_I + " " + today()
    if suffix:
        b[0] += suffix
    return b


def append_archive(content, blocks):
    c = content
    if not c:
        c = ("---\ntags: [todo, archiv]\n---\n\n# Todo-Archiv\n\nErledigte und gelöschte Punkte aus [[Todo]], mit allen Notizen und Unteraufgaben. "
             "➕ = erstellt, ✅ = erledigt, ❌ = gelöscht (`- [-]`).\n")
    now = datetime.now()
    heading = "## %s %d" % (MONTHS[now.month - 1], now.year)
    found = re.findall(r"\n(## [^\r\n]*)", c)
    out = re.sub(r"[\r\n]*$", "", c)
    if not found or found[-1] != heading:
        out += "\n\n" + heading + "\n"
    for b in blocks:
        out += "\n" + "\n".join(b)
    return out + "\n"


# ---------- Inhalt eines Eintrags, so wie ihn beide Seiten vergleichen ----------
class Proj:
    def __init__(self, title="", meta="", due="", done=False, notes=None):
        self.title, self.meta, self.due, self.done = title, meta, due, done
        self.notes = list(notes or [])

    @property
    def notes_key(self):
        return "\n".join(self.notes)

    def same(self, o):
        return o is not None and self.title == o.title and self.meta == o.meta and self.due == o.due and self.done == o.done and self.notes_key == o.notes_key

    def clone(self):
        return Proj(self.title, self.meta, self.due, self.done, self.notes)

    def to_json(self):
        return {"t": self.title, "m": self.meta, "d": self.due, "x": self.done, "n": self.notes}

    @staticmethod
    def from_json(d):
        return Proj(d.get("t") or "", d.get("m") or "", d.get("d") or "", bool(d.get("x")), [str(n) for n in d.get("n") or []])

    @staticmethod
    def of_local(text, done, notes):
        return Proj(title_of(text), meta_of(text), due_of(text), done, [n.strip() for n in notes or [] if n.strip()])

    @staticmethod
    def of_remote(r, sub):
        """Unteraufgaben haben in der Todo.md keine Notizen - ihre Google-Notizen bleiben unberuehrt."""
        human, meta = split_notes(r.notes)
        title, tags = remote_title(r.title)
        if tags:
            meta = meta_of("#" + " #".join(tags) + " " + meta)
        return Proj(title, meta, r.due, r.done, [] if sub else human)

    def align(self, full):
        """Was Google nur gekuerzt speichern kann, gilt als gleich (self = Stand bei Google, full = Stand in der Datei)."""
        if full is None:
            return
        if self.title != full.title and self.title == fit_title(full.title):
            self.title = full.title
        if self.notes_key != full.notes_key and self.notes_key == "\n".join(fit_notes(full.notes, full.meta)):
            self.notes = list(full.notes)

    @staticmethod
    def _pick(b, l, r, local_wins):
        if l == r:
            return l
        if b is not None:
            if l == b:
                return r
            if r == b:
                return l
        return l if local_wins else r

    @staticmethod
    def merge(b, l, r, local_wins):
        """Drei-Wege-Abgleich je Feld: was nur eine Seite geaendert hat, wird uebernommen; bei Streit gewinnt local_wins."""
        p = Proj._pick
        m = Proj()
        m.title = p(b.title if b else None, l.title, r.title, local_wins)
        if not m.title:
            m.title = l.title or r.title       # leeren Titel nie uebernehmen
        m.meta = p(b.meta if b else None, l.meta, r.meta, local_wins)
        m.due = p(b.due if b else None, l.due, r.due, local_wins)
        m.done = p(None if b is None else ("1" if b.done else "0"), "1" if l.done else "0", "1" if r.done else "0", local_wins) == "1"
        nk = p(b.notes_key if b else None, l.notes_key, r.notes_key, local_wins)
        m.notes = list(l.notes if nk == l.notes_key else r.notes if nk == r.notes_key else b.notes)
        return m


# ---------- Todo.md als Folge von Zeilen und Punkten ----------
class TItem:
    def __init__(self):
        self.indent, self.line, self.text = "", "", ""
        self.done = self.is_sub = False
        self.id = None
        self.done_date = None
        self.p = None
        self.dirty = False          # Zeile aus p neu schreiben
        self.marker_changed = False # nur die Kennung anhaengen/aendern
        self.block = None

    @staticmethod
    def from_match(line, m, sub, block):
        it = TItem()
        it.indent, it.line, it.text = m.group(1), line, m.group(4)
        it.done, it.is_sub, it.block = m.group(3) != " ", sub, block
        it.id, it.done_date = id_of(it.text), done_date_of(it.text)
        return it

    def output(self):
        if self.dirty:
            return self.indent + "- [" + ("x" if self.p.done else " ") + "] " + line_text(self.p, (self.done_date or today()) if self.p.done else None, self.id)
        if self.marker_changed:
            return with_marker(self.line, self.id)
        return self.line


class TBlock:
    def __init__(self):
        self.head = None
        self.children = []          # TItem (Unteraufgabe) oder str (unveraenderte Notiz-/Leerzeile)
        self.subs = []
        self.notes = []
        self.dirty = False          # Unteraufgaben und Notizen neu zusammensetzen

    def lines(self):
        out = [self.head.output()]
        if not self.dirty:
            out += [c.output() if isinstance(c, TItem) else c for c in self.children]
        else:
            out += [s.output() for s in self.subs]
            out += [note_line(self.head.indent, n) for n in self.head.p.notes]
        return out


class TodoDoc:
    def __init__(self):
        self.bom, self.nl = "", "\n"
        self.segs = []              # str (Zeile) oder TBlock

    def blocks(self):
        return [s for s in self.segs if isinstance(s, TBlock)]

    @staticmethod
    def _finish(b):
        b.head.p = Proj.of_local(b.head.text, b.head.done, b.notes)
        for s in b.subs:
            s.p = Proj.of_local(s.text, s.done, None)

    @staticmethod
    def parse(content):
        """Wie parse() in todo.js: eingerueckte Zeilen unter einem Punkt sind Unteraufgaben (Checkbox) oder Notizen."""
        d = TodoDoc()
        if content[:1] == "﻿":
            d.bom, content = "﻿", content[1:]
        d.nl = "\r\n" if "\r\n" in content else "\n"
        cur, cur_indent, blanks = None, 0, []
        for line in content.replace("\r\n", "\n").split("\n"):
            blank = not line.strip()
            m = CHECK.match(line)
            if cur is not None and not blank and indent_of(line) > cur_indent:
                cur.children += blanks
                blanks = []
                if m:
                    s = TItem.from_match(line, m, True, cur)
                    cur.children.append(s)
                    cur.subs.append(s)
                else:
                    cur.children.append(line)
                    cur.notes.append(re.sub(r"^[-*+] ", "", line.lstrip()))
                continue
            if cur is not None and blank:
                blanks.append(line)
                continue
            d.segs += blanks
            blanks = []
            if cur is not None:
                TodoDoc._finish(cur)
            if m:
                cur = TBlock()
                cur.head = TItem.from_match(line, m, False, cur)
                cur_indent = indent_of(line)
                d.segs.append(cur)
            else:
                cur = None
                d.segs.append(line)
        d.segs += blanks
        if cur is not None:
            TodoDoc._finish(cur)
        return d

    def serialize(self):
        lines = []
        for s in self.segs:
            if isinstance(s, TBlock):
                lines += s.lines()
            else:
                lines.append(s)
        return self.bom + self.nl.join(lines)


# ---------- gemeinsamer Stand (google-sync.json) ----------
class Entry:
    def __init__(self, p, parent=""):
        self.p, self.parent = p, parent


class SyncState:
    def __init__(self, lst="", todo=""):
        self.list, self.todo = lst, todo
        self.items = {}
        self.order = []             # Reihenfolge der offenen Punkte beim letzten Abgleich
        self.pending = {}           # neu angelegt, Kennung evtl. noch nicht in der Datei

    @staticmethod
    def load(path):
        s = SyncState()
        try:
            txt = read_text(path)
            if txt is None:
                return s
            d = json.loads(txt)
            s.list, s.todo = d.get("list") or "", d.get("todo") or ""
            for k, v in (d.get("items") or {}).items():
                s.items[k] = Entry(Proj.from_json(v.get("p") or {}), v.get("par") or "")
            s.order = list(d.get("order") or [])
            s.pending = dict(d.get("pending") or {})
        except (ValueError, AttributeError) as e:
            log("google-sync.json unlesbar, Abgleich beginnt neu: " + str(e))
            s = SyncState()
        return s

    def save(self, path):
        write_text(path, json.dumps({"v": 1, "list": self.list, "todo": self.todo,
                                     "items": {k: {"p": e.p.to_json(), "par": e.parent} for k, e in self.items.items()},
                                     "order": self.order, "pending": self.pending}, ensure_ascii=False))


# ---------- ein Abgleich-Durchlauf ----------
class GoogleSync:
    def __init__(self, todo, archive, lst, state_path, api, create_if_missing=False, allow_mass=False):
        self.todo, self.archive, self.list, self.state_path, self.api = todo, archive, lst, state_path, api
        self.create_if_missing, self.allow_mass = create_if_missing, allow_mass
        self.suspicious = None
        self.reopened = set()
        self.st = None
        self.final = None           # Inhalt der Datei nach diesem Durchlauf
        self.n = dict(created=0, patched=0, deleted=0, pulled=0, added=0, archived=0, moved=0, reordered=0)

    def summary(self):
        n = self.n
        return ("neu bei Google %d, geaendert bei Google %d, geloescht bei Google %d, neu in der Datei %d, geaendert in der Datei %d, ins Archiv %d, verschoben bei Google %d%s"
                % (n["created"], n["patched"], n["deleted"], n["added"], n["pulled"], n["archived"], n["moved"], ", Datei umsortiert" if n["reordered"] else ""))

    def activity(self):
        return sum(self.n.values())

    def run(self):
        try:
            return self._run()
        except Exception:
            # Fehler mitten im Abgleich: schon bei Google angelegte Eintraege merken, damit sie nicht doppelt angelegt werden
            if self.st is not None and self.st.pending:
                try:
                    self._save_pending()
                except OSError:
                    pass
            raise

    def _save_pending(self):
        keep = SyncState.load(self.state_path)
        if keep.list != self.list:
            keep = SyncState(self.list, self.todo)
        keep.pending.update(self.st.pending)
        keep.save(self.state_path)

    def _run(self):
        c0 = stable_read(self.todo)
        if c0 is None:
            if not self.create_if_missing:
                log("Todo-Datei fehlt - Abgleich ausgesetzt")
                return False
            c0 = ""
        file_time = os.path.getmtime(self.todo) if os.path.exists(self.todo) else 0
        self.doc = TodoDoc.parse(c0 if c0 else "# Todo\n")
        st = SyncState.load(self.state_path)
        if st.list != self.list or os.path.realpath(st.todo or "") != os.path.realpath(self.todo):
            if st.list:
                log("andere Liste oder Datei - Abgleich beginnt neu")
            st = SyncState(self.list, self.todo)
        self.st = st
        self.archive_blocks = []

        # Stand bei Google
        rl = self.api.tasks(self.list)
        self.remote = {r.id: r for r in rl}
        self.rorder = {}
        for r in sorted(rl, key=lambda x: x.position):
            self.rorder.setdefault(r.parent or "", []).append(r.id)

        # Stand in der Datei
        self.local = {}
        items = 0
        for b in self.doc.blocks():
            self._register(b.head)
            items += 1
            for s in b.subs:
                self._register(s)
                items += 1
        # Schutz: Datei ohne Punkte, obwohl beim letzten Mal welche da waren -> lieber nichts tun
        if items == 0 and len(st.items) >= 3:
            log("Todo-Datei ohne Punkte - Abgleich ausgesetzt (Schutz)")
            return False
        self._adopt_pending()
        self._adopt_same()

        # Schutz: verschwinden viele offene Eintraege auf einmal, erst mal nichts loeschen (30 Minuten, siehe cmd_sync)
        open_known = sum(1 for e in st.items.values() if not e.p.done)
        gone_local = sum(1 for k, e in st.items.items() if not e.p.done and k not in self.local and k in self.remote)
        gone_remote = sum(1 for k, e in st.items.items() if not e.p.done and k in self.local and k not in self.remote)
        if not self.allow_mass and (gone_local >= 5 or gone_remote >= 5) and max(gone_local, gone_remote) * 2 >= open_known:
            self.suspicious = ("In der Datei fehlen auf einmal %d Einträge – bei Google wird vorerst nichts gelöscht." % gone_local if gone_local >= gone_remote
                               else "Bei Google fehlen auf einmal %d Einträge – in der Datei wird vorerst nichts entfernt." % gone_remote)
            log("Schutz: %d Eintraege fehlen in der Datei, %d bei Google (von %d offenen)" % (gone_local, gone_remote, open_known))
            return False

        # 1. bekannte Eintraege: erst Punkte, dann Unteraufgaben
        for tid in [k for k, e in st.items.items() if e.parent == ""]:
            self._known(tid)
        for tid in [k for k, e in st.items.items() if e.parent != ""]:
            if tid in st.items:
                self._known(tid)

        # 2. neu bei Google (erst Punkte, dann Unteraufgaben; in Schritt 1 geloeschte nicht gleich wieder hereinholen)
        by_pos = sorted(rl, key=lambda x: x.position)
        for r in [x for x in by_pos if x.parent is None] + [x for x in by_pos if x.parent is not None]:
            if r.id not in st.items and r.id in self.remote:
                self._remote_new(self.remote[r.id], file_time)

        # Kennungen, die es bei Google nicht (mehr) gibt (andere Liste, alter Stand): wie neu behandeln
        for tid, it in list(self.local.items()):
            if tid not in self.remote and tid not in st.items:
                it.id = None
                it.marker_changed = True
                del self.local[tid]

        # 3. neu in der Datei
        for b in self.doc.blocks():
            if b.head.id is None:
                self._create_remote(b.head, None, b)
            for s in b.subs:
                if s.id is None:
                    self._create_remote(s, b.head.id, b)

        # 4. Gliederung und Reihenfolge
        self._fix_parents()
        self._sync_order()

        # 5. Datei schreiben - nur, wenn sie seit dem Lesen niemand geaendert hat
        c1 = self.doc.serialize()
        if not c0 and not self.doc.blocks():
            c1 = c0
        if c1 != c0:
            if (read_text(self.todo) or "") != c0:
                log("Datei wurde waehrend des Abgleichs geaendert - naechster Durchlauf")
                self._save_pending()
                return False
            write_text(self.todo, c1)
        if self.archive_blocks and self.archive:
            try:
                write_text(self.archive, append_archive(read_text(self.archive), self.archive_blocks))
            except OSError as e:
                log("Archiv nicht geschrieben: " + str(e))
        st.pending.clear()
        st.order = [b.head.id for b in self.doc.blocks() if b.head.id is not None and not b.head.p.done]
        st.save(self.state_path)
        self.final = c1
        return True

    def _register(self, it):
        if it.id is None:
            return
        if it.id in self.local:         # kopierte Zeile: zweite ist neu
            it.id = None
            it.marker_changed = True
            return
        self.local[it.id] = it

    def _adopt_pending(self):
        """Nach einem abgebrochenen Durchlauf: neu angelegte Eintraege an ihrem Text wiedererkennen."""
        if not self.st.pending:
            return
        for b in self.doc.blocks():
            for it in [b.head] + b.subs:
                if it.id is not None:
                    continue
                text = strip_marker(it.text)
                for k, v in self.st.pending.items():
                    if v == text and k in self.remote and k not in self.local:
                        it.id = k
                        it.marker_changed = True
                        self.local[k] = it
                        break

    def _adopt_same(self):
        """Zeilen ohne gueltige Kennung an Titel, Datum und Status wiedererkennen, statt sie doppelt anzulegen
        (Liste hin- und zurueckgewechselt, Datei ohne Kennungen mit einer schon gefuellten Liste verbunden)."""
        free = [r for r in self.remote.values() if r.id not in self.st.items and r.id not in self.local]
        if not free:
            return

        def adopt(it, parent):
            if not it.p.title or (it.id is not None and (it.id in self.remote or it.id in self.st.items)):
                return
            for r in free:
                if (r.parent or "") != parent:
                    continue
                p = Proj.of_remote(r, it.is_sub)
                if p.title == it.p.title and p.due == it.p.due and p.done == it.p.done:
                    if it.id is not None:
                        self.local.pop(it.id, None)
                    it.id, it.marker_changed = r.id, True
                    self.local[r.id] = it
                    free.remove(r)
                    return

        for b in self.doc.blocks():
            adopt(b.head, "")
            if b.head.id is not None:
                for s in b.subs:
                    adopt(s, b.head.id)

    @staticmethod
    def _parent_of(it):
        return (it.block.head.id or "") if it.is_sub else ""

    def _known(self, tid):
        st = self.st
        e = st.items[tid]
        L, R = self.local.get(tid), self.remote.get(tid)
        if L is None and R is None:
            del st.items[tid]
            return
        if L is None:
            # in der Datei weg (archiviert oder geloescht)
            sub = R.parent is not None
            pr = Proj.of_remote(R, sub)
            pr.align(e.p)
            if not pr.same(e.p):
                # bei Google inzwischen geaendert -> nicht loeschen, sondern wieder in die Datei holen
                if not sub:
                    self._add_block(R, pr, True)
                else:
                    parent = self.local.get(R.parent)
                    if parent is None or parent.is_sub:
                        self._delete_remote(tid)
                        return
                    self._add_sub(parent.block, R, pr)
                st.items[tid] = Entry(pr, R.parent if sub else "")
                return
            self._delete_remote(tid)
            return
        if R is None:
            # bei Google geloescht
            if not L.p.same(e.p) or (L.is_sub and L.block.head.id is None):
                # in der Datei inzwischen geaendert (oder Unteraufgabe eines solchen Punkts) -> bei Google neu anlegen
                del self.local[tid]
                L.id = None
                L.marker_changed = True
                del st.items[tid]
                return
            self._remove_local(L)
            del st.items[tid]
            return
        prr = Proj.of_remote(R, L.is_sub)
        prr.align(L.p)
        merged = Proj.merge(e.p, L.p, prr, True)
        self._apply(L, R, merged, prr)
        st.items[tid] = Entry(merged, self._parent_of(L))

    def _delete_remote(self, tid):
        self.api.delete(self.list, tid)
        for kid in self.rorder.pop(tid, []):      # Google loescht die Unteraufgaben mit
            self.remote.pop(kid, None)
            self.st.items.pop(kid, None)
        self.remote.pop(tid, None)
        for l in self.rorder.values():
            if tid in l:
                l.remove(tid)
        self.st.items.pop(tid, None)
        self.n["deleted"] += 1

    def _apply(self, L, R, merged, pr):
        if not merged.same(L.p):
            if merged.done and not L.p.done:
                L.done_date = R.completed_day()
            if not L.is_sub and merged.notes_key != L.p.notes_key:
                L.block.dirty = True
            L.p = merged
            L.dirty = True
            self.n["pulled"] += 1
        if not merged.same(pr):
            nr = self.api.patch(self.list, R.id, self._body(merged, R, L.is_sub, True))
            if nr is not None:
                self.remote[R.id] = nr
            self.n["patched"] += 1
            # wieder geoeffnet: Google setzt die Aufgabe dabei selbst woanders hin -> in _sync_order zurueck an ihren Platz
            if pr.done and not merged.done:
                for l in self.rorder.values():
                    if R.id in l:
                        l.remove(R.id)
                self.reopened.add(R.id)

    @staticmethod
    def _body(p, existing, sub, patch):
        """Inhalt fuer Google: Notizen + Schlusszeile mit den Zusatzangaben."""
        d = {"title": fit_title(p.title)}
        lines = []
        if sub:
            if existing is not None:
                lines += fit_notes(split_notes(existing.notes)[0], p.meta)
        else:
            lines += fit_notes(p.notes, p.meta)
        if p.meta:
            lines.append(trailer(p.meta))
        notes = "\n".join(lines)
        if notes:
            d["notes"] = notes
        elif patch:
            d["notes"] = None
        # Datum nur schicken, wenn es sich geaendert hat: eine in Googles App gesetzte Uhrzeit soll dabei nicht verloren gehen
        if p.due != (existing.due if existing is not None else ""):
            d["due"] = p.due + "T00:00:00.000Z" if p.due else None
        d["status"] = "completed" if p.done else "needsAction"
        if not p.done and patch:
            d["completed"] = None
        return d

    # ---------- Aenderungen an der Datei ----------
    def _remove_local(self, L):
        b = L.block
        if not L.is_sub:
            self.archive_blocks.append(archive_block(b.lines(), b.head.indent, not L.p.done))
            self.doc.segs = [s for s in self.doc.segs if s is not b]
            self.local.pop(L.id, None)
            for s in b.subs:
                if s.id is not None:
                    self.local.pop(s.id, None)
        else:
            self.archive_blocks.append(archive_block([L.output()], L.indent, not L.p.done, " · Unteraufgabe von „" + b.head.p.title + "“"))
            b.subs.remove(L)
            b.children = [c for c in b.children if c is not L]
            self.local.pop(L.id, None)
        self.n["archived"] += 1

    def _add_block(self, r, p, with_children):
        head = TItem()
        head.id, head.p, head.dirty = r.id, p, True
        if p.done:
            head.done_date = r.completed_day()
        b = TBlock()
        b.head, b.dirty = head, True
        head.block = b
        at = self._insert_index(r.id)
        if at > 0 and not isinstance(self.doc.segs[at - 1], TBlock) and self.doc.segs[at - 1].lstrip().startswith("#"):
            self.doc.segs.insert(at, "")          # Leerzeile unter einer Ueberschrift
            at += 1
        self.doc.segs.insert(at, b)
        self.local[r.id] = head
        self.n["added"] += 1
        if not with_children:
            return
        for kid in self.rorder.get(r.id, []):     # wieder hereingeholter Punkt: seine Unteraufgaben gleich mit
            kr = self.remote.get(kid)
            if kr is None or kid in self.local:
                continue
            kp = Proj.of_remote(kr, True)
            self._add_sub(b, kr, kp)
            self.st.items[kid] = Entry(kp, r.id)

    def _insert_index(self, tid):
        """Platz fuer einen neuen Punkt: hinter seinem Vorgaenger bei Google, sonst vor dem ersten Punkt, sonst ans Ende."""
        ord_ = self.rorder.get("", [])
        if tid in ord_:
            for i in range(ord_.index(tid) - 1, -1, -1):
                t = self.local.get(ord_[i])
                if t is not None and not t.is_sub and t.block in self.doc.segs:
                    return self.doc.segs.index(t.block) + 1
        for i, s in enumerate(self.doc.segs):
            if isinstance(s, TBlock):
                return i
        end = len(self.doc.segs)
        while end > 0 and not isinstance(self.doc.segs[end - 1], TBlock) and not self.doc.segs[end - 1].strip():
            end -= 1
        return end

    def _add_sub(self, b, r, p):
        s = TItem()
        s.id, s.p, s.dirty, s.is_sub, s.block, s.indent = r.id, p, True, True, b, b.head.indent + "    "
        if p.done:
            s.done_date = r.completed_day()
        at = 0
        ord_ = self.rorder.get(r.parent or "", [])
        if r.id in ord_:
            for i in range(ord_.index(r.id) - 1, -1, -1):
                j = next((n for n, x in enumerate(b.subs) if x.id == ord_[i]), -1)
                if j >= 0:
                    at = j + 1
                    break
        b.subs.insert(at, s)
        b.dirty = True
        self.local[r.id] = s
        self.n["added"] += 1

    def _remote_new(self, r, file_time):
        sub = r.parent is not None
        L = self.local.get(r.id)
        if L is not None:
            # Kennung steht schon in der Datei, aber es gibt keinen gemeinsamen Stand (anderer PC, neu eingerichtet):
            # je Feld zusammenfuehren, bei Streit gewinnt die neuere Seite
            pr = Proj.of_remote(r, L.is_sub)
            pr.align(L.p)
            merged = Proj.merge(None, L.p, pr, r.updated <= file_time)
            self._apply(L, r, merged, pr)
            self.st.items[r.id] = Entry(merged, self._parent_of(L))
            return
        if not r.title.strip():
            return                 # leere Aufgabe (wird gerade in der Google-App getippt)
        p = Proj.of_remote(r, sub)
        if not sub:
            if r.done:
                return             # alte erledigte Aufgaben von Google nicht nachtragen
            self._add_block(r, p, False)
        else:
            parent = self.local.get(r.parent)
            if parent is None or parent.is_sub:
                return
            self._add_sub(parent.block, r, p)
        self.st.items[r.id] = Entry(p, r.parent if sub else "")

    def _create_remote(self, it, parent_id, b):
        if it.is_sub and parent_id is None:
            return
        if not it.p.title:
            return                 # leere Checkbox (wird gerade in Obsidian getippt)
        prev = None
        if not it.is_sub:
            for x in self.doc.blocks():
                if x is b:
                    break
                if x.head.id is not None:
                    prev = x.head.id
        else:
            for x in b.subs:
                if x is it:
                    break
                if x.id is not None:
                    prev = x.id
        r = self.api.insert(self.list, self._body(it.p, None, it.is_sub, False), parent_id, prev)
        it.id = r.id
        it.marker_changed = True
        self.remote[r.id] = r
        self.local[r.id] = it
        self._insert_order(parent_id or "", r.id, prev)
        self.st.items[r.id] = Entry(it.p.clone(), parent_id or "")
        self.st.pending[r.id] = strip_marker(it.text)
        try:
            self._save_pending()   # sofort merken: wird das Programm jetzt beendet, wird der Eintrag trotzdem wiedererkannt
        except OSError:
            pass
        self.n["created"] += 1

    # ---------- Reihenfolge ----------
    def _insert_order(self, parent, tid, prev):
        for l in self.rorder.values():
            if tid in l:
                l.remove(tid)
        lst = self.rorder.setdefault(parent, [])
        at = lst.index(prev) + 1 if prev in lst else 0
        lst.insert(at, tid)

    def _move_remote(self, tid, parent, prev):
        """False: Google lehnt die Verschiebung ab (z. B. Aufgabe mit Unteraufgaben unter eine andere) - dann bleibt es so."""
        try:
            nr = self.api.move(self.list, tid, parent or None, prev)
        except GoogleError as e:
            if e.code != 400:
                raise
            log("Verschieben abgelehnt: " + str(e))
            return False
        if nr is not None:
            self.remote[tid] = nr
        self._insert_order(parent, tid, prev)
        self.n["moved"] += 1
        return True

    def _fix_parents(self):
        for b in self.doc.blocks():
            self._check_parent(b.head, "")
            if b.head.id is None:
                continue
            for s in b.subs:
                self._check_parent(s, b.head.id)

    def _check_parent(self, it, want):
        r = self.remote.get(it.id) if it.id is not None else None
        if r is None or (r.parent or "") == want:
            return
        if self._move_remote(it.id, want, None) and it.id in self.st.items:
            self.st.items[it.id].parent = want

    def _sync_order(self):
        # wieder geoeffnete Aufgaben an ihren Platz in der Datei setzen (in Dateireihenfolge, der Vorgaenger steht dann schon)
        if self.reopened:
            prev_head = None
            for b in self.doc.blocks():
                if b.head.id is None:
                    continue
                if b.head.id in self.reopened:
                    self._move_remote(b.head.id, "", prev_head)
                if not b.head.p.done:
                    prev_head = b.head.id
                prev_sub = None
                for s in b.subs:
                    if s.id is None:
                        continue
                    if s.id in self.reopened:
                        self._move_remote(s.id, b.head.id, prev_sub)
                    if not s.p.done:
                        prev_sub = s.id
        # Punkte: wer hat seit dem letzten Abgleich umsortiert? Datei gewinnt, wenn beide. Nur offene Eintraege.
        have_top = self.rorder.setdefault("", [])
        local_seq = [b.head.id for b in self.doc.blocks() if b.head.id is not None and not b.head.p.done]
        common = {t for t in local_seq if t in have_top}
        l1 = [t for t in local_seq if t in common]
        r1 = [t for t in have_top if t in common]
        if l1 != r1:
            b1 = [t for t in self.st.order if t in common]
            in_base = set(b1)
            local_changed = [t for t in l1 if t in in_base] != b1
            remote_changed = [t for t in r1 if t in in_base] != b1
            if local_changed or not remote_changed:
                self._push_order("", l1, r1)
            else:
                self._pull_order(r1)
        # Unteraufgaben: immer wie in der Datei
        for b in self.doc.blocks():
            if b.head.id is None:
                continue
            have = self.rorder.setdefault(b.head.id, [])
            want = [s.id for s in b.subs if s.id is not None and not s.p.done and s.id in have]
            cur = [t for t in have if t in want]
            if want != cur:
                self._push_order(b.head.id, want, cur)

    def _push_order(self, parent, want, have):
        """Google so umsortieren wie want: die laengste schon richtig liegende Folge bleibt, der Rest wird verschoben."""
        n = len(want)
        pos = [have.index(t) for t in want]
        length, prev_idx, best = [1] * n, [-1] * n, -1
        for i in range(n):
            for j in range(i):
                if pos[j] < pos[i] and length[j] + 1 > length[i]:
                    length[i], prev_idx[i] = length[j] + 1, j
            if best < 0 or length[i] > length[best]:
                best = i
        keep = set()
        i = best
        while i >= 0:
            keep.add(i)
            i = prev_idx[i]
        for k in range(n):
            if k not in keep:
                self._move_remote(want[k], parent, want[k - 1] if k > 0 else None)

    def _pull_order(self, want):
        """Datei so umsortieren wie bei Google (nur die verbundenen Punkte; ihre Plaetze in der Datei bleiben)."""
        slots = [i for i, s in enumerate(self.doc.segs) if isinstance(s, TBlock) and s.head.id in want]
        if len(slots) != len(want):
            return
        by_id = {self.doc.segs[i].head.id: self.doc.segs[i] for i in slots}
        for k, i in enumerate(slots):
            self.doc.segs[i] = by_id[want[k]]
        self.n["reordered"] += 1


# ---------- Ein Vault auf zwei PCs (Nextcloud): nur einer gleicht mit Google ab ----------
# ".taskboard-sync" neben der Todo.md: "<PC>\t<Unix-Zeit>" (wie src/google.cs). Der andere PC haelt sich zurueck,
# solange die Datei juenger als 20 Minuten ist; alle 5 Minuten wird sie erneuert.
OWNER_RENEW, OWNER_STALE = 300, 1200


def other_owner(todo_file):
    try:
        f = os.path.join(os.path.dirname(todo_file), ".taskboard-sync")
        me = socket.gethostname()
        now = int(time.time())
        p = (read_text(f) or "").strip().split("\t")
        valid = len(p) == 2 and p[1].isdigit()
        if valid and p[0] != me and now - int(p[1]) < OWNER_STALE:
            return p[0]
        if not valid or p[0] != me or now - int(p[1]) >= OWNER_RENEW:
            write_text(f, me + "\t" + str(now))
    except OSError:
        pass
    return None


# ---------- Einstellungen ----------
class Conf:
    def __init__(self):
        c, g = read_kv(CONF), read_kv(GCONF)
        self.todo, self.archive = c.get("TODO_FILE", ""), c.get("ARCHIVE_FILE", "")
        self.vault, self.vault_name = c.get("VAULT", ""), c.get("VAULT_NAME", "")
        self.google_on = g.get("GOOGLE_ON") == "1"
        self.obsidian_on = g.get("OBSIDIAN_ON", "1") != "0"
        self.list, self.list_name = g.get("GOOGLE_LIST", ""), g.get("GOOGLE_LIST_NAME", "")
        self.vault_todo, self.vault_archive = g.get("VAULT_TODO_FILE", ""), g.get("VAULT_ARCHIVE_FILE", "")


def clean_name(s):
    return re.sub(r"[\r\n\t]", " ", s or "").replace('"', "'")


# ---------- Dialoge (kdialog, sonst Terminal) ----------
def have_kdialog():
    return shutil.which("kdialog") is not None and not os.environ.get("TASKBOARD_NO_GUI")


def pick_list(api, current):
    """Liste waehlen: (id, name), None = abgebrochen. Eine neue Liste wird hier angelegt."""
    lists = [(l["id"], clean_name(l.get("title"))) for l in api.lists()]
    have_tb = any(n == "Task Board" for _, n in lists)
    new_name = "Task Board (neu)" if have_tb else "Task Board"
    preset = current if any(i == current for i, _ in lists) else next((i for i, n in lists if n == "Task Board"), "__new__")
    if have_kdialog():
        args = ["kdialog", "--title", "Task Board – Google-Liste", "--radiolist",
                "In welcher Google-Liste sollen deine Aufgaben liegen?\nAndere Listen in deinem Google-Konto bleiben unberührt."]
        for i, n in lists:
            args += [i, n, "on" if i == preset else "off"]
        args += ["__new__", "Neue Liste anlegen: „" + new_name + "“", "on" if preset == "__new__" else "off"]
        r = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, universal_newlines=True)
        if r.returncode != 0:
            return None
        sel = r.stdout.strip()
    else:
        print("In welcher Google-Liste sollen deine Aufgaben liegen?")
        for n, (i, name) in enumerate(lists):
            print("  %d) %s" % (n + 1, name))
        print("  %d) Neue Liste anlegen: %s" % (len(lists) + 1, new_name))
        try:
            a = input("Nummer: ").strip()
        except EOFError:
            return None
        if not a.isdigit() or not 1 <= int(a) <= len(lists) + 1:
            return None
        sel = lists[int(a) - 1][0] if int(a) <= len(lists) else "__new__"
    if sel == "__new__":
        created = api.new_list(new_name)
        return created["id"], new_name
    return sel, next(n for i, n in lists if i == sel)


def login_with_dialog(auth):
    """Browser-Anmeldung. Ein kleines Fenster bietet "Seite nochmal öffnen" (Tab geschlossen) und "Abbrechen"."""
    text = ("Dein Browser öffnet sich. Bitte melde dich dort bei Google an und erlaube Task Board den Zugriff.\n\n"
            "Bei „Google hat diese App nicht überprüft“: auf „Erweitert“ und dann auf „Zu Task Board wechseln“ klicken.")
    gui = have_kdialog()
    dlg = [None]

    def show():
        dlg[0] = subprocess.Popen(["kdialog", "--title", "Task Board – Anmeldung bei Google", "--yes-label", "Seite nochmal öffnen",
                                   "--no-label", "Abbrechen", "--yesno", text], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def cancelled():
        rc = dlg[0].poll() if gui else None
        return rc is not None and rc != 0

    def clear_again():
        try:
            os.remove(AGAIN)
            return True
        except OSError:
            return False

    def reopen():
        asked = False
        if gui and dlg[0].poll() == 0:      # Knopf gedrueckt: Fenster schliesst sich, also neu zeigen
            show()
            asked = True
        return clear_again() or asked

    clear_again()
    if gui:
        show()
    else:
        print("Dein Browser öffnet sich – bitte bei Google anmelden und Task Board erlauben ...")
    try:
        # eine Stunde: Familienkonten brauchen die Zustimmung der Eltern, und das Fenster hat einen Abbrechen-Knopf
        return auth.login(3600, cancelled=cancelled, reopen=reopen)
    finally:
        if gui and dlg[0].poll() is None:
            dlg[0].terminate()


def take_login_lock():
    """Nur eine wartende Anmeldung. None = es wartet schon eine."""
    os.makedirs(DATA_DIR, exist_ok=True)
    f = open(os.path.join(DATA_DIR, "google-login.lock"), "w")
    try:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return f
    except OSError:
        f.close()
        return None


def turn_on(pick):
    lock = need_lock()
    c = Conf()
    if c.list != pick[0] and not c.obsidian_on:
        # nur Google: die Kopie auf diesem PC gehoert zur alten Liste - sie wird aus der neuen Liste neu gefuellt
        write_text(LOCAL_TODO, "# Todo\n")
        try:
            os.remove(STATE)
        except OSError:
            pass
    set_kv(GCONF, {"GOOGLE_ON": "1", "GOOGLE_LIST": pick[0], "GOOGLE_LIST_NAME": pick[1]})
    write_status("ok", "Verbunden · Liste „" + pick[1] + "“ · wird abgeglichen …", True)
    log("Liste gewaehlt: " + pick[0])


def take_lock(wait):
    """Immer nur einer: ein Abgleich oder ein Umschalten. Gibt die offene Sperre zurueck, None = gerade belegt."""
    os.makedirs(DATA_DIR, exist_ok=True)
    f = open(os.path.join(DATA_DIR, "google.lock"), "w")
    until = time.time() + wait
    while True:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return f
        except OSError:
            if time.time() >= until:
                f.close()
                return None
            time.sleep(0.2)


def need_lock():
    lock = take_lock(60)
    if lock is None:
        raise GoogleError("der Abgleich läuft noch – bitte gleich nochmal versuchen", 0)
    return lock


def store_switch(to):
    """google: Obsidian aus (Liste liest die Kopie). obsidian: Obsidian an (Kopie zurueck in den Vault, alte Fassung gesichert)."""
    c = Conf()
    if to == "google":
        if not c.obsidian_on:
            return "ok"
        if not c.google_on:
            return "fehler: erst mit Google verbinden"
        src = read_text(c.todo)
        if src is not None:
            write_text(LOCAL_TODO, src)
        elif not os.path.exists(LOCAL_TODO):
            write_text(LOCAL_TODO, "# Todo\n")
        if not os.path.exists(LOCAL_ARCHIVE):
            write_text(LOCAL_ARCHIVE, "")
        set_kv(GCONF, {"OBSIDIAN_ON": "0", "VAULT_TODO_FILE": c.todo, "VAULT_ARCHIVE_FILE": c.archive})
        set_kv(CONF, {"TODO_FILE": LOCAL_TODO, "ARCHIVE_FILE": LOCAL_ARCHIVE})
        _move_state(LOCAL_TODO)
        return "ok"
    if c.obsidian_on:
        return "ok"
    todo, archive = c.vault_todo, c.vault_archive
    if not todo:
        return "kein-vault"
    if not archive:
        archive = os.path.join(os.path.dirname(todo), "Todo-Archiv.md")
    cur = read_text(LOCAL_TODO)
    if cur is not None:
        old = read_text(todo)
        if old is not None and old != cur:
            write_text(os.path.join(DATA_DIR, "Sicherung", "Todo-" + datetime.now().strftime("%Y%m%d-%H%M%S") + ".md"), old)
        write_text(todo, cur)
    # Archiv der Kopie an das Archiv im Vault anhaengen
    la = read_text(LOCAL_ARCHIVE)
    if la and la.strip():
        blocks = []
        for l in la.replace("\r\n", "\n").split("\n"):
            if CHECK.match(l) or re.match(r"^\s*[-*+] \[-\]", l):
                blocks.append([l])
            elif blocks and l.strip() and l.startswith(" "):
                blocks[-1].append(l)
        if blocks:
            write_text(archive, append_archive(read_text(archive), blocks))
        write_text(LOCAL_ARCHIVE, "")
    set_kv(GCONF, {"OBSIDIAN_ON": "1"})
    set_kv(CONF, {"TODO_FILE": todo, "ARCHIVE_FILE": archive})
    _move_state(todo)
    return "ok"


def _move_state(todo):
    """Der gemeinsame Stand gilt fuer die neue Datei weiter (gleicher Inhalt) - sonst begaenne der Abgleich neu."""
    if os.path.exists(STATE):
        s = SyncState.load(STATE)
        s.todo = todo
        s.save(STATE)


def cmd_sync():
    """Ein Abgleich mit der eingestellten Liste. Das Widget ruft das auf; es laeuft immer nur einer."""
    lock = take_lock(0)
    if lock is None:
        return 0
    c = Conf()
    auth = GoogleAuth.load()
    connected = auth is not None and auth.connected
    if not c.google_on or not c.list or auth is None:
        write_status("aus", "Abgleich mit Google ist ausgeschaltet." if connected else "Nicht mit Google verbunden.", connected)
        return 0
    if not connected:
        write_status("abgemeldet", "Google-Zugang abgelaufen oder entfernt – bitte neu verbinden.", False)
        return 0
    if c.obsidian_on:
        other = other_owner(c.todo)
        if other:
            # der andere PC gleicht diesen Vault gerade ab; unsere Aenderungen kommen ueber die Nextcloud zu ihm
            write_status("ok", "Verbunden · Abgleich läuft gerade auf „" + other + "“", True)
            return 0
    # Schutz gegen Massen-Loeschen: seit wann?
    since = 0
    try:
        since = int((read_text(GUARD) or "0").strip() or 0)
    except ValueError:
        pass
    api = TasksApi(auth)
    s = GoogleSync(c.todo, c.archive, c.list, STATE, api, create_if_missing=not c.obsidian_on, allow_mass=since and time.time() - since >= 1800)
    try:
        ok = s.run()
    except GoogleError as e:
        offline = e.code == 0
        if not offline:
            log("Abgleich: " + str(e))
        if e.code == 401:
            write_status("abgemeldet", "Google-Zugang abgelaufen oder entfernt – bitte neu verbinden.", False)
        elif e.code == 404:
            write_status("fehler", "Die Google-Liste gibt es nicht mehr – bitte eine Liste wählen.", True)
        else:
            write_status("offline" if offline else "fehler", "Keine Verbindung zu Google – wird nachgeholt." if offline else "Fehler bei Google – wird nochmal versucht.", True)
        return 1
    except Exception as e:
        log("Abgleich: interner Fehler %s: %s" % (type(e).__name__, str(e)[:200]))
        write_status("fehler", "Fehler beim Abgleich – wird nochmal versucht.", True)
        return 1
    if ok:
        if since:
            try:
                os.remove(GUARD)
            except OSError:
                pass
        if s.activity():
            log("Abgleich: " + s.summary() + " (%d Anfragen)" % api.calls)
        write_status("ok", "Verbunden · Liste „" + c.list_name + "“ · zuletzt abgeglichen " + datetime.now().strftime("%H:%M"), True)
        print(hashlib.md5(s.final.encode("utf-8")).hexdigest())     # das Widget erkennt daran sein "eigenes" Schreiben
        return 0
    if s.suspicious:
        if not since:
            write_text(GUARD, str(int(time.time())))
        write_status("fehler", s.suspicious, True)
    return 1


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "sync":
        return cmd_sync()
    auth = GoogleAuth.load()
    if auth is None:
        print("fehler: google-client.json fehlt")
        return 2
    api = TasksApi(auth)
    try:
        if cmd == "connect":
            out = argv[3] if len(argv) > 3 and argv[2] == "--out" else None
            login_lock = None
            if not auth.connected or out:
                login_lock = take_login_lock()
                if login_lock is None:      # wartet schon (z. B. Tab geschlossen und nochmal geklickt): dort die Seite nochmal oeffnen
                    write_text(AGAIN, "")
                    print("laeuft")
                    return 0
                if not login_with_dialog(auth):
                    log("Anmeldung fehlgeschlagen: " + str(auth.last_error))
                    if not out:
                        write_status("aus", "Nicht verbunden: " + str(auth.last_error), False)
                    print("fehler: " + str(auth.last_error))
                    return 1
                log("angemeldet")
            pick = pick_list(api, "" if out else Conf().list)
            if pick is None:
                print("abgebrochen")
                if not out:
                    write_status("aus", "Verbunden, aber noch keine Liste gewählt.", True)
                return 1
            if out:
                write_text(out, pick[0] + "\t" + pick[1])
            else:
                turn_on(pick)
            print("ok")
            return 0
        if cmd == "pick-list":
            pick = pick_list(api, Conf().list)
            if pick is None:
                print("abgebrochen")
                return 1
            turn_on(pick)
            print("ok")
            return 0
        if cmd == "disconnect":
            lock = need_lock()
            auth.logout()
            set_kv(GCONF, {"GOOGLE_ON": "0"})
            for f in (STATE, GUARD):
                try:
                    os.remove(f)
                except OSError:
                    pass
            write_status("aus", "Nicht mit Google verbunden.", False)
            log("Verbindung getrennt")
            print("ok")
            return 0
        if cmd == "login-again":
            write_text(AGAIN, "")
            print("ok")
            return 0
        if cmd == "logout":
            lock = need_lock()
            auth.logout()
            print("ok")
            return 0
        if cmd == "enable":
            on = len(argv) > 2 and argv[2] == "1"
            lock = need_lock()
            set_kv(GCONF, {"GOOGLE_ON": "1" if on else "0"})
            write_status("ok" if on else "aus", "Wird abgeglichen …" if on else "Abgleich mit Google ist ausgeschaltet.", auth.connected)
            print("ok")
            return 0
        if cmd == "store":
            lock = need_lock()
            r = store_switch(argv[2] if len(argv) > 2 else "")
            log("Speicherort: %s -> %s" % (argv[2] if len(argv) > 2 else "?", r))
            print(r)
            return 0 if r == "ok" else 1
        if cmd == "status":
            print("verbunden" if auth.connected else "nicht verbunden")
            return 0
        # ---------- Tests ----------
        if cmd == "lists":
            for l in api.lists():
                print(l["id"] + "\t" + l.get("title", ""))
            return 0
        if cmd == "newlist":
            print(api.new_list(argv[2])["id"])
            return 0
        if cmd == "sync-file":
            s = GoogleSync(argv[2], argv[3], argv[4], STATE, api)
            ok = s.run()
            print(("ok: " if ok else "abgebrochen: ") + s.summary() + " (%d Anfragen)" % api.calls)
            return 0 if ok else 1
        if cmd == "dump":
            all_ = api.tasks(argv[2])
            by_id = {t.id: t for t in all_}
            for t in sorted(all_, key=lambda x: x.position if not x.parent or x.parent not in by_id else by_id[x.parent].position + "/" + x.position):
                print(("    " if t.parent else "") + ("[x] " if t.done else "[ ] ") + t.title + (" | due " + t.due if t.due else "") +
                      (" | notes " + t.notes.replace("\n", " / ") if t.notes else "") + (" | hidden" if t.hidden else "") + " | id " + t.id)
            return 0
        if cmd == "api":
            body = json.loads(read_text(argv[4])) if len(argv) > 4 else None
            print(json.dumps(api.call(argv[2], argv[3], body), ensure_ascii=False))
            return 0
        if cmd == "parse":
            content = read_text(argv[2])
            d = TodoDoc.parse(content)
            print("unveraendert zusammengesetzt: " + ("ja" if d.serialize() == content else "NEIN"))
            for b in d.blocks():
                print(("[x] " if b.head.p.done else "[ ] ") + b.head.p.title + " | meta " + b.head.p.meta + " | due " + b.head.p.due + " | notes %d | id %s" % (len(b.head.p.notes), b.head.id or "-"))
                for s in b.subs:
                    print("    " + ("[x] " if s.p.done else "[ ] ") + s.p.title + " | meta " + s.p.meta + " | due " + s.p.due)
                m = CHECK.match("- [" + ("x" if b.head.p.done else " ") + "] " + line_text(b.head.p, b.head.done_date or today(), "TESTID"))
                if not Proj.of_local(m.group(4), m.group(3) != " ", b.head.p.notes).same(b.head.p) or id_of(m.group(4)) != "TESTID":
                    print("    !! neu geschrieben anders")
            return 0
    except GoogleError as e:
        log("Fehler: " + str(e))
        print("fehler: " + str(e))
        return 1
    print("unbekannter Befehl")
    return 2


if __name__ == "__main__":
    try:
        code = main(sys.argv)
    except Exception as e:      # nie einen Python-Fehlertext in die Oberflaeche
        log("interner Fehler %s: %s" % (type(e).__name__, str(e)[:200]))
        print("fehler: " + type(e).__name__)
        code = 1
    sys.exit(code)
