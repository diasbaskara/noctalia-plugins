--!nonstrict
-- Face ID watcher (headless service).
--
-- Single owner of the scan phase. It watches for a running Howdy scan with a
-- tiny `pgrep` loop (bracket trick so the loop's own command line never
-- matches itself) and resolves the result:
--
--   scan  -> a `compare.py` process appeared
--   done  -> it exited while nothing was locked (sudo/doas: result unknown)
--   success -> it exited and the session lock was released
--   fail  -> it exited and the session was still locked
--
-- The success check polls briefly, because the session unlocks a moment after
-- the Howdy process exits (PAM returns, then Noctalia releases the lock).
--
-- The bar widget subscribes to `noctalia.state`; it never spawns anything. An
-- external hook can also drive it directly:
--   noctalia msg plugin diasbaskara/faceid:watch all success

local POLL_MS = 250
local HOLD_MS = tonumber(noctalia.getConfig("hold_ms")) or 1400
if HOLD_MS < 400 then HOLD_MS = 400 end

local RESOLVE_ATTEMPTS = 5
local RESOLVE_GAP_MS = 250

local PANEL_ID = "diasbaskara/faceid:dialog"

local phase = "idle"
local phaseAt = 0
local resultHoldUntil = 0
local wasLocked = false
local resolving = false
local resolveAttempts = 0
local resolveNextAt = 0
local detail = ""

-- The panel closes itself once the result fades; here we only ever open it.
local function openDialog()
	noctalia.runAsync("noctalia msg panel-open " .. PANEL_ID)
end

local function publish()
	noctalia.state.set("phase", phase)
	noctalia.state.set("phaseAt", phaseAt)
	noctalia.state.set("detail", detail)
end

local function setPhase(nextPhase, nextDetail)
	phase = nextPhase
	phaseAt = noctalia.nowMs()
	detail = nextDetail or ""
	publish()
end

local function hold()
	resultHoldUntil = noctalia.nowMs() + HOLD_MS
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

local function finish(nextPhase, nextDetail)
	resolving = false
	setPhase(nextPhase, nextDetail)
	hold()
end

local function pollResolve()
	queryLocked(function(nowLocked)
		if nowLocked == false then
			finish("success", "Unlocked")
		elseif nowLocked == nil then
			-- Could not read the lock state at all: do not fake a failure.
			finish("done", "")
		else
			resolveAttempts = resolveAttempts + 1
			if resolveAttempts >= RESOLVE_ATTEMPTS then
				finish("fail", "Not recognized")
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
	if not wasLocked then
		-- sudo/doas/su: the face result is not observable from here.
		finish("done", "")
		return
	end
	resolving = true
	resolveAttempts = 0
	pollResolve()
end

local function onWatchLine(line)
	line = noctalia.string.trim(line)
	if line == "scan" and phase == "idle" then
		resolving = false
		wasLocked = false
		setPhase("scan", "")
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
	elseif phase == "success" or phase == "fail" or phase == "done" then
		if noctalia.nowMs() >= resultHoldUntil then
			setPhase("idle", "")
		end
	end
end

-- Manual / hook-driven control.
function onIpc(event, payload)
	event = tostring(event or "")
	if event == "scan" then
		resolving = false
		setPhase("scan", "")
		openDialog()
	elseif event == "success" then
		finish("success", tostring(payload or ""))
		openDialog()
	elseif event == "fail" then
		finish("fail", tostring(payload or ""))
		openDialog()
	elseif event == "idle" or event == "clear" then
		resolving = false
		setPhase("idle", "")
	end
end

noctalia.setUpdateInterval(POLL_MS)
publish()

local started = noctalia.runStream(watcherCommand(), onWatchLine)
if not started then
	noctalia.state.set("error", "watcher could not start")
end
