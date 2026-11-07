-- Einstellungen-Fenster (Config TaskBoard\Einstellungen): Tags verwalten und von Hand nach Updates suchen.
-- Alles andere im Fenster sind feste Knoepfe aus build-skin.ps1. Datei muss als UTF-16 LE gespeichert sein.
--
-- Tags stehen in prefs.inc als "Tags=arbeit:blau,privat:pink" (bleibt bei Updates erhalten).
-- Klick auf einen Tag = naechste Farbe, "×" = Tag entfernen, "+ Neuer Tag" = Name eintippen.

local ORDER = { 'lila', 'blau', 'gruen', 'orange', 'rot', 'pink', 'grau' }
local COL = {
	lila = { '138,108,245', '165,185,255' }, blau = { '60,130,240', '140,190,255' },
	gruen = { '50,170,100', '140,220,170' }, orange = { '235,135,40', '255,195,130' },
	rot = { '220,70,70', '255,160,160' }, pink = { '220,80,165', '255,165,215' },
	grau = { '140,140,154', '210,210,220' },
}
local MAX = 8
local LEFT, RIGHT = 22, 22 + 438       -- linke Spalte
local tags = {}
local drawn = false
local adding = false   -- "+ Neuer Tag"-Feld offen
local addBox          -- Flaeche von "+ Neuer Tag": { x, y, w, shape }

-- Rausklicken soll nichts loeschen: Eingabefelder haben FocusDismiss=0, dazu laeuft
-- "TaskBoardHotkey.exe --commit" (hotkey.cs). Verliert das Feld den Fokus, legt der Waechter commit.flag an
-- und drueckt Enter - der Text wird uebernommen. commitWatch() beim Oeffnen, wasCommit() beim Uebernehmen.
local watchAt = 0
local function commitWatch()
	local dir = SKIN:GetVariable('@')
	os.remove(dir .. 'commit.flag')
	watchAt = os.time()
	SKIN:Bang('["' .. dir .. 'TaskBoardHotkey.exe" --commit]')
end
-- Notbremse: Solange ein Feld offen ist, kommen Klicks auf Rainmeter-Fenster gar nicht an. Fehlt der
-- Waechter (Lebenszeichen watch.alive aelter als 3 s), haengt sonst alles -> Waechter neu starten.
local function keepWatch(open)
	if not open or os.time() - watchAt < 3 then return end
	local dir = SKIN:GetVariable('@')
	local fh = io.open(dir .. 'commit.flag', 'rb')
	if fh then fh:close() return end          -- Enter ist schon unterwegs
	fh = io.open(dir .. 'watch.alive', 'rb')
	local n = fh and tonumber(fh:read('*a'))
	if fh then fh:close() end
	if n and os.time() - n < 3 then return end
	watchAt = os.time()
	SKIN:Bang('["' .. dir .. 'TaskBoardHotkey.exe" --commit]')
end
local function wasCommit()
	local p = SKIN:GetVariable('@') .. 'commit.flag'
	local fh = io.open(p, 'rb')
	if not fh then return false end
	fh:close(); os.remove(p)
	return true
end

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

local function load()
	tags = {}
	for part in (SKIN:GetVariable('Tags') or ''):gmatch('[^,]+') do
		local name, col = part:match('^%s*(.-):(%a+)%s*$')
		if name and name ~= '' and #tags < MAX then tags[#tags + 1] = { name = name, color = COL[col] and col or 'grau' } end
	end
end

function Initialize() load() end

local function set(m, o, v) SKIN:Bang('!SetOption', m, o, v) end
local function show(m, on) SKIN:Bang(on and '!ShowMeter' or '!HideMeter', m) end

