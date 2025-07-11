local Config = require('config')
local Bridge = exports['community_bridge']:Bridge()

local webhookUrl = ''

function DebugPrint(message)
    if Config.Debug then
        print("[Midnight_Redeem] " .. message)
    end
end

function SendToDiscord(title, message, color, extraFields)
    if not webhookUrl or webhookUrl == "" then
        return DebugPrint("^1[Discord Webhook] No webhook URL defined.^7")
    end

    local embed = {
        {
            ["title"] = title,
            ["description"] = message,
            ["color"] = color or 16777215,
            ["footer"] = { ["text"] = "Midnight Redeem System" },
            ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time())
        }
    }

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

RegisterServerEvent("midnight-redeem:generateCode", function(itemsJson, uses, expiryDays, customCode)
    local src = source
    if not Bridge.Framework.GetIsFrameworkAdmin(src) then
        return Bridge.Notify.SendNotify(src, "You do not have permission to use this command.", "error", 6000)
    end

    local playerName = GetPlayerName(src)
    local identifiers = GetPlayerIdentifiers(src)

    local cfxId = identifiers[1] or "N/A"
    local discordId = "N/A"
    local steamId = "N/A"

    for _, id in ipairs(identifiers) do
        if string.find(id, "discord:") then
            discordId = id:gsub("discord:", "")
        elseif string.find(id, "steam:") then
            steamId = id
        end
    end

    local success, itemsTable = pcall(json.decode, itemsJson)
    if not success then
        return Bridge.Notify.SendNotify(src, "Invalid item data JSON.", "error", 6000)
    end

    if type(itemsTable) ~= "table" then
        return Bridge.Notify.SendNotify(src, "Invalid item data format.", "error", 6000)
    end

    uses = tonumber(uses)
    expiryDays = tonumber(expiryDays)

    if not uses or uses <= 0 then
        return Bridge.Notify.SendNotify(src, "Invalid uses number.", "error", 6000)
    end

    if not expiryDays or expiryDays < 0 then
        expiryDays = 0
    end

    local expiryDate = expiryDays > 0 and os.date("%Y-%m-%d %H:%M:%S", os.time() + (expiryDays * 86400)) or nil

    local function isArray(t)
        if type(t) ~= "table" then return false end
        local count = 0
        for k,_ in pairs(t) do
            if type(k) ~= "number" then return false end
            count = count + 1
        end
        return count > 0
    end

    local rewards = isArray(itemsTable) and itemsTable or { itemsTable }

    local totalItemCount = 0
    for _, reward in ipairs(rewards) do
        if reward.item then
            totalItemCount = totalItemCount + (tonumber(reward.amount) or 0)
        end
    end

    exports.oxmysql:execute(
        'INSERT INTO redeem_codes (code, total_item_count, items, uses, created_by, expiry, redeemed_by) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { customCode, totalItemCount, itemsJson, uses, playerName, expiryDate, json.encode({}) },
        function(rowsChanged)
            local affected = 0
            if type(rowsChanged) == "table" then
                affected = rowsChanged.affectedRows or #rowsChanged
            elseif type(rowsChanged) == "number" then
                affected = rowsChanged
            end

            if affected > 0 then
                Bridge.Notify.SendNotify(src, "Redeem code created successfully!", "success", 6000)
                local rewardLines = {}
                for _, reward in ipairs(rewards) do
                    if reward.item then
                        table.insert(rewardLines, string.format("• %dx %s", reward.amount or 1, reward.item))
                    elseif reward.money then
                        table.insert(rewardLines, string.format("• $%s %s", reward.amount or 0, reward.option or "cash"))
                    end
                end

                local rewardText = table.concat(rewardLines, "\n")
                local message = string.format(
                    "**admin player name:** `%s`\n**Code:** `%s`\n**Uses:** `%s`\n**Expiry:** `%s`\n\n**Rewards:**\n`%s`\n\n**Identifiers:**\n- CFX: `%s`\n- Discord: `%s`\n- Steam: `%s`",
                    playerName,
                    customCode,
                    uses,
                    expiryDate or "Never",
                    rewardText,
                    cfxId,
                    discordId,
                    steamId
                )

                SendToDiscord("Redeem Code Created", message, 3066993)
            else
                Bridge.Notify.SendNotify(src, "Failed to insert into DB.", "error", 6000)
            end
        end
    )
end)

RegisterServerEvent("midnight-redeem:redeemCode", function(code, option)
    local src = source
    local playerName = GetPlayerName(src)
    local identifiers = GetPlayerIdentifiers(src)
    local playerId = identifiers[1]

    exports.oxmysql:execute('SELECT * FROM redeem_codes WHERE code = ? AND (expiry IS NULL OR expiry > NOW())', {
        code
    }, function(result)
        if result[1] then
            local redeemData = result[1]
            local items = json.decode(redeemData.items)
            local remainingUses = redeemData.uses
            local redeemedBy = json.decode(redeemData.redeemed_by) or {}

            if redeemedBy[playerId] then
                return Bridge.Notify.SendNotify(src, "You have already redeemed this code!", "error", 6000)
            end

            if remainingUses <= 0 then
                return Bridge.Notify.SendNotify(src, "This code has already been used the maximum number of times!", "error", 6000)
            end

            local receivedSummary = {}
            local moneyReward = 0
            local accountType = option or "cash"

            for _, reward in ipairs(items) do
                if reward.item then
                    Bridge.Inventory.AddItem(src, reward.item, reward.amount)
                    table.insert(receivedSummary, ("• %dx %s"):format(reward.amount or 1, reward.item))
                elseif reward.money then
                    local account = reward.option or option or "cash"
                    Bridge.Framework.AddAccountBalance(src, account, reward.amount)
                    moneyReward = moneyReward + (tonumber(reward.amount) or 0)
                    accountType = account
                    table.insert(receivedSummary, ("• $%s (%s)"):format(reward.amount or 0, account))
                end
            end

            local notifyMsg = "sucessfull You have received:\n" .. table.concat(receivedSummary, "\n")
            TriggerClientEvent("midnight-redeem:notifyUser", src, "Code Redeemed", notifyMsg, "success")

            redeemedBy[playerId] = true
            exports.oxmysql:execute('UPDATE redeem_codes SET uses = ?, redeemed_by = ? WHERE code = ?', {
                remainingUses - 1,
                json.encode(redeemedBy),
                code
            })

            local cfxId = identifiers[1]
            local discordId = identifiers[2] and identifiers[2]:match("%d+") or 'N/A'
            local steamId = identifiers[3] or 'N/A'

            local itemSummary = ""
            for _, item in ipairs(items) do
                local label = item.item or (item.option or "cash")
                itemSummary = itemSummary .. "- **" .. label .. "** x" .. item.amount .. "\n"
            end

            local message = string.format(
                "**Redeemed By:** %s\n**Code:** `%s`\n\n**Rewards:**\n%s\n**Identifiers:**\nCFX: %s\nDiscord: %s\nSteam: %s",
                playerName, code, itemSummary, cfxId, discordId, steamId
            )

            SendToDiscord("Code Redeemed", message, 15844367)
        else
            Bridge.Notify.SendNotify(src, "Invalid or expired code!", "error", 6000)
        end
    end)
end)