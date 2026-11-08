-- Task Board: zeigt die Checkbox-Zeilen (- [ ] / - [x]) einer Markdown-Datei
-- an und schreibt Aenderungen (abhaken, neu, bearbeiten, aufraeumen) direkt in die Datei zurueck.
-- Eingerueckte Checkboxen unter einem Punkt sind Unteraufgaben (immer sichtbar),
-- andere eingerueckte Zeilen sind Notizen (aufklappbar, Links anklickbar).
-- Datei muss als UTF-16 LE gespeichert sein, sonst behandelt Rainmeter Umlaute als ANSI.

local path, maxItems, maxNotes, maxSubs, rowH, noteH, listTop, width, vault
local lines, display, bom, nl, lastContent, lastOpen, lastDone
local itemY, addY, noteMap, subMap = {}, {}, {}, {}
-- Unterkante jedes Punkts (samt Unteraufgaben/Notizen), Hoehe des Hintergrunds, Tag-Farben: fuers Ziehen und die Etiketten
local itemBot, lastBgH, tagConf = {}, nil, {}
local expanded = {}
-- laufende Bearbeitung: mode = 'task' | 'note' | 'addnote' | 'sub' | 'addsub'
local edit
local dueIcon, collapsed
-- Archiv und Zeitstempel: "➕ 2026-11-01" erstellt, "✅ 2026-11-03" erledigt, "❌ …" geloescht
local archivePath, createdIcon, doneIcon, cancelIcon
-- Wiederholung "🔁 täglich" und Uhrzeit "⏰ 15:00"
local repeatIcon, timeIcon
local notified, lastMinute = {}, nil
-- Einblenden beim Anmelden/Aufwachen/Entsperren: bis revealUntil ueber allen Fenstern
local revealUntil, lastTick = nil, os.time()
-- Einblenden angefordert, bevor die Datei lesbar war (z. B. Cloud-Ordner direkt nach der Anmeldung)
local pendingReveal

local CHECK = '^%s*[-*+] %[([ xX])%] ?(.*)$'

function Initialize()
	path = SKIN:GetVariable('TodoFile')
	vault = SKIN:GetVariable('VaultName')
	maxItems = tonumber(SKIN:GetVariable('MaxItems')) or 15
	maxNotes = tonumber(SKIN:GetVariable('MaxNotes')) or 30
	maxSubs = tonumber(SKIN:GetVariable('MaxSubs')) or 30
	rowH = tonumber(SKIN:GetVariable('RowH')) or 34
	noteH = tonumber(SKIN:GetVariable('NoteH')) or 28
	listTop = tonumber(SKIN:GetVariable('ListTop')) or 60
	width = tonumber(SKIN:GetVariable('Width')) or 440
	dueIcon = SKIN:GetVariable('DueIcon')
	collapsed = SKIN:GetVariable('Collapsed') == '1'
	archivePath = SKIN:GetVariable('ArchiveFile')
	createdIcon = SKIN:GetVariable('CreatedIcon')
	doneIcon = SKIN:GetVariable('DoneIcon')
	cancelIcon = SKIN:GetVariable('CancelIcon')
	repeatIcon = SKIN:GetVariable('RepeatIcon')
	timeIcon = SKIN:GetVariable('TimeIcon')
	lastContent = nil
	setupMode()
end

-- ---------- Anzeige-Art: 'sidebar' (Seitenleiste am rechten Rand), 'desktop', 'both' ----------
-- Variable Mode aus prefs.inc (schreibt das Einstellungen-Fenster). Der Rand-Streifen (Config TaskBoard\Rand)
-- wird hier mit ein- bzw. ausgeschaltet, damit es auch nach Updates ohne Installer-Zutun stimmt.
local RAND = 'TaskBoard\\Rand'
local mode, workH
local panel = false              -- 'both': gerade als Panel am Rand (sidebar.lua: PanelOn/PanelOff)
local deskX, deskY               -- 'both': Desktop-Platz, an den die Liste danach zurueckkehrt
local hideOnFirstUpdate = false
function setupMode()
	-- Hintergrund-Deckkraft aus den Einstellungen
	-- Durchsichtig = 1 statt 0: ganz unsichtbar, aber Klicks auf freie Flaechen kommen noch an.
	-- Alte Stufen (bis 1.2: 218/190/150) einmalig auf die neuen umstellen.
	local op = tonumber(SKIN:GetVariable('Opacity')) or 170
	local old = { [218] = 170, [190] = 100, [150] = 1 }
	if old[op] then
		op = old[op]
		SKIN:Bang('!SetVariable', 'Opacity', op)
		SKIN:Bang('!WriteKeyValue', 'Variables', 'Opacity', op, '#@#prefs.inc')
	end
	SKIN:Bang('!SetVariable', 'ColorBg', '12,12,18,' .. op)
	-- feine helle Umrandung, damit man den Kasten auch bei wenig/keinem Hintergrund sieht
	SKIN:Bang('!SetVariable', 'ColorBorder', '255,255,255,' .. (op <= 100 and 90 or 40))
	-- Durchsichtig: Schrift bekommt einen leichten dunklen Schatten, damit sie auch auf hellem
	-- Hintergrund lesbar bleibt (der Hintergrund selbst wird nicht abgedunkelt)
	if op <= 1 then
		SKIN:Bang('!SetOptionGroup', 'List', 'StringEffect', 'Shadow')
		SKIN:Bang('!SetOptionGroup', 'List', 'FontEffectColor', '0,0,0,210')
		for _, m in ipairs({ 'MeterTitle', 'MeterCount', 'MeterHelp', 'MeterFold' }) do
			SKIN:Bang('!SetOption', m, 'StringEffect', 'Shadow')
			SKIN:Bang('!SetOption', m, 'FontEffectColor', '0,0,0,210')
		end
	end
	mode = SKIN:GetVariable('Mode') or 'sidebar'
	workH = tonumber(SKIN:GetVariable('WORKAREAHEIGHT')) or 1080
	if mode == 'sidebar' then
		-- versteckt, bis die Maus an den Rand kommt; darf ausserhalb des Bildschirms stehen (Animation)
		SKIN:Bang('!KeepOnScreen', '0')
		SKIN:Bang('!Draggable', '0')
		SKIN:Bang('!ZPos', '2')
		-- !Hide wirkt erst, wenn Rainmeter das Fenster angelegt hat -> im ersten Update
		hideOnFirstUpdate = true
	else
		if mode == 'both' then SKIN:Bang('!SetAnchor', '0', '0') end
		SKIN:Bang('!KeepOnScreen', '1')
		SKIN:Bang('!Draggable', '1')
		SKIN:Bang('!ZPos', '-2')
		SKIN:Bang('!Show')
		-- 'both': beim letzten Mal als Seitenleiste am Rand neu geladen -> zurueck an den Desktop-Platz,
		-- und der Rand-Streifen vergisst seine laufende Animation (sonst schoebe er die Liste weiter)
		local pf = SKIN:GetVariable('@') .. 'panel-pos.txt'
		local fh = io.open(pf, 'rb')
		if fh then
			local px, py = (fh:read('*a') or ''):match('(-?%d+)%s+(-?%d+)')
			fh:close()
			os.remove(pf)
			if px and mode == 'both' then
				SKIN:Bang('!Move', px, py)
				SKIN:Bang('!SetTransparency', '255')
				SKIN:Bang('!CommandMeasure', 'MeasureSide', 'PanelReset()', 'TaskBoard\\Rand')
			end
		end
		-- kommt von der Seitenleiste: wieder oben rechts auf den Desktop
		if SKIN:GetVariable('LastMode') == 'sidebar' then
			local right = (tonumber(SKIN:GetVariable('WORKAREAX')) or 0) + (tonumber(SKIN:GetVariable('WORKAREAWIDTH')) or 1920)
			SKIN:Bang('!SetAnchor', '0', '0')
			SKIN:Bang('!Move', right - 24 - width, (tonumber(SKIN:GetVariable('WORKAREAY')) or 0) + 60)
		end
	end
	if SKIN:GetVariable('LastMode') ~= mode then
		SKIN:Bang('!WriteKeyValue', 'Variables', 'LastMode', mode, '#@#prefs.inc')
	end
	if mode == 'desktop' then
		SKIN:Bang('!DeactivateConfig', RAND)
	else
		SKIN:Bang('!ActivateConfig', RAND, 'Rand.ini')
		SKIN:Bang('!Refresh', RAND)
	end
end

local function readFile()
	local f = io.open(path, 'rb')
	if not f then return nil end
	local c = f:read('*a')
	f:close()
	return c
end

local function indentOf(line)
	local ws = line:match('^(%s*)')
	return #ws:gsub('\t', '    ')
end

-- Faelligkeitsdatum: "📅 2026-11-05" (Format des Obsidian-Tasks-Plugins), freiwillig
local WEEKDAYS = { 'So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa' }
local WD_INPUT = { so = 1, sonntag = 1, mo = 2, montag = 2, di = 3, dienstag = 3, mi = 4, mittwoch = 4,
	['do'] = 5, donnerstag = 5, fr = 6, freitag = 6, sa = 7, samstag = 7 }

local function today()
	local d = os.date('*t')
	return os.time({ year = d.year, month = d.month, day = d.day, hour = 12 })
end

local function dueOf(text)
	local y, m, d = text:match(dueIcon .. '%s*(%d%d%d%d)%-(%d%d)%-(%d%d)')
	if not y then return nil end
	return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
