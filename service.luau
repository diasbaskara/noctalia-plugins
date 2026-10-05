--!nonstrict
-- Headless poller: the single owner of `ai-usagebar usage --json`. One call
-- returns every configured vendor, so the capsules and the panel are subscribers
-- of noctalia.state and never spawn a process of their own.

-- `ai-usagebar` is a declared dependency, so it is expected on PATH.
local COMMAND = "ai-usagebar usage --json"

local function intervalMs()
    local minutes = tonumber(noctalia.getConfig("refresh_minutes")) or 2
    if minutes < 1 then minutes = 1 end
    return math.floor(minutes * 60 * 1000)
end

-- Errors can echo config fragments, so scrub anything shaped like a secret
-- before it reaches the screen or the log.
local function safeText(value)
    local text = noctalia.string.trim(tostring(value or ""))
    text = text:gsub("%s+", " ")
    if #text > 300 then text = string.sub(text, 1, 300) .. "..." end
    local lower = text:lower()
    if lower:find("key", 1, true) or lower:find("token", 1, true)
        or lower:find("secret", 1, true) or lower:find("password", 1, true) then
        text = text:gsub("([%w_%-]*[Kk][Ee][Yy][%w_%-]*%s*[:=]%s*)[^%s\"',}]+", "%1<redacted>")
        text = text:gsub("([%w_%-]*[Tt][Oo][Kk][Ee][Nn][%w_%-]*%s*[:=]%s*)[^%s\"',}]+", "%1<redacted>")
        text = text:gsub("([Bb][Ee][Aa][Rr][Ee][Rr]%s+)[^%s\"',}]+", "%1<redacted>")
    end
    return text
end

local function scrub(value, cache)
    cache = cache or {}
    if type(value) == "string" then
        if cache[value] == nil then cache[value] = safeText(value) end
        return cache[value]
    end
    if type(value) ~= "table" then return value end
    for key, inner in pairs(value) do
        local sensitive = false
        if type(key) == "string" then
            local lower = key:lower()
            sensitive = lower:find("authorization", 1, true) ~= nil
                or lower:find("api_key", 1, true) ~= nil
        end
        if sensitive then value[key] = "<redacted>" else value[key] = scrub(inner, cache) end
    end
    return value
end

local function failure(code, detail)
    return { code = code, detail = safeText(detail) }
end

local function classify(result)
    if result == nil then return failure("spawn_failed") end
    if result.timedOut then return failure("timed_out") end
    local stderr = tostring(result.stderr or "")
    if result.exitCode == 127 then
        return failure("not_installed", stderr)
    end
    if result.exitCode ~= 0 then
        return failure("failed", stderr:find("%S") and stderr
            or ("ai-usagebar exited with code " .. tostring(result.exitCode)))
    end
    return failure("no_data", stderr)
end

local inFlight = false
local pendingRefresh = false
local MIN_GAP_MS = 2000
local lastStart = 0

local function queueRefresh()
    pendingRefresh = true
    noctalia.state.set("refresh_queued", true)
    noctalia.setUpdateInterval(250)
end

local function refresh()
    if inFlight then
        queueRefresh()
        return
    end
    local now = noctalia.nowMs()
    if MIN_GAP_MS - (now - lastStart) > 0 then
        queueRefresh()
        return
    end
    lastStart = now
    pendingRefresh = false
    noctalia.setUpdateInterval(intervalMs())
    inFlight = true
    noctalia.state.set("refresh_queued", false)
    noctalia.state.set("polling", true)

    local started = noctalia.runAsync(COMMAND, function(result)
        inFlight = false
        noctalia.state.set("polling", false)

        local decoded = result ~= nil and not result.timedOut
            and noctalia.json.decode(result.stdout or "") or nil
        if type(decoded) == "table" and type(decoded.entries) == "table" then
            -- A failed vendor still comes back as an entry with
            -- `status = "error"`, so a non-zero exit is no reason to drop
            -- the report.
            noctalia.state.set("report", scrub(decoded))
            noctalia.state.set("error", failure(""))
        else
            noctalia.state.set("error", classify(result))
        end

        if pendingRefresh then refresh() end
    end, 30000)

    -- A refusal to spawn never calls back, and the poller would sit in flight
    -- forever.
    if not started then
        inFlight = false
        pendingRefresh = false
        noctalia.state.set("refresh_queued", false)
        noctalia.state.set("polling", false)
        noctalia.state.set("error", failure("spawn_failed"))
    end
end

noctalia.state.watch("command", function(value)
    if type(value) == "table" and value.action == "refresh" then refresh() end
end)

function update()
    -- A read in flight answers on its own callback; the tick only starts them.
    if inFlight then return end
    refresh()
end

function onConfigChanged()
    noctalia.setUpdateInterval(intervalMs())
    refresh()
end

function onIpc(event, _payload)
    if event == "refresh" then refresh() end
end

noctalia.setUpdateInterval(intervalMs())
refresh()
