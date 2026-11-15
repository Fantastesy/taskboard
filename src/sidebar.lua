-- Seitenleiste fuer die Rainmeter-Todo-Liste (Config TaskBoard\Rand).
-- Ein unsichtbarer, 1 Pixel schmaler Streifen am rechten (oder linken) Rand des Hauptbildschirms, immer im
-- Vordergrund. Beruehrt die Maus den Rand, faehrt die Liste (Config TaskBoard) als Panel von aussen herein;
-- verlaesst die Maus die Liste, faehrt sie nach kurzer Zeit wieder hinaus. Ein Klick in ein anderes Fenster
-- (Waechter "TaskBoardHotkey.exe --panel-watch") oder auf das X der Liste schiebt sie sofort hinaus.
--
-- Einstellungen (prefs.inc, schreibt das Einstellungen-Fenster):
--   Mode       'sidebar' (nur Seitenleiste) | 'both' (liegt auf dem Desktop UND faehrt am Rand als Panel herein)
--              | 'desktop' (dieser Streifen wird nicht gebraucht)
--   Side       'right' | 'left'
--   Speed      'fast' | 'normal' | 'slow'  (Animationsdauer und Wartezeit nach Maus-weg)
--   OpenDelay  0 | 500 | 1000  (Millisekunden, so lange muss die Maus am Rand bleiben, bevor die Liste kommt)
--
-- Bei 'both' sagt der Streifen der Liste vorher PanelOn() (Desktop-Platz merken, Panel werden) und
-- nachher PanelOff() (zurueck an den Desktop-Platz). Laeuft mit Update=16, tut aber nur bei Animation etwas.

local LIST = 'TaskBoard'
local MARGIN = 8           -- Abstand zum Bildschirmrand oben, unten und seitlich (wie eine schwebende KDE-Leiste)
local EDGE_FREE = 0.2      -- Anteil der Hoehe oben und unten ohne Rand-Streifen (Ecken loesen nichts aus)
-- Dauer der Animation und Sekunden bis zum Hinausfahren nach Maus-weg (wie KDE). Die Animation richtet sich nach
-- der Uhr, nicht nach gezaehlten Bildern: Rainmeter liefert die Bilder unregelmaessig (mal 15, mal 31 ms), mit
-- festen Schritten pro Bild ruckelte die Bewegung.
local SPEEDS = {
	fast = { slide = 0.15, leave = 0.3 },
	normal = { slide = 0.25, leave = 1 },
	slow = { slide = 0.4, leave = 2 },
}
-- Vom Rand zur Liste: so lange bleibt sie offen, bis die Maus die Liste erreicht hat. Frueher hielt eine
-- unsichtbare Flaeche unter der Liste sie offen - die fing aber alle Klicks auf den Desktop darunter ab.
local GRACE = 1.5

local mode, side, width, left, right, top
local slideDur, leaveDelay, openDelay
local state = 'hidden'     -- hidden | sliding_in | shown | sliding_out | fade_away | fade_back
local prog = 0             -- Fortschritt der laufenden Animation (0..1)
local phaseAt, phaseFrom = 0, 0   -- Animation begann zum Zeitpunkt phaseAt bei Fortschritt phaseFrom
local leaveAt = nil        -- Zeitpunkt (now()), ab dem hinausgefahren wird (Zeit statt Bilder: Rainmeter
                           -- schafft nicht ueberall 60 Bilder pro Sekunde)
local openAt = nil         -- Zeitpunkt, ab dem hereingefahren wird (Einstellung "Seitenleiste öffnen")
local edgeLeftAt = nil     -- wann die Maus den Rand zuletzt verlassen hat
-- Der Streifen ist 1 Pixel breit: zittert die Hand ein Pixel nach links, meldet Rainmeter "Rand verlassen" und
-- gleich wieder "Rand beruehrt" (im Protokoll alle 1-2 ms). So lange darf die Maus weg sein, ohne dass die
-- Wartezeit fuers Oeffnen abbricht.
local JITTER = 0.15
local revealing = false    -- vom Einblenden (Anmelden/Aufwachen) geoeffnet: bleibt, bis RevealEnd()
local onEdge, inList = false, false
local wasInList = false    -- seit dem Hereinfahren schon einmal in der Liste gewesen (sonst gilt GRACE)
local watching = false     -- panel-open.flag liegt da, der Klick-Waechter laeuft

local function num(v, d) return tonumber(SKIN:GetVariable(v)) or d end


-- Uhr mit Millisekunden: os.clock() misst unter Windows (MSVC) die echte Zeit seit dem Programmstart.
-- Nach rund 24 Tagen Laufzeit liefert clock() -1; dann reichen ganze Sekunden.
local function now()
	local c = os.clock()
	if c > 0 then return c end
	return os.time()
end

