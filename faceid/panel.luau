--!nonstrict
-- Face ID dialog.
--
-- A floating, non-interactive overlay that animates while Howdy scans a face.
-- It is a pure subscriber of the phase published by service.luau (and can be
-- driven by IPC). The panel is opened by the service with:
--   noctalia msg panel-open diasbaskara/faceid:dialog
-- and closes itself once the result has faded.
--
-- Panels get onFrameTick(), so unlike a bar widget this animates at frame rate.

local HOLD_MS = tonumber(noctalia.getConfig("hold_ms")) or 1400
local FADE_IN_MS = 180
local FADE_OUT_MS = 220
local POP_MS = 280
local SCAN_MS = 1500
local SHAKE_MS = 420

local GREEN = "#34C759"
local RED = "#FF3B30"

local open = false
local animT = 0
local visualPhase = "scan"
local phaseAnimAt = 0
local closing = false
local closingAt = 0

local function ease(t, dur)
	if dur <= 0 then
		return 1
	end
	local v = t / dur
	if v < 0 then
		return 0
	elseif v > 1 then
		return 1
	end
	return v
end

local function phaseT()
	return animT - phaseAnimAt
end

local function render()
	if not open then
		return
	end

	local t = phaseT()
	local opacity = 1
	local kids = {}

	if visualPhase == "scan" then
		opacity = ease(animT, FADE_IN_MS)
		local cycle = animT % SCAN_MS
		local p = cycle < SCAN_MS / 2 and (cycle / (SCAN_MS / 2)) or ((SCAN_MS - cycle) / (SCAN_MS / 2))
		-- Breathing face glyph.
		local size = 42 + 5 * math.sin(animT / 260)
		kids[#kids + 1] = ui.glyph({ name = "face-id", size = size, color = "primary" })
		kids[#kids + 1] = ui.progress({
			progress = p,
			width = 128,
			height = 5,
			radius = 3,
			fill = "primary/0.9",
			track = "on_surface/0.12",
		})
		kids[#kids + 1] = ui.label({ text = "Face ID", fontSize = 12, color = "on_surface_variant" })
	elseif visualPhase == "success" then
		-- Pop-in check.
		local pop = math.sin(math.pi * math.min(1, t / POP_MS))
		kids[#kids + 1] = ui.glyph({ name = "circle-check", size = 46 + 10 * pop, color = GREEN })
		kids[#kids + 1] = ui.label({ text = "Recognized", fontSize = 12, fontWeight = "semibold", color = GREEN })
	elseif visualPhase == "fail" then
		-- Pop-in X with a decaying horizontal shake.
		local pop = math.sin(math.pi * math.min(1, t / POP_MS))
		local shake = math.sin(t / 26) * 7 * (1 - ease(t, SHAKE_MS))
		local glyph = ui.glyph({ name = "circle-x", size = 46 + 8 * pop, color = RED })
		kids[#kids + 1] = ui.row({ gap = 0, align = "center" }, {
			ui.box({ width = math.max(0, shake) }),
			glyph,
			ui.box({ width = math.max(0, -shake) }),
		})
		kids[#kids + 1] = ui.label({ text = "Not recognized", fontSize = 12, fontWeight = "semibold", color = RED })
	else
		-- "done": nothing was locked, so the face result is not observable.
		opacity = 1 - ease(t, math.min(HOLD_MS, 700))
		kids[#kids + 1] = ui.glyph({ name = "face-id", size = 40, color = "on_surface_variant" })
	end

	if closing then
		local f = ease(animT - closingAt, FADE_OUT_MS)
		opacity = opacity * (1 - f)
		if f >= 1 then
			open = false
			panel.close()
			return
		end
	end

	panel.render(ui.column({
		gap = 10,
		align = "center",
		justify = "center",
		padding = 16,
		fill = "surface/0.92",
		radius = 22,
		border = "outline/0.15",
		borderWidth = 1,
		opacity = opacity,
	}, kids))
end

function onOpen(_context)
	open = true
	closing = false
	animT = 0
	phaseAnimAt = 0
	visualPhase = noctalia.state.get("phase") or "scan"
	if visualPhase == "idle" then
		visualPhase = "scan"
	end
	panel.setNeedsFrameTick(true)
	render()
end

function onClose()
	open = false
	panel.setNeedsFrameTick(false)
end

function onFrameTick(deltaMs)
	animT = animT + (deltaMs or 16)
	render()
end

noctalia.state.watch("phase", function(value)
	local nextPhase = type(value) == "string" and value or "idle"
	if nextPhase == "idle" then
		if not closing then
			closing = true
			closingAt = animT
		end
		return
	end
	visualPhase = nextPhase
	phaseAnimAt = animT
	closing = false
	render()
end)