-- Tags unter "Tags" in Reihen anordnen, abgerundete Flaechen in TagShapes
local function render()
	local cap = SKIN:GetMeter('CapTags')
	if not cap then return end
	local y = cap:GetY() + cap:GetH() + 10
	local x = LEFT
	local shapes = {}
	local function place(m, w)
		if x > LEFT and x + w > RIGHT then x = LEFT; y = y + 42 end
		set(m, 'X', x); set(m, 'Y', y)
		local px = x
		x = x + w
		return px
	end
	for k = 1, MAX do
		local t, m, mx = tags[k], 'TagS' .. k, 'TagX' .. k
		if t then
			local c = COL[t.color]
			set(m, 'Text', t.name)
			set(m, 'FontColor', c[2] .. ',255')
			-- erst einblenden: versteckte Meter melden die Breite 0
			show(m, true); show(mx, true)
			SKIN:Bang('!UpdateMeter', m)
			SKIN:Bang('!UpdateMeter', mx)
			local w, wx = SKIN:GetMeter(m):GetW(), SKIN:GetMeter(mx):GetW()
			if x > LEFT and x + w + wx + 2 > RIGHT then x = LEFT; y = y + 42 end
			local px = place(m, w)
			shapes[#shapes + 1] = string.format('Rectangle %d.5,%d.5,%d,33,8 | Fill Color %s,60 | StrokeWidth 1 | Stroke Color %s,255', px, y, w - 1, c[1], c[1])
			x = x + 2
			local pxx = place(mx, wx)
			shapes[#shapes + 1] = string.format('Rectangle %d.5,%d.5,%d,33,8 | Fill Color 255,255,255,14 | StrokeWidth 1 | Stroke Color 255,255,255,38', pxx, y, wx - 1)
			x = x + 10
			show(m, true); show(mx, true)
		else
			show(m, false); show(mx, false)
		end
	end
	show('TagAdd', #tags < MAX)
	set('TagAdd', 'Text', '+ Neuer Tag')
	addBox = nil
	if #tags < MAX then
		SKIN:Bang('!UpdateMeter', 'TagAdd')
		local w = SKIN:GetMeter('TagAdd'):GetW()
		local px = place('TagAdd', w)
		addBox = { x = px, y = y, w = w, shape = #shapes + 1 }
		shapes[#shapes + 1] = string.format('Rectangle %d.5,%d.5,%d,33,8 | Fill Color 255,255,255,14 | StrokeWidth 1 | Stroke Color 255,255,255,38', px, y, w - 1)
	end
	y = y + 42
	set('TagInfo', 'Y', y)
	for k = 1, math.max(#shapes, 1) + MAX * 2 + 1 do
		set('TagShapes', k == 1 and 'Shape' or ('Shape' .. k), shapes[k] or 'Rectangle 0,0,0,0 | StrokeWidth 0')
	end
	SKIN:Bang('!UpdateMeter', '*')
	SKIN:Bang('!Redraw')
end

-- ---------- Speichern in: Obsidian / Google Tasks (Haekchen; mindestens eins an) ----------
-- Den Rest erledigt TaskBoardHotkey.exe (google.cs): --google-connect | --google-pick-list | --google-disconnect |
-- --google-store google|obsidian. Den Stand schreibt es nach google-status.txt (Zustand, verbunden, Text).
local gState, gConnected, gText, gStamp = 'aus', false, '', nil
local busy = false
local lastPoll = 0

local function readStatus()
	local fh = io.open(SKIN:GetVariable('@') .. 'google-status.txt', 'rb')
	if not fh then return false end
	local c = fh:read('*a')
	fh:close()
	if c == gStamp then return false end
	gStamp = c
	local st, conn, text = c:match('^([^\n]*)\n([^\n]*)\n(.*)$')
	if st then gState, gConnected, gText = st, conn == '1', text end
	return true
end

local function storeView()
	local obs = SKIN:GetVariable('ObsidianOn') ~= '0'
	local goo = SKIN:GetVariable('GoogleOn') == '1'
	set('StoreObsText', 'Text', (obs and '✓ ' or '') .. 'Obsidian')
	set('StoreGoogleText', 'Text', (goo and '✓ ' or '') .. 'Google Tasks')
	set('FileNow', 'Text', obs and (SKIN:GetVariable('TodoFile') or '') or 'Nur bei Google gespeichert (mit einer Kopie auf diesem PC).')
	show('File1', obs); show('File1Text', obs)
	if not busy then set('GoogleInfo', 'Text', gText ~= '' and gText or 'Nicht mit Google verbunden.') end
	show('GList', gConnected); show('GListText', gConnected)
	show('GOff', gConnected); show('GOffText', gConnected)
	SKIN:Bang('!UpdateMeter', '*')
	SKIN:Bang('!Redraw')
end

local function info(text)
	set('GoogleInfo', 'Text', text)
	SKIN:Bang('!UpdateMeter', 'GoogleInfo')
	SKIN:Bang('!Redraw')
end

local function runGoogle(args, text)
	busy = true
	info(text)
	SKIN:Bang('!SetOption', 'MeasureGoogle', 'Parameter', args)
	SKIN:Bang('!UpdateMeasure', 'MeasureGoogle')
	SKIN:Bang('!CommandMeasure', 'MeasureGoogle', 'Run')
end

local function poke()
	SKIN:Bang('["' .. SKIN:GetVariable('@') .. 'TaskBoardHotkey.exe" --google-sync-now]')
end

local function reloadAll()
	SKIN:Bang('!Refresh', 'TaskBoard')
	SKIN:Bang('!Refresh', 'TaskBoard\\Formular')
	SKIN:Bang('!Refresh')
end

function Store(which)
	readStatus()
	local obs = SKIN:GetVariable('ObsidianOn') ~= '0'
	local goo = SKIN:GetVariable('GoogleOn') == '1'
	if which == 'google' then
		if goo then
			if not obs then return info('Ohne Google braucht die Liste Obsidian – zuerst „Obsidian“ anhaken.') end
			SKIN:Bang('!WriteKeyValue', 'Variables', 'GoogleOn', '0', '#@#prefs.inc')
			poke()
			reloadAll()
		elseif gConnected and (SKIN:GetVariable('GoogleList') or '') ~= '' then
			SKIN:Bang('!WriteKeyValue', 'Variables', 'GoogleOn', '1', '#@#prefs.inc')
			poke()
			reloadAll()
		else
			runGoogle('--google-connect', 'Dein Browser öffnet sich – bitte bei Google anmelden und Task Board erlauben …')
		end
	else
		if obs then
			if not goo then return info('Mindestens ein Speicherort muss angehakt sein.') end
			runGoogle('--google-store google', 'Wird umgestellt …')
		else
			runGoogle('--google-store obsidian', 'Wird umgestellt …')
		end
	end
end

function GoogleRun(args)
	if args == '--google-pick-list' then runGoogle(args, 'Einen Moment – Listen werden geladen …')
	else runGoogle(args, 'Verbindung wird getrennt …') end
end

-- TaskBoardHotkey.exe ist fertig
function GoogleDone()
	busy = false
	local out = SKIN:GetMeasure('MeasureGoogle'):GetStringValue() or ''
	if out:find('kein%-vault') then
		return info('Es ist noch keine Todo-Datei in Obsidian eingerichtet – bitte „Andere Datei wählen …“ benutzen.')
	end
	reloadAll()
end

function Update()
	if not drawn then drawn = true; render(); readStatus(); storeView() end
	keepWatch(adding)
	local now = os.time()
	if now - lastPoll >= 2 then
		lastPoll = now
		if readStatus() then storeView() end
	end
	return 0
end

-- speichern, Liste und Formular neu laden (Farben/Etiketten), Fenster neu zeichnen
local function save()
	local parts = {}
	for _, t in ipairs(tags) do parts[#parts + 1] = t.name .. ':' .. t.color end
	local s = table.concat(parts, ',')
	SKIN:Bang('!SetVariable', 'Tags', s)
	SKIN:Bang('!WriteKeyValue', 'Variables', 'Tags', s, '#@#prefs.inc')
	SKIN:Bang('!Refresh', 'TaskBoard')
	render()
end

function Cycle(k)
	local t = tags[k]
	if not t then return end
	for i, c in ipairs(ORDER) do
		if c == t.color then t.color = ORDER[i % #ORDER + 1] break end
	end
	save()
end

function Remove(k)
	if not tags[k] then return end
	table.remove(tags, k)
	save()
end

-- "+ Neuer Tag": Eingabefeld ueber dem Knopf
-- Der Knopf wird selbst zum Eingabefeld: gleiche, deckende Farbe wie das Textfeld,
-- Rahmen in Akzentfarbe, das Textfeld sitzt innen (nicht ueber den runden Ecken).
function AddStart()
	if not addBox then return end
	local b = addBox
	set('TagAdd', 'Text', '')
	set('TagShapes', b.shape == 1 and 'Shape' or ('Shape' .. b.shape), string.format(
		'Rectangle %d.5,%d.5,%d,33,8 | Fill Color 30,32,39,255 | StrokeWidth 1 | Stroke Color %s',
		b.x, b.y, b.w - 1, SKIN:GetVariable('ColorCheck')))
	SKIN:Bang('!UpdateMeter', '*')
	SKIN:Bang('!Redraw')
	SKIN:Bang('!SetVariable', 'TagInX', b.x + 12)
	SKIN:Bang('!SetVariable', 'TagInY', b.y + 6)
	SKIN:Bang('!SetVariable', 'TagInW', b.w - 22)
	SKIN:Bang('!UpdateMeasure', 'MeasureTagInput')
	-- "Stay topmost" (ZPos 2) schiebt das Fenster laufend wieder nach vorn und
	-- verdeckt damit das Eingabefeld; einfaches "Topmost" (1) tut das nicht
	SKIN:Bang('!ZPos', '1')
	SKIN:Bang('!CommandMeasure', 'MeasureTagInput', 'ExecuteBatch 1')
	adding = true
	commitWatch()
end

-- Esc / weggeklickt: Knopf wieder normal
function AddCancel() adding = false; render() end

function AddDone()
	adding = false
	wasCommit()
	render()
	local name = trim(SKIN:GetVariable('NewTag') or ''):gsub('^#+', ''):gsub('%s+', '-'):gsub('[#,:;%.!%?%(%)%[%]{}"\'<>]', '')
	if name == '' or not name:match('%D') or #tags >= MAX then return end
	for _, t in ipairs(tags) do if t.name:lower() == name:lower() then return end end
	-- erste noch nicht benutzte Farbe
	local used = {}
	for _, t in ipairs(tags) do used[t.color] = true end
	local color = ORDER[(#tags % 6) + 1]
	for _, c in ipairs(ORDER) do if not used[c] then color = c break end end
	tags[#tags + 1] = { name = name, color = color }
	save()
end

-- ---------- Updates von Hand ----------
function CheckUpdates()
	set('UpdInfo', 'Text', 'Suche …')
	show('UpdNow', false); show('UpdNowText', false)
	SKIN:Bang('!UpdateMeter', '*')
	SKIN:Bang('!Redraw')
	SKIN:Bang('!CommandMeasure', 'MeasureUpdCheck', 'Run')
end

function UpdChecked()
	local out = SKIN:GetMeasure('MeasureUpdCheck'):GetStringValue() or ''
	local kind, ver = out:match('(%a+) ([%d%.]+)')
	local text
	if kind == 'neu' then
		text = 'Version ' .. ver .. ' ist da.'
		show('UpdNow', true); show('UpdNowText', true)
	elseif kind == 'aktuell' then
		text = 'Du hast die neueste Version (' .. ver .. ').'
	else
		text = 'Keine Verbindung zu GitHub – bitte später nochmal.'
	end
	set('UpdInfo', 'Text', text)
	SKIN:Bang('!UpdateMeter', '*')
	SKIN:Bang('!Redraw')
end

function InstallNow()
	set('UpdInfo', 'Text', 'Wird installiert – die Liste lädt gleich neu …')
	show('UpdNow', false); show('UpdNowText', false)
	SKIN:Bang('!UpdateMeter', '*')
	SKIN:Bang('!Redraw')
	SKIN:Bang('!CommandMeasure', 'MeasureUpdNow', 'Run')
end
