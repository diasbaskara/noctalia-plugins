--!nonstrict
-- Bar capsule. Lists the configured providers side by side: one chip per
-- provider with its headline percentage. A provider that errored shows `!`;
-- a provider the report does not list is skipped.

local vendorsRaw = tostring(noctalia.getConfig("vendors") or "anthropic,cursor,supergrok,opencode-go")
local showGlyph = noctalia.getConfig("show_glyph") ~= false
local showReset = noctalia.getConfig("show_reset") ~= false

local vendors = {}
for part in vendorsRaw:gmatch("[^,%s]+") do
    part = noctalia.string.trim(part):lower()
    if part ~= "" then vendors[#vendors + 1] = part end
end
if #vendors == 0 then vendors = { "anthropic" } end

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
    grokbot = "brand-x",
}

-- Providers with real brand SVGs in icons/ (white for dark themes, dark for
-- light ones, like the tailscale logo pair). Anything else falls back to a
-- Tabler glyph.
local ICONS = {
    anthropic = true, openai = true, copilot = true, cursor = true,
    grok = true, supergrok = true, ["opencode-go"] = true,
    openrouter = true, deepseek = true, kimi = true,
    grokbot = true,
}

local ICON_EXT = { grokbot = "png", grok = "png", anthropic = "png" }
local ICON_FILE = { supergrok = "grok" }

local function providerMark(wanted, size, color)
    if ICONS[wanted] then
        return ui.image({
            path = "icons/" .. (ICON_FILE[wanted] or wanted) .. (noctalia.isDarkMode() and "" or "-light") .. "." .. (ICON_EXT[ICON_FILE[wanted] or wanted] or "svg"),
            width = size, height = size, fit = "contain",
        })
    end
    return ui.glyph({ name = GLYPHS[wanted] or "brain", size = size, color = color })
end

local report = nil
local failed = false
local failDetail = ""

local function baseProvider(id)
    return (tostring(id or ""):match("^[^@]+") or "")
end

local DISPLAY_NAMES = {
    ["opencode-go"] = "OpenCode",
    -- The subscription; [grok] (API prepaid dollars) is a separate billing
    -- product and stays disabled without a management key.
    ["supergrok"] = "Grok",
}

local function displayName(entry)
    local id = baseProvider(entry.id)
    if DISPLAY_NAMES[id] ~= nil then return DISPLAY_NAMES[id] end
    return tostring(entry.display_name or entry.id)
end

local function findEntry(wanted)
    if type(report) ~= "table" or type(report.entries) ~= "table" then return nil end
    for _, entry in ipairs(report.entries) do
        if type(entry) == "table" and baseProvider(entry.id) == wanted then
            return entry
        end
    end
    return nil
end

local function headline(entry)
    local metrics = type(entry.metrics) == "table" and entry.metrics or {}
    for _, m in ipairs(metrics) do
        if type(m) == "table" then return m end
    end
    return nil
end

-- "2026-10-05T10:09:59Z" -> countdown text. UTC stamps vs local os.time.
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

-- "2026-10-05T10:09:59Z" -> epoch seconds. Duplicated from the panel on
-- purpose: the entries are separate runtimes, so a shared module would only
-- add a file to keep in sync.
local function epochOf(resetAt)
    if type(resetAt) ~= "string" then return nil end
    local y, mo, d, h, mi, s = resetAt:match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
    if y == nil then return nil end
    local asLocal = os.time({
        year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = tonumber(s),
    })
    local utc = os.date("!*t", asLocal)
    utc.isdst = nil
    return asLocal + (asLocal - os.time(utc))
end

-- Soonest reset among the entry's windows; nil when nothing resets.
local function resetKey(entry)
    if entry == nil or entry.status == "error" then return nil end
    local best
    local metrics = type(entry.metrics) == "table" and entry.metrics or {}
    for _, m in ipairs(metrics) do
        local at = epochOf(m.reset_at)
        if at ~= nil and (best == nil or at < best) then best = at end
    end
    return best
end