-- Klick-Waechter: laeuft, solange panel-open.flag da ist. Klickt man in ein fremdes Fenster oder tippt dort,
-- ruft er CloseSide() in der Liste auf (hotkey.cs PanelWatch).
local function flagPath() return SKIN:GetVariable('@') .. 'panel-open.flag' end
local function watch(on)
	if on == watching then return end
	watching = on
	if not on then os.remove(flagPath()) return end
	local fh = io.open(flagPath(), 'wb')
	if not fh then watching = false return end
	fh:write('1')
	fh:close()
	SKIN:Bang('["' .. SKIN:GetVariable('@') .. 'TaskBoardHotkey.exe" --panel-watch "' .. SKIN:GetVariable('PROGRAMPATH') .. 'Rainmeter.exe"]')
end

function Initialize()
	mode = SKIN:GetVariable('Mode') or 'sidebar'
	side = SKIN:GetVariable('Side') == 'left' and 'left' or 'right'
	local sp = SPEEDS[SKIN:GetVariable('Speed') or 'normal'] or SPEEDS.normal
	slideDur, leaveDelay = sp.slide, sp.leave
	openDelay = math.max(0, num('OpenDelay', 0)) / 1000
	width = num('Width', 460)
	left = num('WORKAREAX', 0)
	right = left + num('WORKAREAWIDTH', 1920)
	top = num('WORKAREAY', 0)
	-- alter Waechter von vorher (Rainmeter neu geladen, waehrend die Liste offen war): beenden
	watching = true
	watch(false)
	-- Streifen an den Rand, nur im mittleren Teil der Hoehe (Ecken mit Schliessen-Knoepfen, Uhr usw. bleiben frei);
	-- letzte Pixelspalte (dort bleibt die Maus haengen)
	local h = num('WORKAREAHEIGHT', 1080)
	local free = math.floor(h * EDGE_FREE)
	SKIN:Bang('!SetOption', 'MeterEdge', 'H', h - 2 * free)
	SKIN:Bang('!UpdateMeter', 'MeterEdge')
	SKIN:Bang('!Move', side == 'left' and left or right - 1, top + free)
end

-- Position der Liste fuer einen Fortschritt p (0 = draussen, 1 = ganz drin), sanft abbremsend
local function place(p)
	local e = 1 - (1 - p) ^ 3
	local x
	if side == 'left' then
		x = left - width + (width + MARGIN) * e
	else
		x = right - (width + MARGIN) * e
	end
	SKIN:Bang('!Move', math.floor(x + 0.5), top + MARGIN, LIST)
end

-- 'both': die Desktop-Liste blendet erst sanft aus (fade_away), dann faehrt das Panel herein; nach dem
-- Hinausfahren steht sie wieder an ihrem Platz und blendet sanft ein (fade_back). Kurz, weil man waehrenddessen
-- auf den Rand schaut und dort noch nichts passiert.
local function fadeDur() return math.min(0.15, slideDur) end

-- Animation beginnen (oder umkehren: from = 1 - bisheriger Fortschritt). Erst nach der Arbeit davor aufrufen
-- (Liste umbauen dauert 20-30 ms), sonst fehlt am Anfang ein Stueck der Bewegung.
local function begin(newState, from)
	state = newState
	phaseFrom = from or 0
	prog = phaseFrom
	phaseAt = now()
end
local function advance(dur)
	prog = math.min(1, phaseFrom + (now() - phaseAt) / dur)
	return prog
end

local function startPanel()
	-- Liste merkt sich ihren Desktop-Platz und wird zum Panel (unsichtbar umgebaut)
	SKIN:Bang('!CommandMeasure', 'MeasureTodo', 'PanelOn()', LIST)
	place(0)
	SKIN:Bang('!ZPos', '2', LIST)
	SKIN:Bang('!SetTransparency', '255', LIST)
	SKIN:Bang('!Show', LIST)
	begin('sliding_in')
end

-- Reihenfolge in slideIn/slideOut: erst den neuen Zustand setzen, den Waechter zuletzt starten. Beim Starten
-- eines Programms arbeitet Windows schon die naechsten Meldungen ab, und mit der echten Maus kommen am Rand
-- EdgeHit/EdgeLeave alle 1-2 ms. Stand der Start frueher am Anfang, lief ein zweites slideIn mitten im ersten;
-- das erste fuhr danach die Desktop-Liste ohne PanelOn() an den Rand, und sie blieb oben rechts haengen.
local function slideIn()
	if state == 'fade_back' then
		-- war gerade beim Wieder-Einblenden: von dort aus wieder ausblenden
		begin('fade_away', 1 - prog)
	elseif state == 'sliding_out' then
		begin('sliding_in', 1 - prog)   -- war gerade beim Hinausfahren: von dort aus umkehren
	elseif state == 'hidden' then
		-- frisch geoeffnet: oben anfangen und die Maus muss erst noch zur Liste
		wasInList = inList
		if mode == 'both' then
			begin('fade_away')
		else
			begin('sliding_in')
			place(0)
			SKIN:Bang('!ZPos', '2', LIST)
			SKIN:Bang('!Show', LIST)
		end
		SKIN:Bang('!CommandMeasure', 'MeasureTodo', 'ScrollTop()', LIST)
	else
		return   -- schon offen oder auf dem Weg dorthin
	end
	watch(true)
end

