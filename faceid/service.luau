--!nonstrict
-- Face ID watcher (headless service).
--
-- Single owner of the scan phase. It watches for a running Howdy scan with a
-- tiny `pgrep` loop (bracket trick so the loop's own command line never matches
-- itself) and publishes `phase` / `phaseAt`:
--
--   scan    -> a `compare.py` process appeared
--   success -> the scan finished and the face was recognised
--   idle    -> the scan did not succeed; the panel just closes (no error state)
--
-- There is no error state. The outcome is decided per context:
--   * locked session  -> success when the lock is released, otherwise close
--   * unlocked (sudo) -> always success; Howdy's result is not observable from
--                        outside and both success and timeout take about the
--                        same time, so the panel plays the success animation
--
-- An external hook can drive it directly:
--   noctalia msg plugin diasbaskara/faceid:watch all success

local PANEL_ID = "diasbaskara/faceid:dialog"
local POLL_MS = 250
local HOLD_MS = tonumber(noctalia.getConfig("hold_ms")) or 1400
if HOLD_MS < 400 then HOLD_MS = 400 end

local RESOLVE_ATTEMPTS = 5
local RESOLVE_GAP_MS = 250

local phase = "idle"
local phaseAt = 0
local resultHoldUntil = 0
local wasLocked = false
local resolving = false
local resolveAttempts = 0
local resolveNextAt = 0

local function publish()
	noctalia.state.set("phase", phase)
	noctalia.state.set("phaseAt", phaseAt)
end

local function setPhase(nextPhase)
	phase = nextPhase
	phaseAt = noctalia.nowMs()
	publish()
end

local function hold()
	resultHoldUntil = noctalia.nowMs() + HOLD_MS
end

local function openDialog()
	noctalia.runAsync("noctalia msg panel-open " .. PANEL_ID)
end

-- No in-process lock API exists, so ask the shell over IPC. Runs only on scan
-- edges and during the short resolve window, never per tick.
local function queryLocked(cb)
	noctalia.runAsync("noctalia msg status", function(result)
		local locked = nil
		if result ~= nil and result.exitCode == 0 then
			local decoded = noctalia.json.decode(result.stdout or "")
			if type(decoded) == "table" then
				locked = decoded.locked == true
			end
		end
		cb(locked)
	end, 1500)
end

local function finishSuccess()
	resolving = false
	setPhase("success")
	hold()
end

-- Not a success: close the panel, no error state.
local function finishClose()
	resolving = false
	setPhase("idle")
end

local function pollResolve()
	queryLocked(function(nowLocked)
		if nowLocked == false then
			finishSuccess()
		else
			resolveAttempts = resolveAttempts + 1
			if resolveAttempts >= RESOLVE_ATTEMPTS or nowLocked == nil then
				finishClose()
			else
				resolveNextAt = noctalia.nowMs() + RESOLVE_GAP_MS
			end
		end
	end)
end

local function resolveResult()
	if resolving then
		return
	end
	if wasLocked then
		-- The session unlocks a moment after Howdy exits; poll briefly.
		resolving = true
		resolveAttempts = 0
		pollResolve()
	else
		-- sudo/doas/su: Howdy's result is not observable, so play the success
		-- animation. There is no error state to show instead.
		finishSuccess()
	end
end

local function onWatchLine(line)
	line = noctalia.string.trim(line)
	if line == "scan" and phase == "idle" then
		resolving = false
		wasLocked = false
		setPhase("scan")
		openDialog()
		queryLocked(function(locked)
			wasLocked = locked == true
		end)
	elseif line == "idle" and phase == "scan" then
		resolveResult()
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

function update()
	if resolving and noctalia.nowMs() >= resolveNextAt then
		pollResolve()
	elseif phase == "success" then
		if noctalia.nowMs() >= resultHoldUntil then
			setPhase("idle")
		end
	end
end

function onIpc(event, payload)
	event = tostring(event or "")
	if event == "scan" then
		resolving = false
		setPhase("scan")
		openDialog()
	elseif event == "success" then
		finishSuccess()
		openDialog()
	elseif event == "fail" or event == "timeout" then
		finishClose()
	elseif event == "idle" or event == "clear" then
		resolving = false
		setPhase("idle")
	end
end

noctalia.setUpdateInterval(POLL_MS)
publish()

local started = noctalia.runStream(watcherCommand(), onWatchLine)
if not started then
	noctalia.state.set("error", "watcher could not start")
end
