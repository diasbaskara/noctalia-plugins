--!nonstrict
-- Tabbed details panel: one tab per provider in the report, limit cards in
-- the shared usage-card style (hairline outline, pill value chips, clock
-- reset rows). `r` refreshes, arrows switch tabs, escape closes.

local WARNING = "#F5A623"
local CARD = { gap = 5, padding = 7, radius = 9, fill = "surface_variant/0.34", border = "outline/0.08", borderWidth = 1 }

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

local ICONS = {
    anthropic = true, openai = true, copilot = true, cursor = true,
    grok = true, supergrok = true, ["opencode-go"] = true,
    openrouter = true, deepseek = true, kimi = true,
}

local function providerMark(wanted, size, color)
    if ICONS[wanted] then
        return ui.image({
            path = "icons/" .. wanted .. (noctalia.isDarkMode() and ".svg" or "-light.svg"),
            width = size, height = size, fit = "contain",
        })
    end
    return ui.glyph({ name = GLYPHS[wanted] or "brain", size = size, color = color })
end

local report = nil
local selected = nil

local function baseProvider(id)
    return (tostring(id or ""):match("^[^@]+") or "")
end

local function tabName(entry)
    return tostring(entry.display_name or entry.short_name or entry.id or "?")
end

local function listEntries()
    if type(report) ~= "table" or type(report.entries) ~= "table" then return {} end
    local out = {}
    for _, entry in ipairs(report.entries) do
        if type(entry) == "table" then out[#out + 1] = entry end
    end
    return out
end

local function currentEntry()
    local list = listEntries()
    if #list == 0 then return nil end
    for _, entry in ipairs(list) do
        if entry.id == selected then return entry end
    end
    return list[1]
end

local function limitColor(fraction)
    if fraction >= 0.97 then return "error" end
    if fraction >= 0.70 then return WARNING end
    return "primary"
end

local function chip(text, color)
    return ui.row({ paddingH = 6, paddingV = 2, radius = 5, align = "center", justify = "center", fill = color .. "/0.10" }, {
        ui.label({ text = text, fontSize = 12, fontWeight = "bold", color = color, maxLines = 1 }),
    })
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
    local left = (asLocal + (asLocal - os.time(utc))) - os.time()
    if left <= 0 then return "now" end
    local mins = math.floor(left / 60)
    local days = math.floor(mins / 1440)
    local hours = math.floor((mins % 1440) / 60)
    local rest = mins % 60
    if days > 0 then return string.format("%dd %dh", days, hours) end
    if hours > 0 then return string.format("%dh %dm", hours, rest) end
    return string.format("%dm", rest)
end

local function metricCard(m)
    local percent = tonumber(m.percent) or 0
    local tint = limitColor(percent / 100)
    local value = tostring(m.value or "")
    if value == "" and m.percent ~= nil then value = string.format("%d%%", percent) end

    local children = {}
    children[#children + 1] = ui.row({ gap = 8, align = "center" }, {
        ui.label({ text = tostring(m.label or ""), fontSize = 13, fontWeight = "semibold", color = "on_surface", maxLines = 1 }),
        ui.spacer({ flexGrow = 1 }),
        chip(value, tint),
    })

    if m.percent ~= nil then
        children[#children + 1] = ui.progress({
            progress = math.min(1, math.max(0, percent / 100)),
            fill = tint, track = "on_surface/0.10", height = 5, radius = 2,
        })
    end

    local bottom = {}
    local left = countdown(m.reset_at)
    if left ~= "" then
        bottom[#bottom + 1] = ui.glyph({ name = "clock", size = 10, color = "on_surface_variant" })
        bottom[#bottom + 1] = ui.label({ text = "resets " .. left, fontSize = 11, color = "on_surface_variant", maxLines = 1 })
    end
    local detail = noctalia.string.trim(tostring(m.detail or ""))
    if detail ~= "" then
        bottom[#bottom + 1] = ui.spacer({ flexGrow = 1 })
        bottom[#bottom + 1] = ui.label({ text = detail, fontSize = 10, fontWeight = "medium", color = "secondary", maxLines = 1 })
    end
    if #bottom > 0 then
        children[#children + 1] = ui.row({ gap = 4, align = "center" }, bottom)
    end

    return ui.column({
        gap = CARD.gap, padding = CARD.padding, radius = CARD.radius,
        fill = CARD.fill, border = CARD.border, borderWidth = CARD.borderWidth,
    }, children)
end

local function tabRow(list)
    local tabs = {}
    for _, entry in ipairs(list) do
        local active = currentEntry() ~= nil and entry.id == currentEntry().id
        local id = entry.id
        tabs[#tabs + 1] = ui.button({
            text = tabName(entry),
            variant = active and "primary" or "ghost",
            controlSize = "sm",
            onClick = function()
                selected = id
                noctalia.state.set("selected", id)
                render()
            end,
        })
    end
    return ui.row({ gap = 6, align = "center" }, tabs)
end

function render()
    local list = listEntries()
    local current = currentEntry()

    local children = {}
    children[#children + 1] = ui.row({ align = "center", gap = 8, paddingH = 4, paddingV = 2 }, {
        ui.label({ text = "AI Usage", fontSize = 16, fontWeight = "bold", color = "on_surface", maxLines = 1 }),
        ui.spacer({ flexGrow = 1 }),
        ui.button({
            glyph = "refresh", variant = "ghost", controlSize = "sm",
            width = 24, height = 24, glyphSize = 13, tooltip = "Refresh now",
            onClick = function()
                noctalia.state.set("command", { action = "refresh", at = noctalia.nowMs() })
            end,
        }),
    })

    if #list == 0 then
        children[#children + 1] = ui.label({
            text = "Waiting for ai-usagebar…", fontSize = 13, color = "on_surface_variant",
        })
    else
        children[#children + 1] = tabRow(list)
        if current == nil then
            children[#children + 1] = ui.label({ text = "No provider selected.", color = "on_surface_variant" })
        else
            children[#children + 1] = ui.row({ gap = 8, align = "center" }, {
                providerMark(baseProvider(current.id), 18, "primary"),
                ui.label({ text = tabName(current), fontSize = 14, fontWeight = "semibold", color = "on_surface", maxLines = 1 }),
            })
            if current.status == "error" then
            children[#children + 1] = ui.label({
                text = tostring(current.error or "error"), fontSize = 12,
                fontWeight = "medium", color = "error",
            })
        else
            local metrics = type(current.metrics) == "table" and current.metrics or {}
            if #metrics == 0 then
                children[#children + 1] = ui.label({ text = "No readings.", color = "on_surface_variant" })
            end
            for _, m in ipairs(metrics) do
                if type(m) == "table" then children[#children + 1] = metricCard(m) end
            end
        end
    end

    panel.render(ui.column({ gap = 8, paddingH = 10, paddingV = 8, flexGrow = 1, align = "stretch" }, children))
end

noctalia.state.watch("report", function(value)
    if type(value) == "table" then
        report = value
        render()
    end
end)

function onOpen(_context)
    report = noctalia.state.get("report")
    local want = noctalia.state.get("selected")
    if want ~= nil then selected = want end
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
    elseif lower == "left" or lower == "right" or lower == "up" or lower == "down" then
        local list = listEntries()
        if #list > 1 and currentEntry() ~= nil then
            local idx = 1
            for i, entry in ipairs(list) do
                if entry.id == currentEntry().id then idx = i break end
            end
            local next = (lower == "left" or lower == "up")
                and ((idx - 2 + #list) % #list + 1)
                or ((idx % #list) + 1)
            selected = list[next].id
            noctalia.state.set("selected", selected)
            render()
        end
    end
end

-- Panel second tick, for the countdowns.
function update()
    render()
end

render()