local function slideOut()
	if state == 'fade_away' then
		-- noch gar nicht hereingefahren: einfach wieder einblenden
		begin('fade_back', 1 - prog)
	elseif state == 'sliding_in' then
		begin('sliding_out', 1 - prog)
	elseif state == 'shown' then
		begin('sliding_out')
	else
		return   -- schon zu oder auf dem Weg dorthin
	end
	watch(false)
end

function Update()
	if state == 'fade_away' then
		local p = advance(fadeDur())
		SKIN:Bang('!SetTransparency', math.floor(255 * (1 - p)), LIST)
		-- ausgeblendet waehrend der Wartezeit (openAt): erst umbauen, wenn feststeht, dass sie aufgeht
		if p >= 1 and not openAt then startPanel() end
	elseif state == 'fade_back' then
		local p = advance(fadeDur())
		SKIN:Bang('!SetTransparency', math.floor(255 * p), LIST)
		if p >= 1 then state = 'hidden' end
	elseif state == 'sliding_in' then
		local p = advance(slideDur)
		place(p)
		if p >= 1 then state = 'shown' end
	elseif state == 'sliding_out' then
		local p = advance(slideDur)
		place(1 - p)
		if p >= 1 then
			state = 'hidden'
			if mode == 'both' then
				-- zurueck an den Desktop-Platz (unter den Fenstern), dort unsichtbar und sanft einblenden
				SKIN:Bang('!SetTransparency', '0', LIST)
				SKIN:Bang('!CommandMeasure', 'MeasureTodo', 'PanelOff()', LIST)
				begin('fade_back')
			else
				SKIN:Bang('!Hide', LIST)
			end
		end
	end
	if openAt then
		if not onEdge and edgeLeftAt and now() - edgeLeftAt > JITTER then
			openAt = nil   -- Maus ist wirklich weg vom Rand
			if state == 'fade_away' then slideOut() end   -- Desktop-Liste blendete schon aus: wieder einblenden
		elseif now() >= openAt then
			-- nur oeffnen, wenn die Maus jetzt am Rand ist; ist sie gerade ein Pixel daneben, hoechstens JITTER
			-- lang abwarten, ob sie zurueckkommt (sonst bricht der Zweig oben ab)
			if onEdge then openAt = nil; slideIn() end
		elseif mode == 'both' and state == 'hidden' and now() >= openAt - fadeDur() then
			-- 'both': die Desktop-Liste schon waehrend der Wartezeit ausblenden, damit die Seitenleiste genau
			-- nach der eingestellten Zeit losfaehrt (sonst kaemen die 0,15 s Ausblenden noch dazu)
			slideIn()
		end
	end
	if leaveAt and now() >= leaveAt then
		leaveAt = nil
		if not revealing then slideOut() end
	end
	return 0
end

-- ---------- Aufrufe ----------
-- Maus beruehrt den Rand: hereinfahren (bei "Kurz warten" erst, wenn sie dort bleibt); solange sie am Rand
-- bleibt, bleibt die Liste offen
function EdgeHit()
	onEdge = true
	edgeLeftAt = nil
	leaveAt = nil
	if openDelay > 0 and state == 'hidden' then
		openAt = openAt or now() + openDelay   -- laeuft schon: nicht neu anfangen (Zittern, s. JITTER)
	else
		slideIn()
	end
end
-- Maus hat den Rand verlassen (MeterEdge MouseLeaveAction): ist sie nicht in die Liste gewandert, hinaus.
-- War sie seit dem Hereinfahren noch nicht in der Liste, bekommt sie Zeit, vom Rand zur Liste zu fahren.
function EdgeLeave()
	onEdge = false
	edgeLeftAt = now()
	if not inList and state ~= 'hidden' then
		leaveAt = now() + (wasInList and leaveDelay or math.max(GRACE, leaveDelay))
	end
end
-- Maus in der Liste (aus Todo.ini, [Rainmeter] MouseOverAction)
function Enter() inList = true; wasInList = true; leaveAt = nil end
-- Maus hat die Liste verlassen; am Rand bleibt sie offen
function Leave()
	inList = false
	if state ~= 'hidden' and not onEdge then leaveAt = now() + leaveDelay end
end
-- Einblenden beim Anmelden/Aufwachen/Entsperren (todo.lua bestimmt die Dauer)
function Reveal() revealing = true; leaveAt = nil; slideIn() end
function RevealEnd() revealing = false; if not inList and not onEdge then leaveAt = now() + leaveDelay end end
-- sofort hinaus (X in der Liste, Klick in ein anderes Fenster, Knopf "Ausblenden")
function Out() revealing = false; leaveAt = nil; openAt = nil; slideOut() end
-- Liste wurde neu geladen, waehrend sie als Panel am Rand stand (todo.lua hat sie schon an ihren Desktop-Platz
-- zurueckgestellt): laufende Animation vergessen, sonst wuerde sie die Liste weiter verschieben
function PanelReset()
	state = 'hidden'; prog = 0; leaveAt = nil; openAt = nil; revealing = false; inList = false
	watch(false)
end
