--!nonstrict
-- Face ID dialog.
--
-- An attached, square panel (hangs from the bar edge, like the control center).
-- It is a pure subscriber of the phase published by service.luau (and can be
-- driven by IPC). The panel is opened by the service with:
--   noctalia msg panel-open diasbaskara/faceid:dialog
-- and closes itself once the result has faded.
--
-- Artwork is the two-part "Face ID" Lottie animation (see README):
--   part 1 "looking for face" -> assets/look.png       (looped while scanning)
--   part 2 "success"          -> assets/success_NN.png (morph to the check)
-- Noctalia's ui.image only shows the first frame of an animated image, so the
-- success morph is exported to PNG frames and played by swapping the image path
-- each frame tick.

local HOLD_MS = tonumber(noctalia.getConfig("hold_ms")) or 1400
local OPEN_MS = 240
local FADE_OUT_MS = 240
local LABEL_MS = 280
local SWEEP_MS = 1500
local SHAKE_MS = 470
local PULSE_MS = 1700

-- Success part: 22 exported frames (~1.1s), then the last frame is held.
local SUCCESS_N = 22
local SUCCESS_MS = 50

-- Kept small enough that content never overflows the 180x180 panel.
local IMG = 104
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
		-- Part 1: looking-for-face, looped with a gentle breathing pulse plus a
		-- sweeping line, until the phase turns into success or fail.
		local pulse = 1 + 0.035 * math.sin((animT % PULSE_MS) / PULSE_MS * math.pi * 2)
		local size = math.floor(IMG * pulse + 0.5)
		local cycle = (animT % SWEEP_MS) / SWEEP_MS
		local tri = cycle < 0.5 and (cycle * 2) or (2 - cycle * 2)
		local p = easeInOutQuad(tri)
		kids[#kids + 1] = ui.image({ path = "assets/look.png", width = size, height = size })
		kids[#kids + 1] = ui.progress({
			progress = p,
			width = 116,
			height = 4,
			radius = 2,
			fill = "primary/0.85",
			track = "on_surface/0.10",
		})
		local labelA = 0.6 + 0.4 * math.sin(animT / 420)
		kids[#kids + 1] = ui.label({ text = "Face ID", fontSize = 12, color = "on_surface_variant", opacity = labelA })
	elseif visualPhase == "success" then
		-- Part 2: the morph to the check, then hold the last frame.
		local idx = math.min(SUCCESS_N - 1, math.floor(t / SUCCESS_MS))
		local path = string.format("assets/success_%02d.png", idx)
		local labelA = easeOutCubic(math.max(0, (t - SUCCESS_N * SUCCESS_MS * 0.55) / LABEL_MS))
		border = "#006DF847"
		kids[#kids + 1] = ui.image({ path = path, width = IMG, height = IMG })
		kids[#kids + 1] = ui.label({ text = "Recognized", fontSize = 12, fontWeight = "semibold", color = GREEN, opacity = labelA })
	elseif visualPhase == "fail" then
		local pop = easeOutQuint(math.min(1, t / 300))
		local shake = math.sin(t / 30) * 8 * (1 - easeOutQuint(math.min(1, t / SHAKE_MS)))
		local labelA = easeOutCubic(math.max(0, (t - 120) / LABEL_MS))
		border = "#FF3B3047"
		local glyph = ui.glyph({ name = "circle-x", size = 44 + 12 * pop, color = RED })
		kids[#kids + 1] = ui.row({ gap = 0, align = "center" }, {
			ui.box({ width = math.max(0, shake) }),
			glyph,
			ui.box({ width = math.max(0, -shake) }),
		})
		kids[#kids + 1] = ui.label({ text = "Not recognized", fontSize = 12, fontWeight = "semibold", color = RED, opacity = labelA })
	else
		-- "done": nothing was locked, so the face result is not observable.
		opacity = 1 - easeOutCubic(t / math.min(HOLD_MS, 700))
		kids[#kids + 1] = ui.image({ path = "assets/look.png", width = IMG, height = IMG })
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
		gap = 8,
		align = "center",
		justify = "center",
		padding = 12,
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
