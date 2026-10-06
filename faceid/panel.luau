--!nonstrict
-- Face ID dialog.
--
-- An attached panel (hangs from the bar edge, like the control center). It is a
-- pure subscriber of the phase published by service.luau (and can be driven by
-- IPC). The panel is opened by the service with:
--   noctalia msg panel-open diasbaskara/faceid:dialog
-- and closes itself once the result has faded.
--
-- Panels get onFrameTick(), so this animates at frame rate. Motion is eased
-- (cubic/quint/back) so it reads as a soft iOS-style HUD.

local HOLD_MS = tonumber(noctalia.getConfig("hold_ms")) or 1400
local OPEN_MS = 240
local FADE_OUT_MS = 240
local POP_MS = 340
local LABEL_MS = 280
local SCAN_MS = 1600
local SHAKE_MS = 470

local GREEN = "#34C759"
local RED = "#FF3B30"

local open = false
local animT = 0
local visualPhase = "scan"
local phaseAnimAt = 0
local opening = false
local closing = false
local closingAt = 0

local function clamp01(x)
	if x < 0 then
		return 0
	elseif x > 1 then
		return 1
	end
	return x
end

local function easeOutCubic(x)
	x = clamp01(x)
	local u = 1 - x
	return 1 - u * u * u
end

local function easeOutQuint(x)
	x = clamp01(x)
	local u = 1 - x
	return 1 - u * u * u * u * u
end

local function easeInOutQuad(x)
	x = clamp01(x)
	if x < 0.5 then
		return 2 * x * x
	end
	local u = -2 * x + 2
	return 1 - (u * u) / 2
end

-- Slight overshoot, for the result glyph.
local function easeOutBack(x)
	x = clamp01(x)
	local c1 = 1.70158
	local c3 = c1 + 1
	local u = x - 1
	return 1 + c3 * u * u * u + c1 * u * u
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
	local border = "outline/0.15"
	local kids = {}

	if visualPhase == "scan" then
		-- Sweeping bar, eased at both ends so it does not snap at the turn.
		local cycle = (animT % SCAN_MS) / SCAN_MS
		local tri = cycle < 0.5 and (cycle * 2) or (2 - cycle * 2)
		local p = easeInOutQuad(tri)
		-- Very subtle breathing so the card feels alive.
		local breathe = 0.985 + 0.015 * math.sin(animT / 420)
		kids[#kids + 1] = ui.glyph({ name = "face-id", size = 42 + 3 * math.sin(animT / 300), color = "primary" })
		kids[#kids + 1] = ui.progress({
			progress = p,
			width = 132,
			height = 4,
			radius = 2,
			fill = "primary/0.85",
			track = "on_surface/0.10",
		})
		local labelA = 0.6 + 0.4 * math.sin(animT / 420)
		kids[#kids + 1] = ui.label({ text = "Face ID", fontSize = 12, color = "on_surface_variant", opacity = labelA })
		opacity = breathe
	elseif visualPhase == "success" then
		local pop = easeOutBack(math.min(1, t / POP_MS))
		local labelA = easeOutCubic(math.max(0, (t - 90) / LABEL_MS))
		border = "#34C75947"
		kids[#kids + 1] = ui.glyph({ name = "circle-check", size = 40 + 14 * pop, color = GREEN })
		kids[#kids + 1] = ui.label({ text = "Recognized", fontSize = 12, fontWeight = "semibold", color = GREEN, opacity = labelA })
	elseif visualPhase == "fail" then
		local pop = easeOutBack(math.min(1, t / POP_MS))
		local shake = math.sin(t / 30) * 8 * (1 - easeOutQuint(math.min(1, t / SHAKE_MS)))
		local labelA = easeOutCubic(math.max(0, (t - 120) / LABEL_MS))
		border = "#FF3B3047"
		local glyph = ui.glyph({ name = "circle-x", size = 40 + 12 * pop, color = RED })
		kids[#kids + 1] = ui.row({ gap = 0, align = "center" }, {
			ui.box({ width = math.max(0, shake) }),
			glyph,
			ui.box({ width = math.max(0, -shake) }),
		})
		kids[#kids + 1] = ui.label({ text = "Not recognized", fontSize = 12, fontWeight = "semibold", color = RED, opacity = labelA })
	else
		-- "done": nothing was locked, so the face result is not observable.
		opacity = 1 - easeOutCubic(t / math.min(HOLD_MS, 700))
		kids[#kids + 1] = ui.glyph({ name = "face-id", size = 38, color = "on_surface_variant" })
	end

	if opening then
		opacity = opacity * easeOutCubic(animT / OPEN_MS)
	end
	if closing then
		local f = clamp01((animT - closingAt) / FADE_OUT_MS)
		local e = easeInOutQuad(f)
		opacity = opacity * (1 - e)
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
		border = border,
		borderWidth = 1,
		opacity = opacity,
	}, kids))
end

function onOpen(_context)
	open = true
	opening = true
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
	opening = false
	closing = false
	render()
end)
