local webhookUrl = ''

function SendToDiscord(title, message, color, extraFields)
    if not webhookUrl or webhookUrl == "" then
        return DebugPrint("^1[Discord Webhook] No webhook URL defined.^7")
    end
    local embed = {{
        ["title"] = title,
        ["description"] = message,
        ["color"] = color or 16777215,
        ["footer"] = { ["text"] = "Midnight Redeem System" },
        ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time())
    }}
    if extraFields and type(extraFields) == "table" then
        for k, v in pairs(extraFields) do
            embed[1][k] = v
        end
    end
    PerformHttpRequest(webhookUrl, function(err, text, headers)
        if err ~= 204 then
            DebugPrint(string.format("^1[Discord Webhook] Failed to send message. HTTP %s | Response: %s^7", tostring(err), tostring(text)))
        end
    end, 'POST', json.encode({ embeds = embed }), { ['Content-Type'] = 'application/json' })
end

function Checkadmin(src)
    if not Bridge.Framework.GetIsFrameworkAdmin(src) then return false, Bridge.Notify.SendNotify(src, locales("NOTIFY_PERMISSION_DENIED"), "error", 6000) end
    return true
end