local function chip(entry, wanted, isVert)
    local nodes = {}
    local color = "on_surface"
    local text = "—"

    if entry == nil then
        text = "…"
        color = "on_surface_variant"
    elseif entry.status == "error" then
        text = "!"
        color = "error"
    else
        local m = headline(entry)
        if m ~= nil then
            local pct = tonumber(m.percent)
            text = pct ~= nil and string.format("%d%%", pct) or tostring(m.value or "")
            if pct ~= nil then
                if pct >= 90 then
                    color = "error"
                elseif pct >= 70 then
                    color = "tertiary"
                end
            end
        end
    end

    if showGlyph then
        nodes[#nodes + 1] = providerMark(wanted, 14, color)
    end
    nodes[#nodes + 1] = ui.label({ text = text, fontSize = 11, fontWeight = "semibold", color = color, maxLines = 1 })

    if showReset and entry ~= nil and entry.status ~= "error" then
        local m = headline(entry)
        local left = m ~= nil and countdown(m.reset_at) or ""
        if left ~= "" then
            nodes[#nodes + 1] = ui.label({ text = left, fontSize = 10, color = "on_surface_variant", maxLines = 1 })
        end
    end

    if isVert then
        return ui.column({ gap = 2, align = "center" }, nodes)
    end
    return ui.row({ gap = 5, align = "center" }, nodes)
end

local function tooltip()
    if failed then
        return { { key = "AI Usage", value = failDetail ~= "" and failDetail or "fetch failed" } }
    end
    local rows = {}
    for _, wanted in ipairs(vendors) do
        local entry = findEntry(wanted)
        if entry == nil then
            rows[#rows + 1] = { key = wanted, value = "not in report" }
        elseif entry.status == "error" then
            rows[#rows + 1] = { key = displayName(entry), value = tostring(entry.error or "error") }
        else
            local m = headline(entry)
            if m ~= nil then
                local left = countdown(m.reset_at)
                rows[#rows + 1] = {
                    key = displayName(entry),
                    value = tostring(m.label or "") .. ": " .. tostring(m.value or "")
                        .. (left ~= "" and " (resets " .. left .. ")" or ""),
                }
            end
        end
    end
    if #rows == 0 then
        rows[1] = { key = "AI Usage", value = "waiting for ai-usagebar…" }
    end
    return rows
end

local function orderedVendors()
    -- Soonest reset first on the left; providers with no reset (or an error)
    -- keep their configured order after the sorted ones.
    local list = {}
    for index, wanted in ipairs(vendors) do
        local entry = findEntry(wanted)
        list[#list + 1] = { wanted = wanted, entry = entry, index = index }
    end
    table.sort(list, function(a, b)
        local ka, kb = resetKey(a.entry), resetKey(b.entry)
        if ka ~= nil and kb ~= nil then
            if ka ~= kb then return ka < kb end
            return a.index < b.index
        end
        if ka ~= nil then return true end
        if kb ~= nil then return false end
        return a.index < b.index
    end)
    return list
end

local function render()
    local isVert = type(barWidget.isVertical) == "function" and barWidget.isVertical() or false
    local children = {}
    for _, item in ipairs(orderedVendors()) do
        local entry = item.entry
        if entry ~= nil then
            if #children > 0 then
                children[#children + 1] = isVert
                    and ui.box({ width = 12, height = 1, fill = "on_surface_variant", opacity = 0.3 })
                    or ui.label({ text = "·", fontSize = 11, color = "on_surface_variant" })
            end
            children[#children + 1] = chip(entry, item.wanted, isVert)
        end
    end
    if #children == 0 then
        children[1] = ui.glyph({
            name = "brain", size = 14,
            color = failed and "error" or "on_surface_variant",
        })
    end
    if isVert then
        barWidget.render(ui.column({ gap = 5, align = "center" }, children))
    else
        barWidget.render(ui.row({ gap = 7, align = "center" }, children))
    end
    barWidget.setTooltip(tooltip())
end

noctalia.state.watch("report", function(value)
    if type(value) == "table" then
        report = value
        failed = false
        failDetail = ""
        render()
    end
end)

noctalia.state.watch("error", function(value)
    if type(value) == "table" and tostring(value.code or "") ~= "" then
        failed = true
        failDetail = tostring(value.detail or value.code)
    else
        failed = false
        failDetail = ""
    end
    render()
end)

function onClick()
    for _, wanted in ipairs(vendors) do
        local entry = findEntry(wanted)
        if entry ~= nil then
            noctalia.state.set("selected", entry.id)
            break
        end
    end
    noctalia.togglePanel("diasbaskara/ai-usage:panel")
end

report = noctalia.state.get("report")
local errState = noctalia.state.get("error")
if type(errState) == "table" and tostring(errState.code or "") ~= "" then
    failed = true
    failDetail = tostring(errState.detail or errState.code)
end

-- Live countdowns without waking the CLI.
noctalia.setUpdateInterval(30000)
render()

function update()
    render()
end