end

-- Wiederholung "🔁 …" reicht bis zum naechsten Symbol (Emojis beginnen mit Byte 226 bzw. 240),
-- damit auch "🔁 alle 2 Wochen" oder "🔁 Mo,Mi,Fr" gehen
local function repPattern() return '%s*' .. repeatIcon .. '[^\226\240]*[^%s\226\240]' end

local function stripDue(text)
	text = text:gsub('%s*' .. dueIcon .. '%s*%d%d%d%d%-%d%d%-%d%d', '')
	text = text:gsub(repPattern(), '')
	return (text:gsub('%s*' .. timeIcon .. '%s*%d%d?:%d%d', ''))
end

-- ---------- Tags (Obsidian-Schreibweise "#arbeit" in der Zeile) ----------
-- Ein Tag beginnt nach Zeilenanfang oder Leerzeichen mit #, ohne Leer-/Satzzeichen, nicht nur Ziffern.
local TAGCHARS = '[^%s#%.,;:!%?%(%)%[%]{}"\'<>]+'
local MAXTAGS = 3              -- so viele Etiketten pro Punkt in der Liste
local function tagsOf(text)
	local out, seen = {}, {}
	for name in (' ' .. text):gmatch('%s#(' .. TAGCHARS .. ')') do
		if name:match('%D') and not seen[name:lower()] then
			seen[name:lower()] = true
			out[#out + 1] = name
		end
	end
	return out
end
local function stripTags(text)
	local s = (' ' .. text):gsub('(%s)#(' .. TAGCHARS .. ')', function(sp, name)
		if name:match('%D') then return '' end
	end)
	return (s:gsub('^%s', ''):gsub('%s%s+', ' '))
end
-- Tag-Farben wie die Akzentfarben, dazu grau: { Flaeche, Schrift } (RGB)
local TAGCOL = {
	lila = { '138,108,245', '165,185,255' }, blau = { '60,130,240', '140,190,255' },
	gruen = { '50,170,100', '140,220,170' }, orange = { '235,135,40', '255,195,130' },
	rot = { '220,70,70', '255,160,160' }, pink = { '220,80,165', '255,165,215' },
	grau = { '140,140,154', '210,210,220' },
}
-- abgerundete Flaeche (Pille) hinter Etikett Tag{i}_{k}, an dessen endgueltiger Position
local tagFillOf = {}
local function tagPill(i, k)
	local tm, bg = 'Tag' .. i .. '_' .. k, 'TagBg' .. i .. '_' .. k
	SKIN:Bang('!UpdateMeter', tm)
	local m = SKIN:GetMeter(tm)
	local w, h = m:GetW(), m:GetH()
	if w <= 0 then SKIN:Bang('!HideMeter', bg) return end
	local c = tagFillOf[tm] or '140,140,154'
	SKIN:Bang('!SetOption', bg, 'X', m:GetX())
	SKIN:Bang('!SetOption', bg, 'Y', m:GetY())
	SKIN:Bang('!SetOption', bg, 'Shape', string.format('Rectangle 0.5,0.5,%d,%d,%d | Fill Color %s,70 | StrokeWidth 1 | Stroke Color %s,150',
		w - 1, h - 1, math.floor((h - 1) / 2), c, c))
	SKIN:Bang('!ShowMeter', bg)
	SKIN:Bang('!UpdateMeter', bg)
end
-- Einstellung "Tags=arbeit:blau,privat:pink" -> { arbeit = 'blau', ... } (Namen klein)
local function tagColors()
	local out = {}
	for part in (SKIN:GetVariable('Tags') or ''):gmatch('[^,]+') do
		local name, col = part:match('^%s*(.-):(%a+)%s*$')
		if name and name ~= '' then out[name:lower()] = col end
	end
	return out
end

-- Wiederholung und Uhrzeit
local RULES = { ['täglich'] = 'täglich', taeglich = 'täglich', werktags = 'werktags',
	['wöchentlich'] = 'wöchentlich', woechentlich = 'wöchentlich', monatlich = 'monatlich',
	['jährlich'] = 'jährlich', jaehrlich = 'jährlich' }
local function ruleOf(text)
	local r = text:match(repeatIcon .. '%s*([^\226\240]*[^%s\226\240])')
	return r
end
local function timeOf(text)
	local h, m = text:match(timeIcon .. '%s*(%d%d?):(%d%d)')
	if h then return tonumber(h), tonumber(m) end
end

-- naechster Termin nach "due" (nicht vor heute)
-- Regeln: täglich, werktags, wöchentlich, monatlich, jährlich, "alle N Tage|Wochen|Monate|Jahre", "Mo,Mi,Fr"
local WDNUM = { So = 1, Mo = 2, Di = 3, Mi = 4, Do = 5, Fr = 6, Sa = 7 }
local function nextDate(due, rule)
	local days
	if rule == 'werktags' then rule = 'Mo,Di,Mi,Do,Fr' end
	-- Wochentagsliste: nur Kuerzel und Kommas, nie drei Buchstaben am Stueck
	if rule:match('^[%a,]+$') and not rule:find('%a%a%a') then
		for d in rule:gmatch('%a%a') do
			if WDNUM[d] then days = days or {}; days[WDNUM[d]] = true end
		end
	end
	local n, unit = rule:match('^alle (%d+) (%S+)$')
	n = tonumber(n)
	local function step(t)
		local d = os.date('*t', t)
		if days then
			-- naechster passender Wochentag
			repeat
				d.day = d.day + 1
				d.hour = 12
				d = os.date('*t', os.time(d))
			until days[d.wday]
		elseif n then
			if unit == 'Wochen' then d.day = d.day + 7 * n
			elseif unit == 'Monate' then d.month = d.month + n
			elseif unit == 'Jahre' then d.year = d.year + n
			else d.day = d.day + n end
		elseif rule == 'wöchentlich' then d.day = d.day + 7
		elseif rule == 'monatlich' then d.month = d.month + 1
		elseif rule == 'jährlich' then d.year = d.year + 1
		else d.day = d.day + 1 end
		d.hour = 12
		return os.time(d)
	end
	local n = step(due or today())
	while n < today() do n = step(n) end
	return n
end

-- Zeitstempel (➕ erstellt, ✅ erledigt): auf dem Desktop und im Textfeld unsichtbar, bleiben beim Bearbeiten erhalten
local DATE = '%d%d%d%d%-%d%d%-%d%d'
local function stamp(icon) return ' ' .. icon .. ' ' .. os.date('%Y-%m-%d') end
-- Kennung der Google-Aufgabe "%%tb:<id>%%" (Google-Abgleich, google.cs): wie die Stempel unsichtbar,
-- bleibt beim Bearbeiten erhalten, kommt nicht ins Archiv
local MARKER = '%s*%%%%tb:[%w_=%-]+%%%%'
local function stripMarker(text) return (text:gsub(MARKER, '')) end
local function stripStamps(text)
	for _, icon in ipairs({ createdIcon, doneIcon }) do text = text:gsub('%s*' .. icon .. '%s*' .. DATE, '') end
	return stripMarker(text)
end
local function stampsOf(text)
	local s = ''
	for _, icon in ipairs({ createdIcon, doneIcon }) do
		local d = text:match(icon .. '%s*(' .. DATE .. ')')
		if d then s = s .. ' ' .. icon .. ' ' .. d end
	end
	local id = text:match('%%%%tb:[%w_=%-]+%%%%')
	if id then s = s .. ' ' .. id end
	return s
end

-- "@heute", "@morgen", "@übermorgen", "@fr"/"@freitag", "@05.11.", "@05.11.2027"
local function resolveDate(tok)
	local base = today()
	tok = tok:lower()
	if tok == 'heute' then return base end
	if tok == 'morgen' then return base + 86400 end
	if tok == 'übermorgen' or tok == 'uebermorgen' then return base + 2 * 86400 end
	local wd = WD_INPUT[tok]
	if wd then
		return base + ((wd - os.date('*t', base).wday) % 7) * 86400
	end
	local d, m, y = tok:match('^(%d%d?)%.(%d%d?)%.?(%d*)$')
	if d then
		local year = tonumber(y) or os.date('*t', base).year
		if year < 100 then year = year + 2000 end
		local t = os.time({ year = year, month = tonumber(m), day = tonumber(d), hour = 12 })
		-- ohne Jahr und schon vorbei -> naechstes Jahr
		if y == '' and t < base then t = os.time({ year = year + 1, month = tonumber(m), day = tonumber(d), hour = 12 }) end
		return t
	end
end

-- "@täglich" -> "🔁 täglich", "@15:00" -> "⏰ 15:00"; Wiederholung/Uhrzeit ohne Datum -> ab heute
local function convertDates(text)
	text = text:gsub('@(%S+)', function(tok)
		local rule = RULES[tok:lower()]
		if rule then return repeatIcon .. ' ' .. rule end
		local h, m = tok:match('^(%d%d?):(%d%d)$')
		if h then return timeIcon .. ' ' .. string.format('%02d:%s', tonumber(h), m) end
		local t = resolveDate(tok)
		if t then return dueIcon .. ' ' .. os.date('%Y-%m-%d', t) end
	end)
	if (ruleOf(text) or timeOf(text)) and not dueOf(text) then
		text = text .. ' ' .. dueIcon .. ' ' .. os.date('%Y-%m-%d')
	end
	return text
end

-- fuers Textfeld zurueck: "📅 2026-11-05" -> "@05.11.2026", "🔁 täglich" -> "@täglich", "⏰ 15:00" -> "@15:00"
local function datesToInput(text)
	text = text:gsub(repeatIcon .. '%s*(%S+)', '@%1')
	text = text:gsub(timeIcon .. '%s*(%d%d?:%d%d)', '@%1')
	return (text:gsub(dueIcon .. '%s*(%d%d%d%d)%-(%d%d)%-(%d%d)', function(y, m, d) return '@' .. d .. '.' .. m .. '.' .. y end))
end

local function dueLabel(due, done, v, h, mi)
	local n = math.floor((due - today()) / 86400 + 0.5)
	local label
	if n == 0 then label = 'heute'
	elseif n == 1 then label = 'morgen'
	elseif n == -1 then label = 'gestern'
	elseif n > 1 and n < 7 then label = WEEKDAYS[os.date('*t', due).wday]
	else label = os.date('%d.%m.', due) end
	if h then label = label .. ' ' .. string.format('%02d:%02d', h, mi) end
	if done then return label, v.colDone end
	if n < 0 then return label, v.colOver end
	-- heute und Uhrzeit schon vorbei -> rot
	local now = os.date('*t')
	if n == 0 and h and now.hour * 60 + now.min >= h * 60 + mi then return label, v.colOver end
	if n == 0 then return label, v.colToday end
	return label, v.colDue
end

-- Faelligkeit als Zahl (Datum + Uhrzeit), ohne Datum math.huge
local function dueTimeOf(text)
	local d = dueOf(text)
	if not d then return math.huge end
	local h, mi = timeOf(text)
	if h then d = d + (h - 12) * 3600 + mi * 60 end
	return d
end

local function parse(c)
	bom = ''
	if c:sub(1, 3) == '\239\187\191' then
		bom = c:sub(1, 3)
		c = c:sub(4)
	end
	nl = c:find('\r\n', 1, true) and '\r\n' or '\n'
	lines = {}
	local open, done = {}, {}
	local current
	for line in (c .. '\n'):gmatch('(.-)\r?\n') do
		lines[#lines + 1] = line
		local mark, text = line:match(CHECK)
		local inside = current and not line:match('^%s*$') and indentOf(line) > current.indent
		if inside and mark then
			current.subs[#current.subs + 1] = { line = #lines, done = mark ~= ' ', text = text }
			current.last = #lines
		elseif inside then
			local note = line:gsub('^%s+', ''):gsub('^[-*+] ', '')
			current.notes[#current.notes + 1] = note
			current.noteLines[#current.noteLines + 1] = #lines
			current.last = #lines
		elseif mark then
			current = { line = #lines, last = #lines, indent = indentOf(line), done = mark ~= ' ', text = text,
				notes = {}, noteLines = {}, subs = {} }
			table.insert(current.done and done or open, current)
		elseif current and line:match('^%s*$') then
			-- Leerzeile: gehoert nur dazu, wenn danach noch eingerueckt weitergeht
		else
			current = nil
		end
	end
	-- Reihenfolge = Reihenfolge in der Datei (eigene Reihenfolge per Ziehen); neue Punkte mit Datum werden
	-- beim Anlegen nach Faelligkeit oben einsortiert (placeDated); erledigte stehen darunter
	display = open
	for _, t in ipairs(done) do display[#display + 1] = t end
	for _, t in ipairs(display) do t.dueTime = dueTimeOf(t.text) end
	return #open, #done
end

-- display usw. nach Aenderungen an lines neu bestimmen (Zeilenende und BOM bleiben)
local function reparse()
	local b, n = bom, nl
	local o, d = parse(table.concat(lines, '\n'))
	bom, nl = b, n
	return o, d
end

-- Block (Zeilen) eines Punkts mit Datum nach Faelligkeit zwischen die anderen offenen Punkte mit Datum
-- einsortieren: vor den ersten, der spaeter faellig ist, sonst hinter den letzten; gibt es noch keinen,
-- ganz nach oben. Selbst verschobene Punkte ohne Datum bleiben so, wo sie sind. false = kein Platz gefunden.
local function placeDated(block, due)
	local at, lastDated, first
	for _, t in ipairs(display) do
		if not t.done and t.indent == 0 then
			first = first or t
			if t.dueTime ~= math.huge then
				if t.dueTime > due then at = t.line break end
				lastDated = t
			end
		end
	end
	if not at and lastDated then at = lastDated.last + 1 end
	if not at and first then at = first.line end
	if not at then return false end
	for k, l in ipairs(block) do table.insert(lines, at + k - 1, l) end
	return true
end

-- Punkt "from" an die Stelle von "to" schieben (beide offen): nach unten hinter "to", nach oben davor
local function moveTask(from, to)
	if not from or not to or from == to then return false end
	local n = from.last - from.line + 1
	local block = {}
	for k = from.line, from.last do block[#block + 1] = lines[k] end
	for k = from.last, from.line, -1 do table.remove(lines, k) end
	local at = to.line > from.line and (to.last - n + 1) or to.line
	for k, l in ipairs(block) do table.insert(lines, at + k - 1, l) end
	return true
end

-- Einmalig beim Umstieg auf die eigene Reihenfolge (1.3.0): offene Punkte in der Datei so ordnen, wie sie
-- bisher angezeigt wurden (mit Datum nach Faelligkeit zuerst). Erledigte bleiben an ihrem Platz.
local function sortOnce()
	local all = {}
	for _, t in ipairs(display) do all[#all + 1] = t end
	table.sort(all, function(a, b) return a.line < b.line end)
	local out, pos, changed, k = {}, 1, false, 1
	local function blankBetween(a, b)
		for x = a.last + 1, b.line - 1 do if not lines[x]:match('^%s*$') then return false end end
		return true
	end
	while k <= #all do
		-- zusammenhaengender Lauf gleich eingerueckter Punkte, dazwischen nur Leerzeilen
		local run = { all[k] }
		while k < #all and all[k + 1].line > all[k].last and all[k + 1].indent == all[k].indent and blankBetween(all[k], all[k + 1]) do
			k = k + 1
			run[#run + 1] = all[k]
		end
		k = k + 1
		local open, sorted = {}, {}
		for i, t in ipairs(run) do if not t.done then open[#open + 1] = t; sorted[#sorted + 1] = { t = t, i = #open } end end
		table.sort(sorted, function(a, b)
			if a.t.dueTime ~= b.t.dueTime then return a.t.dueTime < b.t.dueTime end
			return a.i < b.i
		end)
		local same = true
		for i, s in ipairs(sorted) do if s.t ~= open[i] then same = false end end
		if not same then
			changed = true
			for x = pos, run[1].line - 1 do out[#out + 1] = lines[x] end
			local oi = 0
			for si, slot in ipairs(run) do
				local t = slot
				if not slot.done then oi = oi + 1; t = sorted[oi].t end
				for x = t.line, t.last do out[#out + 1] = lines[x] end
				local gapEnd = run[si + 1] and run[si + 1].line or slot.last + 1
				for x = slot.last + 1, gapEnd - 1 do out[#out + 1] = lines[x] end
			end
			pos = run[#run].last + 1
		end
	end
	if not changed then return false end
	for x = pos, #lines do out[#out + 1] = lines[x] end
	lines = out
	return true
end

local function save()
	local f = io.open(path, 'wb')
	if not f then return end
	f:write(bom .. table.concat(lines, nl))
	f:close()
	lastContent = nil
end

local function trim(s)
	return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- [[Link]] und [[Link|Alias]] lesbar machen
local function pretty(text)
	return (text:gsub('%[%[(.-)%]%]', function(s) return s:match('|(.*)$') or s end))
end

local function urlEncode(s)
	return (s:gsub('[^%w%-%._~]', function(ch) return string.format('%%%02X', ch:byte()) end))
end

-- erster Link einer Notizzeile: Webadresse, [[Obsidian-Notiz]] oder Windows-Pfad
local function linkOf(note)
	local url = note:match('https?://[^%s%)%]>"]+')
	if url then return url end
	local wiki = note:match('%[%[([^%]|#]+)')
	if wiki then return 'obsidian://open?vault=' .. urlEncode(vault) .. '&file=' .. urlEncode(trim(wiki)) end
	local p = note:match('%a:\\[^"<>|*?]*')
	if p then return (p:gsub('[%s%.,;:]+$', '')) end
	return nil
end

-- lange Webadressen in der Anzeige auf "domain.de ↗" kuerzen (die Datei bleibt unveraendert)
local function shortLinks(text)
	local arrow = SKIN:GetVariable('LinkArrow')
	return (text:gsub('https?://[^%s%)%]>"]+', function(url)
		local host = url:match('^https?://([^/:?#]+)') or url
		return host:gsub('^www%.', '') .. ' ' .. arrow
	end))
end

-- Windows-Pfade in der Anzeige auf den Datei-/Ordnernamen kuerzen (die Datei bleibt unveraendert)
local function shortPaths(text)
	return (text:gsub('%a:\\[^"<>|*?]*', function(p)
		return p:gsub('[\\%s]+$', ''):match('([^\\]+)$') or p
	end))
end

-- Kaestchen (eigener Meter <name>Box) und Text einer Checkbox-Zeile setzen, ggf. mit Datum
local function setCheck(m, done, text, v, y)
	local b = m .. 'Box'
	SKIN:Bang('!SetOption', b, 'Text', done and v.boxDone or v.boxOpen)
	SKIN:Bang('!SetOption', b, 'InlineSetting3', 'Color | ' .. (done and v.colCheck or v.colBox))
	SKIN:Bang('!SetOption', b, 'Y', y)
	SKIN:Bang('!ShowMeter', b)
	local shown = shortLinks(pretty(stripTags(stripDue(stripStamps(text)))))
	local due, dueCol = dueOf(text), v.colDone
	if due then
		local label
		local h, mi = timeOf(text)
		label, dueCol = dueLabel(due, done, v, h, mi)
		shown = shown .. '   ' .. (ruleOf(text) and v.repIcon or v.calIcon) .. ' ' .. label
	end
	SKIN:Bang('!SetOption', m, 'Text', shown)
	SKIN:Bang('!SetOption', m, 'FontColor', done and v.colDone or v.colText)
	-- InlineSetting (Datumsfarbe) nie leer lassen, sonst ignoriert Rainmeter InlineSetting2-4
	SKIN:Bang('!SetOption', m, 'InlineSetting', 'Color | ' .. dueCol)
	SKIN:Bang('!SetOption', m, 'InlineSetting4', done and 'Strikethrough' or '')
	SKIN:Bang('!SetOption', m, 'Y', y)
	SKIN:Bang('!ShowMeter', m)
end
local function hideCheck(m)
	SKIN:Bang('!HideMeter', m)
	SKIN:Bang('!HideMeter', m .. 'Box')
end
-- Hoehe einer Zeile nach dem Umbrechen (mindestens minH)
local function heightOf(m, minH)
	SKIN:Bang('!UpdateMeter', m)
	return math.max(SKIN:GetMeter(m):GetH(), minH)
end

-- Zaehler oben rechts; waehrend die Liste eingeblendet ist: Knopf 'Ausblenden'
local function setCount(openCount)
	if revealUntil then
		SKIN:Bang('!SetOption', 'MeterCount', 'Text', 'Ausblenden ✕')
		SKIN:Bang('!SetOption', 'MeterCount', 'FontColor', SKIN:GetVariable('ColorAccent'))
	else
		SKIN:Bang('!SetOption', 'MeterCount', 'Text', openCount .. ' offen')
		SKIN:Bang('!SetOption', 'MeterCount', 'FontColor', SKIN:GetVariable('ColorDone'))
	end
end

-- Eingeklappt: Rainmeter zaehlt versteckte Meter mit ihrer Position in die Fenstergroesse.
-- Darum alle Listen-Meter nach oben schieben, sonst bliebe das (unsichtbare) Fenster so gross wie vorher
-- und finge Klicks auf den Desktop ab. render() setzt die Positionen beim Aufklappen neu.
local function parkList()
	local function park(m) SKIN:Bang('!SetOption', m, 'Y', 0) end
	for i = 1, maxItems do
		for _, p in ipairs({ 'Item', 'Progress', 'Clip', 'NoteAdd', 'SubAdd', 'FileAdd', 'Drop' }) do park(p .. i) end
		park('Item' .. i .. 'Box'); park('Clip' .. i .. 'Btn')
		for k = 1, MAXTAGS do park('Tag' .. i .. '_' .. k); park('TagBg' .. i .. '_' .. k) end
	end
	for k = 1, maxNotes do park('Note' .. k) end
	for k = 1, maxSubs do park('Sub' .. k); park('Sub' .. k .. 'Box') end
	for _, m in ipairs({ 'MeterMore', 'AddBtn', 'MeterAdd', 'MeterClean', 'DropAll', 'DropLine' }) do park(m) end
end

local function render(openCount, doneCount)
	lastOpen, lastDone = openCount, doneCount
	setCount(openCount)
	-- Seitenleiste (oder "Beides" gerade als Panel am Rand): Liste ist ohnehin bildschirmhoch -> kein Einklappen,
	-- Pfeil weg und "x offen" an den rechten Rand
	local asPanel = mode == 'sidebar' or panel
	local isCollapsed = collapsed and not asPanel
	if asPanel then
		SKIN:Bang('!HideMeter', 'MeterFold')
		SKIN:Bang('!HideMeter', 'FoldBtn')
		SKIN:Bang('!SetOption', 'MeterCount', 'X', width - 20)
	else
		SKIN:Bang('!ShowMeter', 'MeterFold')
		SKIN:Bang('!ShowMeter', 'FoldBtn')
		SKIN:Bang('!SetOption', 'MeterCount', 'X', width - 62)
	end
	SKIN:Bang('!SetOption', 'MeterFold', 'Text', SKIN:GetVariable(isCollapsed and 'FoldClosed' or 'FoldOpen'))
	if isCollapsed then
		SKIN:Bang('!HideMeterGroup', 'List')
		parkList()
		SKIN:Bang('!SetOption', 'MeterBg', 'Shape', 'Rectangle 0.5,0.5,' .. (width - 1) .. ',' .. (listTop - 5) .. ',12 | Fill Color #ColorBg# | StrokeWidth 1 | Stroke Color #ColorBorder#')
		SKIN:Bang('!SetOption', 'MeterBg', 'Shape2', 'Rectangle 0,0,0,0 | StrokeWidth 0')
		SKIN:Bang('!UpdateMeter', '*')
		SKIN:Bang('!Redraw')
		return
	end
	SKIN:Bang('!ShowMeter', 'MeterAdd')
	SKIN:Bang('!ShowMeter', 'AddBtn')
	local v = {
		boxOpen = SKIN:GetVariable('BoxOpen'), boxDone = SKIN:GetVariable('BoxDone'),
		colText = SKIN:GetVariable('ColorText'), colDone = SKIN:GetVariable('ColorDone'), repIcon = SKIN:GetVariable('RepIcon'),
		colBox = SKIN:GetVariable('ColorBox'), colCheck = SKIN:GetVariable('ColorCheck'), calIcon = SKIN:GetVariable('CalIcon'),
		colOver = SKIN:GetVariable('ColorOver'), colToday = SKIN:GetVariable('ColorToday'), colDue = SKIN:GetVariable('ColorDue'),
		colLink = SKIN:GetVariable('ColorAccent'), font = SKIN:GetVariable('FontFace'),
	}
	local colNote = SKIN:GetVariable('ColorNote')
	local clipIcon = SKIN:GetVariable('ClipIcon')
	tagConf = tagColors()
	local y = listTop
	local n, s = 0, 0
	noteMap, subMap = {}, {}
	for i = 1, maxItems do
		local m = 'Item' .. i
		local t = display[i]
		if t then
			local count = #t.notes
			local open = expanded[stripMarker(t.text)]
			local subsDone = 0
			for _, sub in ipairs(t.subs) do if sub.done then subsDone = subsDone + 1 end end

			setCheck(m, t.done, t.text, v, y)
			itemY[i] = y

			-- Tags als farbige Etiketten hinter dem Text (Breite vorher messen, damit der Text Platz macht)
			local tags, tw = tagsOf(t.text), 0
			for k = 1, MAXTAGS do
				local tm = 'Tag' .. i .. '_' .. k
				local name = tags[k]
				if name then
					local col = TAGCOL[tagConf[name:lower()] or 'grau'] or TAGCOL.grau
					SKIN:Bang('!SetOption', tm, 'Text', name)
					SKIN:Bang('!SetOption', tm, 'SolidColor', '0,0,0,0')
					tagFillOf[tm] = col[1]
					SKIN:Bang('!SetOption', tm, 'FontColor', col[2] .. ',255')
					-- erst einblenden: versteckte Meter melden die Breite 0
					SKIN:Bang('!ShowMeter', tm)
					SKIN:Bang('!UpdateMeter', tm)
					tw = tw + SKIN:GetMeter(tm):GetW() + 5
				else
					SKIN:Bang('!HideMeter', tm)
					SKIN:Bang('!HideMeter', 'TagBg' .. i .. '_' .. k)
				end
			end

			-- Fortschritt der Unteraufgaben links neben der Bueroklammer
			local clipW
			if #t.subs > 0 then
				SKIN:Bang('!SetOption', 'Progress' .. i, 'Text', subsDone .. '/' .. #t.subs)
				SKIN:Bang('!SetOption', 'Progress' .. i, 'Y', y)
				SKIN:Bang('!ShowMeter', 'Progress' .. i)
				clipW = width - 183
			else
				SKIN:Bang('!HideMeter', 'Progress' .. i)
				clipW = width - 129
			end
			-- Tags: passen Text und Etiketten in eine Zeile, direkt hinter den Text, sonst in eine eigene Zeile darunter
			local tagsBelow = false
			if tw > 0 then
				SKIN:Bang('!SetOption', m, 'ClipStringW', 3000)
				SKIN:Bang('!UpdateMeter', m)
				local natural = SKIN:GetMeter(m):GetW()
				tagsBelow = natural - 8 + tw > clipW
				local tx = tagsBelow and SKIN:GetMeter(m):GetX() or (SKIN:GetMeter(m):GetX() + natural - 2)
				for k = 1, math.min(#tags, MAXTAGS) do
					local tm = 'Tag' .. i .. '_' .. k
					SKIN:Bang('!SetOption', tm, 'X', tx)
					SKIN:Bang('!SetOption', tm, 'Y', y + math.floor((rowH - 22) / 2))
					SKIN:Bang('!ShowMeter', tm)
					tx = tx + SKIN:GetMeter(tm):GetW() + 5
				end
			end
			SKIN:Bang('!SetOption', m, 'ClipStringW', clipW)

			SKIN:Bang('!SetOption', 'Clip' .. i, 'Text', clipIcon .. (count > 0 and (' ' .. count) or ''))
			-- Knopf mittig in der ersten Zeile des Punkts, Symbol + Anzahl darauf zentriert
			local by = y + math.floor((rowH - 30) / 2)
			SKIN:Bang('!SetOption', 'Clip' .. i .. 'Btn', 'Y', by)
			SKIN:Bang('!ShowMeter', 'Clip' .. i .. 'Btn')
			SKIN:Bang('!SetOption', 'Clip' .. i, 'Y', by + 4)
			SKIN:Bang('!SetOption', 'Clip' .. i, 'FontColor', open and v.colLink or v.colDone)
			SKIN:Bang('!ShowMeter', 'Clip' .. i)
			y = y + heightOf(m, rowH)
			if tagsBelow then
				-- Etiketten-Zeile unter dem (ggf. umbrochenen) Text
				for k = 1, math.min(#tags, MAXTAGS) do SKIN:Bang('!SetOption', 'Tag' .. i .. '_' .. k, 'Y', y - 4) end
				y = y + 24
			end
			for k = 1, math.min(#tags, MAXTAGS) do tagPill(i, k) end

			for _, sub in ipairs(t.subs) do
				if s >= maxSubs then break end
				s = s + 1
				local sm = 'Sub' .. s
				subMap[s] = { task = i, line = sub.line, y = y }
				setCheck(sm, sub.done, sub.text, v, y)
				y = y + heightOf(sm, noteH + 2)
			end

			if open then
				for k, note in ipairs(t.notes) do
					if n >= maxNotes then break end
					n = n + 1
					local nm = 'Note' .. n
					local link = linkOf(note)
					noteMap[n] = { task = i, line = t.noteLines[k], y = y }
					SKIN:Bang('!SetOption', nm, 'Text', shortPaths(shortLinks(pretty(note))))
					SKIN:Bang('!SetOption', nm, 'FontColor', link and v.colLink or colNote)
					SKIN:Bang('!SetOption', nm, 'InlineSetting', link and 'Underline' or '')
					SKIN:Bang('!SetOption', nm, 'LeftMouseUpAction', link and ('["' .. link .. '"]') or '')
					SKIN:Bang('!SetOption', nm, 'Y', y)
					SKIN:Bang('!ShowMeter', nm)
					y = y + heightOf(nm, noteH)
				end
				SKIN:Bang('!SetOption', 'NoteAdd' .. i, 'Y', y)
				SKIN:Bang('!SetOption', 'SubAdd' .. i, 'Y', y)
				SKIN:Bang('!ShowMeter', 'NoteAdd' .. i)
				SKIN:Bang('!ShowMeter', 'SubAdd' .. i)
				SKIN:Bang('!SetOption', 'FileAdd' .. i, 'Y', y)
				SKIN:Bang('!ShowMeter', 'FileAdd' .. i)
				addY[i] = y
				y = y + noteH + 4
			else
				SKIN:Bang('!HideMeter', 'NoteAdd' .. i)
				SKIN:Bang('!HideMeter', 'SubAdd' .. i)
				SKIN:Bang('!HideMeter', 'FileAdd' .. i)
			end
			if #t.subs > 0 and not open then y = y + 4 end
			itemBot[i] = y
		else
			hideCheck(m)
			itemY[i], itemBot[i] = nil, nil
			for _, p in ipairs({ 'Clip' .. i, 'Clip' .. i .. 'Btn', 'Progress' .. i, 'NoteAdd' .. i, 'SubAdd' .. i, 'FileAdd' .. i,
				'Tag' .. i .. '_1', 'Tag' .. i .. '_2', 'Tag' .. i .. '_3',
				'TagBg' .. i .. '_1', 'TagBg' .. i .. '_2', 'TagBg' .. i .. '_3' }) do
				SKIN:Bang('!HideMeter', p)
			end
		end
	end
	for k = n + 1, maxNotes do SKIN:Bang('!HideMeter', 'Note' .. k) end
	for k = s + 1, maxSubs do hideCheck('Sub' .. k) end

	local hidden = #display - maxItems
	if #display == 0 then
		SKIN:Bang('!SetOption', 'MeterMore', 'Text', 'Alles erledigt')
		SKIN:Bang('!SetOption', 'MeterMore', 'Y', y)
		SKIN:Bang('!ShowMeter', 'MeterMore')
		y = y + rowH
	elseif hidden > 0 then
		SKIN:Bang('!SetOption', 'MeterMore', 'Text', '+ ' .. hidden .. ' weitere in Obsidian')
		SKIN:Bang('!SetOption', 'MeterMore', 'Y', y)
		SKIN:Bang('!ShowMeter', 'MeterMore')
		y = y + rowH
	else
		SKIN:Bang('!HideMeter', 'MeterMore')
	end

	y = y + 6
	-- Knopf "+ Neuer Punkt": so breit wie der Text, Text mittig in der Hoehe
	local addW = 130
	local ma = SKIN:GetMeter('MeterAdd')
	if ma and ma:GetW() > 0 then addW = ma:GetW() + 23 end
	SKIN:Bang('!SetVariable', 'AddW', addW)
	SKIN:Bang('!SetOption', 'AddBtn', 'Y', y)
	SKIN:Bang('!SetOption', 'MeterAdd', 'Y', y + math.floor((32 - (ma and ma:GetH() or 22)) / 2))
	SKIN:Bang('!SetOption', 'MeterClean', 'Y', y + 7)
	if doneCount > 0 then SKIN:Bang('!ShowMeter', 'MeterClean') else SKIN:Bang('!HideMeter', 'MeterClean') end
	y = y + math.max(rowH, 32) + 16

	-- Hintergrund nur so hoch wie die Eintraege (auch in der Seitenleiste; frueher bildschirmhoch,
	-- das sah bei "Durchsichtig" wie ein leerer Rahmen aus und hat Klicks darunter abgefangen)
	-- Seitenleiste: darunter eine unsichtbare Flaeche (Deckkraft 1) bis unten, damit die Liste offen bleibt,
	-- wenn die Maus vom Rand (Bildschirmmitte) zur Liste hinauf faehrt
	local bgH = y
	lastBgH = bgH
	local hitH = (mode == 'sidebar' or panel) and math.max(y, workH - 16) or 0
	SKIN:Bang('!SetOption', 'MeterBg', 'Shape2', 'Rectangle 0,0,' .. width .. ',' .. hitH .. ' | Fill Color 0,0,0,1 | StrokeWidth 0')
	SKIN:Bang('!SetOption', 'MeterBg', 'Shape', 'Rectangle 0.5,0.5,' .. (width - 1) .. ',' .. (bgH - 1) .. ',12 | Fill Color #ColorBg# | StrokeWidth 1 | Stroke Color #ColorBorder#')
	setCount(openCount)
	SKIN:Bang('!UpdateMeter', '*')
	SKIN:Bang('!Redraw')
end

local function refresh(force)
	local c = readFile()
	if not c then
		SKIN:Bang('!SetOption', 'MeterCount', 'Text', 'Datei fehlt')
		return 0
	end
	if c == lastContent and not force then return nil end
	lastContent = c
	local o, d = parse(c)
	render(o, d)
	return o
end

-- Punkt wiederfinden, auch wenn die Datei inzwischen geaendert wurde
-- (gleich = gleich ohne Google-Kennung: der Abgleich kann sie anhaengen, waehrend hier etwas offen ist)
local function sameLine(a, b) return a == b or (a ~= nil and b ~= nil and stripMarker(a) == stripMarker(b)) end
local function findTask(lineNo, orig)
	for _, t in ipairs(display) do
		if t.line == lineNo and sameLine(lines[t.line], orig) then return t end
	end
	for _, t in ipairs(display) do
		if sameLine(lines[t.line], orig) then return t end
	end
end

-- Zeile innerhalb eines Punkts (Notiz oder Unteraufgabe) wiederfinden
local function findChild(t, lineNo, orig)
	if sameLine(lines[lineNo], orig) and lineNo > t.line and lineNo <= t.last then return lineNo end
	for k = t.line + 1, t.last do
		if sameLine(lines[k], orig) then return k end
	end
end

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
-- Esc im Eingabefeld der Liste: nichts speichern, nur merken, dass kein Feld mehr offen ist
function EditCancel() edit = nil end

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

-- Textfeld an Position x/y oeffnen
local function openEditor(text, x, y, w)
	SKIN:Bang('!SetVariable', 'EditText', text)
	SKIN:Bang('!SetVariable', 'EditX', x)
	SKIN:Bang('!SetVariable', 'EditY', y)
	SKIN:Bang('!SetVariable', 'EditW', w)
	SKIN:Bang('!UpdateMeasure', 'MeasureEdit')
	SKIN:Bang('!CommandMeasure', 'MeasureEdit', 'ExecuteBatch 1')
	commitWatch()
end

-- abhaken setzt "✅ heute", zuruecknehmen entfernt es wieder
local function flip(lineNo)
	local line = lines[lineNo]
	local nowDone = line:match('%[ %]') ~= nil
	line = line:gsub('%[([ xX])%]', nowDone and '[x]' or '[ ]', 1)
	line = line:gsub('%s*' .. doneIcon .. '%s*' .. DATE, '')
	if nowDone then line = line .. stamp(doneIcon) end
	lines[lineNo] = line
end

-- ---------- Archiv (Todo-Archiv.md): erledigte und geloeschte Punkte statt wegwerfen ----------
local MONTHS = { 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember' }

-- Bloecke (Listen von Zeilen) unter der Ueberschrift des aktuellen Monats anhaengen
local function archive(blocks)
	if #blocks == 0 then return true end
	local f = io.open(archivePath, 'rb')
	local c = f and f:read('*a') or nil
	if f then f:close() end
	if not c or c == '' then
		c = '---\ntags: [todo, archiv]\n---\n\n# Todo-Archiv\n\nErledigte und gelöschte Punkte aus [[Todo]], mit allen Notizen und Unteraufgaben. '
			.. '➕ = erstellt, ✅ = erledigt, ❌ = gelöscht (`- [-]`).\n'
	end
	local d = os.date('*t')
	local heading = '## ' .. MONTHS[d.month] .. ' ' .. d.year
	local lastHeading
	for h in c:gmatch('\n(## [^\r\n]*)') do lastHeading = h end
	local out = { (c:gsub('[\r\n]*$', '')) }
	if lastHeading ~= heading then out[#out + 1] = '\n\n' .. heading .. '\n' end
	for _, b in ipairs(blocks) do out[#out + 1] = '\n' .. table.concat(b, '\n') end
	out[#out + 1] = '\n'
	f = io.open(archivePath, 'wb')
	if not f then return false end
	f:write(table.concat(out))
	f:close()
	return true
end

-- Zeilen eines Punkts (ohne seine Einrueckung) fuers Archiv; mark: 'x' erledigt, '-' geloescht
local function blockOf(t, mark)
	local indent = lines[t.line]:match('^(%s*)')
	local b = {}
	for k = t.line, t.last do
		local line = stripMarker(lines[k])
		if line:sub(1, #indent) == indent then line = line:sub(#indent + 1) end
		if line:match('%S') then b[#b + 1] = line end
	end
	local head = b[1]
	if mark == '-' then
		head = head:gsub('%[[ xX]%]', '[-]', 1) .. stamp(cancelIcon)
	elseif not head:find(doneIcon, 1, true) then
		head = head .. stamp(doneIcon)  -- in Obsidian ohne Datum abgehakt
	end
	b[1] = head
	return b
end

-- ---------- Wiederkehrende Punkte ----------
-- abgehakter "🔁"-Punkt (Desktop oder Obsidian): Kopie mit ✅ ins Archiv,
-- der Punkt selbst wird wieder offen und rutscht auf den naechsten Termin
local function rollRecurring()
	local blocks, changes = {}, {}
	for _, t in ipairs(display) do
		local rule = t.done and ruleOf(t.text)
		if rule then
			local line = lines[t.line]
			local copy = stripMarker(line:sub(#line:match('^(%s*)') + 1):gsub(repPattern(), ''))
			if not copy:find(doneIcon, 1, true) then copy = copy .. stamp(doneIcon) end
			blocks[#blocks + 1] = { copy }
			local nxt = dueIcon .. ' ' .. os.date('%Y-%m-%d', nextDate(dueOf(t.text), RULES[rule] or rule))
			line = line:gsub('%[[xX]%]', '[ ]', 1):gsub('%s*' .. doneIcon .. '%s*' .. DATE, '')
			if dueOf(line) then line = line:gsub(dueIcon .. '%s*' .. DATE, nxt) else line = line .. ' ' .. nxt end
			changes[t.line] = line
			for _, sub in ipairs(t.subs) do
				if sub.done then changes[sub.line] = lines[sub.line]:gsub('%[[xX]%]', '[ ]', 1):gsub('%s*' .. doneIcon .. '%s*' .. DATE, '') end
			end
		end
	end
	if #blocks == 0 or not archive(blocks) then return false end
	for k, line in pairs(changes) do lines[k] = line end
	return true
end

-- Windows-Erinnerung, sobald ein offener Punkt mit Uhrzeit faellig ist (einmal pro Termin,
-- nach "In 15 Min nochmal" erneut). Jede Erinnerung bekommt eine Nummer fuer die Knoepfe (ToastAction).
local reminderIds, reminderCount, snoozed = {}, 0, {}
local function checkReminders()
	-- Einstellungen: RemindOn (1/0), RemindLead (Minuten vorher)
	if SKIN:GetVariable('RemindOn') == '0' then return end
	local lead = tonumber(SKIN:GetVariable('RemindLead')) or 0
	local due = {}
	local now = os.date('*t')
	for _, t in ipairs(display) do
		local h, mi = timeOf(t.text)
		local day = dueOf(t.text)
		local key = stripMarker(t.text)        -- ohne Google-Kennung: sonst kaeme die Erinnerung nach dem ersten Abgleich doppelt
		local again = snoozed[key] and os.time() >= snoozed[key]
		if not t.done and h and day and (not notified[key] or again)
			and (day < today() or (day == today() and now.hour * 60 + now.min >= h * 60 + mi - lead)) then
			notified[key] = true
			snoozed[key] = nil
			reminderCount = reminderCount + 1
			reminderIds[reminderCount] = key
			local name = trim(pretty(stripDue(stripStamps(t.text)))):gsub('["|~]', '')
			due[#due + 1] = reminderCount .. '~' .. name .. string.format(' (%02d:%02d)', h, mi)
		end
	end
	if #due == 0 then return end
	SKIN:Bang('!SetVariable', 'NotifyText', table.concat(due, ' | '))
	SKIN:Bang('!UpdateMeasure', 'MeasureNotify')
	SKIN:Bang('!CommandMeasure', 'MeasureNotify', 'Run')
end

function Update()
	if hideOnFirstUpdate then hideOnFirstUpdate = false; SKIN:Bang('!Hide') end
	keepWatch(edit ~= nil)
	-- Aufwachen aus dem Standby: waehrend des Schlafs laeuft kein Update -> grosse Zeitluecke
	local now = os.time()
	if now - lastTick > 90 then Reveal() end
	lastTick = now
	if revealUntil and now >= revealUntil then HideReveal() end
	if pendingReveal then
		if now - pendingReveal > 300 then pendingReveal = nil
		elseif lastOpen then Reveal() end
	end
	-- jede Minute neu zeichnen, damit "heute 15:00" rechtzeitig rot wird
	local minute = os.date('%H:%M')
	refresh(minute ~= lastMinute)
	lastMinute = minute
	if not display then return 0 end
	-- Umstieg auf die eigene Reihenfolge (1.3.0): Datei einmal so ordnen, wie sie bisher angezeigt wurde
	if SKIN:GetVariable('ManualOrder') ~= '1' then
		if sortOnce() then save(); refresh(true) end
		SKIN:Bang('!SetVariable', 'ManualOrder', '1')
		SKIN:Bang('!WriteKeyValue', 'Variables', 'ManualOrder', '1', '#@#prefs.inc')
	end
	if rollRecurring() then save(); refresh(true) end
	checkReminders()
	return #display
end

function Toggle(i)
	refresh(true)
	local t = display[i]
	if not t then return end
	flip(t.line)
	save()
	refresh(true)
	if rollRecurring() then save(); refresh(true) end
end

-- Knoepfe in der Windows-Erinnerung (ueber toast-action.vbs): 'done' hakt ab, 'snooze' erinnert in 15 Minuten erneut
function ToastAction(action, id)
	local key = reminderIds[tonumber(id)]
	if not key then return end
	if action == 'snooze' then
		snoozed[key] = os.time() + 15 * 60
		return
	end
	if action ~= 'done' then return end
	refresh(true)
	for _, t in ipairs(display) do
		if stripMarker(t.text) == key and not t.done then
			flip(t.line)
			save()
			refresh(true)
			if rollRecurring() then save(); refresh(true) end
			return
		end
	end
end

function ToggleSub(k)
	local sm = subMap[k]
	if not sm then return end
	local orig = lines[sm.line]
	refresh(true)
	if not sameLine(lines[sm.line], orig) then return end
	flip(sm.line)
	save()
	refresh(true)
end

-- Klick auf den Titel: ganze Liste ein-/ausklappen (bleibt nach Neustart erhalten)
function ToggleCollapse()
	collapsed = not collapsed
	-- nicht in die Datei schreiben: beim Start ist die Liste immer aufgeklappt
	SKIN:Bang('!SetVariable', 'Collapsed', collapsed and '1' or '0')
	render(lastOpen or 0, lastDone or 0)
end

-- Notizen unter einem Punkt auf-/zuklappen
function ToggleNotes(i)
	local t = display and display[i]
	if not t then return end
	expanded[stripMarker(t.text)] = not expanded[stripMarker(t.text)] or nil
	render(lastOpen, lastDone)
end

-- ---------- Punkte per Ziehen verschieben ----------
-- Druecken auf den Text eines offenen Punkts (DragStart) blendet unsichtbare Ablageflaechen ueber allen Zeilen
-- ein (Drop1..n, darunter DropAll fuer den Rest der Liste). Die Flaeche unter der Maus zeigt per Linie, wo der
-- Punkt landet (DragOver); Loslassen darauf verschiebt ihn (DragDrop). Loslassen auf der eigenen Zeile ohne
-- Bewegung = normaler Klick (abhaken). Loslassen woanders oder Maus raus = abbrechen (DragCancel).
local drag
local function dragHide()
	SKIN:Bang('!HideMeter', 'DropAll')
	SKIN:Bang('!HideMeter', 'DropLine')
	for k = 1, maxItems do SKIN:Bang('!HideMeter', 'Drop' .. k) end
	SKIN:Bang('!UpdateMeter', '*')
	SKIN:Bang('!Redraw')
end
function DragStart(i)
	local t = display and display[i]
	if not t or t.done or edit or collapsed then return end
	drag = { from = i, to = i, moved = false, line = t.line, orig = lines[t.line] }
	SKIN:Bang('!SetOption', 'DropAll', 'H', lastBgH or 400)
	SKIN:Bang('!ShowMeter', 'DropAll')
	for k = 1, maxItems do
		if display[k] and itemY[k] and itemBot[k] then
			SKIN:Bang('!SetOption', 'Drop' .. k, 'Y', itemY[k])
			SKIN:Bang('!SetOption', 'Drop' .. k, 'H', math.max(itemBot[k] - itemY[k], 1))
			SKIN:Bang('!ShowMeter', 'Drop' .. k)
		else
			SKIN:Bang('!HideMeter', 'Drop' .. k)
		end
	end
	SKIN:Bang('!UpdateMeter', '*')
	SKIN:Bang('!Redraw')
end
function DragOver(j)
	if not drag then return end
	if j ~= drag.from then drag.moved = true end
	local to = j
	if not display[to] or display[to].done then
		-- auf einen erledigten Punkt gezogen: hinter den letzten offenen
		to = nil
		for k = 1, maxItems do if display[k] and not display[k].done and itemY[k] then to = k end end
	end
	if not to then return end
	drag.to = to
	if to == drag.from then
		SKIN:Bang('!HideMeter', 'DropLine')
	else
		SKIN:Bang('!SetOption', 'DropLine', 'Y', to > drag.from and (itemBot[to] - 2) or (itemY[to] - 1))
		SKIN:Bang('!ShowMeter', 'DropLine')
	end
	SKIN:Bang('!UpdateMeter', 'DropLine')
	SKIN:Bang('!Redraw')
end
function DragCancel()
	if not drag then return end
	drag = nil
	dragHide()
end
function DragDrop(j)
	local d = drag
	drag = nil
	dragHide()
	if not d then return end
	if j == d.from and not d.moved then return Toggle(d.from) end
	if d.to == d.from then return end
	local target = display[d.to]
	if not target then return end
	local toLine, toOrig = target.line, lines[target.line]
	refresh(true)
	local a, b = findTask(d.line, d.orig), findTask(toLine, toOrig)
	if not a or not b or a.done or b.done then return end
	if moveTask(a, b) then save(); refresh(true) end
end

-- Zeilen hinter den letzten Todo-Punkt (samt Notizen) einfuegen, sonst ans Ende (vor eine leere Schlusszeile)
local function insertAtEnd(block)
	local pos = 0
	for _, t in ipairs(display) do if t.last > pos then pos = t.last end end
	if pos == 0 then
		pos = #lines
		while pos > 0 and lines[pos] == '' do pos = pos - 1 end
	end
	for k, l in ipairs(block) do table.insert(lines, pos + k, l) end
	if lines[#lines] ~= '' then lines[#lines + 1] = '' end
end

-- Schnell-Eingabe (Textfeld, @-Kurzbefehle); der Desktop nutzt inzwischen das Formular
function Add()
	local text = convertDates(trim(SKIN:GetVariable('NewItem') or ''))
	if text == '' then return end
	refresh(true)
	insertAtEnd({ '- [ ] ' .. text .. stamp(createdIcon) })
	save()
	refresh(true)
end

-- ---------- Formular (Config TaskBoard\Formular, form.lua) fuer neue Punkte und Rechtsklick > bearbeiten ----------
local dialog
-- i = 0: neuer Punkt, sonst Punkt i bearbeiten; top = 1: per Tastenkuerzel geoeffnet -> ueber allen Fenstern
function OpenDialog(i, top)
	refresh(true)
	local f
	if i == 0 then
		dialog = { mode = 'new' }
		f = { 'mode=new' }
	else
		local t = display[i]
		if not t then return end
		dialog = { mode = 'edit', line = t.line, orig = lines[t.line] }
		local h, mi = timeOf(t.text)
		local rule = ruleOf(t.text)
		f = { 'mode=edit', 'title=' .. trim(stripTags(stripDue(stripStamps(t.text)))),
			'date=' .. (t.text:match(dueIcon .. '%s*(' .. DATE .. ')') or ''),
			'time=' .. (h and string.format('%02d:%02d', h, mi) or ''),
			'rule=' .. (rule and (RULES[rule] or rule) or '') }
		for _, n in ipairs(t.notes) do f[#f + 1] = 'note=' .. n end
		for _, g in ipairs(tagsOf(t.text)) do f[#f + 1] = 'tag=' .. g end
	end
	-- angelegte Tags mit Farbe fuers Formular (es liest prefs.inc nicht selbst: dort steht auch die Listenbreite)
	for part in (SKIN:GetVariable('Tags') or ''):gmatch('[^,]+') do f[#f + 1] = 'tagdef=' .. trim(part) end
	local out = io.open(SKIN:GetVariable('@') .. 'dialog-in.txt', 'wb')
	if not out then dialog = nil return end
	out:write(table.concat(f, '\n'))
	out:close()
	-- Formular erscheint dort, wo sonst die Hilfe steht; ist es schon offen, liest es die neuen Werte ein
	SKIN:Bang('!DeactivateConfig', 'TaskBoard\\Einstellungen')
	SKIN:Bang('!ActivateConfig', 'TaskBoard\\Formular', 'Formular.ini')
	SKIN:Bang('!Refresh', 'TaskBoard\\Formular')
	SKIN:Bang('!ZPos', top == 1 and '1' or '-2', 'TaskBoard\\Formular')
end

function Edit(i) OpenDialog(i) end

function DialogDone()
	local d = dialog
	dialog = nil
	if not d then return end
	local r, notes, tags = {}, {}, {}
	local fh = io.open(SKIN:GetVariable('@') .. 'form-out.txt', 'rb')
	if not fh then return end
	local out = fh:read('*a')
	fh:close()
	os.remove(SKIN:GetVariable('@') .. 'form-out.txt')
	for l in out:gmatch('[^\r\n]+') do
		local k, v = l:match('^(%w+)=(.*)$')
		if k == 'note' then
			v = trim(v)
			if v ~= '' then notes[#notes + 1] = v end
		elseif k == 'tag' then
			v = trim(v):gsub('^#+', ''):gsub('%s+', '-')
			if v ~= '' and v:match('%D') then tags[#tags + 1] = v end
		elseif k then r[k] = trim(v) end
	end
	if r.action ~= 'save' and r.action ~= 'delete' then return end
	refresh(true)
	local t
	if d.mode == 'edit' then
		t = findTask(d.line, d.orig)
		if not t then return end
	end

	if r.action == 'delete' then
		if not t or not archive({ blockOf(t, '-') }) then return end
		for k = t.last, t.line, -1 do table.remove(lines, k) end
		save()
		return refresh(true)
	end

	if (r.title or '') == '' then return end
	local text = trim(stripTags(r.title))
	for _, g in ipairs(tags) do text = text .. ' #' .. g end
	if (r.rule or '') ~= '' then text = text .. ' ' .. repeatIcon .. ' ' .. r.rule end
	if (r.time or '') ~= '' then text = text .. ' ' .. timeIcon .. ' ' .. r.time end
	if (r.date or '') ~= '' then text = text .. ' ' .. dueIcon .. ' ' .. r.date end

	if d.mode == 'new' then
		text = text .. stamp(createdIcon)
		local block = { '- [ ] ' .. text }
		for _, n in ipairs(notes) do block[#block + 1] = '    - ' .. n end
		-- mit Datum: oben nach Faelligkeit einsortieren, sonst ans Ende
		if (r.date or '') == '' or not placeDated(block, dueTimeOf(text)) then insertAtEnd(block) end
		if #notes > 0 then expanded[stripMarker(text)] = true end
	else
		-- Punkt neu zusammensetzen: Kopfzeile, Unteraufgaben wie gehabt, dann die Notizen aus dem Formular
		local indent = lines[t.line]:match('^(%s*)')
		text = text .. stampsOf(t.text)
		local block = { lines[t.line]:match('^(%s*[-*+] %[[ xX]%])') .. ' ' .. text }
		for _, sub in ipairs(t.subs) do block[#block + 1] = lines[sub.line] end
		for _, n in ipairs(notes) do block[#block + 1] = indent .. '    - ' .. n end
		if expanded[stripMarker(t.text)] then expanded[stripMarker(text)] = true end
		for k = t.last, t.line, -1 do table.remove(lines, k) end
		-- Termin geaendert: offenen Punkt neu nach Faelligkeit einsortieren, sonst bleibt er an seinem Platz
		local moved = false
		if not t.done and indent == '' and (r.date or '') ~= '' and dueTimeOf(text) ~= dueTimeOf(t.text) then
			reparse()
			moved = placeDated(block, dueTimeOf(text))
		end
		if not moved then
			for k, l in ipairs(block) do table.insert(lines, t.line + k - 1, l) end
		end
	end
	save()
	refresh(true)
end

-- Rechtsklick auf Notiz: Notiz bearbeiten
function EditNote(n)
	local nm = noteMap[n]
	if not nm then return end
	local t = display[nm.task]
	local orig = lines[nm.line]
	edit = { mode = 'note', line = nm.line, orig = orig, taskLine = t.line, taskOrig = lines[t.line] }
	openEditor((orig:gsub('^%s+', ''):gsub('^[-*+] ', '')), 40, nm.y, width - 56)
end

-- Rechtsklick auf Unteraufgabe: Text bearbeiten
function EditSub(k)
	local sm = subMap[k]
	if not sm then return end
	local t = display[sm.task]
	local orig = lines[sm.line]
	local _, text = orig:match(CHECK)
	edit = { mode = 'sub', line = sm.line, orig = orig, taskLine = t.line, taskOrig = lines[t.line], stamps = stampsOf(text or '') }
	openEditor(datesToInput(stripStamps(text or '')), 40, sm.y, width - 56)
end

-- "+ Notiz" / "+ Unteraufgabe": neue Zeile unter dem Punkt
function AddNote(i)
	local t = display[i]
	if not t then return end
	edit = { mode = 'addnote', taskLine = t.line, taskOrig = lines[t.line] }
	openEditor('', 40, addY[i] or listTop, width - 56)
end

function AddSub(i)
	local t = display[i]
	if not t then return end
	edit = { mode = 'addsub', taskLine = t.line, taskOrig = lines[t.line] }
	openEditor('', 40, addY[i] or listTop, width - 56)
end

-- "+ Datei": Windows-Dateiauswahl starten, Ergebnis kommt in FilePicked()
local pendingFile
function PickFile(i)
	local t = display[i]
	if not t then return end
	pendingFile = { taskLine = t.line, taskOrig = lines[t.line] }
	SKIN:Bang('!CommandMeasure', 'MeasureFilePick', 'Run')
end

function FilePicked()
	local e = pendingFile
	pendingFile = nil
	if not e then return end
	local out = SKIN:GetMeasure('MeasureFilePick'):GetStringValue() or ''
	refresh(true)
	local t = findTask(e.taskLine, e.taskOrig)
	if not t then return end
	local indent = e.taskOrig:match('^(%s*)') .. '    '
	local pos = t.last
	for p in out:gmatch('[^\r\n]+') do
		p = trim(p)
		if p:match('^%a:\\') or p:match('^\\\\') then
			pos = pos + 1
			table.insert(lines, pos, indent .. '- ' .. p)
		end
	end
	if pos == t.last then return end
	expanded[stripMarker(t.text)] = true
	save()
	refresh(true)
end

-- Enter im Textfeld; leerer Text loescht Punkt, Notiz bzw. Unteraufgabe
function SaveEdit()
	if not edit then return end
	local e = edit
	edit = nil
	local text = convertDates(trim(SKIN:GetVariable('NewItem') or ''))
	-- leeres Feld darf weg (Notiz/Unteraufgabe) - aber ein ganzer Punkt wird beim Rausklicken nie geloescht, nur mit Enter
	if wasCommit() and text == '' and e.mode == 'task' then return end
	refresh(true)

	if e.mode == 'task' then
		local t = findTask(e.line, e.orig)
		if not t then return refresh(true) end
		if text == '' then
			-- geloeschter Punkt kommt samt Notizen als "- [-] … ❌ heute" ins Archiv
			if not archive({ blockOf(t, '-') }) then return refresh(true) end
			for k = t.last, t.line, -1 do table.remove(lines, k) end
		else
			text = text .. stampsOf(t.text)       -- Stempel und Kennung vom aktuellen Stand der Zeile
			if expanded[stripMarker(t.text)] then expanded[stripMarker(text)] = true end
			lines[t.line] = e.orig:match('^(%s*[-*+] %[[ xX]%])') .. ' ' .. text
		end

	elseif e.mode == 'note' or e.mode == 'sub' then
		local t = findTask(e.taskLine, e.taskOrig)
		if not t then return refresh(true) end
		local ln = findChild(t, e.line, e.orig)
		if not ln then return refresh(true) end
		if text == '' then
			table.remove(lines, ln)
		else
			-- Haekchen, Stempel und Kennung vom aktuellen Stand der Zeile (der Abgleich kann sie inzwischen geaendert haben)
			local cur = lines[ln]
			local prefix = cur:match('^(%s*[-*+] %[[ xX]%] )') or cur:match('^(%s*[-*+] )') or cur:match('^(%s*)')
			local _, curText = cur:match(CHECK)
			lines[ln] = prefix .. text .. (curText and stampsOf(curText) or '')
		end

	elseif e.mode == 'addnote' or e.mode == 'addsub' then
		if text == '' then return end
		local t = findTask(e.taskLine, e.taskOrig)
		if not t then return refresh(true) end
		local indent = e.taskOrig:match('^(%s*)') .. '    '
		if e.mode == 'addsub' then
			-- hinter die letzte Unteraufgabe, sonst direkt unter den Punkt
			local pos = t.line
			for _, sub in ipairs(t.subs) do if sub.line > pos then pos = sub.line end end
			table.insert(lines, pos + 1, indent .. '- [ ] ' .. text .. stamp(createdIcon))
		else
			table.insert(lines, t.last + 1, indent .. '- ' .. text)
			expanded[stripMarker(t.text)] = true
		end
	end

	save()
	refresh(true)
end

-- erledigte Punkte samt Notizen und erledigte Unteraufgaben ins Archiv verschieben
function Cleanup()
	refresh(true)
	local remove, blocks = {}, {}
	for _, t in ipairs(display) do
		if t.done then
			blocks[#blocks + 1] = blockOf(t, 'x')
			for k = t.line, t.last do remove[k] = true end
		else
			local parent = trim(stripDue(stripStamps(t.text)))
			for _, sub in ipairs(t.subs) do
				if sub.done then
					local line = '- [x] ' .. stripMarker(sub.text)
					if not sub.text:find(doneIcon, 1, true) then line = line .. stamp(doneIcon) end
					blocks[#blocks + 1] = { line .. ' · Unteraufgabe von „' .. parent .. '“' }
					remove[sub.line] = true
				end
			end
		end
	end
	-- nur entfernen, wenn das Archiv geschrieben werden konnte
	if not archive(blocks) then return end
	local kept = {}
	for n, line in ipairs(lines) do if not remove[n] then kept[#kept + 1] = line end end
	lines = kept
	save()
	refresh(true)
end

-- ---------- Einblenden (Anmelden, Aufwachen, Entsperren) ----------
-- Die Liste kommt fuer 10 Sekunden pro offenem Punkt (hoechstens 2 Minuten) ueber alle Fenster,
-- danach zurueck auf den Desktop. Aufgerufen per Aufgabenplanung (Anmelden/Entsperren) und aus Update().
function Reveal()
	if not lastOpen then refresh(true) end
	-- Datei noch nicht lesbar: merken und nachholen, sobald die Punkte da sind (hoechstens 5 Minuten)
	if not lastOpen then pendingReveal = os.time() return end
	if lastOpen == 0 then return end
	pendingReveal = nil
	local per = tonumber(SKIN:GetVariable('RevealPerItem')) or 10
	if per <= 0 then return end
	revealUntil = os.time() + math.min(120, per * lastOpen)
	if mode ~= 'desktop' then
		SKIN:Bang('!CommandMeasure', 'MeasureSide', 'Reveal()', RAND)
	else
		SKIN:Bang('!ZPos', '2')
	end
	render(lastOpen, lastDone)
end

-- button = true: Knopf "Ausblenden" (sofort weg); sonst Zeit abgelaufen (Seitenleiste bleibt, solange die Maus drin ist)
function HideReveal(button)
	if not revealUntil then return end
	revealUntil = nil
	if mode ~= 'desktop' then
		SKIN:Bang('!CommandMeasure', 'MeasureSide', button and 'Out()' or 'RevealEnd()', RAND)
	else
		SKIN:Bang('!ZPos', '-2')
	end
	render(lastOpen, lastDone)
end

-- 'both': vom Desktop-Platz zum bildschirmhohen Panel am Rand und zurueck (aufgerufen von sidebar.lua)
-- Desktop-Platz waehrend "Beides"-Panel zusaetzlich in einer Datei: wird die Liste neu geladen (Einstellung
-- geaendert, Rainmeter-Neustart, Abmelden), solange sie als Seitenleiste am Rand steht, findet sie so zurueck
local function panelFile() return SKIN:GetVariable('@') .. 'panel-pos.txt' end

function PanelOn()
	if panel then return end
	panel = true
	deskX, deskY = SKIN:GetX(), SKIN:GetY()
	local fh = io.open(panelFile(), 'wb')
	if fh then fh:write(deskX .. ' ' .. deskY); fh:close() end
	SKIN:Bang('!Hide')
	SKIN:Bang('!KeepOnScreen', '0')
	SKIN:Bang('!Draggable', '0')
	if lastOpen then render(lastOpen, lastDone) end
end
function PanelOff()
	if not panel then return end
	panel = false
	os.remove(panelFile())
	SKIN:Bang('!Hide')
	SKIN:Bang('!ZPos', '-2')
	if deskX then SKIN:Bang('!Move', deskX, deskY) end
	SKIN:Bang('!KeepOnScreen', '1')
	SKIN:Bang('!Draggable', '1')
	if lastOpen then render(lastOpen, lastDone) end
	SKIN:Bang('!Show')
end