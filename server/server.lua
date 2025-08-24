local Bridge = exports['community_bridge']:Bridge()

function CheckExpiredUnusedCodes()
    local now = os.date("%Y-%m-%d %H:%M:%S")
    local results = MySQL.query.await('SELECT * FROM midnight_codes WHERE expiry IS NOT NULL AND expiry <= ? AND uses > 0 AND expired_notified = 0', { now })
    if not results or #results == 0 then return end
    for _, row in ipairs(results) do
        local items = (pcall(json.decode, row.items or "[]")) and json.decode(row.items or "[]") or {}
        local rewardLines = {}
        for _, reward in ipairs(items) do
            if reward.item then
                table.insert(rewardLines, ("• %dx %s"):format(reward.amount or 1, reward.item))
            elseif reward.money then
                table.insert(rewardLines, ("• $%s (%s)"):format(reward.amount or 0, reward.option or "cash"))
            elseif reward.vehicle then
                table.insert(rewardLines, ("• Vehicle: %s"):format(reward.model or "Unknown"))
            end
        end
        local rewardText = next(rewardLines) and table.concat(rewardLines, "\n") or "None"
        local expiryDisplay = row.expiry
        if tonumber(expiryDisplay) then
            expiryDisplay = math.floor(tonumber(expiryDisplay) / 1000)
            expiryDisplay = os.date("%Y-%m-%d %H:%M:%S", expiryDisplay)
        end
        local msg = ("**Code:** `%s`\n**Expired:** `%s`\n**Uses Left:** `%s`\n\n**Rewards:**\n%s\n\n*This code expired without being fully used!*"):format(row.code, expiryDisplay or "N/A", row.uses, rewardText)
        SendToDiscord("Code Expired & Unused", msg, 15158332)
        exports.oxmysql:execute('UPDATE midnight_codes SET expired_notified = 1 WHERE code = ?', { row.code })
    end
end

RegisterServerEvent("midnight-redeem:deleteCode", function(code)
    local src = source
    if not Bridge.Framework.GetIsFrameworkAdmin(src) then return Bridge.Notify.SendNotify(src, locales("NOTIFY_PERMISSION_DENIED_DELETE"), "error", 6000) end

    exports.oxmysql:execute('DELETE FROM midnight_codes WHERE code = ?', { code }, function(affected)
        if affected and ((type(affected) == "number" and affected > 0) or (type(affected) == "table" and affected.affectedRows and affected.affectedRows > 0)) then
            Bridge.Notify.SendNotify(src, locales("NOTIFY_CODE_DELETED", code), "success", 6000)
            SendToDiscord("Code Deleted", string.format("**Code:** `%s`\n**admin** `%s`.", code, GetPlayerName(src)), 15158332)
        else
            Bridge.Notify.SendNotify(src, locales("NOTIFY_CODE_NOT_FOUND", code), "error", 6000)
        end
    end)
end)

function HandleRedeemCode(source, itemsJson, uses, expiryDays, customCode)
    local playerName = GetPlayerName(source) or "discord admin"
    local success, itemsTable = pcall(json.decode, itemsJson)
    if not success or type(itemsTable) ~= "table" then
        return Bridge.Notify.SendNotify(source, locales("NOTIFY_INVALID_ITEM_DATA"), "error", 6000)
    end
    uses = tonumber(uses)
    expiryDays = tonumber(expiryDays)
    if not uses or uses <= 0 then return Bridge.Notify.SendNotify(source, locales("NOTIFY_INVALID_USES"), "error", 6000) end
    if not expiryDays or expiryDays < 0 then expiryDays = 0 end
    local expiryRaw = expiryDays > 0 and os.time() + (expiryDays * 86400) or nil
    local expiryDate = expiryDays > 0 and os.date("%Y-%m-%d %H:%M:%S", os.time() + (expiryDays * 86400)) or nil
    local rewards = (type(itemsTable[1]) == "table") and itemsTable or { itemsTable }
    local totalItemCount = 0
    for _, reward in ipairs(rewards) do
        if reward.item then totalItemCount = totalItemCount + (tonumber(reward.amount) or 0) end
    end

    local insertId = MySQL.insert.await(
        'INSERT INTO midnight_codes (code, total_item_count, items, uses, created_by, expiry, redeemed_by) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { customCode, totalItemCount, itemsJson, uses, playerName, expiryDate, json.encode({}) }
    )

    if insertId then
        TriggerClientEvent("midnight-redeem:notifyUser", source, locales("NOTIFY_CODE_CREATED"), locales("NOTIFY_CODE_CREATED"), "success")
        local rewardLines = {}
        for _, reward in ipairs(rewards) do
            if reward.item then table.insert(rewardLines, string.format("• %dx %s", reward.amount or 1, reward.item))
            elseif reward.money then table.insert(rewardLines, string.format("• $%s (%s)", reward.amount or 0, reward.option or "cash"))
            elseif reward.vehicle then table.insert(rewardLines, string.format("• Vehicle: %s", reward.model or "Unknown")) end
        end
        local rewardText = table.concat(rewardLines, "\n")
        local message = string.format("**Admin:** `%s`\n**Code:** `%s`\n**Uses:** `%s`\n**Expiry:** <t:%s:R>\n\n**Rewards:**\n%s", playerName, customCode, uses, expiryRaw or "Never", rewardText)
        SendToDiscord("Redeem Code Created", message, 3066993)
    else
        Bridge.Notify.SendNotify(source, locales("NOTIFY_FAILED_INSERT"), "error", 6000)
    end
