-- Seitenleiste fuer die Rainmeter-Todo-Liste (Config TaskBoard\Rand).
-- Ein unsichtbarer, 1 Pixel schmaler Streifen am rechten (oder linken) Rand des Hauptbildschirms, immer im
-- Vordergrund. Beruehrt die Maus den Rand, faehrt die Liste (Config TaskBoard) als bildschirmhohes Panel
-- von aussen herein; verlaesst die Maus die Liste, faehrt sie nach kurzer Zeit wieder hinaus.
--
-- Einstellungen (prefs.inc, schreibt das Einstellungen-Fenster):
--   Mode       'sidebar' (nur Seitenleiste) | 'both' (liegt auf dem Desktop UND faehrt am Rand als Panel herein)
--              | 'desktop' (dieser Streifen wird nicht gebraucht)
--   Side       'right' | 'left'
--   Speed      'fast' | 'normal' | 'slow'  (Animationsdauer und Wartezeit nach Maus-weg)
--
-- Bei 'both' sagt der Streifen der Liste vorher PanelOn() (Desktop-Platz merken, bildschirmhoch werden) und
-- nachher PanelOff() (zurueck an den Desktop-Platz). Laeuft mit Update=16, tut aber nur bei Animation etwas.

local LIST = 'TaskBoard'
local MARGIN = 8           -- Abstand zum Bildschirmrand oben, unten und seitlich (wie eine schwebende KDE-Leiste)
local EDGE_FREE = 0.2      -- Anteil der Hoehe oben und unten ohne Rand-Streifen (Ecken loesen nichts aus)
local SPEEDS = {           -- Bilder fuer die Animation, Sekunden bis zum Hinausfahren nach Maus-weg
	fast = { frames = 7, leave = 0 },
	normal = { frames = 12, leave = 1 },
	slow = { frames = 20, leave = 2 },
}

local mode, side, width, left, right, top
local frames, leaveDelay
local state = 'hidden'     -- hidden | sliding_in | shown | sliding_out
local frame = 0
local leaveAt = nil        -- Uhrzeit (os.time), ab der hinausgefahren wird (Uhrzeit statt Bilder: Rainmeter
                           -- schafft nicht ueberall 60 Bilder pro Sekunde)
local revealing = false    -- vom Einblenden (Anmelden/Aufwachen) geoeffnet: bleibt, bis RevealEnd()

local function num(v, d) return tonumber(SKIN:GetVariable(v)) or d end

function Initialize()
	mode = SKIN:GetVariable('Mode') or 'sidebar'
	side = SKIN:GetVariable('Side') == 'left' and 'left' or 'right'
	local sp = SPEEDS[SKIN:GetVariable('Speed') or 'normal'] or SPEEDS.normal
	frames, leaveDelay = sp.frames, sp.leave
	width = num('Width', 460)
	left = num('WORKAREAX', 0)
	right = left + num('WORKAREAWIDTH', 1920)
	top = num('WORKAREAY', 0)
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
-- Hinausfahren steht sie wieder an ihrem Platz und blendet sanft ein (fade_back)
local function fadeFrames() return math.max(6, frames) end

local function startPanel()
	-- Liste merkt sich ihren Desktop-Platz und wird zum bildschirmhohen Panel (unsichtbar umgebaut)
	SKIN:Bang('!CommandMeasure', 'MeasureTodo', 'PanelOn()', LIST)
	frame = 0
	place(0)
	SKIN:Bang('!ZPos', '2', LIST)
	SKIN:Bang('!SetTransparency', '255', LIST)
	SKIN:Bang('!Show', LIST)
	state = 'sliding_in'
end

