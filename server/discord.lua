
local function _resolveWebhook(routeOrUrl)
    if type(routeOrUrl) == "string" and routeOrUrl:find("^https?://") then
        return routeOrUrl
    end

    local key = tostring(routeOrUrl or "default")
    local convarName = "mredeem:webhook_" .. key
    local cv = (GetConvar and GetConvar(convarName, "")) or ""
    if cv and cv ~= "" then
        return cv
    end

    if Config and Config.Webhooks and routeOrUrl and Config.Webhooks[routeOrUrl] then
        return Config.Webhooks[routeOrUrl]
    end
    if Config and Config.Webhooks and Config.Webhooks.default then
        return Config.Webhooks.default
    end

    if webhookUrl and webhookUrl ~= "" then
        return webhookUrl
    end

    return nil
end

local function _dbg(msg)
    if type(DebugPrint) == "function" then
        return DebugPrint(msg)
    elseif type(Debugprint) == "function" then
        return Debugprint(msg)
    else
        print(msg)
    end
end

function SendToDiscord(title, message, color, extraFields, routeOrUrl)
    local routeKey = routeOrUrl or (extraFields and extraFields.__webhook) or "default"
    local url = _resolveWebhook(routeKey)
    if not url or url == "" then
        return _dbg("^1[Discord Webhook] No webhook URL defined for route: " .. tostring(routeKey) .. ".^7")
    end

    local embed = {{
        ["title"]       = title,
        ["description"] = message,
        ["color"]       = color or 16777215,
        ["footer"]      = { ["text"] = "Midnight Redeem System" },
        ["timestamp"]   = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time())
    }}

    if extraFields and type(extraFields) == "table" then
        for k, v in pairs(extraFields) do
            if k ~= "__webhook" and k ~= "__webhook_url" then
                embed[1][k] = v
            end
        end
    end

    PerformHttpRequest(url, function(err, text, headers)
        if err ~= 204 then
            _dbg(string.format("^1[Discord Webhook] Failed to send message. HTTP %s | Response: %s^7", tostring(err), tostring(text)))
        end
    end, 'POST', json.encode({ embeds = embed }), { ['Content-Type'] = 'application/json' })
end

function SendToDiscordDaily(title, message, color, extraFields)
    return SendToDiscord(title, message, color, extraFields, "daily")
end