end

RegisterServerEvent("midnight-redeem:generateCode", function(itemsJson, uses, expiryDays, customCode)
    HandleRedeemCode(source, itemsJson, uses, expiryDays, customCode)
end)

local function addVehicleToGarage(model, playerName, uniqueId)
    local currentFramework = GetFrameworkVersion()
    if model then
        local plate = string.upper(string.sub(playerName, 1, 3)) .. math.random(1000, 9999)
        local props = { model = model, plate = plate }
        local state, garage = 1, "pillbox"
        if currentFramework == "es_extended" then
            exports.oxmysql:execute('INSERT INTO `owned_vehicles` (owner, plate, vehicle, stored) VALUES (?, ?, ?, ?)', {
                uniqueId, plate, json.encode(props), state
            })
        elseif currentFramework == "qb-core" then
            exports.oxmysql:execute('INSERT INTO `player_vehicles` (license, citizenid, vehicle, hash, mods, plate, state, garage) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
                uniqueId, uniqueId, model, GetHashKey(model), json.encode(props), plate, state, garage
            })
        end
        return plate
    end
end


local function handleCodeRedemption(src, code, option)
    local uniqueId = Bridge.Framework.GetPlayerIdentifier(src)
    local playerName = GetPlayerName(src)
    exports.oxmysql:execute('SELECT * FROM midnight_codes WHERE code = ? AND (expiry IS NULL OR expiry > NOW())', { code }, function(result)
        if not result[1] then
            return Bridge.Notify.SendNotify(src, locales("NOTIFY_INVALID_OR_EXPIRED"), "error", 6000)
        end
        local redeemData = result[1]
        local items = json.decode(redeemData.items)
        local remainingUses = redeemData.uses
        local redeemedBy = json.decode(redeemData.redeemed_by) or {}
        if redeemedBy[uniqueId] then
            return Bridge.Notify.SendNotify(src, locales("NOTIFY_ALREADY_REDEEMED"), "error", 6000)
        end
        if remainingUses <= 0 then
            return Bridge.Notify.SendNotify(src, locales("NOTIFY_MAX_USED"), "error", 6000)
        end

        local receivedSummary = {}
        for _, reward in ipairs(items) do
            if reward.item then
                Bridge.Inventory.AddItem(src, reward.item, reward.amount)
                table.insert(receivedSummary, ("• %dx %s"):format(reward.amount or 1, reward.item))
            elseif reward.money then
                local account = reward.option or option or "cash"
                Bridge.Framework.AddAccountBalance(src, account, reward.amount)
                table.insert(receivedSummary, ("• $%s (%s)"):format(reward.amount or 0, account))
            elseif reward.vehicle then
                local plate = addVehicleToGarage(reward.model, playerName, uniqueId)
                table.insert(receivedSummary, ("• Vehicle: %s (Plate: %s)"):format(reward.model, plate))
            end
        end

        redeemedBy[uniqueId] = true
        exports.oxmysql:execute('UPDATE midnight_codes SET uses = ?, redeemed_by = ? WHERE code = ?', { remainingUses - 1, json.encode(redeemedBy), code })

        local notifyMsg = locales("NOTIFY_SUCCESSFUL_RECEIVE", table.concat(receivedSummary, "\n"))
        TriggerClientEvent("midnight-redeem:notifyUser", src, locales("NOTIFY_CODE_REDEEMED"), notifyMsg, "success")

        local safePlayerName = playerName or "N/A"
        local safeCode = code or "N/A"
        local safeSummary = receivedSummary and table.concat(receivedSummary, "\n") or "N/A"
        local safeUniqueId = uniqueId or "N/A"

        local message = ("**Redeemed By:** `%s`\n**Code:** `%s`\n**Rewards:**\n%s\n**Identifiers:**\n- UniqueID: `%s`")
            :format(safePlayerName, safeCode, safeSummary, safeUniqueId)
        SendToDiscord("Code Redeemed", message, 15844367)
    end)
