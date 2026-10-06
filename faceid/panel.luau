--!nonstrict
-- Face ID dialog.
--
-- An attached, square panel (hangs from the bar edge, like the control center).
-- It shows the looping "looking for face" animation from LottieFiles (see
-- README), recoloured white and played by swapping exported PNG frames each
-- frame tick (Noctalia's ui.image only renders the first frame of an animated
-- image).
--
-- There is no success or error state: the panel opens while Howdy scans and
-- closes when the scan ends.

local FADE_MS = 200

-- Looking-for-face loop (source is 60 fps, ~3.9 s; sampled every 4th frame).
local LOOK_N = 60
local LOOK_MS = 65

-- Small, fits comfortably inside the 150x150 panel.
local IMG = 88

local open = false
local animT = 0
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

local function render()
	if not open then
		return
	end

	local opacity = 1
	if closing then
		local f = clamp01((animT - closingAt) / FADE_MS)
		if f >= 1 then
			open = false
			panel.close()
			return
		end
		opacity = 1 - f
	else
		opacity = easeOutCubic(animT / FADE_MS)
	end

	local loop = LOOK_N * LOOK_MS
	local idx = math.floor((animT % loop) / LOOK_MS)

	panel.render(ui.column({
		align = "center",
		justify = "center",
		padding = 12,
		fill = "surface/0.92",
		radius = 22,
		border = "outline/0.15",
		borderWidth = 1,
		opacity = opacity,
	}, {
		ui.image({ path = string.format("assets/look_%02d.png", idx), width = IMG, height = IMG }),
	}))
end

function onOpen(_context)
	open = true
	closing = false
	animT = 0
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
	else
		closing = false
	end
end)
