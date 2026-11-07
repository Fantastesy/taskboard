-- Formular fuer neue Punkte und "bearbeiten" (Config TaskBoard\Formular), dunkel wie die Liste.
-- Liest @Resources\dialog-in.txt (schreibt todo.lua), schreibt @Resources\form-out.txt
-- und ruft danach DialogDone() in der Liste auf. Datei muss als UTF-16 LE gespeichert sein.

local res, width
local f                       -- mode, title, date (os.time 12 Uhr | nil), time ('HH:MM' | nil), rule, notes
local calOpen, calY, calM = false, nil, nil
local calView = 'days'        -- 'days' | 'months'
local clockOpen, clockMode, ch, cm = false, 'h', 12, 0
local custOpen, cn, cu, cdays = false, 1, 1, {}
local input                   -- laufende Eingabe: { kind = 'title' | 'time' | 'note', index }
local pending                 -- Klick, waehrend noch ein Eingabefeld offen war: erst Text uebernehmen, dann ausfuehren

local confirmDelete, errorText = false, nil
local shapeCount = 0
local c = {}

local MONTHS = { 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember' }
local WD = { 'Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag' }
local RULES = { '', 'täglich', 'werktags', 'wöchentlich', 'monatlich', 'jährlich' }
local TIMES = { '09:00', '12:00', '15:00', '18:00', '21:00' }
local MAXNOTES = 8
-- Tags: angelegt in den Einstellungen (kommen als "tagdef=name:farbe" mit), zugewiesen in f.tags
local MAXTAGDEFS = 8
local tagdefs = {}
local TAGCOL = {
	lila = { '138,108,245', '165,185,255' }, blau = { '60,130,240', '140,190,255' },
	gruen = { '50,170,100', '140,220,170' }, orange = { '235,135,40', '255,195,130' },
	rot = { '220,70,70', '255,160,160' }, pink = { '220,80,165', '255,165,215' },
	grau = { '140,140,154', '210,210,220' },
}
local function hasTag(name)
	for i, t in ipairs(f.tags) do if t:lower() == name:lower() then return i end end
end
local CW = 74                 -- Breite einer Kalenderspalte
local MONTHS3 = { 'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez' }
local UNITS = { 'Tage', 'Wochen', 'Monate', 'Jahre' }
local UNIT1 = { 'täglich', 'wöchentlich', 'monatlich', 'jährlich' }
local WDS = { 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So' }
local CLOCK_R, CLOCK_OUT, CLOCK_IN = 118, 96, 62   -- Zifferblatt, aeusserer / innerer Zahlenring

local function today()
	local d = os.date('*t')
	return os.time({ year = d.year, month = d.month, day = d.day, hour = 12 })
end
local function dayOf(y, m, d) return os.time({ year = y, month = m, day = d, hour = 12 }) end
local function iso(t) return os.date('%Y-%m-%d', t) end
local function sameDay(a, b) return a ~= nil and b ~= nil and iso(a) == iso(b) end
local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

-- ---------- eigene Wiederholung: "alle N Tage|Wochen|Monate|Jahre" oder Wochentage "Mo,Mi,Fr" ----------
-- Regeln mit eigenem Knopf (Nie … Monatlich); alles andere, auch "jährlich", laeuft ueber "Individuell …"
local CHIP_RULES = 5
local function isStandard(r)
	for k = 1, CHIP_RULES do if RULES[k] == r then return true end end
	return false
end
local function loadCustom(r)
	cn, cu, cdays = 1, 1, {}
	local n, u = r:match('^alle (%d+) (%S+)$')
	for k, x in ipairs(UNIT1) do if x == r then cu = k end end
	if n then
		cn = tonumber(n)
		for k, x in ipairs(UNITS) do if x == u then cu = k end end
	else
		for d in r:gmatch('%a%a') do
			for k, x in ipairs(WDS) do if x == d then cdays[k] = true end end
		end
	end
end
local function customRule()
	local days = {}
	for k = 1, 7 do if cdays[k] then days[#days + 1] = WDS[k] end end
	if #days > 0 then return table.concat(days, ',') end
	if cn == 1 then return UNIT1[cu] end
	return 'alle ' .. cn .. ' ' .. UNITS[cu]
end

function Initialize()
	res = SKIN:GetVariable('@')
	width = tonumber(SKIN:GetVariable('Width')) or 520
	for _, k in ipairs({ 'ColorText', 'ColorNote', 'ColorDone', 'ColorAccent', 'ColorCheck', 'ColorOver' }) do
		c[k] = SKIN:GetVariable(k)
	end
	f = { mode = 'new', title = '', rule = '', notes = {}, tags = {} }
	tagdefs = {}
	local fh = io.open(res .. 'dialog-in.txt', 'rb')
	if fh then
		for l in fh:read('*a'):gmatch('[^\r\n]+') do
			local k, v = l:match('^(%w+)=(.*)$')
			if k == 'note' then
				f.notes[#f.notes + 1] = v
			elseif k == 'tag' then
				f.tags[#f.tags + 1] = v
			elseif k == 'tagdef' then
				local name, col = v:match('^%s*(.-):(%a+)%s*$')
				if name and name ~= '' and #tagdefs < MAXTAGDEFS then tagdefs[#tagdefs + 1] = { name = name, color = col } end
			elseif k == 'date' then
				local y, m, d = v:match('(%d+)%-(%d+)%-(%d+)')
				if y then f.date = dayOf(tonumber(y), tonumber(m), tonumber(d)) end
			elseif k == 'time' then
				if v ~= '' then f.time = v end
			elseif k then
				f[k] = v
			end
		end
		fh:close()
	end
	local b = os.date('*t', f.date or today())
	calY, calM = b.year, b.month
	if f.rule ~= '' and not isStandard(f.rule) then loadCustom(f.rule) end
end

-- ---------- Anzeige ----------
local function set(m, opt, val) SKIN:Bang('!SetOption', m, opt, val) end
local function show(m, on) SKIN:Bang(on and '!ShowMeter' or '!HideMeter', m) end
local function heightOf(m)
	SKIN:Bang('!UpdateMeter', m)
	return SKIN:GetMeter(m):GetH()
end

local function summary()
	if errorText then return errorText end
	if not f.date and not f.time and f.rule == '' then return 'Ohne Termin – steht einfach auf der Liste.' end
	local day = f.date or today()
	local d = os.date('*t', day)
	local s
	if f.rule == 'täglich' then s = 'Täglich'
	elseif f.rule == 'werktags' then s = 'Werktags (Mo–Fr)'
	elseif f.rule == 'wöchentlich' then s = 'Jeden ' .. WD[d.wday]
	elseif f.rule == 'monatlich' then s = 'Jeden Monat am ' .. d.day .. '.'
	elseif f.rule == 'jährlich' then s = 'Jedes Jahr am ' .. d.day .. '. ' .. MONTHS[d.month]
	elseif f.rule ~= '' then
		local n, u = f.rule:match('^alle (%d+) (%S+)$')
		if n then s = 'Alle ' .. n .. ' ' .. u
		else
			local names = {}
			for x in f.rule:gmatch('%a%a') do names[#names + 1] = x end
			s = 'Jeden ' .. table.concat(names, ', ', 1, #names - 1) .. (#names > 1 and ' und ' or '') .. names[#names]
		end
	else
		local n = math.floor((day - today()) / 86400 + 0.5)
		if n == 0 then s = 'Fällig heute'
		elseif n == 1 then s = 'Fällig morgen'
		else s = 'Fällig ' .. WD[d.wday] .. ', ' .. d.day .. '. ' .. MONTHS[d.month] .. ' ' .. d.year end
	end
	if f.rule ~= '' then s = s .. ', ab ' .. (sameDay(day, today()) and 'heute' or os.date('%d.%m.', day)) end
	if f.time then s = s .. ' um ' .. f.time .. ' – mit Windows-Erinnerung' end
	return s .. '.'
end

local function render()
	local shapes = {}
	local function box(m, fill, stroke, r)
		local mt = SKIN:GetMeter(m)
		local s = string.format('Rectangle %d,%d,%d,%d,%d | Fill Color %s | StrokeWidth %d',
			mt:GetX(), mt:GetY(), mt:GetW(), mt:GetH(), r or 8, fill, stroke and 1 or 0)
		if stroke then s = s .. ' | Stroke Color ' .. stroke end
		shapes[#shapes + 1] = s
	end
	local chips = {}           -- { meter, selected }
	local function chip(m, y, selected, text)
		if y then set(m, 'Y', y) end
		if text then set(m, 'Text', text) end
		set(m, 'FontColor', selected and c.ColorText or c.ColorNote)
		show(m, true)
		chips[#chips + 1] = { m, selected }
	end

	set('MeterHead', 'Text', f.mode == 'edit' and 'Eintrag bearbeiten' or 'Neuer Eintrag')
	local y = 62
	set('LblTitle', 'Y', y); y = y + 24
	set('FieldTitle', 'Y', y)
	set('FieldTitle', 'Text', f.title ~= '' and f.title or 'Hier klicken und eintippen')
	set('FieldTitle', 'FontColor', f.title ~= '' and c.ColorText or c.ColorDone)
	y = y + heightOf('FieldTitle') + 18

	-- Faellig am
	set('LblDate', 'Y', y); y = y + 24
	local t0 = today()
	local quick = sameDay(f.date, t0) or sameDay(f.date, t0 + 86400) or sameDay(f.date, t0 + 7 * 86400)
	chip('DateNone', y, f.date == nil)
	chip('DateToday', nil, sameDay(f.date, t0))
	chip('DateTomorrow', nil, sameDay(f.date, t0 + 86400))
	chip('DateWeek', nil, sameDay(f.date, t0 + 7 * 86400))
	chip('DateCal', nil, (f.date ~= nil and not quick) or calOpen,
		(f.date and not quick) and os.date('%d.%m.%Y', f.date) or 'Datum wählen')
	y = y + 44

	-- Kalender: Kopf mit Jahr (« ») und Monat (‹ ›); Klick auf den Monatsnamen -> Monatsauswahl
	for _, m in ipairs({ 'CalPrevY', 'CalPrev', 'CalMonth', 'CalNext', 'CalNextY' }) do show(m, calOpen) end
	for k = 1, 7 do show('Wd' .. k, calOpen and calView == 'days') end
	local calCells = {}
	for k = 1, 12 do show('Mon' .. k, calOpen and calView == 'months') end
	if calOpen and calView == 'months' then
		for _, m in ipairs({ 'CalPrevY', 'CalPrev', 'CalNext', 'CalNextY' }) do set(m, 'Y', y) end
		set('CalMonth', 'Y', y + 4)
		set('CalMonth', 'Text', tostring(calY))
		show('CalPrev', false); show('CalNext', false)
		y = y + 44
		local mw = math.floor((width - 40) / 4)
		for k = 1, 12 do
			local row, col = math.floor((k - 1) / 4), (k - 1) % 4
			local my = y + row * 44
			set('Mon' .. k, 'Y', my)
			set('Mon' .. k, 'X', 20 + col * mw + mw / 2)
			local sel = calM == k
			set('Mon' .. k, 'FontColor', sel and c.ColorText or c.ColorNote)
			calCells[#calCells + 1] = { x = 20 + col * mw + 4, y = my, w = mw - 8, sel = sel }
		end
		y = y + 3 * 44 + 10
		for k = 1, 42 do show('Day' .. k, false) end
	elseif calOpen then
		for _, m in ipairs({ 'CalPrevY', 'CalPrev', 'CalNext', 'CalNextY' }) do set(m, 'Y', y) end
		set('CalMonth', 'Y', y + 4)
		set('CalMonth', 'Text', MONTHS[calM] .. ' ' .. calY)
		y = y + 44
		for k = 1, 7 do set('Wd' .. k, 'Y', y) end
		y = y + 26
		local first = dayOf(calY, calM, 1)
		local offset = (os.date('*t', first).wday + 5) % 7      -- Montag = 0
		for k = 1, 42 do
			local m = 'Day' .. k
			local t = first + (k - 1 - offset) * 86400
			local d = os.date('*t', t)
			if d.month == calM then
				local row, col = math.floor((k - 1) / 7), (k - 1) % 7
				local cy = y + row * 36
				set(m, 'Text', tostring(d.day))
				set(m, 'Y', cy)
				local sel, isToday = sameDay(f.date, t), sameDay(t, t0)
				set(m, 'FontColor', sel and c.ColorText or (isToday and c.ColorAccent or c.ColorNote))
				show(m, true)
				calCells[#calCells + 1] = { x = 20 + col * CW + 4, y = cy, w = CW - 8, sel = sel, today = isToday }
			else
				show(m, false)
			end
		end
		local rows = math.ceil((offset + os.date('*t', dayOf(calY, calM + 1, 0)).day) / 7)
		y = y + rows * 36 + 10
	else
		for k = 1, 42 do show('Day' .. k, false) end
	end

	-- Uhrzeit
	set('LblTime', 'Y', y); y = y + 24
	local custom = f.time ~= nil
	chip('TimeNone', y, f.time == nil)
	for k, t in ipairs(TIMES) do
		chip('Time' .. k, nil, f.time == t)
		if f.time == t then custom = false end
	end
	chip('TimeOther', nil, custom or clockOpen, custom and f.time or 'Andere')
	y = y + 44

	-- Uhr wie im Google-Kalender: erst Stunde (aussen 1–12, innen 13–00), dann Minute (5er-Schritte)
	for _, m in ipairs({ 'ClockH', 'ClockColon', 'ClockM' }) do show(m, clockOpen) end
	if clockOpen then
		set('ClockH', 'Text', string.format('%02d', ch)); set('ClockM', 'Text', string.format('%02d', cm))
		set('ClockH', 'FontColor', clockMode == 'h' and c.ColorText or c.ColorDone)
		set('ClockM', 'FontColor', clockMode == 'm' and c.ColorText or c.ColorDone)
		for _, m in ipairs({ 'ClockH', 'ClockColon', 'ClockM' }) do set(m, 'Y', y) end
		y = y + 52
		local cx, cy = width / 2, y + CLOCK_R
		shapes[#shapes + 1] = string.format('Ellipse %d,%d,%d | Fill Color 255,255,255,12 | StrokeWidth 0', cx, cy, CLOCK_R)
		local selX, selY
		for k = 1, 24 do
			local m = 'Clock' .. k
			local label, r, angle
			if clockMode == 'h' then
				r = k <= 12 and CLOCK_OUT or CLOCK_IN
				angle = (k % 12) * 30
				label = k == 24 and '00' or tostring(k)
				if (ch == k) or (ch == 0 and k == 24) then selX, selY = r, angle end
			elseif k <= 12 then
				r, angle = CLOCK_OUT, (k % 12) * 30
				label = string.format('%02d', (k % 12) * 5)
				if math.floor(cm / 5 + 0.5) % 12 == k % 12 then selX, selY = r, angle end
			end
			if label then
				local a = math.rad(angle)
				set(m, 'Text', label)
				set(m, 'X', math.floor(cx + r * math.sin(a)))
				set(m, 'Y', math.floor(cy - r * math.cos(a)))
				set(m, 'FontSize', r == CLOCK_IN and 9 or 11)
				set(m, 'FontColor', (selX == r and selY == angle) and c.ColorText or (r == CLOCK_IN and c.ColorDone or c.ColorNote))
				show(m, true)
			else
				show(m, false)
			end
		end
		if selX then
			local a = math.rad(selY)
			local sx, sy = cx + selX * math.sin(a), cy - selX * math.cos(a)
			shapes[#shapes + 1] = string.format('Line %d,%d,%d,%d | StrokeWidth 2 | Stroke Color %s', cx, cy, sx, sy, c.ColorCheck)
			shapes[#shapes + 1] = string.format('Ellipse %d,%d,4 | Fill Color %s | StrokeWidth 0', cx, cy, c.ColorCheck)
			shapes[#shapes + 1] = string.format('Ellipse %d,%d,17 | Fill Color %s | StrokeWidth 0', sx, sy, c.ColorCheck)
		end
		y = y + 2 * CLOCK_R + 14
		chip('ClockCancel', y, false)
		chip('ClockOk', nil, true)
		y = y + 46
	else
		for k = 1, 24 do show('Clock' .. k, false) end
		show('ClockCancel', false); show('ClockOk', false)
	end

	-- Wiederholen (7 = Individuell, mit eigener Zeile darunter)
	set('LblRule', 'Y', y); y = y + 24
	local isCustom = f.rule ~= '' and not isStandard(f.rule)
	for k = 1, CHIP_RULES do chip('Rule' .. k, k == 1 and y or nil, f.rule == RULES[k] and not custOpen) end
	chip('Rule7', nil, isCustom or custOpen)
	y = y + 44
	for _, m in ipairs({ 'CustAlle', 'CustN', 'CustOder' }) do show(m, custOpen) end
	if custOpen then
		set('CustAlle', 'Y', y)
		chip('CustMinus', y, false)
		set('CustN', 'Text', tostring(cn))
		chip('CustPlus', nil, false)
		for k = 1, 4 do chip('CustU' .. k, nil, cu == k and next(cdays) == nil) end
		y = y + 44
		set('CustOder', 'Y', y); y = y + 24
		for k = 1, 7 do chip('CustWd' .. k, k == 1 and y or nil, cdays[k] == true) end
		y = y + 46
	else
		for _, m in ipairs({ 'CustMinus', 'CustPlus' }) do show(m, false) end
		for k = 1, 4 do show('CustU' .. k, false) end
		for k = 1, 7 do show('CustWd' .. k, false) end
	end

	-- Tags (Knoepfe in Zeilen, umbrechen wenn die Breite nicht reicht); ausgewaehlt = in der Farbe des Tags
	set('LblTags', 'Y', y); y = y + 24
	local tx = 20
	for k = 1, MAXTAGDEFS do
		local d, m = tagdefs[k], 'TagChip' .. k
		if d then
			local col = TAGCOL[d.color] or TAGCOL.grau
			local on = hasTag(d.name) ~= nil
			set(m, 'Text', d.name)
			SKIN:Bang('!UpdateMeter', m)
			local w = SKIN:GetMeter(m):GetW()
			if tx > 20 and tx + w > width - 20 then tx = 20; y = y + 44 end
			set(m, 'X', tx); set(m, 'Y', y)
			show(m, true)
			set(m, 'FontColor', on and c.ColorText or (col[2] .. ',255'))
			chips[#chips + 1] = { m, on, on and (col[1] .. ',255') or '255,255,255,16' }
			tx = tx + w + 6
		else
			show(m, false)
		end
	end
	show('TagHint', #tagdefs == 0)
	if #tagdefs == 0 then set('TagHint', 'Y', y); y = y + 34 else y = y + 44 end

	-- Zusammenfassung
	set('Summary', 'Y', y)
	set('Summary', 'Text', summary())
	set('Summary', 'FontColor', errorText and c.ColorOver or c.ColorAccent)
	local sh = heightOf('Summary')
	shapes[#shapes + 1] = string.format('Rectangle 20,%d,%d,%d,8 | Fill Color 138,108,245,40 | StrokeWidth 0', y, width - 40, sh)
	y = y + sh + 18

	-- Notizen
	set('LblNotes', 'Y', y); y = y + 26
	for k = 1, MAXNOTES do
		local n = f.notes[k]
		show('Note' .. k, n ~= nil); show('NoteDel' .. k, n ~= nil)
		if n then
			set('Note' .. k, 'Text', n ~= '' and n or '\194\160')   -- neue, noch leere Zeile (geschuetztes Leerzeichen: volle Zeilenhoehe)
			set('Note' .. k, 'Y', y)
			set('NoteDel' .. k, 'Y', y)
			local h = heightOf('Note' .. k)
			shapes[#shapes + 1] = string.format('Rectangle 20,%d,%d,%d,8 | Fill Color 255,255,255,12 | StrokeWidth 0', y, width - 40, h)
			y = y + h + 6
		end
	end
	chip('NoteAdd', y, false)
	chip('FileAdd', nil, false)
	show('NoteAdd', #f.notes < MAXNOTES); show('FileAdd', #f.notes < MAXNOTES)
	y = y + 56

	-- Knoepfe
	set('BtnDelete', 'Y', y)
	set('BtnDelete', 'Text', confirmDelete and 'Wirklich löschen?' or 'Löschen')
	set('BtnDelete', 'FontColor', '255,140,140,255')
	show('BtnDelete', f.mode == 'edit')
	set('BtnSave', 'Y', y); set('BtnCancel', 'Y', y)
	SKIN:Bang('!UpdateMeter', 'BtnSave'); SKIN:Bang('!UpdateMeter', 'BtnCancel')
	local saveX = width - 20 - SKIN:GetMeter('BtnSave'):GetW()
	set('BtnSave', 'X', saveX)
	set('BtnCancel', 'X', saveX - 10 - SKIN:GetMeter('BtnCancel'):GetW())
	local bottom = y + 34 + 22

	SKIN:Bang('!UpdateMeter', '*')

	-- abgerundete Flaechen hinter Feldern, Knoepfen und Kalendertagen
	box('FieldTitle', '255,255,255,14', input and input.kind == 'title' and c.ColorCheck or '255,255,255,40')
	for _, ch in ipairs(chips) do
		local m, sel = ch[1], ch[2]
		if not (m == 'NoteAdd' or m == 'FileAdd') or #f.notes < MAXNOTES then
			box(m, ch[3] or (sel and c.ColorCheck or '255,255,255,16'))
		end
	end
	for _, cell in ipairs(calCells) do
		if cell.sel then
			shapes[#shapes + 1] = string.format('Rectangle %d,%d,%d,32,8 | Fill Color %s | StrokeWidth 0', cell.x, cell.y, cell.w, c.ColorCheck)
		elseif cell.today then
			shapes[#shapes + 1] = string.format('Rectangle %d,%d,%d,32,8 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke Color %s', cell.x, cell.y, cell.w, c.ColorAccent)
		end
	end
	if f.mode == 'edit' then box('BtnDelete', confirmDelete and '255,115,115,60' or '255,255,255,10') end
	box('BtnCancel', '255,255,255,16')
	box('BtnSave', c.ColorCheck)

	for k = 1, math.max(#shapes, shapeCount) do
		set('MeterShapes', k == 1 and 'Shape' or ('Shape' .. k), shapes[k] or 'Rectangle 0,0,0,0 | StrokeWidth 0')
	end
	shapeCount = #shapes
	set('MeterBg', 'Shape', 'Rectangle 0,0,' .. width .. ',' .. bottom .. ',12 | Fill Color #ColorBg# | StrokeWidth 0')
	SKIN:Bang('!UpdateMeter', '*')
	SKIN:Bang('!Redraw')
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

local drawn = false
local autoOpen          -- neuer Punkt: Titelfeld oeffnen, sobald das Fenster stillsteht
local openInput
function Update()
	-- Notbremse: kam vom Waechter nichts zurueck, den Text jetzt uebernehmen lassen (InputDone fuehrt
	-- den gemerkten Klick dann aus). Hilft auch das nicht, den Klick trotzdem ausfuehren.
	keepWatch(input ~= nil)
	if pending then
		local age = os.time() - pending.at
		if age >= 1 and not pending.kicked then
			pending.kicked = true
			local dir = SKIN:GetVariable('@')
			os.remove(dir .. 'commit.flag')
			SKIN:Bang('["' .. dir .. 'TaskBoardHotkey.exe" --commit-now]')
		elseif age >= 4 then
			local p = pending
			pending, input = nil, nil
			Click(p.what, p.arg)
		end
	end
	if not drawn then
		drawn = true
		render()
		-- neuer Punkt: gleich ins To-do-Feld zum Tippen. Aber erst, wenn das Fenster seine Groesse und
		-- seinen Platz hat: es ist mittig verankert und wandert beim ersten Zeichnen noch. Ein vorher
		-- geoeffnetes Feld bliebe an der alten Stelle stehen (ueber dem Formular).
		if f.mode == 'new' and f.title == '' then autoOpen = { y = nil, n = 0 } end
	elseif autoOpen then
		local y = SKIN:GetVariable('CURRENTCONFIGY')
		autoOpen.n = autoOpen.n + 1
		if (y == autoOpen.y and autoOpen.n >= 2) or autoOpen.n >= 10 then
			local a = autoOpen; autoOpen = nil
			if not input then openInput(a.kind or 'title', '', a.meter or 'FieldTitle', a.index) end
		else
			autoOpen.y = y
		end
	end
	return 0
end

-- ---------- Eingabefeld (InputText) ----------
-- Das Windows-Eingabefeld kennt keinen Innenabstand und schreibt oben links. Darum genau
-- auf den Text des Feldes legen (Abstand links/oben wie dessen Padding), gleiche Schrift.
function openInput(kind, text, meter, index)
	input = { kind = kind, index = index }
	local mt = SKIN:GetMeter(meter)
	-- das Eingabefeld hat selbst ca. 8 px Rand links, darum Padding minus 8
	local padL, padT, size, bold = 4, 6, 11, '0'
	if meter == 'FieldTitle' then padL, padT, size, bold = 8, 6, 13, '1' end
	SKIN:Bang('!SetVariable', 'InText', text or '')
	SKIN:Bang('!SetVariable', 'InX', mt:GetX() + padL)
	SKIN:Bang('!SetVariable', 'InY', mt:GetY() + padT)
	SKIN:Bang('!SetVariable', 'InH', math.max(mt:GetH() - padT - 4, 22))
	SKIN:Bang('!SetVariable', 'InSize', size)
	SKIN:Bang('!SetVariable', 'InStyle', bold == '1' and 'Bold' or 'Normal')
	SKIN:Bang('!SetVariable', 'InW', width - 40 - padL - 12)
	SKIN:Bang('!UpdateMeasure', 'MeasureInput')
	SKIN:Bang('!CommandMeasure', 'MeasureInput', 'ExecuteBatch 1')
	commitWatch()
end

local function parseTime(s)
	local h, m = s:match('^(%d%d?)[:%.]?(%d%d)$')
	if not h then h = s:match('^(%d%d?)$'); m = '00' end
	if h and tonumber(h) < 24 and tonumber(m) < 60 then return string.format('%02d:%s', tonumber(h), m) end
end

-- Uhrzeit oder Wiederholung ohne Datum -> ab heute
local function needDate() if not f.date then f.date = today() end end

-- Eingabe abgebrochen (Esc): gemerkten Klick trotzdem ausfuehren
function InputCancel()
	if not input then return end
	local e = input
	input = nil
	-- neue Notizzeile ohne Text: wieder weg
	if e.kind == 'note' and f.notes[e.index] == '' then table.remove(f.notes, e.index) end
	local p = pending
	pending = nil
	if p then return Click(p.what, p.arg) end
	render()
end

function InputDone()
	local e = input
	input = nil
	local commit = wasCommit()      -- rausgeklickt statt Enter
	local p = pending
	pending = nil
	if not e then return end
	local v = trim(SKIN:GetVariable('Input') or '')
	errorText = nil
	if e.kind == 'title' then
		if v ~= '' or not commit then f.title = v end
		-- Enter im Titelfeld = sofort speichern (nicht beim Rausklicken)
		if v ~= '' and not commit and not p then return Click('save') end
	elseif e.kind == 'time' then
		if v == '' then f.time = nil
		else
			local t = parseTime(v)
			if t then f.time = t; needDate() else errorText = '„' .. v .. '“ ist keine Uhrzeit – bitte z. B. 15:00 eingeben.' end
		end
	elseif e.kind == 'note' then
		if v == '' then
			-- leeres Feld darf weg (auch beim Rausklicken)
			if f.notes[e.index] then table.remove(f.notes, e.index) end
		else
			f.notes[e.index] = v
		end
	end
	if p then return Click(p.what, p.arg) end
	render()
end

function FilePicked()
	local out = SKIN:GetMeasure('MeasureFilePick'):GetStringValue() or ''
	for p in out:gmatch('[^\r\n]+') do
		p = trim(p)
		if #f.notes < MAXNOTES and (p:match('^%a:\\') or p:match('^\\\\')) then f.notes[#f.notes + 1] = p end
	end
	render()
end

-- ---------- Klicks ----------
local function finish(action)
	local out = { 'action=' .. action }
	if action == 'save' then
		if f.time or f.rule ~= '' then needDate() end
		out[#out + 1] = 'title=' .. f.title
		out[#out + 1] = 'date=' .. (f.date and iso(f.date) or '')
		out[#out + 1] = 'time=' .. (f.time or '')
		out[#out + 1] = 'rule=' .. f.rule
		for _, n in ipairs(f.notes) do if trim(n) ~= '' then out[#out + 1] = 'note=' .. n end end
		for _, t in ipairs(f.tags) do out[#out + 1] = 'tag=' .. t end
	end
	local fh = io.open(res .. 'form-out.txt', 'wb')
	if fh then fh:write(table.concat(out, '\n')); fh:close() end
	SKIN:Bang('!CommandMeasure', 'MeasureTodo', 'DialogDone()', 'TaskBoard')
	SKIN:Bang('!DeactivateConfig')
end

function Click(what, arg)
	-- Eingabefeld noch offen: erst den Text uebernehmen lassen (Waechter drueckt Enter), dann diesen Klick
	if input then
		pending = { what = what, arg = arg, at = os.time() }
		return
	end
	-- vor dem Oeffnen der neuen Notizzeile woanders geklickt: leere Zeile wieder weg
	if autoOpen and autoOpen.kind == 'note' then
		if f.notes[autoOpen.index] == '' then table.remove(f.notes, autoOpen.index) end
		autoOpen = nil
	end
	errorText = nil
	if what ~= 'delete' then confirmDelete = false end
	if what == 'title' then return openInput('title', f.title, 'FieldTitle')
	elseif what == 'date' then f.date = today() + arg * 86400; calOpen = false
	elseif what == 'nodate' then f.date = nil; f.time = nil; f.rule = ''; calOpen = false; clockOpen = false; custOpen = false
	elseif what == 'cal' then
		calOpen = not calOpen
		calView = 'days'
		clockOpen = false
		local b = os.date('*t', f.date or today())
		calY, calM = b.year, b.month
	elseif what == 'month' then
		calM = calM + arg
		if calM < 1 then calM, calY = 12, calY - 1 elseif calM > 12 then calM, calY = 1, calY + 1 end
	elseif what == 'year' then calY = calY + arg
	elseif what == 'monthview' then calView = calView == 'days' and 'months' or 'days'
	elseif what == 'pickmonth' then calM = arg; calView = 'days'
	elseif what == 'timeother' then
		clockOpen = not clockOpen
		calOpen = false
		clockMode = 'h'
		local h, m = (f.time or ''):match('^(%d+):(%d+)$')
		if h then ch, cm = tonumber(h), tonumber(m)
		else local now = os.date('*t'); ch, cm = (now.hour + 1) % 24, 0 end
	elseif what == 'clockmode' then clockMode = arg
	elseif what == 'clock' then
		if clockMode == 'h' then
			ch = arg == 24 and 0 or arg
			clockMode = 'm'
		else
			cm = (arg % 12) * 5
			f.time = string.format('%02d:%02d', ch, cm); needDate()
			clockOpen = false
		end
	elseif what == 'clockok' then
		f.time = string.format('%02d:%02d', ch, cm); needDate()
		clockOpen = false
	elseif what == 'clockcancel' then clockOpen = false
	elseif what == 'custom' then
		custOpen = not custOpen
		if custOpen then
			if f.rule == '' or isStandard(f.rule) then loadCustom('') end
			f.rule = customRule(); needDate()
		end
	elseif what == 'custn' then cn = math.max(1, math.min(99, cn + arg)); cdays = {}; f.rule = customRule(); needDate()
	elseif what == 'custu' then cu = arg; cdays = {}; f.rule = customRule(); needDate()
	elseif what == 'custwd' then cdays[arg] = (not cdays[arg]) or nil; f.rule = customRule(); needDate()
	elseif what == 'day' then
		local first = dayOf(calY, calM, 1)
		local offset = (os.date('*t', first).wday + 5) % 7
		f.date = first + (arg - 1 - offset) * 86400
		calOpen = false
	elseif what == 'time' then f.time = TIMES[arg]; clockOpen = false; needDate()
	elseif what == 'notime' then f.time = nil; clockOpen = false
	elseif what == 'rule' then f.rule = RULES[arg]; custOpen = false; if f.rule ~= '' then needDate() end
	elseif what == 'note' then return openInput('note', f.notes[arg], 'Note' .. arg, arg)
	elseif what == 'notedel' then table.remove(f.notes, arg)
	elseif what == 'tag' then
		local d = tagdefs[arg]
		if d then
			local i = hasTag(d.name)
			if i then table.remove(f.tags, i) else f.tags[#f.tags + 1] = d.name end
		end
	elseif what == 'noteadd' then
		-- erst eine leere Notizzeile zeichnen und das Feld dort oeffnen (nicht auf dem Knopf).
		-- Wie beim Titel erst, wenn das mittig verankerte Fenster nach dem Wachsen stillsteht.
		local k = #f.notes + 1
		f.notes[k] = ''
		render()
		autoOpen = { y = nil, n = 0, kind = 'note', meter = 'Note' .. k, index = k }
		return
	elseif what == 'file' then return SKIN:Bang('!CommandMeasure', 'MeasureFilePick', 'Run')
	elseif what == 'cancel' then return SKIN:Bang('!DeactivateConfig')
	elseif what == 'delete' then
		if confirmDelete then return finish('delete') end
		confirmDelete = true
	elseif what == 'save' then
		if trim(f.title) == '' then
			errorText = 'Bitte zuerst eintragen, was zu tun ist.'
			render()
			return openInput('title', '', 'FieldTitle')
		end
		return finish('save')
	end
	render()
end