end

RegisterServerEvent("midnight-redeem:redeemCode", function(code, option)
    handleCodeRedemption(source, code, option)
end)

exports('GenerateRedeemCode', function(source, itemsJson, uses, expiryDays, customCode)
    HandleRedeemCode(source, itemsJson, uses, expiryDays, customCode)
end)

RegisterServerEvent("zdiscord:generateRedeemCode", function(itemsJson, uses, expiryDays, customCode)
    uses = tonumber(uses)
    expiryDays = tonumber(expiryDays)
    if itemsJson and uses and expiryDays and customCode then
        exports["midnight_redeem"]:GenerateRedeemCode(source, itemsJson, uses, expiryDays, customCode)
        print(("Generated redeem code with rewards %s, uses %s, expiry %s, code %s"):format(itemsJson, uses, expiryDays, customCode))
    else
        print("[zdiscord] Invalid arguments for GenerateRedeemCode.")
    end
end)

lib.callback.register("midnight-redeem:getAllCodes", function(src)
    local src = source
    local results = exports.oxmysql:executeSync("SELECT code FROM midnight_codes")
    local options = {}
    for _, row in ipairs(results or {}) do
        table.insert(options, { label = row.code, value = row.code })
    end
    return options
end)

RegisterServerEvent("midnight-redeem:adminCheckCode", function(code)
    local src = source
    exports.oxmysql:execute('SELECT * FROM midnight_codes WHERE code = ?', { code }, function(result)
        if result[1] then
            local row = result[1]
            local items = json.decode(row.items or "[]")
            local rewardList = {}
            for _, reward in ipairs(items) do
                if reward.item then
                    table.insert(rewardList, string.format("• %dx %s", reward.amount or 1, reward.item))
                elseif reward.money then
                    table.insert(rewardList, string.format("• $%s (%s)", reward.amount or 0, reward.option or "cash"))
                elseif reward.vehicle then
                    table.insert(rewardList, string.format("• Vehicle: %s", reward.model or "Unknown"))
                end
            end

            local daysLeft = "Never"
            if row.expiry then
                local expiryTime
                if type(row.expiry) == "number" then
                    expiryTime = math.floor(row.expiry / 1000)
                elseif type(row.expiry) == "string" and #row.expiry >= 10 then
                    expiryTime = os.time({
                        year = tonumber(row.expiry:sub(1,4)),
                        month = tonumber(row.expiry:sub(6,7)),
                        day = tonumber(row.expiry:sub(9,10)),
                        hour = tonumber(row.expiry:sub(12,13)) or 0,
                        min = tonumber(row.expiry:sub(15,16)) or 0,
                        sec = tonumber(row.expiry:sub(18,19)) or 0
                    })
                end
                if expiryTime then
                    local now = os.time()
                    local diff = math.floor((expiryTime - now) / 86400)
                    daysLeft = diff >= 0 and tostring(diff) or "Expired"
                end
            end

            local info = ("Code: %s\nUses Left: %s\nDays Left: %s\nRewards:\n%s"):format(
                row.code, row.uses, daysLeft, table.concat(rewardList, "\n")
            )
            Bridge.Notify.SendNotify(src, info, locales("NOTIFY_INFO"), 15000)
        else
            Bridge.Notify.SendNotify(src, locales("NOTIFY_NO_CODE_FOUND"), "error", 6000)
        end
    end)
end)

RegisterCommand(Config.AdminCommand, function(source)
    local src = source
    local isAdmin = Checkadmin(src)
    if not isAdmin then return end
    TriggerClientEvent("midnight-redeem:openAdminMenu", src)
end, false)

RegisterCommand(Config.RedeemCommand, function(source)
    local src = source
    TriggerClientEvent("midnight-redeem:redeemcode", src)
end, false)