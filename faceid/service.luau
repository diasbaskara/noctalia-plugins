--!nonstrict
-- Face ID watcher (headless service).
--
-- Watches for a running Howdy scan with a tiny `pgrep` loop (bracket trick so
-- the loop's own command line never matches itself) and drives the panel:
--
--   scan -> open the panel (the looking-for-face loop)
--   idle -> close it
--
-- There is no success or error state: the panel just closes when the scan ends.

local PANEL_ID = "diasbaskara/faceid:dialog"

local phase = "idle"
local phaseAt = 0

local function setPhase(nextPhase)
	phase = nextPhase
	phaseAt = noctalia.nowMs()
	noctalia.state.set("phase", phase)
	noctalia.state.set("phaseAt", phaseAt)
end

local function openDialog()
	noctalia.runAsync("noctalia msg panel-open " .. PANEL_ID)
end

local function onWatchLine(line)
	line = noctalia.string.trim(line)
	if line == "scan" and phase == "idle" then
		setPhase("scan")
		openDialog()
	elseif line == "idle" and phase == "scan" then
		setPhase("idle")
	end
end

-- Build a self-match-proof pattern, e.g. "compare.py" -> "[c]ompare.py".
local function watcherCommand()
	local raw = tostring(noctalia.getConfig("process_pattern") or "compare.py")
	raw = raw:gsub("[^%w%._/%-]", "")
	if raw == "" then
		raw = "compare.py"
	end
	local safe = "[" .. raw:sub(1, 1) .. "]" .. raw:sub(2)
	return string.format(
		[[last=""; while :; do if pgrep -f '%s' >/dev/null 2>&1; then s=scan; else s=idle; fi; if [ "$s" != "$last" ]; then echo "$s"; last="$s"; fi; sleep 0.3; done]],
		safe
	)
end

function onIpc(event, _payload)
	event = tostring(event or "")
	if event == "scan" then
		setPhase("scan")
		openDialog()
	elseif event == "idle" or event == "clear" or event == "close" then
		setPhase("idle")
	end
end

noctalia.state.set("phase", phase)
noctalia.state.set("phaseAt", phaseAt)

local started = noctalia.runStream(watcherCommand(), onWatchLine)
if not started then
	noctalia.state.set("error", "watcher could not start")
end