local function slideIn()
	if state == 'shown' or state == 'sliding_in' or state == 'fade_away' then return end
	if state == 'fade_back' then
		-- war gerade beim Wieder-Einblenden: von dort aus wieder ausblenden
		frame = fadeFrames() - frame
		state = 'fade_away'
		return
	end
	if state == 'hidden' then
		if mode == 'both' then
			frame = 0
			state = 'fade_away'
			return
		end
		frame = 0
		place(0)
		SKIN:Bang('!ZPos', '2', LIST)
		SKIN:Bang('!Show', LIST)
	else
		frame = frames - frame   -- war gerade beim Hinausfahren: von dort aus umkehren
	end
	state = 'sliding_in'
end

local function slideOut()
	if state == 'hidden' or state == 'sliding_out' or state == 'fade_back' then return end
	if state == 'fade_away' then
		-- noch gar nicht hereingefahren: einfach wieder einblenden
		frame = fadeFrames() - frame
		state = 'fade_back'
		return
	end
	if state == 'sliding_in' then frame = frames - frame else frame = 0 end
	state = 'sliding_out'
end

function Update()
	if state == 'fade_away' then
		frame = frame + 1
		local f = fadeFrames()
		SKIN:Bang('!SetTransparency', math.floor(255 * math.max(0, 1 - frame / f)), LIST)
		if frame >= f then startPanel() end
	elseif state == 'fade_back' then
		frame = frame + 1
		local f = fadeFrames()
		SKIN:Bang('!SetTransparency', math.floor(255 * math.min(1, frame / f)), LIST)
		if frame >= f then state = 'hidden' end
	elseif state == 'sliding_in' then
		frame = frame + 1
		place(math.min(1, frame / frames))
		if frame >= frames then state = 'shown' end
	elseif state == 'sliding_out' then
		frame = frame + 1
		place(math.max(0, 1 - frame / frames))
		if frame >= frames then
			state = 'hidden'
			if mode == 'both' then
				-- zurueck an den Desktop-Platz (unter den Fenstern), dort unsichtbar und sanft einblenden
				SKIN:Bang('!SetTransparency', '0', LIST)
				SKIN:Bang('!CommandMeasure', 'MeasureTodo', 'PanelOff()', LIST)
				frame = 0
				state = 'fade_back'
			else
				SKIN:Bang('!Hide', LIST)
			end
		end
	end
	if leaveAt and os.time() >= leaveAt then
		leaveAt = nil
		if not revealing then slideOut() end
	end
	return 0
end

-- ---------- Aufrufe ----------
-- Maus beruehrt den Rand: hereinfahren; solange sie am Rand bleibt, bleibt die Liste offen
local onEdge, inList = false, false
function EdgeHit()
	onEdge = true
	leaveAt = nil
	slideIn()
end
-- Maus hat den Rand verlassen (MeterEdge MouseLeaveAction): ist sie nicht in die Liste gewandert, hinaus
function EdgeLeave()
	onEdge = false
	if not inList and state ~= 'hidden' then leaveAt = os.time() + leaveDelay end
end
-- Maus in der Liste (aus Todo.ini, [Rainmeter] MouseOverAction)
function Enter() inList = true; leaveAt = nil end
-- Maus hat die Liste verlassen (bei 0 Sekunden Wartezeit: beim naechsten Durchlauf); am Rand bleibt sie offen
function Leave()
	inList = false
	if state ~= 'hidden' and not onEdge then leaveAt = os.time() + leaveDelay end
end
-- Einblenden beim Anmelden/Aufwachen/Entsperren (todo.lua bestimmt die Dauer)
function Reveal() revealing = true; leaveAt = nil; slideIn() end
function RevealEnd() revealing = false; if not inList and not onEdge then leaveAt = os.time() + leaveDelay end end
-- sofort hinaus (z. B. Knopf "Ausblenden")
function Out() revealing = false; leaveAt = nil; slideOut() end
-- Liste wurde neu geladen, waehrend sie als Panel am Rand stand (todo.lua hat sie schon an ihren Desktop-Platz
-- zurueckgestellt): laufende Animation vergessen, sonst wuerde sie die Liste weiter verschieben
function PanelReset()
	state = 'hidden'; frame = 0; leaveAt = nil; revealing = false; inList = false
end
