--!nonstrict
-- Face ID dialog.
--
-- An attached, square panel (hangs from the bar edge, like the control center).
-- It is a pure subscriber of the phase published by service.luau (and can be
-- driven by IPC). The panel is opened by the service with:
--   noctalia msg panel-open diasbaskara/faceid:dialog
-- and closes itself once the result has faded.
--
-- Artwork is two Face ID animations from LottieFiles (see README), recoloured
-- white to match the shell theme:
--   looking for face -> assets/look_NN.png    (loops while scanning)
--   success          -> assets/success_NN.png (morph to the check)
-- Noctalia's ui.image only shows the first frame of an animated image, so the
-- frames are exported to PNGs and played by swapping the image path each tick.
-- There is no error state: a non-success just closes the panel.

local FADE_MS = 200

-- Looking-for-face loop (source is 60 fps, ~3.9 s; sampled every 4th frame).
local LOOK_N = 60
local LOOK_MS = 65

-- Success part: 22 exported frames (~1.1s), then the last frame is held.
local SUCCESS_N = 22
local SUCCESS_MS = 50

-- Small, fits comfortably inside the 150x150 panel.
local IMG = 88

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

local function body()
	if visualPhase == "success" then
		local t = animT - phaseAnimAt
		local idx = math.min(SUCCESS_N - 1, math.floor(t / SUCCESS_MS))
		return ui.image({ path = string.format("assets/success_%02d.png", idx), width = IMG, height = IMG })
	end
	-- scanning: loop the looking-for-face animation.
	local loop = LOOK_N * LOOK_MS
	local idx = math.floor((animT % loop) / LOOK_MS)
	return ui.image({ path = string.format("assets/look_%02d.png", idx), width = IMG, height = IMG })
end

local function render()
	if not open then
		return
	end

	local opacity = 1
	if opening then
		opacity = easeOutCubic(animT / FADE_MS)
	end
	if closing then
		local f = clamp01((animT - closingAt) / FADE_MS)
		if f >= 1 then
			open = false
			panel.close()
			return
		end
		opacity = opacity * (1 - f)
	end

	panel.render(ui.column({
		align = "center",
		justify = "center",
		padding = 12,
		fill = "surface/0.92",
		radius = 22,
		border = "outline/0.15",
		borderWidth = 1,
		opacity = opacity,
	}, { body() }))
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
