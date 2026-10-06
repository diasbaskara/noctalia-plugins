--!nonstrict
-- Face ID bar capsule.
--
-- Subscribes to the phase published by service.luau and draws the iOS-style
-- Face ID indicator: a face glyph with a sweeping scan bar, morphing to a green
-- check on success or a red X on failure, then fading away.
--
-- The bar has no frame-tick API, so animation is driven by `update()` at a
-- short interval while active and a long one while idle.

local HOLD_MS = tonumber(noctalia.getConfig("hold_ms")) or 1400
local LABEL = tostring(noctalia.getConfig("label") or "")

local SCAN_MS = 1400
local FADE_IN_MS = 200
local POP_MS = 160

local phase = "idle"
local phaseAt = 0
local detail = ""
local fadeStart = 0

local GREEN = "#34C759"
local RED = "#FF3B30"

local function now()
	return noctalia.nowMs()
end

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

local function setTick()
	if phase == "scan" then
		noctalia.setUpdateInterval(40)
	elseif phase == "idle" then
		noctalia.setUpdateInterval(1500)
	else
		noctalia.setUpdateInterval(50)
	end
end

local function render()
	if phase == "idle" then
		barWidget.setVisible(false)
		barWidget.setTooltip(nil)
		return
	end

	barWidget.setVisible(true)

	local t = now() - phaseAt
	local vertical = barWidget.isVertical() == true
	local container = vertical and ui.column or ui.row
	local kids = {}
	local opacity = 1.0

	if phase == "scan" then
		opacity = ease(t, FADE_IN_MS)
		local cycle = t % SCAN_MS
		local p = cycle < SCAN_MS / 2 and (cycle / (SCAN_MS / 2)) or ((SCAN_MS - cycle) / (SCAN_MS / 2))
		kids[#kids + 1] = ui.glyph({ name = "face-id", size = 15, color = "primary" })
		if not vertical then
			kids[#kids + 1] = ui.progress({
				progress = p,
				width = 34,
				height = 4,
				radius = 2,
				fill = "primary/0.9",
				track = "on_surface/0.15",
			})
		end
		barWidget.setTooltip({ { key = "Face ID", value = "Scanning…" } })
	elseif phase == "success" then
		kids[#kids + 1] = ui.glyph({ name = "circle-check", size = 15 + 3 * (1 - ease(t, POP_MS)), color = GREEN })
		barWidget.setTooltip({ { key = "Face ID", value = "Recognized" } })
	elseif phase == "fail" then
		kids[#kids + 1] = ui.glyph({ name = "circle-x", size = 15 + 3 * (1 - ease(t, POP_MS)), color = RED })
		barWidget.setTooltip({ { key = "Face ID", value = "Not recognized" } })
	else
		-- "done": nothing was locked, so the face result is not observable.
		opacity = 1 - ease(t, math.min(HOLD_MS, 600))
		kids[#kids + 1] = ui.glyph({ name = "face-id", size = 14, color = "on_surface_variant" })
	end

	if LABEL ~= "" then
		kids[#kids + 1] = ui.label({ text = LABEL, fontWeight = "semibold" })
	end

	barWidget.render(container({ gap = 6, align = "center", opacity = opacity }, kids))
end

function update()
	render()
end

noctalia.state.watch("phase", function(value)
	phase = type(value) == "string" and value or "idle"
	phaseAt = tonumber(noctalia.state.get("phaseAt")) or now()
	setTick()
	render()
end)

phase = noctalia.state.get("phase") or "idle"
phaseAt = tonumber(noctalia.state.get("phaseAt")) or now()
setTick()
render()
