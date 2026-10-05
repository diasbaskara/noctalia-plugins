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
    grokbot = "brand-x",
}

-- Where to send the user for keys / sign-in, mirroring the community plugin.
local DASHBOARDS = {
    anthropic = "https://claude.ai/settings/usage",
    openai = "https://chatgpt.com/codex/settings/usage",
    copilot = "https://github.com/settings/copilot",
    cursor = "https://www.cursor.com/settings",
    grok = "https://console.x.ai/",
    supergrok = "https://grok.com/",
    ["opencode-go"] = "https://opencode.ai/console/",
    zai = "https://z.ai",
    openrouter = "https://openrouter.ai/activity",
    deepseek = "https://platform.deepseek.com/",
    kimi = "https://platform.moonshot.cn/",
}

local ICONS = {
    anthropic = true, openai = true, copilot = true, cursor = true,
    grok = true, supergrok = true, ["opencode-go"] = true,
    openrouter = true, deepseek = true, kimi = true,
    grokbot = true,
}

local ICON_EXT = { grokbot = "png", grok = "png" }

local function providerMark(wanted, size, color)
    if ICONS[wanted] then
        return ui.image({
            path = "icons/" .. wanted .. (noctalia.isDarkMode() and "" or "-light") .. "." .. (ICON_EXT[wanted] or "svg"),
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

local DISPLAY_NAMES = {
    ["opencode-go"] = "OpenCode",
}

local function tabName(entry)
    local id = baseProvider(entry.id)
    if DISPLAY_NAMES[id] ~= nil then return DISPLAY_NAMES[id] end
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

local function parseEpoch(resetAt)
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

-- Across every provider: which window to spend from first. Soonest-renewing
-- usable window wins (spend it before it resets); otherwise the roomiest one.
local function globalTip(list)
    local best, bestAt, bestEntry = nil, nil, nil
    local usable = 0
    for _, entry in ipairs(list) do
        if type(entry) == "table" and entry.status ~= "error" then
            local metrics = type(entry.metrics) == "table" and entry.metrics or {}
            for _, m in ipairs(metrics) do
                if type(m) == "table" and (tonumber(m.percent) or 0) < 100 then
                    usable = usable + 1
                    local at = parseEpoch(m.reset_at)
                    if best == nil or (at ~= nil and (bestAt == nil or at < bestAt)) then
                        best, bestAt, bestEntry = m, at, entry
                    end
                end
            end
        end
    end
    if best == nil then
        if usable == 0 and #list > 0 then return "All quotas exhausted - usage resumes at the next reset." end
        return ""
    end
    local who = tabName(bestEntry)
    local what = tostring(best.label or "quota")
    if bestAt ~= nil then
        return "Use " .. who .. " " .. what .. " first - resets " .. countdown(best.reset_at) .. "."
    end
    return "Use " .. who .. " " .. what .. " first - most headroom."
end

local function tabNode(entry, active)
    local id = entry.id
    local failedTab = entry.status == "error"
    local children = {
        providerMark(baseProvider(entry.id), 14, active and "primary" or "on_surface"),
        ui.label({
            text = tabName(entry), fontSize = 12,
            fontWeight = active and "bold" or "medium",
            color = active and "primary" or "on_surface",
            maxLines = 1,
        }),
    }
    if failedTab then
        children[#children + 1] = ui.glyph({ name = "alert-circle", size = 12, color = "error" })
    end
    return ui.row({
        -- Stable identity: without it the host can leave a previous render's
        -- closures on the rows, so the highlight sticks to the old tab.
        key = "tab:" .. tostring(id),
        gap = 6, align = "center", paddingH = 12, paddingV = 6,
        minHeight = 32, radius = 8,
        fill = active and "primary/0.14" or "surface_variant/0.22",
        border = active and "primary/0.45" or "outline/0.08",
        borderWidth = 1,
        onClick = function()
            selected = id
            noctalia.state.set("selected", id)
            render()
        end,
    }, children)
end

local function tabRow(list)
    -- Wrap into rows of three: the manifest width is fixed, so tabs flow
    -- instead of overflowing it.
    local rows = {}
    local currentRow = {}
    local current = currentEntry()
    for _, entry in ipairs(list) do
        currentRow[#currentRow + 1] = tabNode(entry, current ~= nil and entry.id == current.id)
        if #currentRow >= 3 then
            rows[#rows + 1] = ui.row({ gap = 6, align = "center" }, currentRow)
            currentRow = {}
        end
    end
    if #currentRow > 0 then
        rows[#rows + 1] = ui.row({ gap = 6, align = "center" }, currentRow)
    end
    if #rows == 1 then return rows[1] end
    return ui.column({ gap = 6 }, rows)
end

local function openDashboard(url)
    if type(noctalia.runAsync) == "function" then
        noctalia.runAsync("xdg-open '" .. url .. "'")
    end
end

-- Runs a CLI login in a terminal, watches its output for the approval link
-- and opens that link in the browser automatically. No copy-paste.
local function autoBrowserLogin(cmd, stayTitle)
    local dir = nil
    if type(noctalia.pluginDataDir) == "function" then
        local d = noctalia.pluginDataDir()
        if type(d) == "string" and d ~= "" then dir = d end
    end
    local out = (dir or "/tmp") .. "/ai-usage-login.out"
    local path = (dir or "/tmp") .. "/ai-usage-login.sh"
    local body = table.concat({
        "#!/bin/sh",
        "OUT='" .. out .. "'",
        ": > \"$OUT\"",
        cmd .. ' >"$OUT" 2>&1 &',
        "PID=$!",
        'URL=""',
        "for i in $(seq 1 60); do",
        "  URL=$(grep -o 'https://[^ \"]*' \"$OUT\" | head -n 1)",
        '  if [ -n "$URL" ]; then break; fi',
        "  kill -0 $PID 2>/dev/null || break",
        "  sleep 0.5",
        "done",
        'if [ -n "$URL" ]; then',
        "  echo 'Opening browser for approval...'",
        '  xdg-open "$URL"',
        "else",
        "  echo 'No approval link appeared:'",
        '  cat "$OUT"',
        "fi",
        "wait $PID",
        "echo",
        "printf 'Press Enter to close... '",
        "read -r _",
        "",
    }, "\n")
    if type(noctalia.writeFile) == "function" then
        noctalia.writeFile(path, body)
    end
    if type(noctalia.runInTerminal) == "function" then
        noctalia.runInTerminal("sh '" .. path .. "'")
    else
        copyLoginCommand(cmd)
    end
end

local function terminalLogin(cmd)
    -- A script file, not a quoted one-liner: argument splitting on the way to
    -- the terminal used to swallow the command and leave an empty window.
    local dir = nil
    if type(noctalia.pluginDataDir) == "function" then
        local d = noctalia.pluginDataDir()
        if type(d) == "string" and d ~= "" then dir = d end
    end
    local path = (dir or "/tmp") .. "/ai-usage-login.sh"
    local body = table.concat({
        "#!/bin/sh",
        "echo 'AI Usage login'",
        "echo '1. Copy the link printed below'",
        "echo '2. Open it in your browser and approve'",
        "echo '3. Wait here for success, then press Enter'",
        "echo",
        cmd,
        "echo",
        "printf 'Press Enter to close... '",
        "read -r _",
        "",
    }, "\n")
    if type(noctalia.writeFile) == "function" then
        noctalia.writeFile(path, body)
    end
    if type(noctalia.runInTerminal) == "function" then
        noctalia.runInTerminal("sh '" .. path .. "'")
    else
        copyLoginCommand(cmd)
    end
end

local function copyLoginCommand(cmd)
    if type(noctalia.copyToClipboard) == "function" then
        noctalia.copyToClipboard(cmd, "text/plain")
    end
    if type(noctalia.notify) == "function" then
        noctalia.notify("Login command copied", "Paste it in your own terminal.")
    end
end

local KEY_ENV = {
    ["opencode-go"] = "OPENCODE_GO_API_KEY",
    grok = "XAI_MANAGEMENT_KEY",
    openrouter = "OPENROUTER_API_KEY",
    deepseek = "DEEPSEEK_API_KEY",
    zai = "ZAI_API_KEY",
    kimi = "KIMI_API_KEY",
}

-- Friendly copy for failed providers. Raw CLI errors never reach the screen.
local function friendlyError(entry)
    local base = baseProvider(entry.id)
    local message = tostring(entry.error or ""):lower()
    if base == "cursor" or message:find("401", 1, true) or message:find("403", 1, true)
        or message:find("expired", 1, true) or message:find("unauthorized", 1, true) then
        return "Sign-in required",
            "Your " .. tabName(entry) .. " session expired. Log in again below, then refresh."
    end
    if message:find("no credential file", 1, true) or base == "grokbot" then
        return "App sign-in needed",
            "Install the Grok Bot desktop app and sign in to it, then refresh."
    end
    if message:find("no api key", 1, true) then
        local env = KEY_ENV[base]
        local hint = env ~= nil
            and ("Set " .. env .. " or add api_key under [" .. base .. "] in ~/.config/ai-usagebar/config.toml.")
            or "Add its api_key in ~/.config/ai-usagebar/config.toml."
        return "API key needed", tabName(entry) .. " has no key yet. " .. hint
    end
    return "Temporarily unavailable",
        tabName(entry) .. " could not be read right now. It retries automatically."
end
local function errorActions(entry)
    local base = baseProvider(entry.id)
    local message = tostring(entry.error or ""):lower()
    local actions = {}
    if base == "cursor" then
        -- NO_OPEN_BROWSER prints the approval link in the terminal instead of
        -- trying (and failing) to pop a browser from the shell's environment.
        actions[#actions + 1] = ui.button({
            text = "Log in with Cursor", variant = "primary", controlSize = "sm",
            onClick = function() autoBrowserLogin("NO_OPEN_BROWSER=1 cursor-agent login") end,
        })
    elseif base == "supergrok" then
        actions[#actions + 1] = ui.button({
            text = "Log in with Grok", variant = "primary", controlSize = "sm",
            onClick = function() terminalLogin("grok login") end,
        })
    end
    if message:find("no api key", 1, true) or message:find("api_key", 1, true) then
        local dash = DASHBOARDS[base]
        if dash ~= nil then
            actions[#actions + 1] = ui.button({
                text = "Open dashboard for key", variant = "outline", controlSize = "sm",
                onClick = function() openDashboard(dash) end,
            })
        end
    elseif DASHBOARDS[base] ~= nil then
        actions[#actions + 1] = ui.button({
            text = "Open dashboard", variant = "ghost", controlSize = "sm",
            onClick = function() openDashboard(DASHBOARDS[base]) end,
        })
    end
    if #actions == 0 then return nil end
    return ui.row({ gap = 8, align = "center" }, actions)
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
        local tip = globalTip(list)
        if tip ~= "" then
            children[#children + 1] = ui.row({ gap = 6, align = "center" }, {
                ui.glyph({ name = "bulb", size = 12, color = "secondary" }),
                ui.label({ text = tip, fontSize = 11, color = "secondary", maxLines = 2 }),
            })
        end
        children[#children + 1] = tabRow(list)
        if current == nil then
            children[#children + 1] = ui.label({ text = "No provider selected.", color = "on_surface_variant" })
        else
            if current.status == "error" then
            local errTitle, errBody = friendlyError(current)
            children[#children + 1] = ui.row({ gap = 8, align = "center" }, {
                ui.glyph({ name = "alert-triangle", size = 16, color = "error" }),
                ui.label({ text = errTitle, fontSize = 14, fontWeight = "semibold", color = "on_surface", maxLines = 1 }),
            })
            children[#children + 1] = ui.label({ text = errBody, fontSize = 12, color = "on_surface_variant" })
            local actions = errorActions(current)
            if actions ~= nil then children[#children + 1] = actions end
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
