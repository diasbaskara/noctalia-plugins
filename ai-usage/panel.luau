--!nonstrict
-- Details panel: one block per provider in the report, with meters, reset
-- countdowns and fetch errors. `r` refreshes, arrows/escape behave as usual.

local report = nil

local GLYPHS = {
    anthropic = "asterisk-simple",
    openai = "brand-openai",
    copilot = "brand-github-copilot",
    cursor = "cursor-text",
    grok = "brand-x",
    supergrok = "brand-x",
    ["opencode-go"] = "code",
    zai = "bolt",
    openrouter = "route",
    deepseek = "fish",
    kimi = "moon",
}

local function baseProvider(id)
    return (tostring(id or ""):match("^[^@]+") or "")
end

local function ratio(percent)
    local value = (tonumber(percent) or 0) / 100
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function countdown(resetAt)
    if type(resetAt) ~= "string" then return "" end
    local y, mo, d, h, mi, s = resetAt:match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
    if y == nil then return "" end
    local asLocal = os.time({
        year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = tonumber(s),
    })
    local utc = os.date("!*t", asLocal)
    utc.isdst = nil
    local at = asLocal + (asLocal - os.time(utc))
    local left = at - os.time()
    if left <= 0 then return "now" end
    local mins = math.floor(left / 60)
    local days = math.floor(mins / 1440)
    local hours = math.floor((mins % 1440) / 60)
    local rest = mins % 60
    if days > 0 then return string.format("%dd %dh", days, hours) end
    if hours > 0 then return string.format("%dh %dm", hours, rest) end
    return string.format("%dm", rest)
end

local function metricBlock(m)
    local percent = tonumber(m.percent) or 0
    local fill = "primary"
    if percent >= 100 then fill = "error" elseif percent >= 90 then fill = "secondary" end
    local value = tostring(m.value or "")
    if value == "" and m.percent ~= nil then value = string.format("%d%%", percent) end

    local nodes = {
        ui.row({ align = "center" }, {
            ui.label({ text = tostring(m.label or ""), fontSize = 12, color = "on_surface_variant" }),
        }),
        ui.row({ gap = 8, align = "center" }, {
            ui.label({ text = value, fontSize = 14, color = "on_surface" }),
        }),
    }
    if m.percent ~= nil then
        nodes[#nodes + 1] = ui.progress({
            progress = ratio(percent), fill = fill,
            track = "on_surface/0.10", radius = 2, height = 5,
        })
    end
    local sub = {}
    local left = countdown(m.reset_at)
    if left ~= "" then sub[#sub + 1] = "resets " .. left end
    local detail = noctalia.string.trim(tostring(m.detail or ""))
    if detail ~= "" then sub[#sub + 1] = detail end
    if #sub > 0 then
        nodes[#nodes + 1] = ui.label({ text = table.concat(sub, " · "), fontSize = 11, color = "on_surface_variant" })
    end
    return ui.column({ gap = 4 }, nodes)
end

local function entryBlock(entry)
    local name = tostring(entry.display_name or entry.id or "")
    local head = {
        ui.glyph({ name = GLYPHS[baseProvider(entry.id)] or "brain", size = 16, color = "primary" }),
        ui.label({ text = name, fontSize = 14, color = "on_surface" }),
    }
    local nodes = { ui.row({ gap = 8, align = "center" }, head) }

    if entry.status == "error" then
        nodes[#nodes + 1] = ui.label({
            text = tostring(entry.error or "error"), fontSize = 12, color = "error",
        })
    else
        local metrics = type(entry.metrics) == "table" and entry.metrics or {}
        if #metrics == 0 then
            nodes[#nodes + 1] = ui.label({ text = "no readings", fontSize = 12, color = "on_surface_variant" })
        end
        for _, m in ipairs(metrics) do
            if type(m) == "table" then nodes[#nodes + 1] = metricBlock(m) end
        end
    end
    return ui.column({ gap = 6 }, nodes)
end

function render()
    local blocks = {
        ui.row({ gap = 8, align = "center" }, {
            ui.glyph({ name = "brain", size = 18, color = "primary" }),
            ui.label({ text = "AI Usage", fontSize = 16, color = "on_surface" }),
        }),
    }

    local list = type(report) == "table" and type(report.entries) == "table" and report.entries or {}
    if #list == 0 then
        blocks[#blocks + 1] = ui.label({ text = "Waiting for ai-usagebar…", fontSize = 13, color = "on_surface_variant" })
    end
    for _, entry in ipairs(list) do
        if type(entry) == "table" then blocks[#blocks + 1] = entryBlock(entry) end
    end

    blocks[#blocks + 1] = ui.label({ text = "press r to refresh", fontSize = 11, color = "on_surface_variant" })

    panel.render(ui.column({ gap = 12, paddingH = 14, paddingV = 12, flexGrow = 1, align = "stretch" }, blocks))
end

noctalia.state.watch("report", function(value)
    if type(value) == "table" then
        report = value
        render()
    end
end)

function onOpen(_context)
    report = noctalia.state.get("report")
    panel.setWantsSecondTicks(true)
    render()
end

function onClose()
    panel.setWantsSecondTicks(false)
end

function onKey(chord, pressed)
    if not pressed then return end
    local lower = tostring(chord or ""):lower()
    if lower == "escape" then
        if type(panel.close) == "function" then panel.close() end
    elseif lower == "r" then
        noctalia.state.set("command", { action = "refresh", at = noctalia.nowMs() })
    end
end

-- Panel second tick, for the countdowns.
function update()
    render()
end

render()
